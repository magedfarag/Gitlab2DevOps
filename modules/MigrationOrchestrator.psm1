<#
.SYNOPSIS
    Backward compatibility wrapper for the migration orchestrator.

.DESCRIPTION
    The orchestrator logic is now provided by modules/Migration.psm1. This
    module simply imports the new orchestrator and re-exports all of its public
    functions so existing automation that referenced MigrationOrchestrator.psm1
    continues to work without code changes.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

$migrationModulePath = Join-Path $PSScriptRoot "Migration.psm1"
$migrationModule = Import-Module $migrationModulePath -Force -PassThru
$exportedFunctions = @()
if ($migrationModule -and $migrationModule.ExportedFunctions) {
    $exportedFunctions = $migrationModule.ExportedFunctions.Keys
}

Export-ModuleMember -Function $exportedFunctions
