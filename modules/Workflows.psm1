<#
.SYNOPSIS
    Migration workflow orchestration module for GitLab to Azure DevOps migration.

.DESCRIPTION
    Handles single project migrations, bulk migration workflows, and preparation
    workflows with progress tracking, error handling, and reporting.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.1.0
    Requires: AzureDevOps module, GitLab module, Logging module
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import required modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot "AzureDevOps.psm1") -Force -Global
Import-Module (Join-Path $ModuleRoot "GitLab.psm1") -Force -Global
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force -Global
Import-Module (Join-Path $ModuleRoot "Core.Rest.psm1") -Force -Global

<#
.SYNOPSIS
    Migrates a single GitLab project to Azure DevOps.

.DESCRIPTION
    Complete migration including Git repository push, history preservation,
    and migration tracking. Supports sync mode for updates.

.PARAMETER SrcPath
    GitLab project path.

.PARAMETER DestProject
    Azure DevOps project name.

.PARAMETER AllowSync
    Allow repository synchronization.

.PARAMETER Force
    Force migration even if repository exists.

.PARAMETER Replace
    Replace existing repository content.

.EXAMPLE
    Invoke-SingleMigration "group/project" "MyProject" -AllowSync
#>
function Invoke-SingleMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrcPath,
        
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [switch]$AllowSync,
        
        [switch]$Force,
        
        [switch]$Replace
    )
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $errorMsg = New-ActionableError -ErrorType 'GitNotFound' -Details @{}
        throw $errorMsg
    }
    
    Write-Host "[INFO] Starting migration: $SrcPath → $DestProject" -ForegroundColor Cyan
    Write-Host "[INFO] IMPORTANT: Migration requires preparation (Option 1) to be completed first" -ForegroundColor Yellow
    Write-Host "          All GitLab connections must happen during preparation." -ForegroundColor Gray
    
    # Extract repository name from path
    $repoName = ($SrcPath -split '/')[-1]
    
    # Detect project structure (new v2.1.0+ vs legacy)
    $migrationsDir = Get-MigrationsDirectory
    $newConfigFile = Join-Path $migrationsDir "$DestProject\migration-config.json"
    $legacyReportDir = Join-Path $migrationsDir "$repoName\reports"
    
    if (Test-Path $newConfigFile) {
        # New self-contained structure (v2.1.0+)
        Write-Host "[INFO] Using v2.1.0+ self-contained structure" -ForegroundColor Cyan
        $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $repoName
        $reportsDir = $paths.reportsDir
        $logsDir = $paths.logsDir
        $repoDir = $paths.repositoryDir
        
        # Look for preflight report in GitLab project subfolder
        $preflightFile = Join-Path $paths.gitlabDir "reports\preflight-report.json"
    }
    else {
        # Legacy flat structure (deprecated but supported)
        Write-Host "[INFO] Using legacy flat structure (consider re-preparing with v2.1.0+)" -ForegroundColor Yellow
        $paths = Get-ProjectPaths -ProjectName $repoName
        $reportsDir = $paths.reportsDir
        $logsDir = $paths.logsDir
        $repoDir = $paths.repositoryDir
        $preflightFile = Join-Path $reportsDir "preflight-report.json"
    }
    
    # Check for existing preflight report
    $useLocalRepo = $false
    $gl = $null
    
    if (Test-Path $preflightFile) {
        Write-Host "[INFO] Using preflight report: $preflightFile"
        $preflightData = Get-Content $preflightFile | ConvertFrom-Json
        
        # Validate repository size
        if ($preflightData.repo_size_MB -gt 100) {
            Write-Host "[WARN] Large repository detected: $($preflightData.repo_size_MB) MB" -ForegroundColor Yellow
        }
        
        # Check LFS
        if ($preflightData.lfs_enabled) {
            Write-Host "[INFO] Git LFS detected - will be preserved during migration" -ForegroundColor Cyan
        }
        
        # Create synthetic GitLab project object from preflight data
        $gl = [PSCustomObject]@{
            path_with_namespace = $SrcPath
            name = $repoName
            default_branch = $preflightData.default_branch
            statistics = [PSCustomObject]@{
                repository_size = $preflightData.repo_size_MB * 1MB
            }
            lfs_enabled = $preflightData.lfs_enabled
            visibility = $preflightData.visibility_level
        }
        
        # Check if prepared repository exists
        if (Test-Path $repoDir) {
            Write-Host "[INFO] Using prepared repository: $repoDir" -ForegroundColor Cyan
            $useLocalRepo = $true
        }
        else {
            Write-Host "[ERROR] Prepared repository not found: $repoDir" -ForegroundColor Red
            Write-Host "[INFO] Please run Option 1 (Preparation) first to clone the repository" -ForegroundColor Yellow
            throw "Repository preparation required. Run Option 1 first."
        }
    }
    else {
        Write-Host "[ERROR] Preflight report not found: $preflightFile" -ForegroundColor Red
        Write-Host "[INFO] Please run Option 1 (Preparation) first" -ForegroundColor Yellow
        throw "Migration preparation required. Run Option 1 first."
    }
    
    # Pre-migration report (Azure DevOps side only)
    $report = New-MigrationPreReport $SrcPath $DestProject $repoName -AllowSync:$AllowSync
    
    # Log file for this migration
    $logFile = New-MigrationLogFile -ProjectName $repoName -Operation "migration" -LogsDir $logsDir
    
    try {
        Start-Transcript -Path $logFile -Append
        
        Write-Host "[INFO] Repository: $($gl.path_with_namespace)" -ForegroundColor Gray
        Write-Host "[INFO] Size: $([math]::Round($gl.statistics.repository_size / 1MB, 2)) MB" -ForegroundColor Gray
        Write-Host "[INFO] Default branch: $($gl.default_branch)" -ForegroundColor Gray
        Write-Host "[INFO] Visibility: $($gl.visibility)" -ForegroundColor Gray
        Write-Host "[INFO] LFS enabled: $($gl.lfs_enabled)" -ForegroundColor Gray
        Write-Host ""
        
        # Get or create Azure DevOps repository
        $adoRepo = Ensure-AdoRepository -Project $DestProject -RepoName $repoName -AllowSync:$AllowSync -Force:$Force
        Write-Host "[SUCCESS] Azure DevOps repository ready" -ForegroundColor Green
        
        # Push from prepared local repository to Azure DevOps
        $success = if ($useLocalRepo) {
            Push-PreparedRepoToAdo -LocalRepoPath $repoDir -AdoProject $DestProject -AdoRepoName $repoName
        } else {
            # Fallback: clone and push (should not happen if preparation was done correctly)
            Write-Host "[WARN] Falling back to direct clone and push (not recommended)" -ForegroundColor Yellow
            Push-GitLabToAdo -GitLabProject $gl -AdoProject $DestProject -AdoRepoName $repoName -AllowSync:$AllowSync
        }
        
        if (-not $success) {
            throw "Git repository push failed"
        }
        
        # Apply branch policies after successful push (with delay for Azure DevOps to recognize branches)
        Write-Host "[INFO] Waiting 2 seconds for Azure DevOps to recognize branches..." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        
        $defaultRef = Get-AdoRepoDefaultBranch $DestProject $adoRepo.id
        if ($defaultRef) {
            Write-Host "[INFO] Applying branch policies to: $defaultRef" -ForegroundColor Cyan
            try {
                Ensure-AdoBranchPolicies -Project $DestProject -RepoId $adoRepo.id -Ref $defaultRef
                Write-Host "[SUCCESS] Branch policies applied" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to apply branch policies: $_"
                Write-Host "[INFO] You can configure branch policies manually via Azure DevOps web interface" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "[INFO] No default branch found - skipping branch policies" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " MIGRATION COMPLETE ✓" -ForegroundColor Green  
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Source: $SrcPath" -ForegroundColor White
        Write-Host "Destination: $DestProject/$repoName" -ForegroundColor White
        Write-Host "Repository URL: $($adoRepo.webUrl)" -ForegroundColor Gray
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        # Generate final report
        $migrationSummary = [PSCustomObject]@{
            timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            source_project = $SrcPath
            destination_project = $DestProject
            destination_repo = $repoName
            repo_size_MB = [math]::Round($gl.statistics.repository_size / 1MB, 2)
            lfs_enabled = $gl.lfs_enabled
            default_branch = $gl.default_branch
            visibility = $gl.visibility
            ado_repo_url = $adoRepo.webUrl
            migration_method = if ($useLocalRepo) { "prepared_repository" } else { "direct_clone" }
            branch_policies_applied = ($null -ne $defaultRef)
            sync_mode = $AllowSync.IsPresent
            status = "SUCCESS"
            notes = "Migration completed successfully. Repository available at: $($adoRepo.webUrl)"
        }
        
        $summaryFile = Join-Path $reportsDir "migration-summary.json"
        Write-MigrationReport -ReportFile $summaryFile -Data $migrationSummary
        Write-Host "[INFO] Migration summary: $summaryFile" -ForegroundColor Cyan
        
        # Generate HTML reports
        try {
            if ($newConfigFile -and (Test-Path $newConfigFile)) {
                $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $newConfigFile -Parent)
                if ($htmlReport) {
                    Write-Host "[INFO] HTML report updated: $htmlReport" -ForegroundColor Cyan
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
        
        # Clear Git credentials for security
        Clear-GitCredentials
        
        return $migrationSummary
    }
    catch {
        Write-Host "[ERROR] Migration failed: $_" -ForegroundColor Red
        
        # Generate failure report
        $failureSummary = [PSCustomObject]@{
            timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            source_project = $SrcPath
            destination_project = $DestProject
            destination_repo = $repoName
            status = "FAILED"
            error = $_.Exception.Message
            notes = "Migration failed. Check logs for details: $logFile"
        }
        
        $failureFile = Join-Path $reportsDir "migration-failure.json"
        Write-MigrationReport -ReportFile $failureFile -Data $failureSummary
        
        Clear-GitCredentials
        throw
    }
    finally {
        if ((Get-Command Stop-Transcript -ErrorAction SilentlyContinue)) {
            try { Stop-Transcript } catch { }
        }
    }
}

<#
.SYNOPSIS
    Prepares multiple GitLab projects for bulk migration.

.DESCRIPTION
    Analyzes GitLab projects, creates Azure DevOps project structure,
    and prepares local repository clones for efficient bulk migration.

.PARAMETER GitLabPaths
    Array of GitLab project paths to prepare.

.PARAMETER DestProject
    Azure DevOps destination project name.

.PARAMETER ConfigFile
    Optional bulk configuration template file.

.EXAMPLE
    Invoke-BulkPreparationWorkflow @("org/app1", "org/app2") "ConsolidatedProject"
#>
function Invoke-BulkPreparationWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$GitLabPaths,
        
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [string]$ConfigFile = $null
    )
    
    Write-Host "[INFO] Starting bulk preparation workflow..." -ForegroundColor Cyan
    Write-Host "[INFO] Projects: $($GitLabPaths.Count)" -ForegroundColor Gray
    Write-Host "[INFO] Destination: $DestProject" -ForegroundColor Gray
    Write-Host ""
    
    $preparationStartTime = Get-Date
    
    # Create bulk migration paths (v2.1.0 self-contained structure)
    $paths = Get-BulkProjectPaths -AdoProject $DestProject
    $bulkConfigFile = $paths.configFile
    $bulkReportsDir = $paths.reportsDir
    $bulkLogsDir = $paths.logsDir
    $containerDir = $paths.containerDir
    
    # Ensure directories exist
    @($bulkReportsDir, $bulkLogsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
    
    # Start logging
    $logFile = New-MigrationLogFile -ProjectName $DestProject -Operation "bulk-preparation" -LogsDir $bulkLogsDir
    Start-Transcript -Path $logFile -Append
    
    try {
        # Initialize bulk configuration
        $bulkConfig = Initialize-BulkConfig -DestProject $DestProject -GitLabPaths $GitLabPaths -ConfigFile $ConfigFile
        
        # Create or ensure Azure DevOps project exists
        Write-Host "[INFO] Ensuring Azure DevOps project: $DestProject" -ForegroundColor Cyan
        $adoProj = Ensure-AdoProject $DestProject
        Write-Host "[SUCCESS] Azure DevOps project ready: $($adoProj.name)" -ForegroundColor Green
        
        # Prepare each GitLab project
        $preparationResults = @()
        $totalProjects = $GitLabPaths.Count
        $currentProject = 0
        
        foreach ($gitlabPath in $GitLabPaths) {
            $currentProject++
            $repoName = ($gitlabPath -split '/')[-1]
            
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host " PREPARING PROJECT $currentProject/$totalProjects" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "GitLab: $gitlabPath" -ForegroundColor White
            Write-Host "Repository: $repoName" -ForegroundColor White
            Write-Host ""
            
            $projectStartTime = Get-Date
            
            try {
                # Analyze GitLab project
                Write-Host "[INFO] Analyzing GitLab project..." -ForegroundColor Cyan
                $gl = Get-GitLabProject $gitlabPath
                
                # Create project-specific paths within bulk container
                $projectPaths = Get-BulkProjectPaths -AdoProject $DestProject -GitLabProject $repoName
                
                # Ensure project directories
                @($projectPaths.gitlabDir, $projectPaths.repositoryDir, (Join-Path $projectPaths.gitlabDir "reports")) | ForEach-Object {
                    if (-not (Test-Path $_)) {
                        New-Item -ItemType Directory -Path $_ -Force | Out-Null
                    }
                }
                
                # Clone repository to project-specific location
                Write-Host "[INFO] Cloning repository..." -ForegroundColor Cyan
                $cloneResult = Invoke-GitLabClone -ProjectPath $gitlabPath -DestinationPath $projectPaths.repositoryDir
                
                if (-not $cloneResult.success) {
                    throw "Failed to clone repository: $($cloneResult.error)"
                }
                
                # Generate preflight report for this project
                $preflightData = [PSCustomObject]@{
                    timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    gitlab_project = $gitlabPath
                    repo_name = $repoName
                    repo_size_MB = [math]::Round($gl.statistics.repository_size / 1MB, 2)
                    lfs_enabled = $gl.lfs_enabled
                    visibility_level = $gl.visibility
                    default_branch = $gl.default_branch
                    clone_success = $cloneResult.success
                    clone_path = $projectPaths.repositoryDir
                    preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                
                # Save preflight report in project-specific location
                $preflightFile = Join-Path $projectPaths.gitlabDir "reports\preflight-report.json"
                Write-MigrationReport -ReportFile $preflightFile -Data $preflightData
                
                # Add to bulk config
                $projectConfig = @{
                    gitlab_path = $gitlabPath
                    ado_repo_name = $repoName
                    description = "Migrated from $gitlabPath"
                    repo_size_MB = $preflightData.repo_size_MB
                    lfs_enabled = $gl.lfs_enabled
                    lfs_size_MB = 0  # TODO: Calculate LFS size if available
                    default_branch = $gl.default_branch
                    visibility = $gl.visibility
                    preparation_status = "SUCCESS"
                }
                
                $bulkConfig.projects += $projectConfig
                
                $preparationTime = (Get-Date) - $projectStartTime
                
                Write-Host "[SUCCESS] Project prepared in $($preparationTime.TotalSeconds)s" -ForegroundColor Green
                Write-Host "[INFO] Size: $($preflightData.repo_size_MB) MB" -ForegroundColor Gray
                Write-Host "[INFO] LFS: $($gl.lfs_enabled)" -ForegroundColor Gray
                Write-Host "[INFO] Branches: Multiple (preserved)" -ForegroundColor Gray
                
                $preparationResults += [PSCustomObject]@{
                    gitlab_path = $gitlabPath
                    repo_name = $repoName
                    status = "SUCCESS"
                    size_MB = $preflightData.repo_size_MB
                    preparation_time_seconds = $preparationTime.TotalSeconds
                }
            }
            catch {
                Write-Host "[ERROR] Failed to prepare project: $_" -ForegroundColor Red
                
                $projectConfig = @{
                    gitlab_path = $gitlabPath
                    ado_repo_name = $repoName
                    description = "FAILED: $($_.Exception.Message)"
                    preparation_status = "FAILED"
                    error = $_.Exception.Message
                }
                
                $bulkConfig.projects += $projectConfig
                
                $preparationResults += [PSCustomObject]@{
                    gitlab_path = $gitlabPath
                    repo_name = $repoName
                    status = "FAILED"
                    error = $_.Exception.Message
                    size_MB = 0
                    preparation_time_seconds = 0
                }
            }
        }
        
        # Finalize bulk configuration
        $totalPreparationTime = (Get-Date) - $preparationStartTime
        $successfulPreparations = ($preparationResults | Where-Object { $_.status -eq "SUCCESS" }).Count
        $failedPreparations = ($preparationResults | Where-Object { $_.status -eq "FAILED" }).Count
        $totalSizeMB = ($preparationResults | Where-Object { $_.status -eq "SUCCESS" } | Measure-Object -Property size_MB -Sum).Sum
        
        $bulkConfig.preparation_summary = @{
            total_projects = $totalProjects
            successful_preparations = $successfulPreparations
            failed_preparations = $failedPreparations
            total_size_MB = $totalSizeMB
            total_lfs_MB = 0  # TODO: Calculate total LFS size
            preparation_time = $preparationStartTime.ToString('yyyy-MM-dd HH:mm:ss')
            preparation_duration_seconds = $totalPreparationTime.TotalSeconds
        }
        
        # Save bulk configuration
        $bulkConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $bulkConfigFile -Encoding UTF8 -Force
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " BULK PREPARATION COMPLETE ✓" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Total projects: $totalProjects" -ForegroundColor White
        Write-Host "Successful: $successfulPreparations" -ForegroundColor Green
        Write-Host "Failed: $failedPreparations" -ForegroundColor $(if ($failedPreparations -gt 0) { "Red" } else { "Gray" })
        Write-Host "Total size: $totalSizeMB MB" -ForegroundColor Gray
        Write-Host "Preparation time: $($totalPreparationTime.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Gray
        Write-Host "Configuration: $bulkConfigFile" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        if ($failedPreparations -gt 0) {
            Write-Host "⚠️  Some projects failed preparation:" -ForegroundColor Yellow
            $preparationResults | Where-Object { $_.status -eq "FAILED" } | ForEach-Object {
                Write-Host "   • $($_.gitlab_path): $($_.error)" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Review preparation results above" -ForegroundColor Gray
        Write-Host "  2. Use Option 6 (Bulk Migration) to push all prepared repositories" -ForegroundColor Gray
        Write-Host "  3. Configuration saved to: $bulkConfigFile" -ForegroundColor Gray
        Write-Host ""
        
        # Generate HTML reports
        try {
            $htmlReport = New-MigrationHtmlReport -ProjectPath $containerDir
            if ($htmlReport) {
                Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
            }
            
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Verbose "Could not generate HTML reports: $_"
        }
        
        return $bulkConfig
    }
    catch {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host " BULK PREPARATION FAILED" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Log: $logFile" -ForegroundColor Gray
        Write-Host ""
        throw
    }
    finally {
        Stop-Transcript
    }
}

<#
.SYNOPSIS
    Executes bulk migration of prepared GitLab projects.

.DESCRIPTION
    Migrates multiple prepared GitLab projects to a single Azure DevOps project,
    using prepared repositories for optimal performance.

.PARAMETER BulkConfigFile
    Path to bulk migration configuration file.

.PARAMETER Force
    Force migration even if repositories exist.

.EXAMPLE
    Invoke-BulkMigrationWorkflow "C:\migrations\MyProject\bulk-migration-config.json"
#>
function Invoke-BulkMigrationWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({
            if (-not (Test-Path $_)) { throw "Bulk configuration file not found: $_" }
            $true
        })]
        [string]$BulkConfigFile,
        
        [switch]$Force
    )
    
    Write-Host "[INFO] Starting bulk migration workflow..." -ForegroundColor Cyan
    
    # Load bulk configuration
    $bulkConfig = Get-Content $BulkConfigFile | ConvertFrom-Json
    $destProject = $bulkConfig.destination_project
    
    Write-Host "[INFO] Destination project: $destProject" -ForegroundColor Gray
    Write-Host "[INFO] Projects to migrate: $($bulkConfig.projects.Count)" -ForegroundColor Gray
    Write-Host ""
    
    $migrationStartTime = Get-Date
    
    # Create execution logs directory
    $containerDir = Split-Path $BulkConfigFile -Parent
    $executionLogsDir = Join-Path $containerDir "logs"
    if (-not (Test-Path $executionLogsDir)) {
        New-Item -ItemType Directory -Path $executionLogsDir -Force | Out-Null
    }
    
    $logFile = New-MigrationLogFile -ProjectName $destProject -Operation "bulk-execution" -LogsDir $executionLogsDir
    Start-Transcript -Path $logFile -Append
    
    try {
        # Validate Azure DevOps project exists
        if (-not (Test-AdoProjectExists -ProjectName $destProject)) {
            throw "Azure DevOps project '$destProject' not found. Run preparation first."
        }
        
        # Filter successful preparations only
        $projectsToMigrate = $bulkConfig.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }
        if ($projectsToMigrate.Count -eq 0) {
            throw "No successfully prepared projects found in configuration."
        }
        
        Write-Host "[INFO] Migrating $($projectsToMigrate.Count) prepared projects..." -ForegroundColor Cyan
        
        # Execute migrations
        $migrationResults = @()
        $currentProject = 0
        
        foreach ($projectConfig in $projectsToMigrate) {
            $currentProject++
            $gitlabPath = $projectConfig.gitlab_path
            $repoName = $projectConfig.ado_repo_name
            
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host " MIGRATING PROJECT $currentProject/$($projectsToMigrate.Count)" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "Source: $gitlabPath" -ForegroundColor White
            Write-Host "Repository: $repoName" -ForegroundColor White
            Write-Host "Size: $($projectConfig.repo_size_MB) MB" -ForegroundColor Gray
            Write-Host ""
            
            $projectStartTime = Get-Date
            
            try {
                # Get repository path from bulk structure
                $projectPaths = Get-BulkProjectPaths -AdoProject $destProject -GitLabProject $repoName
                
                if (-not (Test-Path $projectPaths.repositoryDir)) {
                    throw "Prepared repository not found: $($projectPaths.repositoryDir)"
                }
                
                # Create or get Azure DevOps repository
                Write-Host "[INFO] Ensuring Azure DevOps repository..." -ForegroundColor Cyan
                $adoRepo = Ensure-AdoRepository -Project $destProject -RepoName $repoName -AllowSync -Force:$Force
                
                # Push prepared repository
                Write-Host "[INFO] Pushing repository to Azure DevOps..." -ForegroundColor Cyan
                $pushSuccess = Push-PreparedRepoToAdo -LocalRepoPath $projectPaths.repositoryDir -AdoProject $destProject -AdoRepoName $repoName
                
                if (-not $pushSuccess) {
                    throw "Repository push failed"
                }
                
                # Apply branch policies (with delay)
                Write-Host "[INFO] Waiting for Azure DevOps to recognize branches..." -ForegroundColor Gray
                Start-Sleep -Seconds 2
                
                $defaultRef = Get-AdoRepoDefaultBranch $destProject $adoRepo.id
                if ($defaultRef) {
                    Write-Host "[INFO] Applying branch policies to: $defaultRef" -ForegroundColor Cyan
                    try {
                        Ensure-AdoBranchPolicies -Project $destProject -RepoId $adoRepo.id -Ref $defaultRef
                        Write-Host "[SUCCESS] Branch policies applied" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Failed to apply branch policies: $_"
                    }
                }
                
                $migrationTime = (Get-Date) - $projectStartTime
                
                Write-Host "[SUCCESS] Project migrated in $($migrationTime.TotalSeconds)s" -ForegroundColor Green
                Write-Host "[INFO] Repository URL: $($adoRepo.webUrl)" -ForegroundColor Gray
                
                $migrationResults += [PSCustomObject]@{
                    gitlab_path = $gitlabPath
                    ado_repo_name = $repoName
                    status = "SUCCESS"
                    repo_url = $adoRepo.webUrl
                    migration_time_seconds = $migrationTime.TotalSeconds
                    size_MB = $projectConfig.repo_size_MB
                }
            }
            catch {
                Write-Host "[ERROR] Migration failed: $_" -ForegroundColor Red
                
                $migrationResults += [PSCustomObject]@{
                    gitlab_path = $gitlabPath
                    ado_repo_name = $repoName
                    status = "FAILED"
                    error = $_.Exception.Message
                    migration_time_seconds = 0
                    size_MB = $projectConfig.repo_size_MB
                }
            }
        }
        
        # Generate final summary
        $totalMigrationTime = (Get-Date) - $migrationStartTime
        $successfulMigrations = ($migrationResults | Where-Object { $_.status -eq "SUCCESS" }).Count
        $failedMigrations = ($migrationResults | Where-Object { $_.status -eq "FAILED" }).Count
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " BULK MIGRATION COMPLETE ✓" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Total projects: $($migrationResults.Count)" -ForegroundColor White
        Write-Host "Successful: $successfulMigrations" -ForegroundColor Green
        Write-Host "Failed: $failedMigrations" -ForegroundColor $(if ($failedMigrations -gt 0) { "Red" } else { "Gray" })
        Write-Host "Migration time: $($totalMigrationTime.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Gray
        Write-Host "Destination: $destProject" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        if ($failedMigrations -gt 0) {
            Write-Host "⚠️  Some migrations failed:" -ForegroundColor Yellow
            $migrationResults | Where-Object { $_.status -eq "FAILED" } | ForEach-Object {
                Write-Host "   • $($_.gitlab_path): $($_.error)" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        # Save migration results
        $migrationSummary = [PSCustomObject]@{
            timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            destination_project = $destProject
            total_projects = $migrationResults.Count
            successful_migrations = $successfulMigrations
            failed_migrations = $failedMigrations
            total_migration_time_minutes = $totalMigrationTime.TotalMinutes
            results = $migrationResults
            bulk_config_file = $BulkConfigFile
        }
        
        $summaryFile = Join-Path (Split-Path $BulkConfigFile -Parent) "reports\bulk-migration-summary.json"
        Write-MigrationReport -ReportFile $summaryFile -Data $migrationSummary
        
        Write-Host "Migration summary saved: $summaryFile" -ForegroundColor Cyan
        Write-Host ""
        
        # Generate HTML reports
        try {
            $htmlReport = New-MigrationHtmlReport -ProjectPath $containerDir
            if ($htmlReport) {
                Write-Host "[INFO] HTML report updated: $htmlReport" -ForegroundColor Cyan
            }
            
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Verbose "Could not generate HTML reports: $_"
        }
        
        return $migrationSummary
    }
    catch {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host " BULK MIGRATION FAILED" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Log: $logFile" -ForegroundColor Gray
        Write-Host ""
        throw
    }
    finally {
        Stop-Transcript
    }
}

<#
.SYNOPSIS
    Initializes a bulk migration configuration.

.DESCRIPTION
    Creates the initial bulk configuration structure with project metadata.

.PARAMETER DestProject
    Azure DevOps destination project name.

.PARAMETER GitLabPaths
    Array of GitLab project paths.

.PARAMETER ConfigFile
    Optional configuration template file.

.OUTPUTS
    Bulk configuration object.
#>
function Initialize-BulkConfig {
    [CmdletBinding()]
    param(
        [string]$DestProject,
        [string[]]$GitLabPaths,
        [string]$ConfigFile
    )
    
    $config = [PSCustomObject]@{
        description = "Bulk migration configuration for '$DestProject'"
        destination_project = $DestProject
        migration_type = "BULK"
        preparation_summary = $null
        projects = @()
        created_date = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
        last_updated = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    
    # Load template if provided
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        try {
            $template = Get-Content $ConfigFile | ConvertFrom-Json
            # Apply template settings
            if ($template.migration_settings) {
                $config | Add-Member -NotePropertyName migration_settings -NotePropertyValue $template.migration_settings
            }
        }
        catch {
            Write-Warning "Failed to load configuration template: $_"
        }
    }
    
    return $config
}

Export-ModuleMember -Function @(
    'Invoke-SingleMigration',
    'Invoke-BulkPreparationWorkflow', 
    'Invoke-BulkMigrationWorkflow'
)