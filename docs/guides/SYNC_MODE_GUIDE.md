# Sync Mode Guide

## Overview

Sync Mode allows you to re-run migrations to update Azure DevOps repositories when the source GitLab projects change. This is essential for maintaining up-to-date mirrors of your GitLab repositories in Azure DevOps.

## When to Use Sync Mode

✅ **Use sync mode when:**
- GitLab source repository has new commits that need to be reflected in Azure DevOps
- New branches or tags have been created in GitLab
- You need to refresh the Azure DevOps repository content
- The Azure DevOps repository is a mirror and has no local-only changes

❌ **Do NOT use sync mode when:**
- You're unsure if the Azure DevOps repository exists
- The Azure DevOps repository has local changes that would be lost
- You want to prevent accidental overwrites
- This is the first migration (sync mode is for updates only)

## How It Works

### What Sync Mode Preserves

When you run a migration with `-AllowSync`, the following Azure DevOps settings are **preserved**:
- Repository security settings and permissions
- Branch policies (required reviewers, build validation, etc.)
- Security groups (Dev, QA, BA, Release Approvers, Pipeline Maintainers)
- Work item templates
- Project wiki
- All other Azure DevOps configurations

### What Sync Mode Updates

Sync mode **updates** the following:
- Repository content (all commits, branches, tags)
- Git references to match current GitLab state
- Migration history in summary JSON file

## Usage Examples

### Single Project Sync

#### Command Line
```powershell
.\Gitlab2DevOps.ps1 -Mode migrate `
  -GitLabProject "myorg/my-repository" `
  -AdoProject "ConsolidatedProject" `
  -AllowSync
```

#### Interactive Menu
1. Run `.\Gitlab2DevOps.ps1`
2. Select option **3** (Single Project Migration)
3. Enter GitLab project path: `myorg/my-repository`
4. Enter Azure DevOps project name: `ConsolidatedProject`
5. When asked "Allow sync of existing repository? (Y/N)", answer **Y**
6. Confirm migration

### Bulk Migration Sync

#### Command Line
```powershell
.\Gitlab2DevOps.ps1 -Mode bulkMigrate `
  -ConfigFile "bulk-migration-config.json" `
  -AllowSync
```

#### Interactive Menu
1. Run `.\Gitlab2DevOps.ps1`
2. Select option **6** (Execute Bulk Migration)
3. Select your prepared template file
4. When asked "Allow sync of existing repositories? (Y/N)", answer **Y**
5. Confirm migration

### Pre-flight Check with Sync

You can validate that a repository can be synced before actually syncing:

```powershell
.\Gitlab2DevOps.ps1 -Mode preflight `
  -GitLabProject "myorg/my-repository" `
  -AdoProject "ConsolidatedProject" `
  -AllowSync
```

The preflight report will show:
- ✅ `ready_to_migrate: true`
- ℹ️ `sync_mode: true`
- Repository exists and can be updated

## Migration History Tracking

Every sync operation is recorded in the migration summary JSON file located at:
```
migrations/[normalized-project-name]/reports/migration-summary.json
```

### Summary Structure

```json
{
  "gitlab_project": "myorg/my-repository",
  "ado_project": "ConsolidatedProject",
  "ado_repository": "my-repository",
  "migration_type": "SYNC",
  "migration_count": 3,
  "last_sync": "2024-01-15T14:30:00",
  "migration_start": "2024-01-15T14:28:00",
  "migration_end": "2024-01-15T14:30:00",
  "status": "SUCCESS",
  "previous_migrations": [
    {
      "migration_start": "2024-01-01T10:00:00",
      "migration_end": "2024-01-01T10:15:00",
      "status": "SUCCESS",
      "type": "INITIAL"
    },
    {
      "migration_start": "2024-01-08T11:30:00",
      "migration_end": "2024-01-08T11:42:00",
      "status": "SUCCESS",
      "type": "SYNC"
    },
    {
      "migration_start": "2024-01-15T14:28:00",
      "migration_end": "2024-01-15T14:30:00",
      "status": "SUCCESS",
      "type": "SYNC"
    }
  ]
}
```

### Key Fields

| Field | Description |
|-------|-------------|
| `migration_type` | "INITIAL" for first migration, "SYNC" for updates |
| `migration_count` | Total number of migrations (initial + syncs) |
| `last_sync` | Timestamp of most recent sync |
| `previous_migrations` | Array of all previous migration operations |

## Sync Workflow

### Step-by-Step Process

1. **Pre-Validation**
   - Checks if Azure DevOps repository exists
   - With `-AllowSync`: Treats existing repo as ready for update
   - Without `-AllowSync`: Treats existing repo as blocking issue

2. **Repository Update**
   - Clones latest GitLab repository to local cache
   - Pushes all refs (branches, tags) to Azure DevOps
   - Uses `--force` where needed to update refs

3. **History Recording**
   - Reads previous migration summary (if exists)
   - Adds current migration to `previous_migrations` array
   - Increments `migration_count`
   - Updates `last_sync` timestamp
   - Saves complete history

4. **Completion**
   - Shows summary with sync count
   - Example: "✅ Migration completed successfully! (Sync #3)"

## Configuration Preservation

All migration folder contents are preserved during sync:

```
migrations/myorg-my-repository/
├── repository/              # Updated with latest Git content
├── reports/
│   ├── preflight-report.json      # Preserved
│   ├── migration-summary.json     # Updated with sync history
│   └── rollback-info.json         # Preserved
└── logs/
    ├── 2024-01-01-migration.log   # Preserved
    ├── 2024-01-08-sync.log        # Preserved
    └── 2024-01-15-sync.log        # New log added
```

