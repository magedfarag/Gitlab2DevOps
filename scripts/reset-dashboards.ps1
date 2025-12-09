<#
.SYNOPSIS
    Reset and standardize dashboards for all projects in an Azure DevOps Server 2022 collection.

.DESCRIPTION
    - Reads connection/config parameters from a .env file.
    - Optionally deletes ALL dashboards for ALL teams in ALL projects (per collection).
    - Creates four opinionated SDLC dashboards per team:
        01 - Business / Product
        02 - Engineering / Dev
        03 - Quality / Testing
        04 - Operations / Release

.PARAMETER EnvPath
    Path to the .env file (defaults to ".env" in the current directory).

.PARAMETER ClearExistingDashboards
    When set, delete every existing dashboard before creating the new ones.

.PARAMETER ProjectInclude
    Optional list of project names to include (case-insensitive). If specified, only these projects run.

.PARAMETER ProjectExclude
    Optional list of project names to exclude (case-insensitive).

.PARAMETER DryRun
    Simulate actions (log what would happen) but do not call the REST APIs that modify dashboards.

#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $EnvPath = ".env",
    [switch] $ClearExistingDashboards,
    [string[]] $ProjectInclude,
    [string[]] $ProjectExclude,
    [switch] $Force,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Generate a unique run ID to avoid conflicts with failed previous runs
$script:RunId = Get-Random -Minimum 10000 -Maximum 99999
Write-Verbose "[INIT] Generated unique run ID: $script:RunId"

$markdownContribution   = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget"
$markdownConfig         = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget.Configuration"
$teamMembersContribution= "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.TeamMembersWidget"
$newWitContribution     = "ms.vss-dashboards-web.new-work-item-widget"
$newWitConfig           = "ms.vss-dashboards-web.new-work-item-widget.configuration"

$velocityContribution        = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.VelocityWidget"
$cumulativeFlowContribution  = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.CumulativeFlowDiagramWidget"
$cycleTimeContribution       = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.CycleTimeWidget"
$leadTimeContribution        = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.LeadTimeWidget"
$queryScalarContribution     = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
$buildHistogramContribution  = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.BuildHistogramWidget"
$codeScalarContribution      = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.CodeScalarWidget"
$sprintBurndownContribution  = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.SprintBurndownWidget"

$witChartContribution        = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.WitChartWidget"



$settingsVersion = @{
    major = 1
    minor = 0
    patch = 0
}
Write-Host "[INFO] Loading environment from '$EnvPath'..." -ForegroundColor Cyan

if (-not (Test-Path $EnvPath)) {
    throw "Environment file '$EnvPath' not found. Please ensure it exists and contains required ADO_COLLECTION_URL and ADO_PAT."
}

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

    $config = $envVars
$collection = $envVars["ADO_COLLECTION_URL"]
$collection = $collection.Trim('/')
[Environment]::SetEnvironmentVariable("ADO_COLLECTION_URL", $collection, "Process")

$pat = $envVars["ADO_PAT"]
[Environment]::SetEnvironmentVariable("ADO_PAT", $pat, "Process")

$coreApiOverride = $envVars["ADO_CORE_API_VERSION"]
if ($coreApiOverride) {
    [Environment]::SetEnvironmentVariable("ADO_CORE_API_VERSION", $coreApiOverride, "Process")
}

$dashboardApiOverride = $envVars["ADO_DASHBOARD_API_VERSION"]
if ($dashboardApiOverride) {
    [Environment]::SetEnvironmentVariable("ADO_DASHBOARD_API_VERSION", $dashboardApiOverride, "Process")
}

$script:CoreApiVersion      = if ($coreApiOverride)      { $coreApiOverride }      else { '7.0' }
$script:DashboardApiVersion = if ($dashboardApiOverride) { $dashboardApiOverride } else { '7.0-preview.2' }

# For on-prem ADO, TLS 1.2 avoids handshake issues
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$patBytes   = [Text.Encoding]::ASCII.GetBytes(":$pat")
$patEncoded = [Convert]::ToBase64String($patBytes)

$script:BaseUrl = $collection
$script:DefaultHeaders = @{
    Authorization  = "Basic $patEncoded"
    "Content-Type" = "application/json"
}

Write-Host "BaseUrl       : $($script:BaseUrl)" -ForegroundColor Cyan
Write-Host "Core API      : $($script:CoreApiVersion)" -ForegroundColor Cyan
Write-Host "Dashboard API : $($script:DashboardApiVersion)" -ForegroundColor Cyan
Write-Host "DryRun        : $DryRun" -ForegroundColor Cyan
Write-Host "ClearExisting : $ClearExistingDashboards" -ForegroundColor Cyan

# -------------------------------------------------------
# 3. Generic REST helper (defensive on RelativeUrl)
# -------------------------------------------------------
function Invoke-AdoRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET','POST','PUT','PATCH','DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $RelativeUrl,

        [Parameter()]
        [object] $Body,

        [switch] $IgnoreNotFound,

        [hashtable] $AdditionalHeaders
    )

    if ([string]::IsNullOrWhiteSpace($RelativeUrl)) {
        throw "Internal error: RelativeUrl is null or empty in Invoke-AdoRest."
    }

    $uri = "$($script:BaseUrl)/$($RelativeUrl)"

    $headers = $script:DefaultHeaders.Clone()
    if ($AdditionalHeaders) {
        foreach ($key in $AdditionalHeaders.Keys) {
            $headers[$key] = $AdditionalHeaders[$key]
        }
    }

    $params = @{
        Method  = $Method
        Uri     = "$($script:BaseUrl)/$($RelativeUrl)"
        Headers = $headers
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Body = ($Body | ConvertTo-Json -Depth 12)
    }

    Write-Verbose "[REST] $Method $uri"

    try {
        Write-Verbose "[REST-INVOKE] Executing $Method request to $uri"
        return Invoke-RestMethod @params
    }
    catch [System.Net.WebException] {
        $response = $_.Exception.Response
        if ($response -and $response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound -and $IgnoreNotFound) {
            Write-Verbose "[REST-IGNORED] 404 Not Found: $uri"
            return $null
        }
        Write-Verbose "[REST-ERROR] $Method $uri failed: $($_.Exception.Message)"
        throw
    }
}

