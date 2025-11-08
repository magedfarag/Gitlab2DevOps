#!/usr/bin/env pwsh
# Quick test to check if project exists

Import-Module .\modules\core\EnvLoader.psm1 -Force
Import-DotEnvFile -Path '.env' -SetEnvironmentVariables

Import-Module .\modules\core\Core.Rest.psm1 -Force
Initialize-CoreRest -CollectionUrl $env:ADO_COLLECTION_URL -AdoPat $env:ADO_PAT -GitLabBaseUrl $env:GITLAB_BASE_URL -GitLabToken $env:GITLAB_PAT -SkipCertificateCheck

Import-Module .\modules\adapters\AzureDevOps\Core.psm1 -Force

Write-Host ""
Write-Host "Testing project existence..." -ForegroundColor Cyan
$projectName = "ea-gduea-emfs"
$exists = Test-AdoProjectExists -ProjectName $projectName

Write-Host "Project '$projectName' exists: $exists" -ForegroundColor $(if ($exists) { 'Green' } else { 'Red' })

if (-not $exists) {
    Write-Host ""
    Write-Host "Fetching all projects..." -ForegroundColor Cyan
    $projects = Get-AdoProjectList -RefreshCache
    Write-Host "Total projects found: $($projects.Count)" -ForegroundColor Gray
    
    $projects | Select-Object -First 10 name, id | Format-Table -AutoSize
}
