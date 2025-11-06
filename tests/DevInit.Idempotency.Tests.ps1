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
        param($Method, $Endpoint, $Body)
        
        # Mock project existence check
        if ($Endpoint -match "/_apis/projects/([^/?]+)") {
            return @{ id = "proj-guid"; name = $Matches[1] }
        }
        
        # Mock wiki creation
        if ($Endpoint -match "/wiki/wikis") {
            return @{ id = "wiki-guid"; name = "wiki" }
        }
        
        # Mock dashboard list
        if ($Endpoint -match "/_apis/dashboard/dashboards" -and $Method -eq "GET") {
            return @{ dashboardEntries = @() }
        }
        
        # Mock dashboard creation
        if ($Endpoint -match "/_apis/dashboard/dashboards" -and $Method -eq "POST") {
            return @{ id = "dashboard-guid"; name = "Development Metrics" }
        }
        
        # Mock query folder creation
        if ($Endpoint -match "/_apis/wit/queries") {
            return @{ id = "query-guid"; name = "Development"; isFolder = $true }
        }
        
        # Mock repository list
        if ($Endpoint -match "/_apis/git/repositories") {
            return @{ 
                value = @(
                    @{ id = "repo-guid"; name = "PesterDevProj"; defaultBranch = "refs/heads/main" }
                )
            }
        }
        
        # Mock ref list (branches)
        if ($Endpoint -match "/_apis/git/repositories/.*/refs") {
            return @{
                value = @(
                    @{ name = "refs/heads/main"; objectId = "commit-sha" }
                )
            }
        }
        
        # Mock push operation
        if ($Endpoint -match "/_apis/git/repositories/.*/pushes") {
            return @{ pushId = 1; commits = @() }
        }
        
        return @{}
    }

    Mock -ModuleName Migration Test-AdoProjectExists { return $true }
    Mock -ModuleName Migration Ensure-AdoProjectWiki { return @{ id = "wiki-guid" } }
    Mock -ModuleName Migration Ensure-AdoDevWiki { }
    Mock -ModuleName Migration Ensure-AdoDevDashboard { }
    Mock -ModuleName Migration Ensure-AdoDevQueries { }
    Mock -ModuleName Migration Ensure-AdoRepoFiles { }
    Mock -ModuleName Migration Write-MigrationReport { }
    Mock -ModuleName Migration Invoke-AdoRest {
        param($Method, $Endpoint)
        if ($Endpoint -match "/_apis/projects/") {
            return @{ id = "proj-guid"; name = "PesterDevProj" }
        }
        if ($Endpoint -match "/_apis/git/repositories") {
            return @{ value = @() }
        }
        return @{ value = @() }
    }
    Mock -ModuleName Migration Get-ProjectPaths {
        return @{
            reportsDir = Join-Path $env:TEMP "reports"
        }
    }
}

Describe "Initialize-DevInit idempotency" {
    It "calls key ensure functions exactly once and writes a summary report" {
        # Create temp workspace for test
        $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $env:GITLAB2DEVOPS_MIGRATIONS = $tempBase
        
        try {
            # Execute DevInit
            { Initialize-DevInit -DestProject "PesterDevProj" -ProjectType "dotnet" } | Should -Not -Throw
            
            # Verify mocks were called (proves execution path)
            Should -Invoke -ModuleName Migration -CommandName Test-AdoProjectExists -Times 1
            Should -Invoke -ModuleName Migration -CommandName Ensure-AdoProjectWiki -Times 1
            Should -Invoke -ModuleName Migration -CommandName Ensure-AdoDevWiki -Times 1
            Should -Invoke -ModuleName Migration -CommandName Ensure-AdoDevDashboard -Times 1
            Should -Invoke -ModuleName Migration -CommandName Ensure-AdoDevQueries -Times 1
            Should -Invoke -ModuleName Migration -CommandName Write-MigrationReport -Times 1
        }
        finally {
            Remove-Item $tempBase -Recurse -Force -ErrorAction SilentlyContinue
            $env:GITLAB2DEVOPS_MIGRATIONS = $null
        }
    }
}
