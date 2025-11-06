<#
.SYNOPSIS
    Tests for HTML reporting functions in Logging module.

.DESCRIPTION
    Verifies HTML report generation works correctly for both individual
    migrations and overview dashboards.
#>

BeforeAll {
    # Import modules
    Import-Module "$PSScriptRoot\..\modules\Logging.psm1" -Force
    
    # Create test migrations folder structure
    $script:TestMigrationsDir = Join-Path ([System.IO.Path]::GetTempPath()) "html-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $TestMigrationsDir -Force | Out-Null
    
    # Create test project structure
    $testProject = Join-Path $TestMigrationsDir "TestProject\test-repo"
    New-Item -ItemType Directory -Path $testProject -Force | Out-Null
    
    # Create test migration-config.json
    $testConfig = @{
        ado_project = "TestProject"
        gitlab_project = "org/test-repo"
        gitlab_repo_name = "test-repo"
        migration_type = "SINGLE"
        status = "PREPARED"
        created_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        last_updated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    }
    $testConfig | ConvertTo-Json | Set-Content -Path (Join-Path $testProject "migration-config.json")
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestMigrationsDir) {
        Remove-Item -Path $script:TestMigrationsDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "HTML Reporting Functions" {
    Context "New-MigrationHtmlReport" {
        It "generates HTML report for a single migration" {
            $testProject = Join-Path $script:TestMigrationsDir "TestProject\test-repo"
            $reportPath = New-MigrationHtmlReport -ProjectPath $testProject
            
            $reportPath | Should -Not -BeNullOrEmpty
            Test-Path $reportPath | Should -Be $true
            
            # Verify HTML content
            $html = Get-Content -Path $reportPath -Raw
            $html | Should -Match "Migration Status: org/test-repo"
            $html | Should -Match "TestProject"
            $html | Should -Match "PREPARED"
        }
        
        It "creates reports directory if it doesn't exist" {
            $testProject = Join-Path $script:TestMigrationsDir "TestProject\test-repo"
            $reportsDir = Join-Path $testProject "reports"
            
            if (Test-Path $reportsDir) {
                Remove-Item -Path $reportsDir -Recurse -Force
            }
            
            $reportPath = New-MigrationHtmlReport -ProjectPath $testProject
            
            Test-Path $reportsDir | Should -Be $true
        }
        
        It "returns null for non-existent project" {
            $reportPath = New-MigrationHtmlReport -ProjectPath "C:\NonExistent\Path"
            
            $reportPath | Should -BeNullOrEmpty
        }
    }
    
    Context "New-MigrationsOverviewReport" {
        It "generates overview HTML report" {
            $reportPath = New-MigrationsOverviewReport -MigrationsPath $script:TestMigrationsDir
            
            $reportPath | Should -Not -BeNullOrEmpty
            Test-Path $reportPath | Should -Be $true
            
            # Verify HTML content
            $html = Get-Content -Path $reportPath -Raw
            $html | Should -Match "Migration Dashboard"
            $html | Should -Match "Total Projects"
            $html | Should -Match "auto-refreshes every 30 seconds"
        }
        
        It "includes all projects in overview" {
            $reportPath = New-MigrationsOverviewReport -MigrationsPath $script:TestMigrationsDir
            $html = Get-Content -Path $reportPath -Raw
            
            $html | Should -Match "org/test-repo"
            $html | Should -Match "TestProject"
        }
        
        It "generates stats correctly" {
            $reportPath = New-MigrationsOverviewReport -MigrationsPath $script:TestMigrationsDir
            $html = Get-Content -Path $reportPath -Raw
            
            # Should have at least 1 total project
            $html | Should -Match '<div class="value">1</div>'
        }
    }
    
    Context "HTML Template" {
        It "template file exists" {
            $templatePath = Join-Path $PSScriptRoot "..\modules\templates\migration-status.html"
            Test-Path $templatePath | Should -Be $true
        }
        
        It "template contains all required placeholders" {
            $templatePath = Join-Path $PSScriptRoot "..\modules\templates\migration-status.html"
            $template = Get-Content -Path $templatePath -Raw
            
            $template | Should -Match "{{REPORT_TITLE}}"
            $template | Should -Match "{{REPORT_SUBTITLE}}"
            $template | Should -Match "{{REFRESH_INFO}}"
            $template | Should -Match "{{SUMMARY_STATS}}"
            $template | Should -Match "{{PROJECT_CARDS}}"
            $template | Should -Match "{{GENERATION_TIME}}"
        }
    }
    
    Context "Navigation Links" {
        It "overview report contains clickable project cards" {
            $reportPath = New-MigrationsOverviewReport -MigrationsPath $script:TestMigrationsDir
            $html = Get-Content -Path $reportPath -Raw
            
            # Should have onclick handlers for navigation
            $html | Should -Match "onclick="
            $html | Should -Match "cursor: pointer"
        }
        
        It "overview report contains links to individual reports" {
            $reportPath = New-MigrationsOverviewReport -MigrationsPath $script:TestMigrationsDir
            $html = Get-Content -Path $reportPath -Raw
            
            # Should contain relative paths to project reports
            $html | Should -Match "migration-status\.html"
        }
        
        It "individual report contains back navigation link" {
            $testProject = Join-Path $script:TestMigrationsDir "TestProject\test-repo"
            $reportPath = New-MigrationHtmlReport -ProjectPath $testProject
            $html = Get-Content -Path $reportPath -Raw
            
            # Should have back link to overview
            $html | Should -Match "Back to Migration Overview"
            $html | Should -Match "index\.html"
        }
    }
}
