BeforeAll {
    # Import required modules
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\core\Core.Rest.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\AzureDevOps\AzureDevOps.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Migration.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\core\Logging.psm1") -Force

    # Initialize Core.Rest with mock credentials
    Initialize-CoreRest -CollectionUrl "https://dev.azure.com/test" -AdoPat "mockpat" -GitLabBaseUrl "https://gitlab.com" -GitLabToken "mocktoken"

    # Mock Invoke-AdoRest globally to prevent any real API calls
    Mock Invoke-AdoRest {
        param($Method, $Path, $Body)
        
        # Return appropriate mock responses based on the path
        if ($Path -match "/_apis/projects/.+\?includeCapabilities") {
            return [PSCustomObject]@{ 
                id = "proj-guid"
                name = "PesterDevProj"
                capabilities = @{
                    processTemplate = @{
                        templateName = "Agile"
                    }
                }
            }
        }
        if ($Path -match "/_apis/wiki/wikis" -and $Method -eq "GET") {
            return [PSCustomObject]@{ 
                value = @(
                    [PSCustomObject]@{
                        id = "wiki-guid"
                        name = "PesterDevProj.wiki"
                        type = "projectWiki"
                    }
                )
            }
        }
        if ($Path -match "/_apis/git/repositories") {
            return [PSCustomObject]@{ 
                value = @()
            }
        }
        if ($Path -match "/_apis/wit/workitemtypes") {
            return [PSCustomObject]@{ 
                value = @(
                    [PSCustomObject]@{ name = "User Story" },
                    [PSCustomObject]@{ name = "Task" },
                    [PSCustomObject]@{ name = "Bug" }
                )
            }
        }
        if ($Path -match "/_apis/wit/classificationnodes/areas") {
            return [PSCustomObject]@{ 
                children = @(
                    [PSCustomObject]@{ name = "Frontend" },
                    [PSCustomObject]@{ name = "Backend" }
                )
            }
        }
        if ($Path -match "/_apis/wit/classificationnodes/iterations") {
            return [PSCustomObject]@{ 
                children = @(
                    [PSCustomObject]@{ name = "Sprint 1" },
                    [PSCustomObject]@{ name = "Sprint 2" }
                )
            }
        }
        if ($Path -match "/_apis/wiki/wikis/.+/pages") {
            return [PSCustomObject]@{ 
                subPages = @(
                    [PSCustomObject]@{ path = "/Home" },
                    [PSCustomObject]@{ path = "/Development" }
                )
            }
        }
        if ($Path -match "/_apis/wit/queries/Shared%20Queries") {
            return [PSCustomObject]@{ 
                children = @(
                    [PSCustomObject]@{ name = "My Work" },
                    [PSCustomObject]@{ name = "Development" }
                )
            }
        }
        if ($Path -match "/_apis/dashboard/dashboards") {
            return [PSCustomObject]@{ 
                dashboardEntries = @()
            }
        }
        if ($Path -match "/_apis/build/definitions") {
            return [PSCustomObject]@{ 
                value = @()
            }
        }
        if ($Path -match "/_apis/policy/configurations") {
            return [PSCustomObject]@{ 
                value = @()
            }
        }
        return [PSCustomObject]@{ value = @() }
    }
    Mock -ModuleName Migration Get-ProjectPaths {
        return @{
            reportsDir = Join-Path $($env:TEMP) "reports"
        }
    }
    Mock Test-AdoProjectExists {
        param($ProjectName)
        # Always return true for idempotency tests
        return $true
    }
}

Describe "Initialize-DevInit idempotency" {
    It "runs successfully and completes without errors" {
        # Create temp workspace for test
        $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $env:GITLAB2DEVOPS_MIGRATIONS = $tempBase
        
        try {
            # Execute DevInit - should complete without errors (first time)
            { Initialize-DevInit -DestProject "PesterDevProj" -ProjectType "dotnet" } | Should -Not -Throw
            
            # Verify summary report was created (it's in TEMP\reports folder)
            $summaryFile = Join-Path $env:TEMP "reports\dev-init-summary.json"
            Test-Path $summaryFile | Should -Be $true -Because "Summary report should be created"
            
            # Execute again to test idempotency - should not throw errors (second time)
            { Initialize-DevInit -DestProject "PesterDevProj" -ProjectType "dotnet" } | Should -Not -Throw
        }
        finally {
            Remove-Item $tempBase -Recurse -Force -ErrorAction SilentlyContinue
            $env:GITLAB2DEVOPS_MIGRATIONS = $null
        }
    }
}


