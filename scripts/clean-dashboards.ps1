param(
    # Example: https://ado-server/DefaultCollection
    [Parameter(Mandatory = $true)]
    [string]$CollectionUrl,

    # Personal Access Token with at least Dashboards manage / Project read scope
    [Parameter(Mandatory = $true)]
    [string]$Pat,

    # Dashboard names you want to KEEP
    [string[]]$DashboardNamesToKeep = @("Overview"),

    # Dry run: only log what would be deleted
    [switch]$WhatIf
)

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
$projectApiVersion   = "6.0"
$dashboardApiVersion = "6.0-preview.3"

Write-Host "Collection: $CollectionUrl"
Write-Host "Keeping dashboards named: $($DashboardNamesToKeep -join ', ')"
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
    }
    catch {
        Write-Warning "DELETE failed: $Url"
        Write-Warning $_.Exception.Message
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

    Write-Host ""
    Write-Host "=== Project: $projectName ($projectId) ==="

    # ----- 2a. Project-scoped dashboards -----
    $projDashUrl = "$CollectionUrl/$projectId/_apis/dashboard/dashboards?api-version=$dashboardApiVersion"
    $projDashResponse = Invoke-DevOpsGet -Url $projDashUrl

    if ($projDashResponse -and $projDashResponse.value) {
        foreach ($dash in $projDashResponse.value) {
            $dashName = $dash.name
            $dashId   = $dash.id

            if ($DashboardNamesToKeep -contains $dashName) {
                Write-Host "  [KEEP] Project dashboard '$dashName' ($dashId)"
                continue
            }

            $deleteUrl = "$CollectionUrl/$projectId/_apis/dashboard/dashboards/$($dashId)?api-version=$dashboardApiVersion"

            if ($WhatIf) {
                Write-Host "  [WHATIF] Would DELETE project dashboard '$dashName' ($dashId)"
            }
            else {
                Write-Host "  [DELETE] Project dashboard '$dashName' ($dashId)"
                Invoke-DevOpsDelete -Url $deleteUrl
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

        Write-Host "  -- Team: $teamName ($teamId) --"

        $teamDashUrl = "$CollectionUrl/$projectId/$teamId/_apis/dashboard/dashboards?api-version=$dashboardApiVersion"
        $teamDashResponse = Invoke-DevOpsGet -Url $teamDashUrl

        if (-not ($teamDashResponse -and $teamDashResponse.value)) {
            Write-Host "     No team dashboards found."
            continue
        }

        foreach ($dash in $teamDashResponse.value) {

            $dashName = $dash.name
            $dashId   = $dash.id

            if ($DashboardNamesToKeep -contains $dashName) {
                Write-Host "     [KEEP] Team dashboard '$dashName' ($dashId)"
                continue
            }

            $deleteUrl = "$CollectionUrl/$projectId/$teamId/_apis/dashboard/dashboards/$($dashId)?api-version=$dashboardApiVersion"

            if ($WhatIf) {
                Write-Host "     [WHATIF] Would DELETE team dashboard '$dashName' ($dashId)"
            }
            else {
                Write-Host "     [DELETE] Team dashboard '$dashName' ($dashId)"
                Invoke-DevOpsDelete -Url $deleteUrl
            }
        }
    }
}
