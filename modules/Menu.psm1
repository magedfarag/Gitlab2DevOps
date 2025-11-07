<#
.SYNOPSIS
    Compatibility wrapper for the migration menu module.

.DESCRIPTION
    The interactive menu logic now lives under modules/Migration/Menu.psm1.
    This wrapper keeps the original module path working by importing the new
    implementation and re-exporting the public functions.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

$migrationModuleDir = Join-Path $PSScriptRoot "Migration"
Import-Module (Join-Path $migrationModuleDir "Menu.psm1") -Force -Global

Export-ModuleMember -Function @(
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu'
)