## Best Practices

### Regular Sync Schedule
- Establish a regular sync schedule (daily, weekly, etc.)
- Automate syncs with scheduled tasks or CI/CD pipelines
- Monitor sync status through migration summary files

### Verification After Sync
```powershell
# Check sync history
$summary = Get-Content "migrations/[project]/reports/migration-summary.json" | ConvertFrom-Json
Write-Host "Total syncs: $($summary.migration_count)"
Write-Host "Last sync: $($summary.last_sync)"
Write-Host "Status: $($summary.status)"
```

### Bulk Sync Strategy
For bulk operations with many repositories:
```powershell
# Sync all repositories in config
.\Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "production-sync.json" -AllowSync

# Check results in each migration folder
Get-ChildItem migrations -Directory | ForEach-Object {
  $summaryPath = Join-Path $_.FullName "reports/migration-summary.json"
  if (Test-Path $summaryPath) {
    $summary = Get-Content $summaryPath | ConvertFrom-Json
    Write-Host "$($_.Name): $($summary.migration_count) migrations, last: $($summary.last_sync)"
  }
}
```

### Error Handling
If a sync fails:
1. Check the latest log file in `migrations/[project]/logs/`
2. Verify GitLab connectivity and credentials
3. Ensure Azure DevOps PAT has sufficient permissions
4. Review `previous_migrations` array to see last successful sync
5. Re-run sync after resolving issues

## Automated Sync Example

### Windows Scheduled Task
```powershell
# Create scheduled task to sync daily at 2 AM
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-File C:\Scripts\sync-repos.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

Register-ScheduledTask -Action $action -Trigger $trigger `
  -TaskName "GitLab-ADO-Sync" -Description "Daily repository sync"
```

### sync-repos.ps1 Script
```powershell
Set-Location "C:\Projects\devops\Gitlab2DevOps"

# Load environment variables
.\setup-env.ps1

# Sync all repositories
.\Gitlab2DevOps.ps1 -Mode bulkMigrate `
  -ConfigFile "production-repos.json" `
  -AllowSync

# Email results
$summaries = Get-ChildItem migrations -Directory | ForEach-Object {
  $summaryPath = Join-Path $_.FullName "reports/migration-summary.json"
  if (Test-Path $summaryPath) {
    Get-Content $summaryPath | ConvertFrom-Json
  }
}

$results = $summaries | Format-Table gitlab_project, migration_count, last_sync, status
Send-MailMessage -To "devops@company.com" `
  -Subject "Daily Sync Report" `
  -Body ($results | Out-String)
```

## Troubleshooting

### "Repository already exists" Error
**Problem:** Migration fails with repository exists error even though sync is intended

**Solution:** Add `-AllowSync` parameter
```powershell
.\Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Project" -AllowSync
```

### Sync Count Not Incrementing
**Problem:** `migration_count` stays at 1 after multiple syncs

**Solution:** Check that migration summary JSON exists and is valid
```powershell
$summaryPath = "migrations/[project]/reports/migration-summary.json"
Test-Path $summaryPath  # Should be True
Get-Content $summaryPath | ConvertFrom-Json  # Should parse without error
```

### Lost Azure DevOps Configuration
**Problem:** Branch policies or permissions missing after sync

**Solution:** Sync mode should NOT remove Azure DevOps settings. If this occurs:
1. Check migration logs for errors during policy/permission setup
2. Re-run configuration functions manually if needed
3. Report as a bug if settings are being removed by sync

### Partial Sync Completion
**Problem:** Some repositories synced, others failed in bulk operation

**Solution:** Check individual migration summaries
```powershell
Get-ChildItem migrations -Directory | ForEach-Object {
  $summary = Get-Content "$($_.FullName)/reports/migration-summary.json" | ConvertFrom-Json
  if ($summary.status -eq "FAILED") {
    Write-Host "FAILED: $($summary.gitlab_project)" -ForegroundColor Red
    Write-Host "  Error: Check logs in $($_.FullName)/logs/"
  }
}
```

## API Reference

### Functions with Sync Support

| Function | Sync Parameter | Description |
|----------|----------------|-------------|
| `New-MigrationPreReport` | `-AllowSync` | Validates migration readiness, allows existing repos |
| `Ensure-Repo` | `-AllowExisting` | Returns existing repo info instead of error |
| `Migrate-One` | `-AllowSync` | Executes single project sync |
| `Bulk-Migrate-FromConfig` | `-AllowSync` | Executes bulk config sync |
| `Bulk-Migrate` | `-AllowSync` | Executes bulk template sync |

### Modified Validation Logic

**Without Sync:**
```powershell
if ($repoExists) {
  $report.blocking_issues += "Repository already exists"
  $report.ready_to_migrate = $false
}
```

**With Sync:**
```powershell
if ($repoExists -and -not $AllowSync) {
  $report.blocking_issues += "Repository already exists (use -AllowSync to update)"
  $report.ready_to_migrate = $false
} elseif ($repoExists -and $AllowSync) {
  $report.info_messages += "Sync mode: Will update existing repository"
  $report.sync_mode = $true
}
```

## See Also

- [README.md](README.md) - Main documentation with sync mode section
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Quick command examples including sync
- [BULK_MIGRATION_CONFIG.md](BULK_MIGRATION_CONFIG.md) - Bulk configuration format
- [CHANGELOG.md](CHANGELOG.md) - Version history including sync feature

