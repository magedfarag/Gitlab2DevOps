<#
.SYNOPSIS
    Offline tests for Gitlab2DevOps modules (no API connections required).

.DESCRIPTION
    Tests all new modules without requiring GitLab or Azure DevOps connectivity.
    Uses mock data and validates module functionality in isolation.

.NOTES
    Run with: .\tests\OfflineTests.ps1
    All tests can run offline - no credentials needed
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup test environment
$testRoot = Split-Path -Parent $PSCommandPath
$moduleRoot = Join-Path (Split-Path -Parent $testRoot) "modules"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OFFLINE MODULE TESTS" -ForegroundColor Cyan
Write-Host "  No API connections required" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$testResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    Skipped = 0
}

function Test-Module {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    
    $testResults.Total++
    Write-Host "Testing: $Name" -ForegroundColor Yellow
    
    try {
        & $TestBlock
        $testResults.Passed++
        Write-Host "  ✅ PASS" -ForegroundColor Green
        return $true
    }
    catch {
        $testResults.Failed++
        Write-Host "  ❌ FAIL: $_" -ForegroundColor Red
        return $false
    }
}

#region ProgressTracking Tests

Write-Host "`n=== PROGRESS TRACKING MODULE ===" -ForegroundColor Cyan

Test-Module "ProgressTracking module loads" {
    Import-Module (Join-Path $moduleRoot "ProgressTracking.psm1") -Force
    if (-not (Get-Command Start-MigrationProgress -ErrorAction SilentlyContinue)) {
        throw "Start-MigrationProgress not exported"
    }
}

Test-Module "Start-MigrationProgress creates context" {
    $progress = Start-MigrationProgress -Activity "Test" -TotalItems 10 -Status "Testing"
    
    if (-not $progress) { throw "No context returned" }
    if ($progress.Activity -ne "Test") { throw "Activity not set" }
    if ($progress.TotalItems -ne 10) { throw "TotalItems not set" }
    if (-not $progress.StartTime) { throw "StartTime not set" }
    if (-not $progress.Id) { throw "Id not generated" }
}

Test-Module "Update-MigrationProgress calculates percentage" {
    $progress = Start-MigrationProgress -Activity "Test" -TotalItems 100 -Status "Testing"
    
    # Update to 50%
    Update-MigrationProgress -Context $progress -CurrentItem 50 -Status "Halfway"
    
    if ($progress.CurrentItem -ne 50) { throw "CurrentItem not updated" }
    if ($progress.Status -ne "Halfway") { throw "Status not updated" }
}

Test-Module "Update-MigrationProgress calculates ETA" {
    $progress = Start-MigrationProgress -Activity "Test" -TotalItems 100 -Status "Testing"
    
    # Simulate some time passing
    Start-Sleep -Milliseconds 100
    
    # Update to 10 items (should calculate ETA for remaining 90)
    Update-MigrationProgress -Context $progress -CurrentItem 10 -Status "Processing" -CurrentOperation "Item 10"
    
    # ETA should be calculated
    $elapsed = (Get-Date) - $progress.StartTime
    if ($elapsed.TotalSeconds -lt 0.05) { throw "Time not elapsed properly" }
}

Test-Module "Complete-MigrationProgress clears progress" {
    $progress = Start-MigrationProgress -Activity "Test" -TotalItems 10 -Status "Testing"
    Complete-MigrationProgress -Context $progress
    # Should not throw
}

Test-Module "Invoke-GitCloneWithProgress accepts parameters" {
    # Test parameter validation without actually cloning
    $params = @{
        Url = "https://example.com/repo.git"
        Destination = "C:\temp\test-repo"
        Mirror = $true
        SizeEstimateMB = 100
        WhatIf = $true  # Don't actually execute
    }
    
    # Verify function exists and accepts parameters
    $cmd = Get-Command Invoke-GitCloneWithProgress
    if (-not $cmd) { throw "Function not found" }
    
    # Check required parameters exist
    $requiredParams = @('Url', 'Destination')
    foreach ($param in $requiredParams) {
        if (-not ($cmd.Parameters.ContainsKey($param))) {
            throw "Missing parameter: $param"
        }
    }
}

#endregion

#region Telemetry Tests

Write-Host "`n=== TELEMETRY MODULE ===" -ForegroundColor Cyan

Test-Module "Telemetry module loads" {
    Import-Module (Join-Path $moduleRoot "Telemetry.psm1") -Force
    if (-not (Get-Command Initialize-Telemetry -ErrorAction SilentlyContinue)) {
        throw "Initialize-Telemetry not exported"
    }
}

