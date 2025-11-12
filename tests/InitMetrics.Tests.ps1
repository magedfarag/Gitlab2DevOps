# Pester tests for Ensure-AdoIteration and Ensure-AdoQuery idempotency and InitMetrics

Describe 'Init metrics and idempotent ensures' {
    BeforeAll {
        # Import modules under test
        $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) '..\modules\core'
        Import-Module (Resolve-Path "modules\core\Core.Rest.psm1") -Force -ErrorAction Stop
        # Dot-source AzureDevOps module files to expose internal helpers for testing
        . (Resolve-Path "modules\AzureDevOps\Projects.psm1")
        . (Resolve-Path "modules\AzureDevOps\WorkItems.psm1")
    }

    BeforeEach {
    # Ensure metrics are initialized fresh
    Initialize-CoreRest -CollectionUrl 'https://dev.azure.com/fake' -AdoPat 'fake' -GitLabBaseUrl 'https://gitlab.fake' -GitLabToken 'fake' -LogRestCalls:$false | Out-Null
    Initialize-InitMetrics -Reset | Out-Null
    }

    Context 'Ensure-AdoIteration' {
        It 'skips when iteration already exists and increments skipped counter' {
            # Mock GET to return existing node on first GET
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'classificationnodes/iterations' } -MockWith { @{ id = 'iter-1'; name = 'Sprint 1' } }

            $res = Ensure-AdoIteration -Project 'MyProj' -Name 'Sprint 1' -StartDate (Get-Date) -FinishDate (Get-Date).AddDays(14) -Team 'MyProj Team'
            $res.Created | Should -BeFalse
            $metrics = Get-InitMetrics
            $metrics.iterations.skipped | Should -Be 1
        }

        It 'creates iteration when not present and increments created counter' {
            # First GET returns $null, POST returns created object
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'classificationnodes/iterations' } -MockWith { $null }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'POST' -and $Path -match 'classificationnodes/iterations' } -MockWith { @{ id = 'iter-new'; identifier = 'ident-1'; name = 'Sprint X' } }

            $res = Ensure-AdoIteration -Project 'MyProj' -Name 'Sprint X' -StartDate (Get-Date) -FinishDate (Get-Date).AddDays(14)
            $res.Created | Should -BeTrue
            $metrics = Get-InitMetrics
            $metrics.iterations.created | Should -Be 1
        }

        It 'handles duplicate create error by retrieving existing and increments skipped' {
            # Initial GET returns $null, POST throws duplicate, GET returns existing
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'classificationnodes/iterations' } -MockWith { $null }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'POST' -and $Path -match 'classificationnodes/iterations' } -MockWith { throw [System.Exception]::new('ClassificationNodeDuplicateNameException: duplicate') }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'classificationnodes/iterations/.+' } -MockWith { @{ id = 'iter-dup'; name = 'Sprint D' } }

            $res = Ensure-AdoIteration -Project 'MyProj' -Name 'Sprint D' -StartDate (Get-Date) -FinishDate (Get-Date).AddDays(14)
            $res.Created | Should -BeFalse
            $metrics = Get-InitMetrics
            $metrics.iterations.skipped | Should -Be 1
        }
    }

    Context 'Ensure-AdoQuery' {
        It 'skips when child exists in parent folder and increments skipped counter' {
            # Mock GET parent children to include child and mock POST as duplicate (server would reject create)
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'wit/queries' -and $Path -match '\$depth=1' } -MockWith { @{ children = @(@{ name = 'MyQuery'; isFolder = $false }) } }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'POST' -and $Path -match 'wit/queries' } -MockWith { throw [System.Exception]::new('409: already exists') }

            $res = Ensure-AdoQuery -Project 'MyProj' -ParentPath 'Shared Queries' -Name 'MyQuery' -IsFolder:$false
            $res.Created | Should -BeFalse
            $metrics = Get-InitMetrics
            $metrics.queries.skipped | Should -Be 1
        }

        It 'creates query when not present and increments created counter' {
            # Parent GET returns no children, POST returns created node
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'wit/queries' -and $Path -match '\$depth=1' } -MockWith { @{ children = @() } }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'POST' -and $Path -match 'wit/queries' } -MockWith { @{ id = 'q-1'; name = 'NewQuery' } }

            $res = Ensure-AdoQuery -Project 'MyProj' -ParentPath 'Shared Queries' -Name 'NewQuery' -IsFolder:$false
            $res.Created | Should -BeTrue
            $metrics = Get-InitMetrics
            $metrics.queries.created | Should -Be 1
        }

        It 'handles duplicate create error by fetching existing and increments skipped' {
            # Parent GET returns no children, POST throws duplicate, subsequent GET returns existing
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'wit/queries' -and $Path -match '\$depth=1' } -MockWith { @{ children = @() } }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'POST' -and $Path -match 'wit/queries' } -MockWith { throw [System.Exception]::new('409: already exists') }
            Mock -CommandName Invoke-AdoRest -ParameterFilter { $Method -eq 'GET' -and $Path -match 'wit/queries' -and -not ($Path -match '\$depth=1') } -MockWith { @{ id = 'q-dup'; name = 'DupQuery' } }

            $res = Ensure-AdoQuery -Project 'MyProj' -ParentPath 'Shared Queries' -Name 'DupQuery' -IsFolder:$false
            $res.Created | Should -BeFalse
            $metrics = Get-InitMetrics
            $metrics.queries.skipped | Should -Be 1
        }
    }
}
