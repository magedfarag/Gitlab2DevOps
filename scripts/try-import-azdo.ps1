$projectRoot = 'C:\Projects\devops\Gitlab2DevOps'
$moduleRoot = Join-Path $projectRoot 'modules'
$path = Join-Path $moduleRoot 'AzureDevOps\AzureDevOps.psm1'
Write-Host "Attempting Import-Module $path"
Import-Module $path -Force -Verbose
Write-Host "Import succeeded"
Get-Module AzureDevOps | Format-List * -Force
