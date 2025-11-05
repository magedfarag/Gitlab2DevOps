# CLI Usage Examples for Gitlab2DevOps.ps1
# =========================================
# This file demonstrates all CLI modes for automation scenarios.
#
# Documentation: See docs/cli-usage.md for detailed CLI reference

# Prerequisites:
# --------------
# 1. Set environment variables (recommended):
#    - ADO_COLLECTION_URL, ADO_PAT, GITLAB_BASE_URL, GITLAB_PAT
# 2. Or use parameter-based credentials (see Example 12)
# 3. Ensure Git 2.0+ is installed and in PATH
# 4. PowerShell 5.1+ or PowerShell Core 7+

# Example 1: Preflight - Download and analyze GitLab project
# ----------------------------------------------------------
# Downloads the repository, generates preflight report, and validates for migration readiness
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/my-project"

# Example 2: Initialize - Create Azure DevOps project with policies
# -----------------------------------------------------------------
# Creates ADO project, sets up repository, and configures branch policies
.\Gitlab2DevOps.ps1 -Mode Initialize -Source "group/my-project" -Project "MyProject"

# Example 3: Migrate - Full migration (Preflight + Initialize + Push)
# -------------------------------------------------------------------
# Complete migration from GitLab to Azure DevOps
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject"

# Example 4: Migrate with Force - Override preflight blocking issues
# ------------------------------------------------------------------
# Bypass preflight checks and proceed with migration even if blocking issues exist
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject" -Force

# Example 5: Migrate with Replace - Recreate existing repository
# --------------------------------------------------------------
# Delete and recreate ADO repository if it already has commits
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject" -Replace

# Example 6: Migrate with AllowSync - Update existing repository
# --------------------------------------------------------------
# Allow pushing to existing repository (sync mode)
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject" -AllowSync

# Example 7: Migrate with WhatIf - Preview without executing
# ----------------------------------------------------------
# Show what would be done without making changes
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject" -WhatIf

# Example 8: Migrate with Confirm - Interactive approval
# ------------------------------------------------------
# Prompt before each destructive operation
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject" -Confirm

# Example 9: Migrate with Force + Replace - Full override
# -------------------------------------------------------
# Force migration and recreate repository (use with caution!)
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/my-project" -Project "MyProject" -Force -Replace -Confirm

# Example 10: BulkMigrate from Config File - Migrate multiple projects
# --------------------------------------------------------------------
# Migrate multiple repositories using a configuration file
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ConfigFile "bulk-migration-config.json"

# Example 11: BulkMigrate with Sync - Update existing repositories
# ----------------------------------------------------------------
# Bulk sync mode: Update all repositories in config file
.\Gitlab2DevOps.ps1 -Mode BulkMigrate -ConfigFile "bulk-migration-config.json" -AllowSync

# Example 12: DryRun Preview - Preview migration without execution
# ---------------------------------------------------------------
# Generate preview of what will be migrated (console or HTML)
.\Gitlab2DevOps.ps1 -Mode DryRun -ConfigFile "bulk-migration-config.json"

# Save preview to HTML file
.\Gitlab2DevOps.ps1 -Mode DryRun -ConfigFile "bulk-migration-config.json" -OutputPath "preview.html"

# Example 13: Custom Process Template - Use Scrum instead of Agile
# ----------------------------------------------------------------
.\Gitlab2DevOps.ps1 `
    -Mode Initialize `
    -Source "group/my-project" `
    -Project "MyScrumProject" `
    -ProcessTemplate "Scrum"

# Example 14: Override configuration with explicit parameters
# ----------------------------------------------------------
.\Gitlab2DevOps.ps1 `
    -Mode Migrate `
    -Source "group/my-project" `
    -Project "MyProject" `
    -CollectionUrl "https://dev.azure.com/myorg" `
    -AdoPat $env:CUSTOM_ADO_PAT `
    -GitLabBaseUrl "https://gitlab.custom.com" `
    -GitLabToken $env:CUSTOM_GITLAB_PAT `
    -AdoApiVersion "7.1" `
    -BuildDefinitionId 123 `
    -SonarStatusContext "sonarqube"

# Example 15: Skip SSL certificate validation (on-premise servers)
# ----------------------------------------------------------------
# For on-premise Azure DevOps with self-signed certificates
.\Gitlab2DevOps.ps1 `
    -Mode Migrate `
    -Source "group/my-project" `
    -Project "MyProject" `
    -SkipCertificateCheck

# Example 16: Scheduled Sync with Error Handling
# ----------------------------------------------
# Perfect for scheduled tasks to keep repositories in sync
try {
    $result = .\Gitlab2DevOps.ps1 `
        -Mode Migrate `
        -Source "group/my-project" `
        -Project "MyProject" `
        -AllowSync `
        -ErrorAction Stop
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Sync completed successfully" -ForegroundColor Green
        # Send success notification
        Send-MailMessage -To "team@company.com" -Subject "Migration Sync Success" -Body "Synced successfully"
    }
}
catch {
    Write-Host "❌ Sync failed: $_" -ForegroundColor Red
    # Send failure notification
    Send-MailMessage -To "team@company.com" -Subject "Migration Sync Failed" -Body "Error: $_"
    exit 1
}

# CI/CD Pipeline Examples
# =======================

# GitHub Actions / Azure Pipelines:
# ---------------------------------
# - name: Migrate GitLab project
#   run: |
#     .\Gitlab2DevOps.ps1 `
#       -Mode Migrate `
#       -Source "${{ env.GITLAB_PROJECT }}" `
#       -Project "${{ env.ADO_PROJECT }}" `
#       -Force

# Jenkins:
# --------
# powershell """
#   .\Gitlab2DevOps.ps1 `
#     -Mode Migrate `
#     -Source "${env.GITLAB_PROJECT}" `
#     -Project "${env.ADO_PROJECT}" `
#     -Force
# """

# GitLab CI:
# ----------
# script:
#   - |
#     pwsh -Command "
#       .\Gitlab2DevOps.ps1 `
#         -Mode Migrate `
#         -Source '$CI_PROJECT_PATH' `
#         -Project '$ADO_PROJECT_NAME' `
#         -Force
#     "

# Notes:
# ------
# 1. Interactive mode (default): Run without -Mode parameter for menu-driven workflow
# 2. CLI mode: Use -Mode parameter for automation and scripting
# 3. WhatIf/Confirm: Leverage PowerShell's native ShouldProcess support
# 4. Force: Use carefully - bypasses safety checks
# 5. Replace: Use with caution - deletes existing ADO repository
# 6. Environment variables: Preferred method for storing credentials securely
