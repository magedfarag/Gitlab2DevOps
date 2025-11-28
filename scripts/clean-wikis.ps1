<#
.SYNOPSIS
    Delete ALL wikis and their backing Git repos for a list of projects.

.DESCRIPTION
    - Reads ADO_COLLECTION_URL and ADO_PAT from a .env file.
    - Accepts a comma-separated list of project names.
    - For each project:
        * Calls /_apis/wiki/wikis to list all wikis.
        * Deletes each wiki (projectWiki and codeWiki).
        * Deletes the backing Git repository if repositoryId is present.

    WARNING: Destructive. No undo.

USAGE EXAMPLES
    .\delete-project-wikis.ps1 -ProjectsCsv "projA,projB,shaheed-system"
    .\delete-project-wikis.ps1 -ProjectsCsv "projA,projB" -EnvPath "C:\Secure\.env" -Force

#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectsCsv,           # e.g. "projA,projB,shaheed-system"

    [string]$EnvPath = ".\.env",

    [switch]$DryRun,                # Log only, no DELETE
    [switch]$Force                  # Skip confirmation
)

# ---------- Basic validation ----------
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

# ---------- REST auth + helpers ----------

$ApiVersion = "7.1"
$Headers = @{
    Authorization = "Basic " + [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes(":$Pat")
    )
}

function Invoke-AdoRestSafe {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST','DELETE','PATCH','PUT')]
        [string]$Method,
        [Parameter(Mandatory=$true)]
        [string]$Uri,
        [object]$Body
    )

    Write-Host "[REST] $Method $Uri" -ForegroundColor DarkCyan

    $result = [pscustomobject]@{
        Success          = $false
        StatusCode       = $null
        StatusDescription= $null
        Data             = $null
        ErrorMessage     = $null
    }

    try {
        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 10
            $resp = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $json -ErrorAction Stop
        }
        else {
            $resp = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ErrorAction Stop
        }

        $result.Success = $true
        $result.Data    = $resp
        return $result
    }
    catch {
        $result.Success = $false
        $result.ErrorMessage = $_.Exception.Message

        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $statusDesc = $_.Exception.Response.StatusDescription
            $result.StatusCode        = $statusCode
            $result.StatusDescription = $statusDesc
        }

        Write-Host "[ERROR] REST failed: $($result.StatusCode) $($result.StatusDescription) - $($result.ErrorMessage)" -ForegroundColor Red
        return $result
    }
}

# ---------- Parse projects ----------
$Projects = $ProjectsCsv.Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne "" }

if ($Projects.Count -eq 0) {
    throw "No valid project names parsed from ProjectsCsv."
}

Write-Host ""
Write-Host "This script will:" -ForegroundColor Cyan
Write-Host " - DELETE ALL wikis (projectWiki + codeWiki) for these projects:" -ForegroundColor Cyan
$Projects | ForEach-Object { Write-Host "   - $_" -ForegroundColor Cyan }
Write-Host " - DELETE ALL backing Git repos for those wikis (where repositoryId exists)." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[INFO] DRY RUN MODE: No actual DELETE calls will be made." -ForegroundColor Yellow
}

if (-not $DryRun -and -not $Force) {
    $answer = Read-Host "Type YES to proceed with DELETES, anything else to abort"
    if ($answer -ne "YES") {
        Write-Host "Aborted by user." -ForegroundColor Yellow
        exit 1
    }
}

# ---------- Main loop per project ----------
foreach ($projectName in $Projects) {

    Write-Host ""
    Write-Host "=============================================================" -ForegroundColor Magenta
    Write-Host "Project: $projectName" -ForegroundColor Magenta

    # 1) List wikis for this project
    $wikisUri = "$CollectionUrl/$projectName/_apis/wiki/wikis?api-version=$ApiVersion"
    $wikiRes  = Invoke-AdoRestSafe -Method GET -Uri $wikisUri -Body $null

    if (-not $wikiRes.Success) {
        Write-Host "[WARN] Skipping project '$projectName' due to wiki API failure." -ForegroundColor Yellow
        continue
    }

    if (-not $wikiRes.Data.value -or $wikiRes.Data.value.Count -eq 0) {
        Write-Host "[INFO] Project '$projectName' has no wikis." -ForegroundColor DarkGray
        continue
    }

    $wikis = $wikiRes.Data.value
    foreach ($wiki in $wikis) {

        Write-Host ""
        Write-Host "[INFO] Found wiki '$($wiki.name)' (id=$($wiki.id), type=$($wiki.type)) in '$projectName'." -ForegroundColor Green

        # 2) Delete the wiki itself
        if ($DryRun) {
            Write-Host "   [DRYRUN] Would DELETE wiki id=$($wiki.id)." -ForegroundColor Yellow
        }
        else {
            $delWikiUri = "$CollectionUrl/$projectName/_apis/wiki/wikis/$($wiki.id)?api-version=$ApiVersion"
            $delWikiRes = Invoke-AdoRestSafe -Method DELETE -Uri $delWikiUri -Body $null

            if ($delWikiRes.Success -or $delWikiRes.StatusCode -eq 404) {
                Write-Host "   [OK] Wiki deleted (or already gone)." -ForegroundColor DarkGreen
            }
            else {
                Write-Host "   [WARN] Wiki delete failed: $($delWikiRes.StatusCode) $($delWikiRes.ErrorMessage)" -ForegroundColor Red
            }
        }

        # 3) Delete backing Git repo if repositoryId present
        if ($wiki.repositoryId) {
            if ($DryRun) {
                Write-Host "   [DRYRUN] Would DELETE Git repo id=$($wiki.repositoryId)." -ForegroundColor Yellow
            }
            else {
                $delRepoUri = "$CollectionUrl/$projectName/_apis/git/repositories/$($wiki.repositoryId)?api-version=$ApiVersion"
                $delRepoRes = Invoke-AdoRestSafe -Method DELETE -Uri $delRepoUri -Body $null

                if ($delRepoRes.Success -or $delRepoRes.StatusCode -eq 404) {
                    Write-Host "   [OK] Backing Git repo deleted (or already gone)." -ForegroundColor DarkGreen
                }
                else {
                    Write-Host "   [WARN] Repo delete failed: $($delRepoRes.StatusCode) $($delRepoRes.ErrorMessage)" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "   [INFO] Wiki has no repositoryId; no repo delete attempted." -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Green
Write-Host "Completed processing all requested projects." -ForegroundColor Green
Write-Host "Use -DryRun first if you want to review actions before real deletes." -ForegroundColor Green
