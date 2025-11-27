<#
Clone ALL wikis from one "template" project into all other projects
in an Azure DevOps Server collection.

For each wiki in the template project:
  - Fork its backing Git repo into every other project.
  - Create a code wiki in each project backed by that fork.

Smart naming:
  - Repo name: "<TemplateWikiName>-wiki", sanitized and made unique.
  - Wiki name: "<TemplateWikiName>", sanitized and made unique.

Run FIRST with -DryRun $true to verify actions.
Then run with -DryRun $false to apply.
#>

[CmdletBinding()]
param(
    # Collection URL (Azure DevOps Server collection)
    [string]$CollectionUrl,

    # PAT with Code + Wiki permissions
    [string]$Pat,

    # Project that contains the template wikis
    [Parameter(Mandatory = $true)]
    [string]$TemplateProjectName,

    # Projects to skip (TemplateProjectName is added automatically)
    [string[]]$SkipProjects     = @(),

    # Dry run: only log what would happen
    [bool]$DryRun               = $true
)

# ================================================================
# API version – adjust if your Server only supports 6.0 or 5.1.
# For Azure DevOps Server 2022+, 7.1 works. 
# ================================================================
$ApiVersion = "7.1"

#if parameters are missing, read it from .env file
Import-Module -Name "$($PSScriptRoot)\..\modules\core\EnvLoader.psm1"
Import-DotEnvFile -Path "$($PSScriptRoot)\..\.env"

if (-not $Pat) {
    $Pat = $env:ADO_PAT
}

if (-not $CollectionUrl) {
    $CollectionUrl = $env:ADO_COLLECTION_URL
}


# ================================================================
# Helper: make a safe short name (for Git repo or wiki)
# Git repo names cannot include characters like \ / : * ? " < > ; # $ * { } , + = [ ] |
# and should not start with "_" or end with ".". 
# ================================================================
function New-SafeName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [int]$MaxLength = 64
    )

    $name = $BaseName.Trim()

    # Replace invalid characters with '-'
    $name = $name -replace '[\\/:*?"<>;#$*{},+=\[\]\|]', '-'

    # Collapse multiple hyphens
    $name = $name -replace '-{2,}', '-'

    # Trim periods
    $name = $name.Trim('.')

    # Remove leading underscores
    while ($name.StartsWith('_')) {
        $name = $name.Substring(1)
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "wiki"
    }

    if ($name.Length -gt $MaxLength) {
        $name = $name.Substring(0, $MaxLength)
    }

    return $name
}

function Get-UniqueName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseName,

        [string[]]$ExistingNames,

        [int]$MaxLength = 64
    )

    $candidate = New-SafeName -BaseName $BaseName -MaxLength $MaxLength

    if (-not $ExistingNames -or -not ($ExistingNames -contains $candidate)) {
        return $candidate
    }

    $i = 1
    while ($true) {
        $candidateWithSuffix = New-SafeName -BaseName ("$BaseName-$i") -MaxLength $MaxLength
        if (-not ($ExistingNames -contains $candidateWithSuffix)) {
            return $candidateWithSuffix
        }
        $i++
    }
}

# ================================================================
# Helper: REST error logger that works in PS 5.1 and PS 7+ 
# ================================================================
function Write-DevOpsRestError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [string]$Prefix = "    ERROR"
    )

    Write-Host "$($Prefix): $($ErrorRecord.Exception.Message)" -ForegroundColor Red

    $respBody   = $null
    $statusCode = $null
    $ex         = $ErrorRecord.Exception

    if ($ex.PSObject.Properties.Name -contains 'Response' -and $ex.Response) {
        $resp = $ex.Response

        # PowerShell 7+ HttpClient style
        if ($resp -is [System.Net.Http.HttpResponseMessage]) {
            try {
                $statusCode = [int]$resp.StatusCode
            } catch {}
            try {
                $respBody = $resp.Content.ReadAsStringAsync().Result
            } catch {}
        }
        # Windows PowerShell HttpWebResponse style
        elseif ($resp -is [System.Net.HttpWebResponse]) {
            try {
                $statusCode = [int]$resp.StatusCode
            } catch {}
            try {
                $stream = $resp.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $respBody = $reader.ReadToEnd()
                    $reader.Dispose()
                    $stream.Dispose()
                }
            } catch {}
        }
    }

    if ($statusCode) {
        Write-Host "    HTTP status : $statusCode" -ForegroundColor Yellow
    }
    if ($respBody) {
        Write-Host "    Response body:" -ForegroundColor Yellow
        Write-Host "    $respBody"
    }
}

# ================================================================
# Auth header using PAT via Basic auth (username empty). 
# ================================================================
$bytes  = [Text.Encoding]::ASCII.GetBytes(":$Pat")
$base64 = [Convert]::ToBase64String($bytes)

$Headers = @{
    "Authorization" = "Basic $base64"
    "Content-Type"  = "application/json"
}

Write-Host "Collection : $CollectionUrl" -ForegroundColor Cyan
Write-Host "API        : $ApiVersion"    -ForegroundColor Cyan
Write-Host "Template   : $TemplateProjectName" -ForegroundColor Cyan
Write-Host "DryRun     : $DryRun"        -ForegroundColor Cyan
Write-Host ""

