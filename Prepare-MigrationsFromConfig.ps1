<#
.SYNOPSIS
    Prepares GitLab migrations based on projects.json config file.
.DESCRIPTION
    Reads projects.json and prepares all listed GitLab projects into the correct migrations folder structure for bulk migration.
.NOTES
    Minimal changes, reuses existing functions.
#>

param(
    [string]$ConfigFile = "projects.json"
)

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
        Invoke-BulkPrepareGitLab -ProjectPaths $projectPaths -DestProjectName $adoProject
    } catch {
        Write-Host "[ERROR] Bulk preparation failed for $adoProject: $_" -ForegroundColor Red
    }
}
Write-Host "[SUCCESS] All configured migrations prepared." -ForegroundColor Green
