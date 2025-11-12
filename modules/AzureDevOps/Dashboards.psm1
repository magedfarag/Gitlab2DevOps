<#
.SYNOPSIS
    Dashboard and team settings

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Set-AdoTeamSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Configuring team settings..." -ForegroundColor Cyan
    
    $settingsConfigured = 0
    
    # Configure backlog levels (show Epics and Features)
    try {
        Write-LogLevelVerbose "[Set-AdoTeamSettings] Configuring backlog visibility"
        $backlogBody = @{
            backlogVisibilities = @{
                "Microsoft.EpicCategory" = $true
                "Microsoft.FeatureCategory" = $true
                "Microsoft.RequirementCategory" = $true
            }
            bugsBehavior = "asRequirements"  # Show bugs on backlog
        }
        
        Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings" -Body $backlogBody | Out-Null
        Write-Host "[SUCCESS] Configured backlog levels and bugs visibility" -ForegroundColor Green
        $settingsConfigured++
    }
    catch {
        Write-Warning "Failed to configure backlog settings: $_"
    }
    
    # Configure working days (Monday-Friday)
    try {
        Write-LogLevelVerbose "[Set-AdoTeamSettings] Configuring working days"
        $workingDaysBody = @{
            workingDays = @("monday", "tuesday", "wednesday", "thursday", "friday")
        }
        
        Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings" -Body $workingDaysBody | Out-Null
        Write-Host "[SUCCESS] Set working days to Mon-Fri" -ForegroundColor Green
        $settingsConfigured++
    }
    catch {
        Write-Warning "Failed to configure working days: $_"
    }
    
    # Set default iteration to current sprint (if iterations exist)
    try {
        $iterations = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings/iterations"
        if ($iterations -and $iterations.value -and $iterations.value.Count -gt 0) {
            $firstSprint = $iterations.value[0]
            
            Write-LogLevelVerbose "[Set-AdoTeamSettings] Setting default iteration to: $($firstSprint.name)"
            $defaultIterationBody = @{
                backlogIteration = $firstSprint.id
                defaultIteration = $firstSprint.id
            }
            
            Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings" -Body $defaultIterationBody | Out-Null
            Write-Host "[SUCCESS] Set default iteration to: $($firstSprint.name)" -ForegroundColor Green
            $settingsConfigured++
        }
        else {
            Write-Host "[INFO] No iterations found - skipping default iteration setup" -ForegroundColor Yellow
        }
    }
    catch {
        Write-LogLevelVerbose "[Set-AdoTeamSettings] Could not set default iteration: $_"
        Write-Host "[INFO] Default iteration not set (will use current date)" -ForegroundColor Yellow
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Team settings summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Configured: $settingsConfigured settings" -ForegroundColor Green
    Write-Host "  📊 Backlog levels: Epics → Features → Stories → Tasks" -ForegroundColor Gray
    Write-Host "  🐛 Bugs: Shown on backlog" -ForegroundColor Gray
    Write-Host "  📅 Working days: Mon-Fri" -ForegroundColor Gray
    
    return $settingsConfigured
}

#>
# Helper: Resolve dashboard endpoints for project/team - returns ordered endpoints to try
function Resolve-AdoDashboardEndpoints {
    param(
        [Parameter(Mandatory=$true)][string]$Project,
        [Parameter(Mandatory=$false)][string]$Team,
        [Parameter(Mandatory=$false)][string]$TeamId
    )

    $endpoints = @()
    if ($TeamId) {
        # Team-scoped endpoint (preferred when team exists)
        $endpoints += "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards"
    }

    # Project-scoped endpoint (fallback)
    $endpoints += "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards"

    return $endpoints
}

