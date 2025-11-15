<#
.SYNOPSIS
    Azure DevOps module - Modular architecture loader.

.DESCRIPTION
    Loads all AzureDevOps sub-modules and exports their functions.
    
.NOTES
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Policy type IDs
$script:POLICY_REQUIRED_REVIEWERS = 'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd'
$script:POLICY_BUILD_VALIDATION   = '0609b952-1397-4640-95ec-e00a01b2f659'
$script:POLICY_COMMENT_RESOLUTION = 'c6a1889d-b943-48DE-8ECA-6E5AC81B08B6'
$script:POLICY_WORK_ITEM_LINK     = 'fd2167ab-b0be-447a-8ec8-39368250830e'
$script:POLICY_STATUS_CHECK       = 'caae6c6e-4c53-40e6-94f0-6d7410830a9b'

# Git security namespace
$script:NS_GIT = '2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87'
$script:GIT_BITS = @{
    GenericContribute      = 4
    ForcePush              = 8
    PullRequestContribute  = 262144
}
# Import Core.Rest FIRST so all functions are available for parameter validation and runtime usage
$migrationRoot = Split-Path $PSScriptRoot -Parent
$coreRestPath = Join-Path $migrationRoot "core\Core.Rest.psm1"
if (-not (Get-Module -Name 'Core.Rest') -and (Test-Path $coreRestPath)) {
    Import-Module -WarningAction SilentlyContinue $coreRestPath -Force -Global -ErrorAction Stop
}

$subModuleDir = $PSScriptRoot
$subModules = @('Core.psm1', 'Security.psm1', 'Projects.psm1', 'Repositories.psm1', 'Wikis.psm1', 'WorkItems.psm1', 'Dashboards.psm1')

foreach ($module in $subModules) {
    $modulePath = Join-Path $subModuleDir $module
    if (Test-Path $modulePath) {
        Import-Module -WarningAction SilentlyContinue $modulePath -Global -Force -ErrorAction Stop
    }
    else {
        Write-Warning "Sub-module not found: $modulePath"
    }
}

$allFunctions = @()
foreach ($module in $subModules) {
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($module)
    $moduleObj = Get-Module -Name $moduleName
    if ($moduleObj) { $allFunctions += $moduleObj.ExportedFunctions.Keys }
}

Export-ModuleMember -Function $allFunctions -Variable POLICY_*, NS_GIT, GIT_BITS
