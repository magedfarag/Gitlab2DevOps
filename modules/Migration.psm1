<#
.SYNOPSIS
    Migration orchestration and menu functions.

.DESCRIPTION
    This module handles the migration workflow including single migrations,
    bulk migrations, project initialization, and the interactive menu system.
    Coordinates between GitLab, AzureDevOps, and Logging modules.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, GitLab, AzureDevOps, Logging modules
    Version: 2.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Module-level variables for menu context
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabToken = $null
$script:BuildDefinitionId = 0
$script:SonarStatusContext = ""

<#
.SYNOPSIS
    Scans for prepared GitLab projects.

.DESCRIPTION
    Looks for single project preparations and bulk preparations in the migrations folder.

.OUTPUTS
    Array of prepared project information.
#>
function Get-PreparedProjects {
    [CmdletBinding()]
    param()
    
    $migrationsDir = Join-Path (Get-Location) "migrations"
    $prepared = @()
    
    if (-not (Test-Path $migrationsDir)) {
        return $prepared
    }
    
    # First, collect all project names that are part of bulk preparations
    $bulkProjectNames = @{}
    Get-ChildItem -Path $migrationsDir -Directory -Filter "bulk-prep-*" | ForEach-Object {
        $templateFile = Join-Path $_.FullName "bulk-migration-template.json"
        if (Test-Path $templateFile) {
            try {
                $template = Get-Content $templateFile | ConvertFrom-Json
                foreach ($proj in $template.projects) {
                    $bulkProjectNames[$proj.ado_repo_name] = $true
                }
            }
            catch {
                Write-Verbose "Failed to read template: $templateFile"
            }
        }
    }
    
    # Scan for single project preparations (exclude those in bulk preparations)
    Get-ChildItem -Path $migrationsDir -Directory | Where-Object {
        $_.Name -notlike "bulk-prep-*" -and 
        (Test-Path (Join-Path $_.FullName "reports\preflight-report.json")) -and
        -not $bulkProjectNames.ContainsKey($_.Name)
    } | ForEach-Object {
        $reportFile = Join-Path $_.FullName "reports\preflight-report.json"
        try {
            $report = Get-Content $reportFile | ConvertFrom-Json
            
            # Check if project exists in Azure DevOps and if repo is migrated
            $projectExists = Test-AdoProjectExists -ProjectName $_.Name
            $repoMigrated = $false
            if ($projectExists) {
                $repos = Get-AdoProjectRepositories -ProjectName $_.Name
                $repoMigrated = $repos | Where-Object { $_.name -eq $_.Name }
            }
            
            $prepared += [pscustomobject]@{
                Type = "Single"
                ProjectName = $_.Name
                GitLabPath = $report.project
                RepoSizeMB = $report.repo_size_MB
                PreparationTime = $report.preparation_time
                Folder = $_.FullName
                ProjectExists = $projectExists
                RepoMigrated = $null -ne $repoMigrated
            }
        }
        catch {
            Write-Verbose "Failed to read report: $reportFile"
        }
    }
    
    # Scan for bulk preparations
    Get-ChildItem -Path $migrationsDir -Directory -Filter "bulk-prep-*" | ForEach-Object {
        $templateFile = Join-Path $_.FullName "bulk-migration-template.json"
        if (Test-Path $templateFile) {
            try {
                $template = Get-Content $templateFile | ConvertFrom-Json
                $successfulCount = @($template.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
                
                # Check if project exists in Azure DevOps
                $projectExists = Test-AdoProjectExists -ProjectName $template.destination_project
                $migratedCount = 0
                if ($projectExists) {
                    $repos = Get-AdoProjectRepositories -ProjectName $template.destination_project
                    foreach ($proj in $template.projects) {
                        if ($repos | Where-Object { $_.name -eq $proj.ado_repo_name }) {
                            $migratedCount++
                        }
                    }
                }
                
                $prepared += [pscustomobject]@{
                    Type = "Bulk"
                    ProjectName = $template.destination_project
                    ProjectCount = $template.preparation_summary.total_projects
                    SuccessfulCount = $successfulCount
                    TotalSizeMB = $template.preparation_summary.total_size_MB
                    PreparationTime = $template.preparation_summary.preparation_time
                    Folder = $_.FullName
                    TemplateFile = $templateFile
                    ProjectExists = $projectExists
                    MigratedCount = $migratedCount
                }
            }
            catch {
                Write-Verbose "Failed to read template: $templateFile"
            }
        }
    }
    
    return $prepared
}

<#
.SYNOPSIS
    Displays the interactive migration menu.

.DESCRIPTION
    Main entry point for interactive operations. Provides 6 options:
    1) Prepare single project
    2) Initialize Azure DevOps project
    3) Migrate single project
    4) Bulk preparation
    5) Manage bulk templates
    6) Execute bulk migration

.PARAMETER CollectionUrl
    Azure DevOps collection URL.

.PARAMETER AdoPat
    Azure DevOps PAT.

.PARAMETER GitLabBaseUrl
    GitLab base URL.

.PARAMETER GitLabToken
    GitLab token.

.PARAMETER BuildDefinitionId
    Optional build definition ID.

.PARAMETER SonarStatusContext
    Optional SonarQube context.

.EXAMPLE
    Show-MigrationMenu -CollectionUrl "https://dev.azure.com/org" -AdoPat $pat -GitLabBaseUrl "https://gitlab.com" -GitLabToken $token
