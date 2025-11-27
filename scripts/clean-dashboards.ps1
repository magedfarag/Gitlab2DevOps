param(
    # Example: https://ado-server/DefaultCollection
    [string]$CollectionUrl,

    # Personal Access Token with at least Dashboards manage / Project read scope
    [string]$Pat,

    # Dashboard names you want to KEEP
    [string[]]$DashboardNamesToKeep = @("Overview"),

    # Dry run: only log what would be deleted
    [switch]$WhatIf
)
#if parameters are missing, read it from .env file
Import-Module -Name "$($PSScriptRoot)\..\modules\core\EnvLoader.psm1"
Import-DotEnvFile -Path "$($PSScriptRoot)\..\.env"

if (-not $Pat) {
    $Pat = $env:ADO_PAT
}

if (-not $CollectionUrl) {
    $CollectionUrl = $env:ADO_COLLECTION_URL
}


# ===== Auth header =====
$base64Pat = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$Pat")
)
$Headers = @{
    Authorization = "Basic $base64Pat"
    "Content-Type" = "application/json"
}

# Adjust if you are on a different Server version:
#  - Server 2020  -> 6.0
#  - Server 2022  -> 7.0
#  - SaaS / latest -> 7.1-preview.3
$projectApiVersion   = "7.1"
$dashboardApiVersion = "7.1-preview.3"

Write-Host "Collection: $CollectionUrl"
#Write-Host "Keeping dashboards named: $($DashboardNamesToKeep -join ', ')"
if ($WhatIf) { Write-Host "Running in WHATIF mode. No deletions will be sent." }

# ===== Helper: GET with basic error handling =====
function Invoke-DevOpsGet {
    param(
        [Parameter(Mandatory = $true)][string]$Url
    )
    try {
        return Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get -ErrorAction Stop
    }
    catch {
        Write-Warning "GET failed: $Url"
        Write-Warning $_.Exception.Message
        return $null
    }
}

# ===== Helper: DELETE with basic error handling =====
function Invoke-DevOpsDelete {
    param(
        [Parameter(Mandatory = $true)][string]$Url
    )
    try {
        Invoke-RestMethod -Uri $Url -Headers $Headers -Method Delete -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warning "DELETE failed: $Url"
        Write-Warning $_.Exception.Message
        return $false
    }
}

# ===== 1. Get all projects =====
$projectsUrl = "$CollectionUrl/_apis/projects?`$top=1000&api-version=$projectApiVersion"
$projectsResponse = Invoke-DevOpsGet -Url $projectsUrl

if (-not $projectsResponse) {
    throw "Failed to get projects. Aborting."
}

$projects = $projectsResponse.value
Write-Host "Found $($projects.Count) projects."

