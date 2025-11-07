<#
.SYNOPSIS
    Team initialization pack functions for specialized team resources.

.DESCRIPTION
    This module provides initialization functions for different team types:
    Business, Development, Security, and Management. Each pack provides
    specialized wikis, queries, dashboards, and configurations.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, AzureDevOps modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Provisions business-facing initialization assets for an existing ADO project.

.DESCRIPTION
    Adds wiki pages targeted at business stakeholders, shared queries for status/visibility,
    short-term iterations, and ensures the team dashboard exists. Generates a readiness summary report.

.PARAMETER DestProject
    Azure DevOps project name.

.EXAMPLE
    Initialize-BusinessInit -DestProject "MyProject"
#>
function Initialize-BusinessInit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject
    )

    Write-Host "[INFO] Starting Business Initialization Pack for '$DestProject'" -ForegroundColor Cyan
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray

    # Validate project exists
    if (-not (Test-AdoProjectExists -ProjectName $DestProject)) {
        $errorMsg = New-ActionableError -ErrorType 'ProjectNotFound' -Details @{ ProjectName = $DestProject }
        throw $errorMsg
    }

    # Get project and wiki
    $proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($DestProject))?includeCapabilities=true"
    $projId = $proj.id
    $wiki = Ensure-AdoProjectWiki $projId $DestProject

    # Provision business wiki pages
    Ensure-AdoBusinessWiki -Project $DestProject -WikiId $wiki.id

    # Ensure common tags/guidelines wiki page for consistent labeling (idempotent)
    try {
        Ensure-AdoCommonTags $DestProject $wiki.id | Out-Null
    }
    catch {
        Write-Warning "[BusinessInit] Failed to ensure common tags wiki page: $_"
    }

    # Ensure baseline shared queries + business queries
    Ensure-AdoSharedQueries -Project $DestProject -Team "$DestProject Team" | Out-Null
    Ensure-AdoBusinessQueries -Project $DestProject | Out-Null

    # Seed short-term iterations (using default: 3 sprints of 2 weeks)
    Ensure-AdoIterations -Project $DestProject -Team "$DestProject Team" -SprintCount 3 -SprintDurationDays 14 | Out-Null

    # Ensure dashboard
    Ensure-AdoDashboard -Project $DestProject -Team "$DestProject Team" | Out-Null

    # Generate readiness summary report
    $paths = Get-ProjectPaths -ProjectName $DestProject
    $summary = [pscustomobject]@{
        timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ado_project       = $DestProject
        wiki_pages        = @('Business-Welcome','Decision-Log','Risks-Issues','Glossary','Ways-of-Working','KPIs-and-Success','Training-Quick-Start','Communication-Templates','Post-Cutover-Summary')
        shared_queries    = @('My Active Work','Team Backlog','Active Bugs','Ready for Review','Blocked Items','Current Sprint: Commitment','Unestimated Stories','Epics by Target Date')
        iterations_seeded = 3
        dashboard_created = $true
        notes             = 'Business initialization completed. Some items may already have existed—idempotent operations.'
    }

    $reportFile = Join-Path $paths.reportsDir "business-init-summary.json"
    Write-MigrationReport -ReportFile $reportFile -Data $summary
    Write-Host "[SUCCESS] Business Initialization Pack complete" -ForegroundColor Green
    Write-Host "[INFO] Summary: $reportFile" -ForegroundColor Gray
}

<#
.SYNOPSIS
    Provisions development-focused initialization assets for an existing ADO project.

.DESCRIPTION
    Adds wiki pages, queries, repository files, and documentation targeted at the
    development team for improved productivity and consistent workflows.

.PARAMETER DestProject
    Azure DevOps project name.

.PARAMETER ProjectType
    Project type for .gitignore template (dotnet, node, python, java, all).

.EXAMPLE
    Initialize-DevInit -DestProject "MyProject" -ProjectType "dotnet"