# -------------------------------------------------------
# 4. Projects, Teams, Dashboards helpers
# -------------------------------------------------------
function Get-AdoProjects {
    [CmdletBinding()]
    param()

    Write-Verbose "[PROJECTS] Fetching all projects from collection..."
    # Projects - List
    $relative = "_apis/projects?`$top=1000&api-version=$($script:CoreApiVersion)"
    $result   = Invoke-AdoRest -Method GET -RelativeUrl $relative

    if (-not $result) { 
        Write-Verbose "[PROJECTS] No projects found"
        return @() 
    }
    $projects = if ($result.value) { @($result.value) } else { @() }
    Write-Verbose "[PROJECTS] Found $($projects.Count) project(s)"
    return $projects
}

function Get-AdoTeams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId
    )

    Write-Verbose "[TEAMS] Fetching teams for project $ProjectId..."
    # Teams - Get Teams
    $relative = "_apis/projects/$ProjectId/teams?`$top=100&api-version=$($script:CoreApiVersion)"
    $result   = Invoke-AdoRest -Method GET -RelativeUrl $relative

    if (-not $result) { 
        Write-Verbose "[TEAMS] No teams found for project $ProjectId"
        return @() 
    }
    $teams = if ($result.value) { @($result.value) } else { @() }
    Write-Verbose "[TEAMS] Found $($teams.Count) team(s) in project $ProjectId"
    return $teams
}

function Get-AdoDashboards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId
    )

    Write-Verbose "[DASHBOARDS] Fetching dashboards for project $ProjectId, team $TeamId..."
    # Dashboards - List
    $relative = "$ProjectId/$TeamId/_apis/dashboard/dashboards?api-version=$($script:DashboardApiVersion)"
    $result   = Invoke-AdoRest -Method GET -RelativeUrl $relative -IgnoreNotFound

    if (-not $result) { 
        Write-Verbose "[DASHBOARDS] No dashboards found for team $TeamId"
        return @() 
    }
    $dashboards = if ($result.dashboardEntries) { @($result.dashboardEntries) } elseif ($result.dashboards) { @($result.dashboards) } else { @() }
    Write-Verbose "[DASHBOARDS] Found $($dashboards.Count) dashboard(s) in team $TeamId"
    return $dashboards
}

function Get-AdoDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId,

        [Parameter(Mandatory)]
        [string] $DashboardId
    )

    # Dashboards - Get
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"
    return Invoke-AdoRest -Method GET -RelativeUrl $relative
}

function Remove-AdoDashboard {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId,

        [Parameter(Mandatory)]
        [string] $DashboardId
    )

    Write-Verbose "[DASHBOARD-DELETE] Deleting dashboard $DashboardId from project $ProjectId, team $TeamId"
    # Dashboards - Delete
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"

    if ($PSCmdlet.ShouldProcess("Dashboard $DashboardId", "DELETE")) {
        Invoke-AdoRest -Method DELETE -RelativeUrl $relative -IgnoreNotFound | Out-Null
        Write-Verbose "[DASHBOARD-DELETE] Successfully deleted dashboard $DashboardId"
    }
}

function Clean-TempDashboards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,
        [Parameter(Mandatory)]
        [string] $TeamId
    )

    Write-Verbose "[CLEANUP-TEMP] Cleaning temporary dashboards from project $ProjectId, team $TeamId..."
    $dashboards = Get-AdoDashboards -ProjectId $ProjectId -TeamId $TeamId
    if (-not $dashboards) { 
        Write-Verbose "[CLEANUP-TEMP] No dashboards found to clean"
        return 
    }

    $tempCount = 0
    foreach ($dash in $dashboards) {
        # Match both old [TMP] format and new [TMP-XXXXX] format
        if ($dash.name -like "[TMP]*" -or $dash.name -match '^\[TMP-\d{5}\]') {
            try {
                Write-Verbose "[CLEANUP-TEMP] Removing temporary dashboard: $($dash.name)"
                Remove-AdoDashboard -ProjectId $ProjectId -TeamId $TeamId -DashboardId $dash.id
                $tempCount++
            } catch {
                Write-Warning "Failed to delete temporary dashboard '$($dash.name)' in project '$ProjectId' team '$TeamId'. $_"
            }
        }
    }
    Write-Verbose "[CLEANUP-TEMP] Cleaned $tempCount temporary dashboard(s)"
}




function Set-AdoDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId,

        [Parameter(Mandatory)]
        [string] $DashboardId,

        [Parameter(Mandatory)]
        [object] $DashboardDef
    )

    # Dashboards - Update using PATCH method for partial updates
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"

    # Remove eTag from the body as it should be in headers if needed
    $bodyToSend = [ordered]@{}
    foreach ($key in $DashboardDef.Keys) {
        if ($key -ne 'eTag' -and $key -ne 'id' -and $key -ne '_links') {
            $bodyToSend[$key] = $DashboardDef[$key]
        }
    }

    $additionalHeaders = @{}
    if ($DashboardDef -and $DashboardDef.PSObject.Properties.Name -contains 'eTag' -and $DashboardDef.eTag) {
        $additionalHeaders["If-Match"] = $DashboardDef.eTag
    }

    if ($additionalHeaders.Count -gt 0) {
        return Invoke-AdoRest -Method PUT -RelativeUrl $relative -Body $bodyToSend -AdditionalHeaders $additionalHeaders
    }
    else {
        return Invoke-AdoRest -Method PUT -RelativeUrl $relative -Body $bodyToSend
    }
}




function New-AdoDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId,

        [Parameter(Mandatory)]
        [hashtable] $DashboardDef
    )

    # Dashboards - Create
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards?api-version=$($script:DashboardApiVersion)"
    return Invoke-AdoRest -Method POST -RelativeUrl $relative -Body $DashboardDef
}



