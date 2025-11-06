BeforeAll {
    # Import required modules
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Core.Rest.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\AzureDevOps.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Migration.psm1") -Force
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Logging.psm1") -Force

    # Initialize Core.Rest with mock credentials
    Initialize-CoreRest -CollectionUrl "https://dev.azure.com/test" -AdoPat "mockpat" -GitLabBaseUrl "https://gitlab.com" -GitLabToken "mocktoken"

    # Mock all REST API calls
    Mock -ModuleName AzureDevOps Invoke-AdoRest {
        param($Method, $Path, $Body)
        
        # Mock project existence check
        if ($Path -match "/_apis/projects/([^/?]+)") {
            return @{ id = "proj-guid"; name = $Matches[1] }
        }
        
        # Mock wiki creation
        if ($Path -match "/wiki/wikis") {
            return @{ id = "wiki-guid"; name = "wiki" }
        }
        
        # Mock dashboard list
        if ($Path -match "/_apis/dashboard/dashboards" -and $Method -eq "GET") {
            return @{ dashboardEntries = @() }
        }
        
        # Mock dashboard creation
        if ($Path -match "/_apis/dashboard/dashboards" -and $Method -eq "POST") {
            return @{ id = "dashboard-guid"; name = "Development Metrics" }
        }
        
        # Mock query folder creation
        if ($Path -match "/_apis/wit/queries") {
            return @{ id = "query-guid"; name = "Development"; isFolder = $true }
        }
        
        # Mock repository list
        if ($Path -match "/_apis/git/repositories") {
            return @{ 
                value = @(
                    @{ id = "repo-guid"; name = "PesterDevProj"; defaultBranch = "refs/heads/main" }
                )
            }
        }
        
        # Mock ref list (branches)
        if ($Path -match "/_apis/git/repositories/.*/refs") {
            return @{
                value = @(
                    @{ name = "refs/heads/main"; objectId = "commit-sha" }
                )
            }
        }
        
        # Mock push operation
        if ($Path -match "/_apis/git/repositories/.*/pushes") {
            return @{ pushId = 1; commits = @() }
        }
        
        return @{}
    }

    Mock -ModuleName Core Test-AdoProjectExists { return $true }
    Mock -ModuleName Migration Test-AdoProjectExists { return $true }
    Mock -ModuleName Core Invoke-AdoRest {
        param($Method, $Path, $Body)
        if ($Path -match "/_apis/projects/.+\?includeCapabilities") {
            return [PSCustomObject]@{ 
                id = "proj-guid"
                name = "PesterDevProj"
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
        return [PSCustomObject]@{ value = @() }
    }
    Mock -ModuleName Wikis Ensure-AdoProjectWiki { 
        return [PSCustomObject]@{ 
            id = "wiki-guid"
            name = "PesterDevProj.wiki"
            type = "projectWiki"
        } 
    }
    Mock -ModuleName Wikis Invoke-AdoRest {
        param($Method, $Path, $Body)
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
        return [PSCustomObject]@{ value = @() }
    }
    Mock -ModuleName Wikis Ensure-AdoDevWiki { }
    Mock -ModuleName Dashboards Ensure-AdoDevDashboard { }
    Mock -ModuleName WorkItems Ensure-AdoDevQueries { }
    Mock -ModuleName Repositories Ensure-AdoRepoFiles { }
    # Don't mock Write-MigrationReport - let it create the summary file for testing
    Mock -ModuleName Migration Invoke-AdoRest {
        param($Method, $Path, $Body)
        if ($Path -match "/_apis/projects/.+\?includeCapabilities") {
            return [PSCustomObject]@{ 
                id = "proj-guid"
                name = "PesterDevProj"
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
        return [PSCustomObject]@{ value = @() }
    }
    Mock -ModuleName Migration Get-ProjectPaths {
        return @{
            reportsDir = Join-Path $env:TEMP "reports"
        }
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