foreach ($project in $projects) {

    $projectId   = $project.id
    $projectName = $project.name
    $projNameEnc = [uri]::EscapeDataString($projectName)
    $projIdEnc   = [uri]::EscapeDataString($projectId)

    Write-Host ""
    Write-Host "=== Project: $projectName ($projectId) ==="

    # ----- 2a. Project-scoped dashboards (prefer project name endpoint) -----
    $projDashUrl = "$CollectionUrl/$projNameEnc/_apis/dashboard/dashboards?api-version=$dashboardApiVersion"
    $projDashResponse = Invoke-DevOpsGet -Url $projDashUrl

    if ($projDashResponse -and $projDashResponse.value) {
        foreach ($dash in $projDashResponse.value) {
            $dashName = $dash.name
            $dashId   = $dash.id
            $dashIdEnc = [uri]::EscapeDataString($dashId)

            # Prefer self URL from API response if available
            $selfUrl = $null
            if ($dash.PSObject.Properties['url'] -and $dash.url) {
                $selfUrl = $dash.url
                if ($selfUrl -notmatch 'api-version=') {
                    $selfUrl = "$selfUrl`?api-version=$dashboardApiVersion"
                }
            }

            if ($WhatIf) {
                Write-Host "  [WHATIF] Would DELETE project dashboard '$dashName' ($dashId)"
            }
            else {
                Write-Host "  [DELETE] Project dashboard '$dashName' ($dashId)"
                $projectDeleteUrls = @(
                    $selfUrl,
                    "$CollectionUrl/$projNameEnc/_apis/dashboard/dashboards/$dashIdEnc?api-version=$dashboardApiVersion",
                    "$CollectionUrl/$projIdEnc/_apis/dashboard/dashboards/$dashIdEnc?api-version=$dashboardApiVersion"
                ) | Where-Object { $_ }
                $deleted = $false
                foreach ($u in $projectDeleteUrls) {
                    if (Invoke-DevOpsDelete -Url $u) { $deleted = $true; break }
                }
                if (-not $deleted) {
                    Write-Warning "  [WARN] Unable to delete project dashboard '$dashName' ($dashId) with available endpoints."
                }
            }
        }
    }
    else {
        Write-Host "  No project-scoped dashboards found."
    }

    # ----- 2b. Teams in project -----
    $teamsUrl = "$CollectionUrl/_apis/projects/$projectId/teams?`$top=200&api-version=$projectApiVersion"
    $teamsResponse = Invoke-DevOpsGet -Url $teamsUrl

    if (-not ($teamsResponse -and $teamsResponse.value)) {
        Write-Host "  No teams found in this project or failed to list teams."
        continue
    }

    foreach ($team in $teamsResponse.value) {

        $teamId   = $team.id
        $teamName = $team.name
        $teamNameEnc = [uri]::EscapeDataString($teamName)
        $teamIdEnc   = [uri]::EscapeDataString($teamId)

        Write-Host "  -- Team: $teamName ($teamId) --"

        # Prefer team endpoints using names, then ids
        $teamDashUrl = "$CollectionUrl/$projNameEnc/$teamNameEnc/_apis/dashboard/dashboards?api-version=$dashboardApiVersion"
        $teamDashResponse = Invoke-DevOpsGet -Url $teamDashUrl

        if (-not ($teamDashResponse -and $teamDashResponse.value)) {
            Write-Host "     No team dashboards found."
            continue
        }

        foreach ($dash in $teamDashResponse.value) {

            $dashName = $dash.name
            $dashId   = $dash.id
            $dashIdEnc = [uri]::EscapeDataString($dashId)

            $selfUrl = $null
            if ($dash.PSObject.Properties['url'] -and $dash.url) {
                $selfUrl = $dash.url
                if ($selfUrl -notmatch 'api-version=') {
                    $selfUrl = "$selfUrl`?api-version=$dashboardApiVersion"
                }
            }

            if ($WhatIf) {
                Write-Host "     [WHATIF] Would DELETE team dashboard '$dashName' ($dashId)"
            }
            else {
                Write-Host "     [DELETE] Team dashboard '$dashName' ($dashId)"
                $teamDeleteUrls = @(
                    $selfUrl,
                    "$CollectionUrl/$projNameEnc/$teamNameEnc/_apis/dashboard/dashboards/$dashIdEnc?api-version=$dashboardApiVersion",
                    "$CollectionUrl/_apis/projects/$projIdEnc/teams/$teamIdEnc/dashboard/dashboards/$dashIdEnc?api-version=$dashboardApiVersion",
                    "$CollectionUrl/$projNameEnc/_apis/dashboard/dashboards/$dashIdEnc?teamId=$teamIdEnc&api-version=$dashboardApiVersion",
                    "$CollectionUrl/_apis/dashboard/dashboards/$dashIdEnc?teamId=$teamIdEnc&projectId=$projIdEnc&api-version=$dashboardApiVersion"
                ) | Where-Object { $_ }
                $deleted = $false
                foreach ($u in $teamDeleteUrls) {
                    if (Invoke-DevOpsDelete -Url $u) { $deleted = $true; break }
                }
                if (-not $deleted) {
                    Write-Warning "     [WARN] Unable to delete team dashboard '$dashName' ($dashId) with available endpoints."
                }
            }
        }
    }
}
