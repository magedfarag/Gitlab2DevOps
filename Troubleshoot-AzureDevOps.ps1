<#
.SYNOPSIS
    Comprehensive troubleshooting script for Azure DevOps REST API functions.

.DESCRIPTION
    Tests and diagnoses issues with Get-AdoProjectList, Initialize-AdoProject, and Invoke-AdoRest functions.
    Provides detailed diagnostics, error handling, and step-by-step troubleshooting.

.PARAMETER CollectionUrl
    Azure DevOps collection URL (e.g., https://dev.azure.com/organization or https://your-server/DefaultCollection)

.PARAMETER PersonalAccessToken
    Azure DevOps Personal Access Token

.PARAMETER SkipCertificateCheck
    Skip SSL certificate validation (useful for on-premise servers with self-signed certificates)

.PARAMETER Verbose
    Enable verbose output for detailed diagnostics

.EXAMPLE
    .\Troubleshoot-AzureDevOps.ps1 -CollectionUrl "https://dev.azure.com/myorg" -PersonalAccessToken "your-pat-here"

.EXAMPLE
    .\Troubleshoot-AzureDevOps.ps1 -CollectionUrl "https://ado-server/DefaultCollection" -PersonalAccessToken "your-pat" -SkipCertificateCheck
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CollectionUrl,

    [Parameter(Mandatory = $true)]
    [string]$PersonalAccessToken,

    [switch]$SkipCertificateCheck
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Script configuration
$script:ScriptVersion = "1.0.0"
$script:TestResults = @()
$script:VerboseOutput = $VerbosePreference -eq "Continue"

# Import required modules
$modulesPath = Join-Path $PSScriptRoot "modules"

function Write-TestHeader {
    param([string]$TestName)
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "TEST: $TestName" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Message = "",
        [object]$Details = $null
    )

    $result = @{
        TestName = $TestName
        Success = $Success
        Message = $Message
        Details = $Details
        Timestamp = Get-Date
    }
    $script:TestResults += $result

    if ($Success) {
        Write-Host "✅ PASS: $TestName" -ForegroundColor Green
        if ($Message) { Write-Host "   $Message" -ForegroundColor Gray }
    } else {
        Write-Host "❌ FAIL: $TestName" -ForegroundColor Red
        if ($Message) { Write-Host "   $Message" -ForegroundColor Red }
    }

    if ($Details -and $script:VerboseOutput) {
        Write-Host "   Details:" -ForegroundColor Yellow
        $Details | Format-List | Out-String | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
    }
}

function Test-ModuleImports {
    Write-TestHeader "Module Imports"

    $modulesToTest = @(
        @{ Name = "Core.Rest"; Path = Join-Path $modulesPath "core\Core.Rest.psm1" },
        @{ Name = "AzureDevOps.Projects"; Path = Join-Path $modulesPath "AzureDevOps\Projects.psm1" },
        @{ Name = "Migration.Initialization.ProjectInitialization"; Path = Join-Path $modulesPath "Migration\Initialization\ProjectInitialization.psm1" }
    )

    $allSuccess = $true

    foreach ($module in $modulesToTest) {
        try {
            if (Test-Path $module.Path) {
                Import-Module $module.Path -Force -Global -ErrorAction Stop
                Write-TestResult "Import $($module.Name)" $true "Successfully imported $($module.Path)"
            } else {
                Write-TestResult "Import $($module.Name)" $false "Module file not found: $($module.Path)"
                $allSuccess = $false
            }
        }
        catch {
            Write-TestResult "Import $($module.Name)" $false "Import failed: $($_.Exception.Message)"
            $allSuccess = $false
        }
    }

    return $allSuccess
}

