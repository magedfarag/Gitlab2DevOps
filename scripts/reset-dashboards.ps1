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
$newWitContribution     = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.NewWorkItemWidget"
$newWitConfig           = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.NewWorkItemWidget.Configuration"

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
$script:DashboardApiVersion = if ($dashboardApiOverride) { $dashboardApiOverride } else { '7.0-preview.3' }

# For on-prem ADO, TLS 1.2 avoids handshake issues
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$patBytes   = [Text.Encoding]::ASCII.GetBytes(":$pat")
$patEncoded = [Convert]::ToBase64String($patBytes)

$script:BaseUrl = "$collection"
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

        [switch] $IgnoreNotFound
    )

    if ([string]::IsNullOrWhiteSpace($RelativeUrl)) {
        throw "Internal error: RelativeUrl is null or empty in Invoke-AdoRest."
    }

    $uri = if ($RelativeUrl.StartsWith('http', [System.StringComparison]::OrdinalIgnoreCase)) {
        $RelativeUrl
    } else {
        "$($script:BaseUrl)/$($RelativeUrl.TrimStart('/'))"
    }

    $params = @{
        Method  = $Method
        Uri     = $uri
        Headers = $script:DefaultHeaders
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
    if ($result.value) { return @($result.value) }
    if ($result.dashboardEntries) { return @($result.dashboardEntries) }
    if ($result.dashboards) { return @($result.dashboards) }
    return @()
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

# -------------------------------------------------------
# 5. Recommended SDLC dashboards (widgets)
# -------------------------------------------------------
function Get-RecommendedDashboardDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectName,

        [Parameter(Mandatory)]
        [string] $TeamName
    )

    # Project-level URLs (default team) following standard Azure DevOps hubs
    $projectBase = "$collection/$ProjectName"
    $boardsUrl   = "$projectBase/_boards/board"
    $reposUrl    = "$projectBase/_git"
    $buildsUrl   = "$projectBase/_build"
    $wikiUrl     = "$projectBase/_wiki/wikis"
    $testPlansUrl= "$projectBase/_testPlans"
    $workItemsUrl= "$projectBase/_workitems"

    $businessMd = @"
# Business / Product

**Purpose:** Product vision, value and delivery focus for *$ProjectName / $TeamName*.

**Key navigation**

- [Boards]($boardsUrl)
- [Repos]($reposUrl)
- [Pipelines]($buildsUrl)
- [Wiki]($wikiUrl)
- [Test Plans]($testPlansUrl)

**Checks**

- Are we delivering the right items first?
- Which epics or features are blocked?
- How does current scope compare to roadmap?
"@
$devMd = @"
### Engineering / Dev

- Project: **$ProjectName**
- Team: **$TeamName**

Use this dashboard to:
- Link to sprints, boards, and pull requests.
- Pin build / pipeline overviews.
- Track branch policy and code health signals.
"@
$qaMd = @"
### Quality / Testing

- Project: **$ProjectName**
- Team: **$TeamName**

Use this dashboard to:
- Link to test plans and regression suites.
- Pin defect queries (critical, escape defects, aging).
- Track test completion vs. scope for the release.
"@
$opsMd = @"
### Operations / Release

- Project: **$ProjectName**
- Team: **$TeamName**

Use this dashboard to:
- Link to release / deployment pipelines.
- Pin incident and hotfix queries.
- Surface SLO/SLA metrics and post-mortem links.
"@

    $dashboards = @()

    $dashboards = @()
    $dashboards = @()

    function New-SimpleDashboardDef {
        param(
            [string] $Name,
            [int]    $Position,
            [string] $MarkdownText
        )

        return @{
            name            = $Name
            position        = $Position
            refreshInterval = 0
            widgets         = @(
                @{
                    name                        = "Overview"
                    position                    = @{ row = 1; column = 1 }
                    size                        = @{ rowSpan = 2; columnSpan = 4 }
                    settings                    = $MarkdownText
                    settingsVersion             = $settingsVersion
                    contributionId              = $markdownContribution
                    configurationContributionId = $markdownConfig
                },
                @{
                    name            = "Team Members"
                    position        = @{ row = 3; column = 1 }
                    size            = @{ rowSpan = 1; columnSpan = 2 }
                    settings        = $null
                    settingsVersion = $settingsVersion
                    contributionId  = $teamMembersContribution
                },
                @{
                    name                        = "New Work Item"
                    position                    = @{ row = 3; column = 3 }
                    size                        = @{ rowSpan = 1; columnSpan = 2 }
                    settings                    = $null
                    settingsVersion             = $settingsVersion
                    contributionId              = $newWitContribution
                    configurationContributionId = $newWitConfig
                }
            )
        }
    }

    $dashboards += New-SimpleDashboardDef -Name "01 - Business / Product"   -Position 1 -MarkdownText $businessMd
    $dashboards += New-SimpleDashboardDef -Name "02 - Engineering / Dev"    -Position 2 -MarkdownText $devMd
    $dashboards += New-SimpleDashboardDef -Name "03 - Quality / Testing"    -Position 3 -MarkdownText $qaMd
    $dashboards += New-SimpleDashboardDef -Name "04 - Operations / Release" -Position 4 -MarkdownText $opsMd

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

