param(
    [string]$TestPath = 'tests\BusinessInit.Idempotency.Tests.ps1'
)

Set-StrictMode -Version Latest
Set-Location $PSScriptRoot\..\

$coreRestPath = Join-Path $PWD 'modules\core\Core.Rest.psm1'
if (Test-Path $coreRestPath) {
    try {
        Remove-Module -Name 'Core.Rest' -Force -ErrorAction SilentlyContinue
        Import-Module $coreRestPath -Force -Global -DisableNameChecking -ErrorAction Stop
        Write-Host "Imported Core.Rest from: $coreRestPath"
    }
    catch {
        Write-Warning "Failed to import Core.Rest: $_"
    }
}

# Ensure minimal ADO context for tests so module callers that build URIs don't hit null CollectionUrl
# try {
#     if (Get-Command Initialize-CoreRest -ErrorAction SilentlyContinue) {
#         # Initialize with dummy tokens for test environment (keeps behavior non-interactive)
#         Initialize-CoreRest -CollectionUrl 'https://dev.azure.com/placeholder' -AdoPat 'TEST-PAT' -GitLabBaseUrl 'https://gitlab.com' -GitLabToken 'TEST-TOKEN-PLACEHOLDER' -AdoApiVersion '7.1' -RetryAttempts 1 -RetryDelaySeconds 1 -MaskSecrets $false -LogRestCalls:$false
#     }
#     elseif (-not $script:CollectionUrl) {
#         Set-AdoContext -CollectionUrl 'https://dev.azure.com/placeholder' -ProjectName 'PesterBizProj'
#     }
# } catch {
#     Write-Verbose "Set-AdoContext not available or failed: $_"
# }

# Dump core rest config for debugging
# try {
#     if (Get-Command Get-CoreRestConfig -ErrorAction SilentlyContinue) {
#         $cfg = Get-CoreRestConfig
#         Write-Host "CoreRestConfig: $($cfg | Out-String)"
#     } else {
#         Write-Host "Get-CoreRestConfig not available"
#     }
# } catch {
#     Write-Host "Get-CoreRestConfig failed: $_"
# }

$env:GitLabBaseUrl = $env:GitLabBaseUrl -or 'https://gitlab.com'
$env:GitLabToken = $env:GitLabToken -or 'TEST-TOKEN-PLACEHOLDER'

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { param($Message,$Level); if (-not $Level) { $Level='INFO' }; Write-Host "[LOG:$Level] $Message" }
}

Write-Host "Running test: $TestPath"
$result = Invoke-Pester -Script $TestPath -PassThru -Verbose
$result | Format-List *

if ($result.FailedCount -gt 0) { exit 2 } else { exit 0 }
