<#
.SYNOPSIS
    Standardize all Azure DevOps projects to a single template Project wiki.

.DESCRIPTION
    - Reads ADO_COLLECTION_URL and ADO_PAT from a .env file.
    - Uses the Project wiki from a chosen Template project as the "golden" wiki.
    - For EVERY project in the collection:
        * Deletes ALL code wikis (type = codeWiki) and their Git repositories.
        * Ensures a Project wiki (type = projectWiki) exists.
        * Clones the template Project wiki Git repo once and copies its content
          into each project's Project wiki Git repo via Git (commit & push).

    Authentication:
        Uses PAT over HTTPS via Git's http.extraheader:
        Authorization: Basic <base64("user:PAT")>

    WARNING
        This script is DESTRUCTIVE when -DryRun is NOT used:
        - Deletes ALL code wikis and their repos in ALL projects.
        - Overwrites ALL Project wiki repos with the template content.

    Use -DryRun to verify actions first. Use -Force to skip the interactive prompt.

PREREQUISITES
    - Azure DevOps Server 2020/2022 (or Services).
    - .env file with:
        ADO_COLLECTION_URL=<collection URL>
        ADO_PAT=<PAT with Wiki + Code + Project permissions>
    - Git CLI installed and available in PATH.

USAGE EXAMPLES
    # Safe: see what would happen only
    .\standardize-project-wikis.ps1 -TemplateProjectName "shaheed-system" -DryRun

    # Real run, with interactive confirmation
    .\standardize-project-wikis.ps1 -TemplateProjectName "shaheed-system"

    # Non-interactive destructive run
    .\standardize-project-wikis.ps1 -TemplateProjectName "shaheed-system" -Force
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TemplateProjectName,     # Project that hosts the golden Project wiki

    [string]$TemplateWikiName,       # Optional, default = "<TemplateProjectName>.wiki"

    [string]$EnvPath   = ".\.env",
    [string]$WorkFolder = "$env:TEMP\WikiMigration",

    [switch]$DryRun,
    [switch]$Force
)

if (-not $TemplateWikiName) {
    $TemplateWikiName = "$TemplateProjectName.wiki"
}

# ---------- Basic validation ----------

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git CLI not found in PATH. Install Git and re-run the script."
}

if (-not (Test-Path $EnvPath)) {
    throw "Env file not found at '$EnvPath'. Create it with ADO_COLLECTION_URL and ADO_PAT."
}

# ---------- Load .env ----------

Write-Host "[INFO] Loading environment from '$EnvPath'..." -ForegroundColor Cyan

$envVars = @{}
Get-Content $EnvPath |
    Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') } |
    ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) {
            $key   = $parts[0].Trim()
            $value = $parts[1].Trim()
            if ($key) { $envVars[$key] = $value }
        }
    }

if (-not $envVars.ADO_COLLECTION_URL) {
    throw "ADO_COLLECTION_URL is missing in '$EnvPath'."
}
if (-not $envVars.ADO_PAT) {
    throw "ADO_PAT is missing in '$EnvPath'."
}

$CollectionUrl = $envVars.ADO_COLLECTION_URL.TrimEnd('/')
$Pat           = $envVars.ADO_PAT

Write-Host "[INFO] ADO_COLLECTION_URL = $CollectionUrl" -ForegroundColor Green

# ---------- Auth + global settings ----------

$ApiVersion = "7.1"   # Wiki/Git REST API version

if (-not (Test-Path $WorkFolder)) {
    New-Item -ItemType Directory -Path $WorkFolder | Out-Null
}

