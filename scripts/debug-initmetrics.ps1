# Debug script to call Initialize-InitMetrics and inspect returned value
Import-Module "$PSScriptRoot\..\modules\core\Core.Rest.psm1" -Force -ErrorAction Stop
Initialize-CoreRest -CollectionUrl 'https://dev.azure.com/fake' -AdoPat 'fake' -GitLabBaseUrl 'https://gitlab.fake' -GitLabToken 'fake' -LogRestCalls:$false

Write-Host "Calling Initialize-InitMetrics..."
try {
    $init = Initialize-InitMetrics
    Write-Host "Initialize-InitMetrics returned type: $($init.GetType().FullName)"
    Write-Host "Keys: $($init.Keys -join ', ')"
}
catch {
    Write-Error "Initialize-InitMetrics threw: $($_ | Out-String)"
}

Write-Host "Now calling Get-InitMetrics..."
try {
    $g = Get-InitMetrics
    if ($g -eq $null) { Write-Host "Get-InitMetrics returned NULL" } else { Write-Host ($g | ConvertTo-Json -Depth 5) }
}
catch {
    Write-Error "Get-InitMetrics threw: $($_ | Out-String)"
}
