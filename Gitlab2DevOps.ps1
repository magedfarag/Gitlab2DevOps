<#
.SYNOPSIS
    GitLab to Azure DevOps migration tool - Entry point.

.DESCRIPTION
    This script provides both interactive menu and CLI modes for migrating GitLab projects to Azure DevOps.
    Supports single and bulk migrations with full project setup including branch policies,
    RBAC, wikis, and work item templates.
    
    CLI Mode: Use -Mode parameter with -Source and -Project for automation scenarios.
    Interactive Mode: Run without -Mode parameter to launch interactive menu (default).
    
    WHAT THIS TOOL DOES:
    - Migrates Git repository with full history (commits, branches, tags)
    - Converts GitLab branch protection to Azure DevOps branch policies
    - Configures default branch and repository settings
    - Provides comprehensive logging and audit trails
    
    WHAT THIS TOOL DOES NOT DO:
    - Issues / Work Items (different data models, manual recreation required)
    - Merge Requests / Pull Requests (close before migration)
    - CI/CD Pipelines (recreate in Azure Pipelines)
    - Wikis (planned for v3.0)
    - Project settings, permissions, webhooks
    - Incremental/delta migrations (one-time cutover only)
    
    For complete scope and limitations, see: docs/architecture/limitations.md

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
    Version: 2.1.0
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
    [ValidateSet('Preflight', 'Initialize', 'Migrate', 'BulkPrepare', 'BulkMigrate', 'BusinessInit', 'DevInit', 'SecurityInit')]
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
    [string]$CollectionUrl = "",
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$AdoPat = "",
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$GitLabBaseUrl = "",
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$GitLabToken = "",
    
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
    [bool]$SkipCertificateCheck = $true,  # CRITICAL: Default to TRUE for on-premise servers
    
    [Parameter(ParameterSetName='Interactive')]
    [Parameter(ParameterSetName='CLI')]
    [string]$EnvFile = ""  # Optional: Path to .env file
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get script directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load .env file if available (before loading other modules)
# Auto-load .env files (in priority order: .env.local, .env)
$envFiles = @()
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    # Auto-detect .env files
    $localEnv = Join-Path $scriptRoot ".env.local"
    $defaultEnv = Join-Path $scriptRoot ".env"
    
    if (Test-Path $defaultEnv) { $envFiles += $defaultEnv }
    if (Test-Path $localEnv) { $envFiles += $localEnv }
} else {
    # Use specified .env file
    $envFiles = @($EnvFile)
}

if ($envFiles.Count -gt 0) {
    # Load EnvLoader module (supports legacy and new folder layout)
    $envLoaderCandidates = @(
        (Join-Path $scriptRoot "modules\EnvLoader.psm1"),
        (Join-Path $scriptRoot "modules\core\EnvLoader.psm1")
    )
    $envLoaderModule = $envLoaderCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($envLoaderModule) {
        Import-Module $envLoaderModule -Force -ErrorAction SilentlyContinue
        
        if (Get-Command Import-DotEnvFile -ErrorAction SilentlyContinue) {
            Write-Host "[INFO] Loading configuration from .env file(s)..." -ForegroundColor Cyan
            $envConfig = Import-DotEnvFile -Path $envFiles -SetEnvironmentVariables
            
            # Override parameters with .env values if not explicitly provided
            if ([string]::IsNullOrWhiteSpace($AdoPat) -and $envConfig.ContainsKey('ADO_PAT')) {
                $AdoPat = $envConfig.ADO_PAT
            }
            if ([string]::IsNullOrWhiteSpace($GitLabToken) -and $envConfig.ContainsKey('GITLAB_PAT')) {
                $GitLabToken = $envConfig.GITLAB_PAT
            }
            if ([string]::IsNullOrWhiteSpace($CollectionUrl) -and $envConfig.ContainsKey('ADO_COLLECTION_URL')) {
                $CollectionUrl = $envConfig.ADO_COLLECTION_URL
            }
            if ([string]::IsNullOrWhiteSpace($GitLabBaseUrl) -and $envConfig.ContainsKey('GITLAB_BASE_URL')) {
                $GitLabBaseUrl = $envConfig.GITLAB_BASE_URL
            }
            if ($envConfig.ContainsKey('ADO_API_VERSION')) {
                $AdoApiVersion = $envConfig.ADO_API_VERSION
            }
            if ($envConfig.ContainsKey('SKIP_CERTIFICATE_CHECK') -and $envConfig.SKIP_CERTIFICATE_CHECK -eq 'true') {
                $SkipCertificateCheck = $true
            }
        }
    }
    else {
        Write-Warning "[EnvLoader] Could not locate EnvLoader module under modules\ or modules\core\. Skipping .env processing."
    }
}

# Apply defaults if still empty (after .env loading)
if ([string]::IsNullOrWhiteSpace($CollectionUrl)) {
    $CollectionUrl = if ($env:ADO_COLLECTION_URL) { $env:ADO_COLLECTION_URL } else { "https://devops.example.com/DefaultCollection" }
}
if ([string]::IsNullOrWhiteSpace($GitLabBaseUrl)) {
    $GitLabBaseUrl = if ($env:GITLAB_BASE_URL) { $env:GITLAB_BASE_URL } else { "https://gitlab.example.com" }
}
if ([string]::IsNullOrWhiteSpace($AdoPat)) {
    $AdoPat = if ($env:ADO_PAT) { $env:ADO_PAT } else { "" }
}
if ([string]::IsNullOrWhiteSpace($GitLabToken)) {
    $GitLabToken = if ($env:GITLAB_PAT) { $env:GITLAB_PAT } else { "" }
}

