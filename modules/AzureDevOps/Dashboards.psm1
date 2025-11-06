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
function Ensure-AdoTeamSettings {
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
        Write-Verbose "[Ensure-AdoTeamSettings] Configuring backlog visibility"
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
        Write-Verbose "[Ensure-AdoTeamSettings] Configuring working days"
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
            
            Write-Verbose "[Ensure-AdoTeamSettings] Setting default iteration to: $($firstSprint.name)"
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
        Write-Verbose "[Ensure-AdoTeamSettings] Could not set default iteration: $_"
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
function Ensure-AdoDashboard {
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
        Write-Verbose "[Ensure-AdoDashboard] Team context not available; will attempt project-level dashboards as fallback. Error: $_"
    }
    
    # Check if dashboard already exists
    $dashboardName = "$Team - Overview"
    try {
        $existingDashboards = $null
        if ($teamId) {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Preview
        }
        else {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Preview
        }
        $existing = $existingDashboards.dashboardEntries | Where-Object { $_.name -eq $dashboardName }

        if ($existing) {
            Write-Host "[INFO] Dashboard '$dashboardName' already exists" -ForegroundColor Gray
            return $existing
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoDashboard] Could not check existing dashboards: $_"
    }
    
    # Create dashboard
    try {
        Write-Verbose "[Ensure-AdoDashboard] Creating dashboard: $dashboardName"
        
        $dashboardBody = @{
            name = $dashboardName
            description = "Auto-generated team overview dashboard with key metrics and insights"
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
        if ($teamId) {
            try {
                $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
            }
            catch {
                # Fallback to project-level dashboards (some servers don't support team route)
                Write-Verbose "[Ensure-AdoDashboard] Team dashboards API failed, attempting project-level fallback: $_"
            }
        }
        if (-not $dashboard) {
            $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
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
        Write-Warning "Failed to create dashboard: $_"
        Write-Verbose "[Ensure-AdoDashboard] Error details: $($_.Exception.Message)"
        return $null
    }
}

#>
function Ensure-AdoQADashboard {
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
        Write-Verbose "[Ensure-AdoQADashboard] Team context not available; will attempt project-level dashboards as fallback. Error: $_"
    }
    
    # Check if QA dashboard already exists
    $dashboardName = "$Team - QA Metrics"
    try {
        $existingDashboards = $null
        if ($teamId) {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Preview
        }
        else {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Preview
        }
        $existing = $existingDashboards.dashboardEntries | Where-Object { $_.name -eq $dashboardName }

        if ($existing) {
            Write-Host "[INFO] QA dashboard '$dashboardName' already exists" -ForegroundColor Gray
            return $existing
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoQADashboard] Could not check existing dashboards: $_"
    }
    
    # Create QA dashboard with test and quality widgets
    try {
        Write-Verbose "[Ensure-AdoQADashboard] Creating QA dashboard: $dashboardName"
        
        $dashboardBody = @{
            name = $dashboardName
            description = "QA metrics dashboard with test execution, bug tracking, and quality indicators"
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
        if ($teamId) {
            try {
                $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
            }
            catch {
                Write-Verbose "[Ensure-AdoQADashboard] Team dashboards API failed, attempting project-level fallback: $_"
            }
        }
        if (-not $dashboard) {
            $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
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
        Write-Warning "Failed to create QA dashboard: $_"
        Write-Verbose "[Ensure-AdoQADashboard] Error details: $($_.Exception.Message)"
        return $null
    }
}

#>
function Ensure-AdoDevDashboard {
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
        $dashboards = Invoke-AdoRest GET "/$Project/_apis/dashboard/dashboards?api-version=7.1-preview.3"
        $devDashboard = $dashboards.dashboardEntries | Where-Object { $_.name -eq "Development Metrics" }
        
        if ($devDashboard) {
            Write-Host "  ℹ️ Development dashboard already exists" -ForegroundColor DarkYellow
            return
        }
        
        # Create dashboard
        $dashboardConfig = @{
            name = "Development Metrics"
            description = "Track PR velocity, code quality, and team productivity"
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
        
        $dashboard = Invoke-AdoRest POST "/$Project/_apis/dashboard/dashboards?api-version=7.1-preview.3" -Body $dashboardConfig
        Write-Host "  ✅ Development Metrics dashboard created" -ForegroundColor Gray
        
        # Create component tags wiki page - load from template
        $templatePath = Join-Path $PSScriptRoot "..\templates\ComponentTags.md"
        if (-not (Test-Path $templatePath)) {
            Write-Error "[Ensure-AdoDashboard] Template file not found: $templatePath"
            return $null
        }
        $componentTagsContent = Get-Content -Path $templatePath -Raw -Encoding UTF8
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Component-Tags" $componentTagsContent
        Write-Host "  ✅ Component Tags wiki page created" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] Development dashboard created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create development dashboard: $_"
        Write-Host "[INFO] Note: Dashboard creation requires appropriate permissions" -ForegroundColor DarkYellow
    }
}

#>
function Ensure-AdoSecurityDashboard {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )
    
    Write-Host "[INFO] Creating Security Metrics dashboard..." -ForegroundColor Cyan
    
    try {
        $dashboardConfig = @{
            name = "Security Metrics"
            description = "Security vulnerability tracking, compliance status, and threat intelligence"
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
        
        $dashboard = Invoke-AdoRest POST "/$Project/_apis/dashboard/dashboards?api-version=7.1-preview.3" -Body $dashboardConfig
        Write-Host "  ✅ Security Metrics dashboard created" -ForegroundColor Gray
        Write-Host "[SUCCESS] Security dashboard created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create security dashboard: $_"
        Write-Host "[INFO] Note: Dashboard creation requires appropriate permissions" -ForegroundColor DarkYellow
    }
}

#>
function Ensure-AdoManagementDashboard {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )
    
    Write-Host "[INFO] Creating Program Management dashboard..." -ForegroundColor Cyan
    
    try {
        $dashboardConfig = @{
            name = "Program Management"
            description = "Executive overview with program health, sprint progress, risks, and KPIs"
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
        
        $dashboard = Invoke-AdoRest POST "/$Project/_apis/dashboard/dashboards?api-version=7.1-preview.3" -Body $dashboardConfig
        Write-Host "  ✅ Program Management dashboard created" -ForegroundColor Gray
        Write-Host "[SUCCESS] Management dashboard created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create management dashboard: $_"
        Write-Host "[INFO] Note: Dashboard creation requires appropriate permissions" -ForegroundColor DarkYellow
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Ensure-AdoTeamSettings',
    'Ensure-AdoDashboard',
    'Ensure-AdoQADashboard',
    'Ensure-AdoDevDashboard',
    'Ensure-AdoSecurityDashboard',
    'Ensure-AdoManagementDashboard'
)
