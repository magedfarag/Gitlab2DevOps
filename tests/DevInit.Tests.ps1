BeforeAll {
    # Import the main script to test CLI integration
    $mainScript = Join-Path (Split-Path $PSScriptRoot -Parent) "Gitlab2DevOps.ps1"
    $cliDocs = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\cli-usage.md"
    
    # Import Migration module to test exports
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Migration.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\AzureDevOps.psm1") -Force
}

Describe "DevInit CLI Mode" {
    It "Main script supports DevInit in ValidateSet and switch" {
        $scriptContent = Get-Content $mainScript -Raw
        $scriptContent | Should -Match "ValidateSet.*'DevInit'"
        $scriptContent | Should -Match "'DevInit'\s*\{"
    }
    
    It "CLI docs include DevInit mode and project types" {
        $docsContent = Get-Content $cliDocs -Raw
        $docsContent | Should -Match "DevInit"
        $docsContent | Should -Match "dotnet|node|python|java|all"
    }
}

Describe "DevInit Module Exports" {
    It "Migration module exports Initialize-DevInit" {
        $exports = Get-Command -Module Migration
        $exports.Name | Should -Contain "Initialize-DevInit"
    }
    
    It "Wikis sub-module exports Ensure-AdoDevWiki" {
        Get-Command Ensure-AdoDevWiki -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Dashboards sub-module exports Ensure-AdoDevDashboard" {
        Get-Command Ensure-AdoDevDashboard -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "WorkItems sub-module exports Ensure-AdoDevQueries" {
        Get-Command Ensure-AdoDevQueries -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Repositories sub-module exports Ensure-AdoRepoFiles" {
        Get-Command Ensure-AdoRepoFiles -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