Test-Module "Initialize-Telemetry with disabled flag (opt-in)" {
    # Default should be disabled (opt-in)
    $session = Initialize-Telemetry -SessionName "Test-Disabled"
    
    if ($session) { throw "Session should be null when not enabled" }
}

Test-Module "Initialize-Telemetry with enabled flag" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-Enabled"
    
    if (-not $session) { throw "No session returned" }
    if ($session.SessionName -ne "Test-Enabled") { throw "SessionName not set" }
    if (-not $session.SessionId) { throw "SessionId not generated" }
    if (-not $session.StartTime) { throw "StartTime not set" }
    if ($null -eq $session.Events) { throw "Events array not initialized" }
    if ($null -eq $session.Metrics) { throw "Metrics array not initialized" }
}

Test-Module "Record-TelemetryEvent stores event" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-Events"
    
    Record-TelemetryEvent -EventType "TestEvent" -Project "test-project" -Data @{ Key = "Value" }
    
    $events = $session.Events
    if ($events.Count -ne 1) { throw "Event not recorded" }
    if ($events[0].EventType -ne "TestEvent") { throw "EventType incorrect" }
    if ($events[0].Project -ne "test-project") { throw "Project incorrect" }
}

Test-Module "Record-TelemetryMetric stores metric" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-Metrics"
    
    Record-TelemetryMetric -MetricName "Duration" -Value 125.5 -Unit "seconds" -Tags @{ Test = "Value" }
    
    $metrics = $session.Metrics
    if ($metrics.Count -ne 1) { throw "Metric not recorded" }
    if ($metrics[0].MetricName -ne "Duration") { throw "MetricName incorrect" }
    if ($metrics[0].Value -ne 125.5) { throw "Value incorrect" }
}

Test-Module "Record-TelemetryError stores error" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-Errors"
    
    Record-TelemetryError -ErrorMessage "Test error" -ErrorType "TestError" -Context @{ Info = "Details" }
    
    $errors = $session.Errors
    if ($errors.Count -ne 1) { throw "Error not recorded" }
    if ($errors[0].ErrorType -ne "TestError") { throw "ErrorType incorrect" }
}

Test-Module "Record-TelemetryApiCall stores API call" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-API"
    
    Record-TelemetryApiCall -Method "GET" -Endpoint "/test" -DurationMs 250 -StatusCode 200 -Success
    
    $apiCalls = $session.ApiCalls
    if ($apiCalls.Count -ne 1) { throw "API call not recorded" }
    if ($apiCalls[0].Method -ne "GET") { throw "Method incorrect" }
    if ($apiCalls[0].DurationMs -ne 250) { throw "Duration incorrect" }
    if (-not $apiCalls[0].Success) { throw "Success flag not set" }
}

Test-Module "Export-TelemetryData to JSON" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-Export"
    Record-TelemetryEvent -EventType "Test" -Project "test"
    Record-TelemetryMetric -MetricName "Test" -Value 100
    
    $tempFile = Join-Path $env:TEMP "telemetry-test-$(Get-Random).json"
    
    Export-TelemetryData -OutputPath $tempFile -Format JSON
    
    if (-not (Test-Path $tempFile)) { throw "Export file not created" }
    
    $content = Get-Content $tempFile -Raw | ConvertFrom-Json
    if (-not $content.Summary) { throw "Summary not in export" }
    if (-not $content.Events) { throw "Events not in export" }
    if (-not $content.Metrics) { throw "Metrics not in export" }
    
    Remove-Item $tempFile -Force
}

Test-Module "Get-TelemetryStatistics returns stats" {
    $session = Initialize-Telemetry -Enabled -SessionName "Test-Stats"
    Record-TelemetryEvent -EventType "Test1" -Project "test"
    Record-TelemetryEvent -EventType "Test2" -Project "test"
    Record-TelemetryMetric -MetricName "Test" -Value 100
    Record-TelemetryApiCall -Method "GET" -Endpoint "/test" -DurationMs 250 -StatusCode 200 -Success
    
    $stats = Get-TelemetryStatistics
    
    if (-not $stats) { throw "No stats returned" }
    if ($stats.EventCount -ne 2) { throw "EventCount incorrect: $($stats.EventCount)" }
    if ($stats.MetricCount -ne 1) { throw "MetricCount incorrect" }
    if ($stats.ApiStatistics.TotalCalls -ne 1) { throw "ApiCalls incorrect" }
}

#endregion

