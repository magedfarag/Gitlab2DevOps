# CLI Usage Examples for Gitlab2DevOps.ps1
# =========================================
# This file demonstrates all CLI modes for automation scenarios.

# Prerequisites:
# - Set environment variables: ADO_COLLECTION_URL, ADO_PAT, GITLAB_BASE_URL, GITLAB_PAT
# - Or pass credentials explicitly via parameters

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

# Example 10: BulkPrepare - Prepare multiple projects
# ---------------------------------------------------
# Interactive workflow to download multiple GitLab projects
.\Gitlab2DevOps.ps1 -Mode BulkPrepare

# Example 11: BulkMigrate - Execute bulk migration
# ------------------------------------------------
# Migrate multiple projects from prepared template
.\Gitlab2DevOps.ps1 -Mode BulkMigrate

# Example 12: Override configuration with explicit parameters
# -----------------------------------------------------------
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

# Example 13: Skip SSL certificate validation (not recommended)
# -------------------------------------------------------------
.\Gitlab2DevOps.ps1 `
    -Mode Migrate `
    -Source "group/my-project" `
    -Project "MyProject" `
    -SkipCertificateCheck

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