foreach ($project in $projects) {
    $projectIndex = [array]::IndexOf($projects, $project) + 1
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

        # 2) Recommended SDLC dashboards for this team
        $recommended = @(Get-RecommendedDashboardDefinitions -ProjectName $project.name -TeamName $team.name)

        # Map recommended by name for fast lookup
        $recommendedByName = @{}
        foreach ($def in $recommended) {
            if ($null -ne $def -and $def.name) {
                $recommendedByName[$def.name] = $def
            }
        }

        # Map existing dashboards by name
        $existingByName = @{}
        foreach ($d in $dashboards) {
            if ($null -ne $d -and $d.PSObject.Properties['name']) {
                $existingByName[$d.name] = $d
            }
        }

        if ($ClearExistingDashboards) {
            # --------- RESET MODE ---------

            $primaryName = "01 - Business / Product"

            # 2.1 Ensure the primary recommended dashboard exists
            if (-not $existingByName.ContainsKey($primaryName) -or $Force) {
                if (-not $recommendedByName.ContainsKey($primaryName)) {
                    throw "Internal error: recommended dashboard '$primaryName' not found."
                }

                $primaryDef = $recommendedByName[$primaryName]
                Write-Host "    CREATE primary '$primaryName' before deleting old dashboards..." -ForegroundColor Green

                if (-not $DryRun) {
                    $created = New-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardDef $primaryDef
                    if ($created -and $created.id) {
                        Write-Host "      -> primary created id $($created.id)" -ForegroundColor DarkGreen
                        # Track it as existing now
                        $dashboards += $created
                        $existingByName[$primaryName] = $created
                        $createdCount++
                    }
                }
            } else {
                Write-Host "    Primary '$primaryName' already exists; will keep it." -ForegroundColor DarkGray
            }

            # 2.2 Delete all dashboards that are NOT in the recommended set
            $recommendedNamesSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($name in $recommendedByName.Keys) {
                [void]$recommendedNamesSet.Add($name)
            }

            $toDelete = @($dashboards | Where-Object { -not $recommendedNamesSet.Contains($_.name) })

            if ($toDelete.Count -gt 0) {
                Write-Host "    Deleting $($toDelete.Count) non-standard dashboard(s)..." -ForegroundColor Red
                foreach ($dash in $toDelete) {
                    Write-Host "      DELETE '$($dash.name)' ($($dash.id))"
                    if (-not $DryRun) {
                        Remove-AdoDashboard -ProjectId $project.id -TeamId $team.id -DashboardId $dash.id
                        $deletedCount++
                    }
                }
            } else {
                Write-Host "    No non-standard dashboards to delete." -ForegroundColor DarkGray
            }

            # Refresh dashboards after deletion (in case something changed)
            $dashboards     = @(Get-AdoDashboards -ProjectId $project.id -TeamId $team.id)
            $existingByName = @{}
            foreach ($d in $dashboards) {
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
                        Write-Host "      -> created id $($created.id)" -ForegroundColor DarkGreen
                        $createdCount++
                    }
                }
            }
        }
        else {
            # --------- ADDITIVE MODE (no delete) ---------
            Write-Host "    Existing dashboards kept (use -ClearExistingDashboards to wipe)." -ForegroundColor DarkGray

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
                        Write-Host "      -> created id $($created.id)" -ForegroundColor DarkGreen
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