# -------------------------------------------------------
# 5. Recommended SDLC dashboards (widgets)
# -------------------------------------------------------
function Clean-OldQueries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,
        [Parameter(Mandatory)]
        [string] $TeamId,
        [Parameter(Mandatory)]
        [string] $FolderId
    )

    Write-Verbose "[QUERY-CLEANUP] Cleaning old/temporary queries from project $ProjectId, folder $FolderId..."
    $apiVersion = "7.1"
    $listRelative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?$depth=2&api-version=' + $apiVersion

    $existing = Invoke-AdoRest -Method GET -RelativeUrl $listRelative -IgnoreNotFound
    if (-not $existing) { 
        Write-Verbose "[QUERY-CLEANUP] No queries found to clean"
        return 
    }

    $children = @()
    try {
        if ($existing.children) {
            $children = $existing.children
        } elseif ($existing.value) {
            $children = $existing.value
        } else {
            $children = @($existing)
        }
    } catch {
        $children = @($existing)
    }

    Write-Verbose "[QUERY-CLEANUP] Found $($children.Count) item(s) to examine in folder"
    $cleanedCount = 0
    foreach ($item in $children) {
        if (-not $item.name) { continue }

        # Clean up any temporary or legacy queries:
        # - Names starting with [TMP] or [TMP-XXXXX]
        # - Legacy random-suffix pattern "(R123)"
        if ($item.name -like "[TMP]*" -or $item.name -match '^\[TMP-\d{5}\]' -or $item.name -match '\(R\d+\)$') {
            $deleteRelative = $ProjectId + '/_apis/wit/queries/' + $item.id + '?api-version=' + $apiVersion
            try {
                Write-Verbose "[QUERY-CLEANUP] Deleting temporary/legacy query: $($item.name)"
                Invoke-AdoRest -Method DELETE -RelativeUrl $deleteRelative -IgnoreNotFound | Out-Null
                $cleanedCount++
            } catch {
                Write-Warning "Failed to delete temporary/legacy query '$($item.name)' in project '$ProjectId'. $_"
            }
        }
    }
    Write-Verbose "[QUERY-CLEANUP] Cleaned $cleanedCount old/temporary query(ies)"
}


function Get-SharedQueriesFolderId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId
    )

    Write-Verbose "[QUERIES] Fetching Shared Queries folder ID for project $ProjectId..."
    $relative = $ProjectId + '/_apis/wit/queries?api-version=7.1'
    $result = Invoke-AdoRest -Method GET -RelativeUrl $relative

    $queries = try { $result.value } catch { $result }
    $shared = $queries | Where-Object { $_.name -eq "Shared Queries" -and $_.isFolder }
    if (-not $shared) {
        throw "Shared Queries folder not found for project $ProjectId"
    }
    Write-Verbose "[QUERIES] Found Shared Queries folder with ID: $($shared.id)"
    return $shared.id
}

function New-Query {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId,

        [Parameter(Mandatory)]
        [string] $FolderId,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Wiql
    )

    $apiVersion = "7.1"
    $targetName = $Name
    $tempName   = "[TMP-$($script:RunId)] $Name"

    # Helper: list all children under the folder
    $listRelative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?$depth=1&api-version=' + $apiVersion
    $existing = Invoke-AdoRest -Method GET -RelativeUrl $listRelative -IgnoreNotFound

    $children = @()
    if ($existing) {
        try {
            if ($existing.children) {
                $children = $existing.children
            } elseif ($existing.value) {
                $children = $existing.value
            } else {
                $children = @($existing)
            }
        } catch {
            $children = @($existing)
        }
    }

    # 1) Remove any leftover temporary queries for this name
    Write-Verbose "[QUERY-CREATE] Removing any leftover temporary query: $tempName"
    foreach ($item in $children) {
        if ($item.name -eq $tempName) {
            $deleteTempRelative = $ProjectId + '/_apis/wit/queries/' + $item.id + '?api-version=' + $apiVersion
            try {
                Write-Verbose "[QUERY-CREATE] Deleting leftover temporary query: $($item.name)"
                Invoke-AdoRest -Method DELETE -RelativeUrl $deleteTempRelative -IgnoreNotFound | Out-Null
            } catch {
                Write-Warning "Failed to delete temporary query '$tempName' in project '$ProjectId'. $_"
            }
        }
    }

    # 2) Create a new query with the temporary name
    Write-Verbose "[QUERY-CREATE] Creating new query: $tempName with WIQL pattern"
    $body = @{
        name = $tempName
        wiql = $Wiql
    }

    $createRelative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?api-version=' + $apiVersion

    $created = $null
    try {
        Write-Verbose "[QUERY-CREATE] Posting query creation request to $createRelative"
        $created = Invoke-AdoRest -Method POST -RelativeUrl $createRelative -Body $body
    } catch {
        # If we hit a naming conflict or similar, try to clean conflicting items and retry once
        Write-Warning "Failed to create temporary query '$tempName' under folder '$FolderId' for project '$ProjectId'. Attempting cleanup and retry. $_"
        Write-Verbose "[QUERY-CREATE] Attempting cleanup and retry for query: $tempName"

        $existing = Invoke-AdoRest -Method GET -RelativeUrl $listRelative -IgnoreNotFound
        $children = @()
        if ($existing) {
            try {
                if ($existing.children) {
                    $children = $existing.children
                } elseif ($existing.value) {
                    $children = $existing.value
                } else {
                    $children = @($existing)
                }
            } catch {
                $children = @($existing)
            }
        }

        foreach ($item in $children) {
            if ($item.name -eq $tempName -or $item.name -eq $targetName) {
                $deleteRelative = $ProjectId + '/_apis/wit/queries/' + $item.id + '?api-version=' + $apiVersion
                try {
                    Invoke-AdoRest -Method DELETE -RelativeUrl $deleteRelative -IgnoreNotFound | Out-Null
                } catch {
                    Write-Warning "Failed to delete conflicting query or folder '$($item.name)' in project '$ProjectId'. $_"
                }
            }
        }

        # Retry once
        try {
            $created = Invoke-AdoRest -Method POST -RelativeUrl $createRelative -Body $body
        } catch {
            Write-Warning "Second attempt to create query '$tempName' failed in project '$ProjectId'. $_"
            return $null
        }
    }

    if (-not $created -or -not $created.id) {
        Write-Warning "Query '$tempName' creation returned no id."
        Write-Verbose "[QUERY-CREATE] Failed to create query: $tempName"
        return $null
    }

    $newId = $created.id
    Write-Verbose "[QUERY-CREATE] Successfully created temporary query with ID: $newId"

    # 3) Delete any existing query or folder with the final name
    Write-Verbose "[QUERY-CREATE] Removing any conflicting final-named query: $targetName"
    $existing = Invoke-AdoRest -Method GET -RelativeUrl $listRelative -IgnoreNotFound
    $children = @()
    if ($existing) {
        try {
            if ($existing.children) {
                $children = $existing.children
            } elseif ($existing.value) {
                $children = $existing.value
            } else {
                $children = @($existing)
            }
        } catch {
            $children = @($existing)
        }
    }

    foreach ($item in $children) {
        if ($item.name -eq $targetName -and $item.id -ne $newId) {
            $deleteFinalRelative = $ProjectId + '/_apis/wit/queries/' + $item.id + '?api-version=' + $apiVersion
            try {
                Write-Verbose "[QUERY-CREATE] Deleting conflicting query: $($item.name) (ID: $($item.id))"
                Invoke-AdoRest -Method DELETE -RelativeUrl $deleteFinalRelative -IgnoreNotFound | Out-Null
            } catch {
                Write-Warning "Failed to delete existing query or folder '$targetName' in project '$ProjectId'. $_"
            }
        }
    }

    # 4) Rename the new query from temporary name to final name
    Write-Verbose "[QUERY-CREATE] Renaming query from '$tempName' to final name '$targetName'"
    $updateBody = @{
        name = $targetName
        wiql = $Wiql
    }

    $updateRelative = $ProjectId + '/_apis/wit/queries/' + $newId + '?api-version=' + $apiVersion

    try {
        Write-Verbose "[QUERY-CREATE] Sending PATCH request to rename query ID: $newId"
        $updated = Invoke-AdoRest -Method PATCH -RelativeUrl $updateRelative -Body $updateBody
        if ($updated -and $updated.id) {
            $newId = $updated.id
            Write-Verbose "[QUERY-CREATE] Successfully renamed query to: $targetName (ID: $newId)"
        }
    } catch {
        Write-Warning "Failed to rename query '$tempName' to '$targetName' in project '$ProjectId'. $_"
        Write-Verbose "[QUERY-CREATE] Failed to rename query with ID: $newId"
    }

    Write-Verbose "[QUERY-CREATE] Query creation complete. Final ID: $newId"
    return $newId
}


