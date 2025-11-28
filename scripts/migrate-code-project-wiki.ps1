
param(
    [Parameter(Mandatory = $true)]
    [string]$TemplateProjectName,

    [string]$TemplateWikiName,

    [string]$EnvPath   = ".\.env",
    [string]$WorkFolder = "$($env:TEMP)\WikiMigration",

    [int]$MaxMigrationAttempts = 3,
    [int]$ValidationDelaySeconds = 5,
    [switch]$DryRun,
    [switch]$Force
)

if (-not $TemplateWikiName) {
    $TemplateWikiName = "$TemplateProjectName.wiki"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git CLI not found in PATH. Install Git and re-run the script."
}

if (-not (Test-Path $EnvPath)) {
    throw "Env file not found at '$EnvPath'. Expected ADO_COLLECTION_URL and ADO_PAT."
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
    throw "ADO_COLLECTION_URL missing in .env."
}
if (-not $envVars.ADO_PAT) {
    throw "ADO_PAT missing in .env."
}

$CollectionUrl = $envVars.ADO_COLLECTION_URL.TrimEnd('/')
$Pat           = $envVars.ADO_PAT

Write-Host "[INFO] ADO_COLLECTION_URL = $CollectionUrl" -ForegroundColor Green


# --- Basic checks ---

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git CLI not found in PATH. Install Git and re-run."
}

if (-not (Test-Path $EnvPath)) {
    throw ".env file not found at '$EnvPath'. Expected COLLECTION_URL and ADO_PAT."
}


if (-not (Test-Path $WorkFolder)) {
    New-Item -ItemType Directory -Path $WorkFolder | Out-Null
}

# --- Auth ---

$Headers = @{
    Authorization = "Basic " + [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes(":$Pat")
    )
}

# For git http.extraheader
$global:GitAuthHeader = "Authorization: Basic " + [System.Convert]::ToBase64String(
    [System.Text.Encoding]::UTF8.GetBytes("ado-user`:$Pat")
)

# --- Global tracking ---

$Global:MigratedProjects      = New-Object System.Collections.Generic.List[object]
$Global:SkippedProjects       = New-Object System.Collections.Generic.List[object]
$Global:FailedValidation      = New-Object System.Collections.Generic.List[object]
$Global:ErrorProjects         = New-Object System.Collections.Generic.List[object]

# --- Helper: REST wrapper ---

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
        $json = $Body | ConvertTo-Json -Depth 20
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json
    }
    else {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }
}

# --- Helper: Git clone with PAT header ---

function Invoke-GitCloneWithPat {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++

        Write-Host "[GIT] clone attempt $attempt/$($MaxRetries): $Url"

        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Recurse -Force
        }

        if ($DryRun) {
            Write-Host "[DRYRUN] git -c ""http.extraheader=$($global:GitAuthHeader)"" clone $Url $TargetPath"
            return
        }

        git -c "http.extraheader=$($global:GitAuthHeader)" clone $Url $TargetPath
        if ($LASTEXITCODE -eq 0) { return }

        Write-Host "[WARN] git clone failed (exit $LASTEXITCODE). Retrying..."
        Start-Sleep -Seconds (5 * $attempt)
    }

    throw "git clone failed for '$Url' after $MaxRetries attempts."
}

# --- Helper: list projects ---

function Get-AdoProjects {
    $projects = @()
    $top  = 200
    $skip = 0

    while ($true) {
        $uri  = "$CollectionUrl/_apis/projects?api-version=$ApiVersion&`$top=$top&`$skip=$skip"
        $page = Invoke-AdoRest -Method GET -Uri $uri -Body $null

        if (-not $page.value -or $page.value.Count -eq 0) { break }

        $projects += $page.value
        if ($page.value.Count -lt $top) { break }
        $skip += $top
    }

    return $projects
}

# --- Helper: list wikis in a project ---

function Get-ProjectWikis {
    param([Parameter(Mandatory=$true)][string]$ProjectName)

    $uri = "$CollectionUrl/$ProjectName/_apis/wiki/wikis?api-version=$ApiVersion"
    return Invoke-AdoRest -Method GET -Uri $uri -Body $null
}

# --- Helper: resolve wiki -> Git clone URL ---

