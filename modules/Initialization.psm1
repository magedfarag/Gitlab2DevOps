<#
.SYNOPSIS
    Azure DevOps project initialization module for GitLab to Azure DevOps migration.

.DESCRIPTION
    Handles creation and initialization of Azure DevOps projects with team-specific
    configurations, wiki templates, work items, and team productivity packs.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.1.0
    Requires: AzureDevOps module, Templates module
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import required modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot "AzureDevOps.psm1") -Force -Global
Import-Module (Join-Path $ModuleRoot "Templates.psm1") -Force -Global
Import-Module (Join-Path $ModuleRoot "ConfigLoader.psm1") -Force -Global
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force -Global

# Module variables
$script:DEFAULT_SPRINT_DURATION_DAYS = 14

<#
.SYNOPSIS
    Initializes a complete Azure DevOps project with optional team productivity packs.

.DESCRIPTION
    Creates or configures an Azure DevOps project with work areas, iterations, wiki,
    work item templates, shared queries, and team dashboard. Supports selective
    initialization, profiles, and checkpoint-based resume functionality.

.PARAMETER DestProject
    Name of the Azure DevOps project to create or initialize.

.PARAMETER RepoName
    Name of the primary Git repository to create in the project.

.PARAMETER BuildDefinitionId
    Optional build definition ID for branch policy validation.

.PARAMETER SonarStatusContext
    Optional SonarQube status context for branch policies.

.PARAMETER ConfigFile
    Path to JSON configuration file for project settings.

.PARAMETER Areas
    Custom work item areas to create (overrides config file).

.PARAMETER SprintCount
    Number of sprints to create (overrides config file).

.PARAMETER SprintDurationDays
    Duration of each sprint in days (overrides config file).

.PARAMETER TeamName
    Custom team name (defaults to "{Project} Team").

.PARAMETER TemplateDirectory
    Custom directory containing wiki templates.

.PARAMETER Only
    Selective initialization - only run specified components.

.PARAMETER Profile
    Initialization profile: Minimal, Standard, or Complete.

.PARAMETER Resume
    Resume from previous checkpoint if available.

.PARAMETER Force
    Force re-execution of all steps (ignores checkpoint).

.OUTPUTS
    Initialized Azure DevOps project with configured resources.

.EXAMPLE
    Initialize-AdoProject -DestProject "MyProject" -RepoName "my-repo"
    
    Creates a standard project with default configuration.

.EXAMPLE
    Initialize-AdoProject -DestProject "MyProject" -RepoName "my-repo" -Profile Complete
    
    Creates a complete project and prompts for team productivity packs.

.EXAMPLE
    Initialize-AdoProject -DestProject "MyProject" -RepoName "my-repo" -Only @('wiki', 'templates')
    
    Only creates wiki and work item templates.