function Get-RecommendedDashboardDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectName,

        [Parameter(Mandatory)]
        [string] $TeamName,

        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId
    )

    # Project-level URLs (default team) following standard Azure DevOps hubs
    $projectBase = "$collection/$ProjectName"
    $boardsUrl   = "$projectBase/_boards/board"
    $reposUrl    = "$projectBase/_git"
    $buildsUrl   = "$projectBase/_build"
    $wikiUrl     = "$projectBase/_wiki/wikis"
    $testPlansUrl= "$projectBase/_testPlans"
    $workItemsUrl= "$projectBase/_workitems"

    # Dashboard Markdown Templates
#-----------------------------------------------------------------------------------------------------------------------------------------

# Dashboard Configuration Variables
$TeamAreaPath = $ProjectName
$CurrentIteration = "@CurrentIteration"
$PastIterations = "@CurrentIteration - 3"
$FutureIterations = "@CurrentIteration + 3"

    $folderId = Get-SharedQueriesFolderId -ProjectId $ProjectId -TeamId $TeamId

    Clean-OldQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId

# ============================================
# BUSINESS / PRODUCT DASHBOARD CONFIGURATION
# ============================================

# ============================================
# BUSINESS / PRODUCT DASHBOARD CONFIGURATION
# ============================================

# Load queries from external JSON file
$queryConfigPath = Join-Path $PSScriptRoot "dashboard-queries.json"
if (-not (Test-Path $queryConfigPath)) {
    throw "Query configuration file not found: $queryConfigPath"
}
$queryConfig = Get-Content $queryConfigPath -Raw | ConvertFrom-Json