# ================================================================
# 1) Get all template wikis from the template project
#    GET {collection}/{project}/_apis/wiki/wikis 
# ================================================================
$templateWikisUrl = "$CollectionUrl/$TemplateProjectName/_apis/wiki/wikis?api-version=$ApiVersion"
Write-Host "Getting wikis from template project '$TemplateProjectName'..." -ForegroundColor Cyan

$templateWikisResult = $null
try {
    $templateWikisResult = Invoke-RestMethod -Uri $templateWikisUrl -Headers $Headers -Method GET -ErrorAction Stop
} catch {
    Write-DevOpsRestError -ErrorRecord $_ -Prefix "ERROR listing template wikis"
    throw "Cannot continue without template wikis."
}

$templateWikis = $templateWikisResult.value
if (-not $templateWikis -or $templateWikis.Count -eq 0) {
    throw "Template project '$TemplateProjectName' has no wikis. Nothing to clone."
}

Write-Host "Template project has $($templateWikis.Count) wiki(s):" -ForegroundColor Green
foreach ($tw in $templateWikis) {
    Write-Host ("  - {0} (type={1}, repoId={2})" -f $tw.name, $tw.type, $tw.repositoryId) -ForegroundColor Green
}
Write-Host ""

# ================================================================
# 2) Get all projects in the collection 
# ================================================================
if ($SkipProjects -notcontains $TemplateProjectName) {
    $SkipProjects += $TemplateProjectName
}

$projectsUrl = "$CollectionUrl/_apis/projects?stateFilter=All&`$top=2000&api-version=$ApiVersion"
Write-Host "Listing projects in collection..." -ForegroundColor Cyan

$projectsResult = $null
try {
    $projectsResult = Invoke-RestMethod -Uri $projectsUrl -Headers $Headers -Method GET -ErrorAction Stop
} catch {
    Write-DevOpsRestError -ErrorRecord $_ -Prefix "ERROR listing projects"
    throw "Cannot continue without project list."
}

$allProjects = $projectsResult.value
if (-not $allProjects) {
    throw "No projects returned. Check permissions and collection URL."
}

$targetProjects = $allProjects | Where-Object { $SkipProjects -notcontains $_.name }

Write-Host "Total projects : $($allProjects.Count)" -ForegroundColor Gray
Write-Host "Target projects: $($targetProjects.Count)" -ForegroundColor Gray
Write-Host "Skipped        : $([string]::Join(', ', $SkipProjects))" -ForegroundColor Gray
Write-Host ""