function Test-CoreRestInitialization {
    Write-TestHeader "Core.Rest Module Initialization"

    try {
        # Test Initialize-CoreRest
        $initParams = @{
            CollectionUrl = $CollectionUrl
            AdoPat = $PersonalAccessToken
        }

        if ($SkipCertificateCheck) {
            $initParams.SkipCertificateCheck = $true
        }

        $result = Initialize-CoreRest @initParams

        if ($result) {
            Write-TestResult "Initialize-CoreRest" $true "Core.Rest initialized successfully"
            return $true
        } else {
            Write-TestResult "Initialize-CoreRest" $false "Initialize-CoreRest returned false"
            return $false
        }
    }
    catch {
        Write-TestResult "Initialize-CoreRest" $false "Initialization failed: $($_.Exception.Message)" @{
            Exception = $_.Exception
            StackTrace = $_.ScriptStackTrace
        }
        return $false
    }
}

function Test-BasicConnectivity {
    Write-TestHeader "Basic Azure DevOps Connectivity"

    try {
        # Test basic connection by calling the root API
        Write-Host "Testing basic connectivity to: $CollectionUrl" -ForegroundColor Gray

        $response = Invoke-AdoRest GET "/_apis" -ErrorAction Stop

        if ($response) {
            Write-TestResult "Basic Connectivity" $true "Successfully connected to Azure DevOps API" @{
                ApiVersion = $response.apiVersion
                RequestId = $response.requestId
            }
            return $true
        } else {
            Write-TestResult "Basic Connectivity" $false "No response from API"
            return $false
        }
    }
    catch {
        Write-TestResult "Basic Connectivity" $false "Connection failed: $($_.Exception.Message)" @{
            Exception = $_.Exception
            StackTrace = $_.ScriptStackTrace
            CollectionUrl = $CollectionUrl
        }
        return $false
    }
}

function Test-GetAdoProjectList {
    Write-TestHeader "Get-AdoProjectList Function"

    try {
        Write-Host "Testing Get-AdoProjectList function..." -ForegroundColor Gray

        # Clear any cached data first
        $projects = Get-AdoProjectList -RefreshCache -ErrorAction Stop

        if ($projects -is [array]) {
            Write-TestResult "Get-AdoProjectList" $true "Successfully retrieved $($projects.Count) projects" @{
                ProjectCount = $projects.Count
                SampleProjects = $projects | Select-Object -First 3 | ForEach-Object { $_.name }
            }
            return $true
        } else {
            Write-TestResult "Get-AdoProjectList" $false "Function did not return an array" @{
                ReturnedType = $projects.GetType().FullName
                ReturnedValue = $projects
            }
            return $false
        }
    }
    catch {
        Write-TestResult "Get-AdoProjectList" $false "Function failed: $($_.Exception.Message)" @{
            Exception = $_.Exception
            StackTrace = $_.ScriptStackTrace
            InnerException = $_.Exception.InnerException
        }
        return $false
    }
}

function Test-InvokeAdoRestDirectly {
    Write-TestHeader "Invoke-AdoRest Direct Testing"

    $testCases = @(
        @{ Method = "GET"; Path = "/_apis"; Description = "Root API endpoint" },
        @{ Method = "GET"; Path = "/_apis/projects?`$top=1"; Description = "Projects API (limited)" },
        @{ Method = "GET"; Path = "/_apis/process/processes"; Description = "Process templates" }
    )

    $allSuccess = $true

    foreach ($testCase in $testCases) {
        try {
            Write-Host "Testing $($testCase.Method) $($testCase.Path) - $($testCase.Description)..." -ForegroundColor Gray

            $response = Invoke-AdoRest $testCase.Method $testCase.Path -ErrorAction Stop

            if ($response) {
                Write-TestResult "Invoke-AdoRest $($testCase.Description)" $true "Success" @{
                    Method = $testCase.Method
                    Path = $testCase.Path
                    ResponseType = $response.GetType().FullName
                }
            } else {
                Write-TestResult "Invoke-AdoRest $($testCase.Description)" $false "No response returned"
                $allSuccess = $false
            }
        }
        catch {
            Write-TestResult "Invoke-AdoRest $($testCase.Description)" $false "Failed: $($_.Exception.Message)" @{
                Method = $testCase.Method
                Path = $testCase.Path
                Exception = $_.Exception
                StackTrace = $_.ScriptStackTrace
            }
            $allSuccess = $false
        }
    }

    return $allSuccess
}

