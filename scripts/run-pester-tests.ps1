Set-StrictMode -Version Latest
Set-Location $PSScriptRoot\..\
Write-Host "Running from: $(Get-Location)"

# Ensure Pester available
if (-not (Get-Command Invoke-Pester -ErrorAction SilentlyContinue)) {
    Write-Host 'Pester not found — installing (current user scope)...'
    Install-Module Pester -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
}

$testFiles = Get-ChildItem -Path .\tests -Filter *.Tests.ps1 -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
if (-not $testFiles -or $testFiles.Count -eq 0) {
    Write-Host 'No test files found under tests/' -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($testFiles.Count) test file(s). Running Pester..." -ForegroundColor Cyan

# Preload key modules and test environment to avoid duplicate loads and interactive prompts
$coreRestPath = Join-Path $PSScriptRoot '..' 'modules' 'core' 'Core.Rest.psm1'
if (Test-Path $coreRestPath) {
    try {
        # Ensure any previously loaded Core.Rest module is removed to avoid "multiple modules named 'Core.Rest' are currently loaded"
        Remove-Module -Name 'Core.Rest' -Force -ErrorAction SilentlyContinue
        Import-Module $coreRestPath -Force -Global -DisableNameChecking -ErrorAction Stop
        Write-Host "Imported Core.Rest from: $coreRestPath"
    }
    catch {
        Write-Warning "Failed to import Core.Rest: $_"
    }
}

# Provide test-safe environment variables to avoid interactive prompts in scripts
$env:GitLabBaseUrl = $env:GitLabBaseUrl -or 'https://gitlab.com'
$env:GitLabToken = $env:GitLabToken -or 'TEST-TOKEN-PLACEHOLDER'

# Provide a minimal Write-Log shim used by some tests/scripts
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { param($Message, $Level='INFO') Write-Host "[LOG:$Level] $Message" }
}

$result = Invoke-Pester -Script $testFiles -PassThru -Verbose

Write-Host '--- Pester Summary ---'
$result | Format-List *

if ($result.FailedCount -gt 0) {
    Write-Host "Pester: FAIL - $($result.FailedCount) failed, $($result.SkippedCount) skipped" -ForegroundColor Red
    exit 2
} else {
    Write-Host "Pester: PASS - $($result.TotalCount) tests, $($result.PassedCount) passed" -ForegroundColor Green
    exit 0
}
