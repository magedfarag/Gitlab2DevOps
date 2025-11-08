<#
.SYNOPSIS
    Bulk migration workflows for multiple GitLab projects to Azure DevOps.

.DESCRIPTION
    This module handles bulk migrations including preparation, validation,
    and execution phases for multiple GitLab projects into a single Azure DevOps project.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, GitLab, AzureDevOps, Logging modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import required modules
$migrationRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $migrationRoot "Core\MigrationCore.psm1") -Force -Global

<#
.SYNOPSIS
    Prepares multiple GitLab projects for bulk migration.

.DESCRIPTION
    Downloads repositories, validates projects, and generates configuration
    files for bulk migration workflow.

.PARAMETER ProjectPaths
    Array of GitLab project paths.

.PARAMETER DestProject
    Azure DevOps destination project name.

.EXAMPLE
    Invoke-BulkPreparationWorkflow @("group/project1", "group/project2") "MyProject"
#>
function Invoke-BulkPreparationWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ProjectPaths,
        
        [Parameter(Mandatory)]
        [string]$DestProject
    )
    
    Write-Host "[INFO] Starting bulk preparation for $($ProjectPaths.Count) projects..." -ForegroundColor Cyan
    Write-Host "       Destination project: $DestProject"
    
    $preparationResults = @()
    $totalStartTime = Get-Date
    $successCount = 0
    $failureCount = 0
    
    # Create bulk migration folder structure (v2.1.0+)
    $bulkPaths = Get-BulkProjectPaths -AdoProject $DestProject
    
    Write-Host "[INFO] Using bulk migration folder: $($bulkPaths.containerDir)" -ForegroundColor Cyan
    
    # Ensure directories exist
    foreach ($dir in @($bulkPaths.containerDir, $bulkPaths.reportsDir, $bulkPaths.logsDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    
    # Initialize bulk log
    $bulkLogFile = New-LogFilePath -LogsDir $bulkPaths.logsDir -Prefix "bulk-preparation"
    Write-MigrationLog -LogFile $bulkLogFile -Message @(
        "=== Bulk Preparation Started ==="
        "Timestamp: $(Get-Date)"
        "Destination Project: $DestProject"
        "Projects to prepare: $($ProjectPaths.Count)"
        ($ProjectPaths | ForEach-Object { "  - $_" })
    )
    
    foreach ($gitlabPath in $ProjectPaths) {
        $projectStartTime = Get-Date
        Write-Host "[INFO] Processing project: $gitlabPath" -ForegroundColor Cyan
        
        try {
            # Get GitLab project details
            $gl = Get-GitLabProject $gitlabPath
            $repoName = $gl.path
            
            # Create paths for this specific project (avoid variable name conflict)
            $specificProjectPaths = Get-BulkProjectPaths -AdoProject $DestProject -GitLabProject $repoName
            
            # Ensure GitLab project directory exists
            if (-not (Test-Path $specificProjectPaths.gitlabDir)) {
                New-Item -ItemType Directory -Path $specificProjectPaths.gitlabDir -Force | Out-Null
            }
            if (-not (Test-Path $specificProjectPaths.reportsDir)) {
                New-Item -ItemType Directory -Path $specificProjectPaths.reportsDir -Force | Out-Null
            }
            
            # Use Initialize-GitLab with custom directory structure
            Write-Host "[INFO] Downloading repository..." -ForegroundColor Cyan
            $result = Initialize-GitLab -ProjectPath $gitlabPath -CustomBaseDir $bulkPaths.containerDir -CustomProjectName $repoName
            
            # Create preflight report in the GitLab project subfolder
            $preflightFile = Join-Path $specificProjectPaths.reportsDir "preflight-report.json"
            $preflightData = @{
                project = $gl.path_with_namespace
                ado_repo_name = $repoName
                description = "Migrated from $($gl.path_with_namespace)"
                repo_size_MB = [math]::Round(($gl.statistics.repository_size / 1MB), 2)
                lfs_enabled = $gl.lfs_enabled
                lfs_size_MB = if ($gl.lfs_enabled -and $gl.statistics.lfs_objects_size) {
                    [math]::Round(($gl.statistics.lfs_objects_size / 1MB), 2)
                } else { 0 }
                default_branch = $gl.default_branch
                visibility = $gl.visibility
                http_url_to_repo = $gl.http_url_to_repo
                preparation_status = "SUCCESS"
                preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
            
            $preflightData | ConvertTo-Json -Depth 5 | Set-Content -Path $preflightFile -Encoding UTF8
            Write-Host "[SUCCESS] Project prepared: $gitlabPath" -ForegroundColor Green
            
            $preparationResults += [pscustomobject]@{
                gitlab_path = $gitlabPath
                ado_repo_name = $repoName
                description = "Migrated from $($gl.path_with_namespace)"
                repo_size_MB = $preflightData.repo_size_MB
                lfs_enabled = $preflightData.lfs_enabled
                lfs_size_MB = $preflightData.lfs_size_MB
                default_branch = $preflightData.default_branch
                visibility = $preflightData.visibility
                preparation_status = "SUCCESS"
                preparation_duration_seconds = [math]::Round(((Get-Date) - $projectStartTime).TotalSeconds, 1)
            }
            
            $successCount++
            
            Write-MigrationLog -LogFile $bulkLogFile -Message "[SUCCESS] $gitlabPath prepared successfully (Size: $($preflightData.repo_size_MB) MB)"
        }
        catch {
            Write-Host "[ERROR] Failed to prepare $gitlabPath`: $_" -ForegroundColor Red
            
            $preparationResults += [pscustomobject]@{
                gitlab_path = $gitlabPath
                ado_repo_name = ($gitlabPath -split '/')[-1]
                description = "Failed preparation"
                repo_size_MB = 0
                lfs_enabled = $false
                lfs_size_MB = 0
                default_branch = "main"
                visibility = "private"
                preparation_status = "FAILED"
                error_message = $_.ToString()
                preparation_duration_seconds = [math]::Round(((Get-Date) - $projectStartTime).TotalSeconds, 1)
            }
            
            $failureCount++
            Write-MigrationLog -LogFile $bulkLogFile -Message "[ERROR] $gitlabPath preparation failed: $_"
        }
    }
    
    $totalEndTime = Get-Date
    $totalDuration = ($totalEndTime - $totalStartTime).TotalMinutes
    
    # Calculate totals safely (handle null/empty results)
    $successfulResults = @($preparationResults | Where-Object { $_.preparation_status -eq "SUCCESS" })
    $totalSizeMB = if ($successfulResults.Count -gt 0) {
        ($successfulResults | Measure-Object -Property repo_size_MB -Sum).Sum
    } else { 0 }
    $totalLfsMB = if ($successfulResults.Count -gt 0) {
        ($successfulResults | Measure-Object -Property lfs_size_MB -Sum).Sum
    } else { 0 }
    
    # Create bulk configuration file (v2.1.0+)
    $bulkConfig = @{
        description = "Bulk migration configuration for '$DestProject'"
        destination_project = $DestProject
        migration_type = "BULK"
        preparation_summary = @{
            total_projects = $ProjectPaths.Count
            successful_preparations = $successCount
            failed_preparations = $failureCount
            total_size_MB = $totalSizeMB
            total_lfs_MB = $totalLfsMB
            preparation_time = $totalStartTime.ToString('yyyy-MM-dd HH:mm:ss')
            preparation_duration_minutes = [math]::Round($totalDuration, 1)
        }
        projects = $preparationResults
    }
    
    $bulkConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $bulkPaths.configFile -Encoding UTF8
    
    # Write summary to log
    Write-MigrationLog -LogFile $bulkLogFile -Message @(
        "=== Bulk Preparation Completed ==="
        "Total projects: $($ProjectPaths.Count)"
        "Successful: $successCount"
        "Failed: $failureCount"
        "Total size: $totalSizeMB MB"
        "Duration: $([math]::Round($totalDuration, 1)) minutes"
        "Configuration saved: $($bulkPaths.configFile)"
    )
    
    # Display summary
    Write-Host "[INFO] Bulk preparation completed:" -ForegroundColor Cyan
    Write-Host "       Successful: $successCount / $($ProjectPaths.Count)" -ForegroundColor Green
    Write-Host "       Failed: $failureCount / $($ProjectPaths.Count)" -ForegroundColor Red
    Write-Host "       Total size: $totalSizeMB MB"
    Write-Host "       Duration: $([math]::Round($totalDuration, 1)) minutes"
    Write-Host "       Configuration: $($bulkPaths.configFile)"
    
    # Extract documentation files if any projects were successful
    if ($successCount -gt 0) {
        Write-Host ""
        Write-Host "[INFO] Extracting documentation files..." -ForegroundColor Cyan
        try {
            $docStats = Export-GitLabDocumentation -AdoProject $DestProject
            
            if ($docStats -and $docStats.total_files -gt 0) {
                Write-Host "[SUCCESS] Extracted $($docStats.total_files) documentation files ($($docStats.total_size_MB) MB)" -ForegroundColor Green
                
                # Add documentation stats to config
                $bulkConfig.preparation_summary.documentation_extracted = $docStats.total_files
                $bulkConfig.preparation_summary.documentation_size_MB = $docStats.total_size_MB
                $bulkConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $bulkPaths.configFile -Encoding UTF8
                
                Write-MigrationLog -LogFile $bulkLogFile -Message "[INFO] Documentation extraction: $($docStats.total_files) files, $($docStats.total_size_MB) MB"
            }
            else {
                Write-Host "[INFO] No documentation files found to extract" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "[WARN] Documentation extraction failed: $_"
            Write-MigrationLog -LogFile $bulkLogFile -Message "[WARN] Documentation extraction failed: $_"
        }
    }
    
    if ($failureCount -gt 0) {
        Write-Host "[WARN] Some projects failed preparation. Review logs for details." -ForegroundColor Yellow
        Write-Host "       Failed projects can be retried individually or skipped during execution."
    }
    
    return $bulkConfig
}

<#
.SYNOPSIS
    Executes bulk migration based on prepared configuration.

.DESCRIPTION
    Migrates all prepared projects to Azure DevOps repositories
    based on bulk configuration file.

.PARAMETER AdoProject
    Azure DevOps project name.

.PARAMETER Force
    Skip confirmations and proceed with migration.

.EXAMPLE
    Invoke-BulkMigrationWorkflow "MyProject" -Force
#>
function Invoke-BulkMigrationWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [switch]$Force
    )
    
    # Load bulk configuration
    $bulkPaths = Get-BulkProjectPaths -AdoProject $AdoProject
    
    if (-not (Test-Path $bulkPaths.configFile)) {
        throw "Bulk migration configuration not found: $($bulkPaths.configFile). Run bulk preparation first (Option 4)."
    }
    
    $config = Get-Content $bulkPaths.configFile | ConvertFrom-Json
    $successfulProjects = $config.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }
    
    if ($successfulProjects.Count -eq 0) {
        throw "No successfully prepared projects found in configuration. Run bulk preparation first (Option 4)."
    }
    
    Write-Host "[INFO] Starting bulk migration execution..." -ForegroundColor Cyan
    Write-Host "       Projects to migrate: $($successfulProjects.Count)"
    Write-Host "       Total size: $($config.preparation_summary.total_size_MB) MB"
    
    if (-not $Force) {
        Write-Host ""
        Write-Host "[CONFIRM] This will create $($successfulProjects.Count) repositories in Azure DevOps project '$AdoProject'."
        $confirm = Read-Host "Continue? (y/N)"
        if ($confirm -notlike 'y*') {
            Write-Host "[INFO] Migration cancelled by user."
            return
        }
    }
    
    # Ensure Azure DevOps project exists
    $proj = Measure-Adoproject $AdoProject
    Write-Host "[SUCCESS] Azure DevOps project confirmed: $AdoProject" -ForegroundColor Green
    
    # Initialize bulk execution log
    $bulkLogFile = New-LogFilePath $bulkPaths.logsDir "bulk-execution"
    $totalStartTime = Get-Date
    
    Write-MigrationLog $bulkLogFile @(
        "=== Bulk Migration Execution Started ==="
        "Timestamp: $(Get-Date)"
        "Destination Project: $AdoProject"
        "Projects to migrate: $($successfulProjects.Count)"
    )
    
    $migrationResults = @()
    $successCount = 0
    $failureCount = 0
    
    foreach ($project in $successfulProjects) {
        $projectStartTime = Get-Date
        Write-Host "[INFO] Migrating: $($project.gitlab_path) → $($project.ado_repo_name)" -ForegroundColor Cyan
        
        try {
            # Use single migration workflow for each project
            Invoke-SingleMigration -SrcPath $project.gitlab_path -DestProject $AdoProject -Force
            
            $migrationResults += [pscustomobject]@{
                gitlab_path = $project.gitlab_path
                ado_repo_name = $project.ado_repo_name
                status = "SUCCESS"
                duration_seconds = [math]::Round(((Get-Date) - $projectStartTime).TotalSeconds, 1)
            }
            
            $successCount++
            Write-Host "[SUCCESS] $($project.gitlab_path) migrated successfully" -ForegroundColor Green
            Write-MigrationLog $bulkLogFile "[SUCCESS] $($project.gitlab_path) → $($project.ado_repo_name)"
        }
        catch {
            Write-Host "[ERROR] Failed to migrate $($project.gitlab_path): $_" -ForegroundColor Red
            
            $migrationResults += [pscustomobject]@{
                gitlab_path = $project.gitlab_path
                ado_repo_name = $project.ado_repo_name
                status = "FAILED"
                error_message = $_.ToString()
                duration_seconds = [math]::Round(((Get-Date) - $projectStartTime).TotalSeconds, 1)
            }
            
            $failureCount++
            Write-MigrationLog $bulkLogFile "[ERROR] $($project.gitlab_path) migration failed: $_"
        }
    }
    
    $totalEndTime = Get-Date
    $totalDuration = ($totalEndTime - $totalStartTime).TotalMinutes
    
    # Update bulk configuration with execution results
    $config.execution_summary = @{
        execution_time = $totalStartTime.ToString('yyyy-MM-dd HH:mm:ss')
        execution_duration_minutes = [math]::Round($totalDuration, 1)
        total_migrations = $successfulProjects.Count
        successful_migrations = $successCount
        failed_migrations = $failureCount
    }
    $config.migration_results = $migrationResults
    
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $bulkPaths.configFile -Encoding UTF8
    
    # Write final summary
    Write-MigrationLog $bulkLogFile @(
        "=== Bulk Migration Execution Completed ==="
        "Total migrations: $($successfulProjects.Count)"
        "Successful: $successCount"
        "Failed: $failureCount"
        "Duration: $([math]::Round($totalDuration, 1)) minutes"
    )
    
    # Generate HTML reports for all migrated projects
    try {
        Write-Host "[INFO] Generating HTML reports..." -ForegroundColor Cyan
        foreach ($project in $migrationResults | Where-Object { $_.status -eq "SUCCESS" }) {
            $projectPaths = Get-BulkProjectPaths -AdoProject $AdoProject -GitLabProject $project.ado_repo_name
            $htmlReport = New-MigrationHtmlReport -ProjectPath $projectPaths.gitlabDir
            if ($htmlReport) {
                Write-Host "       Generated: $(Split-Path $htmlReport -Leaf)" -ForegroundColor Gray
            }
        }
        
        # Generate overview dashboard
        $overviewReport = New-MigrationsOverviewReport
        if ($overviewReport) {
            Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Failed to generate some HTML reports: $_"
    }
    
    # Display final summary
    Write-Host ""
    Write-Host "[INFO] Bulk migration execution completed:" -ForegroundColor Cyan
    Write-Host "       Successful: $successCount / $($successfulProjects.Count)" -ForegroundColor Green
    Write-Host "       Failed: $failureCount / $($successfulProjects.Count)" -ForegroundColor Red
    Write-Host "       Duration: $([math]::Round($totalDuration, 1)) minutes"
    Write-Host "       Results saved: $($bulkPaths.configFile)"
    
    if ($successCount -gt 0) {
        Write-Host ""
        Write-Host "[SUCCESS] $successCount repositories successfully migrated to Azure DevOps!" -ForegroundColor Green
        Write-Host "          Project: https://dev.azure.com/YourOrg/$([uri]::EscapeDataString($AdoProject))" -ForegroundColor White
    }
    
    if ($failureCount -gt 0) {
        Write-Host ""
        Write-Host "[WARN] $failureCount migrations failed. Review logs for details:" -ForegroundColor Yellow
        Write-Host "       $bulkLogFile"
    }
    
    return $config
}

<#
.SYNOPSIS
    Displays bulk migration preparation and execution status.

.DESCRIPTION
    Shows summary of prepared projects and their migration status
    from bulk configuration files.

.PARAMETER AdoProject
    Azure DevOps project name.

.EXAMPLE
    Show-BulkMigrationStatus "MyProject"
#>
function Show-BulkMigrationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AdoProject
    )
    
    $bulkPaths = Get-BulkProjectPaths -AdoProject $AdoProject
    
    if (-not (Test-Path $bulkPaths.configFile)) {
        Write-Host "[INFO] No bulk migration found for project: $AdoProject" -ForegroundColor Yellow
        Write-Host "       Run bulk preparation first (Option 4)."
        return
    }
    
    $config = Get-Content $bulkPaths.configFile | ConvertFrom-Json
    
    Write-Host "=== Bulk Migration Status: $AdoProject ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Preparation summary
    if ($config.preparation_summary) {
        Write-Host "Preparation Summary:" -ForegroundColor Green
        Write-Host "  • Total projects: $($config.preparation_summary.total_projects)"
        Write-Host "  • Successful preparations: $($config.preparation_summary.successful_preparations)"
        Write-Host "  • Failed preparations: $($config.preparation_summary.failed_preparations)"
        Write-Host "  • Total size: $($config.preparation_summary.total_size_MB) MB"
        Write-Host "  • Preparation time: $($config.preparation_summary.preparation_time)"
        Write-Host ""
    }
    
    # Execution summary
    if ($config.execution_summary) {
        Write-Host "Execution Summary:" -ForegroundColor Green
        Write-Host "  • Total migrations: $($config.execution_summary.total_migrations)"
        Write-Host "  • Successful migrations: $($config.execution_summary.successful_migrations)"
        Write-Host "  • Failed migrations: $($config.execution_summary.failed_migrations)"
        Write-Host "  • Execution time: $($config.execution_summary.execution_time)"
        Write-Host "  • Duration: $($config.execution_summary.execution_duration_minutes) minutes"
        Write-Host ""
    }
    else {
        Write-Host "Execution Status: " -ForegroundColor Yellow -NoNewline
        Write-Host "Not executed yet" -ForegroundColor Red
        Write-Host ""
    }
    
    # Project details
    Write-Host "Project Details:" -ForegroundColor Green
    $preparedProjects = $config.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }
    $failedProjects = $config.projects | Where-Object { $_.preparation_status -eq "FAILED" }
    
    if ($preparedProjects.Count -gt 0) {
        Write-Host "  Prepared projects ($($preparedProjects.Count)):"
        foreach ($project in $preparedProjects) {
            $status = if ($config.migration_results) {
                $migResult = $config.migration_results | Where-Object { $_.gitlab_path -eq $project.gitlab_path }
                if ($migResult) { $migResult.status } else { "PENDING" }
            } else { "PENDING" }
            
            $statusColor = switch ($status) {
                "SUCCESS" { "Green" }
                "FAILED" { "Red" }
                "PENDING" { "Yellow" }
            }
            
            Write-Host "    • $($project.gitlab_path) → $($project.ado_repo_name) " -NoNewline
            Write-Host "[$status]" -ForegroundColor $statusColor
            Write-Host "      Size: $($project.repo_size_MB) MB, LFS: $($project.lfs_size_MB) MB" -ForegroundColor Gray
        }
        Write-Host ""
    }
    
    if ($failedProjects.Count -gt 0) {
        Write-Host "  Failed preparations ($($failedProjects.Count)):" -ForegroundColor Red
        foreach ($project in $failedProjects) {
            Write-Host "    • $($project.gitlab_path) " -NoNewline
            Write-Host "[FAILED]" -ForegroundColor Red
            if ($project.error_message) {
                Write-Host "      Error: $($project.error_message)" -ForegroundColor Red
            }
        }
        Write-Host ""
    }
    
    Write-Host "Configuration file: $($bulkPaths.configFile)" -ForegroundColor Gray
    Write-Host "Container folder: $($bulkPaths.containerDir)" -ForegroundColor Gray
}

# Export public functions
Export-ModuleMember -Function @(
    'Invoke-BulkPreparationWorkflow',
    'Invoke-BulkMigrationWorkflow',
    'Show-BulkMigrationStatus'
)

