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
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Module-level variables for menu context
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabToken = $null
$script:BuildDefinitionId = 0
$script:SonarStatusContext = ""

# Module-level constants for configuration defaults
$script:DEFAULT_SPRINT_COUNT = 6
$script:DEFAULT_SPRINT_DURATION_DAYS = 14
$script:DEFAULT_AREA_PATHS = @('Frontend', 'Backend', 'Infrastructure', 'Documentation')
$script:REPO_INIT_MAX_RETRIES = 5
$script:REPO_INIT_RETRY_DELAYS = @(2, 4, 8, 16, 32)  # Exponential backoff in seconds
$script:PARALLEL_WIKI_MAX_THREADS = 10
$script:BRANCH_POLICY_WAIT_SECONDS = 2

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
    Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $configFile = Join-Path $_.FullName "bulk-migration-config.json"
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile | ConvertFrom-Json
                foreach ($proj in $config.projects) {
                    $bulkProjectNames[$proj.ado_repo_name] = $true
                }
            }
            catch {
                Write-Verbose "Failed to read config: $configFile"
            }
        }
    }
    
    # Scan for single project preparations
    # New structure (v2.1.0+): Look for migration-config.json with migration_type="SINGLE"
    # Legacy structure: Look for reports/preflight-report.json (deprecated)
    Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | Where-Object {
        $bulkConfigFile = Join-Path $_.FullName "bulk-migration-config.json"
        $singleConfigFile = Join-Path $_.FullName "migration-config.json"
        $legacyReportFile = Join-Path $_.FullName "reports\preflight-report.json"
        
        # Not a bulk preparation AND (has single config OR has legacy report)
        -not (Test-Path $bulkConfigFile) -and 
        ((Test-Path $singleConfigFile) -or (Test-Path $legacyReportFile)) -and
        -not $bulkProjectNames.ContainsKey($_.Name)
    } | ForEach-Object {
        try {
            $singleConfigFile = Join-Path $_.FullName "migration-config.json"
            
            if (Test-Path $singleConfigFile) {
                # New self-contained structure (v2.1.0+)
                $config = Get-Content $singleConfigFile | ConvertFrom-Json
                
                # Find the GitLab project subfolder
                $gitlabDirs = Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -ne "reports" -and $_.Name -ne "logs" }
                
                if ($gitlabDirs) {
                    $gitlabDir = $gitlabDirs[0]
                    $reportFile = Join-Path $gitlabDir.FullName "reports\preflight-report.json"
                    
                    if (Test-Path $reportFile) {
                        $report = Get-Content $reportFile | ConvertFrom-Json
                        
                        # Check if project exists in Azure DevOps
                        $projectExists = Test-AdoProjectExists -ProjectName $config.ado_project
                        $repoMigrated = $false
                        if ($projectExists) {
                            $repos = Get-AdoProjectRepositories -ProjectName $config.ado_project
                            $repoMigrated = $repos | Where-Object { $_.name -eq $config.gitlab_repo_name }
                        }
                        
                        $prepared += [pscustomobject]@{
                            Type = "Single"
                            ProjectName = $config.ado_project
                            GitLabPath = $config.gitlab_project
                            GitLabRepoName = $config.gitlab_repo_name
                            RepoSizeMB = $report.repo_size_MB
                            PreparationTime = $config.created_date
                            Folder = $_.FullName
                            ConfigFile = $singleConfigFile
                            ProjectExists = $projectExists
                            RepoMigrated = $null -ne $repoMigrated
                            Structure = "v2.1.0"
                        }
                    }
                }
            }
            else {
                # Legacy flat structure (deprecated - for backward compat display only)
                $reportFile = Join-Path $_.FullName "reports\preflight-report.json"
                if (Test-Path $reportFile) {
                    $report = Get-Content $reportFile | ConvertFrom-Json
                    
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
                        Structure = "legacy"
                    }
                }
            }
        }
        catch {
            Write-Verbose "Failed to read preparation data from: $($_.FullName)"
        }
    }
    
    # Scan for bulk preparations (now self-contained with config file in root)
    Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $configFile = Join-Path $_.FullName "bulk-migration-config.json"
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile | ConvertFrom-Json
                $successfulCount = @($config.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
                
                # Check if project exists in Azure DevOps
                $projectExists = Test-AdoProjectExists -ProjectName $config.destination_project
                $migratedCount = 0
                if ($projectExists) {
                    $repos = Get-AdoProjectRepositories -ProjectName $config.destination_project
                    foreach ($proj in $config.projects) {
                        if ($repos | Where-Object { $_.name -eq $proj.ado_repo_name }) {
                            $migratedCount++
                        }
                    }
                }
                
                $prepared += [pscustomobject]@{
                    Type = "Bulk"
                    ProjectName = $config.destination_project
                    ProjectCount = $config.preparation_summary.total_projects
                    SuccessfulCount = $successfulCount
                    TotalSizeMB = $config.preparation_summary.total_size_MB
                    PreparationTime = $config.preparation_summary.preparation_time
                    Folder = $_.FullName
                    ConfigFile = $configFile
                    ProjectExists = $projectExists
                    MigratedCount = $migratedCount
                }
            }
            catch {
                Write-Verbose "Failed to read config: $configFile"
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
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     GitLab → Azure DevOps Migration Tool v2.1.0          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Prepare Single           " -ForegroundColor White -NoNewline
    Write-Host "│ Download & analyze single GitLab project" -ForegroundColor Gray
    Write-Host "  2) Prepare Bulk             " -ForegroundColor White -NoNewline
    Write-Host "│ Download & analyze multiple projects" -ForegroundColor Gray
    Write-Host "  3) Create DevOps Project    " -ForegroundColor White -NoNewline
    Write-Host "│ Initialize project + team packs" -ForegroundColor Gray
    Write-Host "  4) Start Planned Migration  " -ForegroundColor White -NoNewline
    Write-Host "│ Execute prepared migration (single/bulk)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  5) Exit" -ForegroundColor Yellow
    Write-Host ""
    
    $choice = Read-Host "Select option (1-5)"
    
    switch ($choice) {
        '1' {
            Write-Host ""
            Write-Host "=== SINGLE PROJECT PREPARATION ===" -ForegroundColor Cyan
            Write-Host "This will create a self-contained preparation folder."
            Write-Host ""
            
            $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
            if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                Write-Host "[ERROR] DevOps project name cannot be empty." -ForegroundColor Red
                return
            }
            
            $SourceProjectPath = Read-Host "Enter GitLab project path (e.g., group/my-project)"
            if ([string]::IsNullOrWhiteSpace($SourceProjectPath)) {
                Write-Host "[ERROR] GitLab project path cannot be empty." -ForegroundColor Red
                return
            }
            
            # Extract GitLab project name from path
            $gitlabProjectName = ($SourceProjectPath -split '/')[-1]
            
            # Use new self-contained structure
            $paths = Get-ProjectPaths -AdoProject $DestProjectName -GitLabProject $gitlabProjectName
            
            Write-Host ""
            Write-Host "[INFO] Preparing self-contained structure:"
            Write-Host "  Container: migrations/$DestProjectName/"
            Write-Host "  Project: $gitlabProjectName/"
            Write-Host ""
            
            # Prepare using custom base directory
            Prepare-GitLab -ProjectPath $SourceProjectPath -CustomBaseDir $paths.projectDir -CustomProjectName $gitlabProjectName
            
            # Create migration config
            $config = [pscustomobject]@{
                ado_project      = $DestProjectName
                gitlab_project   = $SourceProjectPath
                gitlab_repo_name = $gitlabProjectName
                migration_type   = "SINGLE"
                created_date     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                last_updated     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
                status           = "PREPARED"
            }
            
            $config | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $paths.configFile
            Write-Host "[INFO] Migration config created: $($paths.configFile)" -ForegroundColor Green
            
            # Generate HTML report after preparation
            try {
                $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $paths.configFile -Parent)
                if ($htmlReport) {
                    Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
                }
                
                # Update overview dashboard
                $overviewReport = New-MigrationsOverviewReport
                if ($overviewReport) {
                    Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
                }
            }
            catch {
                Write-Warning "Failed to generate HTML reports: $_"
            }
        }
        '2' {
            Invoke-BulkPreparationWorkflow
        }
        '3' {
            # Show prepared projects and create DevOps project (with team packs)
            $preparedProjects = Get-PreparedProjects
            
            if ($preparedProjects.Count -eq 0) {
                Write-Host ""
                Write-Host "No prepared projects found. Please run Option 1 or 2 first to prepare projects." -ForegroundColor Yellow
                Write-Host ""
                $createNew = Read-Host "Do you want to create a new independent Azure DevOps project? (y/N)"
                if ($createNew -match '^[Yy]') {
                    $DestProjectName = Read-Host "Enter Azure DevOps project name (e.g., MyProject)"
                    $RepoName = Read-Host "Enter initial repository name (e.g., my-repo)"
                    if (-not [string]::IsNullOrWhiteSpace($DestProjectName) -and -not [string]::IsNullOrWhiteSpace($RepoName)) {
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                        
                        # Offer team initialization packs after successful project creation
                        Invoke-TeamPackMenu -ProjectName $DestProjectName
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
            Write-Host "[INFO] Projects marked [v2.1.0] use self-contained folder structures (recommended)" -ForegroundColor Cyan
            Write-Host "[INFO] Projects marked [legacy] use flat folder structures (consider re-preparing)" -ForegroundColor DarkYellow
            Write-Host ""
            
            # Filter out already-created projects (keep only those not yet in Azure DevOps)
            $availableProjects = @($preparedProjects | Where-Object { -not $_.ProjectExists })
            
            if ($availableProjects.Count -eq 0) {
                Write-Host "[INFO] All prepared projects have already been created in Azure DevOps." -ForegroundColor Yellow
                Write-Host "[INFO] Use Option 4 (Start Migration) to sync repositories." -ForegroundColor Yellow
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
                        
                        # Offer team initialization packs after successful project creation
                        Invoke-TeamPackMenu -ProjectName $DestProjectName
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
                    $structureIndicator = if ($proj.Structure -eq "v2.1.0") { "[v2.1.0]" } else { "[legacy]" }
                    $structureColor = if ($proj.Structure -eq "v2.1.0") { "Green" } else { "Yellow" }
                    
                    Write-Host "  $($i + 1)) $($proj.ProjectName) (from $($proj.GitLabPath)) " -ForegroundColor White -NoNewline
                    Write-Host $structureIndicator -ForegroundColor $structureColor
                    Write-Host "      Size: $($proj.RepoSizeMB) MB | Prepared: $($proj.PreparationTime)" -ForegroundColor Gray
                }
                
                # Show helpful migration guidance if any legacy structures detected
                $legacyCount = @($singleProjects | Where-Object { $_.Structure -eq "legacy" }).Count
                if ($legacyCount -gt 0) {
                    Write-Host ""
                    Write-Host "  [NOTE] Legacy structures detected. Consider re-preparing with Option 1 for v2.1.0 self-contained folders." -ForegroundColor Yellow
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
                        
                        # Offer team initialization packs after successful project creation
                        Invoke-TeamPackMenu -ProjectName $DestProjectName
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
                        
                        # Offer team initialization packs after successful project creation
                        Invoke-TeamPackMenu -ProjectName $DestProjectName
                    }
                    elseif ($selectedProject.Type -eq "Bulk") {
                        $DestProjectName = Read-Host "Enter Azure DevOps project name (press Enter for '$($selectedProject.ProjectName)')"
                        if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
                            $DestProjectName = $selectedProject.ProjectName
                        }
                        
                        Write-Host ""
                        Write-Host "Initializing Azure DevOps project '$DestProjectName' for bulk migration..." -ForegroundColor Cyan
                        Write-Host "[INFO] This will create the project. Use Option 4 to migrate the repositories." -ForegroundColor Yellow
                        
                        # For bulk, create project without repository (repositories will be added during migration)
                        $tempRepoName = "initial-repo"
                        Initialize-AdoProject -DestProject $DestProjectName -RepoName $tempRepoName -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                        
                        # Offer team initialization packs after successful project creation
                        Invoke-TeamPackMenu -ProjectName $DestProjectName
                    }
                }
            }
            else {
                Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
            }
        }
        '4' {
            # Combined migration workflow - handles both single and bulk
            Write-Host ""
            Write-Host "=== START PLANNED MIGRATION ===" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Select migration type:" -ForegroundColor Cyan
            Write-Host "  1) Single Project Migration" -ForegroundColor White
            Write-Host "  2) Bulk Migration" -ForegroundColor White
            Write-Host ""
            
            $migrationChoice = Read-Host "Select option (1-2)"
            
            switch ($migrationChoice) {
                '1' {
                    # Single project migration (old option 3)
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
                            $syncChoice = Read-Host "Select option (1-3)"
                            
                            switch ($syncChoice) {
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
                '2' {
                    # Bulk migration (old option 6)
                    Invoke-BulkMigrationWorkflow
                }
                default {
                    Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
                }
            }
        }
        '5' {
            Write-Host ""
            Write-Host "Thank you for using GitLab → Azure DevOps Migration Tool" -ForegroundColor Cyan
            Write-Host "Goodbye! 👋" -ForegroundColor Green
            Write-Host ""
            return
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Invalid choice. Please select a number between 1 and 5." -ForegroundColor Red
            Write-Host ""
        }
    }
}