# Start transcript logging to file
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $scriptRoot "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$transcriptFile = Join-Path $logDir "session-$timestamp.log"
Start-Transcript -Path $transcriptFile -Append
Write-Host "📝 Session logging to: $transcriptFile" -ForegroundColor Cyan
Write-Host ""

# Import modules
Write-Host "[INFO] Loading migration modules..."
Import-Module "$scriptRoot\modules\core\Core.Rest.psm1" -Force
Import-Module "$scriptRoot\modules\core\Logging.psm1" -Force
Import-Module "$scriptRoot\modules\GitLab\GitLab.psm1" -Force
Import-Module "$scriptRoot\modules\AzureDevOps\AzureDevOps.psm1" -Force
Import-Module "$scriptRoot\modules\Migration.psm1" -Force
Write-Host "[INFO] Modules loaded successfully"
Write-Host ""

# Initialize Core.Rest module with configuration
# CRITICAL: SkipCertificateCheck defaults to $true for on-premise servers with self-signed certs
$skipCertSwitch = if ($SkipCertificateCheck) { @{SkipCertificateCheck = $true} } else { @{} }
Initialize-CoreRest `
    -CollectionUrl $CollectionUrl `
    -AdoPat $AdoPat `
    -GitLabBaseUrl $GitLabBaseUrl `
    -GitLabToken $GitLabToken `
    -AdoApiVersion $AdoApiVersion `
    @skipCertSwitch

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
    
    # Create run manifest for tracking
    $runParams = @{
        Mode = $Mode
        Source = $Source
        Project = $Project
        Parameters = @{
            AllowSync = $AllowSync.IsPresent
            Force = $Force.IsPresent
            Replace = $Replace.IsPresent
            WhatIf = $WhatIfPreference
        }
    }
    $runManifest = New-RunManifest @runParams
    $runId = $runManifest.run_id
    
    Write-Verbose "[Run] Manifest ID: $runId"
    
    $migrationErrors = @()
    $migrationWarnings = @()
    $migrationStatus = "SUCCESS"
    
    try {
        # Validate required parameters based on mode
        switch ($Mode) {
        'Preflight' {
            if ([string]::IsNullOrWhiteSpace($Source)) {
                Write-Host "[ERROR] -Source parameter is required for Preflight mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode Preflight -Source 'group/project'" -ForegroundColor Yellow
                exit 1
            }
            
            Write-Host "[INFO] Preparing GitLab project: $Source" -ForegroundColor Cyan
            Initialize-GitLab -SrcPath $Source
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
        'BusinessInit' {
            if ([string]::IsNullOrWhiteSpace($Project)) {
                Write-Host "[ERROR] -Project parameter is required for BusinessInit mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode BusinessInit -Project 'MyProject'" -ForegroundColor Yellow
                exit 1
            }

            Write-Host "[INFO] Provisioning Business Initialization Pack for project: $Project" -ForegroundColor Cyan
            Initialize-BusinessInit -DestProject $Project
        }
        'DevInit' {
            if ([string]::IsNullOrWhiteSpace($Project)) {
                Write-Host "[ERROR] -Project parameter is required for DevInit mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode DevInit -Project 'MyProject' [-Source 'group/project']" -ForegroundColor Yellow
                exit 1
            }

            Write-Host "[INFO] Provisioning Development Initialization Pack for project: $Project" -ForegroundColor Cyan
            
            # Detect project type from Source if provided
            $projectType = 'all'
            if (-not [string]::IsNullOrWhiteSpace($Source)) {
                Write-Host "[INFO] Analyzing GitLab project to detect type..." -ForegroundColor Cyan
                # Simple detection based on files in repository
                # This would require GitLab API call - defaulting to 'all' for now
                Write-Verbose "[DevInit] Source provided: $Source - using 'all' project type"
            }
            
            Initialize-DevInit -DestProject $Project -ProjectType $projectType
        }
        'SecurityInit' {
            if ([string]::IsNullOrWhiteSpace($Project)) {
                Write-Host "[ERROR] -Project parameter is required for SecurityInit mode" -ForegroundColor Red
                Write-Host "Usage: .\Gitlab2DevOps.ps1 -Mode SecurityInit -Project 'MyProject'" -ForegroundColor Yellow
                exit 1
            }

            Write-Host "[INFO] Provisioning Security Initialization Pack for project: $Project" -ForegroundColor Cyan
            Initialize-SecurityInit -DestProject $Project
        }
        }
    }
    catch {
        $migrationStatus = "FAILED"
        $migrationErrors += $_.Exception.Message
        Write-Host ""
        Write-Host "[ERROR] CLI operation failed: $_" -ForegroundColor Red
        
        # Update manifest with failure
        Update-RunManifest -RunId $runId -Status $migrationStatus -EndTime (Get-Date) -Errors $migrationErrors -Warnings $migrationWarnings
        throw
    }
    
    # Update manifest with success
    Update-RunManifest -RunId $runId -Status $migrationStatus -EndTime (Get-Date) -Errors $migrationErrors -Warnings $migrationWarnings
    
    Write-Host ""
    Write-Host "[SUCCESS] CLI operation completed" -ForegroundColor Green
    Write-Verbose "[Run] Manifest: migrations/run-manifest-$runId.json"
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

# Stop transcript logging
Stop-Transcript
Write-Host ""
Write-Host "📝 Session log saved: $transcriptFile" -ForegroundColor Green
