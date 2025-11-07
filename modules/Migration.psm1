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
Import-Module (Join-Path $PSScriptRoot "adapters\AzureDevOps.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "adapters\GitLab.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "core\Logging.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "core\ConfigLoader.psm1") -Force -Global

# Import Migration sub-modules
$migrationModulePath = Join-Path $PSScriptRoot "Migration"
Import-Module (Join-Path $migrationModulePath "Core\Core.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "Menu\Menu.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "Initialization\ProjectInitialization.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "TeamPacks\TeamPacks.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "Workflows\SingleMigration.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "Workflows\BulkMigration.psm1") -Force -Global

# Re-export all functions from sub-modules for backward compatibility
Export-ModuleMember -Function @(
    # From Migration/Core/Core.psm1
    'Get-PreparedProjects',
    'Get-CoreRestConfig', 
    'Get-CoreRestThreadParams',
    'Get-WikiTemplateContent',
    
    # From Migration/Menu/Menu.psm1
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu',
    
    # From Migration/Initialization/ProjectInitialization.psm1
    'Initialize-AdoProject',
    
    # From Migration/TeamPacks/TeamPacks.psm1
    'Initialize-BusinessInit',
    'Initialize-DevInit',
    'Initialize-SecurityInit',
    'Initialize-ManagementInit',
    
    # From Migration/Workflows/SingleMigration.psm1
    'New-MigrationPreReport',
    'Invoke-SingleMigration',
    
    # From Migration/Workflows/BulkMigration.psm1
    'Invoke-BulkPreparationWorkflow',
    'Invoke-BulkMigrationWorkflow',
    'Show-BulkMigrationStatus'
)
