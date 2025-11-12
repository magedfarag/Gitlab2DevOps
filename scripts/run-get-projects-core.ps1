# Script: run-get-projects-core.ps1
# Reads .env (if present), initializes Core.Rest and AzureDevOps Core module, and lists projects via Get-AdoProjectList

function Read-DotEnvLocal {
    param([string]$Path = (Join-Path (Get-Location) '.env'))
    $pairs = @{}
    if (-not (Test-Path $Path)) { return $pairs }
    Get-Content $Path | ForEach-Object {
        $_ = $_.Trim()
        if ($_.StartsWith('#') -or $_ -eq '') { return }
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            $k = $parts[0].Trim()
            $v = $parts[1].Trim()
            if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            $pairs[$k] = $v
        }
    }
    return $pairs
}

Write-Host "Loading .env if present..."
$dot = Read-DotEnvLocal
$collectionUrl = $Env:ADO_COLLECTION_URL
if (-not $collectionUrl -and $dot.ContainsKey('ADO_COLLECTION_URL')) { $collectionUrl = $dot['ADO_COLLECTION_URL'] }
$pat = $Env:ADO_PAT
if (-not $pat -and $dot.ContainsKey('ADO_PAT')) { $pat = $dot['ADO_PAT'] }
$skip = $false
if ($Env:SKIP_CERTIFICATE_CHECK -or ($dot.ContainsKey('SKIP_CERTIFICATE_CHECK') -and $dot['SKIP_CERTIFICATE_CHECK'] -in @('1','true','True','TRUE'))) { $skip = $true }

Write-Host "CollectionUrl: $collectionUrl"
Write-Host "PAT present: $([bool]$pat)"

if (-not $collectionUrl -or -not $pat) {
    Write-Host "ERROR: ADO_COLLECTION_URL and ADO_PAT are required in environment or .env" -ForegroundColor Red
    exit 2
}

Import-Module (Join-Path $PSScriptRoot "..\modules\core\Core.Rest.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\modules\AzureDevOps\Core.psm1") -Force

Initialize-CoreRest -CollectionUrl $collectionUrl -AdoPat $pat -SkipCertificateCheck:($skip) -Verbose

Write-Host "Calling Get-AdoProjectList -RefreshCache..."
try {
    $projects = Get-AdoProjectList -RefreshCache
    if ($projects -and $projects.Count -gt 0) {
        Write-Host "Fetched $($projects.Count) projects:" -ForegroundColor Green
        $projects | Select-Object -First 10 | Select-Object name,id | Format-Table -AutoSize
    }
    else {
        Write-Warning "No projects returned or call failed"
    }
}
catch {
    Write-Host "Get-AdoProjectList failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
}
