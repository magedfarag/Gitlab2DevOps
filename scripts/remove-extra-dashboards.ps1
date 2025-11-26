# Temporary script to remove all dashboards except default from all Azure DevOps projects
# Uses credentials from .env file

# Load environment variables from .env file
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

# Get credentials from environment
$adoUrl = $env:ADO_COLLECTION_URL
$adoPat = $env:ADO_PAT

if (-not $adoUrl -or -not $adoPat) {
    Write-Error "ADO_COLLECTION_URL and ADO_PAT must be set in .env file"
    exit 1
}

# Extract organization from URL
if ($adoUrl -match 'https://dev\.azure\.com/([^/]+)') {
    $organization = $matches[1]
} elseif ($adoUrl -match 'https://([^/]+)/(.+)') {
    $organization = $matches[2]  # For on-prem servers
} else {
    Write-Error "Could not parse organization from ADO_COLLECTION_URL: $adoUrl"
    exit 1
}

Write-Host "Organization: $organization"
Write-Host "ADO URL: $adoUrl"

# Function to make API calls
function Invoke-AdoApi {
    param(
        [string]$Uri,
        [string]$Method = 'GET',
        [object]$Body = $null
    )

    $headers = @{
        'Authorization' = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$adoPat"))
        'Content-Type' = 'application/json'
    }

    $params = @{
        Uri = $Uri
        Method = $Method
        Headers = $headers
    }

    if ($Body) {
        $params.Body = $Body | ConvertTo-Json
    }

    try {
        $response = Invoke-RestMethod @params
        return $response
    } catch {
        Write-Warning "API call failed: $($_.Exception.Message)"
        return $null
    }
}

# Get all projects
Write-Host "Getting all projects..."
$projectsUrl = "$adoUrl/_apis/projects?api-version=7.1"
$projectsResponse = Invoke-AdoApi -Uri $projectsUrl

if (-not $projectsResponse -or -not $projectsResponse.value) {
    Write-Error "Failed to get projects"
    exit 1
}

$projects = $projectsResponse.value
Write-Host "Found $($projects.Count) projects"

# Process each project
foreach ($project in $projects) {
    $projectName = $project.name
    $projectId = $project.id

    Write-Host "Processing project: $projectName"

    # Get dashboards for this project
    $dashboardsUrl = "$adoUrl/$projectId/_apis/dashboard/dashboards?api-version=7.1-preview.1"
    $dashboardsResponse = Invoke-AdoApi -Uri $dashboardsUrl

    if (-not $dashboardsResponse -or -not $dashboardsResponse.dashboardEntries) {
        Write-Host "  No dashboards found for $projectName"
        continue
    }

    $dashboards = $dashboardsResponse.dashboardEntries
    Write-Host "  Found $($dashboards.Count) dashboards for $projectName"

    if ($dashboards.Count -le 1) {
        Write-Host "  Only $($dashboards.Count) dashboard(s) found, skipping"
        continue
    }

    # Find the default dashboard (usually position 0 or the first one)
    $defaultDashboard = $dashboards | Where-Object { $_.position -eq 0 } | Select-Object -First 1
    if (-not $defaultDashboard) {
        $defaultDashboard = $dashboards[0]  # Fallback to first dashboard
    }

    Write-Host "  Keeping default dashboard: $($defaultDashboard.name) (ID: $($defaultDashboard.id))"

    # Delete all other dashboards
    foreach ($dashboard in $dashboards) {
        if ($dashboard.id -eq $defaultDashboard.id) {
            continue
        }

        Write-Host "  Deleting dashboard: $($dashboard.name) (ID: $($dashboard.id))"
        $deleteUrl = "$adoUrl/$projectId/_apis/dashboard/dashboards/$($dashboard.id)?api-version=7.1-preview.1"
        $deleteResponse = Invoke-AdoApi -Uri $deleteUrl -Method 'DELETE'

        if ($deleteResponse) {
            Write-Host "    Successfully deleted"
        } else {
            Write-Host "    Failed to delete"
        }
    }
}

Write-Host "Script completed!"