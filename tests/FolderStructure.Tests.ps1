#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }

BeforeAll {
    # Import required modules
    Import-Module (Join-Path $PSScriptRoot "..\modules\core\Logging.psm1") -Force
}

Describe "v2.1.0 Folder Structure Validation" {
    
    Context "Single Project Migration Structure" {
        BeforeAll {
            $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "folder-structure-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $originalLocation = Get-Location
            Set-Location $testRoot
            
            # Create test directories
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        }
        
        AfterAll {
            Set-Location $originalLocation
            if (Test-Path $testRoot) {
                Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
            }
        }
        
        It "Should create v2.1.0 self-contained structure with correct directories" {
            # Get paths using new parameter set
            $paths = Get-ProjectPaths -AdoProject "TestAdoProject" -GitLabProject "test-gitlab-repo"
            
            # Verify structure
            Test-Path $paths.projectDir | Should -Be $true  # migrations/TestAdoProject/
            Test-Path $paths.gitlabDir | Should -Be $true   # migrations/TestAdoProject/test-gitlab-repo/
            Test-Path $paths.reportsDir | Should -Be $true  # migrations/TestAdoProject/reports/
            Test-Path $paths.logsDir | Should -Be $true     # migrations/TestAdoProject/logs/
            
            # Verify GitLab subfolder does NOT have logs/ directory
            $gitlabLogsDir = Join-Path $paths.gitlabDir "logs"
            Test-Path $gitlabLogsDir | Should -Be $false
        }
        
        It "Should return correct paths in hashtable" {
            $paths = Get-ProjectPaths -AdoProject "AnotherProject" -GitLabProject "another-repo"
            
            $paths.Keys | Should -Contain 'projectDir'
            $paths.Keys | Should -Contain 'gitlabDir'
            $paths.Keys | Should -Contain 'reportsDir'
            $paths.Keys | Should -Contain 'logsDir'
            $paths.Keys | Should -Contain 'repositoryDir'
            $paths.Keys | Should -Contain 'configFile'
            
            # Verify path relationships
            $paths.gitlabDir | Should -BeLike "$($paths.projectDir)*"
            $paths.reportsDir | Should -BeLike "$($paths.projectDir)*"
            $paths.logsDir | Should -BeLike "$($paths.projectDir)*"
            $paths.repositoryDir | Should -BeLike "$($paths.gitlabDir)*"
            $paths.configFile | Should -BeLike "$($paths.projectDir)*"
        }
    }
    
    Context "Bulk Migration Structure" {
        BeforeAll {
            $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "bulk-structure-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $originalLocation = Get-Location
            Set-Location $testRoot
            
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        }
        
        AfterAll {
            Set-Location $originalLocation
            if (Test-Path $testRoot) {
                Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
            }
        }
        
        It "Should create bulk migration structure without GitLab project" {
            $bulkPaths = Get-BulkProjectPaths -AdoProject "BulkProject"
            
            Test-Path $bulkPaths.containerDir | Should -Be $true
            Test-Path $bulkPaths.reportsDir | Should -Be $true
            Test-Path $bulkPaths.logsDir | Should -Be $true
            
            $bulkPaths.Keys | Should -Not -Contain 'gitlabDir'
            $bulkPaths.Keys | Should -Not -Contain 'repositoryDir'
        }
        
        It "Should create bulk migration structure WITH GitLab project" {
            $bulkPaths = Get-BulkProjectPaths -AdoProject "BulkProject" -GitLabProject "bulk-repo"
            
            Test-Path $bulkPaths.containerDir | Should -Be $true
            Test-Path $bulkPaths.gitlabDir | Should -Be $true
            Test-Path $bulkPaths.reportsDir | Should -Be $true
            Test-Path $bulkPaths.logsDir | Should -Be $true
            
            # Verify GitLab subfolder does NOT have logs/ directory
            $gitlabLogsDir = Join-Path $bulkPaths.gitlabDir "logs"
            Test-Path $gitlabLogsDir | Should -Be $false
        }
    }
    
    Context "Legacy Structure (Backward Compatibility)" {
        BeforeAll {
            $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "legacy-structure-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
            $originalLocation = Get-Location
            Set-Location $testRoot
            
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        }
        
        AfterAll {
            Set-Location $originalLocation
            if (Test-Path $testRoot) {
                Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue
            }
        }
        
        It "Should create legacy flat structure when using ProjectName parameter" {
            $paths = Get-ProjectPaths -ProjectName "legacy-project"
            
            # Legacy structure has logs/ at project level
            Test-Path $paths.projectDir | Should -Be $true
            Test-Path $paths.reportsDir | Should -Be $true
            Test-Path $paths.logsDir | Should -Be $true
            
            # Legacy doesn't have gitlabDir or configFile
            $paths.Keys | Should -Not -Contain 'gitlabDir'
            $paths.Keys | Should -Not -Contain 'configFile'
        }
    }
}
