#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Diagnose Azure DevOps project connectivity and visibility issues.

.DESCRIPTION
    This script helps troubleshoot why a project might not be found when running
    team pack initialization. It checks:
    - Azure DevOps connection
    - Project existence via multiple methods
    - PAT permissions
    - Project cache state

.EXAMPLE
    .\diagnose-project.ps1 -ProjectName "ea-gduea-emfs"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectName,

    [Parameter()]
    [string]$AdoUrl,

    [Parameter()]
    [string]$AdoPat
)

# Import modules
$scriptRoot = $PSScriptRoot
Import-Module (Join-Path $scriptRoot "modules/core/EnvLoader.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules/core/Logging.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules/core/Core.Rest.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules/adapters/AzureDevOps/Core.psm1") -Force

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Azure DevOps Project Diagnostics" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Load environment
if (-not $AdoUrl -or -not $AdoPat) {
    $envFile = Join-Path $PSScriptRoot ".env"
    if (Test-Path $envFile) {
        Import-DotEnvFile -Path $envFile -SetEnvironmentVariables
    }
    if ($env:ADO_COLLECTION_URL) { $AdoUrl = $env:ADO_COLLECTION_URL }
    if ($env:ADO_PAT) { $AdoPat = $env:ADO_PAT }
}

# Validate credentials
if (-not $AdoUrl) {
    Write-Host "[ERROR] Azure DevOps URL not provided. Use -AdoUrl or set ADO_COLLECTION_URL in .env" -ForegroundColor Red
    exit 1
}

if (-not $AdoPat) {
    Write-Host "[ERROR] Azure DevOps PAT not provided. Use -AdoPat or set ADO_PAT in .env" -ForegroundColor Red
    exit 1
}

# Initialize connection
Write-Host "[1/6] Initializing Azure DevOps connection..." -ForegroundColor Cyan
try {
    Initialize-AdoConnection -ServerUrl $AdoUrl -Pat $AdoPat
    Write-Host "  ✓ Connection initialized successfully" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to initialize connection: $_" -ForegroundColor Red
    exit 1
}

# Test basic connectivity
Write-Host ""
Write-Host "[2/6] Testing API connectivity..." -ForegroundColor Cyan
try {
    $result = Invoke-AdoRest GET "/_apis/projects?`$top=1"
    Write-Host "  ✓ API endpoint accessible" -ForegroundColor Green
    Write-Host "  ✓ Authentication successful" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ API connectivity failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "[TIP] Check your PAT permissions and server URL" -ForegroundColor Yellow
    exit 1
}

# Get all projects (with cache refresh)
Write-Host ""
Write-Host "[3/6] Fetching all projects (refreshing cache)..." -ForegroundColor Cyan
try {
    $allProjects = Get-AdoProjectList -RefreshCache
    Write-Host "  ✓ Found $($allProjects.Count) total projects" -ForegroundColor Green
    
    if ($allProjects.Count -gt 0) {
        Write-Host ""
        Write-Host "  First 10 projects:" -ForegroundColor Gray
        $allProjects | Select-Object -First 10 | ForEach-Object {
            Write-Host "    - $($_.name)" -ForegroundColor Gray
        }
    }
}
catch {
    Write-Host "  ✗ Failed to fetch projects: $_" -ForegroundColor Red
    exit 1
}

# Search for target project (case-insensitive)
Write-Host ""
Write-Host "[4/6] Searching for project '$ProjectName'..." -ForegroundColor Cyan
$normalized = ($ProjectName -replace '\p{C}', '').Trim()
$matchingProjects = $allProjects | Where-Object { 
    ($_.name -as [string]) -and ($_.name.Trim() -ieq $normalized) 
}

