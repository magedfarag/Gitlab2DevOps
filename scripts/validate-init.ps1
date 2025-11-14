# Validation script for Core.Rest init and InitMetrics
try {
    Import-Module "$PSScriptRoot\..\modules\core\Core.Rest.psm1" -Force -ErrorAction Stop
    Write-Host "[TEST] Imported Core.Rest module"
}
catch {
    Write-Error "Failed to import Core.Rest: $_"
    exit 2
}

# try {
#     Initialize-CoreRest -CollectionUrl 'https://dev.azure.com/fake' -AdoPat 'fake' -GitLabBaseUrl 'https://gitlab.fake' -GitLabToken 'fake' -LogRestCalls:$false -RetryAttempts 1 -RetryDelaySeconds 1
#     Write-Host "[TEST] Called Initialize-CoreRest"
# }
# catch {
#     Write-Error "Initialize-CoreRest failed: $_"
#     exit 3
# }

try {
    $hc = Test-HttpClientInitialized
    Write-Host "HttpClientInitialized = $hc"
}
catch {
    Write-Error "Test-HttpClientInitialized failed: $_"
}

try {
    $metrics = Get-InitMetrics
    Write-Host "InitMetrics:" 
    $metrics | ConvertTo-Json -Depth 5 | Write-Host
}
catch {
    Write-Error "Get-InitMetrics failed: $_"
}

Write-Host "Validation script completed"
