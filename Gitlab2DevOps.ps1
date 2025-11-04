<#
.SYNOPSIS
    GitLab to Azure DevOps migration tool - Entry point.

.DESCRIPTION
    This script provides an interactive menu for migrating GitLab projects to Azure DevOps.
    Supports single and bulk migrations with full project setup including branch policies,
    RBAC, wikis, and work item templates.

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
    .\Gitlab2DevOps.ps1 -SkipCertificateCheck
    
    Launches with TLS validation disabled (for on-premises with private CAs).

.NOTES
    Author: Migration Team
    Version: 2.0.0
    Requires: PowerShell 5.1+, Git, Azure DevOps PAT, GitLab PAT
    
    Environment Variables (recommended):
    - ADO_COLLECTION_URL: Azure DevOps organization URL
    - ADO_PAT: Azure DevOps Personal Access Token
    - GITLAB_BASE_URL: GitLab instance URL
    - GITLAB_PAT: GitLab Personal Access Token
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$CollectionUrl = ($env:ADO_COLLECTION_URL -or "https://devops.example.com/DefaultCollection"),
    [string]$AdoPat = ($env:ADO_PAT -or ""),
    [string]$GitLabBaseUrl = ($env:GITLAB_BASE_URL -or "https://gitlab.example.com"),
    [string]$GitLabToken = ($env:GITLAB_PAT -or ""),
    [string]$AdoApiVersion = "7.1",
    [int]$BuildDefinitionId = 0,
    [string]$SonarStatusContext = "",
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

# Launch interactive menu
Show-MigrationMenu `
    -CollectionUrl $CollectionUrl `
    -AdoPat $AdoPat `
    -GitLabBaseUrl $GitLabBaseUrl `
    -GitLabToken $GitLabToken `
    -BuildDefinitionId $BuildDefinitionId `
    -SonarStatusContext $SonarStatusContext
