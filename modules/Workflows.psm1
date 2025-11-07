<#
.SYNOPSIS
    Compatibility wrapper for migration workflow functions.

.DESCRIPTION
    Single and bulk migration workflows now live under modules/Migration.
    This wrapper imports the new modules and re-exports the public workflow
    functions so existing imports keep working.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

$migrationModuleDir = Join-Path $PSScriptRoot "Migration"
Import-Module (Join-Path $migrationModuleDir "SingleMigration.psm1") -Force -Global
Import-Module (Join-Path $migrationModuleDir "BulkMigration.psm1") -Force -Global

Export-ModuleMember -Function @(
    'New-MigrationPreReport',
    'Invoke-SingleMigration',
    'Invoke-BulkPreparationWorkflow',
    'Invoke-BulkMigrationWorkflow',
    'Show-BulkMigrationStatus'
)
