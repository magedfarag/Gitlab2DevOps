<#
.SYNOPSIS
    Core migration utilities and shared functions.

.DESCRIPTION
    This module contains shared utilities used across migration workflows,
    including project detection, configuration management, and helper functions.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, ConfigLoader modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import required modules
Import-Module -WarningAction SilentlyContinue (Join-Path $PSScriptRoot "..\..\core\ConfigLoader.psm1") -Force -Global

# Module-level constants for configuration defaults
$script:DEFAULT_SPRINT_COUNT = 6
$script:DEFAULT_SPRINT_DURATION_DAYS = 14
$script:DEFAULT_AREA_PATHS = @('Frontend', 'Backend', 'Infrastructure', 'Documentation')
$script:REPO_INIT_MAX_RETRIES = 5
$script:REPO_INIT_RETRY_DELAYS = @(2, 4, 8, 16, 32)  # Exponential backoff in seconds
$script:BRANCH_POLICY_WAIT_SECONDS = 2

<#
.SYNOPSIS
    Scans for prepared GitLab projects.

.DESCRIPTION
    Looks for single project preparations and bulk preparations in the migrations folder.

.OUTPUTS
    Array of prepared project information.
#>
function Get-PreparedProjects {
    [CmdletBinding()]
    param()
    
    $migrationsDir = Join-Path (Get-Location) "migrations"
    $prepared = @()
    
    if (-not (Test-Path $migrationsDir)) {
        return $prepared
    }
    
    # First, collect all project names that are part of bulk preparations
    $bulkProjectNames = @{}
    Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $configFile = Join-Path $_.FullName "bulk-migration-config.json"
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile | ConvertFrom-Json
                foreach ($proj in $config.projects) {
                    $bulkProjectNames[$proj.ado_repo_name] = $true
                }
            }
            catch {
                Write-Verbose "Failed to read config: $configFile"
            }
        }
    }
    
    # Scan for single project preparations
    # New structure (v2.1.0+): Look for migration-config.json with migration_type="SINGLE"
    # Legacy structure: Look for reports/preflight-report.json (deprecated)
    Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | Where-Object {
        $bulkConfigFile = Join-Path $_.FullName "bulk-migration-config.json"
        $singleConfigFile = Join-Path $_.FullName "migration-config.json"
        $legacyReportFile = Join-Path $_.FullName "reports\preflight-report.json"
        
        # Not a bulk preparation AND (has single config OR has legacy report)
        -not (Test-Path $bulkConfigFile) -and 
        ((Test-Path $singleConfigFile) -or (Test-Path $legacyReportFile)) -and
        -not $bulkProjectNames.ContainsKey($_.Name)
    } | ForEach-Object {
        try {
            $singleConfigFile = Join-Path $_.FullName "migration-config.json"
            
            if (Test-Path $singleConfigFile) {
                # New self-contained structure (v2.1.0+)
                $config = Get-Content $singleConfigFile | ConvertFrom-Json
                
                # Find the GitLab project subfolder
                $gitlabDirs = Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -ne "reports" -and $_.Name -ne "logs" }
                
                if ($gitlabDirs) {
                    $gitlabDir = $gitlabDirs[0]
                    $reportFile = Join-Path $gitlabDir.FullName "reports\preflight-report.json"
                    
                    if (Test-Path $reportFile) {
                        $report = Get-Content $reportFile | ConvertFrom-Json
                        
                        # Check if project exists in Azure DevOps
                        $projectExists = Test-AdoProjectExists -ProjectName $config.ado_project
                        $repoMigrated = $false
                        if ($projectExists) {
                            $repos = Get-AdoProjectRepositories -ProjectName $config.ado_project
                            $repoMigrated = $repos | Where-Object { $_.name -eq $config.gitlab_repo_name }
                        }
                        
                        $prepared += [pscustomobject]@{
                            Type = "Single"
                            ProjectName = $config.ado_project
                            GitLabPath = $config.gitlab_project
                            GitLabRepoName = $config.gitlab_repo_name
                            RepoSizeMB = $report.repo_size_MB
                            PreparationTime = $config.created_date
                            Folder = $_.FullName
                            ConfigFile = $singleConfigFile
                            ProjectExists = $projectExists
                            RepoMigrated = $null -ne $repoMigrated
                            Structure = "v2.1.0"
                        }
                    }
                }
            }
            else {
                # Legacy flat structure (deprecated - for backward compat display only)
                $reportFile = Join-Path $_.FullName "reports\preflight-report.json"
                if (Test-Path $reportFile) {
                    $report = Get-Content $reportFile | ConvertFrom-Json
                    
                    $projectExists = Test-AdoProjectExists -ProjectName $_.Name
                    $repoMigrated = $false
                    if ($projectExists) {
                        $repos = Get-AdoProjectRepositories -ProjectName $_.Name
                        $repoMigrated = $repos | Where-Object { $_.name -eq $_.Name }
                    }
                    
                    $prepared += [pscustomobject]@{
                        Type = "Single"
                        ProjectName = $_.Name
                        GitLabPath = $report.project
                        RepoSizeMB = $report.repo_size_MB
                        PreparationTime = $report.preparation_time
                        Folder = $_.FullName
                        ProjectExists = $projectExists
                        RepoMigrated = $null -ne $repoMigrated
                        Structure = "legacy"
                    }
                }
            }
        }
        catch {
            Write-Verbose "Failed to read preparation data from: $($_.FullName)"
        }
    }
    
    # Scan for bulk preparations (now self-contained with config file in root)
    Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $configFile = Join-Path $_.FullName "bulk-migration-config.json"
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile | ConvertFrom-Json
                $successfulCount = @($config.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
                
                # Check if project exists in Azure DevOps
                $projectExists = Test-AdoProjectExists -ProjectName $config.destination_project
                $migratedCount = 0
                if ($projectExists) {
                    $repos = Get-AdoProjectRepositories -ProjectName $config.destination_project
                    foreach ($proj in $config.projects) {
                        if ($repos | Where-Object { $_.name -eq $proj.ado_repo_name }) {
                            $migratedCount++
                        }
                    }
                }
                
                $prepared += [pscustomobject]@{
                    Type = "Bulk"
                    ProjectName = $config.destination_project
                    ProjectCount = $config.preparation_summary.total_projects
                    SuccessfulCount = $successfulCount
                    TotalSizeMB = $config.preparation_summary.total_size_MB
                    PreparationTime = $config.preparation_summary.preparation_time
                    Folder = $_.FullName
                    ConfigFile = $configFile
                    ProjectExists = $projectExists
                    MigratedCount = $migratedCount
                }
            }
            catch {
                Write-Verbose "Failed to read config: $configFile"
            }
        }
    }
    
    return $prepared
}

