# Configuration Quick-Switch Guide

This guide shows how to quickly switch between different configuration profiles for Azure DevOps project initialization.

## 📁 Configuration Files Overview

### Active Configurations (Used by Default)
- **`modules/AzureDevOps/config/project-settings.json`** - Project structure and sprints
- **`modules/AzureDevOps/config/branch-policies.json`** - Branch protection policies

### Available Presets (Examples)

#### Project Settings Presets
1. **Default** (`project-settings.json`) - Balanced setup for most teams
2. **Mobile** (`examples/mobile-project-settings.json`) - iOS/Android focused
3. **Enterprise** (`examples/enterprise-project-settings.json`) - Large organization structure
4. **Small Team** (`examples/small-team-project-settings.json`) - Minimal overhead

#### Branch Policies Presets
1. **Default** (`branch-policies.json`) - Standard protection
2. **Strict** (`examples/strict-policies.json`) - Enterprise-grade security
3. **Relaxed** (`examples/relaxed-policies.json`) - Small team flexibility
4. **No Policies** (`examples/no-policies.json`) - Development/testing only

---

## 🔄 Quick Switch Methods

### Method 1: Copy & Replace (Recommended)

#### Switch to Mobile Project Settings
```powershell
# Backup current config
Copy-Item modules/AzureDevOps/config/project-settings.json modules/AzureDevOps/config/project-settings.backup.json

# Apply mobile preset
Copy-Item examples/mobile-project-settings.json modules/AzureDevOps/config/project-settings.json

# Run migration
.\Gitlab2DevOps.ps1
```

#### Switch to Strict Branch Policies
```powershell
# Backup current config
Copy-Item modules/AzureDevOps/config/branch-policies.json modules/AzureDevOps/config/branch-policies.backup.json

# Apply strict preset
Copy-Item examples/strict-policies.json modules/AzureDevOps/config/branch-policies.json

# Run migration
.\Gitlab2DevOps.ps1
```

#### Restore Default
```powershell
# Restore from backup
Copy-Item modules/AzureDevOps/config/project-settings.backup.json modules/AzureDevOps/config/project-settings.json
Copy-Item modules/AzureDevOps/config/branch-policies.backup.json modules/AzureDevOps/config/branch-policies.json
```

---

### Method 2: Rename Files (Quick Toggle)

#### Setup (One-Time)
```powershell
# Rename active configs
Rename-Item modules/AzureDevOps/config/project-settings.json project-settings.default.json
Rename-Item modules/AzureDevOps/config/branch-policies.json branch-policies.default.json

# Copy presets to config folder
Copy-Item examples/mobile-project-settings.json modules/AzureDevOps/config/project-settings.mobile.json
Copy-Item examples/enterprise-project-settings.json modules/AzureDevOps/config/project-settings.enterprise.json
Copy-Item examples/small-team-project-settings.json modules/AzureDevOps/config/project-settings.small.json

Copy-Item examples/strict-policies.json modules/AzureDevOps/config/branch-policies.strict.json
Copy-Item examples/relaxed-policies.json modules/AzureDevOps/config/branch-policies.relaxed.json
Copy-Item examples/no-policies.json modules/AzureDevOps/config/branch-policies.none.json
```

#### Switch to Mobile + Relaxed
```powershell
# Activate mobile settings
Copy-Item modules/AzureDevOps/config/project-settings.mobile.json modules/AzureDevOps/config/project-settings.json

# Activate relaxed policies
Copy-Item modules/AzureDevOps/config/branch-policies.relaxed.json modules/AzureDevOps/config/branch-policies.json

# Run migration
.\Gitlab2DevOps.ps1
```

#### Switch to Enterprise + Strict
```powershell
# Activate enterprise settings
Copy-Item modules/AzureDevOps/config/project-settings.enterprise.json modules/AzureDevOps/config/project-settings.json

# Activate strict policies
Copy-Item modules/AzureDevOps/config/branch-policies.strict.json modules/AzureDevOps/config/branch-policies.json

# Run migration
.\Gitlab2DevOps.ps1
```

---

### Method 3: PowerShell Function (Most Convenient)

Add this to your PowerShell profile or create a helper script:

```powershell
# Save as: Set-MigrationConfig.ps1

function Set-MigrationConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Default', 'Mobile', 'Enterprise', 'SmallTeam')]
        [string]$ProjectProfile,
        
        [Parameter(Mandatory)]
        [ValidateSet('Default', 'Strict', 'Relaxed', 'None')]
        [string]$PolicyProfile
    )
    
    $configPath = "modules/AzureDevOps/config"
    $examplesPath = "examples"
    
    # Map profiles to files
    $projectFiles = @{
        'Default' = "$configPath/project-settings.json"
        'Mobile' = "$examplesPath/mobile-project-settings.json"
        'Enterprise' = "$examplesPath/enterprise-project-settings.json"
        'SmallTeam' = "$examplesPath/small-team-project-settings.json"
    }
    
    $policyFiles = @{
        'Default' = "$configPath/branch-policies.json"
        'Strict' = "$examplesPath/strict-policies.json"
        'Relaxed' = "$examplesPath/relaxed-policies.json"
        'None' = "$examplesPath/no-policies.json"
    }
    
    # Backup current configs
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item "$configPath/project-settings.json" "$configPath/project-settings.$timestamp.backup.json" -Force
    Copy-Item "$configPath/branch-policies.json" "$configPath/branch-policies.$timestamp.backup.json" -Force
    
    # Apply new configs
    Copy-Item $projectFiles[$ProjectProfile] "$configPath/project-settings.json" -Force
    Copy-Item $policyFiles[$PolicyProfile] "$configPath/branch-policies.json" -Force
    
    Write-Host "✅ Configuration updated:" -ForegroundColor Green
    Write-Host "   Project Profile: $ProjectProfile"
    Write-Host "   Policy Profile: $PolicyProfile"
    Write-Host "   Backup created: $timestamp"
}

# Usage examples:
# Set-MigrationConfig -ProjectProfile Mobile -PolicyProfile Relaxed
# Set-MigrationConfig -ProjectProfile Enterprise -PolicyProfile Strict
# Set-MigrationConfig -ProjectProfile Default -PolicyProfile Default
```

