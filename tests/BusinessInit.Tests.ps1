#Requires -Modules Pester
<#!
.SYNOPSIS
    Tests for BusinessInit CLI mode and module exports.

.DESCRIPTION
    Verifies that BusinessInit mode is documented and wired into the CLI, and that
    the Migration and AzureDevOps modules export the new functions for business initialization.
!#>

BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $moduleRoot = Join-Path $projectRoot 'modules'
    Import-Module (Join-Path $moduleRoot 'Migration\Migration.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'adapters\AzureDevOps.psm1') -Force
}

Describe "BusinessInit CLI Mode" {
    It "Main script supports BusinessInit in ValidateSet and switch" {
        $scriptPath = Join-Path $PSScriptRoot '..' 'Gitlab2DevOps.ps1'
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "BusinessInit"
        $content | Should -Match "Initialize-BusinessInit"
        $content | Should -Match "-Project 'MyProject'"
    }

    It "CLI docs include BusinessInit mode and output path" {
        $docPath = Join-Path $PSScriptRoot '..' 'docs' 'cli-usage.md'
        $doc = Get-Content $docPath -Raw
        $doc | Should -Match "BusinessInit"
        $doc | Should -Match "business-init-summary.json"
        $doc | Should -Match "Provision business-facing assets"
    }
}

Describe "BusinessInit Module Exports" {
    It "Migration module exports Initialize-BusinessInit" {
        Get-Command Initialize-BusinessInit -Module Migration -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Wikis sub-module exports Measure-Adobusinesswiki" {
        Get-Command Measure-Adobusinesswiki -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "WorkItems sub-module exports Measure-Adobusinessqueries" {
        Get-Command Measure-Adobusinessqueries -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

AfterAll {
    Remove-Module Migration -Force -ErrorAction SilentlyContinue
    Remove-Module AzureDevOps -Force -ErrorAction SilentlyContinue
}

