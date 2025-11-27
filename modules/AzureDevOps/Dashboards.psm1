<#
.SYNOPSIS
    Dashboard and team settings

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Dashboard REST helper defaults (order: prefer latest, fall back for Azure DevOps Server)
$script:dashboardApiVersions = @('7.1-preview.3', '7.1-preview.1', '7.0', '6.0')

function Invoke-AdoDashboardRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        $Body,

        [string]$ContentType,

        [switch]$ReturnNullOnNotFound
    )

    $lastError = $null
    foreach ($apiVersion in $script:dashboardApiVersions) {
        try {
            $invokeParams = @{ ApiVersion = $apiVersion }
            if ($PSBoundParameters.ContainsKey('Body')) { $invokeParams['Body'] = $Body }
            if ($PSBoundParameters.ContainsKey('ContentType')) { $invokeParams['ContentType'] = $ContentType }
            if ($ReturnNullOnNotFound.IsPresent) { $invokeParams['ReturnNullOnNotFound'] = $true }

            switch ($Method.ToUpperInvariant()) {
                'GET'    { return Invoke-AdoRest GET $Endpoint @invokeParams }
                'POST'   { return Invoke-AdoRest POST $Endpoint @invokeParams }
                'PATCH'  { return Invoke-AdoRest PATCH $Endpoint @invokeParams }
                'DELETE' { return Invoke-AdoRest DELETE $Endpoint @invokeParams }
            }
        }
        catch {
            $lastError = $_
            $statusCode = $null
            try {
                if ($_.Exception -and $_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }
            catch {
                $statusCode = $null
            }

            $message = if ($_.Exception) { $_.Exception.Message } else { $_.ToString() }
            $retryable = $false
            if ($statusCode -in 400, 404, 405) {
                $retryable = $true
            }
            elseif ($message -match 'No HTTP resource was found' -or
                    $message -match 'controller for path' -or
                    $message -match 'api-version' -or
                    $message -match 'TF10158' -or
                    $message -match 'Not Found') {
                $retryable = $true
            }

            if (-not $retryable) {
                throw
            }
        }
    }

    if ($lastError) {
        throw $lastError
    }

    return $null
}


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

# Helper: Ensure dashboard names meet Azure DevOps length limits (32 chars)
function Truncate-DashboardName {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$MaxLength = 32
    )

    if (-not $Name) { return $Name }
    if ($Name.Length -le $MaxLength) { return $Name }

    $truncated = $Name.Substring(0, $MaxLength)
    Write-Host "[WARN] Dashboard name too long (length $($Name.Length)). Truncating to $MaxLength chars: '$truncated'" -ForegroundColor Yellow
    return $truncated
}


# Helper: Resolve dashboard endpoints for project/team - returns ordered endpoints to try
function Resolve-AdoDashboardEndpoints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter()][string]$Team,
        [Parameter()][string]$TeamId,     # kept for signature compatibility, not used for route
        [Parameter()][string]$ProjectId   # kept for signature compatibility, not used for route
    )

    $endpoints = @()
    $projEnc = [uri]::EscapeDataString($Project)
    $teamNameEnc = if ($Team) { [uri]::EscapeDataString($Team) } else { $null }

    # 1) Always try project-scoped dashboards first
    #    GET https://{org}/{project}/_apis/dashboard/dashboards
    $endpoints += "/$projEnc/_apis/dashboard/dashboards"

    # 2) If we have a team name, also try the standard team-scoped pattern
    #    GET https://{org}/{project}/{team}/_apis/dashboard/dashboards
    if ($teamNameEnc) {
        $endpoints += "/$projEnc/$teamNameEnc/_apis/dashboard/dashboards"
    }

    return $endpoints | Select-Object -Unique
}