<#
.SYNOPSIS
    Presents team initialization pack options after project creation.

.DESCRIPTION
    Interactive sub-menu for selecting optional team initialization packs
    (Business, Development, Security, Management) to enhance a newly created
    Azure DevOps project.

.PARAMETER ProjectName
    Azure DevOps project name to apply team packs to.

.EXAMPLE
    Invoke-TeamPackMenu -ProjectName "MyProject"
#>
function Invoke-TeamPackMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
    
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│  OPTIONAL: Enhance with Team Initialization Packs      │" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Would you like to add specialized team resources?" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Business Team Pack       " -ForegroundColor White -NoNewline
    Write-Host "│ Stakeholder wiki, KPIs, roadmap" -ForegroundColor Gray
    Write-Host "  2) Development Team Pack    " -ForegroundColor White -NoNewline
    Write-Host "│ Dev wiki, architecture docs, repo files" -ForegroundColor Gray
    Write-Host "  3) Security Team Pack       " -ForegroundColor White -NoNewline
    Write-Host "│ Security policies, threat model, scanning" -ForegroundColor Gray
    Write-Host "  4) Management Team Pack     " -ForegroundColor White -NoNewline
    Write-Host "│ PMO wiki, RAID log, sprint planning" -ForegroundColor Gray
    Write-Host "  5) All Team Packs           " -ForegroundColor White -NoNewline
    Write-Host "│ Install all 4 packs" -ForegroundColor Gray
    Write-Host "  6) Skip                     " -ForegroundColor White -NoNewline
    Write-Host "│ Continue without team packs" -ForegroundColor Gray
    Write-Host ""
    
    $packChoice = Read-Host "Select option (1-6, default: 6)"
    
    if ([string]::IsNullOrWhiteSpace($packChoice)) {
        $packChoice = '6'
    }
    
    switch ($packChoice) {
        '1' {
            try {
                Write-Host ""
                Write-Host "[INFO] Provisioning Business Team Pack..." -ForegroundColor Cyan
                Initialize-BusinessInit -DestProject $ProjectName
                Write-Host "[SUCCESS] Business Team Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Business Initialization failed: $_" -ForegroundColor Red
            }
        }
        '2' {
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
                Write-Host ""
                Write-Host "[INFO] Provisioning Development Team Pack..." -ForegroundColor Cyan
                Initialize-DevInit -DestProject $ProjectName -ProjectType $projectType
                Write-Host "[SUCCESS] Development Team Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Development Initialization failed: $_" -ForegroundColor Red
            }
        }
        '3' {
            try {
                Write-Host ""
                Write-Host "[INFO] Provisioning Security Team Pack..." -ForegroundColor Cyan
                Initialize-SecurityInit -DestProject $ProjectName
                Write-Host "[SUCCESS] Security Team Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Security Initialization failed: $_" -ForegroundColor Red
            }
        }
        '4' {
            try {
                Write-Host ""
                Write-Host "[INFO] Provisioning Management Team Pack..." -ForegroundColor Cyan
                Initialize-ManagementInit -DestProject $ProjectName
                Write-Host "[SUCCESS] Management Team Pack completed" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Management Initialization failed: $_" -ForegroundColor Red
            }
        }
        '5' {
            try {
                Write-Host ""
                Write-Host "[INFO] Provisioning ALL Team Packs..." -ForegroundColor Cyan
                Write-Host "[INFO] This may take a few minutes..." -ForegroundColor Gray
                
                Write-Host "[INFO] 1/4: Business Team Pack..." -ForegroundColor Cyan
                Initialize-BusinessInit -DestProject $ProjectName
                
                Write-Host "[INFO] 2/4: Development Team Pack..." -ForegroundColor Cyan
                Initialize-DevInit -DestProject $ProjectName -ProjectType 'all'
                
                Write-Host "[INFO] 3/4: Security Team Pack..." -ForegroundColor Cyan
                Initialize-SecurityInit -DestProject $ProjectName
                
                Write-Host "[INFO] 4/4: Management Team Pack..." -ForegroundColor Cyan
                Initialize-ManagementInit -DestProject $ProjectName
                
                Write-Host ""
                Write-Host "[SUCCESS] All Team Packs completed! 🎉" -ForegroundColor Green
                Write-Host "[INFO] Your project now has comprehensive resources for all teams" -ForegroundColor Cyan
            }
            catch {
                Write-Host "[ERROR] Team pack installation failed: $_" -ForegroundColor Red
            }
        }
        '6' {
            Write-Host ""
            Write-Host "[INFO] Skipping team packs. You can add them later if needed." -ForegroundColor Gray
        }
        default {
            Write-Host ""
            Write-Host "[INFO] Invalid selection. Skipping team packs." -ForegroundColor Yellow
        }
    }
}

