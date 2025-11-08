#requires -Modules Pester
<#!
.SYNOPSIS
    Idempotency tests for Initialize-BusinessInit orchestration.

.DESCRIPTION
    Mocks REST-facing functions to validate that Initialize-BusinessInit performs
    the expected calls exactly once and handles reporting without depending on external systems.
!#>

BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $moduleRoot = Join-Path $projectRoot 'modules'

    Import-Module (Join-Path $moduleRoot 'core\Core.Rest.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'core\Logging.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'adapters\AzureDevOps.psm1') -Force
    Import-Module (Join-Path $moduleRoot 'Migration\Migration.psm1') -Force
}

Describe "Initialize-BusinessInit idempotency" {
    BeforeEach {
        $testProject = "PesterBizProj"

        # Mock project existence
        Mock -ModuleName Migration Test-AdoProjectExists { $true }

        # Mock ADO REST project GET used inside Initialize-BusinessInit
        Mock -ModuleName Migration Invoke-AdoRest {
            # Return minimal project payload when querying projects
            return @{ id = "proj-123" }
        }

        # Mock wiki ensure to return a deterministic wiki id
        Mock -ModuleName Migration Measure-Adoprojectwiki { @{ id = "wiki-001" } }

        # Mock business assets to be no-ops but track calls
        Mock -ModuleName Migration Measure-Adobusinesswiki { }
        Mock -ModuleName Migration Measure-Adobusinessqueries { }
        Mock -ModuleName Migration Measure-Adoiterations { }
        Mock -ModuleName Migration Search-Adodashboard { }
        Mock -ModuleName Migration Ensure-AdoSharedQueries { }
        Mock -ModuleName Migration Measure-Adocommontags { }

        # Mock reporting paths and writer
        Mock -ModuleName Migration Get-ProjectPaths {
            $base = Join-Path $TestDrive $testProject
            $reports = Join-Path $base 'reports'
            New-Item -ItemType Directory -Path $reports -Force | Out-Null
            return @{ reportsDir = $reports; logsDir = (Join-Path $base 'logs'); repositoryDir = (Join-Path $base 'repository') }
        }
        Mock -ModuleName Migration Write-MigrationReport { param($ReportFile,$Data) Set-Content -Path $ReportFile -Value ($Data | ConvertTo-Json -Depth 5) }
    }

    It "calls key ensure functions exactly once and writes a summary report" {
        Initialize-BusinessInit -DestProject "PesterBizProj"

        Assert-MockCalled -ModuleName Migration Measure-Adoprojectwiki -Times 1 -Exactly
        Assert-MockCalled -ModuleName Migration Measure-Adobusinesswiki -Times 1 -Exactly
        Assert-MockCalled -ModuleName Migration Measure-Adobusinessqueries -Times 1 -Exactly
        Assert-MockCalled -ModuleName Migration Measure-Adoiterations -Times 1 -Exactly
        Assert-MockCalled -ModuleName Migration Search-Adodashboard -Times 1 -Exactly
        Assert-MockCalled -ModuleName Migration Measure-Adocommontags -Times 1 -Exactly

        # Validate report was written under TestDrive
        $reportPath = Get-ChildItem -Path (Join-Path $TestDrive 'PesterBizProj\reports') -Filter 'business-init-summary.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        $reportPath | Should -Not -BeNullOrEmpty

        $json = Get-Content -Path $reportPath.FullName -Raw | ConvertFrom-Json
        $json.ado_project | Should -Be "PesterBizProj"
        $json.dashboard_created | Should -BeTrue
    }
}

AfterAll {
    Remove-Module Migration -Force -ErrorAction SilentlyContinue
    Remove-Module AzureDevOps -Force -ErrorAction SilentlyContinue
    Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

