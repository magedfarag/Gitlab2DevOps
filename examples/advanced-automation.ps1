# Advanced CLI Automation Examples
# =================================
# This file demonstrates advanced automation scenarios and integration patterns.

# ========================================
# SCENARIO 1: Scheduled Daily Sync
# ========================================
# Keep Azure DevOps repositories synchronized with GitLab on a schedule

<#
.SYNOPSIS
    Daily sync script for maintaining repository synchronization
.DESCRIPTION
    Runs as a scheduled task to sync specified repositories from GitLab to Azure DevOps
#>

param(
    [string]$ConfigFile = "production-repos.json",
    [string]$LogPath = "logs/sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

# Start logging
Start-Transcript -Path $LogPath

Write-Host "=== Starting Daily Sync ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor Gray
Write-Host "Config: $ConfigFile" -ForegroundColor Gray

try {
    # Execute bulk sync
    .\Gitlab2DevOps.ps1 -Mode BulkMigrate -ConfigFile $ConfigFile -AllowSync -ErrorAction Stop
    
    # Parse results
    $summaries = Get-ChildItem migrations -Directory | ForEach-Object {
        $summaryPath = Join-Path $_.FullName "reports/migration-summary.json"
        if (Test-Path $summaryPath) {
            Get-Content $summaryPath | ConvertFrom-Json
        }
    }
    
    # Generate report
    $successCount = ($summaries | Where-Object { $_.status -eq "SUCCESS" }).Count
    $failCount = ($summaries | Where-Object { $_.status -eq "FAILED" }).Count
    
    Write-Host ""
    Write-Host "=== Sync Summary ===" -ForegroundColor Cyan
    Write-Host "✅ Successful: $successCount" -ForegroundColor Green
    Write-Host "❌ Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Gray" })
    
    # Email report
    $emailBody = @"
Daily Sync Report - $(Get-Date -Format 'yyyy-MM-dd')

Successful: $successCount
Failed: $failCount

Details:
$($summaries | Format-Table gitlab_project, status, migration_count | Out-String)

Full logs: $LogPath
"@
    
    Send-MailMessage `
        -To "devops@company.com" `
        -From "gitlab2devops@company.com" `
        -Subject "Daily Sync Report - $(Get-Date -Format 'yyyy-MM-dd')" `
        -Body $emailBody `
        -SmtpServer "smtp.company.com"
    
    Write-Host "✅ Daily sync completed successfully" -ForegroundColor Green
}
catch {
    Write-Host "❌ Daily sync failed: $_" -ForegroundColor Red
    
    # Send failure notification
    Send-MailMessage `
        -To "devops@company.com" `
        -From "gitlab2devops@company.com" `
        -Subject "⚠️ Daily Sync Failed - $(Get-Date -Format 'yyyy-MM-dd')" `
        -Body "Sync failed with error: $_`n`nSee logs: $LogPath" `
        -SmtpServer "smtp.company.com"
    
    exit 1
}
finally {
    Stop-Transcript
}

# ========================================
# SCENARIO 2: Conditional Migration
# ========================================
# Migrate only if changes are detected in GitLab

function Test-GitLabChanges {
    param([string]$ProjectPath, [string]$SinceDate)
    
    # Get recent commits from GitLab
    $encodedPath = [uri]::EscapeDataString($ProjectPath)
    $commits = Invoke-RestMethod `
        -Uri "$env:GITLAB_BASE_URL/api/v4/projects/$encodedPath/repository/commits?since=$SinceDate" `
        -Headers @{ "PRIVATE-TOKEN" = $env:GITLAB_PAT }
    
    return $commits.Count -gt 0
}

# Check for changes in last 24 hours
$projectPath = "group/my-project"
$sinceDate = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")

if (Test-GitLabChanges -ProjectPath $projectPath -SinceDate $sinceDate) {
    Write-Host "✅ Changes detected, starting sync..." -ForegroundColor Green
    .\Gitlab2DevOps.ps1 -Mode Migrate -Source $projectPath -Project "MyProject" -AllowSync
}
else {
    Write-Host "ℹ️ No changes detected, skipping sync" -ForegroundColor Yellow
}

# ========================================
# SCENARIO 3: Multi-Environment Sync
# ========================================
# Sync to different Azure DevOps environments (dev/staging/prod)

