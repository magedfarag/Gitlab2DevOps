<#
.SYNOPSIS
    GitLab project analysis and preparation functions.

.DESCRIPTION
    This module handles all GitLab-specific operations including project fetching,
    repository download, and preflight report generation. It has no knowledge of
    Azure DevOps and focuses solely on source data preparation.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Retrieves GitLab project information with statistics.

.DESCRIPTION
    Fetches detailed project metadata from GitLab including repository size,
    LFS status, and configuration. Provides helpful error messages for common issues.

.PARAMETER PathWithNamespace
    Full project path (e.g., "group/subgroup/project").

.OUTPUTS
    GitLab project object with statistics.

.EXAMPLE
    Get-GitLabProject "my-group/my-project"
#>
function Get-GitLabProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PathWithNamespace
    )
    
    $enc = [uri]::EscapeDataString($PathWithNamespace)  # encodes '/' to %2F as required
    $fullPath = "/api/v4/projects/$enc" + "?statistics=true"
    
    try {
        Invoke-GitLabRest $fullPath
    }
    catch {
        # Extract meaningful error message
        $errorMsg = if ($_.Exception.Message) {
            $_.Exception.Message
        }
        elseif ($_ -is [string]) {
            $_
        }
        else {
            $_.ToString()
        }
        
        Write-Host "[ERROR] Failed to fetch GitLab project '$PathWithNamespace'." -ForegroundColor Red
        Write-Host "        Error: $errorMsg" -ForegroundColor Red
        Write-Host "        Suggestions:" -ForegroundColor Yellow
        Write-Host "          - Verify the project path is correct (group/subgroup/project)." -ForegroundColor Yellow
        Write-Host "          - Ensure the GitLab token has 'api' scope and can access the project." -ForegroundColor Yellow
        Write-Host "          - If the project is private, confirm the token user is a member or has access." -ForegroundColor Yellow
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Tests GitLab authentication and lists accessible projects.

.DESCRIPTION
    Validates that the GitLab base URL and token can successfully authenticate
    and retrieve projects. Useful for troubleshooting connectivity issues.

.EXAMPLE
    Test-GitLabAuth
#>
function Test-GitLabAuth {
    [CmdletBinding()]
    param()
    
    try {
        $uri = "/api/v4/projects?membership=true&per_page=5"
        $res = Invoke-GitLabRest $uri
        
        Write-Host "[OK] GitLab auth successful. Returned $(($res | Measure-Object).Count) project(s)." -ForegroundColor Green
        $res | Select-Object -Property id, path_with_namespace, visibility | Format-Table -AutoSize
    }
    catch {
        Write-Host "[ERROR] GitLab authentication test failed." -ForegroundColor Red
        throw
    }
}

<#
.SYNOPSIS
    Downloads and prepares a GitLab project for migration.

.DESCRIPTION
    Creates project folder structure, downloads repository as mirror clone,
    and generates detailed preflight report with size, LFS status, and metadata.

.PARAMETER SrcPath
    GitLab project path (e.g., "group/project").

.EXAMPLE
    Initialize-GitLab "my-group/my-project"
#>
function Initialize-GitLab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [Alias('SrcPath')]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$CustomBaseDir,
        
        [Parameter()]
        [string]$CustomProjectName
    )
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $errorMsg = New-ActionableError -ErrorType 'GitNotFound' -Details @{}
        throw $errorMsg
    }
    
    $p = Get-GitLabProject $ProjectPath
    
    # Create project metadata report
    $report = [pscustomobject]@{
        project            = $p.path_with_namespace
        http_url_to_repo   = $p.http_url_to_repo
        default_branch     = $p.default_branch
        visibility         = $p.visibility
        lfs_enabled        = $p.lfs_enabled
        repo_size_MB       = [math]::Round(($p.statistics.repository_size / 1MB), 2)
        lfs_size_MB        = [math]::Round(($p.statistics.lfs_objects_size / 1MB), 2)
        open_issues        = $p.open_issues_count
        last_activity      = $p.last_activity_at
        preparation_time   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    
    # Determine folder structure
    $projectName = if ($CustomProjectName) { $CustomProjectName } else { $p.path }
    
    if (-not $CustomBaseDir) {
        throw "[Initialize-GitLab] CustomBaseDir is required. This function only supports v2.1.0 self-contained structure."
    }
    
    # v2.1.0 self-contained mode: CustomBaseDir is ADO container, CustomProjectName is GitLab subfolder
    # Structure: CustomBaseDir/{CustomProjectName}/reports/ and repository/
    # Logs are at ADO container level: CustomBaseDir/logs/
    $projectDir = Join-Path $CustomBaseDir $projectName
    $reportsDir = Join-Path $projectDir "reports"
    $logsDir = Join-Path $CustomBaseDir "logs"  # Container-level logs
    $repoDir = Join-Path $projectDir "repository"
    
    if (-not (Test-Path $projectDir)) {
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        Write-Host "[INFO] Created GitLab project directory: $projectDir"
    }
    
    # Create subdirectories for organization
    # In v2.1.0, only create reports/ in GitLab subfolder
    # (logs/ is already created at container level by Get-ProjectPaths)
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }
    
    # Save preflight report in project-specific reports folder
    $reportFile = Join-Path $reportsDir "preflight-report.json"
    $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
    Write-Host "[OK] Preflight report written: $reportFile"
    
    # Get GitLab token from Core.Rest module
    try {
        $gitLabToken = Get-GitLabToken
    }
    catch {
        # Token error already has actionable message from Core.Rest
        throw
    }
    
    # Download repository for migration preparation
    $gitUrl = $p.http_url_to_repo -replace '^https://', "https://oauth2:$gitLabToken@"
    
    if (Test-Path $repoDir) {
        Write-Host "[INFO] Repository directory exists, checking status..."
        
        # Check if it's a valid git repository
        $isValidRepo = $false
        Push-Location $repoDir
        try {
            $null = git rev-parse --git-dir 2>$null
            $isValidRepo = $?
        }
        catch {
            $isValidRepo = $false
        }
        Pop-Location
        
        if ($isValidRepo) {
            Write-Host "[INFO] Valid repository found, updating..."
            Push-Location $repoDir
            try {
                # Fetch latest changes
                git remote set-url origin $gitUrl 2>$null
                # Respect invalid certificate setting for on-prem GitLab
                $skipCert = $false
                try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
                if ($skipCert) {
                    git -c http.sslVerify=false fetch --all --prune
                }
                else {
                    git fetch --all --prune
                }
                $fetchSuccess = $?
                
                if ($fetchSuccess) {
                    Write-Host "[SUCCESS] Repository updated successfully (reused existing clone)" -ForegroundColor Green
                }
                else {
                    throw "git fetch failed"
                }
            }
            catch {
                Write-Host "[WARN] Failed to update existing repository: $_"
                Write-Host "[INFO] Will re-clone repository..."
                Pop-Location
                Remove-Item -Recurse -Force $repoDir
                $needsClone = $true
            }
            if (-not $needsClone) { Pop-Location }
        }
        else {
            Write-Host "[WARN] Directory exists but is not a valid git repository, removing..."
            Remove-Item -Recurse -Force $repoDir
        }
    }
    
    if (-not (Test-Path $repoDir)) {
        Write-Host "[INFO] Downloading repository (mirror clone)..."
        Write-Host "       Size: $($report.repo_size_MB) MB"
        if ($report.lfs_enabled -and $report.lfs_size_MB -gt 0) {
            Write-Host "       LFS data: $($report.lfs_size_MB) MB"
            if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
                Write-Host "[WARN] Git LFS not found but repository uses LFS. Install git-lfs for complete migration." -ForegroundColor Yellow
            }
        }
        
        try {
            # Respect invalid certificate setting for on-prem GitLab
            $skipCert = $false
            try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
            if ($skipCert) {
                git -c http.sslVerify=false clone --mirror $gitUrl $repoDir
            }
            else {
                git clone --mirror $gitUrl $repoDir
            }
            Write-Host "[OK] Repository downloaded to: $repoDir"
            
            # Update report with local repository info
            $report | Add-Member -NotePropertyName "local_repo_path" -NotePropertyValue $repoDir
            $report | Add-Member -NotePropertyName "download_time" -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
        }
        catch {
            Write-Host "[ERROR] Failed to download repository: $_" -ForegroundColor Red
            Write-Host "[INFO] Migration can still proceed but will require fresh download in Option 3"
        }
    }
    
    # Create preparation log
    $prepLogFile = Join-Path $logsDir "preparation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    @(
        "=== GitLab Project Preparation Log ==="
        "Timestamp: $(Get-Date)"
        "Project: $($p.path_with_namespace)"
        "GitLab URL: $($p.http_url_to_repo)"
        "Project Directory: $projectDir"
        "Repository Size: $($report.repo_size_MB) MB"
        "LFS Enabled: $($report.lfs_enabled)"
        "LFS Size: $($report.lfs_size_MB) MB"
        "Default Branch: $($report.default_branch)"
        "Visibility: $($report.visibility)"
        "Last Activity: $($report.last_activity)"
        ""
        "Files Created:"
        "- Report: $reportFile"
        if (Test-Path $repoDir) { "- Repository: $repoDir" }
        "- Log: $prepLogFile"
        ""
        "=== Preparation Completed Successfully ==="
    ) | Out-File -FilePath $prepLogFile -Encoding utf8
    
    # Validate Git access (quick check)
    Write-Host "[INFO] Validating Git access..."
    # Validate Git access; respect invalid certificate setting
    try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
    if ($skipCert) {
        git -c http.sslVerify=false ls-remote $gitUrl HEAD | Out-Null
    }
    else {
        git ls-remote $gitUrl HEAD | Out-Null
    }
    Write-Host "[OK] Git access validated."
    
    # Summary
    Write-Host ""
    Write-Host "=== PREPARATION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Project: $($p.path_with_namespace)"
    Write-Host "Project folder: $projectDir"
    Write-Host "Size: $($report.repo_size_MB) MB"
    if ($report.lfs_enabled) { Write-Host "LFS: $($report.lfs_size_MB) MB" }
    Write-Host "Default branch: $($report.default_branch)"
    Write-Host "Visibility: $($report.visibility)"
    Write-Host ""
    Write-Host "Generated files:"
    Write-Host "  Report: $reportFile"
    Write-Host "  Log: $prepLogFile"
    if (Test-Path $repoDir) { Write-Host "  Repository: $repoDir" }
    Write-Host "===========================" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Prepares multiple GitLab projects for bulk migration.