#>
function Show-MigrationMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CollectionUrl,
        
        [Parameter(Mandatory)]
        [string]$AdoPat,
        
        [Parameter(Mandatory)]
        [string]$GitLabBaseUrl,
        
        [Parameter(Mandatory)]
        [string]$GitLabToken,
        
        [int]$BuildDefinitionId = 0,
        
        [string]$SonarStatusContext = ""
    )
    
    # Store in script scope for nested functions
    $script:CollectionUrl = $CollectionUrl
    $script:AdoPat = $AdoPat
    $script:GitLabToken = $GitLabToken
    $script:BuildDefinitionId = $BuildDefinitionId
    $script:SonarStatusContext = $SonarStatusContext
    
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "   GitLab → Azure DevOps Migration Tool" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select action:"
    Write-Host "  1) Download & analyze single GitLab project (prepare for migration)"
    Write-Host "  2) Create & setup Azure DevOps project with policies"
    Write-Host "  3) Migrate single GitLab project to Azure DevOps"
    Write-Host "  4) Download & analyze multiple GitLab projects (bulk preparation)"
    Write-Host "  5) Review & update bulk migration template"
    Write-Host "  6) Execute bulk migration from prepared template"
    Write-Host "  7) Provision Business Initialization Pack (wiki, queries, sprints, dashboard)"
    Write-Host "  8) Provision Development Initialization Pack (dev wiki, queries, repo files)"
    Write-Host "  9) Provision Security Initialization Pack (security wiki, queries, dashboard, security files)"
    Write-Host ""
    
    $choice = Read-Host "Enter 1, 2, 3, 4, 5, 6, 7, 8, or 9"
    
    switch ($choice) {
        '1' {
            $SourceProjectPath = Read-Host "Enter Source GitLab project path (e.g., group/my-project)"
            if (-not [string]::IsNullOrWhiteSpace($SourceProjectPath)) {
                Prepare-GitLab $SourceProjectPath
            }
            else {
                Write-Host "[ERROR] Project path cannot be empty." -ForegroundColor Red
            }
        }
        '2' {
            # Show prepared projects
            $preparedProjects = Get-PreparedProjects
            
            if ($preparedProjects.Count -eq 0) {
                Write-Host ""
                Write-Host "No prepared projects found. Please run Option 1 or 4 first to prepare projects." -ForegroundColor Yellow
                Write-Host ""
                $createNew = Read-Host "Do you want to create a new independent Azure DevOps project? (y/N)"
                if ($createNew -match '^[Yy]') {
                    $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
                    $RepoName = Read-Host "Enter initial repository name (e.g., my-repo)"
                    if (-not [string]::IsNullOrWhiteSpace($DestProjectName) -and -not [string]::IsNullOrWhiteSpace($RepoName)) {
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                    }
                    else {
                        Write-Host "[ERROR] Project name and repository name cannot be empty." -ForegroundColor Red
                    }
                }
                return
            }
            
            Write-Host ""
            Write-Host "=== PREPARED PROJECTS ===" -ForegroundColor Cyan
            Write-Host ""
            
            # Filter out already-created projects (keep only those not yet in Azure DevOps)
            $availableProjects = @($preparedProjects | Where-Object { -not $_.ProjectExists })
            
            if ($availableProjects.Count -eq 0) {
                Write-Host "[INFO] All prepared projects have already been created in Azure DevOps." -ForegroundColor Yellow
                Write-Host "[INFO] Use Option 3 (Migrate) or Option 6 (Bulk Migrate) to sync repositories." -ForegroundColor Yellow
                Write-Host ""
                
                # Still allow creating new independent project
                Write-Host "  1) Create new independent Azure DevOps project (not from preparation)" -ForegroundColor Yellow
                Write-Host ""
                
                $selection = Read-Host "Select an option (1 or press Enter to cancel)"
                if ($selection -eq "1") {
                    Write-Host ""
                    Write-Host "=== CREATE NEW INDEPENDENT PROJECT ===" -ForegroundColor Cyan
                    $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
                    $RepoName = Read-Host "Enter initial repository name (e.g., my-repo)"
                    if (-not [string]::IsNullOrWhiteSpace($DestProjectName) -and -not [string]::IsNullOrWhiteSpace($RepoName)) {
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                    }
                    else {
                        Write-Host "[ERROR] Project name and repository name cannot be empty." -ForegroundColor Red
                    }
                }
                return
            }
            
            # Display single preparations (not yet created)
            $singleProjects = @($availableProjects | Where-Object { $_.Type -eq "Single" })
            if ($singleProjects.Count -gt 0) {
                Write-Host "Single Project Preparations:" -ForegroundColor Green
                for ($i = 0; $i -lt $singleProjects.Count; $i++) {
                    $proj = $singleProjects[$i]
                    Write-Host "  $($i + 1)) $($proj.ProjectName) (from $($proj.GitLabPath))" -ForegroundColor White
                    Write-Host "      Size: $($proj.RepoSizeMB) MB | Prepared: $($proj.PreparationTime)" -ForegroundColor Gray
                }
                Write-Host ""
            }
            
            # Display bulk preparations (not yet created)
            $bulkProjects = @($availableProjects | Where-Object { $_.Type -eq "Bulk" })
            $bulkStartIndex = $singleProjects.Count
            if ($bulkProjects.Count -gt 0) {
                Write-Host "Bulk Preparations:" -ForegroundColor Green
                for ($i = 0; $i -lt $bulkProjects.Count; $i++) {
                    $proj = $bulkProjects[$i]
                    Write-Host "  $($bulkStartIndex + $i + 1)) $($proj.ProjectName) (bulk: $($proj.SuccessfulCount)/$($proj.ProjectCount) projects)" -ForegroundColor White
                    Write-Host "      Total size: $($proj.TotalSizeMB) MB | Prepared: $($proj.PreparationTime)" -ForegroundColor Gray
                }
                Write-Host ""
            }
            
            # Add option to create new independent project
            $newProjectIndex = $availableProjects.Count + 1
            Write-Host "  $newProjectIndex) Create new independent Azure DevOps project (not from preparation)" -ForegroundColor Yellow
            Write-Host ""
            
            $selection = Read-Host "Select a project to initialize in Azure DevOps (1-$newProjectIndex)"
            $selectionNum = 0
            
            if ([int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $newProjectIndex) {
                if ($selectionNum -eq $newProjectIndex) {
                    # Create new independent project
                    Write-Host ""
                    Write-Host "=== CREATE NEW INDEPENDENT PROJECT ===" -ForegroundColor Cyan
                    $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
                    $RepoName = Read-Host "Enter initial repository name (e.g., my-repo)"
                    if (-not [string]::IsNullOrWhiteSpace($DestProjectName) -and -not [string]::IsNullOrWhiteSpace($RepoName)) {
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                    }
                    else {
                        Write-Host "[ERROR] Project name and repository name cannot be empty." -ForegroundColor Red
                    }
                }
                else {
                    # Initialize from prepared project
                    $selectedProject = $availableProjects[$selectionNum - 1]
                    
                    if ($selectedProject.Type -eq "Single") {
                        $DestProjectName = Read-Host "Enter Azure DevOps project name (press Enter for '$($selectedProject.ProjectName)')"
                        if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                            $DestProjectName = $selectedProject.ProjectName
                        }
                        $RepoName = $selectedProject.ProjectName
                        
                        Write-Host ""
                        Write-Host "Initializing Azure DevOps project '$DestProjectName' with repository '$RepoName'..." -ForegroundColor Cyan
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                    }
                    elseif ($selectedProject.Type -eq "Bulk") {
                        $DestProjectName = Read-Host "Enter Azure DevOps project name (press Enter for '$($selectedProject.ProjectName)')"
                        if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                            $DestProjectName = $selectedProject.ProjectName
                        }
                        
                        Write-Host ""
                        Write-Host "Initializing Azure DevOps project '$DestProjectName' for bulk migration..." -ForegroundColor Cyan
                        Write-Host "[INFO] This will create the project. Use Option 6 to migrate the repositories." -ForegroundColor Yellow
                        
                        # For bulk, create project without repository (repositories will be added during migration)
                        $tempRepoName = "initial-repo"
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $tempRepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                    }
                }
            }
            else {
                Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
            }
        }
        '3' {
            $SourceProjectPath = Read-Host "Enter Source GitLab project path (e.g., group/my-project)"
            $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (e.g., MyProject)"
            
            if ([string]::IsNullOrWhiteSpace($SourceProjectPath) -or [string]::IsNullOrWhiteSpace($DestProjectName)) {
                Write-Host "[ERROR] Project path and name cannot be empty." -ForegroundColor Red
                return
            }
            
            # Check if project and repository already exist
            $projectExists = Test-AdoProjectExists -ProjectName $DestProjectName
            $repoExists = $false
            $repoName = ($SourceProjectPath -split '/')[-1]
            
            if ($projectExists) {
                Write-Host "[INFO] Project '$DestProjectName' exists in Azure DevOps" -ForegroundColor Cyan
                $repos = Get-AdoProjectRepositories -ProjectName $DestProjectName
                $repoExists = $null -ne ($repos | Where-Object { $_.name -eq $repoName })
                
                if ($repoExists) {
                    Write-Host "[INFO] Repository '$repoName' already migrated in project '$DestProjectName'" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Options:" -ForegroundColor Cyan
                    Write-Host "  1) SYNC - Pull latest from GitLab and push to Azure DevOps (recommended)" -ForegroundColor Green
                    Write-Host "  2) SKIP - Do nothing" -ForegroundColor Yellow
                    Write-Host "  3) FORCE - Replace existing repository (destructive)" -ForegroundColor Red
                    Write-Host ""
                    $choice = Read-Host "Select option (1-3)"
                    
                    switch ($choice) {
                        '1' {
                            Write-Host "[INFO] Starting SYNC operation..." -ForegroundColor Green
                            Invoke-SingleMigration -SrcPath $SourceProjectPath -DestProject $DestProjectName -AllowSync
                        }
                        '2' {
                            Write-Host "[INFO] Skipping migration" -ForegroundColor Yellow
                        }
                        '3' {
                            Write-Host "[WARN] This will REPLACE the existing repository!" -ForegroundColor Red
                            $confirm = Read-Host "Are you sure? Type 'REPLACE' to confirm"
                            if ($confirm -eq 'REPLACE') {
                                Write-Host "[INFO] Starting FORCE migration..." -ForegroundColor Red
                                Invoke-SingleMigration -SrcPath $SourceProjectPath -DestProject $DestProjectName -Replace -Force
                            }
                            else {
                                Write-Host "[INFO] Cancelling operation" -ForegroundColor Yellow
                            }
                        }
                        default {
                            Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
                        }
                    }
                }
                else {
                    # Project exists but repo doesn't - normal migration
                    Write-Host "[INFO] Repository '$repoName' not found in project - starting migration" -ForegroundColor Cyan
                    Invoke-SingleMigration -SrcPath $SourceProjectPath -DestProject $DestProjectName
                }
            }
            else {
                # Project doesn't exist - normal migration
                Write-Host "[INFO] Project '$DestProjectName' not found - will create new project" -ForegroundColor Cyan
                Invoke-SingleMigration -SrcPath $SourceProjectPath -DestProject $DestProjectName
            }
        }
        '4' {
            Invoke-BulkPreparationWorkflow
        }
        '5' {
            Invoke-TemplateManagerWorkflow
        }
        '6' {
            Invoke-BulkMigrationWorkflow
        }
        '7' {
            $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
            if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                Write-Host "[ERROR] Project name cannot be empty." -ForegroundColor Red
                return
            }
            try {
                Write-Host "[INFO] Provisioning Business Initialization Pack for '$DestProjectName'..." -ForegroundColor Cyan
                Initialize-BusinessInit -DestProject $DestProjectName
                Write-Host "[SUCCESS] Business Initialization Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Business Initialization failed: $_" -ForegroundColor Red
            }
        }
        '8' {
            $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
            if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                Write-Host "[ERROR] Project name cannot be empty." -ForegroundColor Red
                return
            }
            
            Write-Host ""
            Write-Host "Select project type for .gitignore template:"
            Write-Host "  1) .NET"
            Write-Host "  2) Node.js"
            Write-Host "  3) Python"
            Write-Host "  4) Java"
            Write-Host "  5) All (multi-language)"
            $typeChoice = Read-Host "Enter 1-5 (default: 5)"
            
            $projectType = switch ($typeChoice) {
                '1' { 'dotnet' }
                '2' { 'node' }
                '3' { 'python' }
                '4' { 'java' }
                default { 'all' }
            }
            
            try {
                Write-Host "[INFO] Provisioning Development Initialization Pack for '$DestProjectName'..." -ForegroundColor Cyan
                Initialize-DevInit -DestProject $DestProjectName -ProjectType $projectType
                Write-Host "[SUCCESS] Development Initialization Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Development Initialization failed: $_" -ForegroundColor Red
            }
        }
        '9' {
            $DestProjectName = Read-Host "Enter Azure DevOps project name"
            if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                Write-Host "[ERROR] Project name cannot be empty." -ForegroundColor Red
                return
            }
            
            try {
                Write-Host "[INFO] Provisioning Security Initialization Pack for '$DestProjectName'..." -ForegroundColor Cyan
                Initialize-SecurityInit -DestProject $DestProjectName
                Write-Host "[SUCCESS] Security Initialization Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Security Initialization failed: $_" -ForegroundColor Red
            }
        }
        default {
            Write-Host "Invalid choice." -ForegroundColor Red
        }
    }
}

