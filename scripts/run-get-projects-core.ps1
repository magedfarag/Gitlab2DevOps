# Script: run-get-projects-core.ps1
# Reads .env (if present), initializes Core.Rest and AzureDevOps Core module, and lists projects via Get-AdoProjectList

Write-Host "Initializing Core.Rest and AzureDevOps core modules..."

Import-Module (Join-Path $PSScriptRoot "..\modules\core\Core.Rest.psm1") -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot "..\modules\AzureDevOps\Core.psm1") -Force -ErrorAction Stop

# Core.Rest is responsible for loading .env and exposing configuration.
# Validate that Core.Rest has been initialized and has a CollectionUrl configured.
try {
    $cfg = Ensure-CoreRestInitialized
    Write-Host "CollectionUrl: $($cfg.CollectionUrl)"
    Write-Host "PAT present: $([bool]$cfg.AdoPat)"
}
catch {
    Write-Host "ERROR: Core.Rest initialization failed or required configuration missing: $($_)" -ForegroundColor Red
    exit 2
}

Write-Host "Calling Get-AdoProjectList -RefreshCache..."
try {
    $projects = Get-AdoProjectList -RefreshCache
    if ($projects -and $projects.Count -gt 0) {
        Write-Host "Fetched $($projects.Count) projects:" -ForegroundColor Green
        $projects | Select-Object -First 10 | Select-Object name,id | Format-Table -AutoSize
    }
    else {
        Write-Warning "No projects returned or call failed"
    }
}
catch {
    Write-Host "Get-AdoProjectList failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
}
