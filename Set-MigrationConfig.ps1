<#
.SYNOPSIS
    Switch between Azure DevOps project configuration profiles

.DESCRIPTION
    Quickly switch between different project settings and branch policy configurations
    for Azure DevOps project initialization during migration.
    
    Automatically backs up current configurations before applying new ones.

.PARAMETER ProjectProfile
    Project settings profile to activate:
    - Default: Balanced setup (4 areas, 6 sprints, Agile)
    - Mobile: iOS/Android focused (4 areas, 8 sprints, Scrum)
    - Enterprise: Large organization (8 areas, 12 sprints, Agile)
    - SmallTeam: Minimal overhead (3 areas, 4 sprints, Agile)

.PARAMETER PolicyProfile
    Branch policies profile to activate:
    - Default: Standard protection (1 reviewer, work items required)
    - Strict: Enterprise-grade (3 reviewers, build validation, SonarQube)
    - Relaxed: Small team flexibility (1 reviewer optional, no builds)
    - None: Development/testing only (all policies disabled)

.PARAMETER ShowCurrent
    Display current active configurations without making changes

.PARAMETER ListProfiles
    List all available configuration profiles with descriptions

.EXAMPLE
    .\Set-MigrationConfig.ps1 -ProjectProfile Mobile -PolicyProfile Relaxed
    
    Switches to mobile project settings with relaxed branch policies.

.EXAMPLE
    .\Set-MigrationConfig.ps1 -ShowCurrent
    
    Displays current active configurations.

.EXAMPLE
    .\Set-MigrationConfig.ps1 -ListProfiles
    
    Lists all available configuration profiles.

.NOTES
    Author: Gitlab2DevOps Project
    Version: 1.0.0
    Last Updated: 2025-11-08
#>

[CmdletBinding(DefaultParameterSetName='Switch')]
param(
    [Parameter(ParameterSetName='Switch', Mandatory=$true)]
    [ValidateSet('Default', 'Mobile', 'Enterprise', 'SmallTeam')]
    [string]$ProjectProfile,
    
    [Parameter(ParameterSetName='Switch', Mandatory=$true)]
    [ValidateSet('Default', 'Strict', 'Relaxed', 'None')]
    [string]$PolicyProfile,
    
    [Parameter(ParameterSetName='ShowCurrent')]
    [switch]$ShowCurrent,
    
    [Parameter(ParameterSetName='ListProfiles')]
    [switch]$ListProfiles
)

$ErrorActionPreference = 'Stop'

# Paths
$configPath = Join-Path $PSScriptRoot "modules\AzureDevOps\config"
$examplesPath = Join-Path $PSScriptRoot "examples"

# Profile definitions
$projectProfiles = @{
    'Default' = @{
        File = "project-settings.json"
        Location = $configPath
        Description = "Balanced setup for most teams (4 areas, 6 sprints, Agile)"
        Areas = 4
        Sprints = 6
        Duration = "14 days"
        Template = "Agile"
    }
    'Mobile' = @{
        File = "mobile-project-settings.json"
        Location = $examplesPath
        Description = "iOS/Android focused (4 areas, 8 sprints, Scrum)"
        Areas = 4
        Sprints = 8
        Duration = "10 days"
        Template = "Scrum"
    }
    'Enterprise' = @{
        File = "enterprise-project-settings.json"
        Location = $examplesPath
        Description = "Large organization structure (8 areas, 12 sprints, Agile)"
        Areas = 8
        Sprints = 12
        Duration = "14 days"
        Template = "Agile"
    }
    'SmallTeam' = @{
        File = "small-team-project-settings.json"
        Location = $examplesPath
        Description = "Minimal overhead (3 areas, 4 sprints, Agile)"
        Areas = 3
        Sprints = 4
        Duration = "7 days"
        Template = "Agile"
    }
}