<#
.SYNOPSIS
    Loads wiki template content with fallback support.

.DESCRIPTION
    Attempts to load wiki templates from custom directory first,
    then default directory, then embedded fallback templates.

.PARAMETER TemplateName
    Name of the template to load.

.PARAMETER CustomDirectory
    Custom template directory path.

.PARAMETER Replacements
    Hashtable of replacement tokens and values.

.OUTPUTS
    Template content as string.
#>
function Get-WikiTemplateContent {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,
        
        [string]$CustomDirectory = $null,
        
        [hashtable]$Replacements = @{}
    )
    
    # Embedded fallback templates
    $embeddedTemplates = @{
        'welcome-wiki' = @"
# Welcome to {{PROJECT_NAME}}

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
        'TagGuidelines' = @"
# Tag Guidelines

## Standard Tags

Use these tags to categorize work items:

- **Priority**: P0, P1, P2, P3
- **Status**: InProgress, Blocked, Review
- **Type**: Feature, Bug, TechDebt, Refactor

## Best Practices

- Use consistent tag naming
- Review tags during sprint planning
- Update tags as work progresses
"@
        'ComponentTags' = @"
# Component Tags

## Components

- Frontend
- Backend
- Database
- Infrastructure
- Documentation
- Testing

Tag work items by component for better tracking.
"@
    }
    
    $content = $null
    
    # Try custom directory first
    if ($CustomDirectory) {
        $customPath = Join-Path $CustomDirectory "$TemplateName.md"
        if (Test-Path $customPath) {
            try {
                $content = Get-Content -Path $customPath -Raw -Encoding UTF8
                Write-Verbose "[Get-WikiTemplateContent] Loaded from custom directory: $customPath"
            }
            catch {
                Write-Warning "Failed to load custom template '$customPath': $_"
            }
        }
        else {
            Write-Verbose "[Get-WikiTemplateContent] Custom template not found: $customPath"
        }
    }
    
    # Try default templates directory
    if (-not $content) {
        $defaultPath = Join-Path $PSScriptRoot "..\..\templates\$TemplateName.md"
        if (Test-Path $defaultPath) {
            try {
                $content = Get-Content -Path $defaultPath -Raw -Encoding UTF8
                Write-Verbose "[Get-WikiTemplateContent] Loaded from default directory: $defaultPath"
            }
            catch {
                Write-Warning "Failed to load default template '$defaultPath': $_"
            }
        }
        else {
            Write-Verbose "[Get-WikiTemplateContent] Default template not found: $defaultPath"
        }
    }
    
    # Fall back to embedded template
    if (-not $content -and $embeddedTemplates.ContainsKey($TemplateName)) {
        $content = $embeddedTemplates[$TemplateName]
        Write-Verbose "[Get-WikiTemplateContent] Using embedded fallback template for: $TemplateName"
    }
    
    # Apply replacements
    if ($content -and $Replacements.Count -gt 0) {
        foreach ($key in $Replacements.Keys) {
            $content = $content -replace [regex]::Escape($key), $Replacements[$key]
        }
    }
    
    if (-not $content) {
        Write-Warning "No template found for '$TemplateName' (checked custom, default, and embedded)"
        return "# $TemplateName`n`nTemplate not available."
    }
    
    return $content
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-PreparedProjects',
    'Get-WikiTemplateContent'
)
