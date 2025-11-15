<#
.SYNOPSIS
    Prepares GitLab migrations based on projects.json config file.
.DESCRIPTION
    Reads projects.json and prepares all listed GitLab projects into the correct
    migrations folder structure for bulk migration.
.NOTES
    Minimal changes, reuses existing functions.
#>

param(
    [Parameter()]
    [string]$ConfigFile = 'projects.json',

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Force
)

# Import required modules when this script is run standalone
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreModule = Join-Path $root 'modules\core\Core.Rest.psm1'
$gitlabModule = Join-Path $root 'modules\GitLab\GitLab.psm1'
$loggingModule = Join-Path $root 'modules\core\Logging.psm1'
if (Test-Path $coreModule) { Import-Module $coreModule -Force -ErrorAction Stop }
if (Test-Path $gitlabModule) { Import-Module $gitlabModule -Force -ErrorAction Stop }
if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction Stop }

# NOTE: Core.Rest is responsible for reading .env files and exposing
# configuration via Get-CoreRestConfig / Get-GitLabToken. This script must
# NOT read .env files directly; centralized access to secrets is enforced.
# Ensure Core.Rest module is imported (above) so it can load configuration.

# Validate GitLab token early to provide clear guidance instead of obscure HTTP errors
if (-not $DryRun.IsPresent) {
    try {
        # Get-GitLabToken will throw a user-friendly actionable error if token not set
        $null = Get-GitLabToken
    }
    catch {
        Write-Host "[ERROR] GitLab token not configured or invalid. Set GITLAB_PAT in environment or .env file before running bulk preparation." -ForegroundColor Red
        Write-Host "        See README.md or docs/env-configuration.md for instructions." -ForegroundColor Yellow
        exit 1
    }
}
else {
    Write-Host "[INFO] Dry run mode enabled - skipping GitLab token validation and API calls." -ForegroundColor Cyan
}

# Resolve config path relative to script root when a relative path is provided
if (-not [System.IO.Path]::IsPathRooted($ConfigFile)) {
    $resolvedLocalConfig = Join-Path $root $ConfigFile
    if (Test-Path $resolvedLocalConfig) {
        $ConfigFile = $resolvedLocalConfig
    }
}

# Load config
if (-not (Test-Path $ConfigFile)) {
    Write-Host "[ERROR] Config file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json

foreach ($entry in $config) {
    $adoProject = $entry.adoproject
    $projectPaths = $entry.projects
    if (-not $adoProject -or -not $projectPaths) {
        Write-Host "[WARN] Skipping entry with missing adoproject or projects." -ForegroundColor Yellow
        continue
    }
    Write-Host "[INFO] Preparing migrations for Azure DevOps project: $adoProject" -ForegroundColor Cyan
    try {
        if ($DryRun.IsPresent) {
            # Simulate bulk preparation: create directories and write minimal preflight reports
            Write-Host "[DRYRUN] Simulating bulk preparation for '$adoProject'..." -ForegroundColor Cyan
            $bulkPaths = Get-BulkProjectPaths -AdoProject $adoProject
            $projectsOut = @()
            foreach ($pp in $projectPaths) {
                $projName = ($pp -split '/')[-1]
                $gitPaths = Get-BulkProjectPaths -AdoProject $adoProject -GitLabProject $projName
                $preflight = [pscustomobject]@{
                    project = $pp
                    repo_size_MB = 0
                    lfs_enabled = $false
                    lfs_size_MB = 0
                    default_branch = 'main'
                    visibility = 'private'
                    preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                $reportFile = Join-Path $gitPaths.gitlabDir "reports\preflight-report.json"
                if (-not (Test-Path (Split-Path $reportFile -Parent))) { New-Item -ItemType Directory -Path (Split-Path $reportFile -Parent) -Force | Out-Null }
                $preflight | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile

                $projectsOut += [pscustomobject]@{
                    gitlab_path = $pp
                    ado_repo_name = $projName
                    description = "Simulated migration of $pp"
                    repo_size_MB = 0
                    lfs_enabled = $false
                    lfs_size_MB = 0
                    default_branch = 'main'
                    visibility = 'private'
                    preparation_status = 'SUCCESS'
                }
            }

            $configOut = [pscustomobject]@{
                description = "Bulk migration configuration for '$adoProject' - DRYRUN"
                destination_project = $adoProject
                migration_type = 'BULK'
                preparation_summary = [pscustomobject]@{
                    total_projects = $projectPaths.Count
                    successful_preparations = $projectPaths.Count
                    failed_preparations = 0
                    total_size_MB = 0
                    total_lfs_MB = 0
                    preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                projects = $projectsOut
            }

            $configFile = $bulkPaths.configFile
            $configOut | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $configFile
            Write-Host "[DRYRUN] Generated simulated bulk config: $configFile" -ForegroundColor Green
        }
        else {
            if ($Force.IsPresent) {
                Invoke-BulkPrepareGitLab -ProjectPaths $projectPaths -DestProjectName $adoProject -Force
            }
            else {
                Invoke-BulkPrepareGitLab -ProjectPaths $projectPaths -DestProjectName $adoProject
            }
        }
    } catch {
        # Use subexpression to avoid PowerShell confusing "$adoProject:" as a variable namespace
        Write-Host "[ERROR] Bulk preparation failed for ${adoProject}: $($_)" -ForegroundColor Red
    }
}
Write-Host "[SUCCESS] All configured migrations prepared." -ForegroundColor Green
