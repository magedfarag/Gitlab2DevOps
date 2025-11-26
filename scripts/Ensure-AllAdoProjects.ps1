# Ensure all Azure DevOps projects exist before import
# Reads projects.json and calls Measure-Adoproject for each

$projectsFile = Join-Path $PSScriptRoot '..\projects.json'
if (-not (Test-Path $projectsFile)) {
    throw "projects.json not found: $projectsFile"
}

$projectsConfig = Get-Content $projectsFile -Raw | ConvertFrom-Json

Import-Module "$PSScriptRoot\..\modules\AzureDevOps\Projects.psm1" -Force -ErrorAction Stop

foreach ($proj in $projectsConfig) {
    $name = $proj.adoproject
    Write-Host "Ensuring Azure DevOps project exists: $name" -ForegroundColor Cyan
    try {
        Measure-Adoproject -Name $name -ProcessTemplate "Agile"
    } catch {
        Write-Warning "Failed to ensure project '$name': $_"
    }
}

Write-Host "All projects checked." -ForegroundColor Green
