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

# Import Migration sub-modules (without -Global to allow re-exporting)
$migrationModulePath = Join-Path $PSScriptRoot "Migration"
$subModules = @(
    @{ Path = "Core\MigrationCore.psm1"; Name = "MigrationCore" }
    @{ Path = "Menu\Menu.psm1"; Name = "Menu" }
    @{ Path = "Initialization\ProjectInitialization.psm1"; Name = "ProjectInitialization" }
    @{ Path = "TeamPacks\TeamPacks.psm1"; Name = "TeamPacks" }
    @{ Path = "Workflows\SingleMigration.psm1"; Name = "SingleMigration" }
    @{ Path = "Workflows\BulkMigration.psm1"; Name = "BulkMigration" }
)

$allFunctions = @()
foreach ($module in $subModules) {
    $modulePath = Join-Path $migrationModulePath $module.Path
    if (Test-Path $modulePath) {
        # Import in current scope (not Global) so we can re-export
        Import-Module $modulePath -Force -ErrorAction Stop
        
        # Collect functions from this module
        $moduleObj = Get-Module -Name $module.Name
        if ($moduleObj) {
            foreach ($funcName in $moduleObj.ExportedFunctions.Keys) {
                if ($allFunctions -notcontains $funcName) {
                    $allFunctions += $funcName
                }
            }
        }
    }
    else {
        Write-Warning "Migration sub-module not found: $modulePath"
    }
}

# Re-export all collected functions
if ($allFunctions.Count -gt 0) {
    Export-ModuleMember -Function $allFunctions
}
else {
    Write-Warning "No functions collected from Migration sub-modules"
}
