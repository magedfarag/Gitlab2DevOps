<#
.SYNOPSIS
    Menu and interactive UI functions for GitLab to Azure DevOps migration.

.DESCRIPTION
    This module handles the interactive menu system and user interface
    components for migration operations. Separated from Migration.psm1 
    to improve maintainability and modularity.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest, GitLab, AzureDevOps, Logging modules
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Displays the interactive migration menu.

.DESCRIPTION
    Main entry point for interactive operations. Provides 5 options:
    1) Prepare single project
    2) Prepare bulk projects
    3) Create Azure DevOps project
    4) Execute planned migration
    5) Exit

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
            Write-Host "═══ Single Project Preparation ═══" -ForegroundColor Cyan
            
            # Get prepared projects first for context
            $prepared = Get-PreparedProjects
            if ($prepared.Count -gt 0) {
                Write-Host ""
                Write-Host "Existing preparations:" -ForegroundColor Yellow
                $prepared | Where-Object { $_.Type -eq 'SINGLE' } | ForEach-Object {
                    $statusColor = switch ($_.Status) {
                        'PREPARED' { 'Green' }
                        'MIGRATED' { 'Cyan' }
                        'COMPLETED' { 'Magenta' }
                        'FAILED' { 'Red' }
                        default { 'Gray' }
                    }
                    $structureInfo = if ($_.Structure -eq 'Legacy') { " (Legacy)" } else { "" }
                    Write-Host "  • $($_.ProjectName) → $($_.AdoProject)$structureInfo" -ForegroundColor $statusColor
                }
                Write-Host ""
            }
            
            $srcPath = Read-Host "GitLab project path (org/project)"
            if ([string]::IsNullOrWhiteSpace($srcPath)) {
                Write-Host "[ERROR] Project path is required" -ForegroundColor Red
                return
            }
            
            $destProject = Read-Host "Azure DevOps project name"
            if ([string]::IsNullOrWhiteSpace($destProject)) {
                Write-Host "[ERROR] Azure DevOps project name is required" -ForegroundColor Red
                return
            }
            
            $repoName = Read-Host "Repository name (default: auto-generated)"
            
            try {
                # Import required modules
                Import-Module (Join-Path $PSScriptRoot "Core.Rest.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "GitLab.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force
                
                # Initialize connections
                Initialize-CoreRest -CollectionUrl $CollectionUrl -AdoPat $AdoPat
                Initialize-GitLab -BaseUrl $GitLabBaseUrl -Token $GitLabToken
                
                New-MigrationPreReport -GitLabPath $srcPath -AdoProject $destProject -AdoRepoName $repoName
                Write-Host "[SUCCESS] Preparation completed! Use option 4 to execute migration." -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Preparation failed: $_" -ForegroundColor Red
            }
        }
        '2' {
            Write-Host ""
            Write-Host "═══ Bulk Project Preparation ═══" -ForegroundColor Cyan
            
            try {
                # Import required modules
                Import-Module (Join-Path $PSScriptRoot "Migration.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Core.Rest.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "GitLab.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force
                
                # Initialize connections
                Initialize-CoreRest -CollectionUrl $CollectionUrl -AdoPat $AdoPat
                Initialize-GitLab -BaseUrl $GitLabBaseUrl -Token $GitLabToken
                
                Invoke-BulkPreparationWorkflow
                Write-Host "[SUCCESS] Bulk preparation completed! Use option 4 to execute migration." -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Bulk preparation failed: $_" -ForegroundColor Red
            }
        }
        '3' {
            Write-Host ""
            Write-Host "═══ Azure DevOps Project Creation ═══" -ForegroundColor Cyan
            
            $projectName = Read-Host "Azure DevOps project name"
            if ([string]::IsNullOrWhiteSpace($projectName)) {
                Write-Host "[ERROR] Project name is required" -ForegroundColor Red
                return
            }
            
            $repoName = Read-Host "Initial repository name"
            if ([string]::IsNullOrWhiteSpace($repoName)) {
                Write-Host "[ERROR] Repository name is required" -ForegroundColor Red
                return
            }
            
            try {
                # Import required modules
                Import-Module (Join-Path $PSScriptRoot "Initialization.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Core.Rest.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "AzureDevOps.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force
                
                # Initialize connections
                Initialize-CoreRest -CollectionUrl $CollectionUrl -AdoPat $AdoPat
                
                Initialize-AdoProject -DestProject $projectName -RepoName $repoName -BuildDefinitionId $BuildDefinitionId -SonarStatusContext $SonarStatusContext
                
                # Prompt for team packs after successful creation
                Invoke-TeamPackMenu -ProjectName $projectName
                
                Write-Host "[SUCCESS] Project creation completed!" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Project creation failed: $_" -ForegroundColor Red
            }
        }
        '4' {
            Write-Host ""
            Write-Host "═══ Execute Planned Migration ═══" -ForegroundColor Cyan
            
            # Get prepared projects
            $prepared = Get-PreparedProjects
            if ($prepared.Count -eq 0) {
                Write-Host "[WARN] No prepared projects found. Use option 1 or 2 to prepare projects first." -ForegroundColor Yellow
                return
            }
            
            # Display prepared projects
            Write-Host ""
            Write-Host "Prepared projects:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $prepared.Count; $i++) {
                $project = $prepared[$i]
                $statusColor = switch ($project.Status) {
                    'PREPARED' { 'Green' }
                    'MIGRATED' { 'Cyan' }
                    'COMPLETED' { 'Magenta' }
                    'FAILED' { 'Red' }
                    default { 'Gray' }
                }
                $structureInfo = if ($project.Structure -eq 'Legacy') { " (Legacy)" } else { "" }
                Write-Host "  $($i + 1)) $($project.ProjectName) → $($project.AdoProject) [$($project.Type)]$structureInfo" -ForegroundColor $statusColor
            }
            Write-Host ""
            
            $selection = Read-Host "Select project to migrate (number)"
            if ([string]::IsNullOrWhiteSpace($selection)) {
                Write-Host "[INFO] Operation cancelled" -ForegroundColor Gray
                return
            }
            
            try {
                $index = [int]$selection - 1
                if ($index -lt 0 -or $index -ge $prepared.Count) {
                    Write-Host "[ERROR] Invalid selection" -ForegroundColor Red
                    return
                }
                
                $selectedProject = $prepared[$index]
                
                # Import required modules
                Import-Module (Join-Path $PSScriptRoot "Workflows.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Core.Rest.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "GitLab.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "AzureDevOps.psm1") -Force
                Import-Module (Join-Path $PSScriptRoot "Logging.psm1") -Force
                
                # Initialize connections
                Initialize-CoreRest -CollectionUrl $CollectionUrl -AdoPat $AdoPat
                Initialize-GitLab -BaseUrl $GitLabBaseUrl -Token $GitLabToken
                
                if ($selectedProject.Type -eq 'SINGLE') {
                    Invoke-SingleMigration -SrcPath $selectedProject.ProjectName -DestProject $selectedProject.AdoProject
                } elseif ($selectedProject.Type -eq 'BULK') {
                    Invoke-BulkMigrationWorkflow
                }
                
                Write-Host "[SUCCESS] Migration completed!" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Migration failed: $_" -ForegroundColor Red
            }
        }
        '5' {
            Write-Host ""
            Write-Host "Goodbye! 👋" -ForegroundColor Cyan
            return
        }
        default {
            Write-Host ""
            Write-Host "[ERROR] Invalid selection. Please choose 1-5." -ForegroundColor Red
            Show-MigrationMenu -CollectionUrl $CollectionUrl -AdoPat $AdoPat -GitLabBaseUrl $GitLabBaseUrl -GitLabToken $GitLabToken -BuildDefinitionId $BuildDefinitionId -SonarStatusContext $SonarStatusContext
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
        $packChoice = "6"
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
            try {
                Write-Host ""
                Write-Host "[INFO] Provisioning Development Team Pack..." -ForegroundColor Cyan
                Initialize-DevInit -DestProject $ProjectName -ProjectType 'all'
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

Export-ModuleMember -Function @(
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu'
)