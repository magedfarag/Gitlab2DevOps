<# 
    Delete duplicate dashboards in all Azure DevOps Server projects.

    Rules:
      - For each project, group dashboards by:
          (Name, dashboardScope, groupId)
        and keep exactly ONE dashboard per group.
      - The script deletes every other dashboard in that group.
      - groupId distinguishes team dashboards; project dashboards have empty groupId. 

    Requirements:
      - Azure DevOps Server on-prem.
      - PAT with permissions to delete dashboards:
          * Project dashboards: Project Collection Administrators or equivalent. 
          * Team dashboards: team admin or explicit delete permission.
      - Adjust REST API versions at the top if your server is older than 2022.
#>

# ===================== USER SETTINGS ==========================
# Collection URL (no trailing slash beyond the collection itself)
# Examples:
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
    Write-Host "Loaded environment variables from .env"
} else {
    Write-Error "No .env file found. Please create one with ADO_COLLECTION_URL and ADO_PAT"
    exit 1
}

$CollectionUrl = $env:ADO_COLLECTION_URL

# Personal Access Token
$Pat = $env:ADO_PAT

# Core and Dashboard API versions:
#   7.1 works with Azure DevOps Server 2022.1+.
#   For Azure DevOps Server 2020, change both to 6.0 / 6.0-preview.3. 
$CoreApiVersion      = "7.1"
$DashboardApiVersion = "7.1-preview.3"
# =============================================================

$ErrorActionPreference = "Stop"

# Use TLS 1.2 for older Windows / .NET
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Build PAT auth header  (Basic :PAT) 
$bytes     = [Text.Encoding]::ASCII.GetBytes(":$Pat")
$base64Pat = [Convert]::ToBase64String($bytes)

$Global:AdoHeaders = @{
    Authorization = "Basic $base64Pat"
    "Content-Type" = "application/json"
}

function Invoke-AdoRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET","POST","PUT","PATCH","DELETE")]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$RelativeUrl,

        [Parameter()]
        $Body
    )

    # Build full URL from collection + relative path
    $uri =
        if ($RelativeUrl.StartsWith("http")) {
            $RelativeUrl
        }
        else {
            # Ensure exactly one slash between base and relative
            if ($RelativeUrl.StartsWith("/")) {
                "$CollectionUrl$RelativeUrl"
            }
            else {
                "$CollectionUrl/$RelativeUrl"
            }
        }

    Write-Host "[REST] $Method $uri" -ForegroundColor DarkGray

    $jsonBody = $null
    if ($Body -ne $null) {
        $jsonBody = $Body | ConvertTo-Json -Depth 10
    }

    try {
        if ($jsonBody) {
            return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Global:AdoHeaders -Body $jsonBody
        }
        else {
            return Invoke-RestMethod -Method $Method -Uri $uri -Headers $Global:AdoHeaders
        }
    }
    catch {
        Write-Warning "[REST] $Method $uri failed: $($_.Exception.Message)"
        throw
    }
}

function Get-AllAdoProjects {
    [CmdletBinding()]
    param()

    $projects = @()
    $relative = "/_apis/projects?`$top=1000&api-version=$CoreApiVersion"

    do {
        $resp = Invoke-AdoRest -Method GET -RelativeUrl $relative
        if ($resp.value) {
            $projects += $resp.value
        }

        $token = $resp.continuationToken
        if ($token) {
            $relative = "/_apis/projects?`$top=1000&continuationToken=$token&api-version=$CoreApiVersion"
        }
        else {
            $relative = $null
        }
    } while ($relative)

    return $projects
}

