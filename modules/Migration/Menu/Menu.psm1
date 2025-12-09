<#
.SYNOPSIS
    Interactive menu system for GitLab to Azure DevOps migration toolkit.

.DESCRIPTION
    This module provides the main menu interface and workflow orchestration
    for migrating projects from GitLab to Azure DevOps. It includes options
    for preparation, migration, user management, and project enhancement.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, Migration.Core modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

#region Module Imports
$migrationRoot = Split-Path $PSScriptRoot -Parent

# Import core migration module
Import-Module -WarningAction SilentlyContinue (Join-Path $migrationRoot "Core\MigrationCore.psm1") -Force -Global

# Import Azure DevOps module
$azureDevOpsModulePath = Join-Path (Split-Path $migrationRoot -Parent) "AzureDevOps\AzureDevOps.psm1"
Import-Module -WarningAction SilentlyContinue $azureDevOpsModulePath -Force -Global

# Import Team Packs module for resource provisioning
$teamPacksModulePath = Join-Path $migrationRoot "TeamPacks\TeamPacks.psm1"
if (Test-Path $teamPacksModulePath) {
    Import-Module -WarningAction SilentlyContinue $teamPacksModulePath -Force -Global
}

# Import Project Initialization module
$projectInitModulePath = Join-Path $migrationRoot "Initialization\ProjectInitialization.psm1"
if (Test-Path $projectInitModulePath) {
    Import-Module -WarningAction SilentlyContinue $projectInitModulePath -Force -Global
}
#endregion

#region Module Variables
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabToken = $null
$script:GitLabBaseUrl = $null
$script:BuildDefinitionId = 0
$script:SonarStatusContext = ""
#endregion

#region Helper Functions

<#
.SYNOPSIS
    Displays the main menu header.
