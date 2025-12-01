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
$markdownContribution   = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget"
$markdownConfig         = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget.Configuration"
$teamMembersContribution= "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.TeamMembersWidget"
$newWitContribution     = "ms.vss-dashboards-web.new-work-item-widget"
$newWitConfig           = "ms.vss-dashboards-web.new-work-item-widget.configuration"

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

    Write-Verbose "$Method $uri"

    try {
        return Invoke-RestMethod @params
    }
    catch [System.Net.WebException] {
        $response = $_.Exception.Response
        if ($response -and $response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound -and $IgnoreNotFound) {
            Write-Verbose "404 Not Found (ignored): $uri"
            return $null
        }
        throw
    }
}

# -------------------------------------------------------
# 4. Projects, Teams, Dashboards helpers
# -------------------------------------------------------
function Get-AdoProjects {
    [CmdletBinding()]
    param()

    # Projects - List
    $relative = "_apis/projects?`$top=1000&api-version=$($script:CoreApiVersion)"
    $result   = Invoke-AdoRest -Method GET -RelativeUrl $relative

    if (-not $result) { return @() }
    if ($result.value) { return @($result.value) }
    return @()
}

function Get-AdoTeams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId
    )

    # Teams - Get Teams
    $relative = "_apis/projects/$ProjectId/teams?`$top=100&api-version=$($script:CoreApiVersion)"
    $result   = Invoke-AdoRest -Method GET -RelativeUrl $relative

    if (-not $result) { return @() }
    if ($result.value) { return @($result.value) }
    return @()
}