$environments = @{
    "dev" = @{
        CollectionUrl = "https://dev.azure.com/myorg-dev"
        PAT = $env:ADO_PAT_DEV
        Projects = @("DevProject1", "DevProject2")
    }
    "staging" = @{
        CollectionUrl = "https://dev.azure.com/myorg-staging"
        PAT = $env:ADO_PAT_STAGING
        Projects = @("StagingProject")
    }
    "prod" = @{
        CollectionUrl = "https://dev.azure.com/myorg-prod"
        PAT = $env:ADO_PAT_PROD
        Projects = @("ProdProject1", "ProdProject2", "ProdProject3")
    }
}

foreach ($env in $environments.Keys) {
    Write-Host ""
    Write-Host "=== Syncing to $env environment ===" -ForegroundColor Cyan
    
    $config = $environments[$env]
    
    foreach ($project in $config.Projects) {
        try {
            .\Gitlab2DevOps.ps1 `
                -Mode Migrate `
                -Source "group/$project" `
                -Project $project `
                -CollectionUrl $config.CollectionUrl `
                -AdoPat $config.PAT `
                -AllowSync `
                -ErrorAction Stop
            
            Write-Host "✅ Synced $project to $env" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Failed to sync $project to $env : $_" -ForegroundColor Red
        }
    }
}

# ========================================
# SCENARIO 4: Webhook-Triggered Migration
# ========================================
# Trigger migration from GitLab webhook

<#
Webhook Listener Setup:
1. Create a simple web server to receive GitLab webhooks
2. Parse webhook payload for push events
3. Trigger migration based on branch and project
#>

param(
    [Parameter(Mandatory)]
    [string]$WebhookPayloadPath  # JSON payload from GitLab webhook
)

$payload = Get-Content $WebhookPayloadPath | ConvertFrom-Json

# Only sync on main branch pushes
if ($payload.ref -eq "refs/heads/main") {
    $projectPath = $payload.project.path_with_namespace
    $projectName = $payload.project.name
    
    Write-Host "🔔 Webhook triggered for $projectPath" -ForegroundColor Cyan
    
    # Trigger sync
    .\Gitlab2DevOps.ps1 `
        -Mode Migrate `
        -Source $projectPath `
        -Project $projectName `
        -AllowSync
}
else {
    Write-Host "ℹ️ Ignoring push to branch: $($payload.ref)" -ForegroundColor Yellow
}

# ========================================
# SCENARIO 5: Parallel Bulk Migration
# ========================================
# Migrate multiple projects in parallel for faster completion

$projects = @(
    @{ Source = "group/project1"; Project = "Project1" }
    @{ Source = "group/project2"; Project = "Project2" }
    @{ Source = "group/project3"; Project = "Project3" }
    @{ Source = "group/project4"; Project = "Project4" }
)

# Run migrations in parallel (max 4 concurrent)
$projects | ForEach-Object -Parallel {
    $proj = $_
    
    Write-Host "Starting migration for $($proj.Project)..." -ForegroundColor Cyan
    
    & ".\Gitlab2DevOps.ps1" `
        -Mode Migrate `
        -Source $proj.Source `
        -Project $proj.Project `
        -AllowSync `
        -ErrorAction Continue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Completed: $($proj.Project)" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Failed: $($proj.Project)" -ForegroundColor Red
    }
} -ThrottleLimit 4

# ========================================
# SCENARIO 6: Migration with Validation
# ========================================
# Validate migration success by comparing commits

function Test-MigrationSuccess {
    param(
        [string]$GitLabProject,
        [string]$AdoProject,
        [string]$AdoRepo
    )
    
    # Get latest commit from GitLab
    $encodedPath = [uri]::EscapeDataString($GitLabProject)
    $gitlabCommit = Invoke-RestMethod `
        -Uri "$env:GITLAB_BASE_URL/api/v4/projects/$encodedPath/repository/commits/main" `
        -Headers @{ "PRIVATE-TOKEN" = $env:GITLAB_PAT }
    
    # Get latest commit from Azure DevOps
    $adoCommit = Invoke-RestMethod `
    -Uri "$env:ADO_COLLECTION_URL/$AdoProject/_apis/git/repositories/$AdoRepo/commits?api-version=7.2&`$top=1" `
        -Headers @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:ADO_PAT")))" }
    
    # Compare commit SHAs
    $gitlabSha = $gitlabCommit.id
    $adoSha = $adoCommit.value[0].commitId
    
    if ($gitlabSha -eq $adoSha) {
        Write-Host "✅ Migration validated: Latest commits match" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "⚠️ Warning: Commits don't match" -ForegroundColor Yellow
        Write-Host "  GitLab: $gitlabSha" -ForegroundColor Gray
        Write-Host "  ADO: $adoSha" -ForegroundColor Gray
        return $false
    }
}

# Migrate and validate
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "Project" -AllowSync

