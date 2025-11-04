# Advanced Features Usage Examples

This guide demonstrates the new advanced features in Gitlab2DevOps v2.0.0.

## Table of Contents
- [Progress Tracking](#progress-tracking)
- [Telemetry and Metrics](#telemetry-and-metrics)
- [Dry-Run Preview](#dry-run-preview)
- [API Error Reference](#api-error-reference)

---

## Progress Tracking

The `ProgressTracking` module provides visual progress bars for long-running operations.

### Basic Progress Tracking

```powershell
# Import the module
Import-Module .\modules\ProgressTracking.psm1

# Start tracking bulk migration
$progress = Start-MigrationProgress `
    -Activity "Bulk Migration" `
    -TotalItems 10 `
    -Status "Initializing..."

# Update progress for each item
for ($i = 1; $i -le 10; $i++) {
    Update-MigrationProgress `
        -Context $progress `
        -CurrentItem $i `
        -Status "Migrating project-$i" `
        -CurrentOperation "Pushing to Azure DevOps"
    
    # Your migration code here
    Start-Sleep -Seconds 2
}

# Complete progress
Complete-MigrationProgress -Context $progress
```

### Git Clone with Progress

```powershell
# Clone with automatic progress monitoring
Invoke-GitCloneWithProgress `
    -Url "https://gitlab.com/mygroup/large-repo.git" `
    -Destination "C:\temp\large-repo" `
    -Mirror `
    -SizeEstimateMB 500
```

### Integration with Migration Scripts

```powershell
# Example: Bulk migration with progress
$projects = @("group/proj1", "group/proj2", "group/proj3")
$progress = Start-MigrationProgress `
    -Activity "Migrating Projects" `
    -TotalItems $projects.Count `
    -Status "Starting bulk migration"

for ($i = 0; $i -lt $projects.Count; $i++) {
    $project = $projects[$i]
    
    Update-MigrationProgress `
        -Context $progress `
        -CurrentItem ($i + 1) `
        -Status "Migrating: $project" `
        -CurrentOperation "Cloning from GitLab"
    
    Invoke-SingleMigration -SrcPath $project -DestProject "MyDevOpsProject"
}

Complete-MigrationProgress -Context $progress
```

---

## Telemetry and Metrics

The `Telemetry` module provides opt-in analytics for migration operations. **All data is stored locally only.**

### Enable Telemetry

```powershell
# Import the module
Import-Module .\modules\Telemetry.psm1

# Start telemetry session (opt-in)
$session = Initialize-Telemetry -Enabled -SessionName "Production-Migration-2024"

# Session started: Production-Migration-2024 (ID: abc-123-def)
# Data will be saved locally for analysis
```

### Record Migration Events

```powershell
# Record migration start
Record-TelemetryEvent `
    -EventType "MigrationStart" `
    -Project "my-project" `
    -Data @{ SizeMB = 150; LfsSizeMB = 25 }

# Record migration completion
Record-TelemetryEvent `
    -EventType "MigrationComplete" `
    -Project "my-project" `
    -Data @{ 
        Status = "Success"
        DurationSeconds = 125
        RepositorySizeMB = 150
    }
```

### Record Metrics

```powershell
# Record migration duration
Record-TelemetryMetric `
    -MetricName "MigrationDurationSeconds" `
    -Value 125.5 `
    -Unit "seconds" `
    -Tags @{ Project = "my-project"; Size = "Medium" }

# Record repository size
Record-TelemetryMetric `
    -MetricName "RepositorySizeMB" `
    -Value 150.2 `
    -Unit "MB" `
    -Tags @{ Project = "my-project" }

# Record API response time
Record-TelemetryMetric `
    -MetricName "ApiResponseTimeMs" `
    -Value 250 `
    -Unit "ms" `
    -Tags @{ Endpoint = "/_apis/projects"; Method = "GET" }
```

### Record Errors

```powershell
# Record migration error
Record-TelemetryError `
    -ErrorMessage "Git clone failed: timeout" `
    -ErrorType "GitError" `
    -Context @{ 
        Project = "my-project"
        Size = 500
        Operation = "Clone"
    }
```

### Record API Calls

```powershell
# Record API call performance
Record-TelemetryApiCall `
    -Method "GET" `
    -Endpoint "/_apis/projects" `
    -DurationMs 250 `
    -StatusCode 200 `
    -Success
```

### Export Telemetry Data

```powershell
# Export to JSON for detailed analysis
Export-TelemetryData `
    -OutputPath "C:\telemetry\migration-session.json" `
    -Format JSON

# Export metrics to CSV for Excel/PowerBI
Export-TelemetryData `
    -OutputPath "C:\telemetry\metrics.csv" `
    -Format CSV

# View session statistics
$stats = Get-TelemetryStatistics
$stats | Format-List
```

### Complete Example

```powershell
# Full telemetry-enabled migration script
Import-Module .\modules\Core.Rest.psm1
Import-Module .\modules\Telemetry.psm1
Import-Module .\modules\Migration.psm1

# Initialize
Initialize-CoreRest -ConfigPath "migration.config.json"
$session = Initialize-Telemetry -Enabled -SessionName "Q4-Migration-Batch"

# Perform migrations with telemetry
$projects = @("group/proj1", "group/proj2", "group/proj3")

foreach ($project in $projects) {
    $startTime = Get-Date
    
    Record-TelemetryEvent `
        -EventType "MigrationStart" `
        -Project $project
    
    try {
        Invoke-SingleMigration -SrcPath $project -DestProject "ConsolidatedProject"
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        Record-TelemetryEvent `
            -EventType "MigrationComplete" `
            -Project $project `
            -Data @{ Status = "Success"; DurationSeconds = $duration }
        
        Record-TelemetryMetric `
            -MetricName "MigrationDurationSeconds" `
            -Value $duration `
            -Tags @{ Project = $project; Status = "Success" }
    }
    catch {
        Record-TelemetryError `
            -ErrorMessage $_.ToString() `
            -ErrorType "MigrationError" `
            -Context @{ Project = $project }
        
        Record-TelemetryEvent `
            -EventType "MigrationFailed" `
            -Project $project `
            -Data @{ Error = $_.ToString() }
    }
}

# Export results
Export-TelemetryData -OutputPath "migration-results.json" -Format JSON
```

---

## Dry-Run Preview

The `DryRunPreview` module generates comprehensive preview reports before migration.

### Console Preview

```powershell
# Import module
Import-Module .\modules\DryRunPreview.psm1

# Generate console preview
$preview = New-MigrationPreview `
    -GitLabProjects @("group/proj1", "group/proj2") `
    -DestinationProject "MyDevOpsProject" `
    -OutputFormat Console
```

**Output:**
```
=== MIGRATION PREVIEW ===

Destination: MyDevOpsProject
Projects: 2
Total Size: 250.5 MB
LFS Data: 15.2 MB
Estimated Duration: 35 minutes

⚠️ Warnings:
   ℹ️ Git LFS required for group/proj1 (LFS: 15.2 MB)

📦 Projects to Migrate:

  group/proj1 → proj1
    Size: 150.2 MB
    LFS: 15.2 MB
    Branch: main
    Estimated: ~20 minutes

  group/proj2 → proj2
    Size: 100.3 MB
    Branch: master
    Estimated: ~15 minutes

=== Operations Summary ===
  ✅ Use existing project: MyDevOpsProject
  Total repositories to migrate: 2
  Total data transfer: 250.5 MB
  Total LFS data: 15.2 MB
  Estimated duration: 35 minutes
```

### JSON Preview

```powershell
# Export preview to JSON
$preview = New-MigrationPreview `
    -GitLabProjects @("group/proj1", "group/proj2", "group/proj3") `
    -DestinationProject "ConsolidatedProject" `
    -OutputFormat JSON `
    -OutputPath "migration-preview.json"

# Load and analyze
$data = Get-Content migration-preview.json | ConvertFrom-Json
Write-Host "Total estimated time: $($data.EstimatedDuration) minutes"
```

### HTML Preview Report

```powershell
# Generate beautiful HTML report
$preview = New-MigrationPreview `
    -GitLabProjects @("group/proj1", "group/proj2", "group/proj3") `
    -DestinationProject "ProductionMigration" `
    -OutputFormat HTML `
    -OutputPath "preview-report.html"

# Open in browser
Start-Process preview-report.html
```

The HTML report includes:
- **Summary cards** with key metrics
- **Color-coded project table** (green=normal, yellow=large repos)
- **Prerequisites section** highlighting requirements
- **Warnings section** with actionable alerts
- **Responsive design** for mobile/desktop viewing

### Bulk Migration Preview

```powershell
# Preview from bulk preparation template
$migrationsDir = Get-MigrationsDirectory
$templateFile = Join-Path $migrationsDir "bulk-prep-MyProject" "bulk-migration-template.json"
$template = Get-Content $templateFile | ConvertFrom-Json

# Extract project paths
$projectPaths = $template.projects | Where-Object { $_.preparation_status -eq "SUCCESS" } | 
    Select-Object -ExpandProperty gitlab_path

# Generate preview
New-MigrationPreview `
    -GitLabProjects $projectPaths `
    -DestinationProject $template.destination_project `
    -OutputFormat HTML `
    -OutputPath "bulk-migration-preview.html"
```

---

## API Error Reference

The comprehensive API error catalog is available at `docs/api-errors.md`.

### Using the Error Catalog

When you encounter an error, refer to the catalog for:
1. **Error cause** - Why it happened
2. **Resolution steps** - How to fix it
3. **Prevention tips** - How to avoid it

### Common Error Scenarios

#### GitLab 401 Unauthorized

```powershell
# Error received
# 401 Unauthorized

# Resolution from catalog:
# 1. Check token in migration.config.json
# 2. Verify token hasn't expired
# 3. Regenerate if needed
# 4. Ensure token has 'api' scope

# Test token
Test-GitLabAuth
```

#### Azure DevOps 409 Conflict

```powershell
# Error: Project already exists

# Resolution from catalog:
# Use idempotent Ensure-* functions

# Instead of manual creation:
Ensure-AdoProject "MyProject"  # Handles both create and exists scenarios

# For repository sync:
Invoke-SingleMigration -SrcPath "group/proj" -DestProject "MyProject" -AllowSync
```

#### Git Clone Timeout

```powershell
# Error: fatal: the remote end hung up unexpectedly

# Resolution from catalog:
# 1. Increase git timeout
git config --global http.timeout 300
git config --global http.postBuffer 524288000

# 2. Check repository size in preflight
Prepare-GitLab "group/large-repo"
# Review: migrations/large-repo/reports/preflight-report.json

# 3. Schedule during off-peak hours
# 4. Use progress tracking to monitor
Invoke-GitCloneWithProgress -Url "..." -Destination "..." -SizeEstimateMB 500
```

### Diagnostic Commands

```powershell
# Test GitLab connectivity
Test-GitLabAuth

# Test Azure DevOps connectivity
$projects = Get-AdoProjectList -RefreshCache

# Enable verbose logging
$VerbosePreference = "Continue"
Invoke-SingleMigration -SrcPath "..." -DestProject "..." -Verbose

# Check logs
Get-Content migrations/project/logs/migration-*.log
```

---

## Integration Examples

### Complete Migration with All Features

```powershell
# Full-featured migration script
Import-Module .\modules\Core.Rest.psm1
Import-Module .\modules\ProgressTracking.psm1
Import-Module .\modules\Telemetry.psm1
Import-Module .\modules\DryRunPreview.psm1
Import-Module .\modules\Migration.psm1

# Initialize
Initialize-CoreRest -ConfigPath "migration.config.json"

# Define projects
$projects = @("group/proj1", "group/proj2", "group/proj3")
$destProject = "ConsolidatedProject"

# Step 1: Generate preview report
Write-Host "Generating preview report..." -ForegroundColor Cyan
$preview = New-MigrationPreview `
    -GitLabProjects $projects `
    -DestinationProject $destProject `
    -OutputFormat HTML `
    -OutputPath "migration-preview-$(Get-Date -Format 'yyyyMMdd').html"

# Step 2: Review and confirm
Write-Host "`nEstimated duration: $($preview.EstimatedDuration) minutes"
$confirm = Read-Host "Proceed with migration? (y/N)"
if ($confirm -notmatch '^[Yy]') {
    Write-Host "Migration cancelled"
    exit
}

# Step 3: Start telemetry
$session = Initialize-Telemetry -Enabled -SessionName "Migration-$(Get-Date -Format 'yyyyMMdd-HHmm')"

# Step 4: Execute with progress tracking
$progress = Start-MigrationProgress `
    -Activity "Migrating to $destProject" `
    -TotalItems $projects.Count `
    -Status "Starting migrations"

for ($i = 0; $i -lt $projects.Count; $i++) {
    $project = $projects[$i]
    
    Update-MigrationProgress `
        -Context $progress `
        -CurrentItem ($i + 1) `
        -Status "Migrating: $project"
    
    Record-TelemetryEvent -EventType "MigrationStart" -Project $project
    $startTime = Get-Date
    
    try {
        Invoke-SingleMigration -SrcPath $project -DestProject $destProject
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Record-TelemetryMetric `
            -MetricName "MigrationDurationSeconds" `
            -Value $duration `
            -Tags @{ Project = $project; Status = "Success" }
        
        Record-TelemetryEvent `
            -EventType "MigrationComplete" `
            -Project $project `
            -Data @{ Status = "Success"; DurationSeconds = $duration }
    }
    catch {
        Record-TelemetryError `
            -ErrorMessage $_.ToString() `
            -ErrorType "MigrationError" `
            -Context @{ Project = $project }
    }
}

Complete-MigrationProgress -Context $progress

# Step 5: Export telemetry
Export-TelemetryData `
    -OutputPath "telemetry-$(Get-Date -Format 'yyyyMMdd-HHmm').json" `
    -Format JSON

# Step 6: Show summary
$stats = Get-TelemetryStatistics
Write-Host "`n=== MIGRATION COMPLETE ===" -ForegroundColor Green
Write-Host "Duration: $($stats.DurationMinutes) minutes"
Write-Host "Events: $($stats.EventCount)"
Write-Host "Errors: $($stats.ErrorStatistics.TotalErrors)"
```

---

## Next Steps

- Review [API Error Catalog](../docs/api-errors.md) for troubleshooting
- See [CLI Usage Guide](cli-usage.md) for command-line examples
- Check [Configuration Guide](../docs/configuration.md) for setup details

**Version**: 2.0.0  
**Last Updated**: 2024-11-04
