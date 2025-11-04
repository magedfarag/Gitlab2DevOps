# CLI Usage Guide

Complete reference for command-line automation with Gitlab2DevOps.

## CLI Mode Overview

CLI mode enables headless automation for CI/CD pipelines, scripts, and batch processing.

**Key Features**:
- Non-interactive execution
- Exit codes for error handling
- Structured JSON output
- Run manifests for audit trails
- `-WhatIf` support for safe testing

---

## Quick Reference

```powershell
# Single migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "ADOProject"

# Preflight check only
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/project"

# Bulk migrate all projects from file
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ProjectsFile projects.txt

# Initialize without migrating
.\Gitlab2DevOps.ps1 -Mode Initialize -Source "group/project" -Project "ADOProject"

# Force migration (skip blocking issues)
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Force

# Test run (preview changes)
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -WhatIf
```

---

## CLI Parameters

### Required Parameters

#### `-Mode`
Execution mode for the operation.

**Type**: String  
**Values**: `Preflight`, `Initialize`, `Migrate`, `BulkPrepare`, `BulkMigrate`  
**Required**: Yes (in CLI mode)

```powershell
# Examples
-Mode Preflight   # Check for issues only
-Mode Initialize  # Create ADO project only
-Mode Migrate     # Full migration
-Mode BulkPrepare # Preflight all projects
-Mode BulkMigrate # Migrate all projects
```

---

### Source/Target Parameters

#### `-Source`
GitLab project path (group/project format).

**Type**: String  
**Required**: Yes (for single project modes)  
**Example**: `engineering/web-app`

```powershell
# Valid formats
-Source "my-group/my-project"
-Source "parent-group/subgroup/project"
-Source "username/personal-project"
```

#### `-Project`
Azure DevOps project name (destination).

**Type**: String  
**Required**: No (defaults to last segment of GitLab path)  
**Example**: `WebApp`

```powershell
# Explicit project name
-Project "WebApplication"

# Auto-detect from source path
-Source "engineering/web-app"  # Creates "web-app" project
```

#### `-ProjectsFile`
Path to text file with GitLab projects (for bulk operations).

**Type**: String  
**Required**: Yes (for bulk modes)  
**Format**: One project path per line

```powershell
-ProjectsFile "projects-to-migrate.txt"
-ProjectsFile "C:\migrations\batch-001.txt"
```

**File Format**:
```text
engineering/api-gateway
engineering/auth-service
marketing/website
devops/infrastructure
```

---

### Behavior Modifiers

#### `-Force`
Skip blocking issue checks and force migration.

**Type**: Switch  
**Default**: False  
**Risk**: High (may result in incomplete migration)

```powershell
# Force migration despite warnings
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Force
```

**Use Cases**:
- Migrating repositories with known issues
- Overriding preflight warnings
- Emergency migrations

**Warning**: Using `-Force` may result in:
- Empty repository migrations
- Missing branch policies
- Incomplete git history

#### `-Replace`
Delete existing Azure DevOps repository and recreate.

**Type**: Switch  
**Default**: False  
**ConfirmImpact**: High (prompts for confirmation)

```powershell
# Replace existing repository
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Replace

# Replace without confirmation
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Replace -Confirm:$false
```

**Use Cases**:
- Retry failed migrations
- Update migrated repository
- Reset corrupted repositories

#### `-AllowSync`
Enable synchronization mode (experimental).

**Type**: Switch  
**Default**: False  
**Status**: Experimental (not recommended)

```powershell
# Enable sync mode
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -AllowSync
```

**Warning**: This feature is not production-ready. Do not use for critical migrations.

---

### PowerShell Common Parameters

#### `-WhatIf`
Preview changes without executing them.

**Type**: Switch  
**Inherited**: From `[CmdletBinding(SupportsShouldProcess)]`

```powershell
# Preview migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -WhatIf
```

**Output**:
```
What if: Creating Azure DevOps project "my-project"
What if: Creating repository "my-project"
What if: Applying 5 branch policies
```

#### `-Confirm`
Prompt for confirmation before destructive operations.

**Type**: Switch  
**Inherited**: From `[CmdletBinding(SupportsShouldProcess)]`

```powershell
# Prompt before replacing
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Replace

# Skip confirmation
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Replace -Confirm:$false
```

#### `-Verbose`
Display detailed execution information.