#>
function Initialize-DevInit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [ValidateSet('dotnet', 'node', 'python', 'java', 'all')]
        [string]$ProjectType = 'all'
    )

    Write-Host "[INFO] Starting Development Initialization Pack for '$DestProject'" -ForegroundColor Cyan
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray

    # Validate project exists
    if (-not (Test-AdoProjectExists -ProjectName $DestProject)) {
        $errorMsg = New-ActionableError -ErrorType 'ProjectNotFound' -Details @{ ProjectName = $DestProject }
        throw $errorMsg
    }

    # Get project and wiki
    $proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($DestProject))?includeCapabilities=true"
    $projId = $proj.id
    $wiki = Ensure-AdoProjectWiki $projId $DestProject

    # Provision development wiki pages
    Write-Host "[INFO] Provisioning development wiki pages..." -ForegroundColor Cyan
    Ensure-AdoDevWiki -Project $DestProject -WikiId $wiki.id

    # Create development dashboard
    Write-Host "[INFO] Creating development dashboard..." -ForegroundColor Cyan
    Ensure-AdoDevDashboard -Project $DestProject -WikiId $wiki.id

    # Ensure development queries
    Write-Host "[INFO] Creating development-focused queries..." -ForegroundColor Cyan
    Ensure-AdoDevQueries -Project $DestProject

    # Get repository for adding files
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($DestProject))/_apis/git/repositories"
    $repo = $repos.value | Where-Object { $_.name -eq $DestProject } | Select-Object -First 1
    
    if ($repo) {
        Write-Host "[INFO] Adding enhanced repository files..." -ForegroundColor Cyan
        Ensure-AdoRepoFiles -Project $DestProject -RepoId $repo.id -RepoName $repo.name -ProjectType $ProjectType
    }
    else {
        Write-Host "[WARN] No repository found - skipping repository files" -ForegroundColor Yellow
        Write-Host "[INFO] Repository files will be added after code migration" -ForegroundColor Gray
    }

    # Generate readiness summary report
    $paths = Get-ProjectPaths -ProjectName $DestProject
    $summary = [pscustomobject]@{
        timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ado_project       = $DestProject
        project_type      = $ProjectType
        wiki_pages        = @('Architecture-Decision-Records','Development-Setup','API-Documentation','Git-Workflow','Code-Review-Checklist','Troubleshooting','Dependencies')
        dev_queries       = @('My PRs Awaiting Review','PRs I Need to Review','Technical Debt','Recently Completed','Code Review Feedback')
        repo_files        = @('.gitignore','.editorconfig','CONTRIBUTING.md','CODEOWNERS')
        repository_found  = ($null -ne $repo)
        notes             = 'Development initialization completed. Repository files added if repository exists.'
    }

    $reportFile = Join-Path $paths.reportsDir "dev-init-summary.json"
    Write-MigrationReport -ReportFile $reportFile -Data $summary
    Write-Host "[SUCCESS] Development Initialization Pack complete" -ForegroundColor Green
    Write-Host "[INFO] Summary: $reportFile" -ForegroundColor Gray
}

<#
.SYNOPSIS
    Initializes security resources for DevSecOps teams.

.DESCRIPTION
    Creates comprehensive security resources in an Azure DevOps project:
    - 7 security wiki pages (policies, threat modeling, testing, incident response, compliance, secret management, security champions)
    - 5 security-focused queries (security bugs, vulnerability backlog, security review required, compliance items, security debt)
    - Security dashboard
    - Security repository files (SECURITY.md, security-scan-config.yml, .trivyignore, .snyk)

.PARAMETER DestProject
    The name of the Azure DevOps project to initialize.

.EXAMPLE
    Initialize-SecurityInit -DestProject "MyProject"
