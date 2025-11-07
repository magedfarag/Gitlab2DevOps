<#
.SYNOPSIS
    Migration orchestration module - delegates to specialized modules.

.DESCRIPTION
    Main orchestration module that coordinates between Menu, Initialization, 
    and Workflows modules. This is the entry point for the migration system.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.1.0 - Refactored to modular architecture
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import core dependencies 
Import-Module (Join-Path $PSScriptRoot "Core.Rest.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "GitLab.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "AzureDevOps.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "ConfigLoader.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "DryRunPreview.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "ProgressTracking.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "Telemetry.psm1") -Force -Global

# Import modular components (v2.1.0+)
Import-Module (Join-Path $PSScriptRoot "Templates.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "Menu.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "Initialization.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "Workflows.psm1") -Force -Global

# Module-level variables for compatibility
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabToken = $null
$script:BuildDefinitionId = 0
$script:SonarStatusContext = ""

# Module-level constants
$script:DEFAULT_SPRINT_COUNT = 6
$script:DEFAULT_SPRINT_DURATION_DAYS = 14
$script:DEFAULT_AREA_PATHS = @('Frontend', 'Backend', 'Infrastructure', 'Documentation')

<#
.SYNOPSIS
    Scans for prepared GitLab projects.

.DESCRIPTION
    Looks for single project preparations and bulk preparations in the migrations folder.
    Supports both v2.1.0+ self-contained structure and legacy flat structure.

.OUTPUTS
    Array of prepared project information.
#>
function Get-PreparedProjects {
    [CmdletBinding()]
    param()
    
    $migrationsDir = Get-MigrationsDirectory
    $prepared = @()
    
    if (-not (Test-Path $migrationsDir)) {
        Write-Verbose "[Get-PreparedProjects] Migrations directory not found: $migrationsDir"
        return $prepared
    }
    
    try {
        # Find v2.1.0+ self-contained projects (migration-config.json in subdirectories)
        $newConfigFiles = Get-ChildItem -Path $migrationsDir -Recurse -Filter "migration-config.json" -File | Where-Object {
            $_.Directory.Parent.Name -eq "migrations"  # Direct subdirectory of migrations/
        }
        
        foreach ($configFile in $newConfigFiles) {
            try {
                $config = Get-Content -Path $configFile.FullName -Raw | ConvertFrom-Json
                
                $prepared += [PSCustomObject]@{
                    ProjectName = $config.ado_project
                    GitLabProject = $config.gitlab_project
                    RepoName = $config.gitlab_repo_name
                    Status = $config.status
                    CreatedDate = $config.created_date
                    LastUpdated = $config.last_updated
                    Type = $config.migration_type
                    Structure = "v2.1.0+"
                    ConfigPath = $configFile.FullName
                }
            }
            catch {
                Write-Verbose "[Get-PreparedProjects] Failed to parse config: $($configFile.FullName)"
            }
        }
        
        # Find bulk migration configs
        $bulkConfigFiles = Get-ChildItem -Path $migrationsDir -Recurse -Filter "bulk-migration-config.json" -File
        
        foreach ($bulkConfigFile in $bulkConfigFiles) {
            try {
                $bulkConfig = Get-Content -Path $bulkConfigFile.FullName -Raw | ConvertFrom-Json
                
                $prepared += [PSCustomObject]@{
                    ProjectName = $bulkConfig.destination_project
                    GitLabProject = "BULK: $($bulkConfig.projects.Count) projects"
                    RepoName = "Multiple repositories"
                    Status = "BULK_PREPARED"
                    CreatedDate = $bulkConfig.created_date
                    LastUpdated = $bulkConfig.last_updated
                    Type = "BULK"
                    Structure = "v2.1.0+"
                    ConfigPath = $bulkConfigFile.FullName
                }
            }
            catch {
                Write-Verbose "[Get-PreparedProjects] Failed to parse bulk config: $($bulkConfigFile.FullName)"
            }
        }
        
        # Find legacy flat structure projects (preflight-report.json in project directories)
        $legacyReports = Get-ChildItem -Path $migrationsDir -Recurse -Filter "preflight-report.json" -File | Where-Object {
            $_.Directory.Parent.Name -eq "migrations" -and $_.Directory.Name -ne "reports"
        }
        
        foreach ($reportFile in $legacyReports) {
            try {
                $report = Get-Content -Path $reportFile.FullName -Raw | ConvertFrom-Json
                $projectName = $reportFile.Directory.Name
                
                # Skip if we already have a v2.1.0+ entry for this project
                if ($prepared | Where-Object { $_.RepoName -eq $projectName -and $_.Structure -eq "v2.1.0+" }) {
                    continue
                }
                
                $prepared += [PSCustomObject]@{
                    ProjectName = $projectName
                    GitLabProject = $report.gitlab_project
                    RepoName = $report.repo_name
                    Status = "PREPARED"
                    CreatedDate = $report.timestamp
                    LastUpdated = $report.timestamp
                    Type = "SINGLE"
                    Structure = "Legacy"
                    ConfigPath = $reportFile.FullName
                }
            }
            catch {
                Write-Verbose "[Get-PreparedProjects] Failed to parse legacy report: $($reportFile.FullName)"
            }
        }
        
        Write-Verbose "[Get-PreparedProjects] Found $($prepared.Count) prepared projects"
        return $prepared | Sort-Object LastUpdated -Descending
    }
    catch {
        Write-Warning "[Get-PreparedProjects] Error scanning migrations directory: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Generates a pre-migration validation report.

.DESCRIPTION
    Validates GitLab project exists, checks Azure DevOps project/repo status,
    and identifies blocking issues before migration. Delegates to workflow modules.

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

# Delegate main functions to specialized modules
# These are re-exported for backward compatibility

# From Menu.psm1
New-Alias -Name Show-MigrationMenu -Value Show-MigrationMenu -Force
New-Alias -Name Invoke-TeamPackMenu -Value Invoke-TeamPackMenu -Force

# From Initialization.psm1  
New-Alias -Name Initialize-AdoProject -Value Initialize-AdoProject -Force
New-Alias -Name Initialize-BusinessInit -Value Initialize-BusinessInit -Force
New-Alias -Name Initialize-DevInit -Value Initialize-DevInit -Force
New-Alias -Name Initialize-SecurityInit -Value Initialize-SecurityInit -Force
New-Alias -Name Initialize-ManagementInit -Value Initialize-ManagementInit -Force

# From Workflows.psm1
New-Alias -Name Invoke-SingleMigration -Value Invoke-SingleMigration -Force
New-Alias -Name Invoke-BulkPreparationWorkflow -Value Invoke-BulkPreparationWorkflow -Force
New-Alias -Name Invoke-BulkMigrationWorkflow -Value Invoke-BulkMigrationWorkflow -Force

Export-ModuleMember -Function @(
    'Get-PreparedProjects',
    'New-MigrationPreReport'
) -Alias @(
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu',
    'Initialize-AdoProject',
    'Initialize-BusinessInit', 
    'Initialize-DevInit',
    'Initialize-SecurityInit',
    'Initialize-ManagementInit',
    'Invoke-SingleMigration',
    'Invoke-BulkPreparationWorkflow',
    'Invoke-BulkMigrationWorkflow'
)