**Type**: Switch  
**Inherited**: From `[CmdletBinding()]`

```powershell
# Verbose output
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Verbose
```

**Output**:
```
VERBOSE: Using cached project list (age: 3 minutes)
VERBOSE: Found project 'my-project' (ID: 12345)
VERBOSE: Repository has 456 commits
VERBOSE: Applying branch policy: Require minimum 2 reviewers
```

---

## Modes Explained

### Mode: Preflight

Validates migration readiness without making changes.

```powershell
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "engineering/api"
```

**Actions**:
- ✅ Fetches GitLab project metadata
- ✅ Checks repository status (commits, branches)
- ✅ Validates branch protection rules
- ✅ Generates preflight report JSON
- ❌ Does NOT create Azure DevOps resources

**Output**:
- Console: Summary of issues
- File: `migrations/<project>/reports/preflight-report.json`

**Exit Codes**:
- `0`: No blocking issues
- `1`: Blocking issues found

---

### Mode: Initialize

Creates Azure DevOps project and repository without migrating code.

```powershell
.\Gitlab2DevOps.ps1 -Mode Initialize -Source "engineering/api" -Project "API"
```

**Actions**:
- ✅ Creates Azure DevOps project
- ✅ Creates empty repository
- ✅ Configures repository settings
- ❌ Does NOT push code

**Use Cases**:
- Prepare infrastructure before migration
- Test project creation
- Pre-create projects for bulk migration

---

### Mode: Migrate

Complete end-to-end migration (preflight + initialize + push).

```powershell
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "engineering/api" -Project "API"
```

**Actions**:
- ✅ Runs preflight checks
- ✅ Creates Azure DevOps project
- ✅ Clones GitLab repository
- ✅ Pushes all branches and tags
- ✅ Configures branch policies
- ✅ Generates migration report

**Duration**: 2-15 minutes (depends on repository size)

---

### Mode: BulkPrepare

Runs preflight checks for multiple projects from a file.

```powershell
.\Gitlab2DevOps.ps1 -Mode BulkPrepare -ProjectsFile projects.txt
```

**Actions**:
- ✅ Reads project list from file
- ✅ Runs preflight for each project
- ✅ Generates summary report
- ❌ Does NOT create Azure DevOps resources

**Output**:
- Console: Progress bar and summary
- Files: Individual preflight reports per project

---

### Mode: BulkMigrate

Migrates multiple projects from a file (end-to-end).

```powershell
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ProjectsFile projects.txt
```

**Actions**:
- ✅ Reads project list from file
- ✅ Runs full migration for each project
- ✅ Generates summary report
- ✅ Continues on errors (logs failures)

**Duration**: 10-60 minutes (depends on project count and sizes)

---

## Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| `0` | Success | Operation completed successfully |
| `1` | General Error | Unhandled exception or failure |
| `2` | Blocking Issues | Preflight found blocking issues (without `-Force`) |
| `3` | Authentication | Invalid GitLab or Azure DevOps credentials |
| `4` | Not Found | Project or repository not found |

**Example**:
```powershell
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "invalid/project"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Migration failed with code $LASTEXITCODE"
}
```

---

## CI/CD Integration Examples

### GitHub Actions

```yaml
name: Migrate to Azure DevOps

on:
  workflow_dispatch:
    inputs:
      gitlab_project:
        description: 'GitLab project path'
        required: true

jobs:
  migrate:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure credentials
        run: |
          @{
            gitlab = @{
              base_url = "${{ secrets.GITLAB_URL }}"
              token = "${{ secrets.GITLAB_TOKEN }}"
            }
            ado = @{
              organization = "${{ secrets.ADO_ORG }}"
              token = "${{ secrets.ADO_TOKEN }}"
            }
          } | ConvertTo-Json | Out-File migration.config.json
      
      - name: Run migration
        run: |
          .\Gitlab2DevOps.ps1 -Mode Migrate -Source "${{ github.event.inputs.gitlab_project }}" -Verbose
      
      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: migration-reports
          path: migrations/*/reports/*.json
```

---

### Azure Pipelines

