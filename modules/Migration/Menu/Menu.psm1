
<#
.DESCRIPTION
    This module handles the interactive menu system and main workflow orchestration
    for the GitLab to Azure DevOps migration toolkit.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, Migration.Core modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
# Import required modules
$migrationRoot = Split-Path $PSScriptRoot -Parent
Import-Module -WarningAction SilentlyContinue (Join-Path $migrationRoot "Core\MigrationCore.psm1") -Force -Global

# Calculate absolute path to AzureDevOps module
$azureDevOpsModulePath = Join-Path (Split-Path $migrationRoot -Parent) "AzureDevOps\AzureDevOps.psm1"
Import-Module -WarningAction SilentlyContinue $azureDevOpsModulePath -Force -Global

# Import Team Packs so resource provisioning helpers are available outside initialization flows
$teamPacksModulePath = Join-Path $migrationRoot "TeamPacks\TeamPacks.psm1"
if (Test-Path $teamPacksModulePath) {
    Import-Module -WarningAction SilentlyContinue $teamPacksModulePath -Force -Global
}

# Import Project Initialization module for Initialize-AdoProject function
$projectInitModulePath = Join-Path $migrationRoot "Initialization\ProjectInitialization.psm1"
if (Test-Path $projectInitModulePath) {
    Import-Module -WarningAction SilentlyContinue $projectInitModulePath -Force -Global
}

# Module-level variables for menu context
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabToken = $null
$script:GitLabBaseUrl = $null
$script:BuildDefinitionId = 0
$script:SonarStatusContext = ""

<#
.SYNOPSIS
    Displays the interactive migration menu.

.DESCRIPTION
    Main entry point for interactive operations. Provides 5 options:
    1) Prepare single project
    2) Bulk preparation 
    3) Create DevOps project
    4) Start planned migration

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
    Show-MigrationMenu -AdoPat $pat -GitLabBaseUrl "https://gitlab.com" -GitLabToken $token
