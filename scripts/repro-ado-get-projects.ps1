<#
Standalone repro for ADO projects GET using module HttpClient path.
Usage:
  pwsh -NoProfile -ExecutionPolicy Bypass .\scripts\repro-ado-get-projects.ps1 -CollectionUrl 'https://dev.azure.com/ORG' -AdoPat 'mypat' -SkipCert
Or rely on env vars: ADO_COLLECTION_URL and ADO_PAT
#>
param(
    [string]$CollectionUrl = $Env:ADO_COLLECTION_URL,
    [string]$AdoPat = $Env:ADO_PAT,
    [switch]$SkipCert
)

Set-StrictMode -Version Latest

function Write-Header { param($m) Write-Host "\n=== $m ===\n" -ForegroundColor Cyan }

if (-not $CollectionUrl -or -not $AdoPat) {
    Write-Host "ERROR: CollectionUrl and AdoPat must be supplied via parameters or ADO_COLLECTION_URL/ADO_PAT environment variables." -ForegroundColor Red
    exit 2
}

# Load core rest module (Import-Module to properly load exported functions and state)
Import-Module -Force -Scope Global "$PSScriptRoot\..\modules\core\Core.Rest.psm1"

Write-Header "Initialize-CoreRest"
try {
    Initialize-CoreRest -CollectionUrl $CollectionUrl -AdoPat $AdoPat -SkipCertificateCheck:($SkipCert.IsPresent) -Verbose
    Write-Host "Initialize-CoreRest completed" -ForegroundColor Green
} catch {
    Write-Host "Initialize-CoreRest failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
    exit 3
}

# Show handler preference and active handler if available
try { Write-Host "HttpClientHandlerPreference: $($script:HttpClientHandlerPreference)" } catch {}
try { Write-Host "HttpClientHandlerActive: $($script:HttpClientHandlerActive)" } catch {}

# Build request
$path = '/_apis/projects?$top=10'
$uri = "{0}/{1}?api-version={2}" -f $CollectionUrl.TrimEnd('/'), $path.TrimStart('/'), '7.1'
Write-Header "Request URI: $uri"

# Attempt Invoke-AdoRest (module path)
Write-Header "Invoke-AdoRest (module HttpClient path)"
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Use the module path style: pass the API path as First (leading '/') and let the module append api-version
    $res = Invoke-AdoRest -First $path -Verbose
    $sw.Stop()
    Write-Host "Invoke-AdoRest completed in $($sw.Elapsed.TotalMilliseconds) ms" -ForegroundColor Green
    if ($res -is [System.String]) {
        Write-Host "Response (trimmed):"; Write-Host $res.Substring(0, [Math]::Min(2000, $res.Length))
    } else {
        $res | ConvertTo-Json -Depth 3 | Write-Host
    }
} catch {
    Write-Host "Invoke-AdoRest failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
    Write-Host "Full exception:`n$($_ | Out-String)" -ForegroundColor Yellow

    Write-Header "Invoke-RestFallbackUsingInvokeWebRequest (test)"
    try {
        $fw = Invoke-RestFallbackUsingInvokeWebRequest -Uri $uri -Method GET -Headers @{ Authorization = (New-AuthHeader -AdoPat $AdoPat).Authorization } -TimeoutSeconds 60
        Write-Host "Fallback result:" -ForegroundColor Green
        if ($fw -is [string]) { Write-Host $fw.Substring(0, [Math]::Min(2000, $fw.Length)) } else { $fw | ConvertTo-Json -Depth 3 | Write-Host }
    } catch {
        Write-Host "Fallback also failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.InnerException) { Write-Host "Fallback inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
    }
    exit 4
}

Write-Host "Done" -ForegroundColor Cyan
exit 0