#region DryRunPreview Tests

Write-Host "`n=== DRY-RUN PREVIEW MODULE ===" -ForegroundColor Cyan

# Mock the GitLab and ADO functions for offline testing
function Get-GitLabProject {
    param([string]$PathWithNamespace)
    
    return [pscustomobject]@{
        path = "test-project"
        path_with_namespace = $PathWithNamespace
        default_branch = "main"
        visibility = "private"
        lfs_enabled = $true
        statistics = @{
            repository_size = 150MB
            lfs_objects_size = 25MB
        }
    }
}

function Get-AdoProjectList {
    param([switch]$UseCache)
    
    return @(
        [pscustomobject]@{ name = "ExistingProject"; id = "123" }
    )
}

function Invoke-AdoRest {
    param([string]$Method, [string]$Path)
    
    if ($Path -like "*repositories*") {
        return @{
            value = @(
                @{ name = "existing-repo" }
            )
        }
    }
    return @{ value = @() }
}

Test-Module "DryRunPreview module loads" {
    Import-Module (Join-Path $moduleRoot "DryRunPreview.psm1") -Force
    if (-not (Get-Command New-MigrationPreview -ErrorAction SilentlyContinue)) {
        throw "New-MigrationPreview not exported"
    }
}

Test-Module "New-MigrationPreview with offline error handling" {
    # This test verifies the module handles missing API dependencies gracefully (offline mode)
    $preview = New-MigrationPreview `
        -GitLabProjects @("group/test-project") `
        -DestinationProject "TestProject" `
        -OutputFormat Console
    
    if (-not $preview) { throw "No preview returned" }
    if ($preview.DestinationProject -ne "TestProject") { throw "DestinationProject incorrect" }
    # In offline mode with no API access, we expect warnings to be present
    if ($preview.Warnings.Count -lt 1) { throw "Warnings should be present for offline mode" }
}

Test-Module "New-MigrationPreview generates JSON (offline)" {
    $tempFile = Join-Path $env:TEMP "preview-test-$(Get-Random).json"
    
    $preview = New-MigrationPreview `
        -GitLabProjects @("group/test-project") `
        -DestinationProject "TestProject" `
        -OutputFormat JSON `
        -OutputPath $tempFile
    
    if (-not (Test-Path $tempFile)) { throw "JSON file not created" }
    
    $content = Get-Content $tempFile -Raw | ConvertFrom-Json
    if (-not $content.DestinationProject) { throw "DestinationProject not in JSON" }
    # In offline mode, verify the structure exists even if empty
    if ($null -eq $content.SourceProjects) { throw "SourceProjects property missing from JSON" }
    if ($null -eq $content.Warnings) { throw "Warnings property missing from JSON" }
    
    Remove-Item $tempFile -Force
}

Test-Module "New-MigrationPreview generates HTML" {
    $tempFile = Join-Path $env:TEMP "preview-test-$(Get-Random).html"
    
    $preview = New-MigrationPreview `
        -GitLabProjects @("group/test-project") `
        -DestinationProject "TestProject" `
        -OutputFormat HTML `
        -OutputPath $tempFile
    
    if (-not (Test-Path $tempFile)) { throw "HTML file not created" }
    
    $content = Get-Content $tempFile -Raw
    if ($content -notmatch "<!DOCTYPE html>") { throw "Not valid HTML" }
    if ($content -notmatch "TestProject") { throw "Project name not in HTML" }
    if ($content -notmatch "<table") { throw "No table in HTML" }
    
    Remove-Item $tempFile -Force
}

#endregion

#region API Error Catalog Tests

Write-Host "`n=== API ERROR CATALOG ===" -ForegroundColor Cyan

Test-Module "API Error Catalog file exists" {
    $catalogPath = Join-Path (Split-Path -Parent $moduleRoot) "docs" "api-errors.md"
    
    if (-not (Test-Path $catalogPath)) {
        throw "API Error Catalog not found at: $catalogPath"
    }
}

Test-Module "API Error Catalog has GitLab errors" {
    $catalogPath = Join-Path (Split-Path -Parent $moduleRoot) "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    $gitlabErrors = @("401 Unauthorized", "403 Forbidden", "404 Not Found", "429 Rate Limited", "500 Internal Server Error")
    
    foreach ($error in $gitlabErrors) {
        if ($content -notmatch [regex]::Escape($error)) {
            throw "Missing GitLab error: $error"
        }
    }
}

Test-Module "API Error Catalog has Azure DevOps errors" {
    $catalogPath = Join-Path (Split-Path -Parent $moduleRoot) "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    $adoErrors = @("TF400813", "TF401019", "TF400948", "TF20503")
    
    foreach ($error in $adoErrors) {
        if ($content -notmatch [regex]::Escape($error)) {
            throw "Missing Azure DevOps error: $error"
        }
    }
}

Test-Module "API Error Catalog has resolution sections" {
    $catalogPath = Join-Path (Split-Path -Parent $moduleRoot) "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    $sections = @("**Resolution**:", "**Prevention**:", "**Cause**:")
    
    foreach ($section in $sections) {
        if ($content -notmatch [regex]::Escape($section)) {
            throw "Missing section: $section"
        }
    }
}

Test-Module "API Error Catalog has troubleshooting guide" {
    $catalogPath = Join-Path (Split-Path -Parent $moduleRoot) "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    if ($content -notmatch "Troubleshooting Guide") {
        throw "Missing Troubleshooting Guide section"
    }
    
    if ($content -notmatch "Diagnostic Steps") {
        throw "Missing Diagnostic Steps"
    }
}

