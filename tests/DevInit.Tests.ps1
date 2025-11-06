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
    
    It "AzureDevOps module exports Ensure-AdoDevWiki" {
        $exports = Get-Command -Module AzureDevOps
        $exports.Name | Should -Contain "Ensure-AdoDevWiki"
    }
    
    It "AzureDevOps module exports Ensure-AdoDevDashboard" {
        $exports = Get-Command -Module AzureDevOps
        $exports.Name | Should -Contain "Ensure-AdoDevDashboard"
    }
    
    It "AzureDevOps module exports Ensure-AdoDevQueries" {
        $exports = Get-Command -Module AzureDevOps
        $exports.Name | Should -Contain "Ensure-AdoDevQueries"
    }
    
    It "AzureDevOps module exports Ensure-AdoRepoFiles" {
        $exports = Get-Command -Module AzureDevOps
        $exports.Name | Should -Contain "Ensure-AdoRepoFiles"
    }
}