function Get-WikiGitCloneUrl {
    param(
        [Parameter(Mandatory=$true)][psobject]$Wiki,
        [Parameter(Mandatory=$true)][string]$ProjectName
    )

    if ($Wiki.repositoryId) {
        $repoUri = "$CollectionUrl/$ProjectName/_apis/git/repositories/$($Wiki.repositoryId)?api-version=$ApiVersion"
        $repo    = Invoke-AdoRest -Method GET -Uri $repoUri -Body $null
        if ($repo.remoteUrl) { return $repo.remoteUrl }
    }

    # fallback: search repo list including hidden
    $reposUri = "$CollectionUrl/$ProjectName/_apis/git/repositories?api-version=$ApiVersion&includeHidden=true"
    $repos    = Invoke-AdoRest -Method GET -Uri $reposUri -Body $null

    $match = $repos.value | Where-Object { $_.name -eq $Wiki.name } | Select-Object -First 1
    if (-not $match) {
        $match = $repos.value | Where-Object { $_.id -eq $Wiki.id } | Select-Object -First 1
    }

    if ($match -and $match.remoteUrl) { return $match.remoteUrl }

    throw "Cannot resolve Git clone URL for wiki '$($Wiki.name)' in project '$ProjectName'."
}

# --- Helper: delete all code wikis in a project ---

function Remove-CodeWikisForProject {
    param(
        [Parameter(Mandatory=$true)][psobject]$Project,
        [Parameter(Mandatory=$true)][psobject]$WikisResponse
    )

    $projectName = $Project.name
    $codeWikis   = @()

    if ($WikisResponse.value) {
        $codeWikis = $WikisResponse.value | Where-Object { $_.type -eq "codeWiki" }
    }

    if (-not $codeWikis -or $codeWikis.Count -eq 0) {
        Write-Host "[INFO] '$projectName': no code wikis to delete."
        return
    }

    foreach ($wiki in $codeWikis) {
        Write-Host "[WARN] '$projectName': deleting code wiki '$($wiki.name)' (id=$($wiki.id))"

        if ($DryRun) {
            Write-Host "   [DRYRUN] would DELETE wiki and repoId '$($wiki.repositoryId)'."
            continue
        }

        try {
            $delWikiUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($wiki.id)?api-version=$ApiVersion"
            Invoke-AdoRest -Method DELETE -Uri $delWikiUri -Body $null | Out-Null
            Write-Host "   - wiki deleted."
        }
        catch {
            Write-Host "   - [WARN] wiki delete failed: $($_.Exception.Message)"
        }

        if ($wiki.repositoryId) {
            try {
                $delRepoUri = "$CollectionUrl/$projectName/_apis/git/repositories/$($wiki.repositoryId)?api-version=$ApiVersion"
                Invoke-AdoRest -Method DELETE -Uri $delRepoUri -Body $null | Out-Null
                Write-Host "   - backing repo deleted (id=$($wiki.repositoryId))."
            }
            catch {
                Write-Host "   - [WARN] repo delete failed: $($_.Exception.Message)"
            }
        }
    }
}

# --- Helper: ensure project wiki exists ---

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
        Write-Host "[INFO] '$projectName': creating Project wiki '$projectName.wiki'..."

        $body = @{
            type      = "projectWiki"
            name      = "$projectName.wiki"
            projectId = $projectId
        }

        if ($DryRun) {
            Write-Host "   [DRYRUN] would POST create project wiki."
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

    if ($DryRun) { return $projectWiki }

    $getUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($projectWiki.id)?api-version=$ApiVersion"
    return Invoke-AdoRest -Method GET -Uri $getUri -Body $null
}

# --- Helper: get all wiki page paths using recursionLevel=Full ---

function Get-WikiPagePaths {
    param(
        [Parameter(Mandatory=$true)][psobject]$Wiki,
        [Parameter(Mandatory=$true)][string]$ProjectName
    )

    $wikiId = $Wiki.id
    $uri    = "$CollectionUrl/$ProjectName/_apis/wiki/wikis/$wikiId/pages?path=/&recursionLevel=Full&includeContent=false&api-version=$ApiVersion"

    try {
        $root = Invoke-AdoRest -Method GET -Uri $uri -Body $null
    }
    catch {
        Write-Host "[WARN] '$ProjectName': failed to read wiki pages for '$($Wiki.name)': $($_.Exception.Message)"
        return @()
    }

    $paths = @()
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)

    while ($stack.Count -gt 0) {
        $p = $stack.Pop()

        if ($p.PSObject.Properties.Name -contains "path" -and $p.path) {
            $paths += [string]$p.path
        }

        if ($p.PSObject.Properties.Name -contains "subPages" -and $p.subPages) {
            foreach ($sp in $p.subPages) {
                $stack.Push($sp)
            }
        }
    }

    return $paths
}

# --- Helper: compare template vs target page sets ---