if ($matchingProjects.Count -gt 0) {
    Write-Host "  ✓ Found matching project(s):" -ForegroundColor Green
    $matchingProjects | ForEach-Object {
        Write-Host "    - Name: '$($_.name)'" -ForegroundColor Gray
        Write-Host "      ID: $($_.id)" -ForegroundColor Gray
        Write-Host "      State: $($_.state)" -ForegroundColor Gray
        Write-Host "      Visibility: $($_.visibility)" -ForegroundColor Gray
    }
}
else {
    Write-Host "  ✗ No matching projects found in list" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Similar project names:" -ForegroundColor Gray
    $similar = $allProjects | Where-Object { $_.name -like "*$ProjectName*" } | Select-Object -First 5
    if ($similar.Count -gt 0) {
        $similar | ForEach-Object {
            Write-Host "    - $($_.name)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "    (none found)" -ForegroundColor Gray
    }
}

# Try direct GET by name
Write-Host ""
Write-Host "[5/6] Testing direct GET by name..." -ForegroundColor Cyan
try {
    $encoded = [uri]::EscapeDataString($normalized)
    $directProject = Invoke-AdoRest GET "/_apis/projects/$encoded"
    
    if ($directProject -and $directProject.id) {
        Write-Host "  ✓ Direct GET succeeded!" -ForegroundColor Green
        Write-Host "    - Name: '$($directProject.name)'" -ForegroundColor Gray
        Write-Host "    - ID: $($directProject.id)" -ForegroundColor Gray
        Write-Host "    - State: $($directProject.state)" -ForegroundColor Gray
    }
}
catch {
    Write-Host "  ✗ Direct GET failed: $_" -ForegroundColor Red
    
    if ($_ -match '404|NotFound') {
        Write-Host ""
        Write-Host "  [!] The project does not exist or you don't have access to it" -ForegroundColor Yellow
    }
}

# Test using Test-AdoProjectExists
Write-Host ""
Write-Host "[6/6] Testing Test-AdoProjectExists function..." -ForegroundColor Cyan
try {
    $exists = Test-AdoProjectExists -ProjectName $ProjectName
    
    if ($exists) {
        Write-Host "  ✓ Test-AdoProjectExists returned TRUE" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Test-AdoProjectExists returned FALSE" -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ Test-AdoProjectExists threw error: $_" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Diagnostic Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$foundInList = $matchingProjects.Count -gt 0
$foundDirect = $null -ne $directProject
$testPassed = $exists -eq $true

Write-Host "Project Name: '$ProjectName'" -ForegroundColor White
Write-Host "Found in Project List: " -NoNewline
if ($foundInList) { Write-Host "YES ✓" -ForegroundColor Green } else { Write-Host "NO ✗" -ForegroundColor Red }

Write-Host "Found via Direct GET: " -NoNewline
if ($foundDirect) { Write-Host "YES ✓" -ForegroundColor Green } else { Write-Host "NO ✗" -ForegroundColor Red }

Write-Host "Test-AdoProjectExists: " -NoNewline
if ($testPassed) { Write-Host "PASS ✓" -ForegroundColor Green } else { Write-Host "FAIL ✗" -ForegroundColor Red }

Write-Host ""

if ($foundInList -and $foundDirect -and $testPassed) {
    Write-Host "[SUCCESS] Project is fully accessible! ✓" -ForegroundColor Green
    Write-Host "[INFO] If team packs still fail, there may be a different issue." -ForegroundColor Cyan
}
elseif ($foundDirect -and -not $foundInList) {
    Write-Host "[WARNING] Project exists but not in cached list" -ForegroundColor Yellow
    Write-Host "[TIP] This might be a timing issue. Try running the team pack installation again." -ForegroundColor Yellow
}
elseif (-not $foundDirect) {
    Write-Host "[ERROR] Project does not exist or is not accessible" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  1. Project was deleted or renamed" -ForegroundColor Gray
    Write-Host "  2. PAT doesn't have 'Project and Team (read)' permissions" -ForegroundColor Gray
    Write-Host "  3. Project is in a different Azure DevOps organization" -ForegroundColor Gray
    Write-Host "  4. Network/firewall blocking access" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Recommended actions:" -ForegroundColor Yellow
    Write-Host "  1. Verify project exists in Azure DevOps web UI" -ForegroundColor Gray
    Write-Host "  2. Check PAT permissions: https://dev.azure.com/[org]/_usersSettings/tokens" -ForegroundColor Gray
    Write-Host "  3. Verify ADO_COLLECTION_URL in .env matches project location" -ForegroundColor Gray
}

Write-Host ""