$policyProfiles = @{
    'Default' = @{
        File = "branch-policies.json"
        Location = $configPath
        Description = "Standard protection (1 reviewer, work items required)"
        Reviewers = "1 (blocking)"
        WorkItems = "Required"
        Build = "Disabled"
        Comments = "Required"
    }
    'Strict' = @{
        File = "strict-policies.json"
        Location = $examplesPath
        Description = "Enterprise-grade security (3 reviewers, build validation, SonarQube)"
        Reviewers = "3 (blocking, reset on push)"
        WorkItems = "Required"
        Build = "Required (ID 42)"
        Comments = "Required"
    }
    'Relaxed' = @{
        File = "relaxed-policies.json"
        Location = $examplesPath
        Description = "Small team flexibility (1 reviewer, optional work items)"
        Reviewers = "1 (blocking)"
        WorkItems = "Optional"
        Build = "Disabled"
        Comments = "Disabled"
    }
    'None' = @{
        File = "no-policies.json"
        Location = $examplesPath
        Description = "Development/testing only (all policies disabled)"
        Reviewers = "Disabled"
        WorkItems = "Disabled"
        Build = "Disabled"
        Comments = "Disabled"
    }
}

function Show-CurrentConfiguration {
    Write-Host "`n📋 Current Active Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    
    try {
        # Read project settings
        $projectSettingsPath = Join-Path $configPath "project-settings.json"
        $projectSettings = Get-Content $projectSettingsPath | ConvertFrom-Json
        
        Write-Host "`n🔧 Project Settings:" -ForegroundColor Yellow
        Write-Host "   Process Template: $($projectSettings.processTemplate)"
        Write-Host "   Areas: $($projectSettings.areas.Count)"
        foreach ($area in $projectSettings.areas) {
            Write-Host "      - $($area.name): $($area.description)" -ForegroundColor DarkGray
        }
        Write-Host "   Sprints: $($projectSettings.iterations.sprintCount) × $($projectSettings.iterations.sprintDurationDays) days"
        Write-Host "   Sprint Prefix: $($projectSettings.iterations.sprintPrefix)"
        Write-Host "   Default Branch: $($projectSettings.defaultRepository.defaultBranch)"
        
        # Read branch policies
        $branchPoliciesPath = Join-Path $configPath "branch-policies.json"
        $branchPolicies = Get-Content $branchPoliciesPath | ConvertFrom-Json
        
        Write-Host "`n🛡️  Branch Policies:" -ForegroundColor Yellow
        $bp = $branchPolicies.branchPolicies
        Write-Host "   Required Reviewers: $(if ($bp.requiredReviewers.enabled) { "$($bp.requiredReviewers.minimumApproverCount) (blocking: $($bp.requiredReviewers.isBlocking))" } else { "Disabled" })"
        Write-Host "   Work Item Linking: $(if ($bp.workItemLinking.enabled) { "Required" } else { "Disabled" })"
        Write-Host "   Comment Resolution: $(if ($bp.commentResolution.enabled) { "Required" } else { "Disabled" })"
        Write-Host "   Build Validation: $(if ($bp.buildValidation.enabled) { "Required (ID: $($bp.buildValidation.buildDefinitionId))" } else { "Disabled" })"
        Write-Host "   Status Checks: $(if ($bp.statusCheck.enabled) { "$($bp.statusCheck.statusGenre)" } else { "Disabled" })"
        Write-Host "   Merge Strategy: $(if ($bp.mergeStrategy.noFastForward) { "No-FF" } elseif ($bp.mergeStrategy.squash) { "Squash" } elseif ($bp.mergeStrategy.rebase) { "Rebase" } else { "All allowed" })"
        
        Write-Host "`n✅ Configuration files found at:" -ForegroundColor Green
        Write-Host "   $projectSettingsPath" -ForegroundColor DarkGray
        Write-Host "   $branchPoliciesPath" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Failed to read current configuration: $_"
    }
    
    Write-Host ""
}

