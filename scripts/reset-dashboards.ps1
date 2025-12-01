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
        [object] $DashboardDef
    )

    # Dashboards - Replace / Update with optional eTag
    $relative = "$($ProjectId)/$($TeamId)/_apis/dashboard/dashboards/$($DashboardId)?api-version=$($script:DashboardApiVersion)"

    $additionalHeaders = @{}
    if ($DashboardDef -and $DashboardDef.PSObject.Properties.Name -contains 'eTag' -and $DashboardDef.eTag) {
        $additionalHeaders["If-Match"] = "`"$([string]$DashboardDef.eTag)`""
    }

    if ($additionalHeaders.Count -gt 0) {
        return Invoke-AdoRest -Method PUT -RelativeUrl $relative -Body $DashboardDef -AdditionalHeaders $additionalHeaders
    }
    else {
        return Invoke-AdoRest -Method PUT -RelativeUrl $relative -Body $DashboardDef
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

    $apiVersion = "7.1"
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

    foreach ($query in $children) {
        if ($query.name -like "[TMP]*") {
            $deleteRelative = $ProjectId + '/_apis/wit/queries/' + $query.id + '?api-version=' + $apiVersion
            try {
                Invoke-AdoRest -Method DELETE -RelativeUrl $deleteRelative -IgnoreNotFound | Out-Null
            } catch {
                Write-Warning "Failed to delete leftover temporary query '$($query.name)' in project '$ProjectId'. $_"
            }
        }
    }
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

    $apiVersion = "7.1"
    $targetName = $Name
    $tempName   = "[TMP] $Name"

    # 1) Load existing children under the target folder
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

    $existingFinal = $null
    $existingTemp  = $null

    foreach ($item in $children) {
        if ($item.name -eq $targetName) {
            $existingFinal = $item
        } elseif ($item.name -eq $tempName) {
            $existingTemp = $item
        }
    }

    # 2) Remove any leftover temporary query
    if ($existingTemp) {
        $deleteTempRelative = $ProjectId + '/_apis/wit/queries/' + $existingTemp.id + '?api-version=' + $apiVersion
        try {
            Invoke-AdoRest -Method DELETE -RelativeUrl $deleteTempRelative -IgnoreNotFound | Out-Null
        } catch {
            Write-Warning "Failed to delete temporary query '$tempName' in project '$ProjectId'. $_"
        }
    }

    # 3) Create a new query with a temporary name
    $body = @{
        name = $tempName
        wiql = $Wiql
    }

    $createRelative = $ProjectId + '/_apis/wit/queries/' + $FolderId + '?api-version=' + $apiVersion

    try {
        $created = Invoke-AdoRest -Method POST -RelativeUrl $createRelative -Body $body
    } catch {
        Write-Warning "Failed to create query '$tempName' under folder '$FolderId' in project '$ProjectId'. $_"
        return $null
    }

    if (-not $created -or -not $created.id) {
        Write-Warning "Query '$tempName' creation returned no id."
        return $null
    }

    $newId = $created.id

    # 4) Delete any existing query with the final name
    if ($existingFinal) {
        $deleteFinalRelative = $ProjectId + '/_apis/wit/queries/' + $existingFinal.id + '?api-version=' + $apiVersion
        try {
            Invoke-AdoRest -Method DELETE -RelativeUrl $deleteFinalRelative -IgnoreNotFound | Out-Null
        } catch {
            Write-Warning "Failed to delete existing query '$targetName' in project '$ProjectId'. $_"
        }
    }

    # 5) Rename the new query from temporary name to final name
    $updateBody = @{
        name = $targetName
        wiql = $Wiql
    }

    $updateRelative = $ProjectId + '/_apis/wit/queries/' + $newId + '?api-version=' + $apiVersion

    try {
        $updated = Invoke-AdoRest -Method PATCH -RelativeUrl $updateRelative -Body $updateBody
        if ($updated -and $updated.id) {
            $newId = $updated.id
        }
    } catch {
        Write-Warning "Failed to rename query '$tempName' to '$targetName' under folder '$FolderId' in project '$ProjectId'. $_"
    }

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
    
    $businessQueries = @(
        @{
            Name = "Product Backlog Health"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Scheduling.StoryPoints], [Microsoft.VSTS.Common.BusinessValue] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('User Story', 'Product Backlog Item', 'Requirement', 'Bug') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [Microsoft.VSTS.Common.Priority], [System.ChangedDate] DESC"
        },
        @{
            Name = "High-Value Items"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [Microsoft.VSTS.Common.BusinessValue], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Feature', 'User Story', 'Product Backlog Item', 'Requirement') AND [Microsoft.VSTS.Common.BusinessValue] >= 50 AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.BusinessValue] DESC, [System.ChangedDate] DESC"
        },
        @{
            Name = "Strategic Initiatives"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Epic', 'Feature') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.CreatedDate]"
        },
        @{
            Name = "Stakeholder Requests"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.CreatedDate] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('User Story', 'Product Backlog Item', 'Requirement', 'Issue') AND [System.State] NOT IN ('Closed', 'Done', 'Removed', 'Resolved') ORDER BY [System.CreatedDate] DESC"
        },
        @{
            Name = "Market Dependency Tracker"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Epic', 'Feature', 'User Story', 'Product Backlog Item', 'Requirement') AND [System.Tags] CONTAINS 'Dependency' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [System.Title]"
        },
        @{
            Name = "Revenue Impact Items"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [Microsoft.VSTS.Common.BusinessValue], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Feature', 'User Story', 'Product Backlog Item', 'Requirement') AND [Microsoft.VSTS.Common.BusinessValue] >= 80 AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.BusinessValue] DESC"
        },
        @{
            Name = "Regulatory Compliance Items"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Requirement', 'User Story', 'Product Backlog Item') AND ([System.Tags] CONTAINS 'Compliance' OR [System.Tags] CONTAINS 'Regulation') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.CreatedDate]"
        },
        @{
            Name = "Customer Feedback Integration"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.CreatedDate] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND ([System.WorkItemType] IN ('Feedback Request', 'Feedback Response', 'Issue') OR [System.Tags] CONTAINS 'Feedback') AND [System.State] NOT IN ('Closed', 'Rejected', 'Removed') ORDER BY [System.CreatedDate] DESC"
        },
        @{
            Name = "Competitive Analysis Items"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Epic', 'Feature', 'User Story', 'Product Backlog Item', 'Requirement') AND [System.Tags] CONTAINS 'Competitive' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [System.Title]"
        },
        @{
            Name = "Partnership Integration Items"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Feature', 'User Story', 'Product Backlog Item', 'Requirement') AND [System.Tags] CONTAINS 'Partner' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [System.Title]"
        },
        @{
            Name = "Go-to-Market Readiness"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Feature', 'User Story', 'Product Backlog Item', 'Requirement') AND ([System.Tags] CONTAINS 'GTM' OR [System.Tags] CONTAINS 'Go-To-Market' OR [System.Tags] CONTAINS 'Release') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [System.Title]"
        }
    )
    
    # ============================================
    # ENGINEERING / DEVELOPMENT DASHBOARD CONFIG
    # ============================================
    
    $devQueries = @(
        @{
            Name = "Sprint Task Breakdown"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Scheduling.RemainingWork], [System.AssignedTo] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [System.AssignedTo]"
        },
        @{
            Name = "Code Review Queue"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.CreatedDate] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.Title] CONTAINS 'Code Review' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.CreatedDate]"
        },
        @{
            Name = "Technical Debt Backlog"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND [System.Tags] CONTAINS 'Tech Debt' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Security Vulnerability Items"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Severity] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND ([System.Tags] CONTAINS 'Security' OR [System.Tags] CONTAINS 'Vulnerability') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.Severity], [System.ChangedDate] DESC"
        },
        @{
            Name = "Performance Optimization Items"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Tags] CONTAINS 'Performance' OR [System.Tags] CONTAINS 'Perf') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Architecture Refactoring Tasks"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Title] CONTAINS 'Refactor' OR [System.Tags] CONTAINS 'Refactor') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Development Spike Tasks"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Task', 'User Story', 'Product Backlog Item', 'Requirement') AND [System.Title] CONTAINS 'Spike' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Test Automation Items"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.TCM.AutomationStatus] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Test Case' AND [Microsoft.VSTS.TCM.AutomationStatus] <> 'Not Automated' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "DevOps Improvement Tasks"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Tags] CONTAINS 'DevOps' OR [System.Tags] CONTAINS 'Pipeline' OR [System.Tags] CONTAINS 'CI/CD') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Code Migration Items"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Title] CONTAINS 'Migration' OR [System.Title] CONTAINS 'Migrate' OR [System.Tags] CONTAINS 'Migration') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.CreatedDate]"
        },
        @{
            Name = "Documentation Tasks"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([Microsoft.VSTS.Common.Activity] = 'Documentation' OR [System.Title] CONTAINS 'Doc' OR [System.Tags] CONTAINS 'Documentation') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Infrastructure As Code Tasks"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Tags] CONTAINS 'IaC' OR [System.Tags] CONTAINS 'Terraform' OR [System.Tags] CONTAINS 'Bicep' OR [System.Tags] CONTAINS 'ARM Template') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        }
    )
    
    # ============================================
    # QUALITY / TESTING DASHBOARD CONFIGURATION
    # ============================================
    
    $qaQueries = @(
        @{
            Name = "Open Defects By Priority"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity], [System.ChangedDate] DESC"
        },
        @{
            Name = "Critical and High Defects"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND ([Microsoft.VSTS.Common.Severity] IN ('1 - Critical', '2 - High') OR [Microsoft.VSTS.Common.Priority] IN (1, 2)) AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.Severity], [Microsoft.VSTS.Common.Priority], [System.ChangedDate] DESC"
        },
        @{
            Name = "New Defects (Last 7 Days)"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [System.CreatedDate] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND [System.CreatedDate] >= @Today - 7 ORDER BY [System.CreatedDate] DESC"
        },
        @{
            Name = "Defects Ready For Test"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND [System.State] = 'Resolved' ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Production Defects"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Severity] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Bug' AND ([System.Tags] CONTAINS 'Production' OR [System.Title] CONTAINS 'Prod') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.Severity], [System.ChangedDate] DESC"
        },
        @{
            Name = "Active Test Cases"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Test Case' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.State], [System.Title]"
        },
        @{
            Name = "Test Cases Not Automated"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.TCM.AutomationStatus] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Test Case' AND [Microsoft.VSTS.TCM.AutomationStatus] = 'Not Automated' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Automated Test Cases"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.TCM.AutomationStatus] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Test Case' AND [Microsoft.VSTS.TCM.AutomationStatus] <> 'Not Automated' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Test Case Design Backlog"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Test Case' AND [System.State] = 'Design' ORDER BY [System.ChangedDate] DESC"
        }
    )
    
    # ============================================
    # OPERATIONS / RELEASE DASHBOARD CONFIGURATION
    # ============================================
    
    $opsQueries = @(
        @{
            Name = "Production Incidents"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [Microsoft.VSTS.Common.Severity] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Bug', 'Issue') AND ([System.Tags] CONTAINS 'Production' OR [System.Tags] CONTAINS 'Incident') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [Microsoft.VSTS.Common.Severity], [System.ChangedDate] DESC"
        },
        @{
            Name = "Open Operational Issues"
            Wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Issue' AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Active Change Requests"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Change Request', 'Issue', 'User Story', 'Product Backlog Item') AND ([System.Tags] CONTAINS 'Change' OR [System.Title] CONTAINS 'Change Request') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Release Deployment Tasks"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Title] CONTAINS 'Deployment' OR [System.Title] CONTAINS 'Deploy' OR [System.Tags] CONTAINS 'Deployment') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Failed Release Follow-Up"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Bug', 'Issue') AND ([System.Tags] CONTAINS 'Failed Deployment' OR [System.Title] CONTAINS 'Failed Deployment') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Service Availability Work Items"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Bug', 'Issue', 'Task') AND ([System.Tags] CONTAINS 'SLA' OR [System.Tags] CONTAINS 'Availability' OR [System.Tags] CONTAINS 'Reliability') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Hotfix Backlog"
            Wiql = "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] IN ('Bug', 'Issue') AND ([System.Tags] CONTAINS 'Hotfix' OR [System.Title] CONTAINS 'Hotfix') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            Name = "Monitoring and Alerting Tasks"
            Wiql = "SELECT [System.Id], [System.Title], [System.State] FROM WorkItems WHERE [System.AreaPath] UNDER '$TeamAreaPath' AND [System.WorkItemType] = 'Task' AND ([System.Tags] CONTAINS 'Monitoring' OR [System.Tags] CONTAINS 'Alerting' OR [System.Tags] CONTAINS 'Alert') AND [System.State] NOT IN ('Closed', 'Removed') ORDER BY [System.ChangedDate] DESC"
        }
    )

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
                position        = @{ row = $row; column = ($row/2 -band 1 ? 1 : 5) }
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

    # 1) Load current dashboards for this team
    $dashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $team.id)
    Write-Host "    Found $($dashboards.Count) existing dashboard(s)." -ForegroundColor Cyan

    $existingByName = @{}
    foreach ($d in $dashboards) {
        if ($null -ne $d -and $d.PSObject.Properties['name']) {
            $existingByName[$d.name] = $d
        }
    }

    # 2) Build recommended SDLC dashboards for this team
    $recommended = @(Get-RecommendedDashboardDefinitions -ProjectName $project.name -TeamName $team.name -ProjectId $project.id -TeamId $team.id)

    if ($recommended.Count -eq 0) {
        Write-Warning "    No recommended dashboards returned for team '$($team.name)'. Skipping."
        continue
    }

    # 3) For each recommended dashboard, force replace by create -> delete old -> rename new
    foreach ($def in $recommended) {
        $finalName = $def.name
        if (-not $finalName) { continue }

        $tempName = "[TMP] $finalName"

        # Remove any stale temp dashboards from previous runs
        if ($existingByName.ContainsKey($tempName)) {
            $tmp = $existingByName[$tempName]
            Write-Host "    CLEAN temp dashboard '$tempName'..." -ForegroundColor DarkGray
            if (-not $DryRun) {
                try {
                    Remove-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $tmp.id
                    $deletedCount++
                } catch {
                    Write-Warning "      Failed to delete stale temp dashboard '$tempName' for team '$($team.name)'. $_"
                }
            }
            $existingByName.Remove($tempName) | Out-Null
        }

        $existingFinal = $null
        if ($existingByName.ContainsKey($finalName)) {
            $existingFinal = $existingByName[$finalName]
        }

        # Create new dashboard with temporary name
        $newDef = $def.Clone()
        $newDef.name = $tempName

        Write-Host "    CREATE/REPLACE '$finalName' (via temp '$tempName')" -ForegroundColor Green

        $created = $null
        if (-not $DryRun) {
            try {
                $created = New-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardDef $newDef
            } catch {
                Write-Warning "      Failed to create dashboard '$tempName' for team '$($team.name)'. $_"
            }
        }

        if ($created -and $created.id) {
            $createdCount++

            # Delete old dashboard with the same final name
            if ($existingFinal) {
                Write-Host "      DELETE existing '$finalName' before rename" -ForegroundColor Red
                if (-not $DryRun) {
                    try {
                        Remove-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $existingFinal.id
                        $deletedCount++
                    } catch {
                        Write-Warning "        Failed to delete existing '$finalName' for team '$($team.name)'. $_"
                    }
                }
                $existingByName.Remove($finalName) | Out-Null
            }

            # Rename newly created dashboard from tempName to finalName
            if (-not $DryRun) {
                try {
                    $updatedDef = $created
                    $updatedDef.name = $finalName
                    $updated = Set-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $created.id -DashboardDef $updatedDef
                    if ($updated) {
                        $created = $updated
                    }
                } catch {
                    Write-Warning "      Failed to rename dashboard '$tempName' to '$finalName' for team '$($team.name)'. $_"
                }
            }

            $existingByName[$finalName] = $created
        } else {
            Write-Warning "      Skipped replace for '$finalName' because creation failed."
        }
    }

    # 4) Remove any remaining dashboards that are not part of the standard set
    $recommendedNames = $recommended | ForEach-Object { $_.name }
    $currentDashboards = @(Get-AdoDashboards -ProjectId $project.id -TeamId $team.id)

    foreach ($d in $currentDashboards) {
        if ($null -eq $d -or -not $d.PSObject.Properties['name']) { continue }

        $name   = $d.name
        $isTemp = $name -like "[TMP]*"

        if (-not $isTemp -and $name -in $recommendedNames) {
            continue
        }

        Write-Host "    DELETE non-standard dashboard '$name'" -ForegroundColor Red
        if (-not $DryRun) {
            try {
                Remove-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $d.id
                Write-Host "      Deleted dashboard '$name'." -ForegroundColor DarkGray
                $deletedCount++
            } catch {
                # Ignore failures such as last-dashboard constraints; script will continue.
                Write-Warning "      Failed to delete non-standard dashboard '$name' for team '$($team.name)'. $_"
            }
        }
    }
}

}

Write-Progress -Activity "Processing Projects" -Completed
Write-Host ""
Write-Host "Done. Created: $createdCount, Deleted: $deletedCount" -ForegroundColor Cyan