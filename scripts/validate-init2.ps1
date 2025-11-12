# Validation script for Core.Rest init and InitMetrics (improved diagnostics)
try {
    Import-Module "$PSScriptRoot\..\modules\core\Core.Rest.psm1" -Force -ErrorAction Stop
    Write-Host "[TEST] Imported Core.Rest module"
}
catch {
    Write-Error "Failed to import Core.Rest: $_"
    exit 2
}

try {
    Initialize-CoreRest -CollectionUrl 'https://dev.azure.com/fake' -AdoPat 'fake' -GitLabBaseUrl 'https://gitlab.fake' -GitLabToken 'fake' -LogRestCalls:$false -RetryAttempts 1 -RetryDelaySeconds 1
    Write-Host "[TEST] Called Initialize-CoreRest"
}
catch {
    Write-Error "Initialize-CoreRest failed: $_"
    exit 3
}

# List exported commands from Core.Rest
Write-Host "Exported commands in Core.Rest:" -ForegroundColor Cyan
try { Get-Command -Module Core.Rest | Select-Object Name,CommandType | Sort-Object Name | Format-Table -AutoSize } catch { Write-Warning "Could not list commands: $_" }

# Try invoking Test-HttpClientInitialized via module-qualified or resolved command
$cmd = Get-Command -Name Test-HttpClientInitialized -ErrorAction SilentlyContinue
if ($cmd) {
    Write-Host "Invoking Test-HttpClientInitialized via resolved command"
    try { & $cmd; } catch { Write-Warning "Invocation failed: $_" }
}
else {
    Write-Host "Test-HttpClientInitialized not found as a command in the session"
}

# Get init metrics
try {
     # Ensure metrics are initialized explicitly
     Initialize-InitMetrics | Out-Null
     Write-Host "Initialize-InitMetrics called"

    $metrics = Get-InitMetrics
    Write-Host "InitMetrics:" 
    $metrics | ConvertTo-Json -Depth 5 | Write-Host
}
catch {
    Write-Error "Get-InitMetrics failed: $_"
}

Write-Host "Validation script completed"