#>
function Initialize-SecurityInit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject
    )

    Write-Host "[INFO] Starting Security Initialization Pack for '$DestProject'" -ForegroundColor Cyan
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray

    # Validate project exists
    if (-not (Test-AdoProjectExists -ProjectName $DestProject)) {
        $errorMsg = New-ActionableError -ErrorType 'ProjectNotFound' -Details @{ ProjectName = $DestProject }
        throw $errorMsg
    }

    # Get project and wiki
    $proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($DestProject))?includeCapabilities=true"
    $projId = $proj.id
    $wiki = Ensure-AdoProjectWiki $projId $DestProject

    # Provision security wiki pages
    Write-Host "[INFO] Provisioning security wiki pages..." -ForegroundColor Cyan
    Ensure-AdoSecurityWiki -Project $DestProject -WikiId $wiki.id

    # Create security dashboard
    Write-Host "[INFO] Creating security dashboard..." -ForegroundColor Cyan
    Ensure-AdoSecurityDashboard -Project $DestProject

    # Ensure security queries
    Write-Host "[INFO] Creating security-focused queries..." -ForegroundColor Cyan
    Ensure-AdoSecurityQueries -Project $DestProject

    # Get repository for adding security files
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($DestProject))/_apis/git/repositories"
    $repo = $repos.value | Where-Object { $_.name -eq $DestProject } | Select-Object -First 1
    
    if ($repo) {
        Write-Host "[INFO] Adding security repository files..." -ForegroundColor Cyan
        Ensure-AdoSecurityRepoFiles -Project $DestProject -RepoId $repo.id
    }
    else {
        Write-Host "[WARN] No repository found - skipping security repository files" -ForegroundColor Yellow
        Write-Host "[INFO] Security files will be added after code migration" -ForegroundColor Gray
    }

    # Generate readiness summary report
    $paths = Get-ProjectPaths -ProjectName $DestProject
    $summary = [pscustomobject]@{
        timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ado_project       = $DestProject
        wiki_pages        = @('Security-Policies','Threat-Modeling-Guide','Security-Testing-Checklist','Incident-Response-Plan','Compliance-Requirements','Secret-Management','Security-Champions-Program')
        security_queries  = @('Security Bugs (Priority 0-1)','Vulnerability Backlog','Security Review Required','Compliance Items','Security Debt')
        repo_files        = @('SECURITY.md','security-scan-config.yml','.trivyignore','.snyk')
        repository_found  = ($null -ne $repo)
        notes             = 'Security initialization completed. Repository files added if repository exists. Embed shift-left security practices from day one.'
    }

    $reportFile = Join-Path $paths.reportsDir "security-init-summary.json"
    Write-MigrationReport -ReportFile $reportFile -Data $summary
    Write-Host "[SUCCESS] Security Initialization Pack complete" -ForegroundColor Green
    Write-Host "[INFO] Summary: $reportFile" -ForegroundColor Gray
}

<#
.SYNOPSIS
    Provisions a Management/PMO Initialization Pack.

.DESCRIPTION
    Sets up program management office (PMO) infrastructure including:
    - 8 Management wiki pages (Program Overview, Sprint Planning, Capacity Planning, Roadmap, RAID, Stakeholder Comms, Retrospectives, Metrics)
    - 6 Management queries (Program Status, Sprint Progress, Risk Register, etc.)
    - Program management dashboard

.PARAMETER DestProject
    Azure DevOps project name.

.EXAMPLE
    Initialize-ManagementInit -DestProject "MyProgram"
#>
function Initialize-ManagementInit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject
    )

    Write-Host "[INFO] Starting Management Initialization Pack for '$DestProject'" -ForegroundColor Cyan
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray

    # Validate project exists
    if (-not (Test-AdoProjectExists -ProjectName $DestProject)) {
        $errorMsg = New-ActionableError -ErrorType 'ProjectNotFound' -Details @{ ProjectName = $DestProject }
        throw $errorMsg
    }

    # Get project and wiki
    $proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($DestProject))?includeCapabilities=true"
    $projId = $proj.id
    $wiki = Ensure-AdoProjectWiki $projId $DestProject

    # Provision management wiki pages
    Write-Host "[INFO] Provisioning management wiki pages..." -ForegroundColor Cyan
    Ensure-AdoManagementWiki -Project $DestProject -WikiId $wiki.id

    # Create management dashboard
    Write-Host "[INFO] Creating management dashboard..." -ForegroundColor Cyan
    Ensure-AdoManagementDashboard -Project $DestProject

    # Ensure management queries
    Write-Host "[INFO] Creating management-focused queries..." -ForegroundColor Cyan
    Ensure-AdoManagementQueries -Project $DestProject

    # Generate readiness summary report
    $paths = Get-ProjectPaths -ProjectName $DestProject
    $summary = [pscustomobject]@{
        timestamp           = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ado_project         = $DestProject
        wiki_pages          = @('Program-Overview','Sprint-Planning','Capacity-Planning','Roadmap','RAID-Log','Stakeholder-Communications','Retrospectives','Metrics-Dashboard')
        management_queries  = @('Program Status','Sprint Progress','Active Risks','Open Issues','Cross-Team Dependencies','Milestone Tracker')
        dashboard_created   = $true
        notes               = 'Management initialization completed. PMO infrastructure ready for program oversight, sprint planning, risk management, and stakeholder reporting.'
    }

    $reportFile = Join-Path $paths.reportsDir "management-init-summary.json"
    Write-MigrationReport -ReportFile $reportFile -Data $summary
    Write-Host "[SUCCESS] Management Initialization Pack complete" -ForegroundColor Green
    Write-Host "[INFO] Summary: $reportFile" -ForegroundColor Gray
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-BusinessInit',
    'Initialize-DevInit',
    'Initialize-SecurityInit',
    'Initialize-ManagementInit'
)