# Build Authorization header for PAT: Base64("user:PAT")
function New-GitAuthHeader {
    param(
        [Parameter(Mandatory=$true)][string]$Pat,
        [string]$UserName = "ado-user"
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$UserName`:$Pat")
    $b64   = [System.Convert]::ToBase64String($bytes)
    return "Authorization: Basic $b64"
}

$Headers = @{
    Authorization = "Basic " + [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes(":$Pat")
    )
}

$global:GitAuthHeader = New-GitAuthHeader -Pat $Pat

# ---------- REST helper ----------

function Invoke-AdoRest {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST','DELETE','PATCH','PUT')]
        [string]$Method,
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        [object]$Body
    )

    Write-Host "[REST] $Method $Uri" -ForegroundColor DarkCyan

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json
    }
    else {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }
}

# ---------- Git helper with PAT + retries ----------

function Invoke-GitCloneWithPat {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++

        Write-Host "[GIT] clone attempt $attempt of $($MaxRetries): $Url" -ForegroundColor Cyan

        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Recurse -Force
        }

        if ($DryRun) {
            Write-Host "[DRYRUN] Would run: git -c ""http.extraheader=$($global:GitAuthHeader)"" clone $Url $TargetPath" -ForegroundColor Yellow
            return
        }

        git -c "http.extraheader=$($global:GitAuthHeader)" clone $Url $TargetPath
        if ($LASTEXITCODE -eq 0) {
            return
        }

        Write-Host "[WARN] git clone failed with exit code $LASTEXITCODE. Retrying..." -ForegroundColor Yellow
        Start-Sleep -Seconds (5 * $attempt)
    }

    throw "git clone failed for '$Url' after $MaxRetries attempts (last exit code $LASTEXITCODE)."
}

# ---------- Get all projects ----------

function Get-AdoProjects {
    $projects = @()
    $top  = 200
    $skip = 0

    while ($true) {
        $uri = "$CollectionUrl/_apis/projects?api-version=$ApiVersion&`$top=$top&`$skip=$skip"
        $page = Invoke-AdoRest -Method GET -Uri $uri

        if (-not $page.value -or $page.value.Count -eq 0) { break }

        $projects += $page.value

        if ($page.value.Count -lt $top) { break }

        $skip += $top
    }

    return $projects
}

# ---------- Resolve wiki -> Git clone URL (backing repo.remoteUrl) ----------

function Get-WikiGitCloneUrl {
    param(
        [Parameter(Mandatory=$true)][psobject]$Wiki,
        [Parameter(Mandatory=$true)][string]$ProjectName
    )

    if ($Wiki.repositoryId) {
        $repoUri = "$CollectionUrl/$ProjectName/_apis/git/repositories/$($Wiki.repositoryId)?api-version=$ApiVersion"
        $repo = Invoke-AdoRest -Method GET -Uri $repoUri
        if ($repo.remoteUrl) {
            return $repo.remoteUrl
        }
    }

    # Fallback: search all repos (including hidden) by name / id
    $reposUri = "$CollectionUrl/$ProjectName/_apis/git/repositories?api-version=$ApiVersion&includeHidden=true"
    $repos = Invoke-AdoRest -Method GET -Uri $reposUri

    $match = $repos.value | Where-Object { $_.name -eq $Wiki.name } | Select-Object -First 1
    if (-not $match) {
        $match = $repos.value | Where-Object { $_.id -eq $Wiki.id } | Select-Object -First 1
    }

    if ($match -and $match.remoteUrl) {
        return $match.remoteUrl
    }

    throw "Cannot resolve Git clone URL for wiki '$($Wiki.name)' in project '$ProjectName'."
}

# ---------- List wikis for a project ----------

function Get-ProjectWikis {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectName
    )

    $wikisUri = "$CollectionUrl/$ProjectName/_apis/wiki/wikis?api-version=$ApiVersion"
    return Invoke-AdoRest -Method GET -Uri $wikisUri
}

# ---------- Delete all code wikis (and their repos) in a project ----------

function Remove-CodeWikisForProject {
    param(
        [Parameter(Mandatory=$true)][psobject]$Project,
        [Parameter(Mandatory=$true)][psobject]$WikisResponse
    )

    $projectName = $Project.name
    $codeWikis = @()

    if ($WikisResponse.value) {
        $codeWikis = $WikisResponse.value |
            Where-Object { $_.type -eq "codeWiki" }
    }

    if (-not $codeWikis -or $codeWikis.Count -eq 0) {
        Write-Host "[INFO] Project '$projectName': no code wikis to delete." -ForegroundColor DarkGray
        return
    }

    foreach ($wiki in $codeWikis) {
        Write-Host "[WARN] Project '$projectName': deleting code wiki '$($wiki.name)' (id=$($wiki.id))..." -ForegroundColor Yellow

        if ($DryRun) {
            Write-Host "    [DRYRUN] Would DELETE wiki '$($wiki.name)' and repoId '$($wiki.repositoryId)'." -ForegroundColor Yellow
            continue
        }

        # 1) Delete wiki resource (codeWiki)
        try {
            $delWikiUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($wiki.id)?api-version=$ApiVersion"
            Invoke-AdoRest -Method DELETE -Uri $delWikiUri | Out-Null
            Write-Host "    - Wiki resource deleted." -ForegroundColor Yellow
        }
        catch {
            Write-Host "    - [WARN] Failed to delete wiki resource: $($_.Exception.Message)" -ForegroundColor Red
        }

        # 2) Delete backing Git repository (if we have repositoryId)
        if ($wiki.repositoryId) {
            try {
                $delRepoUri = "$CollectionUrl/$projectName/_apis/git/repositories/$($wiki.repositoryId)?api-version=$ApiVersion"
                Invoke-AdoRest -Method DELETE -Uri $delRepoUri | Out-Null
                Write-Host "    - Backing Git repo deleted (id=$($wiki.repositoryId))." -ForegroundColor Yellow
            }
            catch {
                Write-Host "    - [WARN] Failed to delete backing Git repo: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "    - [INFO] No repositoryId on wiki, skipping repo delete." -ForegroundColor DarkGray
        }
    }
}

# ---------- Ensure a Project wiki exists for a project ----------

function Ensure-ProjectWiki {
    param(
        [Parameter(Mandatory=$true)][psobject]$Project,
        [Parameter(Mandatory=$true)][psobject]$ExistingWikisResponse
    )

    $projectName = $Project.name
    $projectId   = $Project.id

    $projectWiki = $null

    if ($ExistingWikisResponse.value) {
        $projectWiki = $ExistingWikisResponse.value |
            Where-Object { $_.type -eq "projectWiki" } |
            Select-Object -First 1
    }

    if (-not $projectWiki) {
        Write-Host "[INFO] Project '$projectName': creating Project wiki '$projectName.wiki'..." -ForegroundColor Cyan

        $body = @{
            type      = "projectWiki"
            name      = "$projectName.wiki"
            projectId = $projectId
        }

        if ($DryRun) {
            Write-Host "[DRYRUN] Would POST create Project wiki '$projectName.wiki'." -ForegroundColor Yellow
            # fake object to keep flow working
            return [pscustomobject]@{
                id           = [guid]::NewGuid().ToString()
                name         = "$projectName.wiki"
                type         = "projectWiki"
                repositoryId = $null
            }
        }

        $createUri = "$CollectionUrl/$projectName/_apis/wiki/wikis?api-version=$ApiVersion"
        $projectWiki = Invoke-AdoRest -Method POST -Uri $createUri -Body $body
    }

    if ($DryRun) {
        return $projectWiki
    }

    # Re-fetch to ensure we have full properties (repositoryId, etc.)
    $getUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($projectWiki.id)?api-version=$ApiVersion"
    $projectWiki = Invoke-AdoRest -Method GET -Uri $getUri

    return $projectWiki
}

# ---------- Clone template Project wiki once ----------

function Clone-TemplateWiki {
    param(
        [Parameter(Mandatory=$true)][psobject]$TemplateProject,
        [Parameter(Mandatory=$true)][string]$TemplateWikiName
    )

    $projectName = $TemplateProject.name

    Write-Host ""
    Write-Host "=== Preparing template wiki from project '$projectName' ===" -ForegroundColor Magenta

    $wikis = Get-ProjectWikis -ProjectName $projectName

    if (-not $wikis.value) {
        throw "Template project '$projectName' has no wikis. Create a Project wiki first."
    }

    $tplWiki = $wikis.value |
        Where-Object { $_.type -eq "projectWiki" -and $_.name -eq $TemplateWikiName } |
        Select-Object -First 1

    if (-not $tplWiki) {
        $tplWiki = $wikis.value |
            Where-Object { $_.type -eq "projectWiki" } |
            Select-Object -First 1
    }

    if (-not $tplWiki) {
        throw "Template project '$projectName' has no Project wiki. Create one and re-run."
    }

    if (-not $DryRun) {
        # Refresh full wiki object
        $getUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($tplWiki.id)?api-version=$ApiVersion"
        $tplWiki = Invoke-AdoRest -Method GET -Uri $getUri
    }

    # Get Git clone URL from backing repo
    $tplCloneUrl = Get-WikiGitCloneUrl -Wiki $tplWiki -ProjectName $projectName
    Write-Host "[INFO] Template Project wiki '$($tplWiki.name)' Git clone URL: $tplCloneUrl" -ForegroundColor Green

    $tplPath = Join-Path $WorkFolder "TemplateProjectWiki"
    if (Test-Path $tplPath) {
        Remove-Item $tplPath -Recurse -Force
    }

    Write-Host "[INFO] Cloning template wiki repo..." -ForegroundColor Cyan
    Invoke-GitCloneWithPat -Url $tplCloneUrl -TargetPath $tplPath

    return @{
        WikiObject = $tplWiki
        Path       = $tplPath
        CloneUrl   = $tplCloneUrl
    }
}

# ---------- Copy template wiki content into a project wiki ----------

function Sync-ProjectWikiFromTemplate {
    param(
        [Parameter(Mandatory=$true)][psobject]$Project,
        [Parameter(Mandatory=$true)][psobject]$ProjectWiki,
        [Parameter(Mandatory=$true)][string]$TemplatePath
    )

    $projectName = $Project.name
    $sanitizedProjectName = ($projectName -replace '[^\w\.-]', '_')

    # Resolve Git clone URL for this project's wiki repo
    $dstCloneUrl = Get-WikiGitCloneUrl -Wiki $ProjectWiki -ProjectName $projectName

    $dstPath = Join-Path $WorkFolder "$sanitizedProjectName-ProjectWiki"

    Write-Host "[INFO] Project '$projectName': cloning Project wiki Git repo..." -ForegroundColor Cyan
    Invoke-GitCloneWithPat -Url $dstCloneUrl -TargetPath $dstPath

    if ($DryRun) {
        Write-Host "[DRYRUN] Would clear content of '$dstPath' (except .git) and copy from template '$TemplatePath'." -ForegroundColor Yellow
        return
    }

    # Clear target content except .git
    Write-Host "[INFO] Project '$projectName': clearing existing wiki content..." -ForegroundColor Cyan
    Get-ChildItem -Path $dstPath -Force |
        Where-Object { $_.Name -ne ".git" } |
        Remove-Item -Recurse -Force

    # Copy everything from template except .git
    Write-Host "[INFO] Project '$projectName': copying template wiki content..." -ForegroundColor Cyan
    Get-ChildItem -Path $TemplatePath -Force |
        Where-Object { $_.Name -ne ".git" } |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $dstPath -Recurse
        }

    # Commit + push only if there are changes
    Push-Location $dstPath

    $status = git status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        git add .
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "git add failed for project '$projectName'."
        }

        git commit -m "Standardize Project wiki from template '$TemplateProjectName'"

        Write-Host "[INFO] Project '$projectName': pushing standardized wiki content..." -ForegroundColor Cyan
        git -c "http.extraheader=$($global:GitAuthHeader)" push
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "git push failed for project '$projectName' (exit code $LASTEXITCODE)."
        }
    }
    else {
        Write-Host "[INFO] Project '$projectName': no changes to push (already matches template)." -ForegroundColor DarkGray
    }

    Pop-Location
}

# ---------- MAIN ----------

Write-Host ""
Write-Host ">>> This script will:" -ForegroundColor Cyan
Write-Host "    - Delete ALL code wikis + repos in ALL projects." -ForegroundColor Cyan
Write-Host "    - Overwrite ALL Project wikis with template from '$TemplateProjectName'." -ForegroundColor Cyan

if (-not $DryRun -and -not $Force) {
    $answer = Read-Host "Type YES to continue, anything else to abort"
    if ($answer -ne "YES") {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
Write-Host ">>> Enumerating all projects in '$CollectionUrl'..." -ForegroundColor Cyan
$allProjects = Get-AdoProjects
Write-Host "[INFO] Found $($allProjects.Count) projects." -ForegroundColor Green

# Locate template project
$templateProject = $allProjects | Where-Object { $_.name -eq $TemplateProjectName } | Select-Object -First 1
if (-not $templateProject) {
    throw "Template project '$TemplateProjectName' not found in this collection."
}

# Clone template wiki once
$templateInfo = Clone-TemplateWiki -TemplateProject $templateProject -TemplateWikiName $TemplateWikiName
$templatePath = $templateInfo.Path

# PASS 1: delete all code wikis (and repos)
foreach ($proj in $allProjects) {
    try {
        Write-Host ""
        Write-Host "=================================================================" -ForegroundColor Magenta
        Write-Host "=== PASS 1 (Delete code wikis) - Project: $($proj.name) [$($proj.id)] ===" -ForegroundColor Magenta

        $wikis = Get-ProjectWikis -ProjectName $proj.name
        Remove-CodeWikisForProject -Project $proj -WikisResponse $wikis
    }
    catch {
        Write-Host "[ERROR] PASS 1: Project '$($proj.name)' failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# PASS 2: ensure Project wiki exists and sync from template
foreach ($proj in $allProjects) {
    try {
        Write-Host ""
        Write-Host "=================================================================" -ForegroundColor Magenta
        Write-Host "=== PASS 2 (Sync template Project wiki) - Project: $($proj.name) [$($proj.id)] ===" -ForegroundColor Magenta

        $wikis = Get-ProjectWikis -ProjectName $proj.name
        $projWiki = Ensure-ProjectWiki -Project $proj -ExistingWikisResponse $wikis

        Sync-ProjectWikiFromTemplate -Project $proj -ProjectWiki $projWiki -TemplatePath $templatePath
        Write-Host "[DONE] Project '$($proj.name)' wiki standardized from template." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] PASS 2: Project '$($proj.name)' failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "[ALL DONE]" -ForegroundColor Green
Write-Host " - All code wikis and their repos have been deleted in all projects (where present), unless -DryRun." -ForegroundColor Green
Write-Host " - Every project now has a Project wiki whose Git repo content matches the template project '$TemplateProjectName', unless -DryRun." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