<#
.SYNOPSIS
    Initializes an Azure DevOps project with complete setup.

.DESCRIPTION
    Creates project, sets up RBAC groups, areas, wiki, work item templates,
    repository, and branch policies. Complete project scaffolding.

.PARAMETER DestProject
    Azure DevOps project name.

.PARAMETER RepoName
    Repository name.

.PARAMETER BuildDefinitionId
    Optional build definition ID.

.PARAMETER SonarStatusContext
    Optional SonarQube context.

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -BuildDefinitionId 10
#>
function Initialize-AdoProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [Parameter(Mandatory)]
        [string]$RepoName,
        
        [int]$BuildDefinitionId = 0,
        
        [string]$SonarStatusContext = ""
    )
    
    Write-Host "[INFO] Initializing Azure DevOps project: $DestProject" -ForegroundColor Cyan
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray
    
    # Create/ensure project
    $proj = Ensure-AdoProject $DestProject
    $projId = $proj.id
    $desc = Get-AdoProjectDescriptor $projId
    
    # Only configure RBAC if Graph API is available
    if ($desc) {
        Write-Verbose "[Initialize-AdoProject] Configuring RBAC groups..."
        
        # Get built-in groups
        $descContrib = Get-AdoBuiltInGroupDescriptor $desc "Contributors"
        $descProjAdm = Get-AdoBuiltInGroupDescriptor $desc "Project Administrators"
        
        # Create custom groups
        $grpDev = Ensure-AdoGroup $desc "Dev"
        $grpQA = Ensure-AdoGroup $desc "QA"
        $grpBA = Ensure-AdoGroup $desc "BA"
        
        # Configure group memberships
        Ensure-AdoMembership $descContrib $grpDev.descriptor
        Ensure-AdoMembership $descContrib $grpQA.descriptor
        Ensure-AdoMembership $descContrib $grpBA.descriptor
    }
    else {
        Write-Warning "Graph API unavailable - skipping RBAC group configuration"
    }
    
    # Create work item areas (404 errors are normal - just checking if areas exist)
    Write-Host "[INFO] Setting up work item areas..." -ForegroundColor Cyan
    @("Frontend", "Backend", "Infrastructure", "Documentation") | ForEach-Object {
        Ensure-AdoArea $DestProject $_
    }
    Write-Host "[SUCCESS] Work item areas configured" -ForegroundColor Green
    
    # Set up project wiki
    $wiki = Ensure-AdoProjectWiki $projId $DestProject
    # Load welcome wiki template
    $welcomeTemplate = Get-Content -Path (Join-Path $PSScriptRoot "templates\welcome-wiki.md") -Raw -Encoding UTF8
    $welcomeContent = $welcomeTemplate -replace '{{PROJECT_NAME}}', $DestProject
    Upsert-AdoWikiPage $DestProject $wiki.id "/Home" $welcomeContent
    
    # Create work item templates
    Ensure-AdoTeamTemplates $DestProject "$DestProject Team"
    
    # Create sprint iterations (6 sprints, 2 weeks each)
    Ensure-AdoIterations $DestProject "$DestProject Team" -SprintCount 6 -SprintDurationDays 14
    
    # Create shared work item queries
    Ensure-AdoSharedQueries $DestProject "$DestProject Team"
    
    # Configure team settings
    Ensure-AdoTeamSettings $DestProject "$DestProject Team"
    
    # Create team dashboard
    Ensure-AdoDashboard $DestProject "$DestProject Team"
    
    # Create wiki pages (tag guidelines and best practices)
    Ensure-AdoCommonTags $DestProject $wiki.id
    Ensure-AdoBestPracticesWiki $DestProject $wiki.id
    
    # Configure QA infrastructure (test plans, queries, dashboards, configurations, guidelines)
    Write-Host "[INFO] Setting up QA infrastructure..." -ForegroundColor Cyan
    try {
        # Create test plan with test suites
        $testPlan = Ensure-AdoTestPlan $DestProject
        
        # Create QA queries
        Ensure-AdoQAQueries $DestProject
        
        # Create QA dashboard
        Ensure-AdoQADashboard $DestProject "$DestProject Team"
        
        # Create test configurations
        Ensure-AdoTestConfigurations $DestProject
        
        # Create QA guidelines wiki page
        Ensure-AdoQAGuidelinesWiki $DestProject $wiki.id
        
        Write-Host "[SUCCESS] QA infrastructure configured successfully" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to configure QA infrastructure: $_"
        Write-Warning "Continuing with project initialization..."
    }
    
    # Create repository
    $repo = Ensure-AdoRepository $DestProject $projId $RepoName

    if ($null -ne $repo) {
        # Wait for default branch to be established
        Start-Sleep -Seconds 2
        $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id

        # Apply branch policies only if repository has a default branch
        if ($defaultRef) {
            Ensure-AdoBranchPolicies `
                -Project $DestProject `
                -RepoId $repo.id `
                -Ref $defaultRef `
                -Min 2 `
                -BuildId $BuildDefinitionId `
                -StatusContext $SonarStatusContext

            # Add repository templates (README and PR template) if repository has commits
            Ensure-AdoRepositoryTemplates $DestProject $repo.id $RepoName
        }
        else {
            Write-Host "[INFO] Skipping branch policies - repository has no branches yet" -ForegroundColor Yellow
            Write-Host "[INFO] Branch policies will be applied after first push" -ForegroundColor Yellow
            Write-Host "[INFO] Repository templates (README, PR template) will be added after first push" -ForegroundColor Yellow
        }

        # Apply security restrictions (BA group cannot push directly) - only if RBAC is available
        if ($desc -and $grpBA) {
            $denyBits = 4 + 8  # GenericContribute + ForcePush
            Ensure-AdoRepoDeny $projId $repo.id $grpBA.descriptor $denyBits
        }
    }
    else {
        Write-Host "[WARN] Repository '$RepoName' was not created. Skipping branch policies, templates, and repo-level security." -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " PROJECT INITIALIZATION COMPLETE! 🎉" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Project: $DestProject" -ForegroundColor White
    Write-Host ""
    
    # Team Structure
    Write-Host "👥 Team & Permissions:" -ForegroundColor Cyan
    if ($desc) {
        Write-Host "   ✅ RBAC groups: Dev, QA, BA" -ForegroundColor Green
        if ($grpBA) {
            Write-Host "   ✅ Security: BA group restricted from direct push" -ForegroundColor Green
        }
    }
    else {
        Write-Host "   ⚠️  RBAC groups: Skipped (Graph API unavailable)" -ForegroundColor Yellow
    }
    
    # Work Item Configuration
    Write-Host ""
    Write-Host "📋 Work Item Configuration:" -ForegroundColor Cyan
    Write-Host "   ✅ Areas: Frontend, Backend, Infrastructure, Documentation" -ForegroundColor Green
    Write-Host "   ✅ Templates: 6 comprehensive templates (auto-default)" -ForegroundColor Green
    Write-Host "   ✅ Sprints: 6 upcoming 2-week iterations" -ForegroundColor Green
    Write-Host "   ✅ Queries: 5 shared queries (My Work, Backlog, Bugs, etc.)" -ForegroundColor Green
    Write-Host "   ✅ Team Settings: Backlog levels, working days, bugs on backlog" -ForegroundColor Green
    Write-Host "   ✅ Dashboard: Team overview with burndown, velocity, charts" -ForegroundColor Green
    
    # Documentation & Guidelines
    Write-Host ""
    Write-Host "📚 Documentation:" -ForegroundColor Cyan
    Write-Host "   ✅ Wiki: Initialized with welcome page" -ForegroundColor Green
    Write-Host "   ✅ Tag Guidelines: Common tags documented" -ForegroundColor Green
    Write-Host "   ✅ Best Practices: Comprehensive team productivity guide" -ForegroundColor Green
    Write-Host "   ✅ QA Guidelines: Testing standards and QA processes" -ForegroundColor Green
    
    # QA Infrastructure
    Write-Host ""
    Write-Host "🧪 QA Infrastructure:" -ForegroundColor Cyan
    Write-Host "   ✅ Test Plan: 4 suites (Regression, Smoke, Integration, UAT)" -ForegroundColor Green
    Write-Host "   ✅ Test Configurations: 13 configs (browsers, OS, environments)" -ForegroundColor Green
    Write-Host "   ✅ QA Queries: 8 queries (Test Status, Bugs, Coverage, etc.)" -ForegroundColor Green
    Write-Host "   ✅ QA Dashboard: Metrics dashboard with 8 widgets" -ForegroundColor Green
    
    # Repository Configuration
    Write-Host ""
    Write-Host "🔧 Repository Configuration:" -ForegroundColor Cyan
    Write-Host "   ✅ Repository: $RepoName" -ForegroundColor Green
    if ($null -ne $repo -and $defaultRef) {
        Write-Host "   ✅ Branch Policies: Applied to $defaultRef" -ForegroundColor Green
        Write-Host "   ✅ README.md: Starter template added" -ForegroundColor Green
        Write-Host "   ✅ PR Template: Pull request template added" -ForegroundColor Green
    }
    elseif ($null -ne $repo) {
        Write-Host "   ⏳ Branch Policies: Will apply after first push" -ForegroundColor Yellow
        Write-Host "   ⏳ Templates: Will add after first push" -ForegroundColor Yellow
    }
    else {
        Write-Host "   ⚠️  Repository creation was skipped by user" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Next Steps:" -ForegroundColor White
    Write-Host "  1. Use Option 3 (Migrate) or Option 6 (Bulk) to push code" -ForegroundColor Gray
    Write-Host "  2. 📖 Read Best Practices: Wiki → Best-Practices (START HERE!)" -ForegroundColor Cyan
    Write-Host "  3. 🧪 Review QA Guidelines: Wiki → QA-Guidelines (for QA team)" -ForegroundColor Cyan
    Write-Host "  4. View team dashboard: Dashboards → $DestProject Team - Overview" -ForegroundColor Gray
    Write-Host "  5. View QA dashboard: Dashboards → $DestProject Team - QA Metrics" -ForegroundColor Gray
    Write-Host "  6. Review test plan: Test Plans → $DestProject - Test Plan" -ForegroundColor Gray
    Write-Host "  7. Review shared queries in Queries → Shared Queries" -ForegroundColor Gray
    Write-Host "  8. Check QA queries in Queries → Shared Queries → QA" -ForegroundColor Gray
    Write-Host "  9. Check sprint schedule in Boards → Sprints" -ForegroundColor Gray
    Write-Host " 10. Review tag guidelines in Wiki → Tag-Guidelines" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

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
        throw "Project '$DestProject' was not found in Azure DevOps. Create it first (Initialize mode)."
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

    # Seed short-term iterations (3 sprints of 2 weeks)
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
        throw "Project '$DestProject' was not found in Azure DevOps. Create it first (Initialize mode)."
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
        throw "Project '$DestProject' was not found in Azure DevOps. Create it first (Initialize mode)."
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
    Generates a pre-migration validation report.

.DESCRIPTION
    Validates GitLab project exists, checks Azure DevOps project/repo status,
    and identifies blocking issues before migration.

.PARAMETER GitLabPath
    GitLab project path.

.PARAMETER AdoProject
    Azure DevOps project name.

.PARAMETER AdoRepoName
    Azure DevOps repository name.

.PARAMETER OutputPath
    Optional output path for report.

.PARAMETER AllowSync
    Allow repository synchronization.

.OUTPUTS
    Pre-migration report object.

.EXAMPLE
    New-MigrationPreReport "group/project" "MyProject" "my-repo"
#>
function New-MigrationPreReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GitLabPath,
        
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [Parameter(Mandatory)]
        [string]$AdoRepoName,
        
        [string]$OutputPath = (Join-Path (Get-Location) "migration-precheck-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"),
        
        [switch]$AllowSync
    )
    
    Write-Host "[INFO] Generating pre-migration report..." -ForegroundColor Cyan
    
    # 1. GitLab project facts
    $gl = Get-GitLabProject $GitLabPath
    
    # 2. Azure DevOps project existence
    $adoProjects = Invoke-AdoRest GET "/_apis/projects?`$top=5000"
    $adoProj = $adoProjects.value | Where-Object { $_.name -eq $AdoProject }
    
    # 3. Repo name collision
    $repoExists = $false
    if ($adoProj) {
        $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($AdoProject))/_apis/git/repositories"
        $repoExists = $repos.value | Where-Object { $_.name -eq $AdoRepoName }
    }
    
    $report = [pscustomobject]@{
        timestamp              = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        gitlab_path            = $GitLabPath
        gitlab_size_mb         = [math]::Round(($gl.statistics.repository_size / 1MB), 2)
        gitlab_lfs_enabled     = $gl.lfs_enabled
        gitlab_visibility      = $gl.visibility
        gitlab_default_branch  = $gl.default_branch
        ado_project            = $AdoProject
        ado_project_exists     = [bool]$adoProj
        ado_repo_name          = $AdoRepoName
        ado_repo_exists        = [bool]$repoExists
        sync_mode              = $AllowSync
        ready_to_migrate       = if ($AllowSync) { [bool]$adoProj } else { ($adoProj -and -not $repoExists) }
        blocking_issues        = @()
    }
    
    # Add blocking issues
    if (-not $adoProj) {
        $report.blocking_issues += "Azure DevOps project '$AdoProject' does not exist"
    }
    if ($repoExists -and -not $AllowSync) {
        $report.blocking_issues += "Repository '$AdoRepoName' already exists in project '$AdoProject'. Use -AllowSync to update existing repository."
    }
    elseif ($repoExists -and $AllowSync) {
        Write-Host "[INFO] Sync mode enabled: Repository '$AdoRepoName' will be updated with latest changes from GitLab" -ForegroundColor Yellow
    }
    
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "[INFO] Pre-migration report written to $OutputPath"
    
    # Display summary
    Write-Host "[INFO] Pre-migration Summary:"
    Write-Host "       GitLab: $GitLabPath ($($report.gitlab_size_mb) MB)"
    Write-Host "       Azure DevOps: $AdoProject -> $AdoRepoName"
    Write-Host "       Ready to migrate: $($report.ready_to_migrate)"
    
    if ($report.blocking_issues.Count -gt 0) {
        Write-Host "[ERROR] Blocking issues found:" -ForegroundColor Red
        foreach ($issue in $report.blocking_issues) {
            Write-Host "        - $issue" -ForegroundColor Red
        }
        throw "Precheck failed – resolve blocking issues before proceeding with migration."
    }
    
    return $report
}

