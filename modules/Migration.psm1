<#
.SYNOPSIS
    GitLab to Azure DevOps migration orchestration.

.DESCRIPTION
    This module provides the main orchestration layer for migrating GitLab projects
    to Azure DevOps. Now refactored into focused sub-modules for better maintainability.

.NOTES
    Requires: Core.Rest, GitLab, AzureDevOps, Logging modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import required modules
Import-Module (Join-Path $PSScriptRoot "core\Core.Rest.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "AzureDevOps\AzureDevOps.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "GitLab\GitLab.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "core\Logging.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "core\ConfigLoader.psm1") -Force -Global

# Import Migration sub-modules
$migrationModulePath = Join-Path $PSScriptRoot "Migration"
$subModules = @(
    @{ Path = "Core\Core.psm1"; Name = "Core" }
    @{ Path = "Menu\Menu.psm1"; Name = "Menu" }
    @{ Path = "Initialization\ProjectInitialization.psm1"; Name = "ProjectInitialization" }
    @{ Path = "TeamPacks\TeamPacks.psm1"; Name = "TeamPacks" }
    @{ Path = "Workflows\SingleMigration.psm1"; Name = "SingleMigration" }
    @{ Path = "Workflows\BulkMigration.psm1"; Name = "BulkMigration" }
)

foreach ($module in $subModules) {
    $modulePath = Join-Path $migrationModulePath $module.Path
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -Global -ErrorAction Stop
    }
    else {
        Write-Warning "Migration sub-module not found: $modulePath"
    }
}

# Collect all exported functions from loaded sub-modules
$allFunctions = @()
foreach ($module in $subModules) {
    $moduleObj = Get-Module -Name $module.Name -ErrorAction SilentlyContinue
    if ($moduleObj) {
        $allFunctions += $moduleObj.ExportedFunctions.Keys
    }
}

# Re-export all functions from sub-modules
Export-ModuleMember -Function $allFunctions
