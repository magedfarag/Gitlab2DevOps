Set-StrictMode -Version Latest
# Move to repo root
Set-Location -Path (Join-Path $PSScriptRoot '..')
$coreRestPath = Join-Path $PWD 'modules\core\Core.Rest.psm1'
Import-Module $coreRestPath -Force -Global -DisableNameChecking
Initialize-CoreRest -CollectionUrl 'https://dev.azure.com/placeholder' -AdoPat 'TEST-PAT' -GitLabBaseUrl 'https://gitlab.com' -GitLabToken 'TEST-TOKEN' -AdoApiVersion '7.1' -RetryAttempts 1 -RetryDelaySeconds 1
# Use the accessor/Get-CoreRestConfig instead of directly referencing script-scoped vars inside strings
$coreCfg = Get-CoreRestConfig
Write-Host "After init: CollectionUrl=$($coreCfg.CollectionUrl) ; AdoHeaders present=$([bool]$coreCfg.AdoHeaders)"
try {
    Measure-Adoprojectwiki -ProjId 'fakeid' -Project 'PesterBizProj'
    Write-Host "Measure-Adoprojectwiki succeeded"
}
catch {
    Write-Host "Measure-Adoprojectwiki failed: $_"
    Write-Host "CoreRestConfig:"
    Get-CoreRestConfig | Format-List *
}