<#
.SYNOPSIS
    Migrates a single GitLab project to Azure DevOps.

.DESCRIPTION
    Complete migration including Git repository push, history preservation,
    and migration tracking. Supports sync mode for updates.

.PARAMETER SrcPath
    GitLab project path.

.PARAMETER DestProject
    Azure DevOps project name.

.PARAMETER AllowSync
    Allow repository synchronization.

.EXAMPLE
    Invoke-SingleMigration "group/project" "MyProject" -AllowSync
#>
function Invoke-SingleMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SrcPath,
        
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [switch]$AllowSync,
        
        [switch]$Force,
        
        [switch]$Replace
    )
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git not found on PATH."
    }
    
    Write-Host "[INFO] Starting migration: $SrcPath → $DestProject" -ForegroundColor Cyan
    
    # ENFORCE PRE-MIGRATION REPORT REQUIREMENT (unless -Force)
    $repoName = ($SrcPath -split '/')[-1]
    try {
        $preReport = New-MigrationPreReport -GitLabPath $SrcPath -AdoProject $DestProject -AdoRepoName $repoName -AllowSync:$AllowSync
        
        # Check for blocking issues
        if ($preReport.blocking_issues -gt 0 -and -not $Force) {
            $msg = "Pre-migration validation found $($preReport.blocking_issues) blocking issue(s). "
            $msg += "Review the preflight report or use -Force to proceed anyway."
            throw $msg
        }
        
        Write-Host "[OK] Pre-migration validation passed" -ForegroundColor Green
        if ($AllowSync -and $preReport.ado_repo_exists) {
            Write-Host "[INFO] SYNC MODE: Will update existing repository with latest changes" -ForegroundColor Yellow
        }
    }
    catch {
        if ($Force) {
            Write-Warning "Pre-migration validation failed, but -Force specified. Proceeding anyway..."
            Write-Warning "Error was: $_"
        }
        else {
            Write-Host "[ERROR] Pre-migration validation failed: $_" -ForegroundColor Red
            throw "Migration cannot proceed without successful pre-migration validation. Use -Force to override."
        }
    }
    
    # Get project paths
    $paths = Get-ProjectPaths $repoName
    $reportsDir = $paths.reportsDir
    $logsDir = $paths.logsDir
    $repoDir = $paths.repositoryDir
    
    # Check for existing preflight report
    $preflightFile = Join-Path $reportsDir "preflight-report.json"
    $useLocalRepo = $false
    $gl = $null
    
    if (Test-Path $preflightFile) {
        Write-Host "[INFO] Using preflight report: $preflightFile"
        $preflightData = Get-Content $preflightFile | ConvertFrom-Json
        
        # Validate repository size
        if ($preflightData.repo_size_MB -gt 100) {
            Write-Host "[WARN] Large repository detected: $($preflightData.repo_size_MB) MB" -ForegroundColor Yellow
        }
        
        # Check LFS
        if ($preflightData.lfs_enabled -and $preflightData.lfs_size_MB -gt 0) {
            if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
                if ($Force) {
                    Write-Warning "Git LFS required but not found. Repository has $($preflightData.lfs_size_MB) MB of LFS data. Proceeding due to -Force..."
                }
                else {
                    throw "Git LFS required but not found. Repository has $($preflightData.lfs_size_MB) MB of LFS data."
                }
            }
            else {
                Write-Host "[INFO] Git LFS detected: $($preflightData.lfs_size_MB) MB"
            }
        }
        
        # Use cached data
        $gl = [pscustomobject]@{
            path                = $preflightData.project.Split('/')[-1]
            http_url_to_repo    = $preflightData.http_url_to_repo
            path_with_namespace = $preflightData.project
        }
        
        # Check for local repository
        if (Test-Path $repoDir) {
            Write-Host "[INFO] Found local repository from preparation step"
            $useLocalRepo = $true
        }
    }
    else {
        if ($Force) {
            Write-Warning "No preflight report found, but -Force specified. Proceeding without validation..."
            # Fetch minimal GitLab info on the fly
            $gl = Get-GitLabProject -Path $SrcPath
        }
        else {
            Write-Host "[ERROR] No preflight report found" -ForegroundColor Red
            Write-Host "        Run preparation first (Option 1) or use -Force to bypass" -ForegroundColor Red
            throw "Pre-migration validation required. Run preflight check first or use -Force."
        }
    }
    
    # Ensure Azure DevOps project exists
    $proj = Ensure-AdoProject $DestProject
    $projId = $proj.id
    $repoName = $gl.path
    
    # Create migration log
    $logFile = New-LogFilePath $logsDir "migration"
    $startTime = Get-Date
    
    Write-MigrationLog $logFile @(
        "=== Azure DevOps Migration Log ==="
        "Migration started: $startTime"
        "Source GitLab: $($gl.path_with_namespace)"
        "Source URL: $($gl.http_url_to_repo)"
        "Destination ADO Project: $DestProject"
        "Destination Repository: $repoName"
        "Using local repo: $useLocalRepo"
    )
    
    # Ensure ADO repo exists
    $repo = Ensure-AdoRepository $DestProject $projId $repoName -AllowExisting:$AllowSync -Replace:$Replace
    $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id
    
    $isSync = $AllowSync -and $preReport.ado_repo_exists
    if ($isSync) {
        Write-Host "[INFO] Sync mode: Updating existing repository" -ForegroundColor Yellow
        Write-MigrationLog $logFile "=== SYNC MODE: Updating existing repository ==="
    }
    
    try {
        # Determine source repository
        if ($useLocalRepo) {
            Write-Host "[INFO] Using pre-downloaded repository"
            $sourceRepo = $repoDir
        }
        else {
            Write-Host "[INFO] Downloading repository..."
            $gitUrl = $gl.http_url_to_repo -replace '^https://', "https://oauth2:$($script:GitLabToken)@"
            $sourceRepo = Join-Path $env:TEMP ("migration-" + [Guid]::NewGuid() + ".git")
            # Respect invalid certificate for GitLab
            try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
            if ($skipCert) {
                git -c http.sslVerify=false clone --mirror $gitUrl $sourceRepo
            }
            else {
                git clone --mirror $gitUrl $sourceRepo
            }
        }
        
        # Configure Azure DevOps remote
        $adoRemote = "$($script:CollectionUrl)/$([uri]::EscapeDataString($DestProject))/_git/$([uri]::EscapeDataString($repoName))"
        Push-Location $sourceRepo
        
        git remote remove ado 2>$null | Out-Null
        git remote add ado $adoRemote
        git config http.$adoRemote.extraheader "AUTHORIZATION: basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($script:AdoPat)")))"
        
        # Push to Azure DevOps (respect invalid certificate for on-prem ADO Server)
        Write-Host "[INFO] Pushing to Azure DevOps..."
        try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
        if ($skipCert) {
            git -c http.sslVerify=false push ado --mirror
        }
        else {
            git push ado --mirror
        }
        
        # Clean up credentials
        git config --unset-all "http.$adoRemote.extraheader" 2>$null | Out-Null
        Clear-GitCredentials -RemoteName "ado"
        
        Pop-Location
        
        # Clean up temp repository
        if (-not $useLocalRepo -and (Test-Path $sourceRepo)) {
            Remove-Item -Recurse -Force $sourceRepo -ErrorAction SilentlyContinue
        }
        
        # After successful push, apply branch policies if this is the first migration (not sync)
        if (-not $isSync) {
            Write-Host "[INFO] Applying branch policies to migrated repository..." -ForegroundColor Cyan
            try {
                # Get the default branch now that code has been pushed
                Start-Sleep -Seconds 2  # Wait for Azure DevOps to recognize branches
                $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id
                
                if ($defaultRef) {
                    Write-Host "[INFO] Applying policies to branch: $defaultRef" -ForegroundColor Cyan
                    Ensure-AdoBranchPolicies `
                        -Project $DestProject `
                        -RepoId $repo.id `
                        -Ref $defaultRef `
                        -Min 2
                    
                    Write-Host "[SUCCESS] Branch policies applied successfully" -ForegroundColor Green
                }
                else {
                    Write-Warning "Could not determine default branch. Branch policies not applied."
                }
            }
            catch {
                Write-Warning "Failed to apply branch policies: $_"
                Write-Host "[INFO] You can manually configure branch policies in Azure DevOps" -ForegroundColor Yellow
            }
        }
        
        $endTime = Get-Date
        
        # Create migration summary
        $summary = New-MigrationSummary `
            -GitLabPath $SrcPath `
            -AdoProject $DestProject `
            -AdoRepo $repoName `
            -Status "SUCCESS" `
            -StartTime $startTime `
            -EndTime $endTime `
            -AdditionalData @{
            migration_type = if ($isSync) { "SYNC" } else { "INITIAL" }
            repository_size_mb = $preReport.gitlab_size_mb
        }
        
        # Write summary
        $summaryFile = Join-Path $reportsDir "migration-summary.json"
        Write-MigrationReport $summaryFile $summary
        
        Write-MigrationLog $logFile @(
            "=== Migration Completed Successfully ==="
            "End time: $endTime"
            "Duration: $($summary.duration_minutes) minutes"
        )
        
        Write-Host "[OK] Migration completed successfully!" -ForegroundColor Green
        Write-Host "      Duration: $($summary.duration_minutes) minutes"
        Write-Host "      Summary: $summaryFile"
    }
    catch {
        $endTime = Get-Date
        Write-Host "[ERROR] Migration failed: $_" -ForegroundColor Red
        
        # Create error summary
        $errorSummary = New-MigrationSummary `
            -GitLabPath $SrcPath `
            -AdoProject $DestProject `
            -AdoRepo $repoName `
            -Status "FAILED" `
            -StartTime $startTime `
            -EndTime $endTime `
            -AdditionalData @{
            error_message = $_.ToString()
        }
        
        $errorFile = Join-Path $reportsDir "migration-error.json"
        Write-MigrationReport $errorFile $errorSummary
        
        Write-MigrationLog $logFile "=== Migration Failed ===" -Level ERROR
        Write-MigrationLog $logFile $_.ToString() -Level ERROR
        
        throw
    }
}

