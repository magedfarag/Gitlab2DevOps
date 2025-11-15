Describe 'Import-AdoWorkItemsFromExcel payloads' {
    BeforeAll {
        # Ensure a simple stub exists for Get-AdoWorkItemTypes so import-time calls won't fail
        if (-not (Get-Command -Name Get-AdoWorkItemTypes -ErrorAction SilentlyContinue)) {
            function Get-AdoWorkItemTypes { param($Project) return @('Task') }
        }
        # Ensure a minimal Core.Rest config helper exists for import-time calls
        if (-not (Get-Command -Name Get-CoreRestConfig -ErrorAction SilentlyContinue)) {
            function Get-CoreRestConfig { return @{ CollectionUrl = 'https://dev.azure.com/myorg' } }
        }
        # Note: Defer importing Core.Rest and Logging until after mocks are registered
        # so that Pester can intercept HTTP calls made during module import.

        # Minimal stubs and mocks so import-time calls are safe and no real HTTP is made
        if (-not (Get-Command -Name Get-AdoWorkItemTypes -ErrorAction SilentlyContinue)) { function Get-AdoWorkItemTypes { param($Project) return @('Task') } }
        if (-not (Get-Command -Name Get-CoreRestConfig -ErrorAction SilentlyContinue)) { function Get-CoreRestConfig { return @{ CollectionUrl = 'https://dev.azure.com/myorg' } } }

        Mock -CommandName Invoke-AdoRest -MockWith {
            param($Method, $Path, $Body, $ContentType, $ReturnNullOnNotFound)
            if (-not (Get-Variable -Name 'script:capturedInvokeCalls' -Scope Script -ErrorAction SilentlyContinue)) { Set-Variable -Name 'script:capturedInvokeCalls' -Scope Script -Value @() -Force }
            $script:capturedInvokeCalls += [pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; ContentType = $ContentType }
            if ($Method -eq 'GET') {
                if ($Path -match '_apis/wit/workitemtypes') { return @([pscustomobject]@{ name = 'Task' }) }
                if ($Path -match '_apis/work/teamsettings/iterations') { return [pscustomobject]@{ value = @([pscustomobject]@{ path = "MyProj\\Sprint 1" }) } }
                if ($Path -match 'classificationnodes/areas') { return [pscustomobject]@{ value = @() } }
                if ($Path -match 'classificationnodes/iterations') { return [pscustomobject]@{ value = @() } }
                return $null
            }
            if ($Method -eq 'POST' -and $Path -match '_apis/wit/workitems') {
                if (-not (Get-Variable -Name 'script:postCounter' -Scope Script -ErrorAction SilentlyContinue)) { Set-Variable -Name 'script:postCounter' -Scope Script -Value 0 -Force }
                $script:postCounter = $script:postCounter + 1
                return [pscustomobject]@{ id = 1000 + $script:postCounter }
            }
            return $null
        }

        Mock -CommandName Invoke-RestWithRetry -MockWith {
            param($Method, $Uri, $Headers, $Body, $Side, $MaxAttempts, $DelaySeconds)
            if ($Method -eq 'POST' -and $Uri -match '_apis/wit/workitems') {
                if (-not (Get-Variable -Name 'script:postCounter' -Scope Script -ErrorAction SilentlyContinue)) { Set-Variable -Name 'script:postCounter' -Scope Script -Value 0 -Force }
                $script:postCounter = $script:postCounter + 1
                return [pscustomobject]@{ id = 1000 + $script:postCounter }
            }
            return $null
        }

        Import-Module "$PWD\modules\core\Core.Rest.psm1" -Force -ErrorAction Stop
        Import-Module "$PWD\modules\core\Logging.psm1" -Force -ErrorAction Stop
        Import-Module "$PWD\modules\AzureDevOps\Projects.psm1" -Force -ErrorAction Stop
        Import-Module "$PWD\modules\AzureDevOps\WorkItems.psm1" -Force -ErrorAction Stop

        # Test data and mocks for Import-Excel
        $script:excelPath = Join-Path $env:TEMP 'pester-test-req.xlsx'
        if (-not (Test-Path $script:excelPath)) { New-Item -Path $script:excelPath -ItemType File -Force | Out-Null }
        $parent = [pscustomobject]@{ LocalId = '1'; WorkItemType = 'Task'; Title = 'Parent Task' }
        $child  = [pscustomobject]@{ LocalId = '2'; ParentLocalId = '1'; WorkItemType = 'Task'; Title = 'Child Task' }
        $rows = @($parent, $child)
        Set-Variable -Name 'script:capturedInvokeCalls' -Scope Script -Value @() -Force
        Set-Variable -Name 'script:postCounter' -Scope Script -Value 0 -Force
        Mock -CommandName Import-Excel -ModuleName WorkItems -MockWith { param($Path,$WorksheetName) return $rows }
        Mock -CommandName Get-AdoWorkItemTypes -MockWith { param($Project) return @('Task') }
        Mock -CommandName Get-CoreRestConfig -MockWith { return @{ CollectionUrl = 'https://dev.azure.com/myorg' } }
        Mock -CommandName Invoke-AdoRest -ModuleName Core.Rest -MockWith {
            param($Method, $Path, $Body, $ContentType)
            $call = [pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; ContentType = $ContentType }
            $script:capturedInvokeCalls += $call
            if ($Method -eq 'POST' -and $Path -match '_apis/wit/workitems') { $script:postCounter = $script:postCounter + 1; return [pscustomobject]@{ id = 1000 + $script:postCounter } }
            return $null
        }
    }

    It 'adds System.AreaPath and System.IterationPath and uses absolute relation URLs' {
        $result = Import-AdoWorkItemsFromExcel -Project 'MyProj' -ExcelPath $script:excelPath -WorksheetName 'Requirements' -TeamName 'MyProj Team'
        $postCalls = $script:capturedInvokeCalls | Where-Object { $_.Method -eq 'POST' -and ($_.Path -match '_apis/wit/workitems') }
        $postCalls.Count | Should -Be 2
        $parentBody = $postCalls[0].Body
        $parentBody | Should -BeOfType [string]
        $parentBody | Should -Match '"/fields/System.AreaPath"'
        $parentBody | Should -Match '"/fields/System.IterationPath"'
        $childBody = $postCalls[1].Body
        $childBody | Should -BeOfType [string]
        $childBody | Should -Match '"/fields/System.AreaPath"'
        $childBody | Should -Match '"/fields/System.IterationPath"'
        $childBody | Should -Match 'https://dev.azure.com/myorg/_apis/wit/workItems/1001'
    }
}