$businessQueries = $queryConfig.Business
$devQueries = $queryConfig.Engineering
$qaQueries = $queryConfig.Quality
$opsQueries = $queryConfig.Operations

    $dashboards = @()

    function New-SimpleDashboardDef {
        param(
            [string] $Name,
            [int]    $Position,
            [array]  $Queries,
            [string] $ProjectId,
            [string] $TeamId,
            [string] $FolderId
        )

        $widgets = @()

        # Load widget configuration from JSON file
        $configPath = Join-Path $PSScriptRoot "dashboard-widgets-config.json"
        if (-not (Test-Path $configPath)) {
            Write-Warning "[WIDGET-CONFIG] Configuration file not found: $configPath. Using fallback configuration."
            $widgetConfig = @{ "Fallback" = @() }
        } else {
            try {
                $widgetConfig = Get-Content $configPath -Raw | ConvertFrom-Json -AsHashtable
                Write-Verbose "[WIDGET-CONFIG] Loaded widget configuration from $configPath"
            } catch {
                Write-Warning "[WIDGET-CONFIG] Failed to load configuration file: $_. Using fallback configuration."
                $widgetConfig = @{ "Fallback" = @() }
            }
        }

        # Determine which widget set to use based on dashboard name
        $widgetSetName = "Fallback"
        if ($Name -like "*Business*") { $widgetSetName = "Business" }
        elseif ($Name -like "*Engineering*") { $widgetSetName = "Engineering" }
        elseif ($Name -like "*Quality*") { $widgetSetName = "Quality" }
        elseif ($Name -like "*Operations*") { $widgetSetName = "Operations" }

        $widgetDefinitions = $widgetConfig[$widgetSetName]
        if (-not $widgetDefinitions) {
            Write-Warning "[WIDGET-CONFIG] No widget definitions found for '$widgetSetName'. Using Fallback."
            $widgetDefinitions = $widgetConfig["Fallback"]
        }

        Write-Verbose "[WIDGET-CONFIG] Using widget set: $widgetSetName with $($widgetDefinitions.Count) widget(s)"

        # Build widgets from configuration
        $row = 1
        $currentColumn = 1
        foreach ($widgetDef in $widgetDefinitions) {
            # Handle optional row gap (for Fallback's second KPI Count)
            # Access hashtable properties safely
            $hasRowGap = $false
            if ($widgetDef -is [hashtable]) {
                $hasRowGap = $widgetDef.ContainsKey('addRowGap') -and $widgetDef['addRowGap']
            } elseif ($widgetDef.PSObject.Properties['addRowGap']) {
                $hasRowGap = $widgetDef.addRowGap
            }
            
            if ($hasRowGap) {
                $row += 3
            }

            # Get properties safely from hashtable or PSObject
            $widgetName = if ($widgetDef -is [hashtable]) { $widgetDef['name'] } else { $widgetDef.name }
            $widgetColumn = if ($widgetDef -is [hashtable]) { $widgetDef['column'] } else { $widgetDef.column }
            $widgetContribId = if ($widgetDef -is [hashtable]) { $widgetDef['contributionId'] } else { $widgetDef.contributionId }

            # Map contribution ID string to actual variable
            $contributionIdValue = switch ($widgetContribId) {
                "cumulativeFlowContribution" { $cumulativeFlowContribution }
                "velocityContribution" { $velocityContribution }
                "leadTimeContribution" { $leadTimeContribution }
                "cycleTimeContribution" { $cycleTimeContribution }
                "sprintBurndownContribution" { $sprintBurndownContribution }
                "queryScalarContribution" { $queryScalarContribution }
                "buildHistogramContribution" { $buildHistogramContribution }
                "codeScalarContribution" { $codeScalarContribution }
                "witChartContribution" { $witChartContribution }
                default { 
                    Write-Warning "[WIDGET-CONFIG] Unknown contribution ID: $widgetContribId"
                    $null 
                }
            }

            if ($null -eq $contributionIdValue) {
                Write-Warning "[WIDGET-CONFIG] Skipping widget '$widgetName' - invalid contribution ID"
                continue
            }

            $widgets += @{
                name            = $widgetName
                position        = @{ row = $row; column = $widgetColumn }
                size            = @{ rowSpan = 3; columnSpan = 5 }
                settings        = $null
                settingsVersion = $settingsVersion
                contributionId  = $contributionIdValue
            }

            # Track column to increment row after every 2 widgets (columns 1 and 6)
            if ($widgetColumn -eq 6) {
                $row += 3
            }
        }

        $analyticsCount  = $widgets.Count
        $maxPerDashboard = 12
        $maxQueryWidgets = [math]::Max(0, $maxPerDashboard - $analyticsCount)



        # $widgets += @{
        #     name                        = "New Work Item"
        #     position                    = @{ row = 1; column = 1 }
        #     size                        = @{ rowSpan = 1; columnSpan = 2 }
        #     settings                    = $null
        #     settingsVersion             = $settingsVersion
        #     contributionId              = $newWitContribution
        #     configurationContributionId = $newWitConfig
        # }
        # Add query result widgets (up to remaining slots, total 12 widgets per dashboard)
        if (-not $row) { $row = 1 }
        $queryIndex = 0
        foreach ($query in $Queries) {
            if ($queryIndex -ge $maxQueryWidgets) { break }

            $queryId = New-Query -ProjectId $ProjectId -TeamId $TeamId -FolderId $FolderId -Name $query.Name -Wiql $query.Wiql
            if($null -eq $queryId) {
                Write-Warning "[WIDGET-CREATE] Skipping query widget '$($query.Name)' - query creation failed"
                continue
            }
            
            # Verify the query exists before creating the widget
            Write-Verbose "[WIDGET-CREATE] Verifying query exists: $queryId"
            $apiVersion = "7.1"
            $verifyRelative = "$ProjectId/_apis/wit/queries/$queryId`?api-version=$apiVersion"
            $queryExists = $null
            try {
                $queryExists = Invoke-AdoRest -Method GET -RelativeUrl $verifyRelative -IgnoreNotFound
            } catch {
                Write-Warning "[WIDGET-CREATE] Failed to verify query '$($query.Name)' (ID: $queryId): $_"
            }
            
            if (-not $queryExists -or -not $queryExists.id) {
                Write-Warning "[WIDGET-CREATE] Skipping query widget '$($query.Name)' - query does not exist or is inaccessible (ID: $queryId)"
                continue
            }
            
            Write-Verbose "[WIDGET-CREATE] Query verified successfully: $($queryExists.name) (ID: $queryId)"
            $queryIndex++
            
            # Build query widget - use Query Tile Widget which displays query results
            # Alternate between left (column 1) and right (column 6) columns
            $column = if (($queryIndex % 2) -eq 1) { 1 } else { 6 }
            
            # Query Tile Widget settings - requires queryId and queryName in settings JSON
            $querySettings = @{
                queryId = $queryId
                queryName = $queryExists.name
            } | ConvertTo-Json -Compress
            
            Write-Verbose "[WIDGET-CREATE] Creating query tile widget: $($query.Name) at row $row, column $column (Query ID: $queryId)"
            
            $widgets += @{
                name                        = $query.Name
                position                    = @{ row = $row; column = $column }
                size                        = @{ rowSpan = 2; columnSpan = 5 }
                settings                    = $querySettings
                settingsVersion             = @{ major = 1; minor = 0; patch = 0 }
                contributionId              = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryTileWidget"
            }
            
            # Move to next row after every 2 widgets
            if (($queryIndex % 2) -eq 0) {
                $row += 2
            }
        }

        return @{
            name            = $Name
            position        = $Position
            refreshInterval = 0
            dashboardScope  = "project"
            ownerId         = $TeamId
            widgets         = $widgets
        }
    }

    $dashboards += New-SimpleDashboardDef -Name "Business Product"   -Position 1 -Queries $businessQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId
    $dashboards += New-SimpleDashboardDef -Name "Engineering Dev"    -Position 2 -Queries $devQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId
    $dashboards += New-SimpleDashboardDef -Name "Quality Testing"    -Position 3 -Queries $qaQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId
    $dashboards += New-SimpleDashboardDef -Name "Operations Release" -Position 4 -Queries $opsQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId

    return $dashboards
}

# -------------------------------------------------------
# 6. Main orchestration
# -------------------------------------------------------
$projects = @(Get-AdoProjects)
Write-Host "[PROJECTS] Total projects found: $($projects.Count)" -ForegroundColor Cyan

$createdCount = 0
$deletedCount = 0
$projectsProcessed = 0
$teamsProcessed = 0

if ($ProjectInclude) {
    $includeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ProjectInclude | ForEach-Object { if ($_){ [void]$includeSet.Add($_) } }
    $projects = $projects | Where-Object { $includeSet.Contains($_.name) }
    Write-Host "[FILTER] Applied include filter. Projects remaining: $($projects.Count)" -ForegroundColor Cyan
}

if ($ProjectExclude) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ProjectExclude | ForEach-Object { if ($_){ [void]$excludeSet.Add($_) } }
    $projects = $projects | Where-Object { -not $excludeSet.Contains($_.name) }
    Write-Host "[FILTER] Applied exclude filter. Projects remaining: $($projects.Count)" -ForegroundColor Cyan
}

if ($projects.Count -eq 0) {
    Write-Warning "[ERROR] No projects found after filters. Nothing to do."
    return
}

Write-Host "[PROCESSING] Starting to process $($projects.Count) project(s)..." -ForegroundColor Yellow
Write-Verbose "[PROCESSING] DryRun mode: $DryRun | ClearExisting mode: $ClearExistingDashboards"

