$modulePath = Join-Path (Join-Path $PSScriptRoot '..') 'modules\AzureDevOps\AzureDevOps.psm1'
try {
    Import-Module -Name $modulePath -Force -Verbose -ErrorAction Stop
    Write-Host 'Import succeeded'
}
catch {
    Write-Host 'Import failed:' -ForegroundColor Red
    Write-Host "Message: $($_.Exception.Message)"
    if ($_.Exception.ScriptStackTrace) { Write-Host "ScriptStackTrace:`n$($_.Exception.ScriptStackTrace)" }
    if ($_.InvocationInfo) { Write-Host "InvocationInfo: $($_.InvocationInfo.PositionMessage)" }
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" }
    # Dump the last parser errors in $error
    Write-Host "Full Error Object:`n$($_ | Out-String)"
}