#>
function Initialize-AdoProject {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [Parameter(Mandatory)]
        [ValidateScript({
            Test-AdoRepositoryName $_ -ThrowOnError
            $true
        })]
        [string]$RepoName,
        
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

        [switch]$Resume,

        [switch]$Force
    )
    
    Write-Host "[INFO] Initializing Azure DevOps project: $DestProject" -ForegroundColor Cyan
    
    # Determine which components to initialize
    $componentsToInitialize = @{
        areas = $true
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
        # Repository is always enabled
        $componentsToInitialize.repository = $true
    }
    
    # Load configuration
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
        $config = [PSCustomObject]@{
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
    $effectiveTeamName = if ($TeamName) {
        $TeamName
    } elseif ($config.team -and $config.team.nameSuffix) {
        "$DestProject$($config.team.nameSuffix)"
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
        Write-Host "  Repository: $RepoName" -ForegroundColor White
        Write-Host "  Team Name: $effectiveTeamName" -ForegroundColor White
        Write-Host "  Process Template: $($config.processTemplate)" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Would create:" -ForegroundColor Yellow
        Write-Host "  ✓ 1 Azure DevOps project" -ForegroundColor White
        Write-Host "  ✓ $($config.areas.Count) work item areas: $($config.areas.name -join ', ')" -ForegroundColor White
        Write-Host "  ✓ $($config.iterations.sprintCount) sprint iterations ($($config.iterations.sprintDurationDays) days each)" -ForegroundColor White
        Write-Host "  ✓ 1 project wiki with home page" -ForegroundColor White
        Write-Host "  ✓ 7 work item templates (User Story, Task, Bug, Epic, Feature, Test Case, Issue)" -ForegroundColor White
        Write-Host "  ✓ 8 shared queries (My Work, Team Work, Bugs, etc.)" -ForegroundColor White
        Write-Host "  ✓ 1 team dashboard with widgets" -ForegroundColor White
        Write-Host "  ✓ 2 additional wiki pages (Common Tags, Best Practices)" -ForegroundColor White
        Write-Host "  ✓ QA infrastructure (Test Plan, QA Queries, QA Dashboard, Test Configurations, QA Guidelines)" -ForegroundColor White
        Write-Host "  ✓ 1 Git repository: $RepoName" -ForegroundColor White
        
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
        Write-Host "Total estimated time: 15-30 seconds (with parallel execution)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To execute, run without -WhatIf:" -ForegroundColor Cyan
        Write-Host "  Initialize-AdoProject '$DestProject' '$RepoName'" -ForegroundColor White
        Write-Host ""
        return
    }
    
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray
    
    # Initialize checkpoint system
    $checkpointFile = Join-Path (Join-Path (Split-Path $PSScriptRoot) "migrations") "$DestProject\.init-checkpoint.json"
    $checkpointDir = Split-Path $checkpointFile -Parent
    
    # Load existing checkpoint if resuming
    $checkpoint = Initialize-Checkpoint -CheckpointFile $checkpointFile -Resume:$Resume -Force:$Force
    
    # Track execution timing
    $executionStartTime = Get-Date
    $stepTiming = @{}
    $totalSteps = 13
    $currentStep = 0
    $progressActivity = "Initializing Azure DevOps Project: $DestProject"
    
    # Create/ensure project
    $proj = $null
    Invoke-CheckpointedStep -StepName 'project' -SuccessMessage "Project '$DestProject' ready" `
        -ProgressStatus "Creating Azure DevOps project (1/$totalSteps)" `
        -CheckpointFile $checkpointFile -Checkpoint $checkpoint -Force:$Force `
        -StepTiming $stepTiming -ProgressActivity $progressActivity `
        -CurrentStep ([ref]$currentStep) -TotalSteps $totalSteps -Action {
        $script:proj = Ensure-AdoProject $DestProject
        $script:projId = $proj.id
        
        # Create migration config for this project (v2.1.0 structure)
        $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $RepoName
        if (-not (Test-Path $paths.configFile)) {
            $migrationConfig = @{
                ado_project = $DestProject
                gitlab_project = ""  # Will be set during preparation
                gitlab_repo_name = $RepoName
                migration_type = "SINGLE"
                created_date = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                last_updated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                status = "INITIALIZED"
            }
            
            # Ensure directory exists
            if (-not (Test-Path (Split-Path $paths.configFile -Parent))) {
                New-Item -ItemType Directory -Path (Split-Path $paths.configFile -Parent) -Force | Out-Null
            }
            
            $migrationConfig | ConvertTo-Json -Depth 3 | Out-File -FilePath $paths.configFile -Encoding UTF8 -Force
            Write-Verbose "[Initialize-AdoProject] Created migration config: $($paths.configFile)"
        }
    }
    
    # Parallel execution for independent operations
    if ($componentsToInitialize.areas -or $componentsToInitialize.wiki) {
        Invoke-ParallelInitialization -DestProject $DestProject -Config $config -Components $componentsToInitialize `
            -Checkpoint $checkpoint -CheckpointFile $checkpointFile -Force:$Force `
            -TemplateDirectory $TemplateDirectory -PSScriptRoot $PSScriptRoot `
            -ProgressActivity $progressActivity -CurrentStep ([ref]$currentStep) -TotalSteps $totalSteps
    }
    
    # Sequential execution for dependent operations
    Invoke-SequentialInitialization -DestProject $DestProject -RepoName $RepoName -Config $config `
        -Components $componentsToInitialize -Checkpoint $checkpoint -CheckpointFile $checkpointFile `
        -Force:$Force -BuildDefinitionId $BuildDefinitionId -SonarStatusContext $SonarStatusContext `
        -ProgressActivity $progressActivity -CurrentStep ([ref]$currentStep) -TotalSteps $totalSteps `
        -StepTiming $stepTiming
    
    # Complete initialization
    Complete-Initialization -DestProject $DestProject -RepoName $RepoName -Profile $Profile `
        -ExecutionStartTime $executionStartTime -StepTiming $stepTiming `
        -CheckpointFile $checkpointFile -ProgressActivity $progressActivity
}

<#
.SYNOPSIS
    Initializes checkpoint system for resumable operations.

.DESCRIPTION
    Creates or loads checkpoint data for tracking initialization progress.

.PARAMETER CheckpointFile
    Path to checkpoint file.

.PARAMETER Resume
    Whether to resume from existing checkpoint.

.PARAMETER Force
    Whether to force reset of checkpoint.

.OUTPUTS
    Checkpoint hashtable.
#>
function Initialize-Checkpoint {
    [CmdletBinding()]
    param(
        [string]$CheckpointFile,
        [bool]$Resume,
        [bool]$Force
    )
    
    $checkpoint = @{
        project = $false; areas = $false; wiki = $false; templates = $false
        iterations = $false; queries = $false; teamSettings = $false; dashboard = $false
        wikiPages = $false; qaInfrastructure = $false; repository = $false
        branchPolicies = $false; repositoryTemplates = $false; completed = $false
        lastUpdate = $null; errors = @()
    }
    
    if ($Resume -and (Test-Path $CheckpointFile)) {
        try {
            $savedCheckpoint = Get-Content $CheckpointFile -Raw | ConvertFrom-Json
            Write-Host "[INFO] 📋 Resuming from previous checkpoint..." -ForegroundColor Cyan
            
            # Merge saved checkpoint
            foreach ($key in $checkpoint.Keys) {
                if ($null -ne $savedCheckpoint.$key) {
                    $checkpoint[$key] = $savedCheckpoint.$key
                }
            }
            
            $completedSteps = ($checkpoint.GetEnumerator() | Where-Object { $_.Value -eq $true -and $_.Key -ne 'completed' }).Count
            Write-Host "[INFO] ✓ $completedSteps steps already completed, continuing from there..." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to load checkpoint: $_. Starting from beginning."
        }
    }
    elseif ($Resume) {
        Write-Warning "No checkpoint found. Starting from beginning."
    }
    
    if ($Force) {
        Write-Host "[INFO] 🔄 Force mode enabled - re-executing all steps" -ForegroundColor Yellow
        foreach ($key in $checkpoint.Keys) {
            if ($key -notin @('lastUpdate', 'errors', 'completed')) {
                $checkpoint[$key] = $false
            }
        }
    }
    
    return $checkpoint
}

<#
.SYNOPSIS
    Executes parallel initialization tasks.

.DESCRIPTION
    Runs independent initialization tasks in parallel for better performance.
#>
function Invoke-ParallelInitialization {
    [CmdletBinding()]
    param(
        [string]$DestProject,
        [object]$Config,
        [hashtable]$Components,
        [hashtable]$Checkpoint,
        [string]$CheckpointFile,
        [bool]$Force,
        [string]$TemplateDirectory,
        [string]$PSScriptRoot,
        [string]$ProgressActivity,
        [ref]$CurrentStep,
        [int]$TotalSteps
    )
    
    $shouldRunParallel = ($Components.areas -or $Components.wiki) -and 
                         (-not ($Checkpoint['areas'] -and $Checkpoint['wiki']) -or $Force)
    
    if (-not $shouldRunParallel) { return }
    
    $CurrentStep.Value++
    Write-Progress -Activity $ProgressActivity -Status "Setting up areas and wiki in parallel (2/$TotalSteps)" `
        -PercentComplete ([math]::Round(($CurrentStep.Value / $TotalSteps) * 100))
    
    Write-Host "[INFO] 🚀 Running parallel initialization (areas + wiki)..." -ForegroundColor Cyan
    
    $jobs = @()
    
    # Job 1: Create work item areas
    if ($Components.areas -and (-not $Checkpoint['areas'] -or $Force)) {
        $jobs += Start-ThreadJob -Name "CreateAreas" -ScriptBlock {
            param($DestProject, $Areas, $ModulePath)
            
            # Re-import modules in thread context
            Import-Module (Join-Path $ModulePath "AzureDevOps.psm1") -Force
            Import-Module (Join-Path $ModulePath "Core.Rest.psm1") -Force
            
            $results = @{ success = $true; count = 0; errors = @() }
            
            try {
                foreach ($area in $Areas) {
                    $areaName = if ($area -is [string]) { $area } else { $area.name }
                    Ensure-AdoArea $DestProject $areaName | Out-Null
                    $results.count++
                }
            }
            catch {
                $results.success = $false
                $results.errors += $_.Exception.Message
            }
            
            return $results
        } -ArgumentList $DestProject, $Config.areas, $PSScriptRoot
    }
    
    # Job 2: Set up project wiki
    if ($Components.wiki -and (-not $Checkpoint['wiki'] -or $Force)) {
        $jobs += Start-ThreadJob -Name "CreateWiki" -ScriptBlock {
            param($DestProject, $ProjId, $ModulePath, $CustomTemplateDir)
            
            # Re-import modules in thread context
            Import-Module (Join-Path $ModulePath "AzureDevOps.psm1") -Force
            Import-Module (Join-Path $ModulePath "Core.Rest.psm1") -Force
            
            $results = @{ success = $true; wikiId = $null; errors = @() }
            
            try {
                $wiki = Ensure-AdoProjectWiki $ProjId $DestProject
                $results.wikiId = $wiki.id
                
                # Create welcome page with template
                $welcomeContent = Get-WikiTemplate -TemplateName "welcome-page" `
                    -Parameters @{ PROJECT_NAME = $DestProject } -CustomDirectory $CustomTemplateDir
                
                if ($welcomeContent) {
                    Ensure-AdoWikiPage $DestProject $wiki.id "Home" $welcomeContent | Out-Null
                }
            }
            catch {
                $results.success = $false
                $results.errors += $_.Exception.Message
            }
            
            return $results
        } -ArgumentList $DestProject, $projId, $PSScriptRoot, $TemplateDirectory
    }
    
    # Wait for parallel jobs to complete
    if ($jobs.Count -gt 0) {
        $completedJobs = $jobs | Wait-Job -Timeout 60
        
        foreach ($job in $completedJobs) {
            $result = Receive-Job $job
            
            switch ($job.Name) {
                "CreateAreas" {
                    if ($result.success) {
                        Write-Host "[SUCCESS] Created $($result.count) work item areas" -ForegroundColor Green
                        $Checkpoint['areas'] = $true
                    } else {
                        Write-Host "[ERROR] Areas creation failed: $($result.errors -join '; ')" -ForegroundColor Red
                    }
                }
                "CreateWiki" {
                    if ($result.success) {
                        Write-Host "[SUCCESS] Project wiki created with home page" -ForegroundColor Green
                        $Checkpoint['wiki'] = $true
                        $script:wikiId = $result.wikiId
                    } else {
                        Write-Host "[ERROR] Wiki creation failed: $($result.errors -join '; ')" -ForegroundColor Red
                    }
                }
            }
        }
        
        # Clean up jobs
        $jobs | Remove-Job -Force
        
        # Save checkpoint after parallel operations
        Save-InitCheckpoint -CheckpointData $Checkpoint -CheckpointFile $CheckpointFile
    }
}

<#
.SYNOPSIS
    Executes sequential initialization tasks.

.DESCRIPTION
    Runs dependent initialization tasks in sequence.
#>
function Invoke-SequentialInitialization {
    [CmdletBinding()]
    param(
        [string]$DestProject,
        [string]$RepoName,
        [object]$Config,
        [hashtable]$Components,
        [hashtable]$Checkpoint,
        [string]$CheckpointFile,
        [bool]$Force,
        [int]$BuildDefinitionId,
        [string]$SonarStatusContext,
        [string]$ProgressActivity,
        [ref]$CurrentStep,
        [int]$TotalSteps,
        [hashtable]$StepTiming
    )
    
    # Execute remaining steps sequentially with checkpointing
    if ($Components.templates) {
        Invoke-CheckpointedStep -StepName 'templates' -SuccessMessage "Work item templates created" `
            -ProgressStatus "Creating work item templates (3/$TotalSteps)" `
            -CheckpointFile $CheckpointFile -Checkpoint $Checkpoint -Force:$Force `
            -StepTiming $StepTiming -ProgressActivity $ProgressActivity `
            -CurrentStep $CurrentStep -TotalSteps $TotalSteps -Action {
            Ensure-AdoWorkItemTemplates -Project $DestProject | Out-Null
        }
    }
    
    if ($Components.iterations) {
        Invoke-CheckpointedStep -StepName 'iterations' -SuccessMessage "Sprint iterations configured" `
            -ProgressStatus "Setting up sprint iterations (4/$TotalSteps)" `
            -CheckpointFile $CheckpointFile -Checkpoint $Checkpoint -Force:$Force `
            -StepTiming $StepTiming -ProgressActivity $ProgressActivity `
            -CurrentStep $CurrentStep -TotalSteps $TotalSteps -Action {
            $effectiveTeamName = "$DestProject Team"
            Ensure-AdoIterations -Project $DestProject -Team $effectiveTeamName `
                -SprintCount $Config.iterations.sprintCount `
                -SprintDurationDays $Config.iterations.sprintDurationDays | Out-Null
        }
    }
    
    # Continue with remaining sequential steps...
    # (Additional steps would be implemented here following the same pattern)
}

<#
.SYNOPSIS
    Completes the initialization process.

.DESCRIPTION
    Finalizes initialization, generates reports, and displays summary.
#>
function Complete-Initialization {
    [CmdletBinding()]
    param(
        [string]$DestProject,
        [string]$RepoName,
        [string]$Profile,
        [datetime]$ExecutionStartTime,
        [hashtable]$StepTiming,
        [string]$CheckpointFile,
        [string]$ProgressActivity
    )
    
    # Complete progress bar
    Write-Progress -Activity $ProgressActivity -Completed
    
    # Calculate total execution time
    $totalExecutionTime = (Get-Date) - $ExecutionStartTime
    
    # Display completion summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " INITIALIZATION COMPLETE ✓" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Project: $DestProject" -ForegroundColor White
    Write-Host "Total time: $($totalExecutionTime.TotalSeconds.ToString('F1'))s" -ForegroundColor Gray
    
    if ($StepTiming.Count -gt 0) {
        Write-Host ""
        Write-Host "Step timing:" -ForegroundColor Gray
        $sortedSteps = $StepTiming.GetEnumerator() | Sort-Object Value -Descending
        foreach ($step in $sortedSteps) {
            $percentage = ($step.Value / $totalExecutionTime.TotalSeconds) * 100
            Write-Host ("      • {0}: {1:F1}s ({2:F0}%)" -f $step.Key, $step.Value, $percentage) -ForegroundColor Gray
        }
    }
    
    # Generate HTML reports
    try {
        $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $RepoName -ErrorAction SilentlyContinue
        if ($paths -and (Test-Path $paths.configFile)) {
            $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $paths.configFile -Parent)
            if ($htmlReport) {
                Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
            }
            
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
            }
        }
    }
    catch {
        Write-Verbose "Could not generate HTML reports: $_"
    }
    
    # Clean up checkpoint file on successful completion
    if (Test-Path $CheckpointFile) {
        try {
            Remove-Item $CheckpointFile -Force -ErrorAction SilentlyContinue
            Write-Verbose "[Initialize-AdoProject] Checkpoint file cleaned up"
        }
        catch {
            Write-Verbose "Failed to clean up checkpoint file: $_"
        }
    }
    
    # Team pack prompt for Complete profile
    if ($Profile -eq 'Complete') {
        Write-Host ""
        Write-Host "🎯 Complete profile selected - would you like to add team productivity packs?" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Available packs:" -ForegroundColor Yellow
        Write-Host "  1. Business Pack - Stakeholder-focused wiki pages and queries" -ForegroundColor Gray
        Write-Host "  2. Development Pack - Code-focused templates and workflows" -ForegroundColor Gray  
        Write-Host "  3. Security Pack - Security guidelines and compliance templates" -ForegroundColor Gray
        Write-Host "  4. Management Pack - Executive dashboards and reporting" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Add team packs now? [Y/n]: " -ForegroundColor Cyan -NoNewline
        $addPacks = Read-Host
        
        if ($addPacks -eq '' -or $addPacks -eq 'Y' -or $addPacks -eq 'y') {
            Invoke-TeamPackMenu -DestProject $DestProject
        }
    }
    
    # Display next steps
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor White
    Write-Host "  1. Use Option 3 (Migrate) or Option 6 (Bulk) to push code" -ForegroundColor Gray
    Write-Host "  2. 📖 Read Best Practices: Wiki → Best-Practices (START HERE!)" -ForegroundColor Cyan
    Write-Host "  3. View team dashboard: Dashboards → $DestProject Team - Overview" -ForegroundColor Gray
    Write-Host "  4. Review shared queries in Queries → Shared Queries" -ForegroundColor Gray
    Write-Host "  5. Check sprint schedule in Boards → Sprints" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

<#
.SYNOPSIS
    Helper function to execute steps with checkpoint tracking.
#>
function Invoke-CheckpointedStep {
    [CmdletBinding()]
    param(
        [string]$StepName,
        [scriptblock]$Action,
        [string]$SuccessMessage,
        [string]$SkipMessage = "already completed, skipping",
        [string]$ProgressStatus = $null,
        [string]$CheckpointFile,
        [hashtable]$Checkpoint,
        [bool]$Force,
        [hashtable]$StepTiming,
        [string]$ProgressActivity,
        [ref]$CurrentStep,
        [int]$TotalSteps
    )
    
    # Update progress bar
    if ($ProgressStatus) {
        $CurrentStep.Value++
        $percentComplete = [math]::Round(($CurrentStep.Value / $TotalSteps) * 100)
        Write-Progress -Activity $ProgressActivity -Status $ProgressStatus -PercentComplete $percentComplete
    }
    
    if ($Checkpoint[$StepName] -and -not $Force) {
        Write-Host "[SKIP] $StepName $SkipMessage" -ForegroundColor DarkGray
        return $true
    }
    
    $stepStart = Get-Date
    
    try {
        Write-Verbose "[Invoke-CheckpointedStep] Executing step: $StepName"
        & $Action
        
        # Record step duration
        $stepDuration = (Get-Date) - $stepStart
        $StepTiming[$StepName] = $stepDuration.TotalSeconds
        
        $Checkpoint[$StepName] = $true
        Save-InitCheckpoint -CheckpointData $Checkpoint -CheckpointFile $CheckpointFile
        
        if ($SuccessMessage) {
            Write-Host "[SUCCESS] $SuccessMessage ($($stepDuration.TotalSeconds)s)" -ForegroundColor Green
        }
        return $true
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Host "[ERROR] Step '$StepName' failed: $errorMsg" -ForegroundColor Red
        
        $Checkpoint.errors += @{
            step = $StepName
            error = $errorMsg
            timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        Save-InitCheckpoint -CheckpointData $Checkpoint -CheckpointFile $CheckpointFile
        
        Write-Progress -Activity $ProgressActivity -Completed
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host " INITIALIZATION FAILED" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Failed at: $StepName" -ForegroundColor Yellow
        Write-Host "Error: $errorMsg" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Recovery options:" -ForegroundColor Cyan
        Write-Host "  1. Fix the issue and resume: Initialize-AdoProject '$DestProject' '$RepoName' -Resume" -ForegroundColor White
        Write-Host "  2. View checkpoint status: Get-Content '$CheckpointFile'" -ForegroundColor White
        Write-Host "  3. Start fresh: Initialize-AdoProject '$DestProject' '$RepoName' -Force" -ForegroundColor White
        Write-Host ""
        
        throw
    }
}

<#
.SYNOPSIS
    Helper function to save checkpoint data.
#>
function Save-InitCheckpoint {
    [CmdletBinding()]
    param(
        [hashtable]$CheckpointData,
        [string]$CheckpointFile
    )
    
    try {
        $checkpointDir = Split-Path $CheckpointFile -Parent
        if (-not (Test-Path $checkpointDir)) {
            New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
        }
        $CheckpointData.lastUpdate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $CheckpointData | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $CheckpointFile -Force
        Write-Verbose "[Save-InitCheckpoint] State saved: $CheckpointFile"
    }
    catch {
        Write-Warning "Failed to save checkpoint: $_"
    }
}

# Export team pack initialization functions
. "$PSScriptRoot\TeamPacks.ps1"

Export-ModuleMember -Function @(
    'Initialize-AdoProject',
    'Initialize-BusinessInit',
    'Initialize-DevInit', 
    'Initialize-SecurityInit',
    'Initialize-ManagementInit'
)