function Remove-DuplicateDashboardsForProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Project
    )

    $projectName = $Project.name
    $projectId   = $Project.id

    Write-Host ""
    Write-Host ">>> Project: $projectName" -ForegroundColor Cyan

    $projEnc = [uri]::EscapeDataString($projectName)
    $listRelative = "/$projEnc/_apis/dashboard/dashboards?api-version=$DashboardApiVersion"

    try {
        $resp = Invoke-AdoRest -Method GET -RelativeUrl $listRelative
    }
    catch {
        Write-Warning "  Failed to list dashboards for project '$projectName'. Skipping."
        return
    }

    $dashboards = $resp.value
    if (-not $dashboards -or $dashboards.Count -le 1) {
        Write-Host "  Dashboards: $($dashboards.Count) → no duplicates." -ForegroundColor DarkGray
        return
    }

    # Build a grouping key: Name + Scope + GroupId.
    # groupId separates different teams; empty groupId means project dashboard. 
    foreach ($d in $dashboards) {
        $name   = $d.name
        $scope  = $d.dashboardScope
        $group  = $d.groupId
        $d | Add-Member -NotePropertyName "DuplicateKey" -NotePropertyValue "$name|$scope|$group" -Force
    }

    $groups = $dashboards | Group-Object -Property DuplicateKey
    $totalDeleted = 0

    foreach ($g in $groups) {
        if ($g.Count -le 1) {
            continue
        }

        # Multiple dashboards share same (Name, Scope, GroupId).
        $key = $g.Name
        Write-Host "  [GROUP] $key → $($g.Count) dashboards" -ForegroundColor Yellow

        # Keep the most recently modified one if available, otherwise the first by id. 
        $keep = $null
        if ($g.Group[0].PSObject.Properties['modifiedDate']) {
            $keep = $g.Group | Sort-Object { $_.modifiedDate } -Descending | Select-Object -First 1
        }
        else {
            $keep = $g.Group | Sort-Object { $_.id } | Select-Object -First 1
        }

        Write-Host ("    [KEEP]   {0}  (Id={1}, Scope={2}, GroupId={3})" -f `
            $keep.name, $keep.id, $keep.dashboardScope, $keep.groupId) -ForegroundColor Green

        $toDelete = $g.Group | Where-Object { $_.id -ne $keep.id }

        foreach ($d in $toDelete) {
            $dashId = $d.id

            # For delete, Azure DevOps supports project id or name in the {project} segment. 
            # We use the project GUID because you already see it in your logs.
            $dashIdEnc = [uri]::EscapeDataString($dashId)
            $dashIdEnc = [uri]::EscapeDataString($dashId)
            $deleteRelative = "/$projectId/_apis/Dashboard/Dashboards/$($dashIdEnc)?api-version=$DashboardApiVersion"
            
            try {
                Write-Host ("    [DELETE] {0}  (Id={1}, Scope={2}, GroupId={3})" -f `
                    $d.name, $d.id, $d.dashboardScope, $d.groupId) -ForegroundColor Red

                Invoke-AdoRest -Method DELETE -RelativeUrl $deleteRelative | Out-Null
                $totalDeleted++
            }
            catch {
                Write-Warning ("    [ERROR] Failed to delete dashboard '{0}' (Id={1}): {2}" -f `
                    $d.name, $d.id, $_.Exception.Message)
            }
        }
    }

    if ($totalDeleted -gt 0) {
        Write-Host "  => Deleted $totalDeleted duplicate dashboard(s) in '$projectName'." -ForegroundColor Magenta
    }
    else {
        Write-Host "  => No duplicates found to delete in '$projectName'." -ForegroundColor DarkGray
    }
}

# ===================== MAIN ==========================
Write-Host "=== REMOVE DUPLICATE DASHBOARDS ACROSS ALL PROJECTS ===" -ForegroundColor Cyan
Write-Host "Collection : $CollectionUrl"
Write-Host "API        : Core=$CoreApiVersion, Dashboards=$DashboardApiVersion"
Write-Host ""

$allProjects = Get-AllAdoProjects
Write-Host "Found $($allProjects.Count) project(s)." -ForegroundColor Cyan

foreach ($p in $allProjects) {
    Remove-DuplicateDashboardsForProject -Project $p
}

Write-Host ""
Write-Host "[DONE] Duplicate dashboard cleanup finished." -ForegroundColor Cyan
