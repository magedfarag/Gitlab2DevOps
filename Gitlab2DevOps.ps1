<#
.SYNOPSIS
    GitLab to Azure DevOps migration tool - Entry point.

.DESCRIPTION
    This script provides both interactive menu and CLI modes for migrating GitLab projects to Azure DevOps.
    Supports single and bulk migrations with full project setup including branch policies,
    RBAC, wikis, and work item templates.
    
    CLI Mode: Use -Mode parameter with -Source and -Project for automation scenarios.
    Interactive Mode: Run without -Mode parameter to launch interactive menu (default).

.PARAMETER Mode
    CLI operation mode (CLI parameter set only):
    - Preflight: Download and analyze single GitLab project
    - Initialize: Create and setup Azure DevOps project with policies
    - Migrate: Migrate single GitLab project to Azure DevOps
    - BulkPrepare: Download and analyze multiple GitLab projects
    - BulkMigrate: Execute bulk migration from prepared template

.PARAMETER Source
    Source GitLab project path (e.g., "group/my-project"). Required for Preflight, Initialize, and Migrate modes.

.PARAMETER Project
    Destination Azure DevOps project name (e.g., "MyProject"). Required for Initialize and Migrate modes.

.PARAMETER AllowSync
    Allow sync of existing repository during migration. Use with Migrate mode.

.PARAMETER Force
    Override preflight checks and blocking issues. Use with Migrate mode.

.PARAMETER Replace
    Delete and recreate existing repository with commits. Use with Migrate mode.

.PARAMETER CollectionUrl
    Azure DevOps collection URL (default: $env:ADO_COLLECTION_URL or "https://devops.example.com/DefaultCollection").

.PARAMETER AdoPat
    Azure DevOps Personal Access Token (default: $env:ADO_PAT).

.PARAMETER GitLabBaseUrl
    GitLab instance base URL (default: $env:GITLAB_BASE_URL or "https://gitlab.example.com").

.PARAMETER GitLabToken
    GitLab Personal Access Token (default: $env:GITLAB_PAT).

.PARAMETER AdoApiVersion
    Azure DevOps REST API version (default: "7.1").

.PARAMETER BuildDefinitionId
    Optional build definition ID for branch policy validation.

.PARAMETER SonarStatusContext
    Optional SonarQube status context for branch policy.

.PARAMETER SkipCertificateCheck
    Skip TLS certificate validation (not recommended for production).

.EXAMPLE
    .\Gitlab2DevOps.ps1
    
    Launches interactive menu with default settings from environment variables.

.EXAMPLE
    .\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/app" -Project "MyApp"
    
    CLI mode: Migrate GitLab project to Azure DevOps.

.EXAMPLE
    .\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/app" -Project "MyApp" -Force -Replace
    
    CLI mode: Force migration with repository replacement.

.EXAMPLE
    .\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/app"
    
    CLI mode: Download and analyze GitLab project (preflight check).

.EXAMPLE
    .\Gitlab2DevOps.ps1 -Mode Initialize -Source "group/app" -Project "MyApp"
    
    CLI mode: Create Azure DevOps project with branch policies.

.EXAMPLE
    .\Gitlab2DevOps.ps1 -Mode BulkPrepare
    
    CLI mode: Bulk preparation workflow (interactive prompts for project list).

.EXAMPLE
    .\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/app" -Project "MyApp" -WhatIf
    
    Preview migration without executing changes.

.NOTES
    Author: Migration Team
    Version: 2.0.0
    Requires: PowerShell 5.1+, Git, Azure DevOps PAT, GitLab PAT
    
    Environment Variables (recommended):
    - ADO_COLLECTION_URL: Azure DevOps organization URL
    - ADO_PAT: Azure DevOps Personal Access Token
    - GITLAB_BASE_URL: GitLab instance URL
    - GITLAB_PAT: GitLab Personal Access Token
    
    Parameter Sets:
    - Interactive (default): No -Mode parameter, launches interactive menu
    - CLI: Use -Mode parameter with required parameters for automation
#>

