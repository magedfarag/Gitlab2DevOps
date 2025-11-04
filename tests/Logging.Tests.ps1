#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for Logging module.

.DESCRIPTION
    Tests for migration logging, reporting, and observability functions.
#>

BeforeAll {
    # Import the module to test
    $modulePath = Join-Path $PSScriptRoot ".." "modules" "Logging.psm1"
    Import-Module $modulePath -Force
    
    # Create temp directory for test files
    $script:testDir = Join-Path $TestDrive "test-migrations"
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}

Describe "Get-MigrationsDirectory" {
    It "Should return migrations directory path" {
        $dir = Get-MigrationsDirectory
        $dir | Should -Not -BeNullOrEmpty
        $dir | Should -Match 'migrations$'
    }
}

Describe "Get-ProjectPaths" {
    Context "When getting paths for project" {
        It "Should return all required paths" {
            $paths = Get-ProjectPaths -ProjectName "test-project"
            
            $paths.projectDir | Should -Match 'test-project$'
            $paths.reportsDir | Should -Match 'reports$'
            $paths.logsDir | Should -Match 'logs$'
            $paths.repositoryDir | Should -Match 'repository$'
        }
        
        It "Should handle project names with special characters" {
            $paths = Get-ProjectPaths -ProjectName "my-project_v2"
            $paths.projectDir | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "New-LogFilePath" {
    It "Should create timestamped log filename" {
        $logPath = New-LogFilePath -ProjectName "test-project" -Operation "migration"
        
        $logPath | Should -Match 'migration-\d{8}-\d{6}\.log$'
        $logPath | Should -Match 'test-project'
    }
    
    It "Should support different operations" {
        $logPath = New-LogFilePath -ProjectName "test-project" -Operation "preparation"
        $logPath | Should -Match 'preparation-\d{8}-\d{6}\.log$'
    }
}

Describe "New-ReportFilePath" {
    It "Should create report filename" {
        $reportPath = New-ReportFilePath -ProjectName "test-project" -ReportType "preflight"
        
        $reportPath | Should -Match 'preflight-report\.json$'
        $reportPath | Should -Match 'test-project'
    }
    
    It "Should support different report types" {
        $reportPath = New-ReportFilePath -ProjectName "test-project" -ReportType "migration"
        $reportPath | Should -Match 'migration-report\.json$'
    }
}

Describe "Write-MigrationLog" {
    Context "When writing to log file" {
        BeforeEach {
            $script:logFile = Join-Path $testDir "test.log"
        }
        
        AfterEach {
            if (Test-Path $logFile) {
                Remove-Item $logFile -Force
            }
        }
        
        It "Should create log file with message" {
            Write-MigrationLog -LogFile $logFile -Message "Test message" -Level "INFO"
            
            Test-Path $logFile | Should -Be $true
            $content = Get-Content $logFile -Raw
            $content | Should -Match "Test message"
            $content | Should -Match "\[INFO\]"
        }
        
        It "Should append to existing log file" {
            Write-MigrationLog -LogFile $logFile -Message "First message" -Level "INFO"
            Write-MigrationLog -LogFile $logFile -Message "Second message" -Level "INFO"
            
            $content = Get-Content $logFile -Raw
            $content | Should -Match "First message"
            $content | Should -Match "Second message"
        }
        
        It "Should include timestamp" {
            Write-MigrationLog -LogFile $logFile -Message "Timestamped" -Level "INFO"
            
            $content = Get-Content $logFile -Raw
            $content | Should -Match '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
        }
    }
}

Describe "Write-MigrationReport" {
    Context "When writing JSON report" {
        BeforeEach {
            $script:reportFile = Join-Path $testDir "test-report.json"
        }
        
        AfterEach {
            if (Test-Path $reportFile) {
                Remove-Item $reportFile -Force
            }
        }
        
        It "Should create JSON report file" {
            $data = @{
                project = "test-project"
                status = "SUCCESS"
                timestamp = (Get-Date).ToString('o')
            }
            
            Write-MigrationReport -ReportFile $reportFile -Data $data
            
            Test-Path $reportFile | Should -Be $true
            $content = Get-Content $reportFile | ConvertFrom-Json
            $content.project | Should -Be "test-project"
            $content.status | Should -Be "SUCCESS"
        }
        
        It "Should handle nested objects" {
            $data = @{
                project = "test"
                metadata = @{
                    size_mb = 150
                    lfs_enabled = $true
                }
            }
            
            Write-MigrationReport -ReportFile $reportFile -Data $data
            
            $content = Get-Content $reportFile | ConvertFrom-Json
            $content.metadata.size_mb | Should -Be 150
            $content.metadata.lfs_enabled | Should -Be $true
        }
    }
}

Describe "Write-MigrationMessage" {
    It "Should display INFO message" {
        { Write-MigrationMessage -Message "Test info" -Level "INFO" } | Should -Not -Throw
    }
    
    It "Should display WARN message" {
        { Write-MigrationMessage -Message "Test warning" -Level "WARN" } | Should -Not -Throw
    }
    
    It "Should display ERROR message" {
        { Write-MigrationMessage -Message "Test error" -Level "ERROR" } | Should -Not -Throw
    }
    
    It "Should display SUCCESS message" {
        { Write-MigrationMessage -Message "Test success" -Level "SUCCESS" } | Should -Not -Throw
    }
    
    It "Should display DEBUG message" {
        { Write-MigrationMessage -Message "Test debug" -Level "DEBUG" } | Should -Not -Throw
    }
    
    It "Should default to INFO level" {
        { Write-MigrationMessage -Message "Default level" } | Should -Not -Throw
    }
}

Describe "New-RunManifest" {
    Context "When creating run manifest" {
        It "Should create manifest with required fields" {
            $manifest = New-RunManifest `
                -Mode "Migrate" `
                -Source "group/project" `
                -Project "TestProject"
            
            $manifest.run_id | Should -Not -BeNullOrEmpty
            $manifest.mode | Should -Be "Migrate"
            $manifest.source | Should -Be "group/project"
            $manifest.project | Should -Be "TestProject"
            $manifest.start_time | Should -Not -BeNullOrEmpty
            $manifest.status | Should -Be "RUNNING"
        }
        
        It "Should include parameters when provided" {
            $params = @{
                Force = $true
                Replace = $false
            }
            
            $manifest = New-RunManifest `
                -Mode "Migrate" `
                -Source "group/project" `
                -Parameters $params
            
            $manifest.parameters.Force | Should -Be $true
            $manifest.parameters.Replace | Should -Be $false
        }
        
        It "Should include environment information" {
            $manifest = New-RunManifest -Mode "Preflight" -Source "test/repo"
            
            $manifest.environment.ps_version | Should -Not -BeNullOrEmpty
            $manifest.environment.os | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Update-RunManifest" {
    Context "When updating manifest status" {
        BeforeEach {
            $script:manifestFile = Join-Path $testDir "run-manifest-test.json"
            $manifest = @{
                run_id = "test-guid-1234"
                start_time = (Get-Date).AddMinutes(-5).ToString('o')
                status = "RUNNING"
            }
            Write-MigrationReport -ReportFile $manifestFile -Data $manifest
        }
        
        AfterEach {
            if (Test-Path $manifestFile) {
                Remove-Item $manifestFile -Force
            }
        }
        
        It "Should update status to SUCCESS" {
            Update-RunManifest -ManifestFile $manifestFile -Status "SUCCESS"
            
            $updated = Get-Content $manifestFile | ConvertFrom-Json
            $updated.status | Should -Be "SUCCESS"
            $updated.end_time | Should -Not -BeNullOrEmpty
            $updated.duration_seconds | Should -BeGreaterThan 0
        }
        
        It "Should update status to FAILED with errors" {
            $errors = @("Error 1", "Error 2")
            Update-RunManifest -ManifestFile $manifestFile -Status "FAILED" -Errors $errors
            
            $updated = Get-Content $manifestFile | ConvertFrom-Json
            $updated.status | Should -Be "FAILED"
            $updated.errors.Count | Should -Be 2
        }
        
        It "Should include warnings" {
            $warnings = @("Warning 1")
            Update-RunManifest -ManifestFile $manifestFile -Status "SUCCESS" -Warnings $warnings
            
            $updated = Get-Content $manifestFile | ConvertFrom-Json
            $updated.warnings.Count | Should -Be 1
        }
    }
}

Describe "New-MigrationSummary" {
    It "Should create summary with all fields" {
        $startTime = Get-Date
        $endTime = $startTime.AddMinutes(5)
        
        $summary = New-MigrationSummary `
            -SourceProject "group/project" `
            -DestProject "ADOProject" `
            -Status "SUCCESS" `
            -StartTime $startTime `
            -EndTime $endTime
        
        $summary.source_project | Should -Be "group/project"
        $summary.destination_project | Should -Be "ADOProject"
        $summary.status | Should -Be "SUCCESS"
        $summary.duration_minutes | Should -BeGreaterThan 0
    }
    
    It "Should include additional data" {
        $additionalData = @{
            commits_migrated = 150
            branches_migrated = 5
        }
        
        $summary = New-MigrationSummary `
            -SourceProject "test/repo" `
            -DestProject "Test" `
            -Status "SUCCESS" `
            -StartTime (Get-Date) `
            -EndTime (Get-Date).AddMinutes(1) `
            -AdditionalData $additionalData
        
        $summary.commits_migrated | Should -Be 150
        $summary.branches_migrated | Should -Be 5
    }
}

Describe "Module Exports" {
    It "Should export Get-MigrationsDirectory" {
        Get-Command Get-MigrationsDirectory -Module Logging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export Write-MigrationLog" {
        Get-Command Write-MigrationLog -Module Logging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export Write-MigrationReport" {
        Get-Command Write-MigrationReport -Module Logging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export New-RunManifest" {
        Get-Command New-RunManifest -Module Logging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export Update-RunManifest" {
        Get-Command Update-RunManifest -Module Logging -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

AfterAll {
    # Clean up
    Remove-Module Logging -Force -ErrorAction SilentlyContinue
    if (Test-Path $testDir) {
        Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