**Usage**:
```powershell
# Load the function
. .\Set-MigrationConfig.ps1

# Switch to mobile with relaxed policies
Set-MigrationConfig -ProjectProfile Mobile -PolicyProfile Relaxed

# Switch to enterprise with strict policies
Set-MigrationConfig -ProjectProfile Enterprise -PolicyProfile Strict

# Run migration
.\Gitlab2DevOps.ps1
```

---

## 📊 Configuration Comparison

### Project Settings Comparison

| Feature | Default | Mobile | Enterprise | Small Team |
|---------|---------|--------|------------|------------|
| **Process Template** | Agile | Scrum | Agile | Agile |
| **Areas** | 4 (Frontend/Backend/Infra/Docs) | 4 (iOS/Android/Backend/DevOps) | 8 (Platform/Services/Portal/etc.) | 3 (Features/Bugfixes/Tech Debt) |
| **Sprint Count** | 6 | 8 | 12 | 4 |
| **Sprint Duration** | 14 days | 10 days | 14 days | 7 days |
| **Best For** | General teams | Mobile apps | Large orgs | Startups |

### Branch Policies Comparison

| Feature | Default | Strict | Relaxed | No Policies |
|---------|---------|--------|---------|-------------|
| **Required Reviewers** | 1 (blocking) | 3 (blocking, reset on push) | 1 (non-blocking) | Disabled |
| **Work Item Linking** | Required | Required | Optional | Disabled |
| **Comment Resolution** | Required | Required | Disabled | Disabled |
| **Build Validation** | Disabled | Required (ID 42) | Disabled | Disabled |
| **Status Checks** | Disabled | SonarQube (blocking) | Disabled | Disabled |
| **Merge Strategy** | No-FF only | No-FF only | No-FF only | All allowed |
| **Best For** | Teams | Enterprise | Small teams | Dev/Test |

---

## 🎯 Recommended Combinations

### New Startup
```powershell
Set-MigrationConfig -ProjectProfile SmallTeam -PolicyProfile Relaxed
```
- Fast iteration, minimal overhead
- Weekly sprints, simple structure
- 1 reviewer, optional work items

### Mobile Development
```powershell
Set-MigrationConfig -ProjectProfile Mobile -PolicyProfile Relaxed
```
- iOS/Android focus
- 10-day sprints (app store cycles)
- Flexible policies for rapid iteration

### Enterprise Project
```powershell
Set-MigrationConfig -ProjectProfile Enterprise -PolicyProfile Strict
```
- Comprehensive area structure
- 3 reviewers, SonarQube gates
- Compliance-ready

### General Product Team
```powershell
Set-MigrationConfig -ProjectProfile Default -PolicyProfile Default
```
- Balanced approach
- Standard Agile workflow
- 1 reviewer, work item tracking

---

## 🔍 Verify Current Configuration

```powershell
# Check active project settings
Get-Content modules/AzureDevOps/config/project-settings.json | ConvertFrom-Json | Format-List

# Check active branch policies
Get-Content modules/AzureDevOps/config/branch-policies.json | ConvertFrom-Json | Format-List

# List all backups
Get-ChildItem modules/AzureDevOps/config/*.backup.json | Format-Table Name, LastWriteTime
```

---

## 💡 Tips

1. **Always backup before switching**: Use timestamps in backup filenames
2. **Test with demo projects**: Try `Option 3 → 1 → "demo"` before production
3. **Document your choice**: Add comments in wiki pages explaining why you chose specific configs
4. **Version control**: Store your preferred configs in a separate repo
5. **Team alignment**: Discuss with team before changing policies mid-project

---

## 🚨 Important Notes

- Configuration changes only affect **NEW** projects created after the change
- Existing projects are **NOT** automatically updated
- Schema validation ensures configurations are valid (VS Code IntelliSense)
- Backup files accumulate - clean up old backups periodically

---

## 📚 Related Documentation

- [Configuration README](modules/AzureDevOps/config/README.md)
- [Project Settings Schema](modules/AzureDevOps/config/project-settings.schema.json)
- [Branch Policies Schema](modules/AzureDevOps/config/branch-policies.schema.json)
- [Azure DevOps Process Templates](https://learn.microsoft.com/azure/devops/boards/work-items/guidance/choose-process)

---

*Last updated: 2025-11-08*