#>
function Show-MenuHeader {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     GitLab → Azure DevOps Migration Tool v2.1.0          ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

<#
.SYNOPSIS
    Displays menu options organized by category.
#>
function Show-MenuOptions {
    # Project Preparation & Migration
    Write-Host "  1) Prepare Single Project   " -ForegroundColor White -NoNewline
    Write-Host "│ Download & analyze single GitLab project" -ForegroundColor Gray
    Write-Host "  2) Prepare Bulk Projects    " -ForegroundColor White -NoNewline
    Write-Host "│ Download & analyze multiple projects" -ForegroundColor Gray
    Write-Host "  3) Create DevOps Project    " -ForegroundColor White -NoNewline
    Write-Host "│ Initialize project + team packs" -ForegroundColor Gray
    Write-Host "  4) Start Planned Migration  " -ForegroundColor White -NoNewline
    Write-Host "│ Execute prepared migration (single/bulk)" -ForegroundColor Gray
    Write-Host ""
    
    # User & Identity Management
    Write-Host "  5) Export User Information  " -ForegroundColor White -NoNewline
    Write-Host "│ Export GitLab users/groups to JSON" -ForegroundColor Gray
    Write-Host "  6) Import User Information  " -ForegroundColor White -NoNewline
    Write-Host "│ Create AD OUs/groups & map to Azure DevOps" -ForegroundColor Gray
    Write-Host "  7) Import User Info (ADO-only)" -ForegroundColor White -NoNewline
    Write-Host "│ Map AD groups to Azure DevOps (skip AD changes)" -ForegroundColor Gray
    Write-Host "  8) Reset User Passwords     " -ForegroundColor White -NoNewline
    Write-Host "│ Reset AD passwords & send email notifications" -ForegroundColor Gray
    Write-Host ""
    
    # Project Enhancement
    Write-Host "  9) Add Team Packs           " -ForegroundColor White -NoNewline
    Write-Host "│ Enhance all existing projects with team resources" -ForegroundColor Gray
    Write-Host " 10) Import Work Items        " -ForegroundColor White -NoNewline
    Write-Host "│ Import requirements from Excel file" -ForegroundColor Gray
    Write-Host " 11) Create Dashboards        " -ForegroundColor White -NoNewline
    Write-Host "│ Create dashboards for all projects" -ForegroundColor Gray
    Write-Host ""
    
    # Automation & Batch Operations
    Write-Host " 12) Unattended: Prepare from Config" -ForegroundColor White -NoNewline
    Write-Host "│ Prepare from projects.json (no ADO changes)" -ForegroundColor Gray
    Write-Host " 13) Unattended: Full Migration     " -ForegroundColor White -NoNewline
    Write-Host "│ End-to-end prepare/initialize/migrate" -ForegroundColor Gray
    Write-Host " 14) Sync Repos from Config Map      " -ForegroundColor White -NoNewline
    Write-Host "│ Sync GitLab repos to Azure DevOps projects" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Type 'q' or 'quit' to exit" -ForegroundColor Gray
    Write-Host ""
}

<#
.SYNOPSIS
    Prompts user for menu choice and handles exit commands.

.OUTPUTS
    Returns the user's choice as a string, or $null if exiting.
#>
function Get-MenuChoice {
    $choice = Read-Host "Select option (1-14 or q to quit)"
    
    # Handle quit command
    if ($choice -in @('q', 'quit', 'exit')) {
        Write-Host ""
        Write-Host "Exiting GitLab to Azure DevOps Migration Tool..." -ForegroundColor Cyan
        Write-Host "Goodbye!" -ForegroundColor Green
        return $null
    }
    
    return $choice
}

<#
.SYNOPSIS
    Gets the project root directory path.
#>
function Get-ProjectRoot {
    # From modules/Migration/Menu/ go up 3 levels to get to project root
    return Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
}

#endregion

#region Main Menu Function

<#
.SYNOPSIS
    Displays the interactive migration menu and processes user selections.

.DESCRIPTION
    Main entry point for interactive operations. Provides options for:
    - Project preparation and migration
    - User and identity management
    - Project enhancement with team packs
    - Automated batch operations

.EXAMPLE
    Show-MigrationMenu
#>
function Show-MigrationMenu {
    [CmdletBinding()]
    param()
    
    Show-MenuHeader
    Show-MenuOptions
    
    $choice = Get-MenuChoice
    if ($null -eq $choice) {
        return
    }
    
    # Handle special case: Option 12 (bulk preparation from config)
    if ($choice -eq '12') {
        Invoke-Option10-BulkPreparationFromConfig
        return
    }
    
    # Process menu selections
    switch ($choice) {
        '1'  { Invoke-Option1-PrepareSingle }
        '2'  { Invoke-Option2-PrepareBulk }
        '3'  { Invoke-Option3-CreateDevOpsProject }
        '4'  { Invoke-Option4-StartPlannedMigration }
        '5'  { Invoke-Option5-ExportUserInfo }
        '6'  { Invoke-Option6-ImportUserInfo }
        '7'  { Invoke-Option7-ImportUserInfoAdoOnly }
        '8'  { Invoke-Option15-ResetUserPasswords }
        '9'  { Invoke-Option8-AddTeamPacks }
        '10' { Invoke-Option9-ImportRequirements }
        '11' { Invoke-Option13-CreateDashboards }
        '13' { Invoke-Option11-UnattendedImport }
        '14' { Invoke-Option12-SyncRepos }
        default {
            Write-Host ""
            Write-Host "[ERROR] Invalid choice. Please select a number between 1 and 14, or 'q' to quit." -ForegroundColor Red
            Write-Host ""
        }
    }
}

#endregion

#region Menu Option Handlers

<#
.SYNOPSIS
    Option 1: Prepare single GitLab project for migration.
#>
function Invoke-Option1-PrepareSingle {
    Write-Host ""
    Write-Host "=== SINGLE PROJECT PREPARATION ===" -ForegroundColor Cyan
    Write-Host "This will create a self-contained preparation folder." -ForegroundColor Gray
    Write-Host ""
    
    # Get user input
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
    $paths = Get-ProjectPaths -AdoProject $DestProjectName -GitLabProject $gitlabProjectName
    
    Write-Host ""
    Write-Host "[INFO] Preparing self-contained structure:" -ForegroundColor Cyan
    Write-Host "  Container: migrations/$DestProjectName/" -ForegroundColor Gray
    Write-Host "  Project: $gitlabProjectName/" -ForegroundColor Gray
    Write-Host ""
    
    # Preparation workflow with progress tracking
    Write-Progress -Activity "Single Project Preparation" -Status "Initializing preparation..." -PercentComplete 0 -Id 1
    
    # Step 1: Download GitLab repository
    Write-Progress -Activity "Single Project Preparation" -Status "Downloading GitLab repository..." -PercentComplete 25 -Id 1
    Initialize-GitLab -ProjectPath $SourceProjectPath -CustomBaseDir $paths.projectDir -CustomProjectName $gitlabProjectName
    
    # Step 2: Create migration config
    Write-Progress -Activity "Single Project Preparation" -Status "Creating migration configuration..." -PercentComplete 50 -Id 1
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
    
    # Step 3: Extract documentation
    Write-Progress -Activity "Single Project Preparation" -Status "Extracting documentation files..." -PercentComplete 75 -Id 1
    try {
        $docStats = Export-GitLabDocumentation -AdoProject $DestProjectName
        if ($docStats -and $docStats.total_files -gt 0) {
            Write-Host "[SUCCESS] Extracted $($docStats.total_files) documentation files ($($docStats.total_size_MB) MB)" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] No documentation files found to extract" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "[WARN] Documentation extraction failed: $_"
    }
    
    # Step 4: Generate reports
    Write-Progress -Activity "Single Project Preparation" -Status "Generating reports..." -PercentComplete 90 -Id 1
    try {
        $htmlReport = New-MigrationHtmlReport -ProjectPath (Split-Path $paths.configFile -Parent)
        if ($htmlReport) {
            Write-Host "[INFO] HTML report generated: $htmlReport" -ForegroundColor Cyan
        }
        
        $overviewReport = New-MigrationsOverviewReport
        if ($overviewReport) {
            Write-Host "[INFO] Overview dashboard updated: $overviewReport" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Failed to generate HTML reports: $_"
    }
    
    # Step 5: Cache pre-migration report
    Write-Progress -Activity "Single Project Preparation" -Status "Caching pre-migration report..." -PercentComplete 95 -Id 1
    try {
        $preReportPath = Join-Path $paths.gitlabDir "reports\pre-migration-report.json"
        New-MigrationPreReport -GitLabPath $SourceProjectPath -AdoProject $DestProjectName -AdoRepoName $gitlabProjectName -OutputPath $preReportPath -AllowSync | Out-Null
        Write-Host "[INFO] Pre-migration report cached: $preReportPath" -ForegroundColor Gray
    }
    catch {
        Write-Warning "[WARN] Failed to generate pre-migration report for '$SourceProjectPath': $_"
    }
    
    # Step 6: Provision team resources
    Write-Progress -Activity "Single Project Preparation" -Status "Provisioning team resources..." -PercentComplete 100 -Id 1
    if (Get-Command -Name Invoke-AllTeamPacks -ErrorAction SilentlyContinue) {
        try {
            Write-Host "[INFO] Provisioning project resources (wikis, queries, dashboards) for '$DestProjectName'..." -ForegroundColor Cyan
            Invoke-AllTeamPacks -ProjectName $DestProjectName
        }
        catch {
            Write-Warning "[WARN] Project resource provisioning failed for '$DestProjectName': $_"
        }
    }
    else {
        Write-Verbose "[Menu] Invoke-AllTeamPacks not available; team resources were not provisioned during preparation."
    }
    
    Write-Progress -Activity "Single Project Preparation" -Status "Preparation completed successfully!" -PercentComplete 100 -Id 1 -Completed
}

<#
.SYNOPSIS
    Option 2: Prepare bulk GitLab projects for migration.
#>
function Invoke-Option2-PrepareBulk {
    Invoke-BulkPreparationWorkflow
}

<#
.SYNOPSIS
    Option 10: Bulk preparation from projects.json config file.
#>
function Invoke-Option10-BulkPreparationFromConfig {
    Write-Host ""
    Write-Host "=== BULK PREPARATION FROM CONFIG FILE ===" -ForegroundColor Cyan
    Write-Host "This will read projects.json and prepare migration folders only (no Azure DevOps changes)." -ForegroundColor Gray
    Write-Host "Use Option 3 to create Azure DevOps projects after preparation." -ForegroundColor Gray
    Write-Host ""
    
    $projectRoot = Get-ProjectRoot
    $prepScript = Join-Path $projectRoot "modules\Migration\Prepare-MigrationsFromConfig.ps1"
    
    if (-not (Test-Path $prepScript)) {
        Write-Host "[ERROR] Prepare-MigrationsFromConfig.ps1 not found at: $prepScript" -ForegroundColor Red
        return
    }
    
    try {
        # Locate projects.json configuration file
        $configPath = Join-Path $projectRoot 'projects.json'
        if (-not (Test-Path $configPath)) {
            # Fallback to parent directory (legacy location)
            $configPath = Join-Path (Split-Path $projectRoot -Parent) 'projects.json'
        }
        
        # Run unattended bulk preparation
        & $prepScript -ConfigFile $configPath -Force
        Write-Host "[SUCCESS] Bulk preparation from config completed!" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Bulk preparation failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    Option 3: Create Azure DevOps project with team packs.
#>
function Invoke-Option3-CreateDevOpsProject {
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
                    
                    # Ask about Excel import
                    Write-Host ""
                    $importExcel = Read-Host "Import work items from Excel? (y/N)"
                    $excelPath = $null
                    $excelWorksheet = "Requirements"
                    if ($importExcel -match '^[Yy]') {
                        $excelPath = Read-Host "Enter path to Excel file (e.g., C:\requirements.xlsx)"
                        if (Test-Path $excelPath) {
                            $worksheetInput = Read-Host "Enter worksheet name (default: Requirements)"
                            if (-not [string]::IsNullOrWhiteSpace($worksheetInput)) {
                                $excelWorksheet = $worksheetInput
                            }
                        }
                        else {
                            Write-Host "[WARN] Excel file not found: $excelPath" -ForegroundColor Yellow
                            $excelPath = $null
                        }
                    }
                    
                    if (-not [string]::IsNullOrWhiteSpace($DestProjectName) -and -not [string]::IsNullOrWhiteSpace($RepoName)) {
                        if ($excelPath) {
                            Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName `
                                                 -ExcelRequirementsPath $excelPath `
                                                 -ExcelWorksheetName $excelWorksheet `
                                                 -BuildDefinitionId $script:BuildDefinitionId `
                                                 -SonarStatusContext $script:SonarStatusContext
                        }
                        else {
                            Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName `
                                                 -BuildDefinitionId $script:BuildDefinitionId `
                                                 -SonarStatusContext $script:SonarStatusContext
                        }
                        
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
                    
                    # Ask about Excel import
                    Write-Host ""
                    $importExcel = Read-Host "Import work items from Excel? (y/N)"
                    $excelPath = $null
                    $excelWorksheet = "Requirements"
                    if ($importExcel -match '^[Yy]') {
                        $excelPath = Read-Host "Enter path to Excel file (e.g., C:\requirements.xlsx)"
                        if (Test-Path $excelPath) {
                            $worksheetInput = Read-Host "Enter worksheet name (default: Requirements)"
                            if (-not [string]::IsNullOrWhiteSpace($worksheetInput)) {
                                $excelWorksheet = $worksheetInput
                            }
                        }
                        else {
                            Write-Host "[WARN] Excel file not found: $excelPath" -ForegroundColor Yellow
                            $excelPath = $null
                        }
                    }
                    
                    if (-not [string]::IsNullOrWhiteSpace($DestProjectName) -and -not [string]::IsNullOrWhiteSpace($RepoName)) {
                        if ($excelPath) {
                            Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName `
                                                 -ExcelRequirementsPath $excelPath `
                                                 -ExcelWorksheetName $excelWorksheet `
                                                 -BuildDefinitionId $script:BuildDefinitionId `
                                                 -SonarStatusContext $script:SonarStatusContext
                        }
                        else {
                            Initialize-AdoProject -DestProject $DestProjectName -RepoName $RepoName `
                                                 -BuildDefinitionId $script:BuildDefinitionId `
                                                 -SonarStatusContext $script:SonarStatusContext
                        }
                        
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
                        Initialize-AdoProject -DestProject $DestProjectName -BulkInit -BuildDefinitionId $script:BuildDefinitionId -SonarStatusContext $script:SonarStatusContext
                        
                        # Offer team initialization packs after successful project creation
                        Invoke-TeamPackMenu -ProjectName $DestProjectName
                    }
                }
            }
            else {
                Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
            }
}

<#
.SYNOPSIS
    Option 4: Start planned migration from prepared projects.
#>
function Invoke-Option4-StartPlannedMigration {
            # Start Planned Migration - list prepared projects for selection
            Write-Host ""
            Write-Host "=== START PLANNED MIGRATION ===" -ForegroundColor Cyan
            Write-Host "Select a prepared project to migrate to Azure DevOps."
            Write-Host ""
            
            $preparedProjects = Get-PreparedProjects
            
            if ($preparedProjects.Count -eq 0) {
                Write-Host "No prepared projects found. Please run Option 1 or 2 first to prepare projects." -ForegroundColor Yellow
                Write-Host ""
                return
            }
            
            Write-Host "[INFO] Projects marked [v2.1.0] use self-contained folder structures (recommended)" -ForegroundColor Cyan
            Write-Host "[INFO] Projects marked [legacy] use flat folder structures (consider re-preparing)" -ForegroundColor DarkYellow
            Write-Host ""
            
            # Display single preparations
            $singleProjects = @($preparedProjects | Where-Object { $_.Type -eq "Single" })
            if ($singleProjects.Count -gt 0) {
                Write-Host "Single Project Preparations:" -ForegroundColor Green
                for ($i = 0; $i -lt $singleProjects.Count; $i++) {
                    $proj = $singleProjects[$i]
                    $structureIndicator = if ($proj.Structure -eq "v2.1.0") { "[v2.1.0]" } else { "[legacy]" }
                    $structureColor = if ($proj.Structure -eq "v2.1.0") { "Green" } else { "Yellow" }
                    
                    Write-Host "  $($i + 1)) $($proj.ProjectName) (from $($proj.GitLabPath)) " -ForegroundColor White -NoNewline
                    Write-Host $structureIndicator -ForegroundColor $structureColor
                    Write-Host "      Size: $($proj.RepoSizeMB) MB | Prepared: $($proj.PreparationTime)" -ForegroundColor Gray
                    
                    # Show migration status
                    if ($proj.RepoMigrated) {
                        Write-Host "      Status: Already migrated" -ForegroundColor Green
                    } else {
                        Write-Host "      Status: Ready to migrate" -ForegroundColor Cyan
                    }
                }
                
                # Show helpful migration guidance if any legacy structures detected
                $legacyCount = @($singleProjects | Where-Object { $_.Structure -eq "legacy" }).Count
                if ($legacyCount -gt 0) {
                    Write-Host ""
                    Write-Host "  [NOTE] Legacy structures detected. Consider re-preparing with Option 1 for v2.1.0 self-contained folders." -ForegroundColor Yellow
                }
                Write-Host ""
            }
            
            # Display bulk preparations
            $bulkProjects = @($preparedProjects | Where-Object { $_.Type -eq "Bulk" })
            $bulkStartIndex = $singleProjects.Count
            if ($bulkProjects.Count -gt 0) {
                Write-Host "Bulk Preparations:" -ForegroundColor Green
                for ($i = 0; $i -lt $bulkProjects.Count; $i++) {
                    $proj = $bulkProjects[$i]
                    Write-Host "  $($bulkStartIndex + $i + 1)) $($proj.ProjectName) (bulk: $($proj.SuccessfulCount)/$($proj.ProjectCount) projects)" -ForegroundColor White
                    Write-Host "      Total size: $($proj.TotalSizeMB) MB | Prepared: $($proj.PreparationTime)" -ForegroundColor Gray
                    
                    # Show migration status
                    if ($proj.MigratedCount -ge $proj.ProjectCount) {
                        Write-Host "      Status: All projects migrated" -ForegroundColor Green
                    } elseif ($proj.MigratedCount -gt 0) {
                        Write-Host "      Status: Partially migrated ($($proj.MigratedCount)/$($proj.ProjectCount))" -ForegroundColor Yellow
                    } else {
                        Write-Host "      Status: Ready to migrate" -ForegroundColor Cyan
                    }
                }
                Write-Host ""
            }
            
            $selection = Read-Host "Select a project to migrate (1-$($preparedProjects.Count))"
            $selectionNum = 0
            
            if ([int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $preparedProjects.Count) {
                $selectedProject = $preparedProjects[$selectionNum - 1]
                
                if ($selectedProject.Type -eq "Single") {
                    # Check if already migrated
                    if ($selectedProject.RepoMigrated) {
                        Write-Host ""
                        Write-Host "[INFO] Project '$($selectedProject.ProjectName)' appears to be already migrated." -ForegroundColor Yellow
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
                                Invoke-SingleMigration -SrcPath $selectedProject.GitLabPath -DestProject $selectedProject.ProjectName -AllowSync
                            }
                            '2' {
                                Write-Host "[INFO] Skipping migration" -ForegroundColor Yellow
                            }
                            '3' {
                                Write-Host "[WARN] This will REPLACE the existing repository!" -ForegroundColor Red
                                $confirm = Read-Host "Are you sure? Type 'REPLACE' to confirm"
                                if ($confirm -eq 'REPLACE') {
                                    Write-Host "[INFO] Starting FORCE migration..." -ForegroundColor Red
                                    Invoke-SingleMigration -SrcPath $selectedProject.GitLabPath -DestProject $selectedProject.ProjectName -Replace -Force
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
                        # Normal migration
                        Write-Host ""
                        Write-Host "[INFO] Starting migration: $($selectedProject.GitLabPath) → $($selectedProject.ProjectName)" -ForegroundColor Cyan
                        Invoke-SingleMigration -SrcPath $selectedProject.GitLabPath -DestProject $selectedProject.ProjectName
                    }
                }
                elseif ($selectedProject.Type -eq "Bulk") {
                    # Check if already fully migrated
                    if ($selectedProject.MigratedCount -ge $selectedProject.ProjectCount) {
                        Write-Host ""
                        Write-Host "[INFO] All projects in bulk migration '$($selectedProject.ProjectName)' appear to be already migrated." -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Options:" -ForegroundColor Cyan
                        Write-Host "  1) SYNC - Update all repositories with latest from GitLab" -ForegroundColor Green
                        Write-Host "  2) SKIP - Do nothing" -ForegroundColor Yellow
                        Write-Host ""
                        $syncChoice = Read-Host "Select option (1-2)"
                        
                        switch ($syncChoice) {
                            '1' {
                                Write-Host "[INFO] Starting SYNC operation for all repositories..." -ForegroundColor Green
                                Invoke-BulkMigrationWorkflow -AdoProject $selectedProject.ProjectName -Force -AllowSync
                            }
                            '2' {
                                Write-Host "[INFO] Skipping migration" -ForegroundColor Yellow
                            }
                            default {
                                Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
                            }
                        }
                    }
                    else {
                        # Normal bulk migration
                        Write-Host ""
                        Write-Host "[INFO] Starting bulk migration for: $($selectedProject.ProjectName)" -ForegroundColor Cyan
                        Invoke-BulkMigrationWorkflow -AdoProject $selectedProject.ProjectName
                    }
                }
            }
            else {
                Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
            }
}

<#
.SYNOPSIS
    Option 5: Export user information from GitLab.
#>
function Invoke-Option5-ExportUserInfo {
    # Export User Information
    Write-Host ""
    Write-Host "=== EXPORT USER INFORMATION ===" -ForegroundColor Cyan
            Write-Host "Export GitLab users, groups, and memberships to JSON files for later import into Azure DevOps."
            Write-Host ""
            
            $exportDir = Read-Host "Enter output directory for export (press Enter for 'exports')"
            if ([string]::IsNullOrWhiteSpace($exportDir)) {
                $exportDir = "exports"
            }
            
            # Ensure the exports directory exists
            if (-not (Test-Path $exportDir)) {
                New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
                Write-Host "[INFO] Created export directory: $exportDir" -ForegroundColor Green
            }
            
            Write-Host ""
            Write-Host "Export Profile Options:" -ForegroundColor Cyan
            Write-Host "  1) Minimal   - Users and groups only" -ForegroundColor White
            Write-Host "  2) Standard  - Users, groups, and projects" -ForegroundColor White  
            Write-Host "  3) Complete  - Users, groups, projects, and all memberships" -ForegroundColor White
            Write-Host ""
            
            $profileChoice = Read-Host "Select export profile (1-3)"
            $profile = switch ($profileChoice) {
                '1' { 'Minimal' }
                '2' { 'Standard' }
                '3' { 'Complete' }
                default { 'Complete' }
            }
            
            Write-Host "[INFO] Starting export with profile: $profile" -ForegroundColor Green
            
            try {
                # Call the export script - navigate from module location to project root
                # From modules/Migration/Menu/ go up 3 levels to get to project root
                $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
                $exportScript = Join-Path $projectRoot "modules\Migration\Export-GitLabIdentity.ps1"
                
                if (-not (Test-Path $exportScript)) {
                    throw "Export script not found at: $exportScript"
                }
                
                # Import GitLab module for the export script
                $gitLabModule = Join-Path $projectRoot "modules\GitLab\GitLab.psm1"
                if (Test-Path $gitLabModule) {
                    Import-Module $gitLabModule -Force -WarningAction SilentlyContinue
                }
                
                # Show progress bar for export
                Write-Progress -Activity "Export User Information" -Status "Starting GitLab identity export..." -PercentComplete 0 -Id 3
                
                & $exportScript -OutDirectory $exportDir -Profile $profile
                
                Write-Progress -Activity "Export User Information" -Status "Export completed successfully!" -PercentComplete 100 -Id 3 -Completed
                
                Write-Host ""
                Write-Host "[SUCCESS] Export completed! Files saved to: $exportDir" -ForegroundColor Green
                Write-Host "[INFO] You can now use Option 6 to import this data into Azure DevOps" -ForegroundColor Cyan
            }
            catch {
                Write-Progress -Activity "Export User Information" -Status "Export failed!" -Id 3 -Completed
                Write-Host "[ERROR] Export failed: $($_.Exception.Message)" -ForegroundColor Red
            }
}

<#
.SYNOPSIS
    Option 6: Import user information into Azure DevOps.
#>
function Invoke-Option6-ImportUserInfo {
    # Import User Information
    Write-Host ""
    Write-Host "=== IMPORT USER INFORMATION ===" -ForegroundColor Cyan
            Write-Host "Import previously exported GitLab identity data into Azure DevOps using config-ado-ad.json mappings."
            Write-Host ""

            $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
            $defaultConfig = Join-Path $projectRoot "config-ado-ad.json"
            $configInput = Read-Host "Enter path to config-ado-ad.json (press Enter for default: $defaultConfig)"
            $configPath = if ([string]::IsNullOrWhiteSpace($configInput)) { $defaultConfig } else { $configInput }

            if (-not (Test-Path $configPath)) {
                Write-Host "[ERROR] Config file not found: $configPath" -ForegroundColor Red
                return
            }

            Write-Host "Import Options:" -ForegroundColor Cyan
            Write-Host "  1) Dry Run    - Preview what would be imported (recommended first)" -ForegroundColor Yellow
            Write-Host "  2) Execute    - Perform actual import to Azure DevOps for all projects" -ForegroundColor White
            Write-Host ""

            $importChoice = Read-Host "Select import mode (1-2)"
            $dryRun = ($importChoice -eq '1')

            Write-Host "[INFO] Starting import in $(if ($dryRun) { 'DRY RUN' } else { 'EXECUTE' }) mode using $configPath ..." -ForegroundColor Green

            try {
                Write-Progress -Activity "Import User Information" -Status "Starting GitLab identity import..." -PercentComplete 0 -Id 4

                $invokeParams = @{ ConfigPath = $configPath }
                if ($dryRun) { $invokeParams['DryRun'] = $true }

                Invoke-GitLabIdentityToAdoImport @invokeParams

                Write-Progress -Activity "Import User Information" -Status "Import completed successfully!" -PercentComplete 100 -Id 4 -Completed

                Write-Host ""
                Write-Host "[SUCCESS] Import completed!" -ForegroundColor Green
                if ($dryRun) {
                    Write-Host "[INFO] This was a dry run. Use Execute mode to perform actual import." -ForegroundColor Cyan
                }
            }
            catch {
                Write-Progress -Activity "Import User Information" -Status "Import failed!" -Id 4 -Completed
                Write-Host "[ERROR] Import failed: $($_.Exception.Message)" -ForegroundColor Red
            }
}

<#
.SYNOPSIS
    Option 7: Import user information (ADO-only).
#>
function Invoke-Option7-ImportUserInfoAdoOnly {
    # Import User Info (ADO-only)
    Write-Host ""
    Write-Host "=== IMPORT USER INFORMATION (ADO-ONLY) ===" -ForegroundColor Cyan
            Write-Host "Map existing AD groups into Azure DevOps (skips AD OU/group/user changes)." -ForegroundColor Gray
            Write-Host ""

            $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
            $defaultConfig = Join-Path $projectRoot "config-ado-ad.json"
            $configInput = Read-Host "Enter path to config-ado-ad.json (press Enter for default: $defaultConfig)"
            $configPath = if ([string]::IsNullOrWhiteSpace($configInput)) { $defaultConfig } else { $configInput }

            if (-not (Test-Path $configPath)) {
                Write-Host "[ERROR] Config file not found: $configPath" -ForegroundColor Red
                return
            }

            Write-Host "Import Options:" -ForegroundColor Cyan
            Write-Host "  1) Dry Run    - Preview mappings only (recommended first)" -ForegroundColor Yellow
            Write-Host "  2) Execute    - Map AD groups into Azure DevOps" -ForegroundColor White
            Write-Host ""

            $importChoice = Read-Host "Select import mode (1-2)"
            $dryRun = ($importChoice -eq '1')

            Write-Host "[INFO] Starting ADO-only import in $(if ($dryRun) { 'DRY RUN' } else { 'EXECUTE' }) mode using $configPath ..." -ForegroundColor Green

            try {
                Write-Progress -Activity "Import User Information (ADO-only)" -Status "Starting ADO mapping..." -PercentComplete 0 -Id 6

                $invokeParams = @{ ConfigPath = $configPath; SkipAdOperations = $true }
                if ($dryRun) { $invokeParams['DryRun'] = $true }

                Invoke-GitLabIdentityToAdoImport @invokeParams

                Write-Progress -Activity "Import User Information (ADO-only)" -Status "Import completed successfully!" -PercentComplete 100 -Id 6 -Completed

                Write-Host ""
                Write-Host "[SUCCESS] ADO-only import completed!" -ForegroundColor Green
                if ($dryRun) {
                    Write-Host "[INFO] This was a dry run. Use Execute mode to perform actual mapping." -ForegroundColor Cyan
                }
            }
            catch {
                Write-Progress -Activity "Import User Information (ADO-only)" -Status "Import failed!" -Id 6 -Completed
                Write-Host "[ERROR] Import failed: $($_.Exception.Message)" -ForegroundColor Red
            }
}

<#
.SYNOPSIS
    Option 15: Reset user passwords.
#>
function Invoke-Option15-ResetUserPasswords {
    # Reset User Passwords
    Write-Host ""
    Write-Host "=== RESET USER PASSWORDS ===" -ForegroundColor Cyan
            Write-Host "Reset Active Directory passwords for exported GitLab users and send email notifications." -ForegroundColor Gray
            Write-Host ""
            Write-Host "This will:" -ForegroundColor Yellow
            Write-Host "  1. Read users from exported JSON file" -ForegroundColor Gray
            Write-Host "  2. Find matching AD accounts" -ForegroundColor Gray
            Write-Host "  3. Generate secure random passwords" -ForegroundColor Gray
            Write-Host "  4. Reset AD passwords" -ForegroundColor Gray
            Write-Host "  5. Send email notifications to users" -ForegroundColor Gray
            Write-Host ""

            # Get users JSON path
            $defaultUsersPath = Join-Path (Join-Path $script:RepoRoot 'exports') 'users.json'
            Write-Host "Default users file: $defaultUsersPath" -ForegroundColor Gray
            $usersPath = Read-Host "Enter users JSON file path (or press Enter for default)"
            if ([string]::IsNullOrWhiteSpace($usersPath)) {
                $usersPath = $defaultUsersPath
            }

            if (-not (Test-Path $usersPath)) {
                Write-Host "[ERROR] Users file not found: $usersPath" -ForegroundColor Red
                Write-Host "[INFO] Please export users first using Option 5" -ForegroundColor Yellow
                continue
            }

            # Email template path
            $defaultTemplatePath = Join-Path (Join-Path $script:RepoRoot 'templates') 'password-reset-email.template.txt'
            Write-Host ""
            Write-Host "Email template: $defaultTemplatePath" -ForegroundColor Gray
            $templatePath = Read-Host "Enter custom template path (or press Enter for default)"
            if ([string]::IsNullOrWhiteSpace($templatePath)) {
                $templatePath = $defaultTemplatePath
            }

            # SMTP Configuration
            Write-Host ""
            Write-Host "SMTP Configuration:" -ForegroundColor Cyan
            $smtpServer = Read-Host "SMTP server address (or press Enter to skip email notifications)"
            
            $skipEmail = [string]::IsNullOrWhiteSpace($smtpServer)
            $smtpPort = 25
            $fromAddress = 'noreply@company.com'
            $useSSL = $false
            $smtpCred = $null

            if (-not $skipEmail) {
                $smtpPortInput = Read-Host "SMTP port (default: 25)"
                if (-not [string]::IsNullOrWhiteSpace($smtpPortInput)) {
                    $smtpPort = [int]$smtpPortInput
                }

                $fromAddress = Read-Host "From email address (default: noreply@company.com)"
                if ([string]::IsNullOrWhiteSpace($fromAddress)) {
                    $fromAddress = 'noreply@company.com'
                }

                $useSSLInput = Read-Host "Use SSL? (y/n, default: n)"
                $useSSL = $useSSLInput -eq 'y'

                $authRequired = Read-Host "SMTP requires authentication? (y/n, default: n)"
                if ($authRequired -eq 'y') {
                    $smtpUser = Read-Host "SMTP username"
                    $smtpPass = Read-Host "SMTP password" -AsSecureString
                    $smtpCred = New-Object System.Management.Automation.PSCredential($smtpUser, $smtpPass)
                }
            }

            # Output CSV path
            Write-Host ""
            $defaultCsvPath = Join-Path (Join-Path $script:RepoRoot 'exports') "password-reset-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
            Write-Host "Results will be saved to CSV (contains temporary passwords)" -ForegroundColor Yellow
            Write-Host "Default: $defaultCsvPath" -ForegroundColor Gray
            $csvPath = Read-Host "Enter CSV output path (or press Enter for default)"
            if ([string]::IsNullOrWhiteSpace($csvPath)) {
                $csvPath = $defaultCsvPath
            }

            # Dry run option
            Write-Host ""
            $dryRunInput = Read-Host "Perform dry run? (y/n, default: y)"
            $dryRun = ($dryRunInput -ne 'n')

            # Password length
            $passwordLength = 16
            $passwordLengthInput = Read-Host "Password length (default: 16)"
            if (-not [string]::IsNullOrWhiteSpace($passwordLengthInput)) {
                $passwordLength = [int]$passwordLengthInput
            }

            # Confirmation
            Write-Host ""
            Write-Host "Summary:" -ForegroundColor Cyan
            Write-Host "  Users file: $usersPath" -ForegroundColor Gray
            Write-Host "  Email template: $templatePath" -ForegroundColor Gray
            Write-Host "  SMTP server: $(if ($skipEmail) { 'Not configured (emails will be skipped)' } else { $smtpServer })" -ForegroundColor Gray
            Write-Host "  Output CSV: $csvPath" -ForegroundColor Gray
            Write-Host "  Password length: $passwordLength" -ForegroundColor Gray
            Write-Host "  Dry run: $dryRun" -ForegroundColor Gray
            Write-Host ""

            if (-not $dryRun) {
                Write-Host "WARNING: This will reset passwords for all matching AD users!" -ForegroundColor Red
                $confirm = Read-Host "Type 'RESET' to confirm"
                if ($confirm -ne 'RESET') {
                    Write-Host "[INFO] Password reset cancelled" -ForegroundColor Yellow
                    continue
                }
            }

            try {
                # Import the Reset-UserPasswords module
                $resetModule = Join-Path (Join-Path $script:RepoRoot 'modules\Migration') 'Reset-UserPasswords.psm1'
                if (-not (Test-Path $resetModule)) {
                    throw "Reset-UserPasswords module not found at: $resetModule"
                }
                Import-Module $resetModule -Force

                Write-Progress -Activity "Reset User Passwords" -Status "Starting password reset..." -PercentComplete 0 -Id 7

                # Get ADO collection URL from environment
                $adoCollectionUrl = $env:ADO_COLLECTION_URL
                if (-not $adoCollectionUrl) {
                    $adoCollectionUrl = Read-Host "Enter Azure DevOps collection URL (for email template)"
                }

                # Build parameters
                $resetParams = @{
                    UsersJsonPath = $usersPath
                    EmailTemplatePath = $templatePath
                    OutputCsvPath = $csvPath
                    AdoCollectionUrl = $adoCollectionUrl
                    PasswordLength = $passwordLength
                    DryRun = $dryRun
                }

                if (-not $skipEmail) {
                    $resetParams['SmtpServer'] = $smtpServer
                    $resetParams['SmtpPort'] = $smtpPort
                    $resetParams['FromAddress'] = $fromAddress
                    $resetParams['UseSSL'] = $useSSL
                    if ($smtpCred) {
                        $resetParams['SmtpCredential'] = $smtpCred
                    }
                } else {
                    $resetParams['SkipEmailNotification'] = $true
                }

                # Execute password reset
                $results = Invoke-UserPasswordReset @resetParams

                Write-Progress -Activity "Reset User Passwords" -Status "Password reset completed!" -PercentComplete 100 -Id 7 -Completed

                Write-Host ""
                Write-Host "[SUCCESS] Password reset process completed!" -ForegroundColor Green
                if (-not $dryRun) {
                    Write-Host "[IMPORTANT] Results saved to: $csvPath" -ForegroundColor Yellow
                    Write-Host "[SECURITY] Store this file securely and delete after users have changed their passwords!" -ForegroundColor Red
                }
            }
            catch {
                Write-Progress -Activity "Reset User Passwords" -Status "Password reset failed!" -Id 7 -Completed
                Write-Host "[ERROR] Password reset failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "[DEBUG] $($_.ScriptStackTrace)" -ForegroundColor Gray
            }
}

<#
.SYNOPSIS
    Option 8: Add team packs to all existing projects.
#>
function Invoke-Option8-AddTeamPacks {
    # Add Team Packs to All Existing Projects
    Write-Host ""
    Write-Host "=== ADD TEAM PACKS TO ALL EXISTING PROJECTS ===" -ForegroundColor Cyan
            Write-Host "This will enhance all Azure DevOps projects with team resources (Business, Development, Security, Management packs)."
            Write-Host ""
            $sourceProjectForClone = Read-Host "Optional: enter a source project to clone wiki content from (press Enter to skip)"
            if (-not [string]::IsNullOrWhiteSpace($sourceProjectForClone)) {
                Write-Host "[INFO] Will attempt efficient wiki cloning from '$sourceProjectForClone' into each target project (when different)." -ForegroundColor Cyan
            }
            Write-Host ""
            
            $prevProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                # Get all Azure DevOps projects
                Write-Host "[INFO] Fetching Azure DevOps projects..." -ForegroundColor Cyan
                $allProjects = Get-AdoProjectList -RefreshCache
                    
                    if ($allProjects.Count -eq 0) {
                        Write-Host "[ERROR] No Azure DevOps projects found." -ForegroundColor Red
                        Write-Host "[TIP] Create projects first using Option 3." -ForegroundColor Yellow
                        return
                    }
                    
                    Write-Host "[INFO] Found $($allProjects.Count) project(s). Applying team packs to all..." -ForegroundColor Green
                    Write-Host ""
                    
                    $successCount = 0
                    $errorCount = 0
                    
                    # Resolve source wiki once; do not attempt to create/ensure it here
                    $sourceWikiId = $null
                    if ($sourceProjectForClone) {
                        try {
                            $encSource = [uri]::EscapeDataString($sourceProjectForClone)
                            $sourceWikis = Invoke-AdoRest GET "/$encSource/_apis/wiki/wikis" -ReturnNullOnNotFound
                            if ($sourceWikis -and $sourceWikis.PSObject.Properties['value']) {
                                $sourceWikiId = ($sourceWikis.value | Where-Object { $_.PSObject.Properties['id'] } | Select-Object -First 1).id
                            }
                            elseif ($sourceWikis -is [System.Array]) {
                                $sourceWikiId = ($sourceWikis | Where-Object { $_.PSObject.Properties['id'] } | Select-Object -First 1).id
                            }
                            elseif ($sourceWikis -and $sourceWikis.PSObject.Properties['id']) {
                                $sourceWikiId = $sourceWikis.id
                            }

                            if (-not $sourceWikiId) {
                                throw "No wiki found for source project '$sourceProjectForClone'"
                            }
                        }
                        catch {
                            throw "Source wiki could not be resolved for '$sourceProjectForClone': $($_.Exception.Message)"
                        }
                    }
                    
                foreach ($project in $allProjects) {
                    $projectName = $project.name
                    Write-Host ""
                    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
                    Write-Host "║ 🚀 STARTING TEAM PACKS FOR PROJECT: $projectName" -ForegroundColor Magenta -NoNewline
                    $padding = 55 - $projectName.Length
                    if ($padding -gt 0) { Write-Host (" " * $padding) -NoNewline }
                    Write-Host "║" -ForegroundColor Magenta
                    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
                    Write-Host ""
                    
                    try {
                        $packParams = @{ DestProject = $projectName }

                        if ($sourceProjectForClone -and ($sourceProjectForClone -eq $projectName)) {
                            Write-Host "  [INFO] Skipping '$projectName' because it is the source wiki project." -ForegroundColor Yellow
                            continue
                        }

                        $preCloned = $false
                        if ($sourceWikiId -and $sourceProjectForClone -and ($sourceProjectForClone -ne $projectName)) {
                            $targetRepoName = if ($projectName -like '*.wiki') { $projectName } else { "$projectName.wiki" }
                            $encTarget = [uri]::EscapeDataString($projectName)
                            $existingRepos = Invoke-AdoRest GET "/$encTarget/_apis/git/repositories" -ReturnNullOnNotFound
                            if ($existingRepos -and $existingRepos.PSObject.Properties['value']) {
                                $repoToDelete = @($existingRepos.value) | Where-Object { $_.name -eq $targetRepoName -or $_.name -eq "$targetRepoName.wiki" } | Select-Object -First 1
                                if ($repoToDelete -and $repoToDelete.id) {
                                    Write-Host "  [INFO] Deleting existing wiki repository '$($repoToDelete.name)' in '$projectName' before clone..." -ForegroundColor Yellow
                                    Invoke-AdoRest DELETE "/_apis/git/repositories/$($repoToDelete.id)" | Out-Null
                                }
                            }

                            Write-Host "  [INFO] Cloning wiki from '$sourceProjectForClone' into '$projectName' (overwriting existing content)..." -ForegroundColor Gray
                            Copy-AdoWikiViaGit -SourceProject $sourceProjectForClone -TargetProject $projectName -WikiId $sourceWikiId
                            $preCloned = $true
                        }
                        elseif ($sourceProjectForClone -and -not $sourceWikiId) {
                            throw "Source wiki could not be resolved for '$sourceProjectForClone' (clone required)."
                        }

                        if ($preCloned) {
                            $packParams['SkipWikiClone'] = $true
                        }

                        Write-Host "  [INFO] Provisioning Business Team Pack..." -ForegroundColor Gray
                        Initialize-BusinessInit @packParams
                        
                        Write-Host "  [INFO] Provisioning Development Team Pack..." -ForegroundColor Gray
                        Initialize-DevInit @packParams -ProjectType 'all'
                        
                        Write-Host "  [INFO] Provisioning Security Team Pack..." -ForegroundColor Gray
                        Initialize-SecurityInit @packParams
                        
                        Write-Host "  [INFO] Provisioning Management Team Pack..." -ForegroundColor Gray
                        Initialize-ManagementInit @packParams
                        
                        Write-Host "  [SUCCESS] All team packs applied to $projectName" -ForegroundColor Green
                        $successCount++
                    }
                    catch {
                        Write-Host "  [ERROR] Failed to apply team packs to $projectName`: $($_.Exception.Message)" -ForegroundColor Red
                        $errorCount++
                    }
                    
                    Write-Host ""
                    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
                    Write-Host "║ ✅ COMPLETED TEAM PACKS FOR PROJECT: $projectName" -ForegroundColor Magenta -NoNewline
                    $padding = 55 - $projectName.Length
                    if ($padding -gt 0) { Write-Host (" " * $padding) -NoNewline }
                    Write-Host "║" -ForegroundColor Magenta
                    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
                    
                    # Wait 2 seconds between projects to avoid overwhelming the API
                    if ($project -ne $allProjects[-1]) {
                        Write-Host ""
                        Write-Host "[INFO] Waiting 2 seconds before processing next project..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 2
                    }
                }                
                    Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
                    Write-Host "Projects processed: $($allProjects.Count)" -ForegroundColor White
                    Write-Host "Successful: $successCount" -ForegroundColor Green
                    Write-Host "Failed: $errorCount" -ForegroundColor Red
                
            }
            catch {
                Write-Host "[ERROR] Failed to process projects: $_" -ForegroundColor Red
                Write-Host ""
                Write-Host "[TIP] Verify your Azure DevOps connection and try again." -ForegroundColor Yellow
            }
            finally {
                $ProgressPreference = $prevProgressPreference
            }
}

<#
.SYNOPSIS
    Option 9: Import requirements from Excel.
#>
function Invoke-Option9-ImportRequirements {
    # Import Requirements from Excel
    Write-Host ""
    Write-Host "=== IMPORT REQUIREMENTS FROM EXCEL ===" -ForegroundColor Cyan
            Write-Host "Import work items from requirements.xlsx files in prepared project folders."
            Write-Host ""
            
            try {
                # Get migrations directory
                $migrationsDir = Get-MigrationsDirectory
                if (-not $migrationsDir -or -not (Test-Path $migrationsDir)) {
                    Write-Host "[ERROR] Migrations directory not found." -ForegroundColor Red
                    return
                }
                
                # Find projects with requirements.xlsx
                $projectsWithRequirements = @()
                $projectFolders = Get-ChildItem -Path $migrationsDir -Directory
                
                foreach ($folder in $projectFolders) {
                    $requirementsPath = Join-Path $folder.FullName "requirements.xlsx"
                    if (Test-Path $requirementsPath) {
                        $projectsWithRequirements += [PSCustomObject]@{
                            Name = $folder.Name
                            RequirementsPath = $requirementsPath
                        }
                    }
                }
                
                if ($projectsWithRequirements.Count -eq 0) {
                    Write-Host "[INFO] No projects with requirements.xlsx found in migrations folder." -ForegroundColor Yellow
                    Write-Host "[TIP] Prepare projects first and ensure requirements.xlsx exists in the project folder." -ForegroundColor Gray
                    return
                }
                
                Write-Host "[INFO] Found $($projectsWithRequirements.Count) project(s) with requirements.xlsx:" -ForegroundColor Green
                Write-Host ""
                
                # Display projects
                for ($i = 0; $i -lt $projectsWithRequirements.Count; $i++) {
                    $proj = $projectsWithRequirements[$i]
                    Write-Host "  $($i + 1)) $($proj.Name)" -ForegroundColor White
                    Write-Host "      File: $($proj.RequirementsPath)" -ForegroundColor Gray
                }
                
                Write-Host ""
                $selection = Read-Host "Select project number (1-$($projectsWithRequirements.Count))"
                
                $selectionNum = 0
                if ([int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $projectsWithRequirements.Count) {
                    $selectedProject = $projectsWithRequirements[$selectionNum - 1]
                    
                    Write-Host ""
                    Write-Host "[INFO] Importing requirements for project '$($selectedProject.Name)'..." -ForegroundColor Cyan
                    
                    # Show progress bar for Excel import
                    Write-Progress -Activity "Import Requirements" -Status "Starting Excel import..." -PercentComplete 0 -Id 5
                    
                    # Call the Excel import function
                    Write-Progress -Activity "Import Requirements" -Status "Reading Excel file and validating data..." -PercentComplete 25 -Id 5
                    $result = Invoke-ExcelRequirementsImport -ProjectName $selectedProject.Name
                    
                    Write-Progress -Activity "Import Requirements" -Status "Creating work items in Azure DevOps..." -PercentComplete 75 -Id 5
                    
                    if ($result) {
                        Write-Host ""
                        Write-Host "[SUCCESS] Requirements import completed for '$($selectedProject.Name)'!" -ForegroundColor Green
                    }
                    else {
                        Write-Host ""
                        Write-Host "[WARN] Requirements import did not complete successfully." -ForegroundColor Yellow
                    }
                    
                    Write-Progress -Activity "Import Requirements" -Status "Import completed!" -PercentComplete 100 -Id 5
                }
                else {
                    Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
                }
            }
            catch {
                Write-Host "[ERROR] Failed to import requirements: $_" -ForegroundColor Red
            }
}

<#
.SYNOPSIS
    Option 11: Unattended end-to-end import.
#>
function Invoke-Option11-UnattendedImport {
    Write-Host ""
    Write-Host "=== END-TO-END UNATTENDED IMPORT FROM PROJECTS.JSON ===" -ForegroundColor Cyan
            Write-Host "This will perform complete end-to-end setup for all prepared projects:" -ForegroundColor Gray
            Write-Host "  • Initialize Azure DevOps projects (if missing)" -ForegroundColor Gray
            Write-Host "  • Migrate code from GitLab" -ForegroundColor Gray
            Write-Host "  • Apply all team packs (Business, Dev, Security, Management)" -ForegroundColor Gray
            Write-Host "  • Create dashboards" -ForegroundColor Gray
            Write-Host "  • Import work items from Excel" -ForegroundColor Gray
            Write-Host ""

            # Retrieve prepared projects
            $prepared = Get-PreparedProjects

            if (-not $prepared -or $prepared.Count -eq 0) {
                Write-Host "[INFO] No prepared projects found. Run Option 10 to prepare projects first." -ForegroundColor Yellow
                return
            }

            # Run migrations non-interactively where possible
            $oldConfirm = $ConfirmPreference
            $oldWhatIf = $WhatIfPreference
        try {
            $ConfirmPreference = 'None'
            $WhatIfPreference = $false
            $runPreparePhase = $false
            if ($env:GITLAB2DEVOPS_IMPORT_PREPARE_MODE -and $env:GITLAB2DEVOPS_IMPORT_PREPARE_MODE -match '^(1|true|yes|on)$') {
                $runPreparePhase = $true
                Write-Host "[INFO] Preparation mode enabled (GITLAB2DEVOPS_IMPORT_PREPARE_MODE=1). Projects will re-run the GitLab prepare phase before migration." -ForegroundColor Yellow
            }

            $total = $prepared.Count
            $successCount = 0
                $failureCount = 0
                $excelImportTracker = @{}
                $teamPackTracker = @{}
                $dashboardTracker = @{}
                
                # Initialize progress bar for unattended migration
                Write-Progress -Activity "End-to-End Migration" -Status "Starting end-to-end migration of $total projects..." -PercentComplete 0 -Id 6
                $processedCount = 0

                foreach ($item in $prepared) {
                    $processedCount++
                    $progressPercent = [math]::Round(($processedCount - 1) / $total * 100)
                    Write-Progress -Activity "End-to-End Migration" -Status "Processing project $processedCount of $total`: $($item.ProjectName)" -PercentComplete $progressPercent -Id 6
                    
                    try {
                        Write-Host ""
                        Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                        Write-Host "║ 🚀 PROCESSING: $($item.ProjectName)" -ForegroundColor Cyan -NoNewline
                        $padding = 55 - $item.ProjectName.Length
                        if ($padding -gt 0) { Write-Host (" " * $padding) -NoNewline }
                        Write-Host "║" -ForegroundColor Cyan
                        Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                        Write-Host ""
                        
                        # STEP 1: Check if Azure DevOps project exists and initialize if needed
                        $projectExists = Test-AdoProjectExists -ProjectName $item.ProjectName
                        if (-not $projectExists) {
                            Write-Host "  [1/5] Initializing Azure DevOps project '$($item.ProjectName)'..." -ForegroundColor Cyan
                            try {
                                # Initialize the project with work item templates and basic setup
                                Initialize-AdoProject -DestProject $item.ProjectName -BulkInit
                                Write-Host "  [SUCCESS] Project initialized with work item templates" -ForegroundColor Green
                            }
                            catch {
                                Write-Host "  [ERROR] Failed to initialize project: $($_.Exception.Message)" -ForegroundColor Red
                                $failureCount++
                                continue
                            }
                        }
                        else {
                            Write-Host "  [1/5] Azure DevOps project already exists" -ForegroundColor Gray
                        }

                        # STEP 2: Migrate code
                        if ($item.Type -eq 'Single') {
                            # Skip already migrated repos
                            if ($item.RepoMigrated) {
                                Write-Host "  [2/5] Code already migrated, skipping..." -ForegroundColor Gray
                            }
                            else {
                                if ($runPreparePhase) {
                                    Invoke-Option9PreparationRefresh -PreparedItem $item | Out-Null
                                }

                                Write-Host "  [2/5] Migrating code: $($item.GitLabPath) → $($item.ProjectName)" -ForegroundColor Cyan
                                Invoke-SingleMigration -SrcPath $item.GitLabPath -DestProject $item.ProjectName -Force
                                Write-Host "  [SUCCESS] Code migrated successfully" -ForegroundColor Green
                            }
                        }
                        elseif ($item.Type -eq 'Bulk') {
                            # Skip if all projects already migrated
                            if ($item.MigratedCount -ge $item.ProjectCount) {
                                Write-Host "  [2/5] All bulk repos already migrated, skipping..." -ForegroundColor Gray
                            }
                            else {
                                if ($runPreparePhase) {
                                    Invoke-Option9PreparationRefresh -PreparedItem $item | Out-Null
                                }

                                Write-Host "  [2/5] Executing bulk migration for: $($item.ProjectName)" -ForegroundColor Cyan
                                Invoke-BulkMigrationWorkflow -AdoProject $item.ProjectName -Force
                                Write-Host "  [SUCCESS] Bulk migration completed" -ForegroundColor Green
                            }
                        }
                        else {
                            Write-Host "  [WARN] Unknown prepared item type: $($item.Type) - skipping code migration" -ForegroundColor Yellow
                        }
                        
                        # STEP 3: Apply Team Packs (Business, Dev, Security, Management)
                        if (-not $teamPackTracker.ContainsKey($item.ProjectName)) {
                            Write-Host "  [3/5] Applying team initialization packs..." -ForegroundColor Cyan
                            try {
                                $packParams = @{ DestProject = $item.ProjectName }
                                
                                Write-Host "    • Business Team Pack..." -ForegroundColor Gray
                                Initialize-BusinessInit @packParams
                                
                                Write-Host "    • Development Team Pack..." -ForegroundColor Gray
                                Initialize-DevInit @packParams -ProjectType 'all'
                                
                                Write-Host "    • Security Team Pack..." -ForegroundColor Gray
                                Initialize-SecurityInit @packParams
                                
                                Write-Host "    • Management Team Pack..." -ForegroundColor Gray
                                Initialize-ManagementInit @packParams
                                
                                Write-Host "  [SUCCESS] All team packs applied" -ForegroundColor Green
                                $teamPackTracker[$item.ProjectName] = $true
                            }
                            catch {
                                Write-Host "  [WARN] Failed to apply team packs: $($_.Exception.Message)" -ForegroundColor Yellow
                            }
                        }
                        else {
                            Write-Host "  [3/5] Team packs already applied, skipping..." -ForegroundColor Gray
                        }
                        
                        # STEP 4: Create Dashboards
                        if (-not $dashboardTracker.ContainsKey($item.ProjectName)) {
                            Write-Host "  [4/5] Creating dashboards..." -ForegroundColor Cyan
                            try {
                                # Resolve wiki id
                                $wikiId = $null
                                try {
                                    $wiki = Ensure-ProjectWiki -ProjectName $item.ProjectName
                                    if ($wiki -is [System.Collections.IDictionary]) { try { $wiki = [PSCustomObject]$wiki } catch { } }
                                    if ($wiki -and $wiki.PSObject.Properties['id']) { $wikiId = $wiki.id }
                                }
                                catch {
                                    Write-Verbose "[Dashboards] Ensure-ProjectWiki failed: $_"
                                }
                                if (-not $wikiId) {
                                    try { $wikiId = Get-ProjectWikiId -ProjectName $item.ProjectName } catch { }
                                }
                                if (-not $wikiId) { $wikiId = $item.ProjectName }
                                
                                New-Adodevdashboard -Project $item.ProjectName -Team $item.ProjectName -WikiId $wikiId -Replace | Out-Null
                                New-AdoSecurityDashboard -Project $item.ProjectName -Team $item.ProjectName -Replace | Out-Null
                                Test-Adomanagementdashboard -Project $item.ProjectName -Team $item.ProjectName -Replace | Out-Null
                                Test-Adoqadashboard -Project $item.ProjectName -Team $item.ProjectName -Replace | Out-Null
                                
                                Write-Host "  [SUCCESS] Dashboards created" -ForegroundColor Green
                                $dashboardTracker[$item.ProjectName] = $true
                            }
                            catch {
                                Write-Host "  [WARN] Failed to create dashboards: $($_.Exception.Message)" -ForegroundColor Yellow
                            }
                        }
                        else {
                            Write-Host "  [4/5] Dashboards already created, skipping..." -ForegroundColor Gray
                        }
                        
                        # STEP 5: Import Work Items from Excel
                        if (-not $excelImportTracker.ContainsKey($item.ProjectName)) {
                            Write-Host "  [5/5] Importing work items from Excel..." -ForegroundColor Cyan
                            try {
                                $importResult = Invoke-ExcelRequirementsImport -ProjectName $item.ProjectName
                                if ($importResult) {
                                    Write-Host "  [SUCCESS] Work items imported from Excel" -ForegroundColor Green
                                }
                                else {
                                    Write-Host "  [INFO] No requirements.xlsx found or import skipped" -ForegroundColor Gray
                                }
                                $excelImportTracker[$item.ProjectName] = $true
                            }
                            catch {
                                Write-Host "  [WARN] Failed to import work items: $($_.Exception.Message)" -ForegroundColor Yellow
                            }
                        }
                        else {
                            Write-Host "  [5/5] Work items already imported, skipping..." -ForegroundColor Gray
                        }
                        
                        $successCount++
                        Write-Host ""
                        Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
                        Write-Host "║ ✅ COMPLETED: $($item.ProjectName)" -ForegroundColor Green -NoNewline
                        $padding = 55 - $item.ProjectName.Length
                        if ($padding -gt 0) { Write-Host (" " * $padding) -NoNewline }
                        Write-Host "║" -ForegroundColor Green
                        Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
                    }
                    catch {
                        Write-Host ""
                        Write-Host "  [ERROR] Failed to process $($item.ProjectName): $($_.Exception.Message)" -ForegroundColor Red
                        $failureCount++
                        continue
                    }
                }
                
                Write-Progress -Activity "End-to-End Migration" -Status "Migration completed! Generating final reports..." -PercentComplete 100 -Id 6

                Write-Host ""
                Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
                Write-Host "                    FINAL SUMMARY" -ForegroundColor Cyan
                Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
                Write-Host "Total projects processed: $total" -ForegroundColor White
                Write-Host "Successful: $successCount" -ForegroundColor Green
                Write-Host "Failed: $failureCount" -ForegroundColor Red
                Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
            }
            finally {
                $ConfirmPreference = $oldConfirm
                $WhatIfPreference = $oldWhatIf
            }
}

<#
.SYNOPSIS
    Option 12: Sync repos from projects.json.
#>
function Invoke-Option12-SyncRepos {
    Write-Host ""
    Write-Host "=== SYNC REPOS FROM PROJECTS.JSON MAP ===" -ForegroundColor Cyan
            Write-Host "This will sync GitLab repositories to Azure DevOps projects according to the projects.json mapping."
            Write-Host "Only repositories that exist in both GitLab and Azure DevOps will be synced."
            Write-Host ""

            # Get the projects.json file path
            $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
            $projectsJsonPath = Join-Path $projectRoot 'projects.json'

            if (-not (Test-Path $projectsJsonPath)) {
                Write-Host "[ERROR] projects.json not found at: $projectsJsonPath" -ForegroundColor Red
                return
            }

            try {
                $projectsConfig = Get-Content $projectsJsonPath -Raw | ConvertFrom-Json
                Write-Host "[INFO] Loaded $($projectsConfig.Count) project mappings from projects.json" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Failed to parse projects.json: $($_.Exception.Message)" -ForegroundColor Red
                return
            }

            $totalMappings = 0
            $validMappings = 0
            $syncSuccess = 0
            $syncFailed = 0
            $processedMappings = 0

            # Pre-calc total mappings for progress tracking
            foreach ($mapping in $projectsConfig) {
                if ($mapping.projects) { $totalMappings += $mapping.projects.Count }
            }

            Write-Host ""
            Write-Host "[INFO] Validating project mappings..." -ForegroundColor Cyan

            foreach ($mapping in $projectsConfig) {
                $adoProject = $mapping.adoproject
                $gitlabProjects = $mapping.projects

                foreach ($gitlabProject in $gitlabProjects) {
                    $processedMappings++
                    $progressPct = if ($totalMappings -gt 0) { [int](($processedMappings / $totalMappings) * 100) } else { 0 }
                    Write-Progress -Activity "Sync Repos from projects.json" -Status "Processing $gitlabProject -> $adoProject ($processedMappings of $totalMappings)" -PercentComplete $progressPct -Id 12

                    Write-Host "  Checking: $gitlabProject → $adoProject" -ForegroundColor Gray

                    # Check if Azure DevOps project exists
                    $adoProjectExists = $false
                    try {
                        $adoProjectExists = Test-AdoProjectExists -ProjectName $adoProject
                    }
                    catch {
                        Write-Host "    [WARN] Could not verify Azure DevOps project '$adoProject': $($_.Exception.Message)" -ForegroundColor Yellow
                    }

                    if (-not $adoProjectExists) {
                        Write-Host "    [SKIP] Azure DevOps project '$adoProject' does not exist" -ForegroundColor Yellow
                        continue
                    }

                    # Check if GitLab project exists (by checking if it was prepared)
                    $repoName = ($gitlabProject -split '/')[-1]
                    $migrationsDir = Get-MigrationsDirectory
                    $configFile = Join-Path $migrationsDir "$adoProject\migration-config.json"

                    if (-not (Test-Path $configFile)) {
                        Write-Host "    [SKIP] Project not prepared. Expected config file: $configFile" -ForegroundColor Yellow
                        Write-Host "           Run Option 1 (Prepare Single) or Option 10 (Prepare from projects.json) first." -ForegroundColor Gray
                        continue
                    }

                    $validMappings++
                    Write-Host "    [VALID] Both GitLab project and Azure DevOps project exist" -ForegroundColor Green

                    # Attempt to sync
                    try {
                        Write-Host "    [SYNC] Starting sync: $gitlabProject → $adoProject" -ForegroundColor Cyan
                        Invoke-SingleMigration -SrcPath $gitlabProject -DestProject $adoProject -AllowSync
                        Write-Host "    [SUCCESS] Synced: $gitlabProject" -ForegroundColor Green
                        $syncSuccess++
                    }
                    catch {
                        Write-Host "    [ERROR] Failed to sync $gitlabProject → $adoProject`: $($_.Exception.Message)" -ForegroundColor Red
                        $syncFailed++
                    }
                }
            }

            Write-Progress -Activity "Sync Repos from projects.json" -Status "Completed" -PercentComplete 100 -Id 12 -Completed

            Write-Host ""
            Write-Host "=== SYNC SUMMARY ===" -ForegroundColor Cyan
            Write-Host "Total mappings in projects.json: $totalMappings" -ForegroundColor White
            Write-Host "Valid mappings (both projects exist): $validMappings" -ForegroundColor Green
            Write-Host "Successful syncs: $syncSuccess" -ForegroundColor Green
            Write-Host "Failed syncs: $syncFailed" -ForegroundColor Red

            if ($validMappings -eq 0) {
                Write-Host ""
                Write-Host "[INFO] No valid mappings found. Make sure to:" -ForegroundColor Yellow
                Write-Host "  1. Prepare projects using Option 1 or Option 10" -ForegroundColor Gray
                Write-Host "  2. Create Azure DevOps projects using Option 3" -ForegroundColor Gray
            }
}

<#
.SYNOPSIS
    Option 13: Create dashboards for all projects.
#>
function Invoke-Option13-CreateDashboards {
    Write-Host ""
            Write-Host "=== CREATE DASHBOARDS FOR ALL AZURE DEVOPS PROJECTS ===" -ForegroundColor Cyan
            Write-Host "This will ensure standard dashboards exist across all projects (Dev, Security, Management, QA/Overview)." -ForegroundColor Gray
            Write-Host ""

            try {
                Write-Host "[INFO] Fetching Azure DevOps projects..." -ForegroundColor Cyan
                $allProjects = Get-AdoProjectList -RefreshCache
                if (-not $allProjects -or $allProjects.Count -eq 0) {
                    Write-Host "[ERROR] No Azure DevOps projects found." -ForegroundColor Red
                    return
                }

                $total = $allProjects.Count
                $i = 0
                $success = 0
                $failed = 0

                foreach ($proj in $allProjects) {
                    $i++
                    $projName = $proj.name
                    $pct = [int](($i / $total) * 100)
                    Write-Progress -Activity "Creating dashboards" -Status "Processing $projName ($i of $total)" -PercentComplete $pct -Id 14

                    Write-Host ""
                    Write-Host "  [INFO] Ensuring dashboards for project '$projName'..." -ForegroundColor Cyan
                    try {
                        # Resolve wiki id (required for Dev dashboard wiki page)
                        $wikiId = $null
                        try {
                            $wiki = Ensure-ProjectWiki -ProjectName $projName
                            if ($wiki -is [System.Collections.IDictionary]) { try { $wiki = [PSCustomObject]$wiki } catch { } }
                            if ($wiki -and $wiki.PSObject.Properties['id']) { $wikiId = $wiki.id }
                        }
                        catch {
                            Write-Verbose "[Dashboards] Ensure-ProjectWiki failed for '$projName': $_"
                        }
                        if (-not $wikiId) {
                            try { $wikiId = Get-ProjectWikiId -ProjectName $projName } catch { }
                        }
                        if (-not $wikiId) { $wikiId = $projName }  # fallback to project name for API that accepts projectId/name

                        New-Adodevdashboard -Project $projName -Team $projName -WikiId $wikiId -Replace | Out-Null
                        New-AdoSecurityDashboard -Project $projName -Team $projName -Replace | Out-Null
                        Test-Adomanagementdashboard -Project $projName -Team $projName -Replace | Out-Null
                        Test-Adoqadashboard -Project $projName -Team $projName -Replace | Out-Null

                        Write-Host "  [SUCCESS] Dashboards ensured for '$projName'" -ForegroundColor Green
                        $success++
                    }
                    catch {
                        Write-Host "  [ERROR] Failed to ensure dashboards for '$projName': $($_.Exception.Message)" -ForegroundColor Red
                        $failed++
                    }
                }

                Write-Progress -Activity "Creating dashboards" -Status "Completed" -PercentComplete 100 -Id 14 -Completed
                Write-Host ""
                Write-Host "=== DASHBOARD SUMMARY ===" -ForegroundColor Cyan
                Write-Host "Projects processed: $total" -ForegroundColor White
                Write-Host "Successful: $success" -ForegroundColor Green
                Write-Host "Failed: $failed" -ForegroundColor Red
            }
            catch {
                Write-Host "[ERROR] Dashboard creation failed: $($_.Exception.Message)" -ForegroundColor Red
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
    Automatically provisions every team pack for a project without prompts.

.DESCRIPTION
    Runs Business, Development, Security, and Management initialization packs
    sequentially so migrated projects receive the full suite of wiki pages,
    queries, dashboards, and repository assets in unattended scenarios (Option 9).

.PARAMETER ProjectName
    Azure DevOps project that should receive all packs.
#>
<#
.SYNOPSIS
    Imports work items from requirements.xlsx for the specified project when available.

.DESCRIPTION
    Looks for requirements spreadsheets in project-specific migration folders (or a custom path),
    then calls Import-AdoWorkItemsFromExcel to create hierarchical Azure DevOps work items.
    Used by Option 9 so unattended migrations still hydrate work item backlogs.

.PARAMETER ProjectName
    Destination Azure DevOps project name.
#>
function Invoke-ExcelRequirementsImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        return $false
    }

    if ($env:GITLAB2DEVOPS_SKIP_REQUIREMENTS_IMPORT -and
        $env:GITLAB2DEVOPS_SKIP_REQUIREMENTS_IMPORT -match '^(1|true)$') {
        Write-Host "[INFO] Skipping Excel import for '$ProjectName' (GITLAB2DEVOPS_SKIP_REQUIREMENTS_IMPORT=1)." -ForegroundColor Yellow
        return $false
    }

    $worksheetName = if ($env:GITLAB2DEVOPS_REQUIREMENTS_SHEET) { $env:GITLAB2DEVOPS_REQUIREMENTS_SHEET } else { "Requirements" }
    $teamName = "$ProjectName Team"

    $candidatePaths = @()
    if ($env:GITLAB2DEVOPS_REQUIREMENTS_FILE) {
        $candidatePaths += $env:GITLAB2DEVOPS_REQUIREMENTS_FILE
    }

    try {
        $paths = Get-ProjectPaths -ProjectName $ProjectName -ErrorAction Stop
        if ($paths -and $paths.projectDir) {
            $candidatePaths += (Join-Path $paths.projectDir "requirements.xlsx")
        }
    }
    catch {
        Write-LogLevelVerbose "[Invoke-ExcelRequirementsImport] Get-ProjectPaths failed for '$ProjectName': $_"
    }

    try {
        $migrationsDir = Get-MigrationsDirectory
        if ($migrationsDir) {
            $candidatePaths += (Join-Path $migrationsDir "$ProjectName\requirements.xlsx")
        }
    }
    catch {
        Write-LogLevelVerbose "[Invoke-ExcelRequirementsImport] Get-MigrationsDirectory failed: $_"
    }

    $excelPath = $null
    foreach ($path in ($candidatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path $path) {
            $excelPath = (Resolve-Path $path).Path
            break
        }
    }

    if (-not $excelPath) {
        Write-Host "[INFO] No requirements.xlsx found for '$ProjectName'. Skipping Excel import." -ForegroundColor Gray
        return $false
    }

    Write-Host "[INFO] Importing work items from Excel for '$ProjectName'..." -ForegroundColor Cyan
    Write-Host "       File: $excelPath" -ForegroundColor Gray
    Write-Host "       Worksheet: $worksheetName" -ForegroundColor Gray

    try {
        $result = Import-AdoWorkItemsFromExcel -Project $ProjectName `
                                               -ExcelPath $excelPath `
                                               -WorksheetName $worksheetName `
                                               -TeamName $teamName

        if ($result) {
            Write-Host "[SUCCESS] Imported $($result.SuccessCount) work items (errors: $($result.ErrorCount))" -ForegroundColor Green
            if ($result.ErrorCount -gt 0 -and $result.Errors) {
                Write-Host "[INFO] First error: $($result.Errors[0])" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "[SUCCESS] Excel import completed." -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Host "[WARN] Excel import failed for '$ProjectName': $_" -ForegroundColor Yellow
        return $false
    }
}

<#
.SYNOPSIS
    Re-runs the GitLab preparation phase for a prepared project.

.DESCRIPTION
    Option 9 normally skips preparation and only migrates/imports. When preparation
    refresh mode is enabled, this helper can re-download repositories and regenerate
    preflight assets before the migration runs.

.PARAMETER PreparedItem
    Entry returned by Get-PreparedProjects (Type = Single or Bulk).
#>
function Invoke-Option9PreparationRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$PreparedItem
    )

    if (-not $PreparedItem) { return $false }

    if ($PreparedItem.Type -eq 'Single') {
        if ($PreparedItem.Structure -and $PreparedItem.Structure -eq 'legacy') {
            Write-Host "[WARN] Legacy preparations are not refreshable automatically. Skipping '$($PreparedItem.ProjectName)'." -ForegroundColor Yellow
            return $false
        }

        $gitLabPath = $PreparedItem.GitLabPath
        if ([string]::IsNullOrWhiteSpace($gitLabPath)) {
            Write-Host "[WARN] Prepared entry '$($PreparedItem.ProjectName)' is missing GitLab path. Skipping refresh." -ForegroundColor Yellow
            return $false
        }

        $repoName = ($gitLabPath -split '/')[-1]
        try {
            $paths = Get-ProjectPaths -AdoProject $PreparedItem.ProjectName -GitLabProject $repoName -ErrorAction Stop
            Write-Host "[INFO] Refreshing preparation for '$($PreparedItem.ProjectName)' from $gitLabPath ..." -ForegroundColor Cyan
            Initialize-GitLab -ProjectPath $gitLabPath -CustomBaseDir $paths.projectDir -CustomProjectName $repoName | Out-Null
            try {
                $preReportPath = Join-Path $paths.gitlabDir "reports\pre-migration-report.json"
                New-MigrationPreReport -GitLabPath $gitLabPath `
                                       -AdoProject $PreparedItem.ProjectName `
                                       -AdoRepoName $repoName `
                                       -OutputPath $preReportPath -AllowSync | Out-Null
                Write-Verbose "[Option9Prep] Pre-migration report refreshed at $preReportPath"
            }
            catch {
                Write-Warning "[Option9Prep] Failed to refresh pre-migration report for '$($PreparedItem.ProjectName)': $($_.Exception.Message)"
            }
            try { Export-GitLabDocumentation -AdoProject $PreparedItem.ProjectName | Out-Null } catch { Write-Verbose "[Option9Prep] Documentation export failed: $_" }
            try {
                if ($paths.configFile) {
                    $container = Split-Path $paths.configFile -Parent
                    New-MigrationHtmlReport -ProjectPath $container | Out-Null
                }
                New-MigrationsOverviewReport | Out-Null
            }
            catch {
                Write-Verbose "[Option9Prep] Report regeneration failed: $_"
            }
            return $true
        }
        catch {
            Write-Host "[WARN] Preparation refresh failed for '$($PreparedItem.ProjectName)': $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }
    elseif ($PreparedItem.Type -eq 'Bulk') {
        $configPath = $PreparedItem.ConfigFile
        if (-not (Test-Path $configPath)) {
            Write-Host "[WARN] Bulk configuration not found for '$($PreparedItem.ProjectName)'. Skipping refresh." -ForegroundColor Yellow
            return $false
        }

        try {
            $config = Get-Content $configPath | ConvertFrom-Json
            $projectPaths = @()
            if ($config.projects) {
                foreach ($proj in $config.projects) {
                    if ($proj.PSObject.Properties['gitlab_path'] -and $proj.gitlab_path) {
                        $projectPaths += [string]$proj.gitlab_path
                    }
                    elseif ($proj.PSObject.Properties['project'] -and $proj.project) {
                        $projectPaths += [string]$proj.project
                    }
                }
            }

            if ($projectPaths.Count -eq 0) {
                Write-Host "[WARN] No GitLab paths found in $configPath. Skipping bulk refresh for '$($PreparedItem.ProjectName)'." -ForegroundColor Yellow
                return $false
            }

            Write-Host "[INFO] Refreshing bulk preparation for '$($PreparedItem.ProjectName)' ($($projectPaths.Count) repositories)..." -ForegroundColor Cyan
            Invoke-BulkPreparationWorkflow -ProjectPaths $projectPaths -DestProject $PreparedItem.ProjectName | Out-Null
            return $true
        }
        catch {
            Write-Host "[WARN] Bulk preparation refresh failed for '$($PreparedItem.ProjectName)': $($_.Exception.Message)" -ForegroundColor Yellow
            return $false
        }
    }

    Write-Verbose "[Option9Prep] Unknown prepared item type '$($PreparedItem.Type)' - no refresh performed."
    return $false
}

# Export public functions
Export-ModuleMember -Function @(
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu'
)
