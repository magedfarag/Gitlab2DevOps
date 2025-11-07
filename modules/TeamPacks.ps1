<#
.SYNOPSIS
    Compatibility shim for team pack initialization functions.

.DESCRIPTION
    The concrete implementations now live in modules/Migration/TeamPacks.psm1.
    This script simply imports that module so existing dot-sourcing continues
    to expose the same functions.
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

$migrationModuleDir = Join-Path $PSScriptRoot "Migration"
Import-Module (Join-Path $migrationModuleDir "TeamPacks.psm1") -Force -Global