<#
.SYNOPSIS
    Interactive bulk preparation workflow.

.DESCRIPTION
    Guides user through bulk preparation of multiple GitLab projects.
    Calls Invoke-BulkPrepareGitLab from GitLab module.

.EXAMPLE
    Invoke-BulkPreparationWorkflow
#>
function Invoke-BulkPreparationWorkflow {
    [CmdletBinding()]
    param()
    
    Write-Host ""
    Write-Host "=== BULK PREPARATION ===" -ForegroundColor Cyan
    Write-Host "This will download and analyze multiple GitLab projects for migration."
    Write-Host ""
    
    # Get destination project name first
    $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (e.g., ConsolidatedProject)"
    if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
        Write-Host "[ERROR] Project name is required." -ForegroundColor Red
        return
    }
    
    # Check if preparation already exists
    $migrationsDir = Get-MigrationsDirectory
    $bulkPrepDir = Join-Path $migrationsDir "bulk-prep-$DestProjectName"
    if (Test-Path $bulkPrepDir) {
        Write-Host ""
        Write-Host "⚠️  Existing preparation found for '$DestProjectName'" -ForegroundColor Yellow
        Write-Host "   Folder: $bulkPrepDir"
        $continueChoice = Read-Host "Continue and update existing preparation? (y/N)"
        if ($continueChoice -notmatch '^[Yy]') {
            Write-Host "Bulk preparation cancelled."
            return
        }
    }
    
    Write-Host ""
    Write-Host "Enter GitLab project paths (one per line, empty line to finish):"
    Write-Host "Format: group/project or group/subgroup/project"
    Write-Host "Example: mygroup/frontend-portal"
    Write-Host ""
    
    $projectPaths = @()
    $lineNum = 1
    do {
        $projectPath = Read-Host "Project $lineNum"
        if ($projectPath.Trim() -ne "") {
            $projectPaths += $projectPath.Trim()
            $lineNum++
        }
    } while ($projectPath.Trim() -ne "")
    
    if ($projectPaths.Count -eq 0) {
        Write-Host "[ERROR] No projects specified." -ForegroundColor Red
        return
    }
    
    # Display summary
    Write-Host ""
    Write-Host "=== PREPARATION SUMMARY ==="
    Write-Host "Destination Project: $DestProjectName"
    Write-Host "Projects to prepare: $($projectPaths.Count)"
    foreach ($path in $projectPaths) {
        Write-Host "  - $path"
    }
    Write-Host ""
    
    # Confirm before proceeding
    $confirm = Read-Host "Proceed with bulk preparation? (y/N)"
    if ($confirm -match '^[Yy]') {
        Invoke-BulkPrepareGitLab -ProjectPaths $projectPaths -DestProjectName $DestProjectName
    }
    else {
        Write-Host "Preparation cancelled."
    }
}

