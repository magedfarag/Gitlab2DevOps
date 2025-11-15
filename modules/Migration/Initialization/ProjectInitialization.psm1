<#
.SYNOPSIS
    Azure DevOps project initialization and setup.

.DESCRIPTION
    This module handles the complete initialization of Azure DevOps projects,
    including project creation, work item setup, wikis, repositories, and
    branch policies with checkpoint/resume support.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, AzureDevOps, Migration.Core modules
    Version: 2.1.0
#>

# Import Core.Rest FIRST so all functions are available for parameter validation and runtime usage
$migrationRoot = Split-Path $PSScriptRoot -Parent
$coreRestPath = Join-Path $migrationRoot "core\Core.Rest.psm1"
if (-not (Get-Module -Name 'Core.Rest') -and (Test-Path $coreRestPath)) {
    Import-Module -WarningAction SilentlyContinue $coreRestPath -Force -Global -ErrorAction Stop
}
#Requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module -WarningAction SilentlyContinue (Join-Path $migrationRoot "Core\MigrationCore.psm1") -Force -Global

# Progress tracking defaults (avoids StrictMode complaints before initialization)
$script:totalSteps = 0
$script:currentStep = 0
$script:progressActivity = ""
$script:proj = $null
$script:projId = $null
$script:repo = $null

<#
.SYNOPSIS
    Initializes an Azure DevOps project with complete setup.

.DESCRIPTION
    Creates project, sets up RBAC groups, areas, wiki, work item templates,
    repository, and branch policies. Complete project scaffolding with checkpoint/resume support.
    Supports -WhatIf for preview mode.

.PARAMETER DestProject
    Azure DevOps project name.

.PARAMETER RepoName
    Repository name.

.PARAMETER BuildDefinitionId
    Optional build definition ID.

.PARAMETER SonarStatusContext
    Optional SonarQube context.

.PARAMETER ConfigFile
    Path to custom project-settings.json file. If not specified, uses default configuration.

.PARAMETER Areas
    Custom area names to create. Overrides configuration file. Example: @('Frontend', 'Backend', 'Mobile').

.PARAMETER SprintCount
    Number of sprints to create. Defaults to 6. Overrides configuration file.

.PARAMETER SprintDurationDays
    Sprint duration in days. Defaults to 14. Overrides configuration file.

.PARAMETER TeamName
    Custom team name. Defaults to '$DestProject Team'. Overrides default naming convention.

.PARAMETER TemplateDirectory
    Custom path to wiki template directory. Defaults to 'modules\templates'. 
    Allows organizations to use custom templates. Falls back to embedded templates if path invalid.

.PARAMETER Resume
    Resume from last checkpoint after previous failure. Skips completed steps.

.PARAMETER Force
    Force re-execution of all steps, ignoring checkpoints. Use with caution.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. No changes are made.

.PARAMETER Confirm
    Prompts for confirmation before executing each major step.

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -BuildDefinitionId 10

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -ConfigFile "my-settings.json"

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -Areas @('API', 'UI', 'Database') -SprintCount 8 -SprintDurationDays 10

.EXAMPLE
    # Resume after failure
    Initialize-AdoProject "MyProject" "my-repo" -Resume

.EXAMPLE
    # Preview mode - see what would be created
    Initialize-AdoProject "MyProject" "my-repo" -WhatIf
