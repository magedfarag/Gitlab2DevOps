<#
.SYNOPSIS
    Compatibility wrapper for Initialize-AdoProject.

.DESCRIPTION
    The full project initialization implementation now resides in
    modules/Migration/ProjectInitialization.psm1. This wrapper simply imports
    that module so existing scripts that import modules/Initialization.psm1
    continue to function without modification.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

$migrationModuleDir = Join-Path $PSScriptRoot "Migration"
Import-Module (Join-Path $migrationModuleDir "ProjectInitialization.psm1") -Force -Global

Export-ModuleMember -Function 'Initialize-AdoProject'