function Test-InitializeAdoProjectMinimal {
    Write-TestHeader "Initialize-AdoProject Minimal Test"

    try {
        Write-Host "Testing Initialize-AdoProject with minimal parameters..." -ForegroundColor Gray
        Write-Host "NOTE: This will attempt to create a test project. Use with caution!" -ForegroundColor Yellow

        $testProjectName = "Gitlab2DevOps-Test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $testRepoName = "test-repo"

        Write-Host "Test project name: $testProjectName" -ForegroundColor Gray

        # Use WhatIf to avoid actually creating the project
        $result = Initialize-AdoProject -DestProject $testProjectName -RepoName $testRepoName -WhatIf -ErrorAction Stop

        Write-TestResult "Initialize-AdoProject (WhatIf)" $true "WhatIf mode completed successfully" @{
            TestProjectName = $testProjectName
            TestRepoName = $testRepoName
            WhatIfMode = $true
        }
        return $true
    }
    catch {
        Write-TestResult "Initialize-AdoProject (WhatIf)" $false "WhatIf test failed: $($_.Exception.Message)" @{
            Exception = $_.Exception
            StackTrace = $_.ScriptStackTrace
            TestProjectName = $testProjectName
        }
        return $false
    }
}

function Test-EnvironmentInfo {
    Write-TestHeader "Environment Information"

    $envInfo = @{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OS = [System.Environment]::OSVersion.ToString()
        Platform = [System.Environment]::OSVersion.Platform.ToString()
        Is64Bit = [System.Environment]::Is64BitOperatingSystem
        CurrentDirectory = Get-Location
        CollectionUrl = $CollectionUrl
        SkipCertificateCheck = $SkipCertificateCheck
        ScriptVersion = $script:ScriptVersion
        ModulesPath = $modulesPath
        ScriptRoot = $PSScriptRoot
    }

    Write-Host "Environment Details:" -ForegroundColor Gray
    $envInfo | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Gray }

    Write-TestResult "Environment Check" $true "Environment information collected"
    return $true
}

function Test-NetworkConnectivity {
    Write-TestHeader "Network Connectivity"

    try {
        $uri = [System.Uri]$CollectionUrl
        $hostName = $uri.Host
        $port = if ($uri.Port -ne -1) { $uri.Port } else { if ($uri.Scheme -eq "https") { 443 } else { 80 } }

        Write-Host "Testing network connectivity to ${hostName}:${port}..." -ForegroundColor Gray

        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectTask = $tcpClient.ConnectAsync($hostName, $port)
        $timeoutTask = [System.Threading.Tasks.Task]::Delay(5000) # 5 second timeout

        $completedTask = [System.Threading.Tasks.Task]::WhenAny($connectTask, $timeoutTask).Result

        if ($completedTask -eq $connectTask -and $connectTask.Status -eq "RanToCompletion") {
            Write-TestResult "Network Connectivity" $true "TCP connection successful to ${hostName}:${port}"
            $tcpClient.Close()
            return $true
        } else {
            Write-TestResult "Network Connectivity" $false "TCP connection failed or timed out to ${hostName}:${port}"
            return $false
        }
    }
    catch {
        Write-TestResult "Network Connectivity" $false "Network test failed: $($_.Exception.Message)"
        return $false
    }
}