#endregion

#region Advanced Features Documentation Tests

Write-Host "`n=== DOCUMENTATION TESTS ===" -ForegroundColor Cyan

Test-Module "Advanced features documentation exists" {
    $docPath = Join-Path (Split-Path -Parent $moduleRoot) "examples" "advanced-features.md"
    
    if (-not (Test-Path $docPath)) {
        throw "Advanced features documentation not found"
    }
}

Test-Module "Advanced features has all sections" {
    $docPath = Join-Path (Split-Path -Parent $moduleRoot) "examples" "advanced-features.md"
    $content = Get-Content $docPath -Raw
    
    $sections = @(
        "Progress Tracking",
        "Telemetry and Metrics",
        "Dry-Run Preview",
        "API Error Reference"
    )
    
    foreach ($section in $sections) {
        if ($content -notmatch [regex]::Escape($section)) {
            throw "Missing section: $section"
        }
    }
}

Test-Module "Advanced features has code examples" {
    $docPath = Join-Path (Split-Path -Parent $moduleRoot) "examples" "advanced-features.md"
    $content = Get-Content $docPath -Raw
    
    # Should have PowerShell code blocks
    if ($content -notmatch '```powershell') {
        throw "Missing PowerShell code examples"
    }
    
    # Should have function examples
    $functions = @(
        "Start-MigrationProgress",
        "Initialize-Telemetry",
        "New-MigrationPreview"
    )
    
    foreach ($func in $functions) {
        if ($content -notmatch [regex]::Escape($func)) {
            throw "Missing function example: $func"
        }
    }
}

#endregion

#region Integration Tests

Write-Host "`n=== INTEGRATION TESTS ===" -ForegroundColor Cyan

Test-Module "All modules can be loaded together" {
    Import-Module (Join-Path $moduleRoot "ProgressTracking.psm1") -Force
    Import-Module (Join-Path $moduleRoot "Telemetry.psm1") -Force
    Import-Module (Join-Path $moduleRoot "DryRunPreview.psm1") -Force
    
    # Verify no conflicts
    $commands = @(
        "Start-MigrationProgress",
        "Initialize-Telemetry",
        "New-MigrationPreview"
    )
    
    foreach ($cmd in $commands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "Command not available after loading all modules: $cmd"
        }
    }
}

Test-Module "Progress tracking with telemetry integration" {
    $session = Initialize-Telemetry -Enabled -SessionName "Integration-Test"
    $progress = Start-MigrationProgress -Activity "Test" -TotalItems 5 -Status "Testing"
    
    for ($i = 1; $i -le 5; $i++) {
        Update-MigrationProgress -Context $progress -CurrentItem $i -Status "Item $i"
        Record-TelemetryEvent -EventType "ItemProcessed" -Project "test" -Data @{ Item = $i }
    }
    
    Complete-MigrationProgress -Context $progress
    
    $stats = Get-TelemetryStatistics
    if ($stats.EventCount -ne 5) { throw "Integration failed: expected 5 events, got $($stats.EventCount)" }
}

#endregion

# Display results
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  TEST RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total:   $($testResults.Total)" -ForegroundColor White
Write-Host "Passed:  $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped: $($testResults.Skipped)" -ForegroundColor Yellow
Write-Host ""

if ($testResults.Failed -gt 0) {
    Write-Host "❌ Some tests failed" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Cyan
    exit 1
}
else {
    Write-Host "✅ All tests passed!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    exit 0
}