function Get-AdoDashboardContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$Team
    )

    $projEnc   = [uri]::EscapeDataString($Project)
    $teamId    = $null
    $projectId = $null

    # 1) Resolve project once, reliably
    try {
        $projInfo = Invoke-AdoRest GET "/_apis/projects/$projEnc"
        if ($projInfo -and $projInfo.PSObject.Properties['id']) {
            $projectId = $projInfo.id
        }
    }
    catch {
        Write-LogLevelVerbose "[Dashboards] Project context lookup failed for $($Project): $_"
    }

    # 2) Resolve team by listing teams, not by hitting /teams/{TeamName}
    if ($projectId -and $Team) {
        try {
            # List all teams for this project (no 404, just empty list if none)
            $teams = Invoke-AdoRest GET "/_apis/projects/$projEnc/teams"

            if ($teams -and $teams.value) {
                # Accept either the explicit name or the conventional '<Project> Team'
                $candidateNames = @($Team, "$Project Team")

                $match = $teams.value |
                    Where-Object { $candidateNames -contains $_.name } |
                    Select-Object -First 1

                if ($match) {
                    $teamId = $match.id
                }
                else {
                    Write-LogLevelVerbose "[Dashboards] No team matching '$Team' or '$Project Team' in project '$Project'"
                }
            }
        }
        catch {
            Write-LogLevelVerbose "[Dashboards] Team list lookup failed for $($Project)/$($Team): $_"
        }
    }

    return [pscustomobject]@{
        TeamId    = $teamId
        ProjectId = $projectId
    }
}

# Helper: Delete a dashboard by id using multiple endpoint patterns
function Remove-AdoDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter()][string]$Team,
        [Parameter()][string]$ProjectId,
        [Parameter()][string]$TeamId,
        [Parameter(Mandatory)][string]$DashboardId,
        [string]$DashboardUrl
    )

    $projEnc   = [uri]::EscapeDataString($Project)
    $projIdEnc = if ($ProjectId) { [uri]::EscapeDataString($ProjectId) } else { $projEnc }
    $teamNameEnc = if ($Team) { [uri]::EscapeDataString($Team) } else { $null }
    $teamIdEnc = if ($TeamId) { [uri]::EscapeDataString($TeamId) } else { $null }
    $dashIdEnc = [uri]::EscapeDataString($DashboardId)

    $candidateEndpoints = @()

    if ($DashboardUrl) {
        $candidateEndpoints += ($DashboardUrl -match 'api-version=') ? $DashboardUrl : "$DashboardUrl`?api-version=$($script:dashboardApiVersions[0])"
    }

    if ($teamNameEnc) { $candidateEndpoints += "/$projEnc/$teamNameEnc/_apis/dashboard/dashboards/$dashIdEnc" }
    if ($teamIdEnc) {
        $candidateEndpoints += "/_apis/projects/$projIdEnc/teams/$teamIdEnc/dashboard/dashboards/$dashIdEnc"
        $candidateEndpoints += "/$projEnc/_apis/dashboard/dashboards/$($dashIdEnc)?teamId=$teamIdEnc"
        $candidateEndpoints += "/_apis/dashboard/dashboards/$($dashIdEnc)?teamId=$teamIdEnc&projectId=$projIdEnc"
    }

    # Project-scoped fallbacks
    $candidateEndpoints += "/$projEnc/_apis/dashboard/dashboards/$dashIdEnc"
    $candidateEndpoints += "/_apis/dashboard/dashboards/$($dashIdEnc)?projectId=$projIdEnc"

    foreach ($ep in $candidateEndpoints | Where-Object { $_ } | Select-Object -Unique) {
        try {
            Invoke-AdoDashboardRest -Method DELETE -Endpoint $ep | Out-Null
            return $true
        }
        catch {
            Write-LogLevelVerbose "[Dashboards] DELETE failed for $($ep): $($_.Exception.Message)"
        }
    }

    return $false
}