if (Test-MigrationSuccess -GitLabProject "group/project" -AdoProject "Project" -AdoRepo "project") {
    Write-Host "✅ Migration and validation successful" -ForegroundColor Green
}
else {
    Write-Host "❌ Validation failed - manual review needed" -ForegroundColor Red
    exit 1
}

# ========================================
# SCENARIO 7: Metrics and Monitoring
# ========================================
# Track migration metrics over time

function Write-MigrationMetrics {
    param([string]$MetricsFile = "migration-metrics.json")
    
    $summaries = Get-ChildItem migrations -Directory | ForEach-Object {
        $summaryPath = Join-Path $_.FullName "reports/migration-summary.json"
        if (Test-Path $summaryPath) {
            Get-Content $summaryPath | ConvertFrom-Json
        }
    }
    
    $metrics = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        total_projects = $summaries.Count
        successful_migrations = ($summaries | Where-Object { $_.status -eq "SUCCESS" }).Count
        failed_migrations = ($summaries | Where-Object { $_.status -eq "FAILED" }).Count
        total_sync_count = ($summaries | Measure-Object -Property migration_count -Sum).Sum
        avg_duration_minutes = ($summaries | Measure-Object -Property duration_minutes -Average).Average
        projects = $summaries | Select-Object gitlab_project, status, migration_count, last_sync
    }
    
    # Append to metrics file
    $allMetrics = if (Test-Path $MetricsFile) {
        Get-Content $MetricsFile | ConvertFrom-Json
    } else {
        @()
    }
    
    $allMetrics += $metrics
    $allMetrics | ConvertTo-Json -Depth 10 | Set-Content $MetricsFile
    
    Write-Host "📊 Metrics recorded to $MetricsFile" -ForegroundColor Cyan
}

# Execute migration and record metrics
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ConfigFile "bulk-migration-config.json" -AllowSync
Write-MigrationMetrics

# ========================================
# SCENARIO 8: Error Recovery and Retry
# ========================================
# Automatic retry with exponential backoff

function Invoke-MigrationWithRetry {
    param(
        [string]$Source,
        [string]$Project,
        [int]$MaxRetries = 3,
        [int]$InitialDelaySeconds = 60
    )
    
    $attempt = 0
    $delay = $InitialDelaySeconds
    
    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-Host "Attempt $attempt of $MaxRetries..." -ForegroundColor Cyan
        
        try {
            .\Gitlab2DevOps.ps1 `
                -Mode Migrate `
                -Source $Source `
                -Project $Project `
                -AllowSync `
                -ErrorAction Stop
            
            Write-Host "✅ Migration successful on attempt $attempt" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "❌ Attempt $attempt failed: $_" -ForegroundColor Red
            
            if ($attempt -lt $MaxRetries) {
                Write-Host "⏳ Waiting $delay seconds before retry..." -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
                $delay *= 2  # Exponential backoff
            }
        }
    }
    
    Write-Host "❌ All retry attempts exhausted" -ForegroundColor Red
    return $false
}

# Use retry logic
if (-not (Invoke-MigrationWithRetry -Source "group/project" -Project "Project")) {
    # Send critical alert
    Send-MailMessage `
        -To "devops-oncall@company.com" `
        -Subject "🚨 CRITICAL: Migration Failed After Retries" `
        -Body "Migration failed after all retry attempts. Manual intervention required."
    exit 1
}

# ========================================
# NOTES AND BEST PRACTICES
# ========================================

<#
Best Practices:
1. Always use environment variables for credentials
2. Implement proper error handling and logging
3. Use -AllowSync for scheduled syncs to avoid conflicts
4. Validate migrations after completion
5. Keep metrics for monitoring and troubleshooting
6. Use parallel execution for large-scale migrations
7. Implement retry logic for transient failures
8. Send notifications for failures requiring attention

Security Considerations:
- Never log credentials in plain text
- Rotate PATs regularly
- Use separate service accounts for automation
- Restrict PAT permissions to minimum required
- Secure webhook endpoints with authentication
- Encrypt sensitive configuration files

Performance Tips:
- Use parallel execution for bulk migrations (max 4-6 concurrent)
- Schedule large migrations during off-peak hours
- Monitor Azure DevOps API rate limits
- Cache preflight reports to avoid redundant downloads
- Use incremental sync instead of full re-migration

Troubleshooting:
- Check migration logs in migrations/<project>/logs/
- Review migration summaries in migrations/<project>/reports/
- Validate environment variables are set correctly
- Ensure network connectivity to both GitLab and Azure DevOps
- Verify PAT permissions and expiration dates
#>