function Show-AvailableProfiles {
    Write-Host "`n📚 Available Configuration Profiles" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    
    Write-Host "`n🔧 Project Settings Profiles:" -ForegroundColor Yellow
    foreach ($profile in $projectProfiles.GetEnumerator() | Sort-Object Name) {
        Write-Host "`n   [$($profile.Key)]" -ForegroundColor Green
        Write-Host "      Description: $($profile.Value.Description)"
        Write-Host "      Areas: $($profile.Value.Areas) | Sprints: $($profile.Value.Sprints) × $($profile.Value.Duration)"
        Write-Host "      Template: $($profile.Value.Template)"
        Write-Host "      File: $($profile.Value.File)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n`n🛡️  Branch Policies Profiles:" -ForegroundColor Yellow
    foreach ($profile in $policyProfiles.GetEnumerator() | Sort-Object Name) {
        Write-Host "`n   [$($profile.Key)]" -ForegroundColor Green
        Write-Host "      Description: $($profile.Value.Description)"
        Write-Host "      Reviewers: $($profile.Value.Reviewers)"
        Write-Host "      Work Items: $($profile.Value.WorkItems) | Build: $($profile.Value.Build)"
        Write-Host "      Comments: $($profile.Value.Comments)"
        Write-Host "      File: $($profile.Value.File)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n`n💡 Usage:" -ForegroundColor Cyan
    Write-Host "   .\Set-MigrationConfig.ps1 -ProjectProfile <Profile> -PolicyProfile <Profile>"
    Write-Host "`n   Example: .\Set-MigrationConfig.ps1 -ProjectProfile Mobile -PolicyProfile Relaxed`n"
}

function Set-Configuration {
    param(
        [string]$ProjectProfile,
        [string]$PolicyProfile
    )
    
    Write-Host "`n🔄 Switching Configuration..." -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    
    # Get source files
    $projectSource = Join-Path $projectProfiles[$ProjectProfile].Location $projectProfiles[$ProjectProfile].File
    $policySource = Join-Path $policyProfiles[$PolicyProfile].Location $policyProfiles[$PolicyProfile].File
    
    # Validate source files exist
    if (-not (Test-Path $projectSource)) {
        throw "Project settings file not found: $projectSource"
    }
    if (-not (Test-Path $policySource)) {
        throw "Branch policies file not found: $policySource"
    }
    
    # Create backup
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $projectTarget = Join-Path $configPath "project-settings.json"
    $policyTarget = Join-Path $configPath "branch-policies.json"
    
    Write-Host "`n📦 Creating backups..." -ForegroundColor Yellow
    if (Test-Path $projectTarget) {
        $projectBackup = Join-Path $configPath "project-settings.$timestamp.backup.json"
        Copy-Item $projectTarget $projectBackup -Force
        Write-Host "   ✓ Project settings backed up: project-settings.$timestamp.backup.json" -ForegroundColor DarkGray
    }
    
    if (Test-Path $policyTarget) {
        $policyBackup = Join-Path $configPath "branch-policies.$timestamp.backup.json"
        Copy-Item $policyTarget $policyBackup -Force
        Write-Host "   ✓ Branch policies backed up: branch-policies.$timestamp.backup.json" -ForegroundColor DarkGray
    }
    
    # Apply new configurations
    Write-Host "`n🔧 Applying new configurations..." -ForegroundColor Yellow
    Copy-Item $projectSource $projectTarget -Force
    Write-Host "   ✓ Project settings: $ProjectProfile" -ForegroundColor Green
    Write-Host "      $($projectProfiles[$ProjectProfile].Description)" -ForegroundColor DarkGray
    
    Copy-Item $policySource $policyTarget -Force
    Write-Host "   ✓ Branch policies: $PolicyProfile" -ForegroundColor Green
    Write-Host "      $($policyProfiles[$PolicyProfile].Description)" -ForegroundColor DarkGray
    
    Write-Host "`n✅ Configuration switch complete!" -ForegroundColor Green
    Write-Host "   You can now run: .\Gitlab2DevOps.ps1`n" -ForegroundColor Cyan
}

# Main execution
try {
    if ($ShowCurrent) {
        Show-CurrentConfiguration
    }
    elseif ($ListProfiles) {
        Show-AvailableProfiles
    }
    else {
        Set-Configuration -ProjectProfile $ProjectProfile -PolicyProfile $PolicyProfile
        Show-CurrentConfiguration
    }
}
catch {
    Write-Host "`n❌ Error: $_" -ForegroundColor Red
    exit 1
}