#>
function Initialize-AdoProject {
    [CmdletBinding(DefaultParameterSetName = 'Standard', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [Parameter(Mandatory, ParameterSetName = 'Standard')]
        [Parameter(Mandatory, ParameterSetName = 'Profile')]
        [Parameter(Mandatory, ParameterSetName = 'Selective')]
        [string]$RepoName,
        
        [Parameter(ParameterSetName = 'BulkInit')]
        [switch]$BulkInit,
        
        [int]$BuildDefinitionId = 0,
        
        [string]$SonarStatusContext = "",

        [string]$ConfigFile,

        [string[]]$Areas,

        [int]$SprintCount = 0,

        [int]$SprintDurationDays = 0,

        [string]$TeamName,

        [string]$TemplateDirectory,
        
        [Parameter(ParameterSetName = 'Selective')]
        [ValidateSet('areas', 'iterations', 'wiki', 'wikiPages', 'templates', 'queries', 
                     'teamSettings', 'dashboard', 'qaInfrastructure', 'repository', 
                     'branchPolicies', 'repositoryTemplates')]
        [string[]]$Only,
        
        [Parameter(ParameterSetName = 'Profile')]
        [ValidateSet('Minimal', 'Standard', 'Complete')]
        [string]$Profile = 'Standard',

        [ValidateScript({
            if ($_ -and -not (Test-Path $_)) {
                throw "Excel file not found: $_"
            }
            if ($_ -and $_ -notmatch '\.(xlsx|xls)$') {
                throw "File must be Excel format (.xlsx or .xls): $_"
            }
            $true
        })]
        [string]$ExcelRequirementsPath,

        [string]$ExcelWorksheetName = "Requirements",

        [switch]$Resume,

        [switch]$Force
    )
    
    # Ensure Core.Rest is imported in the current session for validation
    $migrationRoot = Split-Path $PSScriptRoot -Parent
    $coreRestPath = Join-Path $migrationRoot "core\Core.Rest.psm1"
    if (-not (Get-Module -Name 'Core.Rest') -and (Test-Path $coreRestPath)) {
        Import-Module -WarningAction SilentlyContinue $coreRestPath -Force -Global -ErrorAction Stop
    }
    # Validate repository name (moved from parameter block to function body for module import timing)
    if ($RepoName -and -not (Test-AdoRepositoryName $RepoName -ThrowOnError:$false)) {
        throw "Invalid repository name: $RepoName"
    }
    # Initialize logging for project initialization
    $migrationsDir = Join-Path $PSScriptRoot "..\..\..\migrations"
    $projectDir = Join-Path $migrationsDir $DestProject
    $logsDir = Join-Path $projectDir "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $logsDir "initialization-$timestamp.log"
    
    # Start transcript logging
    try {
        Start-Transcript -Path $logFile -Append -ErrorAction Stop
        Write-Host "[INFO] Logging to: $logFile" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Could not start transcript logging: $_"
    }
    
    Write-Host "[INFO] Initializing Azure DevOps project: $DestProject" -ForegroundColor Cyan
    # Small diagnostic helper for tracing execution inside this function. Use -Verbose when running to see these messages.
    function Log-Diag {
        param([string]$Message)
        # Respect Set-StrictMode: use Get-Variable to check existence
        $gv = Get-Variable -Scope Script -Name __init_log_counter -ErrorAction SilentlyContinue
        if ($null -eq $gv) {
            $count = 0
        }
        else {
            $count = [int]$gv.Value
        }
        $count = $count + 1
        Set-Variable -Scope Script -Name __init_log_counter -Value $count -Force
        Write-Verbose "[InitDiag:$count] $Message"
    }

    Log-Diag "Entered Initialize-AdoProject - DestProject=$DestProject RepoName=$RepoName BulkInit=$BulkInit Profile=$Profile Resume=$($Resume.IsPresent) Force=$($Force.IsPresent)"
    
    # Determine which components to initialize based on Profile or Only parameter
    $componentsToInitialize = @{
        areas = $false  # Disabled for sequential execution
        iterations = $true
        wiki = $true
        wikiPages = $true
        templates = $true
        queries = $true
        teamSettings = $true
        dashboard = $true
        qaInfrastructure = $true
        repository = $true
        branchPolicies = $true
        repositoryTemplates = $true
    }
    
    # Apply profile settings
    if ($PSCmdlet.ParameterSetName -eq 'Profile') {
        switch ($Profile) {
            'Minimal' {
                Write-Host "[INFO] Using Minimal profile: Project + Repository only" -ForegroundColor Cyan
                $componentsToInitialize.areas = $false
                $componentsToInitialize.iterations = $false
                $componentsToInitialize.wiki = $false
                $componentsToInitialize.wikiPages = $false
                $componentsToInitialize.templates = $false
                $componentsToInitialize.queries = $false
                $componentsToInitialize.teamSettings = $false
                $componentsToInitialize.dashboard = $false
                $componentsToInitialize.qaInfrastructure = $false
                $componentsToInitialize.repositoryTemplates = $false
            }
            'Complete' {
                Write-Host "[INFO] Using Complete profile: All components + Team Packs" -ForegroundColor Cyan
                # All components enabled (default), will prompt for team packs at end
            }
            'Standard' {
                Write-Host "[INFO] Using Standard profile: Default configuration" -ForegroundColor Cyan
                # All components enabled except team packs prompt
            }
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'BulkInit') {
        Write-Host "[INFO] Bulk initialization: Project infrastructure only" -ForegroundColor Cyan
        # Disable repository-specific components for bulk init
        $componentsToInitialize.repository = $false
        $componentsToInitialize.branchPolicies = $false
        $componentsToInitialize.repositoryTemplates = $false
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Selective' -and $Only) {
        Write-Host "[INFO] Selective initialization: $(($Only -join ', '))" -ForegroundColor Cyan
        # Disable all components first
        foreach ($key in $componentsToInitialize.Keys) {
            $componentsToInitialize[$key] = $false
        }
        # Enable only specified components
        foreach ($component in $Only) {
            $componentsToInitialize[$component] = $true
        }
        # Repository is always enabled unless bulk init
        if (-not $BulkInit.IsPresent) {
            $componentsToInitialize.repository = $true
        }
    }
    
    # Load configuration early for preview mode
    Write-Verbose "[Initialize-AdoProject] Loading project configuration..."
    try {
        $config = if ($ConfigFile) {
            Get-ProjectSettings -ConfigFile $ConfigFile
        } else {
            Get-ProjectSettings  # Uses default from ConfigLoader
        }
        Write-Verbose "[Initialize-AdoProject] Configuration loaded successfully"
    }
    catch {
        Write-Warning "Failed to load configuration: $_. Using embedded defaults."
        # Fallback to hardcoded defaults if ConfigLoader fails
        $config = @{
            areas = @(
                @{ name = 'Frontend'; description = 'Frontend development' }
                @{ name = 'Backend'; description = 'Backend development' }
                @{ name = 'Infrastructure'; description = 'Infrastructure and DevOps' }
                @{ name = 'Documentation'; description = 'Documentation and guides' }
            )
            iterations = @{
                sprintCount = 6
                sprintDurationDays = 14
                sprintPrefix = 'Sprint'
            }
            processTemplate = 'Agile'
            team = @{
                nameSuffix = ' Team'
            }
        }
    }

    # Apply parameter overrides to configuration
    if ($Areas) {
        Write-Verbose "[Initialize-AdoProject] Overriding areas from parameter: $($Areas -join ', ')"
        $config.areas = $Areas | ForEach-Object { @{ name = $_; description = "Area: $_" } }
    }
    if ($SprintCount -gt 0) {
        Write-Verbose "[Initialize-AdoProject] Overriding sprint count from parameter: $SprintCount"
        $config.iterations.sprintCount = $SprintCount
    }
    if ($SprintDurationDays -gt 0) {
        Write-Verbose "[Initialize-AdoProject] Overriding sprint duration from parameter: $SprintDurationDays days"
        $config.iterations.sprintDurationDays = $SprintDurationDays
    }

    # Determine team name (parameter > config > default pattern)
    $configTeamNameSuffix = $null
    if ($config.team) {
        if ($config.team -is [System.Collections.IDictionary]) {
            if ($config.team.Contains('nameSuffix')) {
                $configTeamNameSuffix = $config.team['nameSuffix']
            }
        }
        elseif ($config.team.PSObject.Properties.Name -contains 'nameSuffix') {
            $configTeamNameSuffix = $config.team.nameSuffix
        }
    }

    $effectiveTeamName = if ($TeamName) {
        $TeamName
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$configTeamNameSuffix)) {
        "$DestProject$configTeamNameSuffix"
    } else {
        "$DestProject Team"
    }
    Write-Verbose "[Initialize-AdoProject] Using team name: $effectiveTeamName"
    
    # Display preview summary in WhatIf mode
    if ($WhatIfPreference) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " INITIALIZATION PREVIEW" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Project Configuration:" -ForegroundColor Yellow
        Write-Host "  Project Name: $DestProject" -ForegroundColor White
        if ($RepoName) {
            Write-Host "  Repository: $RepoName" -ForegroundColor White
        } elseif ($BulkInit.IsPresent) {
            Write-Host "  Mode: Bulk initialization (repositories added during migration)" -ForegroundColor Yellow
        }
        Write-Host "  Team Name: $effectiveTeamName" -ForegroundColor White
        Write-Host "  Process Template: $($config.processTemplate)" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Would create:" -ForegroundColor Yellow
        Write-Host "  ✓ 1 Azure DevOps project" -ForegroundColor White
        Write-Host "  ✓ 6 sprint iterations ($($config.iterations.sprintDurationDays) days each)" -ForegroundColor White
        Write-Host "  ✓ 1 project wiki with home page" -ForegroundColor White
        Write-Host "  ✓ 7 work item templates (User Story, Task, Bug, Epic, Feature, Test Case, Issue)" -ForegroundColor White
        Write-Host "  ✓ 8 shared queries (My Work, Team Work, Bugs, etc.)" -ForegroundColor White
        Write-Host "  ✓ 1 team dashboard with widgets" -ForegroundColor White
        Write-Host "  ✓ 2 additional wiki pages (Common Tags, Best Practices)" -ForegroundColor White
        Write-Host "  ✓ QA infrastructure (Test Plan, QA Queries, QA Dashboard, Test Configurations, QA Guidelines)" -ForegroundColor White
        
        if ($componentsToInitialize.repository -and $RepoName) {
            Write-Host "  ✓ 1 Git repository: $RepoName" -ForegroundColor White
        } elseif ($BulkInit.IsPresent) {
            Write-Host "  → Git repositories will be added during bulk migration (Option 4)" -ForegroundColor Yellow
        }
        
        if ($BuildDefinitionId -gt 0) {
            Write-Host "  ✓ Branch policies with build validation (Build ID: $BuildDefinitionId)" -ForegroundColor White
        } else {
            Write-Host "  ✓ Branch policies (minimum 2 reviewers)" -ForegroundColor White
        }
        
        if ($SonarStatusContext) {
            Write-Host "  ✓ SonarQube status check: $SonarStatusContext" -ForegroundColor White
        }
        
        Write-Host "  ✓ Repository templates (README.md, Pull Request template)" -ForegroundColor White
        Write-Host ""
        Write-Host "Total estimated time: 15-30 seconds (sequential execution)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To execute, run without -WhatIf:" -ForegroundColor Cyan
        Write-Host "  Initialize-AdoProject '$DestProject' '$RepoName'" -ForegroundColor White
        Write-Host ""
        return
    }
    
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray
    
    # Track execution timing for performance metrics
    $executionStartTime = Get-Date
    $stepTiming = @{}

    # Track wiki state for downstream steps
    $wiki = $null
    
    # Define total steps for progress tracking
    $script:totalSteps = 12  # Reduced from 13 since areas are disabled
    $script:currentStep = 0
    $script:progressActivity = "Initializing Azure DevOps Project: $DestProject"
    
    # Initialize checkpoint system
    $checkpointFile = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "migrations") "$DestProject\.init-checkpoint.json"
    $checkpointDir = Split-Path $checkpointFile -Parent
    
    # Load existing checkpoint if resuming
    $checkpoint = @{
        project = $false
        areas = $false
        wiki = $false
        templates = $false
        iterations = $false
        queries = $false
        teamSettings = $false
        dashboard = $false
        wikiPages = $false
        qaInfrastructure = $false
        repository = $false
        branchPolicies = $false
        repositoryTemplates = $false
        completed = $false
        lastUpdate = $null
        errors = @()
    }
    
    if ($Resume.IsPresent -and (Test-Path $checkpointFile)) {
        try {
            $savedCheckpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json
            Write-Host "[INFO] 📋 Resuming from previous checkpoint..." -ForegroundColor Cyan
            
            # Merge saved checkpoint
            foreach ($key in $checkpoint.Keys) {
                if ($null -ne $savedCheckpoint.$key) {
                    $checkpoint[$key] = $savedCheckpoint.$key
                }
            }
            
            # Display resume summary
            $completedSteps = ($checkpoint.GetEnumerator() | Where-Object { $_.Value -eq $true -and $_.Key -ne 'completed' }).Count
            Write-Host "[INFO] ✓ $completedSteps steps already completed, continuing from there..." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to load checkpoint: $_. Starting from beginning."
            $Resume = $false
        }
    }
    elseif ($Resume.IsPresent) {
        Write-Warning "No checkpoint found for project '$DestProject'. Starting from beginning."
        $Resume = $false
    }
    
    if ($Force.IsPresent) {
        Write-Host "[INFO] 🔄 Force mode enabled - re-executing all steps" -ForegroundColor Yellow
        # Reset checkpoint
        foreach ($key in $checkpoint.Keys) {
            if ($key -notin @('lastUpdate', 'errors', 'completed')) {
                $checkpoint[$key] = $false
            }
        }
    }
    
    # Helper function to save checkpoint
    function Save-InitCheckpoint {
        param($CheckpointData)
        try {
            if (-not (Test-Path $checkpointDir)) {
                New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
            }
            $CheckpointData.lastUpdate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $CheckpointData | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $checkpointFile -Force
            Write-Verbose "[Checkpoint] State saved: $checkpointFile"
        }
        catch {
            Write-Warning "Failed to save checkpoint: $_"
        }
    }
    
    # Helper function to execute step with checkpoint tracking
    function Invoke-CheckpointedStep {
        param(
            [string]$StepName,
            [scriptblock]$Action,
            [string]$SuccessMessage,
            [string]$SkipMessage = "already completed, skipping",
            [string]$ProgressStatus = $null
        )
        
        # Update progress bar (robust: avoid division-by-zero and clamp percent)
        if ($ProgressStatus) {
            $script:currentStep++
            # Defensive: guard against uninitialized or zero totalSteps
            $percentComplete = 0
            if ($script:totalSteps -and ($script:totalSteps -gt 0)) {
                try {
                    $percentComplete = [int][math]::Round((($script:currentStep / $script:totalSteps) * 100))
                } catch {
                    $percentComplete = 0
                }
            }
            # Clamp to 0..100
            try { $percentComplete = [int][math]::Min(100, [math]::Max(0, $percentComplete)) } catch { $percentComplete = [int]$percentComplete }

            Write-Progress -Activity $script:progressActivity -Status $ProgressStatus -PercentComplete $percentComplete
        }
        
        if ($checkpoint[$StepName] -and -not $Force.IsPresent) {
            Write-Host "[SKIP] $StepName $SkipMessage" -ForegroundColor DarkGray
            return $true
        }
        
        # Start timing this step
        $stepStart = Get-Date
        $stepDuration = [TimeSpan]::Zero
        
        try {
            Write-Verbose "[Initialize-AdoProject] Executing step: $StepName"
            & $Action
            
            # Record step duration
            $stepDuration = (Get-Date) - $stepStart
            $stepTiming[$StepName] = $stepDuration.TotalSeconds
            
            $checkpoint[$StepName] = $true
            Save-InitCheckpoint $checkpoint
            if ($SuccessMessage) {
                $durationSeconds = $stepDuration.TotalSeconds
                Write-Host "[SUCCESS] $SuccessMessage ($($durationSeconds)s)" -ForegroundColor Green
            }
            return $true
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Host "[ERROR] Step '$StepName' failed: $errorMsg" -ForegroundColor Red
            $checkpoint.errors += @{
                step = $StepName
                error = $errorMsg
                timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            Save-InitCheckpoint $checkpoint
            
            Write-Progress -Activity $script:progressActivity -Completed
            
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Red
            Write-Host " INITIALIZATION FAILED" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "Failed at: $StepName" -ForegroundColor Yellow
            Write-Host "Error: $errorMsg" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Recovery options:" -ForegroundColor Cyan
            Write-Host "  1. Fix the issue and resume: Initialize-AdoProject '$DestProject' '$RepoName' -Resume" -ForegroundColor White
            Write-Host "  2. View checkpoint status: Get-Content '$checkpointFile'" -ForegroundColor White
            Write-Host "  3. Start fresh: Initialize-AdoProject '$DestProject' '$RepoName' -Force" -ForegroundColor White
            Write-Host ""
            
            throw
        }
    }
    
    # Configuration already loaded earlier for preview mode - skip duplicate loading
    # (Configuration is loaded at the beginning of the function to support -WhatIf preview)
    
    # Create/ensure project with checkpoint
    $script:proj = $null
    $script:projId = $null
    Invoke-CheckpointedStep -StepName 'project' -SuccessMessage "Project '$DestProject' ready" `
        -ProgressStatus "Creating Azure DevOps project (1/$($script:totalSteps))" -Action {
        Log-Diag "[project step] Starting project resolution for '$DestProject'"
        Log-Diag "[project step] Calling Measure-Adoproject $DestProject"
        $script:proj = Measure-Adoproject $DestProject

        Log-Diag "[project step] Measure-Adoproject returned: $([string]::IsNullOrWhiteSpace($script:proj) ? '<null-or-empty>' : ($script:proj | ConvertTo-Json -Depth 2 -ErrorAction SilentlyContinue))"

        # Additional diagnostics: type and basic info
        try {
            $projType = if ($script:proj -ne $null) { $script:proj.GetType().FullName } else { '<null>' }
        } catch { $projType = "<error getting type: $($_.Exception.Message)>" }
        Log-Diag "[project step] script:proj type: $projType"

        if (-not $script:proj) {
            throw "Measure-Adoproject did not return project data for '$DestProject'."
        }

        if ($script:proj -is [array]) {
            Log-Diag "[project step] Measure-Adoproject returned an array (count=$($script:proj.Length)), selecting first element"
            $script:proj = $script:proj | Select-Object -First 1
        }

        # Safely inspect properties - protect against non-PSObject/strings that may throw
        $hasIdProperty = $false
        try {
            $propNames = $null
            try { $propNames = $script:proj.PSObject.Properties.Name } catch { $propNames = @() }
            Log-Diag "[project step] script:proj property names: $([string]::Join(',', $propNames))"
            $hasIdProperty = $propNames -contains 'id'
        }
        catch {
            Log-Diag "[project step] Error inspecting script:proj properties: $($_.Exception.Message)"
            $hasIdProperty = $false
        }

        if (-not $hasIdProperty -or [string]::IsNullOrWhiteSpace([string]$script:proj.id)) {
            Log-Diag "[project step] Project object missing 'id'. Refreshing details from REST API..."
            try {
                Log-Diag "[project step] About to call Invoke-AdoRest GET for project details"
                $script:proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($DestProject))?includeCapabilities=true"
                Log-Diag "[project step] Invoke-AdoRest returned (type=$((if ($script:proj) { $script:proj.GetType().FullName } else { '<null>' }))): $([string]::IsNullOrWhiteSpace($script:proj) ? '<null-or-empty>' : ($script:proj | ConvertTo-Json -Depth 2 -ErrorAction SilentlyContinue))"
            }
            catch {
                Log-Diag "[project step] Invoke-AdoRest threw: $($_.Exception.Message)"
                Log-Diag "[project step] Invoke-AdoRest exception details: $($_.Exception | Format-List * | Out-String)"
                throw
            }
            try {
                $propNames = $script:proj.PSObject.Properties.Name
                Log-Diag "[project step] After refresh, script:proj property names: $([string]::Join(',', $propNames))"
                $hasIdProperty = $propNames -contains 'id'
            } catch {
                Log-Diag "[project step] After refresh, failed to enumerate properties: $($_.Exception.Message)"
                $hasIdProperty = $false
            }
        }

        if (-not $hasIdProperty -or -not $script:proj.id) {
            Log-Diag "[project step] Unable to resolve project id. script:proj dump: $([string]::IsNullOrWhiteSpace($script:proj) ? '<null-or-empty>' : ($script:proj | ConvertTo-Json -Depth 3 -ErrorAction SilentlyContinue))"
            throw "Unable to resolve Azure DevOps project ID for '$DestProject'."
        }

        $script:projId = $script:proj.id
        Log-Diag "[project step] Resolved project ID: $($script:projId)"
    }
    
    # Note: RBAC group configuration removed - Graph API is unreliable for on-premise servers
    # Users should configure security groups manually via Azure DevOps UI:
    # Project Settings > Permissions > Add security groups and members
    # For more info: https://learn.microsoft.com/azure/devops/organizations/security/add-users-team-project
    
    Write-Verbose "[Initialize-AdoProject] Skipping RBAC configuration (configure manually via UI if needed)"
    
    # Set up project wiki (executes sequentially)
    $wiki = $null
    if ($componentsToInitialize.wiki -and (-not $checkpoint['wiki'] -or $Force.IsPresent)) {
        Invoke-CheckpointedStep -StepName 'wiki' -SuccessMessage "Project wiki created" `
            -ProgressStatus "Creating project wiki (2/$($script:totalSteps))" -Action {
            # Get core rest config
            # No need to assign coreRestConfig; config is loaded internally
            $script:wiki = Measure-Adoprojectwiki $script:projId $DestProject
            
            # Load welcome wiki template
            $welcomeContent = $null
            $embeddedWelcome = @"
# Welcome to $DestProject

This project was migrated from GitLab using automated tooling.

## Project Structure

- **Frontend**: Web UI components
- **Backend**: API and services
- **Infrastructure**: DevOps and deployment
- **Documentation**: Technical docs and guides

## Getting Started

1. Clone the repository
2. Review branch policies
3. Check work item templates
"@

            # Try custom directory
            if ($TemplateDirectory) {
                $customPath = Join-Path $TemplateDirectory "welcome-wiki.md"
                if (Test-Path $customPath) {
                    try {
                        $template = Get-Content -Path $customPath -Raw -Encoding UTF8
                        $welcomeContent = $template -replace '{{PROJECT_NAME}}', $DestProject
                    } catch { }
                }
            }
            
            # Try default directory
            if (-not $welcomeContent) {
                $templatesDir = Join-Path $PSScriptRoot "..\..\..\templates"
                $defaultPath = Join-Path $templatesDir "welcome-wiki.md"
                if (Test-Path $defaultPath) {
                    try {
                        $template = Get-Content -Path $defaultPath -Raw -Encoding UTF8
                        $welcomeContent = $template -replace '{{PROJECT_NAME}}', $DestProject
                    } catch { }
                }
            }
            
            # Fall back to embedded
            if (-not $welcomeContent) {
                $welcomeContent = $embeddedWelcome
            }
            
            Set-AdoWikiPage $DestProject $script:wiki.id "/Home" $welcomeContent
        }
    }
    else {
        # Need to re-fetch wiki ID if skipped
        if (-not $script:wiki) {
                try {
                # Do a fast, non-retried check for project wiki to avoid noisy global retries
                $wikiList = Invoke-AdoRest GET "/$DestProject/_apis/wiki/wikis" -MaxAttempts 1 -DelaySeconds 0
                $script:wiki = $wikiList.value | Where-Object { $_.type -eq 'projectWiki' } | Select-Object -First 1
            }
            catch {
                Write-Warning "Could not retrieve wiki ID for skipped step: $_"
            }
        }
    }
    
    # Create work item templates using effective team name with checkpoint
    if ($componentsToInitialize.templates) {
        Invoke-CheckpointedStep -StepName 'templates' -SuccessMessage "Work item templates created" `
            -ProgressStatus "Creating work item templates (2/$script:totalSteps)" -Action {
            Initialize-AdoTeamTemplates $DestProject $effectiveTeamName
        }
    }
    else {
        Write-Host "[SKIP] Work item templates (disabled by selection)" -ForegroundColor DarkGray
    }
    
    # Import work items from Excel (auto-detect or explicit path)
    $excelFileToImport = $null
    
    Write-Verbose "[Initialize-AdoProject] Checking Excel requirements import..."
    
    if ($ExcelRequirementsPath) {
        # Explicit path provided via parameter
        $excelFileToImport = $ExcelRequirementsPath
        Write-Host "[INFO] Using Excel file from parameter: $excelFileToImport" -ForegroundColor Cyan
    }
    else {
        # Auto-detect requirements.xlsx in project directory
        $migrationsDir = Join-Path $PSScriptRoot "..\..\..\migrations"
        $projectExcelPath = Join-Path $migrationsDir "$DestProject\requirements.xlsx"
        
        Write-Verbose "[Initialize-AdoProject] Auto-detection path: $projectExcelPath"
        Write-Verbose "[Initialize-AdoProject] Checking if file exists..."
        
        if (Test-Path $projectExcelPath) {
            $excelFileToImport = $projectExcelPath
            Write-Host "[INFO] 🔍 Auto-detected Excel file in project directory: requirements.xlsx" -ForegroundColor Cyan
            Write-Host "[INFO] Full path: $projectExcelPath" -ForegroundColor Gray
        }
        else {
            Write-Verbose "[Initialize-AdoProject] Excel file not found at: $projectExcelPath"
        }
    }
    
    if ($excelFileToImport) {
        Write-Host ""
        Write-Host "[INFO] 📊 Importing work items from Excel..." -ForegroundColor Cyan
        Write-Host "[INFO] File: $excelFileToImport" -ForegroundColor Gray
        Write-Host "[INFO] Worksheet: $ExcelWorksheetName" -ForegroundColor Gray
        
        try {
            Write-Verbose "[Initialize-AdoProject] Calling Import-AdoWorkItemsFromExcel..."
            # Get CollectionUrl from core rest config to pass explicitly to avoid script variable issues
            # No need to assign coreRestConfig or collectionUrl
            
            $importResult = Import-AdoWorkItemsFromExcel -Project $DestProject `
                                                          -ExcelPath $excelFileToImport `
                                                          -WorksheetName $ExcelWorksheetName `
                                                          -TeamName $effectiveTeamName
            
            Write-Verbose "[Initialize-AdoProject] Import completed. Result: $($importResult | ConvertTo-Json -Compress)"
            
            if ($importResult.SuccessCount -gt 0) {
                Write-Host "[SUCCESS] ✅ Imported $($importResult.SuccessCount) work items from Excel" -ForegroundColor Green
                Write-Host "[INFO] Work items created in project: $DestProject" -ForegroundColor Gray
            }
            if ($importResult.ErrorCount -gt 0) {
                Write-Host "[WARN] ⚠️ $($importResult.ErrorCount) work items failed to import" -ForegroundColor Yellow
                if ($importResult.Errors) {
                    foreach ($err in $importResult.Errors) {
                        Write-Verbose "[Initialize-AdoProject] Excel import error: $err"
                    }
                }
            }
            
            if ($importResult.SuccessCount -eq 0 -and $importResult.ErrorCount -eq 0) {
                Write-Host "[WARN] No work items were imported from Excel" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "[ERROR] Excel import failed: $_" -ForegroundColor Red
            Write-Verbose "[Initialize-AdoProject] Excel import exception: $($_.Exception | Format-List * | Out-String)"
            Write-Host "[INFO] Continuing with project initialization..." -ForegroundColor Yellow
        }
        Write-Host ""
    }
    else {
        Write-Host "[INFO] No Excel requirements file found (checked: migrations\$DestProject\requirements.xlsx)" -ForegroundColor DarkGray
        Write-Host "[TIP] Place requirements.xlsx in migrations\$DestProject\ for automatic import" -ForegroundColor DarkGray
    }
    
    # Create sprint iterations from configuration with checkpoint
    if ($componentsToInitialize.iterations) {
        Invoke-CheckpointedStep -StepName 'iterations' -SuccessMessage "Sprint iterations configured ($($config.iterations.sprintCount) sprints)" `
            -ProgressStatus "Setting up sprint iterations (3/$script:totalSteps)" -Action {
            $sprintCount = $config.iterations.sprintCount
            $sprintDays = $config.iterations.sprintDurationDays
            Measure-Adoiterations $DestProject $effectiveTeamName -SprintCount $sprintCount -SprintDurationDays $sprintDays
        }
    }
    else {
        Write-Host "[SKIP] Sprint iterations (disabled by selection)" -ForegroundColor DarkGray
    }
    
    # Create shared work item queries with checkpoint
    if ($componentsToInitialize.queries) {
        Invoke-CheckpointedStep -StepName 'queries' -SuccessMessage "Shared queries created" `
            -ProgressStatus "Creating shared queries (4/$script:totalSteps)" -Action {
            New-AdoSharedQueries $DestProject $effectiveTeamName
        }
    }
    else {
        Write-Host "[SKIP] Shared queries (disabled by selection)" -ForegroundColor DarkGray
    }
    
    # Configure team settings with checkpoint
    if ($componentsToInitialize.teamSettings) {
        Invoke-CheckpointedStep -StepName 'teamSettings' -SuccessMessage "Team settings configured" `
            -ProgressStatus "Configuring team settings (5/$script:totalSteps)" -Action {
            Set-AdoTeamSettings $DestProject $effectiveTeamName
        }
    }
    else {
        Write-Host "[SKIP] Team settings (disabled by selection)" -ForegroundColor DarkGray
    }
    
    # Create team dashboard with checkpoint
    if ($componentsToInitialize.dashboard) {
        Invoke-CheckpointedStep -StepName 'dashboard' -SuccessMessage "Team dashboard created" `
            -ProgressStatus "Creating team dashboard (6/$script:totalSteps)" -Action {
            Search-Adodashboard $DestProject $effectiveTeamName
        }
    }
    else {
        Write-Host "[SKIP] Team dashboard (disabled by selection)" -ForegroundColor DarkGray
    }
    
    # Create wiki pages sequentially (tag guidelines and best practices)
    if ($componentsToInitialize.wikiPages) {
        if (-not $script:wiki) {
            Write-Host "[SKIP] Additional wiki pages (project wiki unavailable)" -ForegroundColor Yellow
        }
        else {
            Invoke-CheckpointedStep -StepName 'wikiPages' -SuccessMessage "Additional wiki pages created" `
                -ProgressStatus "Creating additional wiki pages (8/$script:totalSteps)" -Action {
                Write-Host "[INFO] Creating wiki pages sequentially..." -ForegroundColor Cyan
                
                # Get core rest config
                # No need to assign coreRestConfig
                
                # Create Common Tags wiki page
                try {
                    Measure-Adocommontags $DestProject $script:wiki.id
                    Write-Verbose "[Initialize-AdoProject] ✓ Common Tags wiki page created successfully"
                }
                catch {
                    Write-Warning "Common Tags wiki page failed: $($_.Exception.Message)"
                }
                
                # Create Best Practices wiki page
                try {
                    Measure-Adobestpracticeswiki $DestProject $script:wiki.id
                    Write-Verbose "[Initialize-AdoProject] ✓ Best Practices wiki page created successfully"
                }
                catch {
                    Write-Warning "Best Practices wiki page failed: $($_.Exception.Message)"
                }
            }
        }
    }
    
    # Configure QA infrastructure with granular error handling and checkpoint
    if ($componentsToInitialize.qaInfrastructure) {
        Invoke-CheckpointedStep -StepName 'qaInfrastructure' `
            -ProgressStatus "Setting up QA infrastructure (7/$script:totalSteps)" -Action {
            Write-Host "[INFO] Setting up QA infrastructure..." -ForegroundColor Cyan
            $qaResults = [ordered]@{
                testPlan = @{ success = $false; error = $null }
                queries = @{ success = $false; error = $null }
                dashboard = @{ success = $false; error = $null }
                configurations = @{ success = $false; error = $null }
                guidelines = @{ success = $false; error = $null }
            }
            
            # Test Plan
            try {
                $testPlan = New-AdoTestPlan $DestProject
                $qaResults.testPlan.success = $true
                Write-Verbose "[Initialize-AdoProject] ✓ Test plan created successfully"
            }
            catch {
                $qaResults.testPlan.error = $_.Exception.Message
                Write-Warning "  ✗ Test plan creation failed: $($_.Exception.Message)"
                if ($_.Exception.Message -match '401|403') {
                    Write-Warning "    → Ensure PAT has 'Test Plans: Read, write, & manage' scope"
                    Write-Warning "    → Generate token at: [ADO_COLLECTION_URL]/_usersSettings/tokens"
                }
            }
            
            # QA Queries
            try {
                New-AdoQAQueries $DestProject
                $qaResults.queries.success = $true
                Write-Verbose "[Initialize-AdoProject] ✓ QA queries created successfully"
            }
            catch {
                $qaResults.queries.error = $_.Exception.Message
                Write-Warning "  ✗ QA queries creation failed: $($_.Exception.Message)"
            }
            
            # QA Dashboard
            try {
                Test-Adoqadashboard $DestProject $effectiveTeamName
                $qaResults.dashboard.success = $true
                Write-Verbose "[Initialize-AdoProject] ✓ QA dashboard created successfully"
            }
            catch {
                $qaResults.dashboard.error = $_.Exception.Message
                Write-Warning "  ✗ QA dashboard creation failed: $($_.Exception.Message)"
            }
            
            # Test Configurations
            try {
                New-AdoTestConfigurations $DestProject
                $qaResults.configurations.success = $true
                Write-Verbose "[Initialize-AdoProject] ✓ Test configurations created successfully"
            }
            catch {
                $qaResults.configurations.error = $_.Exception.Message
                Write-Warning "  ✗ Test configurations creation failed: $($_.Exception.Message)"
                if ($_.Exception.Message -match '401|403') {
                    Write-Warning "    → Ensure PAT has 'Test Plans: Read, write, & manage' scope"
                }
            }
            
            # Project Wiki pages (create all sections once)
            if ($script:wiki) {
                try {
                    Initialize-AdoProjectWikis -Project $DestProject -WikiId $script:wiki.id | Out-Null
                    $qaResults.guidelines.success = $true
                    Write-Verbose "[Initialize-AdoProject] ✓ Project wiki pages initialized successfully"
                }
                catch {
                    $qaResults.guidelines.error = $_.Exception.Message
                    Write-Warning "  ✗ Project wiki initialization failed: $($_.Exception.Message)"
                }
            }
            else {
                $qaResults.guidelines.error = "Wiki unavailable"
                Write-Warning "  ⚠ Project wiki initialization skipped (project wiki not available)"
            }
            
            # Summary report
            $qaSuccessCount = ($qaResults.Values | Where-Object { $_.success }).Count
            $qaTotalCount = $qaResults.Count
            if ($qaSuccessCount -eq $qaTotalCount) {
                Write-Host "[SUCCESS] QA infrastructure: $qaSuccessCount/$qaTotalCount components configured successfully" -ForegroundColor Green
            }
            elseif ($qaSuccessCount -gt 0) {
                Write-Host "[PARTIAL] QA infrastructure: $qaSuccessCount/$qaTotalCount components configured (see warnings above)" -ForegroundColor Yellow
            }
            else {
                Write-Host "[FAILED] QA infrastructure: 0/$qaTotalCount components configured" -ForegroundColor Red
                Write-Warning "QA infrastructure setup failed completely. Check PAT permissions and retry."
            }
        }
    }
    else {
        Write-Host "[SKIP] QA infrastructure (disabled by selection)" -ForegroundColor DarkGray
    }
    
    # Repository creation and RBAC have been intentionally deferred to the migration phase
    # (Option 4: Start Planned Migration). Creating repositories during initialization
    # causes additional waits and may create noise; perform repository creation as the
    # final step of the planned migration workflow when code is pushed.
    $script:repo = $null
    Write-Host "[INFO] Repository creation and RBAC tasks are deferred to the migration step (Option 4)" -ForegroundColor Yellow
    if ($BulkInit.IsPresent) {
        Write-Host "[SKIP] Repository creation (bulk initialization - repositories will be created during migration)" -ForegroundColor DarkGray
    }

    if ($null -ne $script:repo) {
        # Apply branch policies with checkpoint (only if default branch exists)
        if ($componentsToInitialize.branchPolicies) {
            Invoke-CheckpointedStep -StepName 'branchPolicies' `
                -ProgressStatus "Applying branch policies (9/$script:totalSteps)" -Action {
                # Wait for default branch with retry logic (handles ADO initialization delays)
                Write-Verbose "[Initialize-AdoProject] Waiting for repository default branch to be established..."
                $maxRetries = 5  # REPO_INIT_MAX_RETRIES
                $retryDelays = @(2, 4, 8, 16, 32)  # REPO_INIT_RETRY_DELAYS
                $defaultRef = $null
                
                for ($i = 0; $i -lt $maxRetries; $i++) {
                    $delay = $retryDelays[$i]
                    Write-Verbose "[Initialize-AdoProject] Attempt $($i + 1)/$maxRetries - waiting ${delay}s..."
                    Start-Sleep -Seconds $delay
                    
                    $defaultRef = Get-AdoRepoDefaultBranch $using:DestProject $using:script:repo.id
                    if ($defaultRef) {
                        Write-Verbose "[Initialize-AdoProject] ✓ Default branch found: $defaultRef (after $($i + 1) attempts)"
                        break
                    }
                    
                    if ($i -lt ($maxRetries - 1)) {
                        Write-Verbose "[Initialize-AdoProject] Branch not ready yet, retrying..."
                    }
                }

                # Apply branch policies only if repository has a default branch
                if ($defaultRef) {
                    New-Adobranchpolicies `
                        -Project $using:DestProject `
                        -RepoId $using:script:repo.id `
                        -Ref $defaultRef `
                        -Min 2 `
                        -BuildId $using:BuildDefinitionId `
                        -StatusContext $using:SonarStatusContext
                    Write-Host "[SUCCESS] Branch policies applied to $defaultRef" -ForegroundColor Green
                }
                else {
                    Write-Host "[WARN] Default branch not available after $maxRetries retries (62s total wait)" -ForegroundColor Yellow
                    Write-Host "[INFO] Branch policies will be applied after first push" -ForegroundColor Yellow
                    Write-Host "[INFO] This is normal for empty repositories - no action needed" -ForegroundColor Gray
                    # Mark as completed even if skipped
                }
            }
        }
        else {
            Write-Host "[SKIP] Branch policies (disabled by selection)" -ForegroundColor DarkGray
        }
        
        # Add repository templates with checkpoint (only if repository was created)
        if ($componentsToInitialize.repositoryTemplates -and $script:repo) {
            Invoke-CheckpointedStep -StepName 'repositoryTemplates' `
                -ProgressStatus "Adding repository templates (10/$script:totalSteps)" -Action {
                $defaultRef = Get-AdoRepoDefaultBranch $using:DestProject $using:script:repo.id
                if ($defaultRef) {
                    New-AdoRepositoryTemplates $using:DestProject $using:script:repo.id $using:RepoName
                    Write-Host "[SUCCESS] Repository templates (README, PR template) added" -ForegroundColor Green
                }
                else {
                    Write-Host "[INFO] Repository templates will be added after first push" -ForegroundColor Yellow
                    # Mark as completed even if skipped (not a failure)
                }
            }
        }
        elseif ($componentsToInitialize.repositoryTemplates -and -not $script:repo) {
            Write-Host "[SKIP] Repository templates (no repository created)" -ForegroundColor DarkGray
        }
        else {
            Write-Host "[SKIP] Repository templates (disabled by selection)" -ForegroundColor DarkGray
        }
        
        # Repository-level security configuration reminder
        if ($componentsToInitialize.repository -and $script:repo) {
            Write-Host ""
            Write-Host "[INFO] Repository-level security should be configured manually via Azure DevOps UI:" -ForegroundColor Cyan
            Write-Host "  1. Navigate to: Project Settings > Repositories > $RepoName > Security" -ForegroundColor Gray
            Write-Host "  2. Configure permissions for teams (Readers, Contributors, Build Admins)" -ForegroundColor Gray
            Write-Host "  3. Set branch-level permissions if needed (protect main/develop branches)" -ForegroundColor Gray
            Write-Host "  4. Review security best practices in wiki: /Security/Security-Policies" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Reference: https://learn.microsoft.com/azure/devops/repos/git/set-git-repository-permissions" -ForegroundColor DarkGray
            Write-Host ""
        }
    }
    else {
        Write-Host "[WARN] Repository '$RepoName' was not created. Skipping branch policies, templates, and repo-level security." -ForegroundColor Yellow
    }
    
    # Mark initialization as completed
    $script:currentStep++
    Write-Progress -Activity $script:progressActivity -Status "Finalizing initialization (11/$($script:totalSteps))" `
        -PercentComplete ([math]::Round(($script:currentStep / $script:totalSteps) * 100))
    
    $checkpoint.completed = $true
    Save-InitCheckpoint $checkpoint
    
    # Complete progress bar
    Write-Progress -Activity $script:progressActivity -Completed
    
    # Clean up checkpoint file on successful completion
    try {
        if (Test-Path $checkpointFile) {
            Remove-Item $checkpointFile -Force
            Write-Verbose "[Initialize-AdoProject] Checkpoint file removed after successful completion"
        }
    }
    catch {
        Write-Verbose "[Initialize-AdoProject] Could not remove checkpoint file: $_"
    }
    
    # Create migration config in new v2.1.0 structure (skip for bulk init)
    if (-not $BulkInit.IsPresent -and $RepoName) {
        try {
            $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $RepoName
            
            # Create migration config
            $migrationConfig = [pscustomobject]@{
                ado_project      = $DestProject
                ado_repo_name    = $RepoName
                migration_type   = "SINGLE"
                created_date     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                last_updated     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                status           = "INITIALIZED"
            }
            
            $migrationConfig | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $paths.configFile
            Write-Verbose "[Initialize-AdoProject] Migration config created: $($paths.configFile)"
        }
        catch {
            Write-Verbose "[Initialize-AdoProject] Could not create migration config: $_"
            # Non-critical, continue
        }
    }
    elseif ($BulkInit.IsPresent) {
        Write-Verbose "[Initialize-AdoProject] Skipping migration config creation for bulk initialization"
    }
    
    # Complete Profile: Prompt for team initialization packs
    if ($Profile -eq 'Complete') {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " TEAM INITIALIZATION PACKS" -ForegroundColor Magenta
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Complete profile includes optional team-specific initialization packs:" -ForegroundColor White
        Write-Host ""
        Write-Host "Available packs:" -ForegroundColor Cyan
        Write-Host "  [B] Business Team Pack" -ForegroundColor Yellow
        Write-Host "      10 wiki templates + 4 work item types (Requirements, Change Requests)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [D] Dev Team Pack" -ForegroundColor Yellow
        Write-Host "      7 wiki templates + comprehensive workflows (CI/CD, Code Review)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [S] Security Team Pack" -ForegroundColor Yellow
        Write-Host "      7 wiki templates + security configurations (Threat Model, Audit)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [M] Management Team Pack" -ForegroundColor Yellow
        Write-Host "      8 wiki templates + executive dashboards (OKRs, Roadmap)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [A] All Packs" -ForegroundColor Green
        Write-Host "      Install all team packs (comprehensive setup)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  [N] None" -ForegroundColor DarkGray
        Write-Host "      Skip team packs (standard setup)" -ForegroundColor Gray
        Write-Host ""
        
        # If running non-interactively (automation), default to 'N' to skip team pack prompts
        if ($Host.UI -and $Host.UI.RawUI -and -not $Host.UI.RawUI.KeyAvailable) {
            # In some hosts RawUI may not expose KeyAvailable; fall back to checking if input is redirected
            $isInteractive = -not [Console]::IsInputRedirected
        }
        else {
            $isInteractive = -not [Console]::IsInputRedirected
        }

        if (-not $isInteractive) {
            Write-Verbose "Non-interactive host detected - skipping team pack prompt (default: None)"
            $teamPackChoice = 'N'
        }
        else {
            $teamPackChoice = Read-Host "Select team packs to install [B/D/S/M/A/N]"
        }
        
        switch ($teamPackChoice.ToUpper()) {
            'B' {
                Write-Host ""
                Write-Host "[INFO] Installing Business Team Pack..." -ForegroundColor Cyan
                Initialize-BusinessInit -DestProject $DestProject
            }
            'D' {
                Write-Host ""
                Write-Host "[INFO] Installing Dev Team Pack..." -ForegroundColor Cyan
                Initialize-DevInit -DestProject $DestProject
            }
            'S' {
                Write-Host ""
                Write-Host "[INFO] Installing Security Team Pack..." -ForegroundColor Cyan
                Initialize-SecurityInit -DestProject $DestProject
            }
            'M' {
                Write-Host ""
                Write-Host "[INFO] Installing Management Team Pack..." -ForegroundColor Cyan
                Initialize-ManagementInit -DestProject $DestProject
            }
            'A' {
                Write-Host ""
                Write-Host "[INFO] Installing all team packs..." -ForegroundColor Cyan
                Initialize-BusinessInit -DestProject $DestProject
                Initialize-DevInit -DestProject $DestProject
                Initialize-SecurityInit -DestProject $DestProject
                Initialize-ManagementInit -DestProject $DestProject
            }
            'N' {
                Write-Host ""
                Write-Host "[INFO] Skipping team packs (standard setup)" -ForegroundColor Gray
            }
            default {
                Write-Host ""
                Write-Host "[WARN] Invalid selection '$teamPackChoice' - skipping team packs" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " PROJECT INITIALIZATION COMPLETE! 🎉" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Project: $DestProject" -ForegroundColor White
    Write-Host ""
    
    # Team Structure
    Write-Host "👥 Team & Permissions:" -ForegroundColor Cyan
    Write-Host "   ⚠️  RBAC groups: Configure manually via Azure DevOps UI" -ForegroundColor Yellow
    Write-Host "       → Project Settings > Permissions > Add security groups" -ForegroundColor Gray
    
    # Work Item Configuration
    Write-Host ""
    Write-Host "📋 Work Item Configuration:" -ForegroundColor Cyan
    Write-Host "  ⚠️  Areas: Disabled for sequential execution" -ForegroundColor Yellow
    Write-Host "  ✅ Templates: 6 comprehensive templates (auto-default)" -ForegroundColor Green
    Write-Host "  ✅ Sprints: $($config.iterations.sprintCount) upcoming $($config.iterations.sprintDurationDays)-day iterations" -ForegroundColor Green
    Write-Host "  ✅ Queries: 5+ shared queries (My Work, Backlog, Bugs, etc.)" -ForegroundColor Green
    Write-Host "  ✅ Team Settings: Backlog levels, working days, bugs on backlog" -ForegroundColor Green
    Write-Host "  ✅ Dashboard: Team overview with burndown, velocity, charts" -ForegroundColor Green
    
    # Documentation & Guidelines
    Write-Host ""
    Write-Host "📚 Documentation:" -ForegroundColor Cyan
    if ($script:wiki) {
        Write-Host "   ✅ Wiki: Initialized with welcome page" -ForegroundColor Green
        Write-Host "   ✅ Tag Guidelines: Common tags documented" -ForegroundColor Green
        Write-Host "   ✅ Best Practices: Comprehensive team productivity guide" -ForegroundColor Green
        Write-Host "   ✅ QA Guidelines: Testing standards and QA processes" -ForegroundColor Green
    }
    else {
        Write-Host "   ⚠️  Wiki: Could not be created (check server configuration)" -ForegroundColor Yellow
    }
    
    # QA Infrastructure
    Write-Host ""
    Write-Host "🧪 QA Infrastructure:" -ForegroundColor Cyan
    Write-Host "   ✅ Test Plan: 4 suites (Regression, Smoke, Integration, UAT)" -ForegroundColor Green
    Write-Host "   ✅ Test Configurations: 13 configs (browsers, OS, environments)" -ForegroundColor Green
    Write-Host "   ✅ QA Queries: 8 queries (Test Status, Bugs, Coverage, etc.)" -ForegroundColor Green
    Write-Host "   ✅ QA Dashboard: Metrics dashboard with 8 widgets" -ForegroundColor Green
    
    # Repository Configuration
    Write-Host ""
    Write-Host "🔧 Repository Configuration:" -ForegroundColor Cyan
    if ($RepoName -and -not $BulkInit.IsPresent) {
        Write-Host "   ✅ Repository: $RepoName" -ForegroundColor Green
        if ($null -ne $script:repo) {
            $defaultRef = Get-AdoRepoDefaultBranch $DestProject $script:repo.id
            if ($defaultRef) {
                Write-Host "   ✅ Branch Policies: Applied to $defaultRef" -ForegroundColor Green
                Write-Host "   ✅ README.md: Starter template added" -ForegroundColor Green
                Write-Host "   ✅ PR Template: Pull request template added" -ForegroundColor Green
            }
            else {
                Write-Host "   ⏳ Branch Policies: Will apply after first push" -ForegroundColor Yellow
                Write-Host "   ⏳ Templates: Will add after first push" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "   ⚠️  Repository creation was skipped" -ForegroundColor Yellow
        }
    }
    elseif ($BulkInit.IsPresent) {
        Write-Host "   ✅ Bulk Mode: Repositories will be added during migration" -ForegroundColor Green
    }
    else {
        Write-Host "   ⚠️  Repository creation was skipped" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Display execution timing summary
    $totalExecutionTime = (Get-Date) - $executionStartTime
    Write-Host "⏱️  Execution Timing:" -ForegroundColor Cyan
    Write-Host ("   Total: {0:F1}s ({1}m {2}s)" -f $totalExecutionTime.TotalSeconds, [int]$totalExecutionTime.Minutes, $totalExecutionTime.Seconds) -ForegroundColor White
    
    if ($stepTiming.Count -gt 0) {
        Write-Host "   Step breakdown:" -ForegroundColor Gray
        $sortedSteps = $stepTiming.GetEnumerator() | Sort-Object Value -Descending
        foreach ($step in $sortedSteps) {
            $stepName = $step.Key
            $stepSeconds = $step.Value
            $percentage = ($stepSeconds / $totalExecutionTime.TotalSeconds) * 100
            Write-Host ("      • {0}: {1:F1}s ({2:F0}%)" -f $stepName, $stepSeconds, $percentage) -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor White
    Write-Host "  1. Use Option 4 (Start Migration) to push code from prepared projects" -ForegroundColor Gray
    if ($script:wiki) {
        Write-Host "  2. 📖 Read Best Practices: Wiki → Best-Practices (START HERE!)" -ForegroundColor Cyan
        Write-Host "  3. 🧪 Review QA Guidelines: Wiki → QA-Guidelines (for QA team)" -ForegroundColor Cyan
    }
    Write-Host "  4. View team dashboard: Dashboards → $effectiveTeamName - Overview" -ForegroundColor Gray
    Write-Host "  5. View QA dashboard: Dashboards → $effectiveTeamName - QA Metrics" -ForegroundColor Gray
    Write-Host "  6. Review test plan: Test Plans → $DestProject - Test Plan" -ForegroundColor Gray
    Write-Host "  7. Review shared queries in Queries → Shared Queries" -ForegroundColor Gray
    Write-Host "  8. Check QA queries in Queries → Shared Queries → QA" -ForegroundColor Gray
    Write-Host "  9. Check sprint schedule in Boards → Sprints" -ForegroundColor Gray
    if ($script:wiki) {
        Write-Host " 10. Review tag guidelines in Wiki → Tag-Guidelines" -ForegroundColor Gray
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Generate HTML report if migration config was created (skip for bulk init)
    if (-not $BulkInit.IsPresent -and $RepoName) {
        try {
            $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $RepoName -ErrorAction SilentlyContinue
            if ($paths -and (Test-Path $paths.configFile)) {
                $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $paths.configFile -Parent)
                if ($htmlReport) {
                    Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
                }
                
                # Update overview dashboard
                $overviewReport = New-MigrationsOverviewReport
                if ($overviewReport) {
                    Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
                }
            }
        }
        catch {
            Write-Verbose "Could not generate HTML reports: $_"
            # Non-critical, continue
        }
    }
    
    # Stop transcript logging
    try {
        Stop-Transcript -ErrorAction Stop
    }
    catch {
        # Transcript might not be running
    }

    # Write init metrics summary for project initialization (if metrics helper available)
    try {
        if (Get-Command -Name Write-InitSummaryReport -ErrorAction SilentlyContinue) {
            # Determine reports directory: prefer $paths.reportsDir if available, else use migrations/<project>/reports
            if ($paths -and $paths.reportsDir) {
                $reportsDir = $paths.reportsDir
            }
            else {
                $migrationsDir = Join-Path $PSScriptRoot "..\..\..\migrations"
                $projectDir = Join-Path $migrationsDir $DestProject
                $reportsDir = Join-Path $projectDir "reports"
            }

            Write-Verbose "[Init] Writing init summary report to $reportsDir"
            Write-InitSummaryReport -ReportsDir $reportsDir -FileName 'project-initialize-init-summary.json' | Out-Null
        }
        else {
            Write-Verbose "[Init] Write-InitSummaryReport not available in this session"
        }
    }
    catch {
        Write-Warning "[WARN] Failed to write initialization init summary: $_"
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-AdoProject'
)

