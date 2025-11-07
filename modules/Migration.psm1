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
Import-Module (Join-Path $PSScriptRoot "Core.Rest.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "AzureDevOps.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "GitLab.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force -Global
Import-Module (Join-Path $PSScriptRoot "ConfigLoader.psm1") -Force -Global

# Import Migration sub-modules
$migrationModulePath = Join-Path $PSScriptRoot "Migration"
Import-Module (Join-Path $migrationModulePath "Core.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "Menu.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "ProjectInitialization.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "TeamPacks.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "SingleMigration.psm1") -Force -Global
Import-Module (Join-Path $migrationModulePath "BulkMigration.psm1") -Force -Global

# Re-export all functions from sub-modules for backward compatibility
Export-ModuleMember -Function @(
    # From Migration/Core.psm1
    'Get-PreparedProjects',
    'Get-CoreRestConfig', 
    'Get-CoreRestThreadParams',
    'Get-WikiTemplateContent',
    
    # From Migration/Menu.psm1
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu',
    
    # From Migration/ProjectInitialization.psm1
    'Initialize-AdoProject',
    
    # From Migration/TeamPacks.psm1
    'Initialize-BusinessInit',
    'Initialize-DevInit',
    'Initialize-SecurityInit',
    'Initialize-ManagementInit',
    
    # From Migration/SingleMigration.psm1
    'New-MigrationPreReport',
    'Invoke-SingleMigration',
    
    # From Migration/BulkMigration.psm1
    'Invoke-BulkPreparationWorkflow',
    'Invoke-BulkMigrationWorkflow',
    'Show-BulkMigrationStatus'
)
