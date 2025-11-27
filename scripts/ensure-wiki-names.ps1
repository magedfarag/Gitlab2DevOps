param(
    # Personal Access Token with vso.wiki_write + vso.code_manage
    # vso.wiki_write is required to update wiki resources; vso.code_manage is required to rename Git repos.
    # Docs show these scopes for the Wiki Update and Git Repositories Update APIs.
    # https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/wikis/update
    # https://learn.microsoft.com/en-us/rest/api/azure/devops/git/repositories/update
    [string]$Pat,

    # Azure DevOps Server instance + collection URL.
    # For another server, use: https://{server}/tfs/{collection} or whatever your base is.
    [string]$CollectionUrl,

    # REST API version compatible with Azure DevOps Server 2022.1+ / 7.1.
    [string]$ApiVersion = "7.1",

    # Optional explicit list of projects. If empty, the script discovers all projects.
    [string[]]$Projects = @(),

    # Dry-run switch. When set, the script only prints what it *would* change.
    [switch]$WhatIf
)

# Load environment variables from .env file if parameters are missing
Import-Module -Name "$($PSScriptRoot)\..\modules\core\EnvLoader.psm1"
Import-DotEnvFile -Path "$($PSScriptRoot)\..\.env"

if (-not $Pat) {
    $Pat = $env:ADO_PAT
}

if (-not $CollectionUrl) {
    $CollectionUrl = $env:ADO_COLLECTION_URL
}



$ErrorActionPreference = "Stop"

# --- Auth headers ---------------------------------------------------------
$base64Auth = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$Pat")
)

$Headers = @{
    "Authorization" = "Basic $base64Auth"
    "Content-Type"  = "application/json"
}

function Invoke-AdoGet {
    param([string]$Url)
    Invoke-RestMethod -Method Get -Uri $Url -Headers $Headers
}

function Invoke-AdoPatch {
    param(
        [string]$Url,
        [object]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 10

    if ($WhatIf) {
        Write-Host "      [WhatIf] PATCH $Url"
        Write-Host "              Body: $json"
    }
    else {
        Invoke-RestMethod -Method Patch -Uri $Url -Headers $Headers -Body $json | Out-Null
    }
}

# --- Helper: compute new name from old ------------------------------------
function Get-NewWikiOrRepoName {
    param(
        [string]$ProjectName,
        [string]$OldName
    )

    # Anything starting with "shaheed-system.wiki"
    $prefix = "shaheed-system.wiki"
    if ($OldName -notlike "$prefix*") {
        return $null
    }

    # Suffix is whatever comes after "shaheed-system.wiki"
    $suffix = $OldName.Substring($prefix.Length)   # may be "", "-1", "-wiki-1", ...
    return "$ProjectName.wiki$suffix"
}

# --- Discover project names -----------------------------------------------
function Get-ProjectNames {
    if ($Projects -and $Projects.Count -gt 0) {
        return $Projects
    }

    $names = @()
    $url   = "$CollectionUrl/_apis/projects?`$top=1000&api-version=$ApiVersion"

    do {
        $resp = Invoke-AdoGet -Url $url
        foreach ($p in $resp.value) {
            $names += $p.name
        }

        $token = $resp.continuationToken
        if ($token) {
            $url = "$CollectionUrl/_apis/projects?`$top=1000&continuationToken=$token&api-version=$ApiVersion"
        }
        else {
            $url = $null
        }
    } while ($url)

    return $names
}

# --- Rename all matching wikis in a project -------------------------------
function Rename-WikisForProject {
    param([string]$ProjectName)

    $wikisUrl = "$CollectionUrl/$ProjectName/_apis/wiki/wikis?api-version=$ApiVersion"

    try {
        $wikisResp = Invoke-AdoGet -Url $wikisUrl
    }
    catch {
        Write-Warning "  Failed to list wikis: $($_.Exception.Message)"
        return
    }

    $wikis = $wikisResp.value
    if (-not $wikis) {
        Write-Host "  No wikis found." -ForegroundColor DarkGray
        return
    }

    foreach ($wiki in $wikis) {
        $oldName = $wiki.name
        $newName = Get-NewWikiOrRepoName -ProjectName $ProjectName -OldName $oldName

        if (-not $newName) {
            Write-Host "  [SKIP] Wiki '$oldName' (does not start with 'shaheed-system.wiki')" -ForegroundColor DarkGray
            continue
        }

        Write-Host "  Wiki '$oldName' (type=$($wiki.type))"

        if ($oldName -eq $newName) {
            Write-Host "    Wiki name already '$newName' – no change." -ForegroundColor DarkGray
            continue
        }

        # Important: send name + versions in body (this fixed your 400)
        $wikiPatchUrl = "$CollectionUrl/$ProjectName/_apis/wiki/wikis/$($wiki.id)?api-version=$ApiVersion"

        $body = @{
            name     = $newName
            versions = $wiki.versions
        }

        Write-Host "    Renaming wiki -> '$newName'"
        Invoke-AdoPatch -Url $wikiPatchUrl -Body $body
    }
}

# --- Rename all matching repos in a project -------------------------------
function Rename-ReposForProject {
    param([string]$ProjectName)

    # includeHidden=true so we also see hidden wiki repos
    $reposUrl = "$CollectionUrl/$ProjectName/_apis/git/repositories?includeHidden=true&api-version=$ApiVersion"

    try {
        $reposResp = Invoke-AdoGet -Url $reposUrl
    }
    catch {
        Write-Warning "  Failed to list git repos: $($_.Exception.Message)"
        return
    }

    $repos = $reposResp.value
    if (-not $repos) {
        Write-Host "  No git repos found." -ForegroundColor DarkGray
        return
    }

    foreach ($repo in $repos) {
        $oldName = $repo.name
        $newName = Get-NewWikiOrRepoName -ProjectName $ProjectName -OldName $oldName

        if (-not $newName) {
            continue
        }

        Write-Host "  Repo '$oldName' (id=$($repo.id))"

        if ($oldName -eq $newName) {
            Write-Host "    Repo name already '$newName' – no change." -ForegroundColor DarkGray
            continue
        }

        $repoPatchUrl = "$CollectionUrl/$ProjectName/_apis/git/repositories/$($repo.id)?api-version=$ApiVersion"
        $body = @{ name = $newName }

        Write-Host "    Renaming repo -> '$newName'"
        Invoke-AdoPatch -Url $repoPatchUrl -Body $body
    }
}

# --- Main -----------------------------------------------------------------
try {
    $projectNames = Get-ProjectNames

    if (-not $projectNames -or $projectNames.Count -eq 0) {
        Write-Warning "No projects found. Check CollectionUrl / PAT / ApiVersion."
        return
    }

    Write-Host "Projects to process:" -ForegroundColor Cyan
    $projectNames | ForEach-Object { Write-Host " - $_" }

    foreach ($p in $projectNames) {
        if ($SkipProjects -contains $p) {
            Write-Host ">>> Project: $p (skipped – template/explicit skip)" -ForegroundColor Magenta
            continue
        }

        Write-Host ">>> Project: $p" -ForegroundColor Yellow

        Rename-WikisForProject -ProjectName $p
        Rename-ReposForProject -ProjectName $p
    }

    if ($WhatIf) {
        Write-Host "`n[WhatIf] No changes were applied. Run again without -WhatIf to actually rename." -ForegroundColor Cyan
    }
}
catch {
    Write-Error "Fatal error: $($_.Exception.Message)"
    throw
}