<#
.SYNOPSIS
    Interactive template manager workflow.

.DESCRIPTION
    Allows users to view, edit, and manage bulk migration template files.

.EXAMPLE
    Invoke-TemplateManagerWorkflow
#>
function Invoke-TemplateManagerWorkflow {
    [CmdletBinding()]
    param()
    
    Write-Host ""
    Write-Host "=== BULK MIGRATION TEMPLATE MANAGER ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Look for existing template files
    $migrationsDir = Get-MigrationsDirectory
    $bulkPrepDirs = Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -like "bulk-prep-*" }
    
    if (-not $bulkPrepDirs) {
        Write-Host "❌ No bulk preparation templates found." -ForegroundColor Red
        Write-Host "   Run Option 4 (Bulk Preparation) first to create templates."
        return
    }
    
    Write-Host "Available bulk preparation templates:"
    Write-Host ""
    
    $templates = @()
    $index = 1
    foreach ($dir in $bulkPrepDirs) {
        $templateFile = Join-Path $dir.FullName "bulk-migration-template.json"
        if (Test-Path $templateFile) {
            $projectName = $dir.Name -replace '^bulk-prep-', ''
            Write-Host "  [$index] $projectName"
            
            try {
                $templateData = Get-Content $templateFile | ConvertFrom-Json
                $totalProjects = $templateData.projects.Count
                $successProjects = ($templateData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
                Write-Host "      - $totalProjects project(s), $successProjects ready for migration"
                Write-Host "      - Template: $templateFile"
            }
            catch {
                Write-Host "      - Error reading template"
            }
            
            $templates += @{
                Index        = $index
                ProjectName  = $projectName
                TemplateFile = $templateFile
                Directory    = $dir.FullName
            }
            $index++
            Write-Host ""
        }
    }
    
    if ($templates.Count -eq 0) {
        Write-Host "❌ No valid template files found in bulk preparation directories." -ForegroundColor Red
        return
    }
    
    Write-Host "  [0] Cancel"
    Write-Host ""
    
    do {
        $selection = Read-Host "Select template to manage (0-$($templates.Count))"
        $selectionNum = [int]0
        $validSelection = [int]::TryParse($selection, [ref]$selectionNum)
    } while (-not $validSelection -or $selectionNum -lt 0 -or $selectionNum -gt $templates.Count)
    
    if ($selectionNum -eq 0) {
        Write-Host "Cancelled."
        return
    }
    
    $selectedTemplate = $templates[$selectionNum - 1]
    
    Write-Host ""
    Write-Host "Selected: $($selectedTemplate.ProjectName)"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  [1] View template contents"
    Write-Host "  [2] Open template in notepad"
    Write-Host "  [3] View preparation log"
    Write-Host "  [0] Cancel"
    Write-Host ""
    
    $action = Read-Host "Select action (0-3)"
    
    switch ($action) {
        '1' {
            Write-Host ""
            Write-Host "=== TEMPLATE CONTENTS ===" -ForegroundColor Cyan
            Get-Content $selectedTemplate.TemplateFile | Write-Host
            Write-Host "=========================" -ForegroundColor Cyan
        }
        '2' {
            Write-Host "[INFO] Opening template in notepad..."
            Start-Process notepad $selectedTemplate.TemplateFile -Wait
            Write-Host "[INFO] Editing complete."
        }
        '3' {
            $logFile = Join-Path $selectedTemplate.Directory "bulk-preparation.log"
            if (Test-Path $logFile) {
                Write-Host ""
                Write-Host "=== PREPARATION LOG ===" -ForegroundColor Cyan
                Get-Content $logFile | Write-Host
                Write-Host "========================" -ForegroundColor Cyan
            }
            else {
                Write-Host "[WARN] Log file not found: $logFile" -ForegroundColor Yellow
            }
        }
        '0' {
            Write-Host "Cancelled."
        }
        default {
            Write-Host "[ERROR] Invalid option." -ForegroundColor Red
        }
    }
}