function Search-Adodashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Creating team dashboard..." -ForegroundColor Cyan
    
    # Resolve team/project context (optional for fallback)
    $context = Get-AdoDashboardContext -Project $Project -Team $Team
    $teamId = $context.TeamId
    $projectId = $context.ProjectId
    
    # Check if dashboard already exists
    $dashboardName = "$Team - Overview"
    # Ensure dashboard name meets ADO max length
    $dashboardName = Truncate-DashboardName $dashboardName
    try {
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId

        $existingDashboards = $null
        foreach ($ep in $endpoints) {
            try {
                $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
                break
            }
            catch {
                $statusMessage = $null
                try {
                    if ($_.Exception -and $_.Exception.Response) {
                        $statusMessage = "$([int]$_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)"
                    }
                }
                catch { $statusMessage = $null }
                Write-LogLevelVerbose "[Search-Adodashboard] Dashboard GET failed for endpoint $ep - trying next. Error: $_"
                if ($statusMessage) {
                    Write-Warning "[Search-Adodashboard] GET $ep failed ($statusMessage)."
                }
                else {
                    Write-Warning "[Search-Adodashboard] GET $ep failed: $($_.Exception.Message)"
                }
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
            # Note: Dashboard widget updates are not supported in this Azure DevOps version
            # The existing dashboard will be used as-is
            return $existing
        }
    }
    catch {
        Write-LogLevelVerbose "[Search-Adodashboard] Could not check existing dashboards: $_"
    }
    
    # Create dashboard if it doesn't exist
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
        $lastPostError = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoDashboardRest -Method POST -Endpoint $ep -Body $dashboardBody
                break
            }
            catch {
                $lastPostError = $_
                $postErr = $_.Exception.Message
                # If duplicate dashboard name was reported, try to locate and return existing dashboard instead
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName' -or $postErr -match 'already exists' -or $postErr -match '409')) {
                    Write-LogLevelVerbose "[Search-Adodashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
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

                $statusMessage = $null
                try {
                    if ($_.Exception -and $_.Exception.Response) {
                        $statusMessage = "$([int]$_.Exception.Response.StatusCode) $($_.Exception.Response.StatusDescription)"
                    }
                }
                catch { $statusMessage = $null }
                Write-LogLevelVerbose "[Search-Adodashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
                if ($statusMessage) {
                    Write-Warning "[Search-Adodashboard] POST $ep failed while creating dashboard '$dashboardName' ($statusMessage)."
                }
                else {
                    Write-Warning "[Search-Adodashboard] POST $ep failed while creating dashboard '$dashboardName': $($_.Exception.Message)"
                }
            }
        }

        if (-not $dashboard) {
            if ($lastPostError) {
                throw $lastPostError
            }

            throw "Failed to create dashboard '$dashboardName' for project '$Project' and team '$Team'."
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
        if ($_ -match "404|Not Found|500|Internal Server Error") {
            Write-Host ""
            Write-Host "ℹ️  [INFO] Dashboard API not available (common on on-premise servers or API issues)" -ForegroundColor Cyan
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


function Test-Adoqadashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team",

        [switch]$Replace
    )
    
    Write-Host "[INFO] Creating QA dashboard..." -ForegroundColor Cyan
    
    # Get team/project context (optional for fallback)
    $context = Get-AdoDashboardContext -Project $Project -Team $Team
    $teamId = $context.TeamId
    $projectId = $context.ProjectId
    
    # Check if QA dashboard already exists
    $dashboardName = "$Team - QA Metrics"
    # Ensure dashboard name meets ADO max length
    $dashboardName = Truncate-DashboardName $dashboardName
    try {
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId

        $existingDashboards = $null
        foreach ($ep in $endpoints) {
            try {
                $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
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
            if ($Replace) {
                Write-Host "[INFO] Replacing existing QA dashboard '$dashboardName'" -ForegroundColor Yellow
                $removed = Remove-AdoDashboard -Project $Project -Team $Team -ProjectId $projectId -TeamId $teamId -DashboardId $existing.id -DashboardUrl $existing.url
                if (-not $removed) {
                    Write-Warning "[QADashboard] Failed to remove existing dashboard; attempting to recreate anyway."
                }
            }
            else {
                Write-Host "[INFO] QA dashboard '$dashboardName' already exists" -ForegroundColor Gray
                return $existing
            }
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
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoDashboardRest -Method POST -Endpoint $ep -Body $dashboardBody
                break
            }
            catch {
                $postErr = $_.Exception.Message
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-LogLevelVerbose "[Test-Adoqadashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
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
        if ($_ -match "404|Not Found|500|Internal Server Error") {
            Write-Host ""
            Write-Host "ℹ️  [INFO] QA Dashboard API not available (common on on-premise servers or API issues)" -ForegroundColor Cyan
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


function New-Adodevdashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$WikiId,

        [string]$Team,

        [switch]$Replace
    )
    
    Write-Host "[INFO] Attempting to create development dashboard for '$Project' (Team: $Team)..." -ForegroundColor Cyan

    if (-not $Team) { $Team = "$Project Team" }

    $context = Get-AdoDashboardContext -Project $Project -Team $Team
    $teamId = $context.TeamId
    $projectId = $context.ProjectId

    $result = [pscustomobject]@{ status = "unknown"; message = $null }

    try {
        # Check if dashboard already exists
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId
        $dashboards = $null
        foreach ($ep in $endpoints) {
            try {
                $dashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
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
            if ($Replace) {
                Write-Host "  [INFO] Replacing existing Development dashboard for '$Project' (Team: $Team)" -ForegroundColor Yellow
                $removed = Remove-AdoDashboard -Project $Project -Team $Team -ProjectId $projectId -TeamId $teamId -DashboardId $devDashboard.id -DashboardUrl $devDashboard.url
                if (-not $removed) {
                    Write-Warning "[DevDashboard] Failed to remove existing dashboard; attempting to recreate anyway."
                }
            }
            else {
                Write-Host "  ℹ️ Development dashboard already exists for '$Project' (Team: $Team)" -ForegroundColor DarkYellow
                $result.status = "skipped"
                $result.message = "Dashboard already exists."
                return $result
            }
        }

        Write-Host "[INFO] Creating development dashboard for '$Project' (Team: $Team)..." -ForegroundColor Cyan
        # Create dashboard
        $dashboardConfig = @{
            name = Truncate-DashboardName "Development Metrics"
            description = "Track PR velocity, code quality, and team productivity"
            dashboardScope = if ($teamId) { "project_Team" } else { "project" }
            groupId = if ($teamId) { $teamId } else { $null }
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
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoDashboardRest -Method POST -Endpoint $ep -Body $dashboardConfig
                break
            }
            catch {
                Write-Verbose "[New-Adodevdashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }
        if (-not $dashboard) {
            throw "Failed to create Development Metrics dashboard for team '$Team'."
        }
        Write-Host "  ✅ Development Metrics dashboard created" -ForegroundColor Gray
        
        # Create component tags wiki page - load from template (best effort)
        $templatePath = Join-Path $PSScriptRoot "..\templates\ComponentTags.md"
        if (-not (Test-Path $templatePath)) {
            Write-Error "[New-Adodevdashboard] Template file not found: $templatePath"
            return $result
        }
        $componentTagsContent = Get-Content -Path $templatePath -Raw -Encoding UTF8

        $resolvedWikiId = $null

        try {
            $projEnc = [uri]::EscapeDataString($Project)

            # 1) If caller passed -WikiId, validate it against Wiki GET API.
            if ($WikiId) {
                Write-LogLevelVerbose "[Dashboards] Validating explicit WikiId '$WikiId' for project '$Project'"
                $candidate = Invoke-AdoRest GET "/$projEnc/_apis/wiki/wikis/$([uri]::EscapeDataString($WikiId))" -ReturnNullOnNotFound
                if ($candidate) {
                    # Use the canonical id from the service (works for id or name). 
                    if ($candidate.PSObject.Properties['id']) {
                        $resolvedWikiId = $candidate.id
                    }
                    else {
                        $resolvedWikiId = $WikiId
                    }
                }
                else {
                    Write-LogLevelVerbose "[Dashboards] Wiki '$WikiId' not found in project '$Project'; falling back to auto-discovery."
                }
            }

            # 2) If no valid wiki yet, auto-discover from the project’s wikis list.
            if (-not $resolvedWikiId) {
                Write-LogLevelVerbose "[Dashboards] Discovering wiki for project '$Project'"
                $wikiList = Invoke-AdoRest GET "/$projEnc/_apis/wiki/wikis" -ReturnNullOnNotFound
                if ($wikiList) {
                    $wikis = @()
                    if ($wikiList.PSObject.Properties['value'] -and $wikiList.value) {
                        $wikis = $wikiList.value
                    }
                    elseif ($wikiList.PSObject.Properties['id']) {
                        $wikis = @($wikiList)
                    }

                    if ($wikis.Count -gt 0) {
                        # Prefer project wiki if available, else first wiki. 
                        $projectWiki = $wikis | Where-Object { $_.type -eq "projectWiki" } | Select-Object -First 1
                        $selected = if ($projectWiki) { $projectWiki } else { $wikis[0] }

                        $resolvedWikiId = $selected.id
                        Write-LogLevelVerbose "[Dashboards] Using wiki '$($selected.name)' (id=$resolvedWikiId, type=$($selected.type)) for project '$Project'"
                    }
                }
            }
        }
        catch {
            Write-LogLevelVerbose "[Dashboards] Failed to resolve wiki id for $($Project): $_"
        }

        if ($resolvedWikiId) {
            try {
                Set-AdoWikiPage $Project $resolvedWikiId "/Development/Component-Tags" $componentTagsContent
                Write-Host "  ✅ Component Tags wiki page created" -ForegroundColor Gray
            }
            catch {
                Write-LogLevelVerbose "[Dashboards] Failed to create Component Tags page for $($Project): $($_.Exception.Message)"
            }
        }
        else {
            Write-LogLevelVerbose "[Dashboards] Skipping Component Tags page; no wiki found for $Project."
        }

        Write-Host "[SUCCESS] Development dashboard created for '$Project' (Team: $Team)" -ForegroundColor Green
        $result.status  = "created"
        $result.message = "Development dashboard and Component Tags page created."
        return $result

    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found|500|Internal Server Error") {
            Write-Host "ℹ️  [INFO] Development Dashboard API not available (common on on-premise servers or API issues)" -ForegroundColor Cyan
            $result.status = "failed"
            $result.message = "Dashboard API not available."
        }
        else {
            Write-Warning "Failed to create development dashboard: $_"
            $result.status = "failed"
            $result.message = "Failed to create dashboard: $_"
        }
        Write-Verbose "[New-Adodevdashboard] Error details: $($_.Exception.Message)"
        return $result
    }
}


function New-AdoSecurityDashboard {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project,

        [string]$Team,

        [switch]$Replace
    )
    
    Write-Host "[INFO] Attempting to create Security Metrics dashboard for '$Project' (Team: $Team)..." -ForegroundColor Cyan

    if (-not $Team) { $Team = "$Project Team" }

    $context = Get-AdoDashboardContext -Project $Project -Team $Team
    $teamId = $context.TeamId
    $projectId = $context.ProjectId

    $result = [pscustomobject]@{ status = "unknown"; message = $null }

    try {
        # Discover existing dashboards first
        $existing = $null
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId
        foreach ($ep in $endpoints) {
            try {
                $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
                $entries = @()
                if ($existingDashboards -eq $null) { $entries = @() }
                elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                else { $entries = @($existingDashboards) }
                $existing = $entries | Where-Object { $_.name -eq "Security Metrics" } | Select-Object -First 1
                if ($existing) { break }
            }
            catch {
                Write-LogLevelVerbose "[New-AdoSecurityDashboard] Dashboard GET failed for endpoint $ep - trying next. Error: $_"
            }
        }

        if ($existing) {
            if ($Replace) {
                Write-Host "[INFO] Replacing existing Security dashboard for '$Project' (Team: $Team)" -ForegroundColor Yellow
                $removed = Remove-AdoDashboard -Project $Project -Team $Team -ProjectId $projectId -TeamId $teamId -DashboardId $existing.id -DashboardUrl $existing.url
                if (-not $removed) {
                    Write-Warning "[SecurityDashboard] Failed to remove existing dashboard; attempting to recreate anyway."
                }
            }
            else {
                Write-Host "[INFO] Security Metrics dashboard already exists for '$Project' (Team: $Team)" -ForegroundColor DarkYellow
                $result.status = "skipped"
                $result.message = "Dashboard already exists."
                return $existing
            }
        }

        $dashboardConfig = @{
            name = Truncate-DashboardName "Security Metrics"
            description = "Security vulnerability tracking, compliance status, and threat intelligence"
            dashboardScope = if ($teamId) { "project_Team" } else { "project" }
            groupId = if ($teamId) { $teamId } else { $null }
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
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoDashboardRest -Method POST -Endpoint $ep -Body $dashboardConfig
                break
            }
            catch {
                $postErr = $_.Exception.Message
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-Verbose "[New-AdoSecurityDashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
                        $entries = @()
                        if ($existingDashboards -eq $null) { $entries = @() }
                        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                        else { $entries = @($existingDashboards) }

                        $found = $entries | Where-Object { $_.name -eq $dashboardConfig.name } | Select-Object -First 1
                        if ($found) {
                            Write-Host "[INFO] Security Metrics dashboard already exists for '$Project' (Team: $Team)" -ForegroundColor DarkYellow
                            $dashboard = $found
                            $result.status = "skipped"
                            $result.message = "Dashboard already exists."
                            return $result
                        }
                    }
                    catch {
                        Write-Verbose "[New-AdoSecurityDashboard] Failed to locate existing dashboard after duplicate error: $_"
                    }
                }

                Write-Verbose "[New-AdoSecurityDashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }

        if (-not $dashboard) {
            $result.status = "failed"
            $result.message = "Failed to create Security Metrics dashboard for team '$Team'."
            throw $result.message
        }

        Write-Host "  ✅ Security Metrics dashboard created for '$Project' (Team: $Team)" -ForegroundColor Gray
        Write-Host "[SUCCESS] Security dashboard created for '$Project' (Team: $Team)" -ForegroundColor Green
        $result.status = "created"
        $result.message = "Dashboard created successfully."
        return $result
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found|500|Internal Server Error") {
            Write-Host "ℹ️  [INFO] Security Dashboard API not available (common on on-premise servers or API issues)" -ForegroundColor Cyan
            $result.status = "failed"
            $result.message = "Dashboard API not available."
        }
        else {
            Write-Warning "Failed to create security dashboard: $_"
            $result.status = "failed"
            $result.message = "Failed to create dashboard: $_"
        }
        Write-Verbose "[New-AdoSecurityDashboard] Error details: $($_.Exception.Message)"
        return $result
    }
}


function Test-Adomanagementdashboard {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project,

        [string]$Team,

        [switch]$Replace
    )
    
    Write-Host "[INFO] Attempting to create Program Management dashboard for '$Project' (Team: $Team)..." -ForegroundColor Cyan

    if (-not $Team) { $Team = "$Project Team" }

    $context = Get-AdoDashboardContext -Project $Project -Team $Team
    $teamId = $context.TeamId
    $projectId = $context.ProjectId

    $result = [pscustomobject]@{ status = "unknown"; message = $null }

    try {
        $dashboardConfig = @{
            name = Truncate-DashboardName "Program Management"
            description = "Executive overview with program health, sprint progress, risks, and KPIs"
            dashboardScope = if ($teamId) { "project_Team" } else { "project" }
            groupId = if ($teamId) { $teamId } else { $null }
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
        $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team $Team -TeamId $teamId -ProjectId $projectId
        foreach ($ep in $endpoints) {
            try {
                $dashboard = Invoke-AdoDashboardRest -Method POST -Endpoint $ep -Body $dashboardConfig
                break
            }
            catch {
                $postErr = $_.Exception.Message
                if ($postErr -and ($postErr -match 'DuplicateDashboardNameException' -or $postErr -match 'DuplicateDashboardName')) {
                    Write-Verbose "[Test-Adomanagementdashboard] Duplicate dashboard name detected when posting to $ep - attempting to find existing dashboard"
                    try {
                        $existingDashboards = Invoke-AdoDashboardRest -Method GET -Endpoint $ep
                        $entries = @()
                        if ($existingDashboards -eq $null) { $entries = @() }
                        elseif ($existingDashboards.PSObject.Properties['dashboardEntries']) { $entries = $existingDashboards.dashboardEntries }
                        elseif ($existingDashboards.PSObject.Properties['value']) { $entries = $existingDashboards.value }
                        elseif ($existingDashboards -is [array]) { $entries = $existingDashboards }
                        else { $entries = @($existingDashboards) }

                        $found = $entries | Where-Object { $_.name -eq $dashboardConfig.name } | Select-Object -First 1
                        if ($found) {
                            if ($Replace) {
                                Write-Host "[INFO] Replacing existing Program Management dashboard for '$Project' (Team: $Team)" -ForegroundColor Yellow
                                $removed = Remove-AdoDashboard -Project $Project -Team $Team -ProjectId $projectId -TeamId $teamId -DashboardId $found.id -DashboardUrl $found.url
                                if (-not $removed) {
                                    Write-Warning "[ManagementDashboard] Failed to remove existing dashboard; attempting to recreate anyway."
                                }
                            }
                            else {
                                Write-Host "[INFO] Program Management dashboard already exists for '$Project' (Team: $Team)" -ForegroundColor DarkYellow
                                $dashboard = $found
                                $result.status = "skipped"
                                $result.message = "Dashboard already exists."
                                return $result
                            }
                        }
                    }
                    catch {
                        Write-Verbose "[Test-Adomanagementdashboard] Failed to locate existing dashboard after duplicate error: $_"
                    }
                }

                Write-Verbose "[Test-Adomanagementdashboard] Dashboard POST failed for endpoint $ep - trying next. Error: $_"
            }
        }

        if (-not $dashboard) {
            $result.status = "failed"
            $result.message = "Failed to create Program Management dashboard for team '$Team'."
            throw $result.message
        }

        Write-Host "  ✅ Program Management dashboard created for '$Project' (Team: $Team)" -ForegroundColor Gray
        Write-Host "[SUCCESS] Management dashboard created for '$Project' (Team: $Team)" -ForegroundColor Green
        $result.status = "created"
        $result.message = "Dashboard created successfully."
        return $result
    }
    catch {
        # Dashboard API is often not available on on-premise Azure DevOps Server
        if ($_ -match "404|Not Found|500|Internal Server Error") {
            Write-Host "ℹ️  [INFO] Management Dashboard API not available (common on on-premise servers or API issues)" -ForegroundColor Cyan
            $result.status = "failed"
            $result.message = "Dashboard API not available."
        }
        else {
            Write-Warning "Failed to create management dashboard: $_"
            $result.status = "failed"
            $result.message = "Failed to create dashboard: $_"
        }
        Write-Verbose "[Test-Adomanagementdashboard] Error details: $($_.Exception.Message)"
        return $result
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Set-AdoTeamSettings',
    'Search-Adodashboard',
    'Test-Adoqadashboard',
    'New-Adodevdashboard',
    'New-AdoSecurityDashboard',
    'Test-Adomanagementdashboard',
    'Get-AdoDashboardContext'
)

Export-ModuleMember -Function 'Resolve-AdoDashboardEndpoints'