.DESCRIPTION
    Downloads and analyzes multiple GitLab projects, creating a consolidated
    template file for bulk migration and individual project preparations.

.PARAMETER ProjectPaths
    Array of GitLab project paths.

.PARAMETER DestProjectName
    Target Azure DevOps project name.

.EXAMPLE
    Invoke-BulkPrepareGitLab -ProjectPaths @("group1/proj1", "group2/proj2") -DestProjectName "MyDevOpsProject"
#>
function Invoke-BulkPrepareGitLab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ProjectPaths,
        
        [Parameter(Mandatory)]
        [string]$DestProjectName
    )
    
    if ($ProjectPaths.Count -eq 0) {
        throw "No projects specified for bulk preparation."
    }
    
    if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
        throw "Destination DevOps project name is required for bulk preparation."
    }
    
    Write-Host "=== BULK PREPARATION STARTING ===" -ForegroundColor Cyan
    Write-Host "Destination Project: $DestProjectName"
    Write-Host "Projects to prepare: $($ProjectPaths.Count)"
    Write-Host ""
    
    # Create self-contained bulk preparation folder structure
    $bulkPaths = Get-BulkProjectPaths -AdoProject $DestProjectName
    $bulkPrepDir = $bulkPaths.containerDir
    $configFile = $bulkPaths.configFile
    
    # Check if preparation already exists
    if (Test-Path $configFile) {
        Write-Host "⚠️  Existing preparation found for '$DestProjectName'" -ForegroundColor Yellow
        Write-Host "   Folder: $bulkPrepDir"
        $choice = Read-Host "Continue and update existing preparation? (y/N)"
        if ($choice -notmatch '^[Yy]') {
            Write-Host "Bulk preparation cancelled."
            return
        }
        Write-Host "Updating existing preparation..."
    }
    else {
        Write-Host "Creating new self-contained preparation for '$DestProjectName'..."
    }
    
    # Create bulk preparation log in logs folder
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $bulkLogFile = Join-Path $bulkPaths.logsDir "bulk-preparation-$timestamp.log"
    $startTime = Get-Date
    
    @(
        "=== GitLab Bulk Preparation Log ==="
        "Bulk preparation started: $startTime"
        "Destination DevOps Project: $DestProjectName"
        "Projects to prepare: $($ProjectPaths.Count)"
        ""
        "=== Project List ==="
    ) | Out-File -FilePath $bulkLogFile -Encoding utf8
    
    # Log all projects first
    foreach ($projectPath in $ProjectPaths) {
        "- $projectPath" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    }
    "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    $results = @()
    $projects = @()
    $successCount = 0
    $failureCount = 0
    
    # Process each project
    for ($i = 0; $i -lt $ProjectPaths.Count; $i++) {
        $projectPath = $ProjectPaths[$i]
        $projectNum = $i + 1
        $projectName = ($projectPath -split '/')[-1]
        
        Write-Host "[$projectNum/$($ProjectPaths.Count)] Preparing: $projectPath"
        "=== Project $projectNum/$($ProjectPaths.Count): $projectPath ===" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        "Start time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        
        try {
            # Check if project already prepared in self-contained structure
            $gitlabPaths = Get-BulkProjectPaths -AdoProject $DestProjectName -GitLabProject $projectName
            $projectDir = $gitlabPaths.gitlabDir
            $repoDir = $gitlabPaths.repositoryDir
            
            if (Test-Path $repoDir) {
                Write-Host "    Project already prepared, updating..."
                "Project already exists, updating: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            }
            else {
                Write-Host "    Downloading and analyzing project..."
                "Preparing new project in self-contained structure: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            }
            
            # Run preparation for this project using bulk-specific path
            Initialize-GitLab -ProjectPath $projectPath -CustomBaseDir $bulkPrepDir -CustomProjectName $projectName
            
            # Read the generated preflight report from bulk structure
            $preflightFile = Join-Path $projectDir "reports" "preflight-report.json"
            if (Test-Path $preflightFile) {
                $preflightData = Get-Content $preflightFile | ConvertFrom-Json
                
                # Add to bulk template
                $projects += [pscustomobject]@{
                    gitlab_path       = $projectPath
                    ado_repo_name     = $projectName
                    description       = "Migrated from $projectPath"
                    repo_size_MB      = $preflightData.repo_size_MB
                    lfs_enabled       = $preflightData.lfs_enabled
                    lfs_size_MB       = $preflightData.lfs_size_MB
                    default_branch    = $preflightData.default_branch
                    visibility        = $preflightData.visibility
                    preparation_status = "SUCCESS"
                }
                
                $result = [pscustomobject]@{
                    gitlab_project   = $projectPath
                    status           = "SUCCESS"
                    repo_size_MB     = $preflightData.repo_size_MB
                    lfs_size_MB      = $preflightData.lfs_size_MB
                    preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                $successCount++
                
                Write-Host "    ✅ SUCCESS: $projectPath ($($preflightData.repo_size_MB) MB)" -ForegroundColor Green
            }
            else {
                throw "Preflight report not found after preparation"
            }
            
            $results += $result
            "Status: SUCCESS" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        }
        catch {
            # Add failed project to template with error status
            $projects += [pscustomobject]@{
                gitlab_path        = $projectPath
                ado_repo_name      = $projectName
                description        = "FAILED: $($_.ToString())"
                preparation_status = "FAILED"
                error_message      = $_.ToString()
            }
            
            $result = [pscustomobject]@{
                gitlab_project   = $projectPath
                status           = "FAILED"
                error_message    = $_.ToString()
                preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
            $results += $result
            $failureCount++
            
            Write-Host "    ❌ FAILED: $projectPath" -ForegroundColor Red
            Write-Host "       Error: $_" -ForegroundColor Red
            "Status: FAILED" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "Error: $_" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        }
    }
    
    # Create bulk migration config (renamed from template for clarity)
    # Calculate totals safely (only for successful preparations)
    $successfulProjects = $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' -and $_.repo_size_MB }
    $totalSizeMB = if ($successfulProjects) {
        ($successfulProjects | Measure-Object -Property repo_size_MB -Sum).Sum
    } else { 0 }
    
    $successfulProjectsWithLfs = $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' -and $_.lfs_size_MB }
    $totalLfsMB = if ($successfulProjectsWithLfs) {
        ($successfulProjectsWithLfs | Measure-Object -Property lfs_size_MB -Sum).Sum
    } else { 0 }
    
    $config = [pscustomobject]@{
        description         = "Bulk migration configuration for '$DestProjectName' - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        destination_project = $DestProjectName
        migration_type      = "BULK"
        preparation_summary = [pscustomobject]@{
            total_projects          = $ProjectPaths.Count
            successful_preparations = $successCount
            failed_preparations     = $failureCount
            total_size_MB           = $totalSizeMB
            total_lfs_MB            = $totalLfsMB
            preparation_time        = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
        projects            = $projects
    }
    
    $config | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $configFile
    
    # Create summary report in reports folder
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $summaryFile = Join-Path $bulkPaths.reportsDir "preparation-summary.json"
    
    $summary = [pscustomobject]@{
        preparation_start       = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        preparation_end         = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
        duration_minutes        = [math]::Round($duration.TotalMinutes, 2)
        total_projects          = $ProjectPaths.Count
        successful_preparations = $successCount
        failed_preparations     = $failureCount
        success_rate            = [math]::Round(($successCount / $ProjectPaths.Count) * 100, 1)
        total_size_MB           = $totalSizeMB
        results                 = $results
    }
    
    $summary | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $summaryFile
    
    # Final log entries
    @(
        "=== BULK PREPARATION SUMMARY ==="
        "Bulk preparation completed: $endTime"
        "Total duration: $($duration.ToString('hh\:mm\:ss')) ($([math]::Round($duration.TotalMinutes, 2)) minutes)"
        "Total projects: $($ProjectPaths.Count)"
        "Successful: $successCount"
        "Failed: $failureCount"
        "Success rate: $([math]::Round(($successCount / $ProjectPaths.Count) * 100, 1))%"
        "Config file: $configFile"
        "Summary report: $summaryFile"
        "=== BULK PREPARATION COMPLETED ==="
    ) | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    # Display final results
    Write-Host ""
    Write-Host "=== BULK PREPARATION RESULTS ===" -ForegroundColor Cyan
    Write-Host "Destination Project: $DestProjectName"
    Write-Host "Container folder: $bulkPrepDir" -ForegroundColor Cyan
    Write-Host "Total projects: $($ProjectPaths.Count)"
    Write-Host "✅ Successful: $successCount" -ForegroundColor Green
    Write-Host "❌ Failed: $failureCount" -ForegroundColor Red
    Write-Host "Success rate: $([math]::Round(($successCount / $ProjectPaths.Count) * 100, 1))%"
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
    if ($summary.total_size_MB -gt 0) {
        Write-Host "Total repository size: $($summary.total_size_MB) MB"
    }
    Write-Host ""
    Write-Host "Self-contained structure:" -ForegroundColor Yellow
    Write-Host "  � Container: migrations/$DestProjectName/"
    Write-Host "     ├── 📋 bulk-migration-config.json"
    Write-Host "     ├── 📊 reports/preparation-summary.json"
    Write-Host "     ├── 📝 logs/bulk-preparation-*.log"
    foreach ($proj in $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' } | Select-Object -First 3) {
        Write-Host "     ├── 📂 $($proj.ado_repo_name)/repository/"
    }
    if ($successCount -gt 3) {
        Write-Host "     └── ... ($($successCount - 3) more)"
    }
    Write-Host ""
    
    if ($failureCount -gt 0) {
        Write-Host "⚠️  Some projects failed preparation. Review the log file for details." -ForegroundColor Yellow
        Write-Host "   You can fix the issues and re-run preparation to update the config." -ForegroundColor Yellow
    }
    
    Write-Host "Next step: Use Option 6 (Bulk Migration Execution) to migrate all repositories" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Extracts documentation files from prepared GitLab repositories into a centralized docs folder.

.DESCRIPTION
    Scans all prepared GitLab project repositories and copies documentation files
    (docx, pdf, xlsx, pptx) into a centralized docs folder at the Azure DevOps project level.
    Creates subfolders for each repository to maintain organization.

.PARAMETER AdoProject
    Azure DevOps project name (container folder).

.PARAMETER DocExtensions
    Array of file extensions to extract (default: docx, pdf, xlsx, pptx).

.OUTPUTS
    Hashtable with extraction statistics.

.EXAMPLE
    Export-GitLabDocumentation -AdoProject "MyProject"
#>
function Export-GitLabDocumentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [Parameter()]
        [string[]]$DocExtensions = @('docx', 'pdf', 'xlsx', 'pptx', 'doc', 'xls', 'ppt')
    )
    
    Write-Host "[INFO] Starting documentation extraction for project: $AdoProject" -ForegroundColor Cyan
    
    # Get bulk project paths to find container directory
    $bulkPaths = Get-BulkProjectPaths -AdoProject $AdoProject
    $containerDir = $bulkPaths.containerDir
    
    if (-not (Test-Path $containerDir)) {
        Write-Host "[ERROR] Container directory not found: $containerDir" -ForegroundColor Red
        Write-Host "        Make sure the project has been prepared first." -ForegroundColor Yellow
        return $null
    }
    
    # Create docs folder at project level
    $docsDir = Join-Path $containerDir "docs"
    if (-not (Test-Path $docsDir)) {
        New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
        Write-Host "[INFO] Created documentation folder: $docsDir" -ForegroundColor Green
    }
    
    # Statistics
    $stats = @{
        total_files = 0
        total_size_MB = 0
        repositories_processed = 0
        files_by_type = @{}
    }
    
    # Find all repository directories
    $repoDirs = @(Get-ChildItem -Path $containerDir -Directory | Where-Object {
        $repoPath = Join-Path $_.FullName "repository"
        Test-Path $repoPath
    })
    
    if ($repoDirs.Count -eq 0) {
        Write-Host "[WARN] No repository directories found in: $containerDir" -ForegroundColor Yellow
        return $stats
    }
    
    Write-Host "[INFO] Found $($repoDirs.Count) repository directories to scan" -ForegroundColor Cyan
    
    foreach ($repoDir in $repoDirs) {
        $repoName = $repoDir.Name
        $repositoryPath = Join-Path $repoDir.FullName "repository"
        
        Write-Host "[INFO] Scanning repository: $repoName" -ForegroundColor Gray
        
        # Create subfolder for this repository in docs
        $repoDocsDir = Join-Path $docsDir $repoName
        if (-not (Test-Path $repoDocsDir)) {
            New-Item -ItemType Directory -Path $repoDocsDir -Force | Out-Null
        }
        
        # Find documentation files
        $docFiles = @(Get-ChildItem -Path $repositoryPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $extension = $_.Extension.TrimStart('.').ToLower()
            $DocExtensions -contains $extension
        })
        
        if ($docFiles.Count -gt 0) {
            Write-Host "  [INFO] Found $($docFiles.Count) documentation files" -ForegroundColor Cyan
            
            foreach ($file in $docFiles) {
                try {
                    # Preserve relative path structure
                    $relativePath = $file.FullName.Substring($repositoryPath.Length).TrimStart('\', '/')
                    $targetPath = Join-Path $repoDocsDir $relativePath
                    $targetDir = Split-Path -Parent $targetPath
                    
                    # Create target directory if needed
                    if (-not (Test-Path $targetDir)) {
                        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    }
                    
                    # Copy file
                    Copy-Item -Path $file.FullName -Destination $targetPath -Force
                    
                    # Update statistics
                    $stats.total_files++
                    $stats.total_size_MB += [math]::Round(($file.Length / 1MB), 2)
                    
                    $extension = $file.Extension.TrimStart('.').ToLower()
                    if (-not $stats.files_by_type.ContainsKey($extension)) {
                        $stats.files_by_type[$extension] = 0
                    }
                    $stats.files_by_type[$extension]++
                    
                    Write-Host "    ✓ $relativePath" -ForegroundColor Green
                }
                catch {
                    Write-Warning "    ✗ Failed to copy $($file.Name): $_"
                }
            }
        }
        else {
            Write-Host "  [INFO] No documentation files found" -ForegroundColor Gray
        }
        
        $stats.repositories_processed++
    }
    
    # Display summary
    Write-Host ""
    Write-Host "=== DOCUMENTATION EXTRACTION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Repositories scanned: $($stats.repositories_processed)"
    Write-Host "Total files extracted: $($stats.total_files)"
    Write-Host "Total size: $($stats.total_size_MB) MB"
    
    if ($stats.files_by_type.Count -gt 0) {
        Write-Host ""
        Write-Host "Files by type:" -ForegroundColor Cyan
        foreach ($ext in $stats.files_by_type.Keys | Sort-Object) {
            Write-Host "  .$ext : $($stats.files_by_type[$ext]) files" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Documentation folder: $docsDir" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Cyan
    
    return $stats
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-GitLabProject',
    'Test-GitLabAuth',
    'Initialize-GitLab',
    'Invoke-BulkPrepareGitLab',
    'Export-GitLabDocumentation'
)
