<#
.SYNOPSIS
    Migration menu system and main orchestration.

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
Import-Module (Join-Path $migrationRoot "Core\Core.psm1") -Force -Global

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
    $script:GitLabBaseUrl = $GitLabBaseUrl
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
    Write-Host "  5) Export User Information  " -ForegroundColor White -NoNewline
    Write-Host "│ Export GitLab users/groups to JSON" -ForegroundColor Gray
    Write-Host "  6) Import User Information  " -ForegroundColor White -NoNewline
    Write-Host "│ Import JSON data to Azure DevOps" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  7) Exit" -ForegroundColor Yellow
    Write-Host ""
    
    $choice = Read-Host "Select option (1-7)"
    
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
                    # Single project migration
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
                    # Bulk migration
                    Invoke-BulkMigrationWorkflow
                }
                default {
                    Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
                }
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
                default { 'Standard' }
            }
            
            Write-Host "[INFO] Starting export with profile: $profile" -ForegroundColor Green
            
            try {
                # Call the export script - navigate from module location to project root
                # From modules/Migration/Menu/ go up 3 levels to get to project root
                $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
                $exportScript = Join-Path $projectRoot "examples\export-gitlab-identity.ps1"
                
                if (-not (Test-Path $exportScript)) {
                    throw "Export script not found at: $exportScript"
                }
                
                & $exportScript -GitLabBaseUrl $script:GitLabBaseUrl -GitLabToken $script:GitLabToken -OutDirectory $exportDir -Profile $profile
                
                Write-Host ""
                Write-Host "[SUCCESS] Export completed! Files saved to: $exportDir" -ForegroundColor Green
                Write-Host "[INFO] You can now use Option 6 to import this data into Azure DevOps" -ForegroundColor Cyan
            }
            catch {
                Write-Host "[ERROR] Export failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        '6' {
            # Import User Information
            Write-Host ""
            Write-Host "=== IMPORT USER INFORMATION ===" -ForegroundColor Cyan
            Write-Host "Import previously exported GitLab identity data into Azure DevOps Server."
            Write-Host ""
            
            $importDir = Read-Host "Enter directory containing exported JSON files (press Enter for 'exports')"
            if ([string]::IsNullOrWhiteSpace($importDir)) {
                $importDir = "exports"
            }
            
            # Verify the directory exists and has required files
            if (-not (Test-Path $importDir)) {
                Write-Host "[ERROR] Import directory not found: $importDir" -ForegroundColor Red
                Write-Host "[INFO] Use Option 5 to export GitLab data first" -ForegroundColor Yellow
                return
            }
            
            $usersFile = Join-Path $importDir "users.json"
            $groupsFile = Join-Path $importDir "groups.json"
            
            if (-not (Test-Path $usersFile) -or -not (Test-Path $groupsFile)) {
                Write-Host "[ERROR] Required files not found in $importDir" -ForegroundColor Red
                Write-Host "Expected files: users.json, groups.json" -ForegroundColor Yellow
                return
            }
            
            Write-Host "[INFO] Found export files in: $importDir" -ForegroundColor Green
            Write-Host ""
            Write-Host "Import Options:" -ForegroundColor Cyan
            Write-Host "  1) Dry Run    - Preview what would be imported (recommended first)" -ForegroundColor Yellow
            Write-Host "  2) Execute    - Perform actual import to Azure DevOps" -ForegroundColor White
            Write-Host ""
            
            $importChoice = Read-Host "Select import mode (1-2)"
            $dryRun = ($importChoice -eq '1')
            
            Write-Host "[INFO] Starting import in $(if ($dryRun) { 'DRY RUN' } else { 'EXECUTE' }) mode..." -ForegroundColor Green
            
            try {
                # Call the import script - navigate from module location to project root
                # From modules/Migration/Menu/ go up 3 levels to get to project root
                $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
                $importScript = Join-Path $projectRoot "Import-GitLabIdentityToAdo.ps1"
                
                if (-not (Test-Path $importScript)) {
                    throw "Import script not found at: $importScript"
                }
                
                if ($dryRun) {
                    & $importScript -CollectionUrl $script:CollectionUrl -AdoPat $script:AdoPat -ExportFolder $importDir -WhatIf
                }
                else {
                    & $importScript -CollectionUrl $script:CollectionUrl -AdoPat $script:AdoPat -ExportFolder $importDir
                }
                
                Write-Host ""
                Write-Host "[SUCCESS] Import completed!" -ForegroundColor Green
                if ($dryRun) {
                    Write-Host "[INFO] This was a dry run. Use Execute mode to perform actual import." -ForegroundColor Cyan
                }
            }
            catch {
                Write-Host "[ERROR] Import failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        '7' {
            Write-Host ""
            Write-Host "Thank you for using GitLab → Azure DevOps Migration Tool" -ForegroundColor Cyan
            Write-Host "Goodbye! 👋" -ForegroundColor Green
            Write-Host ""
            return
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Invalid choice. Please select a number between 1 and 7." -ForegroundColor Red
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

# Export public functions
Export-ModuleMember -Function @(
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu'
)
