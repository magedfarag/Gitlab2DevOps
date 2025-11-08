<#
.SYNOPSIS
    Single project migration workflows and pre-migration validation.

.DESCRIPTION
    This module handles single GitLab project to Azure DevOps migrations,
    including pre-migration validation reports and the complete migration process.

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
    Generates a pre-migration validation report.

.DESCRIPTION
    Validates GitLab project exists, checks Azure DevOps project/repo status,
    and identifies blocking issues before migration.

.PARAMETER GitLabPath
    GitLab project path.

.PARAMETER AdoProject
    Azure DevOps project name.

.PARAMETER AdoRepoName
    Azure DevOps repository name.

.PARAMETER OutputPath
    Optional output path for report.

.PARAMETER AllowSync
    Allow repository synchronization.

.OUTPUTS
    Pre-migration report object.

.EXAMPLE
    New-MigrationPreReport "group/project" "MyProject" "my-repo"
#>
function New-MigrationPreReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GitLabPath,
        
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [Parameter(Mandatory)]
        [ValidateScript({
            Test-AdoRepositoryName $_ -ThrowOnError
            $true
        })]
        [string]$AdoRepoName,
        
        [string]$OutputPath = (Join-Path (Get-Location) "migration-precheck-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"),
        
        [switch]$AllowSync
    )
    
    Write-Host "[INFO] Generating pre-migration report..." -ForegroundColor Cyan
    
    # 1. GitLab project facts
    $gl = Get-GitLabProject $GitLabPath
    
    # 2. Azure DevOps project existence
    $adoProjects = Invoke-AdoRest GET "/_apis/projects?`$top=5000"
    $adoProj = $adoProjects.value | Where-Object { $_.name -eq $AdoProject }
    
    # 3. Repo name collision
    $repoExists = $false
    if ($adoProj) {
        $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($AdoProject))/_apis/git/repositories"
        $repoExists = $repos.value | Where-Object { $_.name -eq $AdoRepoName }
    }
    
    $report = [pscustomobject]@{
        timestamp              = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        gitlab_path            = $GitLabPath
        gitlab_size_mb         = [math]::Round(($gl.statistics.repository_size / 1MB), 2)
        gitlab_lfs_enabled     = $gl.lfs_enabled
        gitlab_visibility      = $gl.visibility
        gitlab_default_branch  = $gl.default_branch
        ado_project            = $AdoProject
        ado_project_exists     = [bool]$adoProj
        ado_repo_name          = $AdoRepoName
        ado_repo_exists        = [bool]$repoExists
        sync_mode              = $AllowSync
        ready_to_migrate       = if ($AllowSync) { [bool]$adoProj } else { ($adoProj -and -not $repoExists) }
        blocking_issues        = @()
    }
    
    # Add blocking issues
    if (-not $adoProj) {
        $report.blocking_issues += "Azure DevOps project '$AdoProject' does not exist"
    }
    if ($repoExists -and -not $AllowSync) {
        $report.blocking_issues += "Repository '$AdoRepoName' already exists in project '$AdoProject'. Use -AllowSync to update existing repository."
    }
    elseif ($repoExists -and $AllowSync) {
        Write-Host "[INFO] Sync mode enabled: Repository '$AdoRepoName' will be updated with latest changes from GitLab" -ForegroundColor Yellow
    }
    
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "[INFO] Pre-migration report written to $OutputPath"
    
    # Display summary
    Write-Host "[INFO] Pre-migration Summary:"
    Write-Host "       GitLab: $GitLabPath ($($report.gitlab_size_mb) MB)"
    Write-Host "       Azure DevOps: $AdoProject -> $AdoRepoName"
    Write-Host "       Ready to migrate: $($report.ready_to_migrate)"
    
    if ($report.blocking_issues.Count -gt 0) {
        Write-Host "[ERROR] Blocking issues found:" -ForegroundColor Red
        foreach ($issue in $report.blocking_issues) {
            Write-Host "        - $issue" -ForegroundColor Red
        }
        throw "Precheck failed – resolve blocking issues before proceeding with migration."
    }
    
    return $report
}

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
    
    # Get v2.1.0 self-contained structure paths
    $migrationsDir = Get-MigrationsDirectory
    $configFile = Join-Path $migrationsDir "$DestProject\migration-config.json"
    
    if (-not (Test-Path $configFile)) {
        Write-Host "[ERROR] Project not prepared. Run Option 1 (Prepare GitLab Project) first." -ForegroundColor Red
        Write-Host "        Expected config file: $configFile" -ForegroundColor Gray
        return
    }
    
    Write-Host "[INFO] Using v2.1.0 self-contained structure" -ForegroundColor Cyan
    $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $repoName
    $reportsDir = $paths.reportsDir
    $logsDir = $paths.logsDir
    $repoDir = $paths.repositoryDir
    
    # Look for preflight report in GitLab project subfolder
    $preflightFile = Join-Path $paths.gitlabDir "reports\preflight-report.json"
    
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
        if ($preflightData.lfs_enabled -and $preflightData.lfs_size_MB -gt 0) {
            if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
                if ($Force) {
                    Write-Warning "Git LFS required but not found. Repository has $($preflightData.lfs_size_MB) MB of LFS data. Proceeding due to -Force..."
                }
                else {
                    $errorMsg = New-ActionableError -ErrorType 'GitLFSRequired' -Details @{ LFSSizeMB = $preflightData.lfs_size_MB }
                    throw $errorMsg
                }
            }
            else {
                Write-Host "[INFO] Git LFS detected: $($preflightData.lfs_size_MB) MB"
            }
        }
        
        # Use cached data
        $gl = [pscustomobject]@{
            path                = $preflightData.project.Split('/')[-1]
            http_url_to_repo    = $preflightData.http_url_to_repo
            path_with_namespace = $preflightData.project
        }
        
        # Check for local repository
        if (Test-Path $repoDir) {
            Write-Host "[INFO] Found local repository from preparation step"
            $useLocalRepo = $true
        }
    }
    else {
        # CRITICAL: Never connect to GitLab during migration execution
        # All GitLab data must be gathered during preparation (Option 1 or 4)
        Write-Host "[ERROR] No preflight report found" -ForegroundColor Red
        Write-Host "        Run preparation first:" -ForegroundColor Red
        Write-Host "          - Option 1 (Single Project Preparation)" -ForegroundColor Yellow
        Write-Host "          - Option 4 (Bulk Preparation)" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Red
        Write-Host "        Migration cannot proceed without preparation data." -ForegroundColor Red
        Write-Host "        This ensures all GitLab connections happen during preparation," -ForegroundColor Gray
        Write-Host "        allowing execution to work in air-gapped environments." -ForegroundColor Gray
        throw "Pre-migration validation required. Run preparation first (Option 1 or 4)."
    }
    
    # Generate pre-migration report for validation
    $preReport = New-MigrationPreReport -GitLabPath $SrcPath -AdoProject $DestProject -AdoRepoName $repoName -AllowSync:$AllowSync -OutputPath (Join-Path $reportsDir "pre-migration-report.json")
    
    # Ensure Azure DevOps project exists
    $proj = Measure-Adoproject $DestProject
    $projId = $proj.id
    $repoName = $gl.path
    
    # Create migration log
    $logFile = New-LogFilePath $logsDir "migration"
    $startTime = Get-Date
    $stepTiming = @{}

    Write-MigrationLog $logFile @(
        "=== Azure DevOps Migration Log ==="
        "Migration started: $startTime"
        "Source GitLab: $($gl.path_with_namespace)"
        "Source URL: $($gl.http_url_to_repo)"
        "Destination ADO Project: $DestProject"
        "Destination Repository: $repoName"
        "Using local repo: $useLocalRepo"
    )
    
    # Ensure ADO repo exists
    $stepStart = Get-Date
    $repo = New-AdoRepository $DestProject $projId $repoName -AllowExisting:$AllowSync -Replace:$Replace
    $stepTiming['Repository Creation'] = ((Get-Date) - $stepStart).TotalSeconds
    
    $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id
    $isSync = $AllowSync -and $preReport.ado_repo_exists
    if ($isSync) {
        Write-Host "[INFO] Sync mode: Updating existing repository" -ForegroundColor Yellow
        Write-MigrationLog $logFile "=== SYNC MODE: Updating existing repository ==="
    }
    
    try {
        # Get Core.Rest configuration for git operations
        $coreRestConfig = Get-CoreRestConfig
        if (-not $coreRestConfig) {
            throw "Core REST configuration not found. Please initialize Core.Rest module first."
        }
        
        # Determine source repository
        $stepStart = Get-Date
        if ($useLocalRepo) {
            Write-Host "[INFO] Using pre-downloaded repository"
            $sourceRepo = $repoDir
        }
        else {
            Write-Host "[INFO] Downloading repository..."
            $gitUrl = $gl.http_url_to_repo -replace '^https://', "https://oauth2:$($coreRestConfig.GitLabToken)@"
            $sourceRepo = Join-Path $env:TEMP ("migration-" + [Guid]::NewGuid() + ".git")
            # Respect invalid certificate for GitLab
            try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
            if ($skipCert) {
                git -c http.sslVerify=false clone --mirror $gitUrl $sourceRepo
            }
            else {
                git clone --mirror $gitUrl $sourceRepo
            }
        }
        $stepTiming['Repository Download'] = ((Get-Date) - $stepStart).TotalSeconds
        
        # Configure Azure DevOps remote
        $stepStart = Get-Date
        $adoRemote = "$($coreRestConfig.CollectionUrl)/$([uri]::EscapeDataString($DestProject))/_git/$([uri]::EscapeDataString($repoName))"
        Push-Location $sourceRepo
        
        git remote remove ado 2>$null | Out-Null
        git remote add ado $adoRemote
        git config http.$adoRemote.extraheader "AUTHORIZATION: basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($coreRestConfig.AdoPat)")))"
        
        # Push to Azure DevOps (respect invalid certificate for on-prem ADO Server)
        Write-Host "[INFO] Pushing to Azure DevOps..."
        try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
        if ($skipCert) {
            git -c http.sslVerify=false push ado --mirror
        }
        else {
            git push ado --mirror
        }
        $stepTiming['Git Push'] = ((Get-Date) - $stepStart).TotalSeconds
        
        # Clean up credentials
        git config --unset-all "http.$adoRemote.extraheader" 2>$null | Out-Null
        Clear-Gitcredentials -RemoteName "ado"
        
        Pop-Location
        
        # Clean up temp repository
        if (-not $useLocalRepo -and (Test-Path $sourceRepo)) {
            Remove-Item -Recurse -Force $sourceRepo -ErrorAction SilentlyContinue
        }
        
        # After successful push, apply branch policies if this is the first migration (not sync)
        if (-not $isSync) {
            Write-Host "[INFO] Applying branch policies to migrated repository..." -ForegroundColor Cyan
            $stepStart = Get-Date
            try {
                # Get the default branch now that code has been pushed
                Start-Sleep -Seconds 2  # Wait for Azure DevOps to recognize branches
                $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id
                
                if ($defaultRef) {
                    Write-Host "[INFO] Applying policies to branch: $defaultRef" -ForegroundColor Cyan
                    New-Adobranchpolicies `
                        -Project $DestProject `
                        -RepoId $repo.id `
                        -Ref $defaultRef `
                        -Min 2

                    Write-Host "[SUCCESS] Branch policies applied successfully" -ForegroundColor Green
                }
                else {
                    Write-Warning "Could not determine default branch. Branch policies not applied."
                }
                $stepTiming['Branch Policies'] = ((Get-Date) - $stepStart).TotalSeconds
            }
            catch {
                Write-Warning "Failed to apply branch policies: $_"
                Write-Host "[INFO] You can manually configure branch policies in Azure DevOps" -ForegroundColor Yellow
                $stepTiming['Branch Policies'] = ((Get-Date) - $stepStart).TotalSeconds
            }
        }
        
        $endTime = Get-Date
        
        # Create migration summary
        $summary = New-MigrationSummary `
            -GitLabPath $SrcPath `
            -AdoProject $DestProject `
            -AdoRepo $repoName `
            -Status "SUCCESS" `
            -StartTime $startTime `
            -EndTime $endTime `
            -AdditionalData @{
            migration_type = if ($isSync) { "SYNC" } else { "INITIAL" }
            repository_size_mb = $preReport.gitlab_size_mb
        }
        
        # Write summary
        $summaryFile = Join-Path $reportsDir "migration-summary.json"
        Write-MigrationReport $summaryFile $summary
        
        # Generate HTML report
        try {
            $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $reportsDir -Parent)
            if ($htmlReport) {
                Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Warning "Failed to generate HTML report: $_"
        }
        
        # Regenerate overview dashboard
        try {
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Warning "Failed to update overview dashboard: $_"
        }
        
        Write-MigrationLog $logFile @(
            "=== Migration Completed Successfully ==="
            "End time: $endTime"
            "Duration: $($summary.duration_minutes) minutes"
        )
        
        Write-Host "[OK] Migration completed successfully!" -ForegroundColor Green
        Write-Host "      Total duration: $($summary.duration_minutes) minutes" -ForegroundColor White
        
        # Show timing breakdown
        if ($stepTiming.Count -gt 0) {
            Write-Host "      Step breakdown:" -ForegroundColor Gray
            $sortedSteps = $stepTiming.GetEnumerator() | Sort-Object Value -Descending
            foreach ($step in $sortedSteps) {
                Write-Host ("        • {0}: {1:F1}s" -f $step.Key, $step.Value) -ForegroundColor Gray
            }
        }
        
        Write-Host "      Summary: $summaryFile"
    }
    catch {
        $endTime = Get-Date
        Write-Host "[ERROR] Migration failed: $_" -ForegroundColor Red
        
        # Create error summary
        $errorSummary = New-MigrationSummary `
            -GitLabPath $SrcPath `
            -AdoProject $DestProject `
            -AdoRepo $repoName `
            -Status "FAILED" `
            -StartTime $startTime `
            -EndTime $endTime `
            -AdditionalData @{
            error_message = $_.ToString()
        }
        
        $errorFile = Join-Path $reportsDir "migration-error.json"
        Write-MigrationReport $errorFile $errorSummary
        
        # Generate HTML report for failed migration
        try {
            $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $reportsDir -Parent)
            if ($htmlReport) {
                Write-Host "[INFO] HTML error report generated: $htmlReport" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Warning "Failed to generate HTML error report: $_"
        }
        
        # Regenerate overview dashboard
        try {
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Warning "Failed to update overview dashboard: $_"
        }
        
        Write-MigrationLog $logFile "=== Migration Failed ===" -Level ERROR
        Write-MigrationLog $logFile $_.ToString() -Level ERROR
        
        throw
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'New-MigrationPreReport',
    'Invoke-SingleMigration'
)