<#
.SYNOPSIS
    Initializes an Azure DevOps project with complete setup.

.DESCRIPTION
    Creates project, sets up RBAC groups, areas, wiki, work item templates,
    repository, and branch policies. Complete project scaffolding with checkpoint/resume support.
    Supports -WhatIf for preview mode.

.PARAMETER DestProject
    Azure DevOps project name.

.PARAMETER RepoName
    Repository name.

.PARAMETER BuildDefinitionId
    Optional build definition ID.

.PARAMETER SonarStatusContext
    Optional SonarQube context.

.PARAMETER ConfigFile
    Path to custom project-settings.json file. If not specified, uses default configuration.

.PARAMETER Areas
    Custom area names to create. Overrides configuration file. Example: @('Frontend', 'Backend', 'Mobile').

.PARAMETER SprintCount
    Number of sprints to create. Defaults to 6. Overrides configuration file.

.PARAMETER SprintDurationDays
    Sprint duration in days. Defaults to 14. Overrides configuration file.

.PARAMETER TeamName
    Custom team name. Defaults to '$DestProject Team'. Overrides default naming convention.

.PARAMETER TemplateDirectory
    Custom path to wiki template directory. Defaults to 'modules\templates'. 
    Allows organizations to use custom templates. Falls back to embedded templates if path invalid.

.PARAMETER Resume
    Resume from last checkpoint after previous failure. Skips completed steps.

.PARAMETER Force
    Force re-execution of all steps, ignoring checkpoints. Use with caution.

.PARAMETER WhatIf
    Shows what would happen if the cmdlet runs. No changes are made.

.PARAMETER Confirm
    Prompts for confirmation before executing each major step.

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -BuildDefinitionId 10

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -ConfigFile "my-settings.json"

.EXAMPLE
    Initialize-AdoProject "MyProject" "my-repo" -Areas @('API', 'UI', 'Database') -SprintCount 8 -SprintDurationDays 10

.EXAMPLE
    # Resume after failure
    Initialize-AdoProject "MyProject" "my-repo" -Resume

.EXAMPLE
    # Preview mode - see what would be created
    Initialize-AdoProject "MyProject" "my-repo" -WhatIf