function Generate-Report {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "TROUBLESHOOTING REPORT SUMMARY" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    $passedTests = ($script:TestResults | Where-Object { $_.Success }).Count
    $failedTests = ($script:TestResults | Where-Object { -not $_.Success }).Count
    $totalTests = $script:TestResults.Count

    Write-Host "Test Results: $passedTests/$totalTests passed" -ForegroundColor $(if ($passedTests -eq $totalTests) { "Green" } else { "Yellow" })

    if ($failedTests -gt 0) {
        Write-Host ""
        Write-Host "Failed Tests:" -ForegroundColor Red
        $script:TestResults | Where-Object { -not $_.Success } | ForEach-Object {
            Write-Host "  ❌ $($_.TestName): $($_.Message)" -ForegroundColor Red
        }

        Write-Host ""
        Write-Host "Common Issues and Solutions:" -ForegroundColor Yellow
        Write-Host "1. 'You cannot call a method on a null-valued expression':" -ForegroundColor Yellow
        Write-Host "   - Usually indicates Core.Rest module not properly initialized" -ForegroundColor Gray
        Write-Host "   - Check that Initialize-CoreRest was called before using Invoke-AdoRest" -ForegroundColor Gray
        Write-Host ""
        Write-Host "2. Authentication failures:" -ForegroundColor Yellow
        Write-Host "   - Verify Personal Access Token is valid and has correct permissions" -ForegroundColor Gray
        Write-Host "   - Ensure token hasn't expired" -ForegroundColor Gray
        Write-Host "   - Check that token has 'Read' permissions for projects" -ForegroundColor Gray
        Write-Host ""
        Write-Host "3. SSL/TLS certificate issues:" -ForegroundColor Yellow
        Write-Host "   - Use -SkipCertificateCheck for on-premise servers with self-signed certificates" -ForegroundColor Gray
        Write-Host "   - Verify certificate is valid and trusted" -ForegroundColor Gray
        Write-Host ""
        Write-Host "4. Network connectivity:" -ForegroundColor Yellow
        Write-Host "   - Ensure Azure DevOps server is accessible from this machine" -ForegroundColor Gray
        Write-Host "   - Check firewall and proxy settings" -ForegroundColor Gray
        Write-Host "   - Verify URL is correct (include /DefaultCollection for on-premise)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan

    # Save detailed report
    $reportPath = Join-Path $PSScriptRoot "troubleshooting-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $script:TestResults | ConvertTo-Json -Depth 5 | Out-File $reportPath -Encoding UTF8
    Write-Host "Detailed report saved to: $reportPath" -ForegroundColor Gray
}

# Main execution
Write-Host "Azure DevOps Troubleshooting Script v$($script:ScriptVersion)" -ForegroundColor Cyan
Write-Host "Started at: $(Get-Date)" -ForegroundColor Gray
Write-Host ""

# Run all tests
$tests = @(
    @{ Name = "Environment Info"; Function = "Test-EnvironmentInfo" },
    @{ Name = "Module Imports"; Function = "Test-ModuleImports" },
    @{ Name = "Network Connectivity"; Function = "Test-NetworkConnectivity" },
    @{ Name = "Core.Rest Initialization"; Function = "Test-CoreRestInitialization" },
    @{ Name = "Basic Connectivity"; Function = "Test-BasicConnectivity" },
    @{ Name = "Invoke-AdoRest Direct"; Function = "Test-InvokeAdoRestDirectly" },
    @{ Name = "Get-AdoProjectList"; Function = "Test-GetAdoProjectList" },
    @{ Name = "Initialize-AdoProject Minimal"; Function = "Test-InitializeAdoProjectMinimal" }
)

$overallSuccess = $true

foreach ($test in $tests) {
    try {
        $success = & $test.Function
        if (-not $success) { $overallSuccess = $false }
    }
    catch {
        Write-TestResult $test.Name $false "Test execution failed: $($_.Exception.Message)" @{
            Exception = $_.Exception
            StackTrace = $_.ScriptStackTrace
        }
        $overallSuccess = $false
    }
}

# Generate final report
Generate-Report

Write-Host ""
if ($overallSuccess) {
    Write-Host "🎉 All tests passed! Azure DevOps functions should work correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️ Some tests failed. Review the output above for troubleshooting guidance." -ForegroundColor Yellow
    exit 1
}