function Get-AdoDashboards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId
    )

    # Dashboards - List
    $relative = "$ProjectId/$TeamId/_apis/dashboard/dashboards?api-version=$($script:DashboardApiVersion)"
    $result   = Invoke-AdoRest -Method GET -RelativeUrl $relative -IgnoreNotFound

    if (-not $result) { return @() }
    #if ($result.value) { return @($result.value) }
    if ($result.dashboardEntries) { return @($result.dashboardEntries) }
    if ($result.dashboards) { return @($result.dashboards) }
    return @()
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

    # Dashboards - Delete
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"

    if ($PSCmdlet.ShouldProcess("Dashboard $DashboardId", "DELETE")) {
        Invoke-AdoRest -Method DELETE -RelativeUrl $relative -IgnoreNotFound | Out-Null
    }
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
        [hashtable] $DashboardDef
    )

    # Dashboards - Replace Dashboard
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"
    Invoke-AdoRest -Method PUT -RelativeUrl $relative -Body $DashboardDef | Out-Null
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
        [hashtable] $DashboardDef
    )

    # Dashboards - Update
    $relative = "$($ProjectId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"
    $additionalHeaders = @{
        "If-Match" = "`"$([string]$DashboardDef.eTag)`""
    }
    return Invoke-AdoRest -Method PUT -RelativeUrl $relative -Body $DashboardDef -AdditionalHeaders $additionalHeaders
}

# -------------------------------------------------------
# 5. Recommended SDLC dashboards (widgets)
# -------------------------------------------------------
function Clean-OldQueries {
    param($ProjectId, $TeamId, $FolderId)
    # Query cleanup is handled per-query inside New-Query using delete-and-recreate logic.
}

function Get-SharedQueriesFolderId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $TeamId
    )

    $relative = $ProjectId + '/_apis/wit/queries?api-version=7.1'
    $result = Invoke-AdoRest -Method GET -RelativeUrl $relative

    $queries = try { $result.value } catch { $result }
    $shared = $queries | Where-Object { $_.name -eq "Shared Queries" -and $_.isFolder }
    if (-not $shared) {
        throw "Shared Queries folder not found for project $ProjectId"
    }
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

    $body = @{
        name = $Name
        wiql = $Wiql
    }

    # Remove any existing query or folder with the same name in the target folder
    # to avoid TF237018 duplicate-name errors.
    try {
        $listRelative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?$depth=1&api-version=7.1'
        $existing = Invoke-AdoRest -Method GET -RelativeUrl $listRelative
        $children = try { $existing.value } catch { $existing }
        if ($children) {
            foreach ($item in $children) {
                if ($item.name -eq $Name) {
                    $deleteRelative = $ProjectId + '/_apis/wit/queries/' + $item.id + '?api-version=7.1'
                    try {
                        Invoke-AdoRest -Method DELETE -RelativeUrl $deleteRelative | Out-Null
                    } catch {
                        # If delete fails we still attempt to create; any remaining conflict will surface.
                    }
                }
            }
        }
    } catch {
        # If listing fails, continue and let creation attempt surface any issues.
    }

    $relative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?api-version=7.1'
    try {
        $result = Invoke-AdoRest -Method POST -RelativeUrl $relative -Body $body
        return $result.id
    }
    catch {
        # Final fallback: if a non-folder with the same name exists, update its WIQL.
        try {
            $listRelative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?$depth=1&api-version=7.1'
            $existing = Invoke-AdoRest -Method GET -RelativeUrl $listRelative
            $children = try { $existing.value } catch { $existing }
            $existingQuery = $null
            foreach ($item in $children) {
                if ($item.name -eq $Name -and -not $item.isFolder) {
                    $existingQuery = $item
                    break
                }
            }
            if ($existingQuery) {
                $updateRelative = $ProjectId + '/_apis/wit/queries/' + $existingQuery.id + '?api-version=7.1'
                Invoke-AdoRest -Method PUT -RelativeUrl $updateRelative -Body $body | Out-Null
                return $existingQuery.id
            }
        } catch {
            # Ignore and fall through to returning $null.
        }
        return $null
    }
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

$businessQueries = @(
    @{Name = "Product Backlog Health"; Wiql = "SELECT [System.Id], [System.Title], [Microsoft.VSTS.Common.Priority], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Feature', 'Epic') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.Priority]" },
    @{Name = "High-Value Items"; Wiql = "SELECT [System.Id], [System.Title], [Microsoft.VSTS.Common.BusinessValue], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [Microsoft.VSTS.Common.BusinessValue] > 50 AND [System.State] <> 'Closed'" },
    @{Name = "Strategic Initiatives"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Epic' AND [System.State] <> 'Closed' ORDER BY [System.CreatedDate]" },
    @{Name = "Stakeholder Requests"; Wiql = "SELECT [System.Id], [System.Title], [System.CreatedDate] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'User Story' AND [System.State] NOT IN ('Closed', 'Done')" },
    @{Name = "Market Dependency Tracker"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed'" },
    @{Name = "Revenue Impact Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Feature' AND [System.State] <> 'Closed'" },
    @{Name = "Regulatory Compliance Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Requirement' ORDER BY [System.CreatedDate]" },
    @{Name = "Customer Feedback Integration"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Feedback' AND [System.State] NOT IN ('Closed', 'Rejected')" },
    @{Name = "Competitive Analysis Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Epic' AND [System.State] <> 'Closed'" },
    @{Name = "Partnership Integration Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Feature' AND [System.State] IN ('Active', 'New')" },
    @{Name = "Go-to-Market Readiness"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Feature' AND [System.State] <> 'Closed'" }
)

# ============================================
# ENGINEERING / DEVELOPMENT DASHBOARD CONFIGURATION
# ============================================

$devQueries = @(
    @{Name = "Sprint Task Breakdown"; Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Scheduling.RemainingWork] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' ORDER BY [System.State]" },
    @{Name = "Code Review Queue"; Wiql = "SELECT [System.Id], [System.Title], [System.CreatedDate] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Code Review' AND [System.State] = 'Active' ORDER BY [System.CreatedDate]" },
    @{Name = "Technical Debt Backlog"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.State] <> 'Closed' ORDER BY [System.CreatedDate]" },
    @{Name = "Security Vulnerability Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed'" },
    @{Name = "Performance Optimization Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.State] <> 'Closed'" },
    @{Name = "Architecture Refactoring Tasks"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' ORDER BY [System.CreatedDate]" },
    @{Name = "Development Spike Tasks"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task'" },
    @{Name = "Test Automation Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Test Case' AND [System.State] <> 'Closed'" },
    @{Name = "DevOps Improvement Tasks"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.State] IN ('New', 'Active')" },
    @{Name = "Code Migration Items"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' ORDER BY [System.CreatedDate]" },
    @{Name = "Documentation Tasks"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.State] <> 'Closed'" },
    @{Name = "Infrastructure As Code Tasks"; Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.State] IN ('New', 'Active')" }
)

# ============================================
# QUALITY / TESTING DASHBOARD CONFIGURATION
# ============================================

$qaQueries = @()

# ============================================
# OPERATIONS / RELEASE DASHBOARD CONFIGURATION
# ============================================

$opsQueries = @()

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

        # $widgets += @{
        #     name                        = "New Work Item"
        #     position                    = @{ row = 1; column = 1 }
        #     size                        = @{ rowSpan = 1; columnSpan = 2 }
        #     settings                    = $null
        #     settingsVersion             = $settingsVersion
        #     contributionId              = $newWitContribution
        #     configurationContributionId = $newWitConfig
        # }
        # Add query result widgets
        $row = 2
        foreach ($query in $Queries) {
            $queryId = New-Query -ProjectId $ProjectId -TeamId $TeamId -FolderId $FolderId -Name $query.Name -Wiql $query.Wiql
            if($null -eq $queryId) {
                continue
            }
            $settings = @{
                            defaultBackgroundColor="#51399f";
                            queryId=$queryId;
                            queryName="Open Issues";
                            colorRules= @( @{ isEnabled=$true;backgroundColor="#339947";thresholdCount=0;operator="<=" } )  | ConvertTo-Json -Compress;
                            lastArtifactName="Open Issues";
                            showTitle=$true;title="Open Issues";titleSize=2;showBorder=$true;
                            borderColor="#cccccc";showHeader=$true;headerColor="#f4f4f4";
                            showFooter=$false;footerColor="#f4f4f4";layout="list";
                            pageSize=5;sortOrder="Descending";sortBy="ChangedDate";
                            fieldsToDisplay=@("Id";"Title";"State";"AssignedTo";"ChangedDate")  | ConvertTo-Json -Compress;
                            linkBehavior="newTab"
                        }

            $widgets += @{
                name            = $query.Name
                position        = @{ row = $row; column = 1 }
                size            = @{ rowSpan = 2; columnSpan = 4 }
                settings        = ($settings  | ConvertTo-Json -Compress)
                settingsVersion = $settingsVersion
                contributionId  = "ms.vss-work-web.query-widget"
            }
            $row += 2
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

    $dashboards += New-SimpleDashboardDef -Name "01 - Business Product"   -Position 1 -Queries $businessQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId
    $dashboards += New-SimpleDashboardDef -Name "02 - Engineering Dev"    -Position 2 -Queries $devQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId
    $dashboards += New-SimpleDashboardDef -Name "03 - Quality Testing"    -Position 3 -Queries $qaQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId
    $dashboards += New-SimpleDashboardDef -Name "04 - Operations Release" -Position 4 -Queries $opsQueries -ProjectId $ProjectId -TeamId $TeamId -FolderId $folderId

    return $dashboards
}

# -------------------------------------------------------
# 6. Main orchestration
# -------------------------------------------------------
$projects = @(Get-AdoProjects)

$createdCount = 0
$deletedCount = 0

if ($ProjectInclude) {
    $includeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ProjectInclude | ForEach-Object { if ($_){ [void]$includeSet.Add($_) } }
    $projects = $projects | Where-Object { $includeSet.Contains($_.name) }
}

if ($ProjectExclude) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ProjectExclude | ForEach-Object { if ($_){ [void]$excludeSet.Add($_) } }
    $projects = $projects | Where-Object { -not $excludeSet.Contains($_.name) }
}

if ($projects.Count -eq 0) {
    Write-Warning "No projects found after filters. Nothing to do."
    return
}

$projectIndex = 0
foreach ($project in $projects) {
    $projectIndex++
    Write-Progress -Activity "Processing Projects" -Status "Project: $($project.name)" -PercentComplete (($projectIndex / $projects.Count) * 100)

    Write-Host ""
    Write-Host ">>> Project: $($project.name)  [$($project.id)]" -ForegroundColor Magenta

    $teams = @(Get-AdoTeams -ProjectId $project.id)
    if ($teams.Count -eq 0) {
        Write-Warning "  No teams found in project '$($project.name)'. Skipping."
        continue
    }

    foreach ($team in $teams) {
        Write-Host "  Team: $($team.name) [$($team.id)]" -ForegroundColor Yellow

        # 1) Read current dashboards safely as array
        $dashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $team.id)
        Write-Host "    DEBUG: Found $($dashboards.Count) existing dashboards." -ForegroundColor Cyan
        foreach ($d in $dashboards) {
            Write-Host "      DEBUG: Existing dashboard - Name: '$($d.name)'" -ForegroundColor Gray
        }

        # 2) Recommended SDLC dashboards for this team
        $recommended = @(Get-RecommendedDashboardDefinitions -ProjectName $project.name -TeamName $team.name -ProjectId $project.id -TeamId $team.id)

        # Map recommended by name for fast lookup
        $recommendedByName = @{ }
        foreach ($def in $recommended) {
            if ($null -ne $def -and $def.name) {
                $recommendedByName[$def.name] = $def
            } else {
                Write-Host "      DEBUG: Skipped invalid recommended dashboard definition" -ForegroundColor Yellow
            }
        }

        # Map existing dashboards by name
        Write-Host "    Found $($dashboards.Count) existing dashboard(s)." -ForegroundColor Cyan
        $existingByName = @{}
        foreach ($d in $dashboards) {
            if ($null -ne $d -and $d.PSObject.Properties['name']) {
                $existingByName[$d.name] = $d.PSObject.Properties['id'].Value
            }
        }
$ClearExistingDashboards=$true;
        if ($ClearExistingDashboards) {
            # --------- RESET MODE ---------
            Write-Host "    FORCE: Apply recommended dashboards (upsert)..." -ForegroundColor Yellow

            # 1) Upsert recommended dashboards by name: update when they exist, create when missing
            foreach ($def in $recommended) {
                if ($null -eq $def -or -not $def.name) { continue }

                $name = $def.name
                if ($existingByName.ContainsKey($name)) {
                    $id = $existingByName[$name]
                    Write-Host "    UPDATE '$name'..." -ForegroundColor Yellow
                    if (-not $DryRun) {
                        Set-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $id -DashboardDef $def
                    }
                }
                else {
                    Write-Host "    CREATE '$name'..." -ForegroundColor Green
                    if (-not $DryRun) {
                        $created = New-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardDef $def
                        if ($created -and $created.id) {
                            Write-Host "      -> created" -ForegroundColor DarkGreen
                            $createdCount++
                            # Track created dashboard so it isn't deleted in the cleanup step
                            $existingByName[$created.name] = $created.id
                        }
                    }
                }
            }

            # 2) Delete existing dashboards that are not in the recommended set
            $recommendedNames = $recommended | ForEach-Object { $_.Name }
            foreach ($name in $existingByName.Keys) {
                if ($name -notin $recommendedNames) {
                    $id = $existingByName[$name]
                    Write-Host "      DELETE '$name'" -ForegroundColor Red
                    if (-not $DryRun) {
                        Remove-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $id
                        $deletedCount++
                    }
                }
            }

        } else {
            $existingByName = @{}
            foreach ($d in $dashboards) {
                Write-Host "    Found $($d.url) existing dashboard(s)." -ForegroundColor Cyan
                if ($null -ne $d -and $d.PSObject.Properties['name']) {
                    $existingByName[$d.name] = $d
                }
            }

            # 2.3 Create any missing recommended dashboards
            foreach ($def in $recommended) {
                $name = $def.name
                if ($existingByName.ContainsKey($name)) {
                    Write-Host "    SKIP create '$name' (already exists)." -ForegroundColor DarkGray
                    continue
                }

                Write-Host "    CREATE '$name'" -ForegroundColor Green
                if (-not $DryRun) {
                    $created = New-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardDef $def
                    if ($created -and $created.id) {
                        Write-Host "      -> created" -ForegroundColor DarkGreen
                        $createdCount++
                    }
                }
            }
        }

    }
}

Write-Progress -Activity "Processing Projects" -Completed
Write-Host ""
Write-Host "Done. Created: $createdCount, Deleted: $deletedCount" -ForegroundColor Cyan