#>
function Initialize-AdoProject {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$DestProject,
        
        [Parameter(Mandatory)]
        [ValidateScript({
            Test-AdoRepositoryName $_ -ThrowOnError
            $true
        })]
        [string]$RepoName,
        
        [int]$BuildDefinitionId = 0,
        
        [string]$SonarStatusContext = "",

        [string]$ConfigFile,

        [string[]]$Areas,

        [int]$SprintCount = 0,

        [int]$SprintDurationDays = 0,

        [string]$TeamName,

        [string]$TemplateDirectory,

        [switch]$Resume,

        [switch]$Force
    )
    
    Write-Host "[INFO] Initializing Azure DevOps project: $DestProject" -ForegroundColor Cyan
    
    # Helper function to load wiki template with fallback
    function Get-WikiTemplateContent {
        param(
            [string]$TemplateName,
            [string]$CustomDirectory = $null,
            [hashtable]$Replacements = @{}
        )
        
        # Embedded fallback templates
        $embeddedTemplates = @{
            'welcome-wiki' = @"
# Welcome to {{PROJECT_NAME}}

This project was migrated from GitLab using automated tooling.

## Project Structure

- **Frontend**: Web UI components
- **Backend**: API and services
- **Infrastructure**: DevOps and deployment
- **Documentation**: Technical docs and guides

## Getting Started

1. Clone the repository
2. Review branch policies
3. Check work item templates
"@
            'TagGuidelines' = @"
# Tag Guidelines

## Standard Tags

Use these tags to categorize work items:

- **Priority**: P0, P1, P2, P3
- **Status**: InProgress, Blocked, Review
- **Type**: Feature, Bug, TechDebt, Refactor

## Best Practices

- Use consistent tag naming
- Review tags during sprint planning
- Update tags as work progresses
"@
            'ComponentTags' = @"
# Component Tags

## Components

- Frontend
- Backend
- Database
- Infrastructure
- Documentation
- Testing

Tag work items by component for better tracking.
"@
        }
        
        $content = $null
        
        # Try custom directory first
        if ($CustomDirectory) {
            $customPath = Join-Path $CustomDirectory "$TemplateName.md"
            if (Test-Path $customPath) {
                try {
                    $content = Get-Content -Path $customPath -Raw -Encoding UTF8
                    Write-Verbose "[Get-WikiTemplateContent] Loaded from custom directory: $customPath"
                }
                catch {
                    Write-Warning "Failed to load custom template '$customPath': $_"
                }
            }
            else {
                Write-Verbose "[Get-WikiTemplateContent] Custom template not found: $customPath"
            }
        }
        
        # Try default templates directory
        if (-not $content) {
            $defaultPath = Join-Path $PSScriptRoot "templates\$TemplateName.md"
            if (Test-Path $defaultPath) {
                try {
                    $content = Get-Content -Path $defaultPath -Raw -Encoding UTF8
                    Write-Verbose "[Get-WikiTemplateContent] Loaded from default directory: $defaultPath"
                }
                catch {
                    Write-Warning "Failed to load default template '$defaultPath': $_"
                }
            }
            else {
                Write-Verbose "[Get-WikiTemplateContent] Default template not found: $defaultPath"
            }
        }
        
        # Fall back to embedded template
        if (-not $content -and $embeddedTemplates.ContainsKey($TemplateName)) {
            $content = $embeddedTemplates[$TemplateName]
            Write-Verbose "[Get-WikiTemplateContent] Using embedded fallback template for: $TemplateName"
        }
        
        # Apply replacements
        if ($content -and $Replacements.Count -gt 0) {
            foreach ($key in $Replacements.Keys) {
                $content = $content -replace [regex]::Escape($key), $Replacements[$key]
            }
        }
        
        if (-not $content) {
            Write-Warning "No template found for '$TemplateName' (checked custom, default, and embedded)"
            return "# $TemplateName`n`nTemplate not available."
        }
        
        return $content
    }
    
    # Load configuration early for preview mode
    Write-Verbose "[Initialize-AdoProject] Loading project configuration..."
    try {
        $config = if ($ConfigFile) {
            Get-ProjectSettings -ConfigFile $ConfigFile
        } else {
            Get-ProjectSettings  # Uses default from ConfigLoader
        }
        Write-Verbose "[Initialize-AdoProject] Configuration loaded successfully"
    }
    catch {
        Write-Warning "Failed to load configuration: $_. Using embedded defaults."
        # Fallback to hardcoded defaults if ConfigLoader fails
        $config = [PSCustomObject]@{
            areas = @(
                @{ name = 'Frontend'; description = 'Frontend development' }
                @{ name = 'Backend'; description = 'Backend development' }
                @{ name = 'Infrastructure'; description = 'Infrastructure and DevOps' }
                @{ name = 'Documentation'; description = 'Documentation and guides' }
            )
            iterations = @{
                sprintCount = 6
                sprintDurationDays = 14
                sprintPrefix = 'Sprint'
            }
            processTemplate = 'Agile'
            team = @{
                nameSuffix = ' Team'
            }
        }
    }

    # Apply parameter overrides to configuration
    if ($Areas) {
        Write-Verbose "[Initialize-AdoProject] Overriding areas from parameter: $($Areas -join ', ')"
        $config.areas = $Areas | ForEach-Object { @{ name = $_; description = "Area: $_" } }
    }
    if ($SprintCount -gt 0) {
        Write-Verbose "[Initialize-AdoProject] Overriding sprint count from parameter: $SprintCount"
        $config.iterations.sprintCount = $SprintCount
    }
    if ($SprintDurationDays -gt 0) {
        Write-Verbose "[Initialize-AdoProject] Overriding sprint duration from parameter: $SprintDurationDays days"
        $config.iterations.sprintDurationDays = $SprintDurationDays
    }

    # Determine team name (parameter > config > default pattern)
    $effectiveTeamName = if ($TeamName) {
        $TeamName
    } elseif ($config.team -and $config.team.nameSuffix) {
        "$DestProject$($config.team.nameSuffix)"
    } else {
        "$DestProject Team"
    }
    Write-Verbose "[Initialize-AdoProject] Using team name: $effectiveTeamName"
    
    # Display preview summary in WhatIf mode
    if ($WhatIfPreference) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " INITIALIZATION PREVIEW" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Project Configuration:" -ForegroundColor Yellow
        Write-Host "  Project Name: $DestProject" -ForegroundColor White
        Write-Host "  Repository: $RepoName" -ForegroundColor White
        Write-Host "  Team Name: $effectiveTeamName" -ForegroundColor White
        Write-Host "  Process Template: $($config.processTemplate)" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Would create:" -ForegroundColor Yellow
        Write-Host "  ✓ 1 Azure DevOps project" -ForegroundColor White
        Write-Host "  ✓ $($config.areas.Count) work item areas: $($config.areas.name -join ', ')" -ForegroundColor White
        Write-Host "  ✓ $($config.iterations.sprintCount) sprint iterations ($($config.iterations.sprintDurationDays) days each)" -ForegroundColor White
        Write-Host "  ✓ 1 project wiki with home page" -ForegroundColor White
        Write-Host "  ✓ 7 work item templates (User Story, Task, Bug, Epic, Feature, Test Case, Issue)" -ForegroundColor White
        Write-Host "  ✓ 8 shared queries (My Work, Team Work, Bugs, etc.)" -ForegroundColor White
        Write-Host "  ✓ 1 team dashboard with widgets" -ForegroundColor White
        Write-Host "  ✓ 2 additional wiki pages (Common Tags, Best Practices)" -ForegroundColor White
        Write-Host "  ✓ QA infrastructure (Test Plan, QA Queries, QA Dashboard, Test Configurations, QA Guidelines)" -ForegroundColor White
        Write-Host "  ✓ 1 Git repository: $RepoName" -ForegroundColor White
        
        if ($BuildDefinitionId -gt 0) {
            Write-Host "  ✓ Branch policies with build validation (Build ID: $BuildDefinitionId)" -ForegroundColor White
        } else {
            Write-Host "  ✓ Branch policies (minimum 2 reviewers)" -ForegroundColor White
        }
        
        if ($SonarStatusContext) {
            Write-Host "  ✓ SonarQube status check: $SonarStatusContext" -ForegroundColor White
        }
        
        Write-Host "  ✓ Repository templates (README.md, Pull Request template)" -ForegroundColor White
        Write-Host ""
        Write-Host "Total estimated time: 15-30 seconds (with parallel execution)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To execute, run without -WhatIf:" -ForegroundColor Cyan
        Write-Host "  Initialize-AdoProject '$DestProject' '$RepoName'" -ForegroundColor White
        Write-Host ""
        return
    }
    
    Write-Host "[NOTE] You may see some 404 errors - these are normal when checking if resources already exist" -ForegroundColor Gray
    
    # Track execution timing for performance metrics
    $executionStartTime = Get-Date
    $stepTiming = @{}
    
    # Define total steps for progress tracking
    $totalSteps = 13
    $currentStep = 0
    $progressActivity = "Initializing Azure DevOps Project: $DestProject"
    
    # Initialize checkpoint system
    $checkpointFile = Join-Path (Join-Path (Split-Path $PSScriptRoot) "migrations") "$DestProject\.init-checkpoint.json"
    $checkpointDir = Split-Path $checkpointFile -Parent
    
    # Load existing checkpoint if resuming
    $checkpoint = @{
        project = $false
        areas = $false
        wiki = $false
        templates = $false
        iterations = $false
        queries = $false
        teamSettings = $false
        dashboard = $false
        wikiPages = $false
        qaInfrastructure = $false
        repository = $false
        branchPolicies = $false
        repositoryTemplates = $false
        completed = $false
        lastUpdate = $null
        errors = @()
    }
    
    if ($Resume.IsPresent -and (Test-Path $checkpointFile)) {
        try {
            $savedCheckpoint = Get-Content $checkpointFile -Raw | ConvertFrom-Json
            Write-Host "[INFO] 📋 Resuming from previous checkpoint..." -ForegroundColor Cyan
            
            # Merge saved checkpoint
            foreach ($key in $checkpoint.Keys) {
                if ($null -ne $savedCheckpoint.$key) {
                    $checkpoint[$key] = $savedCheckpoint.$key
                }
            }
            
            # Display resume summary
            $completedSteps = ($checkpoint.GetEnumerator() | Where-Object { $_.Value -eq $true -and $_.Key -ne 'completed' }).Count
            Write-Host "[INFO] ✓ $completedSteps steps already completed, continuing from there..." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to load checkpoint: $_. Starting from beginning."
            $Resume = $false
        }
    }
    elseif ($Resume.IsPresent) {
        Write-Warning "No checkpoint found for project '$DestProject'. Starting from beginning."
        $Resume = $false
    }
    
    if ($Force.IsPresent) {
        Write-Host "[INFO] 🔄 Force mode enabled - re-executing all steps" -ForegroundColor Yellow
        # Reset checkpoint
        foreach ($key in $checkpoint.Keys) {
            if ($key -notin @('lastUpdate', 'errors', 'completed')) {
                $checkpoint[$key] = $false
            }
        }
    }
    
    # Helper function to save checkpoint
    function Save-InitCheckpoint {
        param($CheckpointData)
        try {
            if (-not (Test-Path $checkpointDir)) {
                New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
            }
            $CheckpointData.lastUpdate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $CheckpointData | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $checkpointFile -Force
            Write-Verbose "[Checkpoint] State saved: $checkpointFile"
        }
        catch {
            Write-Warning "Failed to save checkpoint: $_"
        }
    }
    
    # Helper function to execute step with checkpoint tracking
    function Invoke-CheckpointedStep {
        param(
            [string]$StepName,
            [scriptblock]$Action,
            [string]$SuccessMessage,
            [string]$SkipMessage = "already completed, skipping",
            [string]$ProgressStatus = $null
        )
        
        # Update progress bar
        if ($ProgressStatus) {
            $script:currentStep++
            $percentComplete = [math]::Round(($script:currentStep / $script:totalSteps) * 100)
            Write-Progress -Activity $script:progressActivity -Status $ProgressStatus -PercentComplete $percentComplete
        }
        
        if ($checkpoint[$StepName] -and -not $Force.IsPresent) {
            Write-Host "[SKIP] $StepName $SkipMessage" -ForegroundColor DarkGray
            return $true
        }
        
        # Start timing this step
        $stepStart = Get-Date
        
        try {
            Write-Verbose "[Initialize-AdoProject] Executing step: $StepName"
            & $Action
            
            # Record step duration
            $stepDuration = (Get-Date) - $stepStart
            $stepTiming[$StepName] = $stepDuration.TotalSeconds
            
            $checkpoint[$StepName] = $true
            Save-InitCheckpoint $checkpoint
            if ($SuccessMessage) {
                Write-Host "[SUCCESS] $SuccessMessage (${stepDuration.TotalSeconds}s)" -ForegroundColor Green
            }
            return $true
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Host "[ERROR] Step '$StepName' failed: $errorMsg" -ForegroundColor Red
            $checkpoint.errors += @{
                step = $StepName
                error = $errorMsg
                timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            Save-InitCheckpoint $checkpoint
            
            Write-Progress -Activity $script:progressActivity -Completed
            
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Red
            Write-Host " INITIALIZATION FAILED" -ForegroundColor Red
            Write-Host "========================================" -ForegroundColor Red
            Write-Host "Failed at: $StepName" -ForegroundColor Yellow
            Write-Host "Error: $errorMsg" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Recovery options:" -ForegroundColor Cyan
            Write-Host "  1. Fix the issue and resume: Initialize-AdoProject '$DestProject' '$RepoName' -Resume" -ForegroundColor White
            Write-Host "  2. View checkpoint status: Get-Content '$checkpointFile'" -ForegroundColor White
            Write-Host "  3. Start fresh: Initialize-AdoProject '$DestProject' '$RepoName' -Force" -ForegroundColor White
            Write-Host ""
            
            throw
        }
    }
    
    # Configuration already loaded earlier for preview mode - skip duplicate loading
    # (Configuration is loaded at the beginning of the function to support -WhatIf preview)
    
    # Create/ensure project with checkpoint
    $proj = $null
    Invoke-CheckpointedStep -StepName 'project' -SuccessMessage "Project '$DestProject' ready" `
        -ProgressStatus "Creating Azure DevOps project (1/$totalSteps)" -Action {
        $script:proj = Ensure-AdoProject $DestProject
        $script:projId = $proj.id
    }
    
    # Note: RBAC group configuration removed - Graph API is unreliable for on-premise servers
    # Users should configure security groups manually via Azure DevOps UI:
    # Project Settings > Permissions > Add security groups and members
    # For more info: https://learn.microsoft.com/azure/devops/organizations/security/add-users-team-project
    
    Write-Verbose "[Initialize-AdoProject] Skipping RBAC configuration (configure manually via UI if needed)"
    
    # Parallel execution: Create areas, wiki, and initial wiki pages concurrently (independent operations)
    # This reduces initialization time by 60-75% (from ~60s to ~15-20s)
    if (-not ($checkpoint['areas'] -and $checkpoint['wiki']) -or $Force.IsPresent) {
        $currentStep++
        Write-Progress -Activity $progressActivity -Status "Setting up areas and wiki in parallel (2/$totalSteps)" `
            -PercentComplete ([math]::Round(($currentStep / $totalSteps) * 100))
        
        Write-Host "[INFO] 🚀 Running parallel initialization (areas + wiki)..." -ForegroundColor Cyan
        
        $jobs = @()
        
        # Job 1: Create work item areas from configuration
        if (-not $checkpoint['areas'] -or $Force.IsPresent) {
            $jobs += Start-ThreadJob -Name "CreateAreas" -ScriptBlock {
                param($DestProject, $Areas, $ModulePath)
                
                # Re-import required modules in thread context
                Import-Module (Join-Path $ModulePath "AzureDevOps.psm1") -Force
                Import-Module (Join-Path $ModulePath "Core.Rest.psm1") -Force
                
                $results = @{
                    success = $true
                    count = 0
                    errors = @()
                }
                
                try {
                    foreach ($area in $Areas) {
                        $areaName = if ($area -is [string]) { $area } else { $area.name }
                        Ensure-AdoArea $DestProject $areaName | Out-Null
                        $results.count++
                    }
                }
                catch {
                    $results.success = $false
                    $results.errors += $_.Exception.Message
                }
                
                return $results
            } -ArgumentList $DestProject, $config.areas, $PSScriptRoot
        }
        
        # Job 2: Set up project wiki
        if (-not $checkpoint['wiki'] -or $Force.IsPresent) {
            $jobs += Start-ThreadJob -Name "CreateWiki" -ScriptBlock {
                param($DestProject, $ProjId, $ModulePath, $CustomTemplateDir)
                
                # Re-import required modules in thread context
                Import-Module (Join-Path $ModulePath "AzureDevOps.psm1") -Force
                Import-Module (Join-Path $ModulePath "Core.Rest.psm1") -Force
                
                $results = @{
                    success = $true
                    wikiId = $null
                    errors = @()
                }
                
                try {
                    $wiki = Ensure-AdoProjectWiki $ProjId $DestProject
                    $results.wikiId = $wiki.id
                    
                    # Load welcome wiki template with fallback (inline for thread context)
                    $welcomeContent = $null
                    $embeddedWelcome = @"
# Welcome to $DestProject

This project was migrated from GitLab using automated tooling.

## Project Structure

- **Frontend**: Web UI components
- **Backend**: API and services
- **Infrastructure**: DevOps and deployment
- **Documentation**: Technical docs and guides

## Getting Started

1. Clone the repository
2. Review branch policies
3. Check work item templates
"@
                    
                    # Try custom directory
                    if ($CustomTemplateDir) {
                        $customPath = Join-Path $CustomTemplateDir "welcome-wiki.md"
                        if (Test-Path $customPath) {
                            try {
                                $template = Get-Content -Path $customPath -Raw -Encoding UTF8
                                $welcomeContent = $template -replace '{{PROJECT_NAME}}', $DestProject
                            } catch { }
                        }
                    }
                    
                    # Try default directory
                    if (-not $welcomeContent) {
                        $defaultPath = Join-Path $ModulePath "templates\welcome-wiki.md"
                        if (Test-Path $defaultPath) {
                            try {
                                $template = Get-Content -Path $defaultPath -Raw -Encoding UTF8
                                $welcomeContent = $template -replace '{{PROJECT_NAME}}', $DestProject
                            } catch { }
                        }
                    }
                    
                    # Fall back to embedded
                    if (-not $welcomeContent) {
                        $welcomeContent = $embeddedWelcome
                    }
                    
                    Upsert-AdoWikiPage $DestProject $wiki.id "/Home" $welcomeContent
                }
                catch {
                    $results.success = $false
                    $results.errors += $_.Exception.Message
                }
                
                return $results
            } -ArgumentList $DestProject, $projId, $PSScriptRoot, $TemplateDirectory
        }
        
        # Wait for parallel jobs with timeout (60 seconds max)
        if ($jobs.Count -gt 0) {
            Write-Verbose "[Initialize-AdoProject] Waiting for $($jobs.Count) parallel jobs to complete..."
            $jobs | Wait-Job -Timeout 60 | Out-Null
            
            # Process results
            foreach ($job in $jobs) {
                $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
                
                if ($job.Name -eq "CreateAreas") {
                    if ($result.success) {
                        $checkpoint['areas'] = $true
                        Write-Host "[SUCCESS] Work item areas configured ($($result.count) areas)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[ERROR] Areas creation failed: $($result.errors -join '; ')" -ForegroundColor Red
                        throw "Areas creation failed in parallel job"
                    }
                }
                elseif ($job.Name -eq "CreateWiki") {
                    if ($result.success) {
                        $checkpoint['wiki'] = $true
                        $wiki = @{ id = $result.wikiId }
                        Write-Host "[SUCCESS] Project wiki created" -ForegroundColor Green
                    }
                    else {
                        Write-Host "[ERROR] Wiki creation failed: $($result.errors -join '; ')" -ForegroundColor Red
                        throw "Wiki creation failed in parallel job"
                    }
                }
                
                Remove-Job -Job $job -Force
            }
            
            Save-InitCheckpoint $checkpoint
            Write-Verbose "[Initialize-AdoProject] ✓ Parallel initialization completed"
        }
    }
    else {
        # Skip message if already completed
        Write-Host "[SKIP] areas and wiki already completed, skipping" -ForegroundColor DarkGray
        
        # Need to re-fetch wiki ID if skipped
        if (-not $wiki) {
            try {
                $wikiList = Invoke-AdoRest GET "/$DestProject/_apis/wiki/wikis"
                $wiki = $wikiList.value | Where-Object { $_.type -eq 'projectWiki' } | Select-Object -First 1
            }
            catch {
                Write-Warning "Could not retrieve wiki ID for skipped step: $_"
            }
        }
    }
    
    # Create work item templates using effective team name with checkpoint
    Invoke-CheckpointedStep -StepName 'templates' -SuccessMessage "Work item templates created" `
        -ProgressStatus "Creating work item templates (3/$totalSteps)" -Action {
        Ensure-AdoTeamTemplates $DestProject $effectiveTeamName
    }
    
    # Create sprint iterations from configuration with checkpoint
    Invoke-CheckpointedStep -StepName 'iterations' -SuccessMessage "Sprint iterations configured ($($config.iterations.sprintCount) sprints)" `
        -ProgressStatus "Setting up sprint iterations (4/$totalSteps)" -Action {
        $sprintCount = $config.iterations.sprintCount
        $sprintDays = $config.iterations.sprintDurationDays
        Ensure-AdoIterations $DestProject $effectiveTeamName -SprintCount $sprintCount -SprintDurationDays $sprintDays
    }
    
    # Create shared work item queries with checkpoint
    Invoke-CheckpointedStep -StepName 'queries' -SuccessMessage "Shared queries created" `
        -ProgressStatus "Creating shared queries (5/$totalSteps)" -Action {
        Ensure-AdoSharedQueries $DestProject $effectiveTeamName
    }
    
    # Configure team settings with checkpoint
    Invoke-CheckpointedStep -StepName 'teamSettings' -SuccessMessage "Team settings configured" `
        -ProgressStatus "Configuring team settings (6/$totalSteps)" -Action {
        Ensure-AdoTeamSettings $DestProject $effectiveTeamName
    }
    
    # Create team dashboard with checkpoint
    Invoke-CheckpointedStep -StepName 'dashboard' -SuccessMessage "Team dashboard created" `
        -ProgressStatus "Creating team dashboard (7/$totalSteps)" -Action {
        Ensure-AdoDashboard $DestProject $effectiveTeamName
    }
    
    # Create wiki pages (tag guidelines and best practices) with checkpoint - PARALLEL
    Invoke-CheckpointedStep -StepName 'wikiPages' -SuccessMessage "Additional wiki pages created" `
        -ProgressStatus "Creating additional wiki pages (8/$totalSteps)" -Action {
        Write-Host "[INFO] 🚀 Creating wiki pages in parallel..." -ForegroundColor Cyan
        
        $wikiJobs = @()
        
        # Job 1: Common Tags wiki
        $wikiJobs += Start-ThreadJob -Name "WikiCommonTags" -ScriptBlock {
            param($DestProject, $WikiId, $ModulePath)
            
            Import-Module (Join-Path $ModulePath "AzureDevOps.psm1") -Force
            Import-Module (Join-Path $ModulePath "Core.Rest.psm1") -Force
            
            try {
                Ensure-AdoCommonTags $DestProject $WikiId
                return @{ success = $true; name = "Common Tags" }
            }
            catch {
                return @{ success = $false; name = "Common Tags"; error = $_.Exception.Message }
            }
        } -ArgumentList $DestProject, $wiki.id, $PSScriptRoot
        
        # Job 2: Best Practices wiki
        $wikiJobs += Start-ThreadJob -Name "WikiBestPractices" -ScriptBlock {
            param($DestProject, $WikiId, $ModulePath)
            
            Import-Module (Join-Path $ModulePath "AzureDevOps.psm1") -Force
            Import-Module (Join-Path $ModulePath "Core.Rest.psm1") -Force
            
            try {
                Ensure-AdoBestPracticesWiki $DestProject $WikiId
                return @{ success = $true; name = "Best Practices" }
            }
            catch {
                return @{ success = $false; name = "Best Practices"; error = $_.Exception.Message }
            }
        } -ArgumentList $DestProject, $wiki.id, $PSScriptRoot
        
        # Wait and collect results
        $wikiJobs | Wait-Job -Timeout 30 | Out-Null
        
        $wikiErrors = @()
        foreach ($job in $wikiJobs) {
            $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if (-not $result.success) {
                $wikiErrors += "$($result.name): $($result.error)"
            }
            Remove-Job -Job $job -Force
        }
        
        if ($wikiErrors.Count -gt 0) {
            Write-Warning "Some wiki pages failed: $($wikiErrors -join '; ')"
        }
        else {
            Write-Verbose "[Initialize-AdoProject] ✓ All wiki pages created successfully"
        }
    }
    
    # Configure QA infrastructure with granular error handling and checkpoint
    Invoke-CheckpointedStep -StepName 'qaInfrastructure' `
        -ProgressStatus "Setting up QA infrastructure (9/$totalSteps)" -Action {
        Write-Host "[INFO] Setting up QA infrastructure..." -ForegroundColor Cyan
        $qaResults = [ordered]@{
            testPlan = @{ success = $false; error = $null }
            queries = @{ success = $false; error = $null }
            dashboard = @{ success = $false; error = $null }
            configurations = @{ success = $false; error = $null }
            guidelines = @{ success = $false; error = $null }
        }
        
        # Test Plan
        try {
            $testPlan = Ensure-AdoTestPlan $DestProject
            $qaResults.testPlan.success = $true
            Write-Verbose "[Initialize-AdoProject] ✓ Test plan created successfully"
        }
        catch {
            $qaResults.testPlan.error = $_.Exception.Message
            Write-Warning "  ✗ Test plan creation failed: $($_.Exception.Message)"
            if ($_.Exception.Message -match '401|403') {
                Write-Warning "    → Ensure PAT has 'Test Plans: Read, write, & manage' scope"
                Write-Warning "    → Generate token at: $(Get-CoreRestConfig).CollectionUrl/_usersSettings/tokens"
            }
        }
        
        # QA Queries
        try {
            Ensure-AdoQAQueries $DestProject
            $qaResults.queries.success = $true
            Write-Verbose "[Initialize-AdoProject] ✓ QA queries created successfully"
        }
        catch {
            $qaResults.queries.error = $_.Exception.Message
            Write-Warning "  ✗ QA queries creation failed: $($_.Exception.Message)"
        }
        
        # QA Dashboard
        try {
            Ensure-AdoQADashboard $DestProject $effectiveTeamName
            $qaResults.dashboard.success = $true
            Write-Verbose "[Initialize-AdoProject] ✓ QA dashboard created successfully"
        }
        catch {
            $qaResults.dashboard.error = $_.Exception.Message
            Write-Warning "  ✗ QA dashboard creation failed: $($_.Exception.Message)"
        }
        
        # Test Configurations
        try {
            Ensure-AdoTestConfigurations $DestProject
            $qaResults.configurations.success = $true
            Write-Verbose "[Initialize-AdoProject] ✓ Test configurations created successfully"
        }
        catch {
            $qaResults.configurations.error = $_.Exception.Message
            Write-Warning "  ✗ Test configurations creation failed: $($_.Exception.Message)"
            if ($_.Exception.Message -match '401|403') {
                Write-Warning "    → Ensure PAT has 'Test Plans: Read, write, & manage' scope"
            }
        }
        
        # QA Guidelines Wiki
        try {
            Ensure-AdoQAGuidelinesWiki $DestProject $wiki.id
            $qaResults.guidelines.success = $true
            Write-Verbose "[Initialize-AdoProject] ✓ QA guidelines wiki created successfully"
        }
        catch {
            $qaResults.guidelines.error = $_.Exception.Message
            Write-Warning "  ✗ QA guidelines wiki creation failed: $($_.Exception.Message)"
        }
        
        # Summary report
        $qaSuccessCount = ($qaResults.Values | Where-Object { $_.success }).Count
        $qaTotalCount = $qaResults.Count
        if ($qaSuccessCount -eq $qaTotalCount) {
            Write-Host "[SUCCESS] QA infrastructure: $qaSuccessCount/$qaTotalCount components configured successfully" -ForegroundColor Green
        }
        elseif ($qaSuccessCount -gt 0) {
            Write-Host "[PARTIAL] QA infrastructure: $qaSuccessCount/$qaTotalCount components configured (see warnings above)" -ForegroundColor Yellow
        }
        else {
            Write-Host "[FAILED] QA infrastructure: 0/$qaTotalCount components configured" -ForegroundColor Red
            Write-Warning "QA infrastructure setup failed completely. Check PAT permissions and retry."
        }
    }
    
    # Create repository with checkpoint
    $repo = $null
    Invoke-CheckpointedStep -StepName 'repository' -SuccessMessage "Repository '$RepoName' created" `
        -ProgressStatus "Creating repository (10/$totalSteps)" -Action {
        $script:repo = Ensure-AdoRepository $DestProject $projId $RepoName
    }

    if ($null -ne $repo) {
        # Apply branch policies with checkpoint (only if default branch exists)
        Invoke-CheckpointedStep -StepName 'branchPolicies' `
            -ProgressStatus "Applying branch policies (11/$totalSteps)" -Action {
            # Wait for default branch with retry logic (handles ADO initialization delays)
            Write-Verbose "[Initialize-AdoProject] Waiting for repository default branch to be established..."
            $maxRetries = $script:REPO_INIT_MAX_RETRIES
            $retryDelays = $script:REPO_INIT_RETRY_DELAYS
            $defaultRef = $null
            
            for ($i = 0; $i -lt $maxRetries; $i++) {
                $delay = $retryDelays[$i]
                Write-Verbose "[Initialize-AdoProject] Attempt $($i + 1)/$maxRetries - waiting ${delay}s..."
                Start-Sleep -Seconds $delay
                
                $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id
                if ($defaultRef) {
                    Write-Verbose "[Initialize-AdoProject] ✓ Default branch found: $defaultRef (after $($i + 1) attempts)"
                    break
                }
                
                if ($i -lt ($maxRetries - 1)) {
                    Write-Verbose "[Initialize-AdoProject] Branch not ready yet, retrying..."
                }
            }

            # Apply branch policies only if repository has a default branch
            if ($defaultRef) {
                Ensure-AdoBranchPolicies `
                    -Project $DestProject `
                    -RepoId $repo.id `
                    -Ref $defaultRef `
                    -Min 2 `
                    -BuildId $BuildDefinitionId `
                    -StatusContext $SonarStatusContext
                Write-Host "[SUCCESS] Branch policies applied to $defaultRef" -ForegroundColor Green
            }
            else {
                Write-Host "[WARN] Default branch not available after $maxRetries retries (62s total wait)" -ForegroundColor Yellow
                Write-Host "[INFO] Branch policies will be applied after first push" -ForegroundColor Yellow
                Write-Host "[INFO] This is normal for empty repositories - no action needed" -ForegroundColor Gray
                # Mark as completed even if skipped (not a failure)
            }
        }
        
        # Add repository templates with checkpoint
        Invoke-CheckpointedStep -StepName 'repositoryTemplates' `
            -ProgressStatus "Adding repository templates (12/$totalSteps)" -Action {
            $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id
            if ($defaultRef) {
                Ensure-AdoRepositoryTemplates $DestProject $repo.id $RepoName
                Write-Host "[SUCCESS] Repository templates (README, PR template) added" -ForegroundColor Green
            }
            else {
                Write-Host "[INFO] Repository templates will be added after first push" -ForegroundColor Yellow
                # Mark as completed even if skipped (not a failure)
            }
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
    
    # Mark initialization as completed
    $currentStep++
    Write-Progress -Activity $progressActivity -Status "Finalizing initialization (13/$totalSteps)" `
        -PercentComplete ([math]::Round(($currentStep / $totalSteps) * 100))
    
    $checkpoint.completed = $true
    Save-InitCheckpoint $checkpoint
    
    # Complete progress bar
    Write-Progress -Activity $progressActivity -Completed
    
    # Clean up checkpoint file on successful completion
    try {
        if (Test-Path $checkpointFile) {
            Remove-Item $checkpointFile -Force
            Write-Verbose "[Initialize-AdoProject] Checkpoint file removed after successful completion"
        }
    }
    catch {
        Write-Verbose "[Initialize-AdoProject] Could not remove checkpoint file: $_"
    }
    
    # Create migration config in new v2.1.0 structure
    try {
        $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $RepoName
        
        # Create migration config
        $config = [pscustomobject]@{
            ado_project      = $DestProject
            ado_repo_name    = $RepoName
            migration_type   = "SINGLE"
            created_date     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            last_updated     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            status           = "INITIALIZED"
        }
        
        $config | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $paths.configFile
        Write-Verbose "[Initialize-AdoProject] Migration config created: $($paths.configFile)"
    }
    catch {
        Write-Verbose "[Initialize-AdoProject] Could not create migration config: $_"
        # Non-critical, continue
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
    
    # Display execution timing summary
    $totalExecutionTime = (Get-Date) - $executionStartTime
    Write-Host "⏱️  Execution Timing:" -ForegroundColor Cyan
    Write-Host ("   Total: {0:F1}s ({1}m {2}s)" -f $totalExecutionTime.TotalSeconds, [int]$totalExecutionTime.Minutes, $totalExecutionTime.Seconds) -ForegroundColor White
    
    if ($stepTiming.Count -gt 0) {
        Write-Host "   Step breakdown:" -ForegroundColor Gray
        $sortedSteps = $stepTiming.GetEnumerator() | Sort-Object Value -Descending
        foreach ($step in $sortedSteps) {
            $stepName = $step.Key
            $stepSeconds = $step.Value
            $percentage = ($stepSeconds / $totalExecutionTime.TotalSeconds) * 100
            Write-Host ("      • {0}: {1:F1}s ({2:F0}%)" -f $stepName, $stepSeconds, $percentage) -ForegroundColor Gray
        }
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
    
    # Generate HTML report if migration config was created
    try {
        $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $RepoName -ErrorAction SilentlyContinue
        if ($paths -and (Test-Path $paths.configFile)) {
            $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $paths.configFile -Parent)
            if ($htmlReport) {
                Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
            }
            
            # Update overview dashboard
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
            }
        }
    }
    catch {
        Write-Verbose "Could not generate HTML reports: $_"
        # Non-critical, continue
    }
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
    Ensure-AdoIterations -Project $DestProject -Team "$DestProject Team" -SprintCount 3 -SprintDurationDays $script:DEFAULT_SPRINT_DURATION_DAYS | Out-Null

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
        [ValidateScript({
            Test-AdoRepositoryName $_ -ThrowOnError
            $true
        })]
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
        $errorMsg = New-ActionableError -ErrorType 'GitNotFound' -Details @{}
        throw $errorMsg
    }
    
    Write-Host "[INFO] Starting migration: $SrcPath → $DestProject" -ForegroundColor Cyan
    Write-Host "[INFO] IMPORTANT: Migration requires preparation (Option 1) to be completed first" -ForegroundColor Yellow
    Write-Host "          All GitLab connections must happen during preparation." -ForegroundColor Gray
    
    # Extract repository name from path
    $repoName = ($SrcPath -split '/')[-1]
    
    # Detect project structure (new v2.1.0+ vs legacy)
    $migrationsDir = Get-MigrationsDirectory
    $newConfigFile = Join-Path $migrationsDir "$DestProject\migration-config.json"
    $legacyReportDir = Join-Path $migrationsDir "$repoName\reports"
    
    if (Test-Path $newConfigFile) {
        # New self-contained structure (v2.1.0+)
        Write-Host "[INFO] Using v2.1.0+ self-contained structure" -ForegroundColor Cyan
        $paths = Get-ProjectPaths -AdoProject $DestProject -GitLabProject $repoName
        $reportsDir = $paths.reportsDir
        $logsDir = $paths.logsDir
        $repoDir = $paths.repositoryDir
        
        # Look for preflight report in GitLab project subfolder
        $preflightFile = Join-Path $paths.gitlabDir "reports\preflight-report.json"
    }
    else {
        # Legacy flat structure (deprecated but supported)
        Write-Host "[INFO] Using legacy flat structure (consider re-preparing with v2.1.0+)" -ForegroundColor Yellow
        $paths = Get-ProjectPaths -ProjectName $repoName
        $reportsDir = $paths.reportsDir
        $logsDir = $paths.logsDir
        $repoDir = $paths.repositoryDir
        $preflightFile = Join-Path $reportsDir "preflight-report.json"
    }
    
    # Check for existing preflight report
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
                    $errorMsg = New-ActionableError -ErrorType 'GitLFSRequired' -Details @{ LFSSizeMB = $preflightData.lfs_size_MB }
                    throw $errorMsg
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
        # CRITICAL: Never connect to GitLab during migration execution
        # All GitLab data must be gathered during preparation (Option 1 or 4)
        Write-Host "[ERROR] No preflight report found" -ForegroundColor Red
        Write-Host "        Run preparation first:" -ForegroundColor Red
        Write-Host "          - Option 1 (Single Project Preparation)" -ForegroundColor Yellow
        Write-Host "          - Option 4 (Bulk Preparation)" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Red
        Write-Host "        Migration cannot proceed without preparation data." -ForegroundColor Red
        Write-Host "        This ensures all GitLab connections happen during preparation," -ForegroundColor Gray
        Write-Host "        allowing execution to work in air-gapped environments." -ForegroundColor Gray
        throw "Pre-migration validation required. Run preparation first (Option 1 or 4)."
    }
    
    # Ensure Azure DevOps project exists
    $proj = Ensure-AdoProject $DestProject
    $projId = $proj.id
    $repoName = $gl.path
    
    # Create migration log
    $logFile = New-LogFilePath $logsDir "migration"
    $startTime = Get-Date
    $stepTiming = @{}

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
    $stepStart = Get-Date
    $repo = Ensure-AdoRepository $DestProject $projId $repoName -AllowExisting:$AllowSync -Replace:$Replace
    $stepTiming['Repository Creation'] = ((Get-Date) - $stepStart).TotalSeconds
    
    $defaultRef = Get-AdoRepoDefaultBranch $DestProject $repo.id    $isSync = $AllowSync -and $preReport.ado_repo_exists
    if ($isSync) {
        Write-Host "[INFO] Sync mode: Updating existing repository" -ForegroundColor Yellow
        Write-MigrationLog $logFile "=== SYNC MODE: Updating existing repository ==="
    }
    
    try {
        # Determine source repository
        $stepStart = Get-Date
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
        $stepTiming['Repository Download'] = ((Get-Date) - $stepStart).TotalSeconds
        
        # Configure Azure DevOps remote
        $stepStart = Get-Date
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
        $stepTiming['Git Push'] = ((Get-Date) - $stepStart).TotalSeconds
        
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
            $stepStart = Get-Date
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
                $stepTiming['Branch Policies'] = ((Get-Date) - $stepStart).TotalSeconds
            }
            catch {
                Write-Warning "Failed to apply branch policies: $_"
                Write-Host "[INFO] You can manually configure branch policies in Azure DevOps" -ForegroundColor Yellow
                $stepTiming['Branch Policies'] = ((Get-Date) - $stepStart).TotalSeconds
            }
        }        $endTime = Get-Date
        
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
        
        # Generate HTML report
        try {
            $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $reportsDir -Parent)
            if ($htmlReport) {
                Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Warning "Failed to generate HTML report: $_"
        }
        
        # Regenerate overview dashboard
        try {
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Warning "Failed to update overview dashboard: $_"
        }
        
        Write-MigrationLog $logFile @(
            "=== Migration Completed Successfully ==="
            "End time: $endTime"
            "Duration: $($summary.duration_minutes) minutes"
        )
        
        Write-Host "[OK] Migration completed successfully!" -ForegroundColor Green
        Write-Host "      Total duration: $($summary.duration_minutes) minutes" -ForegroundColor White
        
        # Show timing breakdown
        if ($stepTiming.Count -gt 0) {
            Write-Host "      Step breakdown:" -ForegroundColor Gray
            $sortedSteps = $stepTiming.GetEnumerator() | Sort-Object Value -Descending
            foreach ($step in $sortedSteps) {
                Write-Host ("        • {0}: {1:F1}s" -f $step.Key, $step.Value) -ForegroundColor Gray
            }
        }
        
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
        
        # Generate HTML report for failed migration
        try {
            $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $reportsDir -Parent)
            if ($htmlReport) {
                Write-Host "[INFO] HTML error report generated: $htmlReport" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Warning "Failed to generate HTML error report: $_"
        }
        
        # Regenerate overview dashboard
        try {
            $overviewReport = New-MigrationsOverviewReport
            if ($overviewReport) {
                Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Warning "Failed to update overview dashboard: $_"
        }
        
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
    
    # Check if preparation already exists (new self-contained structure)
    $bulkPaths = Get-BulkProjectPaths -AdoProject $DestProjectName
    $configFile = $bulkPaths.configFile
    
    if (Test-Path $configFile) {
        Write-Host ""
        Write-Host "⚠️  Existing preparation found for '$DestProjectName'" -ForegroundColor Yellow
        Write-Host "   Folder: $($bulkPaths.containerDir)"
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
    
    # Look for existing bulk config files (new self-contained structure)
    $migrationsDir = Get-MigrationsDirectory
    $bulkPrepDirs = Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | 
        Where-Object { Test-Path (Join-Path $_.FullName "bulk-migration-config.json") }
    
    if (-not $bulkPrepDirs) {
        Write-Host "❌ No bulk preparation configurations found." -ForegroundColor Red
        Write-Host "   Run Option 4 (Bulk Preparation) first to create configurations."
        return
    }
    
    Write-Host "Available bulk migration configurations:"
    Write-Host ""
    
    $templates = @()
    $index = 1
    foreach ($dir in $bulkPrepDirs) {
        $configFile = Join-Path $dir.FullName "bulk-migration-config.json"
        if (Test-Path $configFile) {
            $projectName = $dir.Name
            Write-Host "  [$index] $projectName"
            
            try {
                $configData = Get-Content $configFile | ConvertFrom-Json
                $totalProjects = $configData.projects.Count
                $successProjects = ($configData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
                Write-Host "      - $totalProjects project(s), $successProjects ready for migration"
                Write-Host "      - Config: $configFile"
            }
            catch {
                Write-Host "      - Error reading configuration"
            }
            
            $templates += @{
                Index        = $index
                ProjectName  = $projectName
                ConfigFile   = $configFile
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
    Write-Host "  [1] View configuration contents"
    Write-Host "  [2] Open configuration in notepad"
    Write-Host "  [3] View preparation log"
    Write-Host "  [0] Cancel"
    Write-Host ""
    
    $action = Read-Host "Select action (0-3)"
    
    switch ($action) {
        '1' {
            Write-Host ""
            Write-Host "=== CONFIGURATION CONTENTS ===" -ForegroundColor Cyan
            Get-Content $selectedTemplate.ConfigFile | Write-Host
            Write-Host "=============================" -ForegroundColor Cyan
        }
        '2' {
            Write-Host "[INFO] Opening configuration in notepad..."
            Start-Process notepad $selectedTemplate.ConfigFile -Wait
            Write-Host "[INFO] Editing complete."
        }
        '3' {
            $logsDir = Join-Path $selectedTemplate.Directory "logs"
            if (Test-Path $logsDir) {
                $logFiles = Get-ChildItem -Path $logsDir -Filter "bulk-preparation-*.log" | Sort-Object LastWriteTime -Descending
                if ($logFiles) {
                    $latestLog = $logFiles[0].FullName
                    Write-Host ""
                    Write-Host "=== PREPARATION LOG (Latest) ===" -ForegroundColor Cyan
                    Get-Content $latestLog | Write-Host
                    Write-Host "================================" -ForegroundColor Cyan
                }
                else {
                    Write-Host "[WARN] No preparation log files found in: $logsDir" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "[WARN] Logs directory not found: $logsDir" -ForegroundColor Yellow
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
    Write-Host "This will execute migrations from prepared configuration files."
    Write-Host ""
    
    # Look for available config files (new self-contained structure)
    $migrationsDir = Get-MigrationsDirectory
    $bulkPrepDirs = Get-ChildItem -Path $migrationsDir -Directory -ErrorAction SilentlyContinue | 
        Where-Object { Test-Path (Join-Path $_.FullName "bulk-migration-config.json") }
    
    if (-not $bulkPrepDirs) {
        Write-Host "❌ No bulk preparation configurations found." -ForegroundColor Red
        Write-Host "   Run Option 4 (Bulk Preparation) first."
        return
    }
    
    $templates = @()
    foreach ($dir in $bulkPrepDirs) {
        $configFile = Join-Path $dir.FullName "bulk-migration-config.json"
        if (Test-Path $configFile) {
            $projectName = $dir.Name
            $templates += @{
                ProjectName  = $projectName
                ConfigFile   = $configFile
                Directory    = $dir.FullName
            }
        }
    }
    
    if ($templates.Count -eq 0) {
        Write-Host "❌ No valid configuration files found." -ForegroundColor Red
        return
    }
    
    Write-Host "Available configurations:"
    for ($i = 0; $i -lt $templates.Count; $i++) {
        $template = $templates[$i]
        Write-Host "  [$($i + 1)] $($template.ProjectName)"
        
        try {
            $configData = Get-Content $template.ConfigFile | ConvertFrom-Json
            $successProjects = ($configData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }).Count
            Write-Host "      - $successProjects project(s) ready for migration"
        }
        catch {
            Write-Host "      - Unable to read configuration"
        }
    }
    Write-Host ""
    
    do {
        $selection = Read-Host "Select configuration (1-$($templates.Count))"
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
    
    # Read configuration
    try {
        $configData = Get-Content $selectedTemplate.ConfigFile | ConvertFrom-Json
        $successfulProjects = @($configData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" })
        $failedProjects = @($configData.projects | Where-Object { $_.preparation_status -eq "FAILED" })
        
        Write-Host "=== MIGRATION PREVIEW ===" -ForegroundColor Cyan
        Write-Host "Destination project: $DestProjectName"
        Write-Host "Total projects in configuration: $(@($configData.projects).Count)"
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
        Write-Host "❌ Error reading configuration file: $_" -ForegroundColor Red
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
    
    # Generate HTML reports for all migrated projects
    Write-Host ""
    Write-Host "[INFO] Generating HTML reports..." -ForegroundColor Cyan
    try {
        # Find all individual project folders
        $projectFolders = Get-ChildItem -Path $selectedTemplate.Directory -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "reports" -and $_.Name -ne "logs" }
        
        foreach ($folder in $projectFolders) {
            $configFile = Join-Path $folder.FullName "reports\migration-config.json"
            if (Test-Path $configFile) {
                try {
                    $htmlReport = New-MigrationHtmlReport -ProjectPath $folder.FullName
                    if ($htmlReport) {
                        Write-Verbose "[INFO] Generated report: $htmlReport"
                    }
                }
                catch {
                    Write-Verbose "Could not generate report for $($folder.Name): $_"
                }
            }
        }
        
        # Update overview dashboard
        $overviewReport = New-MigrationsOverviewReport
        if ($overviewReport) {
            Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Failed to generate HTML reports: $_"
    }
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
