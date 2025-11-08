#!/usr/bin/env pwsh
# Test URL escaping

$testUrl1 = "/_apis/projects?`$top=5000"
Write-Host "Test 1: $testUrl1"

$testUrl2 = '/_apis/projects?$top=5000'
Write-Host "Test 2: $testUrl2"

$testUrl3 = "/_apis/projects?`${top}=5000"
Write-Host "Test 3: $testUrl3"

# This is what's in the code
$testUrl4 = "/_apis/projects?``$top=5000"
Write-Host "Test 4: $testUrl4"