#>
function Search-Adodashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Creating team dashboard..." -ForegroundColor Cyan
    
    # Get team context (optional for fallback)
    $teamId = $null
    try {
        $teamContext = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))/teams/$([uri]::EscapeDataString($Team))"
        $teamId = $teamContext.id
    }
    catch {
        Write-LogLevelVerbose "[Search-Adodashboard] Team context not available; will attempt project-level dashboards as fallback. Error: $_"
    }
    
    # Check if dashboard already exists
    $dashboardName = "$Team - Overview"
    try {
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId

        $existingDashboards = $null
        foreach ($ep in $endpoints) {
            try {
                $existingDashboards = Invoke-AdoRest GET $ep -Preview
                break
            }
            catch {
                Write-LogLevelVerbose "[Search-Adodashboard] Dashboard GET failed for endpoint $ep - trying next. Error: $_"
            }
        }

        # Normalize response: some servers return dashboardEntries, others return value or direct array
        $entries = @()
        if ($existingDashboards -eq $null) { $entries = @() }
        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
        else { $entries = @($existingDashboards) }

        $existing = $entries | Where-Object { $_.name -eq $dashboardName }

        if ($existing) {
            Write-Host "[INFO] Dashboard '$dashboardName' already exists" -ForegroundColor Gray
            return $existing
        }
    }
    catch {
        Write-LogLevelVerbose "[Search-Adodashboard] Could not check existing dashboards: $_"
    }
    
    # Create dashboard
    try {
        Write-LogLevelVerbose "[Search-Adodashboard] Creating dashboard: $dashboardName"
        
        $dashboardBody = @{
            name = $dashboardName
            description = "Auto-generated team overview dashboard with key metrics and insights"
            dashboardScope = if ($teamId) { "project_Team" } else { "project" }
            groupId = if ($teamId) { $teamId } else { $null }
            widgets = @(
                # Row 1: Sprint Burndown + Velocity
                @{
                    name = "Sprint Burndown"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-work-web.microsoft-teams-sprint-burndown"
                },
                @{
                    name = "Velocity"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-work-web.microsoft-teams-velocity"
                },
                
                # Row 2: Work Items by State + Work Items by Assignment
                @{
                    name = "Work Items by State"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryId":"","chartType":"pie"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Work Items by Assigned To"
                    position = @{ row = 3; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryId":"","chartType":"stackBar"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                
                # Row 3: Query Tiles
                @{
                    name = "My Active Work"
                    position = @{ row = 5; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"My Active Work"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Active Bugs"
                    position = @{ row = 5; column = 2 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"Active Bugs"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Blocked Items"
                    position = @{ row = 5; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"Blocked Items"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Ready for Review"
                    position = @{ row = 5; column = 4 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"Ready for Review"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                }
            )
            _links = $null
        }
        
        $dashboard = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoRest POST $ep -Body $dashboardBody -Preview
                break
            }
            catch {
                $postErr = $_.Exception.Message
                # If duplicate dashboard name was reported, try to locate and return existing dashboard instead
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-LogLevelVerbose "[Search-Adodashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoRest GET $ep -Preview
                        $entries = @()
                        if ($existingDashboards -eq $null) { $entries = @() }
                        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                        else { $entries = @($existingDashboards) }

                        $found = $entries | Where-Object { $_.name -eq $dashboardName }
                        if ($found) {
                            Write-Host "[INFO] Found existing dashboard '$dashboardName' after duplicate error" -ForegroundColor Gray
                            return $found
                        }
                    }
                    catch {
                        Write-LogLevelVerbose "[Search-Adodashboard] Failed to locate existing dashboard after duplicate error: $_"
                    }
                }

                Write-LogLevelVerbose "[Search-Adodashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }
        
        Write-Host "[SUCCESS] Created team dashboard: $dashboardName" -ForegroundColor Green
        Write-Host ""
        Write-Host "[INFO] Dashboard widgets:" -ForegroundColor Cyan
        Write-Host "  📊 Sprint Burndown - Track sprint progress" -ForegroundColor Gray
        Write-Host "  📈 Velocity Chart - Team capacity over time" -ForegroundColor Gray
        Write-Host "  🥧 Work Items by State - Current work distribution" -ForegroundColor Gray
        Write-Host "  👥 Work Items by Assignment - Team workload balance" -ForegroundColor Gray
        Write-Host "  🎯 Query Tiles - Quick metrics (My Work, Bugs, Blocked, Review)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  📍 Location: Dashboards → $dashboardName" -ForegroundColor Gray
        
        return $dashboard
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found") {
            Write-Host ""
            Write-Host "ℹ️  [INFO] Dashboard API not available (common on on-premise servers)" -ForegroundColor Cyan
            Write-Host "    Dashboards must be created manually in Azure DevOps UI" -ForegroundColor DarkCyan
            Write-Host "    Navigate to: Overview → Dashboards → New Dashboard" -ForegroundColor DarkCyan
            Write-Host ""
        }
        else {
            Write-Warning "Failed to create dashboard: $_"
        }
        Write-LogLevelVerbose "[Search-Adodashboard] Error details: $($_.Exception.Message)"
        return $null
    }
}

#>
function Test-Adoqadashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Creating QA dashboard..." -ForegroundColor Cyan
    
    # Get team context (optional for fallback)
    $teamId = $null
    try {
        $teamContext = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))/teams/$([uri]::EscapeDataString($Team))"
        $teamId = $teamContext.id
    }
    catch {
        Write-LogLevelVerbose "[Test-Adoqadashboard] Team context not available; will attempt project-level dashboards as fallback. Error: $_"
    }
    
    # Check if QA dashboard already exists
    $dashboardName = "$Team - QA Metrics"
    try {
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId

        $existingDashboards = $null
        foreach ($ep in $endpoints) {
            try {
                $existingDashboards = Invoke-AdoRest GET $ep -Preview
                break
            }
            catch {
                Write-LogLevelVerbose "[Test-Adoqadashboard] Dashboard GET failed for endpoint $ep - trying next. Error: $_"
            }
        }

        # Normalize response
        $entries = @()
        if ($existingDashboards -eq $null) { $entries = @() }
        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
        else { $entries = @($existingDashboards) }

        $existing = $entries | Where-Object { $_.name -eq $dashboardName }

        if ($existing) {
            Write-Host "[INFO] QA dashboard '$dashboardName' already exists" -ForegroundColor Gray
            return $existing
        }
    }
    catch {
        Write-LogLevelVerbose "[Test-Adoqadashboard] Could not check existing dashboards: $_"
    }
    
    # Create QA dashboard with test and quality widgets
    try {
        Write-LogLevelVerbose "[Test-Adoqadashboard] Creating QA dashboard: $dashboardName"
        
        $dashboardBody = @{
            name = $dashboardName
            description = "QA metrics dashboard with test execution, bug tracking, and quality indicators"
            dashboardScope = if ($teamId) { "project_Team" } else { "project" }
            groupId = if ($teamId) { $teamId } else { $null }
            widgets = @(
                # Row 1: Test Execution Status (2x2) + Bugs by Severity (2x2)
                @{
                    name = "Test Execution Status"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Test Execution Status","chartType":"pie"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Bugs by Severity"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Bugs by Severity","chartType":"stackBar"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                
                # Row 2: Test Coverage (2x2) + Bugs by Priority (2x2)
                @{
                    name = "Test Coverage"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Test Coverage","chartType":"pie"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Bugs by Priority"
                    position = @{ row = 3; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Bugs by Priority","chartType":"pivot"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                
                # Row 3: Query Tiles (1x1 each) - Quick metrics
                @{
                    name = "Failed Test Cases"
                    position = @{ row = 5; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Failed Test Cases"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Regression Candidates"
                    position = @{ row = 5; column = 2 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Regression Candidates"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Bug Triage Queue"
                    position = @{ row = 5; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Bug Triage Queue"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Reopened Bugs"
                    position = @{ row = 5; column = 4 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Reopened Bugs"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                }
            )
            _links = $null
        }
        
        $dashboard = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoRest POST $ep -Body $dashboardBody -Preview
                break
            }
            catch {
                $postErr = $_.Exception.Message
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-LogLevelVerbose "[Test-Adoqadashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoRest GET $ep -Preview
                        $entries = @()
                        if ($existingDashboards -eq $null) { $entries = @() }
                        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                        else { $entries = @($existingDashboards) }

                        $found = $entries | Where-Object { $_.name -eq $dashboardName }
                        if ($found) {
                            Write-Host "[INFO] Found existing QA dashboard '$dashboardName' after duplicate error" -ForegroundColor Gray
                            return $found
                        }
                    }
                    catch {
                        Write-LogLevelVerbose "[Test-Adoqadashboard] Failed to locate existing QA dashboard after duplicate error: $_"
                    }
                }

                Write-LogLevelVerbose "[Test-Adoqadashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }
        
        Write-Host "[SUCCESS] Created QA dashboard: $dashboardName" -ForegroundColor Green
        Write-Host ""
        Write-Host "[INFO] QA dashboard widgets:" -ForegroundColor Cyan
        Write-Host "  🧪 Test Execution Status - Test case states (pie chart)" -ForegroundColor Gray
        Write-Host "  🐛 Bugs by Severity - Critical/High/Medium/Low distribution (stacked bar)" -ForegroundColor Gray
        Write-Host "  📊 Test Coverage - Requirements with test tracking (pie chart)" -ForegroundColor Gray
        Write-Host "  📈 Bugs by Priority - Priority-based bug distribution (pivot table)" -ForegroundColor Gray
        Write-Host "  ❌ Failed Test Cases - Count of failed tests (query tile)" -ForegroundColor Gray
        Write-Host "  🔄 Regression Candidates - Resolved bugs with regression tags (query tile)" -ForegroundColor Gray
        Write-Host "  🎯 Bug Triage Queue - New bugs awaiting triage (query tile)" -ForegroundColor Gray
        Write-Host "  🔁 Reopened Bugs - Regressed/reopened bug count (query tile)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  📍 Location: Dashboards → $dashboardName" -ForegroundColor Gray
        Write-Host "  💡 TIP: Configure chart colors in each widget's settings for better visibility" -ForegroundColor Yellow
        
        return $dashboard
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found") {
            Write-Host ""
            Write-Host "ℹ️  [INFO] QA Dashboard API not available (common on on-premise servers)" -ForegroundColor Cyan
            Write-Host "    Dashboards must be created manually in Azure DevOps UI" -ForegroundColor DarkCyan
            Write-Host ""
        }
        else {
            Write-Warning "Failed to create QA dashboard: $_"
        }
        Write-LogLevelVerbose "[Test-Adoqadashboard] Error details: $($_.Exception.Message)"
        return $null
    }
}

#>
function New-Adodevdashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating development dashboard..." -ForegroundColor Cyan
    
    try {
        # Check if dashboard already exists
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $null -TeamId $null
        $dashboards = $null
        foreach ($ep in $endpoints) {
            try {
                $dashboards = Invoke-AdoRest GET $ep -Preview
                break
            }
            catch {
                Write-LogLevelVerbose "[New-Adodevdashboard] Dashboard GET failed for endpoint $ep - trying next. Error: $_"
            }
        }

        $entries = @()
        if ($dashboards -and $dashboards.PSObject.Properties['value']) { $entries = $dashboards.value }
        elseif ($dashboards -is [array]) { $entries = $dashboards }
        elseif ($dashboards) { $entries = @($dashboards) }

        $devDashboard = $entries | Where-Object { $_.name -eq "Development Metrics" }

        if ($devDashboard) {
            Write-Host "  ℹ️ Development dashboard already exists" -ForegroundColor DarkYellow
            return
        }

        # Create dashboard
        $dashboardConfig = @{
            name = "Development Metrics"
            description = "Track PR velocity, code quality, and team productivity"
            dashboardScope = "project"
            widgets = @(
                # Pull Request Overview
                @{
                    name = "Active Pull Requests"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.PullRequestWidget"
                }
                # Build Success Rate
                @{
                    name = "Build Success Rate"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.BuildHistogramWidget"
                }
                # Work in Progress
                @{
                    name = "Work in Progress"
                    position = @{ row = 2; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-work-web.Microsoft.VisualStudioOnline.MyWork.WorkWidget"
                }
                # Sprint Burndown
                @{
                    name = "Sprint Burndown"
                    position = @{ row = 2; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.SprintBurndownWidget"
                }
                # Test Results Trend
                @{
                    name = "Test Pass Rate"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-test-web.test-results-trending-widget"
                }
            )
        }
        
        $dashboard = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $null -TeamId $null
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoRest POST $ep -Body $dashboardConfig -Preview
                break
            }
            catch {
                Write-Verbose "[New-Adodevdashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }
        if ($dashboard) { Write-Host "  ✅ Development Metrics dashboard created" -ForegroundColor Gray }
        
        # Create component tags wiki page - load from template
        $templatePath = Join-Path $PSScriptRoot "..\templates\ComponentTags.md"
        if (-not (Test-Path $templatePath)) {
            Write-Error "[Search-Adodashboard] Template file not found: $templatePath"
            return $null
        }
        $componentTagsContent = Get-Content -Path $templatePath -Raw -Encoding UTF8
        
        Set-AdoWikiPage $Project $WikiId "/Development/Component-Tags" $componentTagsContent
        Write-Host "  ✅ Component Tags wiki page created" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] Development dashboard created" -ForegroundColor Green
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found") {
            Write-Host "ℹ️  [INFO] Development Dashboard API not available (common on on-premise servers)" -ForegroundColor Cyan
        }
        else {
            Write-Warning "Failed to create development dashboard: $_"
        }
        Write-Verbose "[New-Adodevdashboard] Error details: $($_.Exception.Message)"
    }
}

#>
function New-AdoSecurityDashboard {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )
    
    Write-Host "[INFO] Creating Security Metrics dashboard..." -ForegroundColor Cyan
    
    try {
        $dashboardConfig = @{
            name = "Security Metrics"
            description = "Security vulnerability tracking, compliance status, and threat intelligence"
            dashboardScope = "project"
            widgets = @(
                @{
                    name = "Security Overview"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Vulnerability Trend"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Compliance Status"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget"
                }
            )
        }

        $dashboard = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $null -TeamId $null
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoRest POST $ep -Body $dashboardConfig -Preview
                break
            }
            catch {
                $postErr = $_.Exception.Message
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-Verbose "[New-AdoSecurityDashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoRest GET $ep -Preview
                        $entries = @()
                        if ($existingDashboards -eq $null) { $entries = @() }
                        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                        else { $entries = @($existingDashboards) }

                        $found = $entries | Where-Object { $_.name -eq $dashboardConfig.name }
                        if ($found) {
                            Write-Host "[INFO] Found existing Security Metrics dashboard after duplicate error" -ForegroundColor Gray
                            return $found
                        }
                    }
                    catch {
                        Write-Verbose "[New-AdoSecurityDashboard] Failed to locate existing dashboard after duplicate error: $_"
                    }
                }

                Write-Verbose "[New-AdoSecurityDashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }

        if ($dashboard) { Write-Host "  ✅ Security Metrics dashboard created" -ForegroundColor Gray }
        Write-Host "[SUCCESS] Security dashboard created" -ForegroundColor Green
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found") {
            Write-Host "ℹ️  [INFO] Security Dashboard API not available (common on on-premise servers)" -ForegroundColor Cyan
        }
        else {
            Write-Warning "Failed to create security dashboard: $_"
        }
        Write-Verbose "[New-AdoSecurityDashboard] Error details: $($_.Exception.Message)"
    }
}