function Test-TemplateCoverage {
    param(
        [Parameter(Mandatory=$true)][string[]]$TemplatePaths,
        [Parameter(Mandatory=$true)][string[]]$TargetPaths
    )

    $tpl = $TemplatePaths | Where-Object { $_ -ne "/" } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique
    $dst = $TargetPaths   | Where-Object { $_ -ne "/" } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique

    if ($tpl.Count -eq 0) {
        Write-Host "[WARN] Template wiki appears empty (no page paths other than '/')."
        return $false
    }

    foreach ($t in $tpl) {
        if (-not ($dst -contains $t)) {
            return $false
        }
    }
    return $true
}

# --- Helper: clone template wiki once ---

function Clone-TemplateWiki {
    param(
        [Parameter(Mandatory=$true)][psobject]$TemplateProject,
        [Parameter(Mandatory=$true)][string]$TemplateWikiName
    )

    $projectName = $TemplateProject.name
    Write-Host ""
    Write-Host "=== Using template wiki from '$projectName' ==="

    $wikis = Get-ProjectWikis -ProjectName $projectName
    if (-not $wikis.value) {
        throw "Template project '$projectName' has no wikis."
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
        throw "Template project '$projectName' has no Project wiki."
    }

    if (-not $DryRun) {
        $getUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($tplWiki.id)?api-version=$ApiVersion"
        $tplWiki = Invoke-AdoRest -Method GET -Uri $getUri -Body $null
    }

    $tplCloneUrl = Get-WikiGitCloneUrl -Wiki $tplWiki -ProjectName $projectName
    Write-Host "[INFO] Template wiki '$($tplWiki.name)' Git URL: $tplCloneUrl"

    $tplPath = Join-Path $WorkFolder "TemplateProjectWiki"
    if (Test-Path $tplPath) { Remove-Item $tplPath -Recurse -Force }

    Write-Host "[INFO] Cloning template wiki repo..."
    Invoke-GitCloneWithPat -Url $tplCloneUrl -TargetPath $tplPath

    # Page set for template
    $tplPaths = Get-WikiPagePaths -Wiki $tplWiki -ProjectName $projectName
    Write-Host "[INFO] Template wiki has $($tplPaths.Count) pages (including '/')."

    return @{
        WikiObject   = $tplWiki
        Path         = $tplPath
        CloneUrl     = $tplCloneUrl
        PagePaths    = $tplPaths
    }
}

# --- Helper: sync wiki from template via Git ---

function Sync-ProjectWikiFromTemplate {
    param(
        [Parameter(Mandatory=$true)][psobject]$Project,
        [Parameter(Mandatory=$true)][psobject]$ProjectWiki,
        [Parameter(Mandatory=$true)][string]$TemplatePath
    )

    $projectName = $Project.name
    $sanitized   = ($projectName -replace '[^\w\.-]', '_')

    $dstCloneUrl = Get-WikiGitCloneUrl -Wiki $ProjectWiki -ProjectName $projectName
    $dstPath     = Join-Path $WorkFolder "$sanitized-ProjectWiki"

    if ($DryRun) {
        Write-Host "[DRYRUN] Would clone '$dstCloneUrl', wipe contents, and copy from '$TemplatePath'."
        return
    }

    Write-Host "[INFO] '$projectName': cloning project wiki repo..."
    Invoke-GitCloneWithPat -Url $dstCloneUrl -TargetPath $dstPath

    # Clear target content except .git
    Get-ChildItem -Path $dstPath -Force |
        Where-Object { $_.Name -ne ".git" } |
        Remove-Item -Recurse -Force

    # Copy template contents except .git
    Get-ChildItem -Path $TemplatePath -Force |
        Where-Object { $_.Name -ne ".git" } |
        ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $dstPath -Recurse
        }

    Push-Location $dstPath
    $status = git status --porcelain

    if (-not [string]::IsNullOrWhiteSpace($status)) {
        git add .
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "git add failed for '$projectName'."
        }

        git commit -m "Seed project wiki from template '$TemplateProjectName'"
        git -c "http.extraheader=$($global:GitAuthHeader)" push
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "git push failed for '$projectName'."
        }

        Write-Host "[INFO] '$projectName': wiki content pushed."
    }
    else {
        Write-Host "[INFO] '$projectName': no changes to push (already identical)."
    }

    Pop-Location
}

# --- MAIN ---

Write-Host ""
Write-Host "This run will:"
Write-Host " - Delete ALL code wikis in ALL projects."
Write-Host " - Ensure each project has a project wiki."
Write-Host " - Seed project wikis from '$TemplateProjectName' only when they do NOT yet contain all template pages."
Write-Host " - Validate each migration by comparing page paths and retry up to $MaxMigrationAttempts times."

if (-not $DryRun -and -not $Force) {
    $answer = Read-Host "Type YES to continue, anything else to abort"
    if ($answer -ne "YES") {
        Write-Host "Aborted."
        exit 1
    }
}

