# Smoke test for Core.Rest edits
Import-Module "$PSScriptRoot\..\modules\core\Core.Rest.psm1" -Force -DisableNameChecking
Set-AdoContext -CollectionUrl 'https://dev.azure.com/exampleorg' -ProjectName 'demo'
# $config = Get-CoreRestConfig
# Write-Host "CollectionUrl: $($config.CollectionUrl)"
# Write-Host "ProjectName: $($config.ProjectName)"
# Write-Host "ModuleVersion: $(Get-CoreRestVersion)"
exit 0