$projectIndex = 0
foreach ($project in $projects) {
    $projectIndex++
    $projectsProcessed++
    Write-Progress -Activity "Processing Projects" -Status "[$projectIndex/$($projects.Count)] $($project.name)" -PercentComplete (($projectIndex / $projects.Count) * 100) -Id 1

    Write-Host ""
    Write-Host "[PROJECT] [$projectIndex/$($projects.Count)] Processing: $($project.name) [ID: $($project.id)]" -ForegroundColor Magenta
    Write-Verbose "[PROJECT] Starting project processing: $($project.name)"

    $teams = @(Get-AdoTeams -ProjectId $project.id)
    if ($teams.Count -eq 0) {
        Write-Host "[PROJECT-SKIP] No teams found in project '$($project.name)'. Skipping." -ForegroundColor Yellow
        Write-Verbose "[PROJECT] Skipped project $($project.name) - no teams found"
        continue
    }
    Write-Host "[PROJECT] Found $($teams.Count) team(s) in project $($project.name)" -ForegroundColor Cyan

    # Use the default team for project-level dashboards
    $defaultTeam = $teams | Where-Object { $_.name -eq "$($project.name) Team" } | Select-Object -First 1
    if (-not $defaultTeam) {
        # If no team matches project name, use first team
        $defaultTeam = $teams[0]
    }
    
    Write-Host "    [PROJECT-DASHBOARD] Using team '$($defaultTeam.name)' for project-level dashboards" -ForegroundColor Cyan
    Write-Verbose "[PROJECT] Processing project-level dashboards using team: $($defaultTeam.name) [ID: $($defaultTeam.id)]"

    # 0) Clean any temporary dashboards before proceeding
    Write-Host "      [PROJECT-CLEANUP] Cleaning temporary dashboards..." -ForegroundColor DarkGray
    Clean-TempDashboards -ProjectId $project.id -TeamId $defaultTeam.id

    # 1) Read current dashboards safely as array (after cleanup)
    Write-Host "      [PROJECT-READ] Reading current dashboard list..." -ForegroundColor DarkGray
    $dashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $defaultTeam.id)
    Write-Host "      [PROJECT-READ] Found $($dashboards.Count) existing dashboard(s) after cleanup." -ForegroundColor Cyan
    foreach ($d in $dashboards) {
        Write-Verbose "[PROJECT-READ] Existing dashboard: '$($d.name)' [ID: $($d.id)]"
    }

    # 2) Recommended SDLC dashboards for this project
    Write-Host "      [PROJECT-RECOMMEND] Generating recommended dashboard definitions..." -ForegroundColor DarkGray
    Write-Verbose "[PROJECT] Fetching recommended dashboard definitions for project $($project.name)"
    $recommended = @(Get-RecommendedDashboardDefinitions -ProjectName $project.name -TeamName $defaultTeam.name -ProjectId $project.id -TeamId $defaultTeam.id)

    if ($recommended.Count -eq 0) {
        Write-Host "      [PROJECT-SKIP] No recommended dashboards returned for project '$($project.name)'. Skipping." -ForegroundColor Yellow
        Write-Verbose "[PROJECT] Skipped project $($project.name) - no recommended dashboards"
        continue
    }
    Write-Host "      [PROJECT-RECOMMEND] Generated $($recommended.Count) recommended dashboard(s)" -ForegroundColor Cyan

    # Map recommended by name for fast lookup
    $recommendedByName = @{}
    foreach ($def in $recommended) {
        # Hashtables use .ContainsKey, PSObjects use .PSObject.Properties
        $hasName = $false
        if ($def -is [hashtable] -or $def -is [System.Collections.IDictionary]) {
            $hasName = $def.ContainsKey('name')
        } elseif ($def.PSObject.Properties['name']) {
            $hasName = $true
        }
        
        if ($null -ne $def -and $hasName -and $def.name) {
            $recommendedByName[$def.name] = $def
        }
    }

    # Map existing dashboards by name (ignore any [TMP] or [TMP-XXXXX] remnants just in case)
    Write-Host "    Found $($dashboards.Count) existing dashboard(s)." -ForegroundColor Cyan
    $existingByName = @{}
    foreach ($d in $dashboards) {
        if ($null -ne $d -and $d.PSObject.Properties['name']) {
            # Exclude both old [TMP] and new [TMP-XXXXX] formats
            if ($d.name -notlike "[TMP]*" -and $d.name -notmatch '^\[TMP-\d{5}\]') {
                $existingByName[$d.name] = $d
            }
        }
    }

    if ($ClearExistingDashboards) {
        # --------- RESET MODE: force standard dashboards, remove the rest ----------
        Write-Host "      [PROJECT-RESET] FORCE MODE: Resetting dashboards for project '$($project.name)'..." -ForegroundColor Yellow
        Write-Verbose "[PROJECT] Entering dashboard reset mode for project $($project.name)"

        # 2.1 Create all recommended dashboards first with temporary [TMP-XXXXX] names
        Write-Host "      [PROJECT-CREATE-TMP] Creating temporary dashboards with unique ID [$script:RunId] (Phase 1 of 3)..." -ForegroundColor DarkGray
        $createdTemp = @{}
        $dashIndex = 0

        foreach ($def in $recommended) {
            $dashIndex++
            Write-Progress -Activity "Creating Temp Dashboards" -Status "[$dashIndex/$($recommended.Count)] $($def.name)" -PercentComplete (($dashIndex / $recommended.Count) * 100) -ParentId 2 -Id 3
            
            $finalName = $def.name
            $tempName  = "[TMP-$script:RunId] $finalName"

            $newDef = [ordered]@{
                name            = $tempName
                position        = $def.position
                refreshInterval = $def.refreshInterval
                widgets         = $def.widgets
            }

            Write-Host "        [CREATE] [$dashIndex/$($recommended.Count)] Creating temporary dashboard: '$tempName'" -ForegroundColor Green
            Write-Verbose "[DASHBOARD-CREATE] Creating temp dashboard: $tempName with $($def.widgets.Count) widget(s)"
            if (-not $DryRun) {
                $created = New-AdoDashboard -ProjectId $project.id -TeamId $defaultTeam.id -DashboardDef $newDef
                if ($created -and $created.id) {
                    $createdTemp[$finalName] = $created
                    Write-Host "          -> Created TMP dashboard ID: $($created.id)" -ForegroundColor DarkGreen
                    Write-Verbose "[DASHBOARD-CREATE] Successfully created temp dashboard with ID: $($created.id)"
                    $createdCount++
                } else {
                    Write-Warning "          -> Failed to create temporary dashboard '$tempName'"
                    Write-Verbose "[DASHBOARD-CREATE] Failed to create temp dashboard: $tempName"
                }
            } else {
                Write-Host "          -> [DRY-RUN] Would create temporary dashboard" -ForegroundColor Cyan
            }
        }
        Write-Progress -Activity "Creating Temp Dashboards" -Completed -ParentId 2 -Id 3

        if (-not $DryRun) {
            # Re-read dashboards including the newly created TMP ones
            Write-Host "      [PROJECT-DELETE] Deleting old dashboards (Phase 2 of 3)..." -ForegroundColor DarkGray
            Write-Verbose "[PROJECT] Re-reading dashboard list after temp creation"
            $dashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $defaultTeam.id)
            Write-Host "        [READ] Found $($dashboards.Count) dashboard(s) total after temp creation" -ForegroundColor Cyan

            # 2.2 Delete all existing dashboards that are not one of the new TMP ones
            $recommendedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($name in $recommendedByName.Keys) { [void]$recommendedNames.Add($name) }

            $tmpIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($kvp in $createdTemp.GetEnumerator()) {
                if ($kvp.Value -and $kvp.Value.id) { [void]$tmpIds.Add([string]$kvp.Value.id) }
            }
            Write-Verbose "[PROJECT] Temporary dashboard IDs to preserve: $($tmpIds.Count) item(s)"

            $delIndex = 0
            $delCount = 0
            foreach ($d in $dashboards) {
                if (-not $d -or -not $d.id) { continue }

                $isTmp = $d.name -like "[TMP]*" -or $d.name -match '^\[TMP-\d{5}\]' -or $tmpIds.Contains([string]$d.id)
                if ($isTmp) {
                    # Keep TMP dashboards for now; they will be renamed
                    Write-Verbose "[DASHBOARD-DELETE] Skipping temporary dashboard: $($d.name) [will be renamed]"
                    continue
                }

                $delIndex++
                # Delete everything else (old standard dashboards and custom ones)
                Write-Host "        [DELETE] [$delIndex] Deleting old dashboard: '$($d.name)' [ID: $($d.id)]" -ForegroundColor DarkYellow
                Write-Verbose "[DASHBOARD-DELETE] Deleting dashboard: $($d.name)"
                try {
                    Remove-AdoDashboard -ProjectId $project.id -TeamId $defaultTeam.id -DashboardId $d.id
                    $deletedCount++
                    $delCount++
                    Write-Verbose "[DASHBOARD-DELETE] Successfully deleted dashboard ID: $($d.id)"
                } catch {
                    Write-Warning "        -> Failed to delete dashboard '$($d.name)' in project '$($project.name)'. $_"
                    Write-Verbose "[DASHBOARD-DELETE] Error deleting dashboard $($d.id): $_"
                }
            }
            Write-Host "        [DELETE] Deleted $delCount old dashboard(s)" -ForegroundColor Cyan

            # 2.3 Rename each TMP dashboard to its final name (no numbers, no TMP prefix)
            Write-Host "      [PROJECT-RENAME] Renaming temporary dashboards (Phase 3 of 3)..." -ForegroundColor DarkGray
            Write-Verbose "[PROJECT] Re-reading dashboard list for rename phase"
            $dashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $defaultTeam.id)
            $dashById = @{}
            foreach ($d in $dashboards) {
                if ($d -and $d.id) { $dashById[[string]$d.id] = $d }
            }
            Write-Host "        [READ] Found $($dashById.Count) dashboard(s) for rename phase" -ForegroundColor Cyan

            $renameIndex = 0
            
            foreach ($finalName in $recommendedByName.Keys) {
                # Find ANY temp dashboard that matches this final name (from current or previous runs)
                $matchingTempDash = $null
                $matchingTempId = $null
                
                # First, try dashboards created in this run
                if ($createdTemp.ContainsKey($finalName)) {
                    $matchingTempDash = $createdTemp[$finalName]
                    $matchingTempId = [string]$matchingTempDash.id
                } else {
                    # Look for any existing temp dashboard with this name pattern
                    foreach ($d in $dashById.Values) {
                        if ($d.name -match '^\[TMP-\d{5}\]\s+(.+)$') {
                            if ($matches[1] -eq $finalName) {
                                $matchingTempDash = $d
                                $matchingTempId = [string]$d.id
                                Write-Verbose "[DASHBOARD-RENAME] Found orphaned temp dashboard from previous run: $($d.name)"
                                break
                            }
                        }
                    }
                }

                if (-not $matchingTempDash) {
                    Write-Verbose "[DASHBOARD-RENAME] No temp dashboard found for '$finalName' - skipping rename"
                    continue
                }

                if (-not $dashById.ContainsKey($matchingTempId)) {
                    Write-Warning "        [RENAME] TMP dashboard for '$finalName' (ID: $matchingTempId) not found. Skipping."
                    Write-Verbose "[DASHBOARD-RENAME] Dashboard ID $matchingTempId not found in current list"
                    continue
                }

                $renameIndex++
                
                # Get FULL dashboard details (list entries don't include widgets)
                $current = Get-AdoDashboard -ProjectId $project.id -TeamId $defaultTeam.id -DashboardId $matchingTempId
                
                if (-not $current) {
                    Write-Warning "        [RENAME] Failed to fetch dashboard details for ID $matchingTempId. Skipping."
                    continue
                }
                
                # For rename, only send name and position (don't touch widgets to avoid eTag conflicts)
                $updateDef = [ordered]@{
                    name            = $finalName
                    position        = $recommendedByName[$finalName].position
                }

                # Handle eTag for both hashtable and PSObject
                if ($current -is [hashtable] -and $current.ContainsKey('eTag')) {
                    $updateDef['eTag'] = $current['eTag']
                } elseif ($current.PSObject.Properties['eTag']) {
                    $updateDef['eTag'] = $current.eTag
                }

                Write-Host "        [RENAME] [$renameIndex] Renaming: '$($current.name)' -> '$finalName'" -ForegroundColor Green
                Write-Verbose "[DASHBOARD-RENAME] Renaming dashboard ID $matchingTempId from '$($current.name)' to '$finalName'"
                try {
                    $updated = Set-AdoDashboard -ProjectId $project.id -TeamId $defaultTeam.id -DashboardId $matchingTempId -DashboardDef $updateDef
                    if ($updated -and $updated.id) {
                        Write-Host "          -> Successfully renamed (ID: $($updated.id))" -ForegroundColor DarkGreen
                        Write-Verbose "[DASHBOARD-RENAME] Successfully renamed dashboard to: $finalName (ID: $($updated.id))"
                    } else {
                        Write-Warning "          -> Rename returned no ID"
                    }
                } catch {
                    Write-Warning "          -> Failed to rename dashboard '$($current.name)' to '$finalName' in project '$($project.name)'. $_"
                    Write-Verbose "[DASHBOARD-RENAME] Error renaming dashboard ID $($matchingTempId): $_"
                }
            }
            Write-Host "      [PROJECT-RESET] Dashboard reset complete for project '$($project.name)'" -ForegroundColor Cyan
        }
    }
    else {
        # Non-reset mode: only create missing dashboards, keep others intact
        # Use [TMP-XXXXX] strategy to avoid duplicate name errors during creation
        Write-Host "      [PROJECT-MERGE] MERGE MODE: Creating missing dashboards with unique ID [$script:RunId]..." -ForegroundColor Yellow
        Write-Verbose "[PROJECT] Entering merge mode for project $($project.name)"
        
        $createdTemp = @{}
        $createIndex = 0
        
        foreach ($def in $recommended) {
            $name = $def.name
            if ($existingByName.ContainsKey($name)) {
                Write-Host "        [SKIP] Dashboard '$name' already exists (keeping)." -ForegroundColor DarkGray
                Write-Verbose "[PROJECT-MERGE] Skipping dashboard creation for $name - already exists"
                continue
            }

            $createIndex++
            $tempName = "[TMP-$script:RunId] $name"
            
            Write-Host "        [CREATE] [$createIndex] Creating dashboard: '$name' (via temp name)" -ForegroundColor Green
            Write-Verbose "[PROJECT-MERGE] Creating missing dashboard: $name"
            
            if (-not $DryRun) {
                # Create with temporary name first
                $newDef = [ordered]@{
                    name            = $tempName
                    position        = $def.position
                    refreshInterval = $def.refreshInterval
                    widgets         = $def.widgets
                }
                
                $created = New-AdoDashboard -ProjectId $project.id -TeamId $defaultTeam.id -DashboardDef $newDef
                if ($created -and $created.id) {
                    $createdTemp[$name] = $created
                    Write-Host "          -> Created temp dashboard (ID: $($created.id))" -ForegroundColor DarkGreen
                    Write-Verbose "[PROJECT-MERGE] Created temp dashboard with ID: $($created.id)"
                } else {
                    Write-Warning "          -> Failed to create dashboard '$name'"
                    Write-Verbose "[PROJECT-MERGE] Failed to create dashboard: $name"
                }
            } else {
                Write-Host "          -> [DRY-RUN] Would create dashboard" -ForegroundColor Cyan
            }
        }
        
        # Rename temporary dashboards to final names in merge mode
        if (-not $DryRun -and $createdTemp.Count -gt 0) {
            Write-Host "      [PROJECT-MERGE] Renaming temporary dashboards to final names..." -ForegroundColor DarkGray
            Write-Verbose "[PROJECT] Re-reading dashboard list for merge mode rename"
            $dashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $defaultTeam.id)
            $dashById = @{}
            foreach ($d in $dashboards) {
                if ($d -and $d.id) { $dashById[[string]$d.id] = $d }
            }
            
            $renameIndex = 0
            foreach ($finalName in $createdTemp.Keys) {
                $renameIndex++
                $tmpDash = $createdTemp[$finalName]
                $dashId  = [string]$tmpDash.id
                
                if (-not $dashById.ContainsKey($dashId)) {
                    Write-Warning "        [RENAME] Temp dashboard for '$finalName' not found. Skipping."
                    Write-Verbose "[PROJECT-MERGE] Dashboard ID $dashId not found in current list"
                    continue
                }
                
                $current = $dashById[$dashId]
                
                # For rename, only send name and position (don't touch widgets/refreshInterval to avoid eTag conflicts)
                $updateDef = [ordered]@{
                    name     = $finalName
                    position = $recommendedByName[$finalName].position
                }
                
                # Handle eTag for both hashtable and PSObject
                if ($current -is [hashtable] -and $current.ContainsKey('eTag')) {
                    $updateDef['eTag'] = $current['eTag']
                } elseif ($current.PSObject.Properties['eTag']) {
                    $updateDef['eTag'] = $current.eTag
                }
                
                Write-Host "        [RENAME] [$renameIndex] Renaming: '$($current.name)' -> '$finalName'" -ForegroundColor Green
                Write-Verbose "[PROJECT-MERGE] Renaming dashboard ID $dashId to '$finalName'"
                try {
                    $updated = Set-AdoDashboard -ProjectId $project.id -TeamId $defaultTeam.id -DashboardId $dashId -DashboardDef $updateDef
                    if ($updated -and $updated.id) {
                        Write-Host "          -> Successfully renamed (ID: $($updated.id))" -ForegroundColor DarkGreen
                        Write-Verbose "[PROJECT-MERGE] Successfully renamed dashboard to: $finalName (ID: $($updated.id))"
                        $createdCount++
                    }
                } catch {
                    Write-Warning "          -> Failed to rename dashboard '$($current.name)' to '$finalName'. $_"
                    Write-Verbose "[PROJECT-MERGE] Error renaming dashboard ID $($dashId): $_"
                }
            }
        }
    }
    Write-Verbose "[PROJECT] Completed project processing: $($project.name)"
}

    Write-Verbose "[PROJECT] Completed project processing: $($project.name)"


Write-Progress -Activity "Processing Projects" -Completed -Id 1
Write-Host ""
Write-Host "[COMPLETE] Dashboard operation completed!" -ForegroundColor Green
Write-Host "[SUMMARY] Statistics:" -ForegroundColor Cyan
Write-Host "  - Projects Processed: $projectsProcessed" -ForegroundColor Cyan
Write-Host "  - Teams Processed: $teamsProcessed" -ForegroundColor Cyan
Write-Host "  - Dashboards Created: $createdCount" -ForegroundColor Green
Write-Host "  - Dashboards Deleted: $deletedCount" -ForegroundColor Yellow
Write-Host "  - DryRun Mode: $DryRun" -ForegroundColor Cyan
Write-Host "  - Reset Mode: $ClearExistingDashboards" -ForegroundColor Cyan
Write-Verbose "[COMPLETE] Dashboard reset/creation process finished. Projects: $projectsProcessed, Teams: $teamsProcessed, Created: $createdCount, Deleted: $deletedCount"