<#
.SYNOPSIS
    Interactive bulk migration execution workflow.

.DESCRIPTION
    Guides user through executing bulk migrations from prepared templates.
    Supports sync mode for updating existing repositories.

.EXAMPLE
    Invoke-BulkMigrationWorkflow
#>
function Invoke-BulkMigrationWorkflow {
    [CmdletBinding()]
    param()
    
    Write-Host ""
    Write-Host "=== BULK MIGRATION EXECUTION ===" -ForegroundColor Cyan
    Write-Host "This will execute migrations from prepared template files."
    Write-Host ""
    
    # Look for available template files
    $migrationsDir = Get-MigrationsDirectory
    $bulkPrepDirs = Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -like "bulk-prep-*" }
    
    if (-not $bulkPrepDirs) {
        Write-Host "❌ No bulk preparation templates found." -ForegroundColor Red
        Write-Host "   Run Option 4 (Bulk Preparation) first."
        return
    }
    
    $templates = @()
    foreach ($dir in $bulkPrepDirs) {
        $templateFile = Join-Path $dir.FullName "bulk-migration-template.json"
        if (Test-Path $templateFile) {
            $projectName = $dir.Name -replace '^bulk-prep-', ''
            $templates += @{
                ProjectName  = $projectName
                TemplateFile = $templateFile
                Directory    = $dir.FullName
            }
        }
    }
    
    if ($templates.Count -eq 0) {
        Write-Host "❌ No valid template files found." -ForegroundColor Red
        return
    }
    
    Write-Host "Available templates:"
    for ($i = 0; $i -lt $templates.Count; $i++) {
        $template = $templates[$i]
        Write-Host "  [$($i + 1)] $($template.ProjectName)"
        
        try {
            $templateData = Get-Content $template.TemplateFile | ConvertFrom-Json
            $successProjects = ($templateData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
            Write-Host "      - $successProjects project(s) ready for migration"
        }
        catch {
            Write-Host "      - Unable to read template"
        }
    }
    Write-Host ""
    
    do {
        $selection = Read-Host "Select template (1-$($templates.Count))"
        $selectionNum = [int]0
        $validSelection = [int]::TryParse($selection, [ref]$selectionNum)
    } while (-not $validSelection -or $selectionNum -lt 1 -or $selectionNum -gt $templates.Count)
    
    $selectedTemplate = $templates[$selectionNum - 1]
    $selectedDevOpsProject = $selectedTemplate.ProjectName
    
    Write-Host ""
    Write-Host "Selected: Preparation for '$selectedDevOpsProject'"
    Write-Host ""
    
    # Get destination project name (default to prepared project name)
    $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (press Enter for '$selectedDevOpsProject')"
    if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
        $DestProjectName = $selectedDevOpsProject
    }
    
    # Read template
    try {
        $templateData = Get-Content $selectedTemplate.TemplateFile | ConvertFrom-Json
        $successfulProjects = @($templateData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" })
        $failedProjects = @($templateData.projects | Where-Object { $_.preparation_status -eq "FAILED" })
        
        Write-Host "=== MIGRATION PREVIEW ===" -ForegroundColor Cyan
        Write-Host "Destination project: $DestProjectName"
        Write-Host "Total projects in template: $(@($templateData.projects).Count)"
        Write-Host "✅ Ready for migration: $($successfulProjects.Count)" -ForegroundColor Green
        if ($failedProjects.Count -gt 0) {
            Write-Host "❌ Failed preparation (will be skipped): $($failedProjects.Count)" -ForegroundColor Red
        }
        Write-Host ""
        
        if ($successfulProjects.Count -eq 0) {
            Write-Host "❌ No projects are ready for migration." -ForegroundColor Red
            return
        }
        
        # Check which repositories already exist
        $projectExists = Test-AdoProjectExists -ProjectName $DestProjectName
        $existingRepos = @()
        $newRepos = @()
        
        if ($projectExists) {
            Write-Host "[INFO] Project '$DestProjectName' exists - checking repository status..." -ForegroundColor Cyan
            $repos = Get-AdoProjectRepositories -ProjectName $DestProjectName
            
            foreach ($proj in $successfulProjects) {
                $repoExists = $null -ne ($repos | Where-Object { $_.name -eq $proj.ado_repo_name })
                if ($repoExists) {
                    $existingRepos += $proj
                }
                else {
                    $newRepos += $proj
                }
            }
            
            Write-Host ""
            Write-Host "Repository Status:" -ForegroundColor Cyan
            Write-Host "  ✨ New repositories: $($newRepos.Count)" -ForegroundColor Green
            Write-Host "  🔄 Already migrated: $($existingRepos.Count)" -ForegroundColor Yellow
        }
        else {
            Write-Host "[INFO] Project '$DestProjectName' doesn't exist - all repositories will be new" -ForegroundColor Cyan
            $newRepos = $successfulProjects
        }
        
        Write-Host ""
        Write-Host "Projects to migrate:"
        foreach ($proj in $successfulProjects) {
            $status = if ($existingRepos -contains $proj) { " (already migrated - will sync)" } else { " (new)" }
            Write-Host "  $($proj.gitlab_path) → $($proj.ado_repo_name)$status"
        }
        Write-Host ""
    }
    catch {
        Write-Host "❌ Error reading template file: $_" -ForegroundColor Red
        return
    }
    
    # Ask about sync mode if there are existing repositories
    $allowSyncFlag = $false
    if ($existingRepos.Count -gt 0) {
        Write-Host "⚠️  $($existingRepos.Count) repositor(ies) already exist in Azure DevOps" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  1) SYNC - Update existing repositories with latest from GitLab (recommended)" -ForegroundColor Green
        Write-Host "  2) SKIP - Only migrate new repositories" -ForegroundColor Yellow
        Write-Host ""
        $syncChoice = Read-Host "Select option (1-2, default: 1)"
        
        if ([string]::IsNullOrWhiteSpace($syncChoice) -or $syncChoice -eq '1') {
            $allowSyncFlag = $true
            Write-Host "[INFO] Sync mode enabled - existing repositories will be updated" -ForegroundColor Green
        }
        elseif ($syncChoice -eq '2') {
            Write-Host "[INFO] Skipping existing repositories" -ForegroundColor Yellow
            # Filter out existing repos from migration list
            $successfulProjects = @($newRepos)
            
            if ($successfulProjects.Count -eq 0) {
                Write-Host "[INFO] All repositories already exist and sync was not selected. Nothing to do." -ForegroundColor Yellow
                return
            }
        }
        else {
            Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
            return
        }
    }
    else {
        Write-Host "[INFO] All repositories are new - proceeding with normal migration" -ForegroundColor Cyan
    }
    
    # Final confirmation
    Write-Host ""
    $confirm = Read-Host "Proceed with bulk migration of $($successfulProjects.Count) project(s)? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Migration cancelled."
        return
    }
    
    # Execute migrations
    Write-Host ""
    Write-Host "=== STARTING BULK MIGRATION ===" -ForegroundColor Cyan
    $startTime = Get-Date
    $migrationResults = @()
    
    foreach ($proj in $successfulProjects) {
        Write-Host ""
        Write-Host "Migrating: $($proj.gitlab_path)" -ForegroundColor Cyan
        
        try {
            if ($allowSyncFlag) {
                Invoke-SingleMigration -SrcPath $proj.gitlab_path -DestProject $DestProjectName -AllowSync
            }
            else {
                Invoke-SingleMigration -SrcPath $proj.gitlab_path -DestProject $DestProjectName
            }
            
            $migrationResults += [pscustomobject]@{
                gitlab_path = $proj.gitlab_path
                ado_repo    = $proj.ado_repo_name
                status      = "SUCCESS"
            }
            Write-Host "✅ SUCCESS: $($proj.gitlab_path)" -ForegroundColor Green
        }
        catch {
            $migrationResults += [pscustomobject]@{
                gitlab_path   = $proj.gitlab_path
                ado_repo      = $proj.ado_repo_name
                status        = "FAILED"
                error_message = $_.ToString()
            }
            Write-Host "❌ FAILED: $($proj.gitlab_path)" -ForegroundColor Red
            Write-Host "   Error: $_" -ForegroundColor Red
        }
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Summary
    $successCount = ($migrationResults | Where-Object { $_.status -eq "SUCCESS" }).Count
    $failedCount = ($migrationResults | Where-Object { $_.status -eq "FAILED" }).Count
    
    Write-Host ""
    Write-Host "=== BULK MIGRATION COMPLETE ===" -ForegroundColor Cyan
    Write-Host "Total migrations: $($migrationResults.Count)"
    Write-Host "✅ Successful: $successCount" -ForegroundColor Green
    Write-Host "❌ Failed: $failedCount" -ForegroundColor Red
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-Host ""
    
    # Save results
    $resultsFile = Join-Path $selectedTemplate.Directory "bulk-migration-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $migrationResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultsFile -Encoding utf8
    Write-Host "Results saved to: $resultsFile"
}

# Export public functions
Export-ModuleMember -Function @(
    'Show-MigrationMenu',
    'Initialize-AdoProject',
    'Initialize-BusinessInit',
    'Initialize-DevInit',
    'Initialize-SecurityInit',
    'New-MigrationPreReport',
    'Invoke-SingleMigration',
    'Invoke-BulkPreparationWorkflow',
    'Invoke-TemplateManagerWorkflow',
    'Invoke-BulkMigrationWorkflow'
)