#Requires -Version 5.1
[CmdletBinding(DefaultParameterSetName='Interactive', SupportsShouldProcess)]
param(
    # CLI Mode Parameters
    [Parameter(ParameterSetName='CLI', Mandatory)]
    [ValidateSet('Preflight', 'Initialize', 'Migrate', 'BulkPrepare', 'BulkMigrate')]
    [string]$Mode,
    
    [Parameter(ParameterSetName='CLI')]
    [string]$Source,
    
    [Parameter(ParameterSetName='CLI')]
    [string]$Project,
    
    [Parameter(ParameterSetName='CLI')]
    [switch]$AllowSync,
    
    [Parameter(ParameterSetName='CLI')]
    [switch]$Force,
    
    [Parameter(ParameterSetName='CLI')]
    [switch]$Replace,
    
    # Common Parameters (both parameter sets)
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$CollectionUrl = ($env:ADO_COLLECTION_URL -or "https://devops.example.com/DefaultCollection"),
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$AdoPat = ($env:ADO_PAT -or ""),
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$GitLabBaseUrl = ($env:GITLAB_BASE_URL -or "https://gitlab.example.com"),
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$GitLabToken = ($env:GITLAB_PAT -or ""),
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$AdoApiVersion = "7.1",
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [int]$BuildDefinitionId = 0,
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$SonarStatusContext = "",
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [switch]$SkipCertificateCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get script directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
Write-Host "[INFO] Loading migration modules..."
Import-Module "$scriptRoot\modules\Core.Rest.psm1" -Force
Import-Module "$scriptRoot\modules\Logging.psm1" -Force
Import-Module "$scriptRoot\modules\GitLab.psm1" -Force
Import-Module "$scriptRoot\modules\AzureDevOps.psm1" -Force
Import-Module "$scriptRoot\modules\Migration.psm1" -Force
Write-Host "[INFO] Modules loaded successfully"
Write-Host ""

# Initialize Core.Rest module with configuration
Initialize-CoreRest `
    -CollectionUrl $CollectionUrl `
    -AdoPat $AdoPat `
    -GitLabBaseUrl $GitLabBaseUrl `
    -GitLabToken $GitLabToken `
    -AdoApiVersion $AdoApiVersion `
    -SkipCertificateCheck:$SkipCertificateCheck

# Display configuration
Write-Host "[INFO] Configuration loaded successfully"
Write-Host "       Azure DevOps: $CollectionUrl (API v$AdoApiVersion)"
Write-Host "       GitLab: $GitLabBaseUrl"
if ($SkipCertificateCheck) {
    Write-Host "       SSL Certificate Check: DISABLED (not recommended for production)" -ForegroundColor Yellow
}
Write-Host ""

# Determine mode: CLI or Interactive
if ($PSCmdlet.ParameterSetName -eq 'CLI') {
    Write-Host "[INFO] Running in CLI mode: $Mode" -ForegroundColor Cyan
    Write-Host ""
    
    # Validate required parameters based on mode
    switch ($Mode) {
        'Preflight' {
            if ([string]::IsNullOrWhiteSpace($Source)) {
                Write-Host "[ERROR] -Source parameter is required for Preflight mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode Preflight -Source 'group/project'" -ForegroundColor Yellow
                exit 1
            }
            
            Write-Host "[INFO] Preparing GitLab project: $Source" -ForegroundColor Cyan
            Prepare-GitLab -SrcPath $Source
        }
        
        'Initialize' {
            if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Project)) {
                Write-Host "[ERROR] -Source and -Project parameters are required for Initialize mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode Initialize -Source 'group/project' -Project 'MyProject'" -ForegroundColor Yellow
                exit 1
            }
            
            $repoName = ($Source -split '/')[-1]
            Write-Host "[INFO] Initializing Azure DevOps project: $Project (Repository: $repoName)" -ForegroundColor Cyan
            Initialize-AdoProject `
                -DestProject $Project `
                -RepoName $repoName `
                -BuildDefinitionId $BuildDefinitionId `
                -SonarStatusContext $SonarStatusContext
        }
        
        'Migrate' {
            if ([string]::IsNullOrWhiteSpace($Source) -or [string]::IsNullOrWhiteSpace($Project)) {
                Write-Host "[ERROR] -Source and -Project parameters are required for Migrate mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode Migrate -Source 'group/project' -Project 'MyProject'" -ForegroundColor Yellow
                exit 1
            }
            
            Write-Host "[INFO] Migrating $Source → $Project" -ForegroundColor Cyan
            if ($AllowSync) {
                Write-Host "[INFO] Sync mode enabled - will update existing repository if it exists" -ForegroundColor Yellow
            }
            if ($Force) {
                Write-Host "[WARN] Force mode enabled - bypassing preflight checks and blocking issues" -ForegroundColor Yellow
            }
            if ($Replace) {
                Write-Host "[WARN] Replace mode enabled - existing repository will be deleted and recreated" -ForegroundColor Yellow
            }
            
            $migrateParams = @{
                SrcPath = $Source
                DestProject = $Project
            }
            if ($AllowSync) { $migrateParams['AllowSync'] = $true }
            if ($Force) { $migrateParams['Force'] = $true }
            if ($Replace) { $migrateParams['Replace'] = $true }
            if ($WhatIfPreference) { $migrateParams['WhatIf'] = $true }
            if ($ConfirmPreference -ne 'None') { $migrateParams['Confirm'] = $true }
            
            Invoke-SingleMigration @migrateParams
        }
        
        'BulkPrepare' {
            Write-Host "[INFO] Starting bulk preparation workflow" -ForegroundColor Cyan
            Invoke-BulkPreparationWorkflow
        }
        
        'BulkMigrate' {
            Write-Host "[INFO] Starting bulk migration workflow" -ForegroundColor Cyan
            Invoke-BulkMigrationWorkflow
        }
    }
    
    Write-Host ""
    Write-Host "[INFO] CLI operation completed" -ForegroundColor Green
}
else {
    # Interactive mode - launch menu
    Write-Host "[INFO] Launching interactive menu..." -ForegroundColor Cyan
    Write-Host ""
    Show-MigrationMenu `
        -CollectionUrl $CollectionUrl `
        -AdoPat $AdoPat `
        -GitLabBaseUrl $GitLabBaseUrl `
        -GitLabToken $GitLabToken `
        -BuildDefinitionId $BuildDefinitionId `
        -SonarStatusContext $SonarStatusContext
}