Write-Host ""
Write-Host ">>> Enumerating projects..."
$allProjects = Get-AdoProjects
Write-Host "[INFO] Found $($allProjects.Count) projects."

$templateProject = $allProjects | Where-Object { $_.name -eq $TemplateProjectName } | Select-Object -First 1
if (-not $templateProject) {
    throw "Template project '$TemplateProjectName' not found."
}

$templateInfo = Clone-TemplateWiki -TemplateProject $templateProject -TemplateWikiName $TemplateWikiName
$templatePath   = $templateInfo.Path
$templatePaths  = $templateInfo.PagePaths

foreach ($proj in $allProjects) {
    try {
        Write-Host ""
        Write-Host "============================================================="
        Write-Host "Project: $($proj.name)"

        $projectName = $proj.name

        # Skip re-seeding the template project itself; only clean its code wikis
        $wikis = Get-ProjectWikis -ProjectName $projectName
        Remove-CodeWikisForProject -Project $proj -WikisResponse $wikis

        if ($projectName -eq $TemplateProjectName) {
            Write-Host "[INFO] Template project detected; skip seeding, only cleaned code wikis."
            $Global:SkippedProjects.Add([pscustomobject]@{
                ProjectName = $projectName
                Reason      = "TemplateProject"
            })
            continue
        }

        # Refresh and ensure project wiki exists
        $wikis2   = Get-ProjectWikis -ProjectName $projectName
        $projWiki = Ensure-ProjectWiki -Project $proj -ExistingWikisResponse $wikis2

        # Current page set
        $currentPaths = Get-WikiPagePaths -Wiki $projWiki -ProjectName $projectName
        $hasTemplate  = Test-TemplateCoverage -TemplatePaths $templatePaths -TargetPaths $currentPaths

        if ($hasTemplate) {
            Write-Host "[SKIP] '$projectName': wiki already contains all template pages."
            $Global:SkippedProjects.Add([pscustomobject]@{
                ProjectName = $projectName
                Reason      = "AlreadyHasTemplate"
            })
            continue
        }

        # Needs migration + validation
        $migrationOk = $false
        for ($attempt = 1; $attempt -le $MaxMigrationAttempts; $attempt++) {
            Write-Host "[INFO] '$projectName': migration attempt $attempt/$MaxMigrationAttempts..."

            Sync-ProjectWikiFromTemplate -Project $proj -ProjectWiki $projWiki -TemplatePath $templatePath

            if (-not $DryRun) {
                Write-Host "[INFO] '$projectName': waiting $ValidationDelaySeconds seconds before validation..."
                Start-Sleep -Seconds $ValidationDelaySeconds
            }

            $afterPaths = Get-WikiPagePaths -Wiki $projWiki -ProjectName $projectName
            $afterHasTemplate = Test-TemplateCoverage -TemplatePaths $templatePaths -TargetPaths $afterPaths

            if ($afterHasTemplate) {
                Write-Host "[OK] '$projectName': wiki now contains all template pages."
                $migrationOk = $true
                $Global:MigratedProjects.Add([pscustomobject]@{
                    ProjectName = $projectName
                    Attempts    = $attempt
                })
                break
            }
            else {
                Write-Host "[WARN] '$projectName': validation failed after attempt $attempt; template pages still missing."
            }
        }

        if (-not $migrationOk) {
            Write-Host "[ERROR] '$projectName': migration validation failed after $MaxMigrationAttempts attempts."
            $Global:FailedValidation.Add([pscustomobject]@{
                ProjectName = $projectName
                Attempts    = $MaxMigrationAttempts
            })
        }
    }
    catch {
        Write-Host "[ERROR] '$($proj.name)': $($_.Exception.Message)"
        $Global:ErrorProjects.Add([pscustomobject]@{
            ProjectName = $proj.name
            Error       = $_.Exception.Message
        })
    }
}

Write-Host ""
Write-Host "============================================================="
Write-Host "Run summary:"
Write-Host "  Migrated (validated OK): $($MigratedProjects.Count)"
Write-Host "  Skipped (template / already had template): $($SkippedProjects.Count)"
Write-Host "  Failed validation: $($FailedValidation.Count)"
Write-Host "  Errors: $($ErrorProjects.Count)"

if ($FailedValidation.Count -gt 0) {
    Write-Host ""
    Write-Host "Projects that failed validation:"
    $FailedValidation | Format-Table -AutoSize
}
if ($ErrorProjects.Count -gt 0) {
    Write-Host ""
    Write-Host "Projects with errors:"
    $ErrorProjects | Format-Table -AutoSize
}