# ================================================================
# 3) For each target project:
#    - Read existing wikis and repos
#    - For each template wiki:
#         * choose smart repo and wiki names
#         * fork template repo into target project 
#         * wait for defaultBranch on the fork 
#         * create code wiki on that repo 
# ================================================================
foreach ($proj in $targetProjects) {

    Write-Host "=== Project: $($proj.name) [$($proj.id)] ===" -ForegroundColor Cyan

    # 3.a – existing wikis in this project
    $projWikisUrl = "$CollectionUrl/$($proj.name)/_apis/wiki/wikis?api-version=$ApiVersion"
    $existingWikiNames = @()

    try {
        $projWikisResult = Invoke-RestMethod -Uri $projWikisUrl -Headers $Headers -Method GET -ErrorAction Stop
        if ($projWikisResult.value) {
            $existingWikiNames = $projWikisResult.value | ForEach-Object { $_.name }
        }
        Write-Host "  Existing wikis   : $($existingWikiNames.Count)" -ForegroundColor DarkGray
    } catch {
        Write-DevOpsRestError -ErrorRecord $_ -Prefix "  ERROR listing wikis for project '$($proj.name)'"
        Write-Host "  Skipping project '$($proj.name)'." -ForegroundColor Yellow
        continue
    }

    # 3.b – existing Git repos in this project
    $reposUrl = "$CollectionUrl/$($proj.name)/_apis/git/repositories?api-version=$ApiVersion"
    $existingRepoNames = @()

    try {
        $reposResult = Invoke-RestMethod -Uri $reposUrl -Headers $Headers -Method GET -ErrorAction Stop
        if ($reposResult.value) {
            $existingRepoNames = $reposResult.value | ForEach-Object { $_.name }
        }
        Write-Host "  Existing repos   : $($existingRepoNames.Count)" -ForegroundColor DarkGray
    } catch {
        Write-DevOpsRestError -ErrorRecord $_ -Prefix "  ERROR listing repos for project '$($proj.name)'"
        Write-Host "  Skipping project '$($proj.name)'." -ForegroundColor Yellow
        continue
    }

    # 3.c – for each template wiki, clone into this project
    foreach ($tw in $templateWikis) {

        $templateWikiName = $tw.name
        $templateRepoId   = $tw.repositoryId
        $templateProjId   = $tw.projectId

        if (-not $templateRepoId) {
            Write-Host "  SKIP template wiki '$templateWikiName' (no repositoryId returned)." -ForegroundColor Yellow
            continue
        }

        # Smart repo name: "<TemplateWikiName>-wiki" -> unique
        $baseRepoName   = "$templateWikiName-wiki"
        $targetRepoName = Get-UniqueName -BaseName $baseRepoName -ExistingNames $existingRepoNames -MaxLength 64
        $existingRepoNames += $targetRepoName

        # Smart wiki name: "<TemplateWikiName>" -> unique in this project
        $targetWikiName = Get-UniqueName -BaseName $templateWikiName -ExistingNames $existingWikiNames -MaxLength 64
        $existingWikiNames += $targetWikiName

        Write-Host "  Template wiki : '$templateWikiName'" -ForegroundColor Gray
        Write-Host "    -> Repo name : '$targetRepoName'" -ForegroundColor Gray
        Write-Host "    -> Wiki name : '$targetWikiName'" -ForegroundColor Gray

        if ($DryRun) {
            Write-Host "    DRYRUN: would fork repo $templateRepoId into '$targetRepoName' and create code wiki '$targetWikiName' in project '$($proj.name)'." -ForegroundColor DarkYellow
            continue
        }

        # --- 3.c.1 – create forked repo in target project ---
        $forkUri = "$CollectionUrl/$($proj.name)/_apis/git/repositories?api-version=$ApiVersion"

        $forkBodyObj = @{
            name    = $targetRepoName
            project = @{
                id = $proj.id
            }
            parentRepository = @{
                id      = $templateRepoId
                project = @{
                    id = $templateProjId
                }
            }
        }

        $forkBodyJson = $forkBodyObj | ConvertTo-Json -Depth 6

        $newRepo = $null
        try {
            $newRepo = Invoke-RestMethod -Uri $forkUri -Headers $Headers -Method POST -Body $forkBodyJson -ErrorAction Stop
            Write-Host "    OK: repo created '$($newRepo.name)' (id = $($newRepo.id))" -ForegroundColor Green
        } catch {
            Write-DevOpsRestError -ErrorRecord $_ -Prefix "    ERROR creating forked repo in '$($proj.name)'"
            continue
        }

        # --- 3.c.2 – wait for fork sync so defaultBranch exists ---
        $maxAttempts  = 20
        $delaySeconds = 3
        $repoDetails  = $null

        for ($i = 1; $i -le $maxAttempts; $i++) {
            try {
                $repoDetails = Invoke-RestMethod -Uri "$CollectionUrl/$($proj.name)/_apis/git/repositories/$($newRepo.id)?api-version=$ApiVersion" -Headers $Headers -Method GET -ErrorAction Stop
            } catch {
                Write-DevOpsRestError -ErrorRecord $_ -Prefix "    ERROR reading repo details for '$($newRepo.name)'"
                $repoDetails = $null
            }

            if ($repoDetails -and $repoDetails.defaultBranch) {
                break
            }

            if ($i -eq 1) {
                Write-Host "    INFO: fork sync in progress (defaultBranch is null). Waiting..." -ForegroundColor DarkGray
            }
            Start-Sleep -Seconds $delaySeconds
        }

        if (-not $repoDetails -or -not $repoDetails.defaultBranch) {
            Write-Host "    ERROR: forked repo '$($newRepo.name)' in project '$($proj.name)' has no defaultBranch after $($maxAttempts * $delaySeconds)s. Skipping wiki creation." -ForegroundColor Red
            continue
        }

        $branchRef  = $repoDetails.defaultBranch   # e.g. refs/heads/wikiMain or refs/heads/wikiMaster 
        $branchName = $branchRef
        if ($branchRef -like 'refs/heads/*') {
            $branchName = $branchRef.Split('/')[-1]
        }

        Write-Host "    OK: fork sync complete. defaultBranch = '$branchRef' (branchName = '$branchName')" -ForegroundColor Green

        # --- 3.c.3 – create code wiki backed by this repo ---
        # POST {collection}/{project}/_apis/wiki/wikis?api-version=7.1 
        $createWikiUri = "$CollectionUrl/$($proj.name)/_apis/wiki/wikis?api-version=$ApiVersion"

        $wikiBodyObj = @{
            name         = $targetWikiName
            projectId    = $proj.id
            repositoryId = $newRepo.id
            type         = "codeWiki"
            mappedPath   = "/"
            version      = @{
                version     = $branchName
                versionType = "branch"
            }
        }

        $wikiBodyJson = $wikiBodyObj | ConvertTo-Json -Depth 5

        Write-Host "    ACTION: create code wiki '$targetWikiName' on branch '$branchName'..." -ForegroundColor Gray

        try {
            $wikiResult = Invoke-RestMethod -Uri $createWikiUri -Headers $Headers -Method POST -Body $wikiBodyJson -ErrorAction Stop
            Write-Host "    OK: wiki created '$($wikiResult.name)' (id = $($wikiResult.id)) in project '$($proj.name)'" -ForegroundColor Green
        } catch {
            Write-DevOpsRestError -ErrorRecord $_ -Prefix "    ERROR creating wiki '$targetWikiName' in '$($proj.name)'"
            continue
        }
    }

    Write-Host ""
}

Write-Host "Done." -ForegroundColor Cyan