```yaml
trigger: none

parameters:
  - name: gitlabProject
    displayName: 'GitLab Project Path'
    type: string
  - name: adoProject
    displayName: 'Azure DevOps Project Name'
    type: string

pool:
  vmImage: 'windows-latest'

steps:
  - pwsh: |
      @{
        gitlab = @{
          base_url = "$(GITLAB_URL)"
          token = "$(GITLAB_TOKEN)"
        }
        ado = @{
          organization = "$(ADO_ORG)"
          token = "$(ADO_TOKEN)"
        }
      } | ConvertTo-Json | Out-File migration.config.json
    displayName: 'Configure credentials'
    
  - pwsh: |
      .\Gitlab2DevOps.ps1 -Mode Migrate `
        -Source "${{ parameters.gitlabProject }}" `
        -Project "${{ parameters.adoProject }}" `
        -Verbose
    displayName: 'Run migration'
    
  - task: PublishBuildArtifacts@1
    condition: always()
    inputs:
      pathToPublish: 'migrations'
      artifactName: 'migration-output'
```

---

### Jenkins

```groovy
pipeline {
    agent { label 'windows' }
    
    parameters {
        string(name: 'GITLAB_PROJECT', description: 'GitLab project path')
        string(name: 'ADO_PROJECT', description: 'Azure DevOps project name')
    }
    
    environment {
        GITLAB_URL = credentials('gitlab-url')
        GITLAB_TOKEN = credentials('gitlab-token')
        ADO_ORG = credentials('ado-org')
        ADO_TOKEN = credentials('ado-token')
    }
    
    stages {
        stage('Configure') {
            steps {
                pwsh '''
                    @{
                        gitlab = @{
                            base_url = $env:GITLAB_URL
                            token = $env:GITLAB_TOKEN
                        }
                        ado = @{
                            organization = $env:ADO_ORG
                            token = $env:ADO_TOKEN
                        }
                    } | ConvertTo-Json | Out-File migration.config.json
                '''
            }
        }
        
        stage('Migrate') {
            steps {
                pwsh """
                    .\\Gitlab2DevOps.ps1 -Mode Migrate `
                      -Source "${params.GITLAB_PROJECT}" `
                      -Project "${params.ADO_PROJECT}" `
                      -Verbose
                """
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'migrations/**/reports/*.json', allowEmptyArchive: true
        }
    }
}
```

---

## Best Practices

### 1. Always Run Preflight First

```powershell
# Check first
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/project"

# Review reports/preflight-report.json

# Then migrate
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"
```

### 2. Use -WhatIf for Testing

```powershell
# Preview changes
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -WhatIf

# Execute after review
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"
```

### 3. Enable Verbose Logging

```powershell
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Verbose
```

### 4. Secure Credentials

```powershell
# Read from environment variables
$config = @{
    gitlab = @{
        base_url = $env:GITLAB_URL
        token = $env:GITLAB_TOKEN
    }
    ado = @{
        organization = $env:ADO_ORG
        token = $env:ADO_TOKEN
    }
} | ConvertTo-Json | Out-File migration.config.json

# Run migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"

# Clean up
Remove-Item migration.config.json
```

### 5. Check Exit Codes

```powershell
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Migration completed successfully"
} else {
    Write-Error "❌ Migration failed with code $LASTEXITCODE"
    exit $LASTEXITCODE
}
```

---

## Troubleshooting

### "Parameter set cannot be resolved"
**Cause**: Mixing interactive and CLI parameters.  
**Solution**: Use `-Mode` with all CLI parameters, or omit for interactive mode.

```powershell
# ❌ Invalid
.\Gitlab2DevOps.ps1 -Source "group/project"  # Missing -Mode

# ✅ Valid
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"
```

### "Source parameter is required"
**Cause**: Using single-project mode without `-Source`.  
**Solution**: Add `-Source` parameter.

```powershell
# ❌ Invalid
.\Gitlab2DevOps.ps1 -Mode Migrate

# ✅ Valid
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"
```

### "ProjectsFile not found"
**Cause**: Invalid file path in bulk mode.  
**Solution**: Use absolute path or verify file exists.

```powershell
# ❌ Invalid
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ProjectsFile "missing.txt"

# ✅ Valid
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ProjectsFile "C:\migrations\projects.txt"
```

---

## See Also

- [Interactive Mode Guide](interactive-mode.md)
- [Configuration Reference](configuration.md)
- [Troubleshooting](troubleshooting.md)
- [Examples Directory](../examples/)

---

[← Back to Documentation Index](README.md)