#>
function Test-Adomanagementdashboard {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )
    
    Write-Host "[INFO] Creating Program Management dashboard..." -ForegroundColor Cyan
    
    try {
        $dashboardConfig = @{
            name = "Program Management"
            description = "Executive overview with program health, sprint progress, risks, and KPIs"
            dashboardScope = "project"
            widgets = @(
                @{
                    name = "Program Health"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget"
                },
                @{
                    name = "Sprint Velocity"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.VelocityWidget"
                },
                @{
                    name = "Active Risks"
                    position = @{ row = 2; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Sprint Burndown"
                    position = @{ row = 3; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.BurndownWidget"
                },
                @{
                    name = "Milestone Progress"
                    position = @{ row = 4; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryResultsWidget"
                },
                @{
                    name = "Cross-Team Dependencies"
                    position = @{ row = 5; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                }
            )
        }
        
        $dashboard = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $null -TeamId $null
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoRest POST $ep -Body $dashboardConfig -Preview
                break
            }
            catch {
                $postErr = $_.Exception.Message
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-Verbose "[Test-Adomanagementdashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoRest GET $ep -Preview
                        $entries = @()
                        if ($existingDashboards -eq $null) { $entries = @() }
                        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                        else { $entries = @($existingDashboards) }

                        $found = $entries | Where-Object { $_.name -eq $dashboardConfig.name }
                        if ($found) {
                            Write-Host "[INFO] Found existing Program Management dashboard after duplicate error" -ForegroundColor Gray
                            return $found
                        }
                    }
                    catch {
                        Write-Verbose "[Test-Adomanagementdashboard] Failed to locate existing dashboard after duplicate error: $_"
                    }
                }

                Write-Verbose "[Test-Adomanagementdashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }

        if ($dashboard) { Write-Host "  ✅ Program Management dashboard created" -ForegroundColor Gray }
        Write-Host "[SUCCESS] Management dashboard created" -ForegroundColor Green
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found") {
            Write-Host "ℹ️  [INFO] Management Dashboard API not available (common on on-premise servers)" -ForegroundColor Cyan
        }
        else {
            Write-Warning "Failed to create management dashboard: $_"
        }
        Write-Verbose "[Test-Adomanagementdashboard] Error details: $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Set-AdoTeamSettings',
    'Search-Adodashboard',
    'Test-Adoqadashboard',
    'New-Adodevdashboard',
    'New-AdoSecurityDashboard',
    'Test-Adomanagementdashboard'
)

Export-ModuleMember -Function 'Resolve-AdoDashboardEndpoints'