#>
function Show-MigrationMenu {
    [CmdletBinding()]
    param()
    
    # Initialize Core.Rest module in menu context (now .env-driven)
    # try {
    #     #Initialize-CoreRest
    #     Write-Verbose "[Menu] Core.Rest module initialized successfully"
        
    #     # Get configuration values from Core.Rest and populate script variables
    #     # $coreConfig = Get-CoreRestConfig
    #     $script:CollectionUrl = $coreConfig.CollectionUrl
    #     $script:AdoPat = $coreConfig.AdoPat
    #     $script:GitLabBaseUrl = $coreConfig.GitLabBaseUrl
    #     $script:GitLabToken = $coreConfig.GitLabToken
    #     Write-Verbose "[Menu] Configuration loaded from Core.Rest"
    # }
    # catch {
    #     Write-Warning "[Menu] Failed to initialize Core.Rest module: $_"
    #     Write-Host "[ERROR] Failed to initialize connection modules. Please check your .env file." -ForegroundColor Red
    #     return
    # }
    
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
    Write-Host "  5) Export User Information  " -ForegroundColor White -NoNewline
    Write-Host "│ Export GitLab users/groups to JSON" -ForegroundColor Gray
    Write-Host "  6) Import User Information  " -ForegroundColor White -NoNewline
    Write-Host "│ Import JSON data to Azure DevOps" -ForegroundColor Gray
    Write-Host "  7) Import User Info (ADO-only)" -ForegroundColor White -NoNewline
    Write-Host "- Map AD groups into Azure DevOps (skip AD changes)" -ForegroundColor Gray
    Write-Host ""
    Write-Host ""
    Write-Host "  8) Add Team Packs           " -ForegroundColor White -NoNewline
    Write-Host "│ Enhance all existing projects with team resources" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  9) Import Requirements       " -ForegroundColor White -NoNewline
    Write-Host "│ Import work items from requirements.xlsx" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  10) Unattended: Prepare from projects.json" -ForegroundColor White -NoNewline
    Write-Host "│ Prepare migration folders only (no Azure DevOps changes)" -ForegroundColor Gray
    Write-Host "  11) Unattended: Import from projects.json " -ForegroundColor White -NoNewline
    Write-Host "│ end-to-end prepare/initialize/migrate"
    Write-Host ""
    Write-Host "  12) Sync Repos from projects.json Map     " -ForegroundColor White -NoNewline
    Write-Host "│ Sync GitLab repos to Azure DevOps projects"
    Write-Host ""
    Write-Host "  13) Create Dashboards for All Projects    " -ForegroundColor White -NoNewline
    Write-Host "│ Ensure Dev/Security/Management/QA dashboards exist" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  14) Exit" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ""
    
    $choice = Read-Host "Select option (1-14)"
    if ($choice -eq '10') {
        Write-Host ""
        Write-Host "=== BULK PREPARATION FROM CONFIG FILE ===" -ForegroundColor Cyan
        Write-Host "This will read projects.json and prepare migration folders only (no Azure DevOps changes)." -ForegroundColor Gray
        Write-Host "Use Option 3 to create Azure DevOps projects after preparation." -ForegroundColor Gray
        Write-Host ""
        # From modules/Migration/Menu/ go up 3 levels to get to project root
        $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $prepScript = Join-Path $projectRoot "/modules/Migration/Prepare-MigrationsFromConfig.ps1"
        if (-not (Test-Path $prepScript)) {
            Write-Host "[ERROR] Prepare-MigrationsFromConfig.ps1 not found at: $prepScript" -ForegroundColor Red
            return
        }
        try {
            # Run unattended bulk preparation using projects.json at repo root and force updates
            $configPath = Join-Path $projectRoot 'projects.json'
            if (-not (Test-Path $configPath)) {
                # fall back to parent directory (legacy location)
                $configPath = Join-Path (Split-Path $projectRoot -Parent) 'projects.json'
            }
            & $prepScript -ConfigFile $configPath -Force
            Write-Host "[SUCCESS] Bulk preparation from config completed!" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Bulk preparation failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }
    
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
            
            # Show progress bar for preparation steps
            Write-Progress -Activity "Single Project Preparation" -Status "Initializing preparation..." -PercentComplete 0 -Id 1
            
            # Prepare using custom base directory
            Write-Progress -Activity "Single Project Preparation" -Status "Downloading GitLab repository..." -PercentComplete 25 -Id 1
            Initialize-GitLab -ProjectPath $SourceProjectPath -CustomBaseDir $paths.projectDir -CustomProjectName $gitlabProjectName
            
            # Create migration config
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
            
            # Extract documentation files
            Write-Progress -Activity "Single Project Preparation" -Status "Extracting documentation files..." -PercentComplete 75 -Id 1
            Write-Host ""
            Write-Host "[INFO] Extracting documentation files..." -ForegroundColor Cyan
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
            
            # Generate HTML report after preparation
            Write-Progress -Activity "Single Project Preparation" -Status "Generating reports..." -PercentComplete 90 -Id 1
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

            # Generate and cache the Azure DevOps pre-migration report during preparation
            Write-Progress -Activity "Single Project Preparation" -Status "Caching pre-migration report..." -PercentComplete 95 -Id 1
            try {
                $preReportPath = Join-Path $paths.gitlabDir "reports\pre-migration-report.json"
                New-MigrationPreReport -GitLabPath $SourceProjectPath -AdoProject $DestProjectName -AdoRepoName $gitlabProjectName -OutputPath $preReportPath -AllowSync | Out-Null
                Write-Host "[INFO] Pre-migration report cached: $preReportPath" -ForegroundColor Gray
            }
            catch {
                Write-Warning "[WARN] Failed to generate pre-migration report for '$SourceProjectPath': $_"
            }

            # Provision team resources once during preparation instead of after every migration run
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
                Write-Verbose "[Menu] Invoke-AllTeamPacks not available in this session; team resources were not provisioned during preparation."
            }
            
            Write-Progress -Activity "Single Project Preparation" -Status "Preparation completed successfully!" -PercentComplete 100 -Id 1
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
        '4' {
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
        '5' {
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
        '6' {
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
        '7' {
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
        '8' {
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
        '9' {
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
        '10' {
            Write-Host ""
            Write-Host "=== MIGRATE ALL PREPARED PROJECTS ===" -ForegroundColor Cyan
            Write-Host "This will migrate all projects that have already been prepared (no preparations will be performed)." -ForegroundColor Gray
            Write-Host ""

            # Retrieve prepared projects
            $prepared = Get-PreparedProjects

            if (-not $prepared -or $prepared.Count -eq 0) {
                Write-Host "[INFO] No prepared projects found. Run Option 1 or 2 to prepare projects first." -ForegroundColor Yellow
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
                
                # Initialize progress bar for unattended migration
                Write-Progress -Activity "Unattended Migration" -Status "Starting unattended migration of $total projects..." -PercentComplete 0 -Id 6
                $processedCount = 0

                foreach ($item in $prepared) {
                    $processedCount++
                    $progressPercent = [math]::Round(($processedCount - 1) / $total * 100)
                    Write-Progress -Activity "Unattended Migration" -Status "Processing project $processedCount of $total`: $($item.ProjectName)" -PercentComplete $progressPercent -Id 6
                    
                    try {
                        # Check if Azure DevOps project exists and initialize if needed
                        $projectExists = Test-AdoProjectExists -ProjectName $item.ProjectName
                        if (-not $projectExists) {
                            Write-Host "[INFO] Azure DevOps project '$($item.ProjectName)' does not exist. Initializing project with work item templates..." -ForegroundColor Cyan
                            try {
                                # Initialize the project with work item templates and basic setup
                                Initialize-AdoProject -DestProject $item.ProjectName -BulkInit
                                Write-Host "[SUCCESS] Project '$($item.ProjectName)' initialized with work item templates" -ForegroundColor Green
                            }
                            catch {
                                Write-Host "[ERROR] Failed to initialize project '$($item.ProjectName)': $($_.Exception.Message)" -ForegroundColor Red
                                $failureCount++
                                continue
                            }
                        }
                        else {
                            Write-Host "[INFO] Azure DevOps project '$($item.ProjectName)' already exists" -ForegroundColor Gray
                        }

                        if ($item.Type -eq 'Single') {
                            # Skip already migrated repos
                            if ($item.RepoMigrated) {
                                Write-Host "[INFO] Skipping already-migrated repo: $($item.ProjectName) / $($item.GitLabRepoName)" -ForegroundColor Gray
                                continue
                            }
                            if ($runPreparePhase) {
                                Invoke-Option9PreparationRefresh -PreparedItem $item | Out-Null
                            }

                            Write-Host "[INFO] Migrating single project: $($item.GitLabPath) → $($item.ProjectName)" -ForegroundColor Cyan
                            # Use Force to avoid interactive prompts
                            Invoke-SingleMigration -SrcPath $item.GitLabPath -DestProject $item.ProjectName -Force
                            $successCount++
                            Write-Host "[SUCCESS] Migrated: $($item.GitLabPath)" -ForegroundColor Green
                            if (-not $excelImportTracker.ContainsKey($item.ProjectName)) {
                                Invoke-ExcelRequirementsImport -ProjectName $item.ProjectName | Out-Null
                                $excelImportTracker[$item.ProjectName] = $true
                            }
                        }
                        elseif ($item.Type -eq 'Bulk') {
                            # Skip if all projects already migrated
                            if ($item.MigratedCount -ge $item.ProjectCount) {
                                Write-Host "[INFO] Skipping bulk project (already migrated): $($item.ProjectName)" -ForegroundColor Gray
                                continue
                            }
                            if ($runPreparePhase) {
                                Invoke-Option9PreparationRefresh -PreparedItem $item | Out-Null
                            }

                            Write-Host "[INFO] Executing bulk migration for: $($item.ProjectName)" -ForegroundColor Cyan
                            Invoke-BulkMigrationWorkflow -AdoProject $item.ProjectName -Force
                            $successCount++
                            Write-Host "[SUCCESS] Bulk migration completed for: $($item.ProjectName)" -ForegroundColor Green
                            if (-not $excelImportTracker.ContainsKey($item.ProjectName)) {
                                Invoke-ExcelRequirementsImport -ProjectName $item.ProjectName | Out-Null
                                $excelImportTracker[$item.ProjectName] = $true
                            }
                        }
                        else {
                            Write-Host "[WARN] Unknown prepared item type: $($item.Type) - skipping" -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-Host "[ERROR] Failed to migrate $($item.ProjectName): $($_.Exception.Message)" -ForegroundColor Red
                        $failureCount++
                        continue
                    }
                }
                
                Write-Progress -Activity "Unattended Migration" -Status "Migration completed! Generating final reports..." -PercentComplete 100 -Id 6

                Write-Host ""
                Write-Host "[INFO] Migration run completed. Summary:" -ForegroundColor Cyan
                Write-Host "       Total prepared items: $total" -ForegroundColor White
                Write-Host "       Successful migrations: $successCount" -ForegroundColor Green
                Write-Host "       Failed migrations: $failureCount" -ForegroundColor Red
            }
            finally {
                $ConfirmPreference = $oldConfirm
                $WhatIfPreference = $oldWhatIf
            }

            return
        }

        '11' {
            Write-Host ""
            Write-Host "Thank you for using GitLab → Azure DevOps Migration Tool" -ForegroundColor Cyan
            Write-Host "Goodbye! 👋" -ForegroundColor Green
            Write-Host ""
            return
        }
        '12' {
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
        '13' {
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
        '14' {
            Write-Host ""
            Write-Host "Thank you for using GitLab → Azure DevOps Migration Tool" -ForegroundColor Cyan
            Write-Host "Goodbye! 👋" -ForegroundColor Green
            Write-Host ""
            return
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Invalid choice. Please select a number between 1 and 14." -ForegroundColor Red
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
