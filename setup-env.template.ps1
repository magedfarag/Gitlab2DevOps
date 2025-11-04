# Example Environment Configuration Script
# Copy this file to setup-env.ps1 and customize with your actual values
# DO NOT commit setup-env.ps1 to version control!

# ===================================================================
# Azure DevOps Configuration
# ===================================================================

# Azure DevOps Server URL (on-premises) or Azure DevOps Services URL
# Examples:
#   On-premises: https://devops.example.com/DefaultCollection
#   Cloud:       https://dev.azure.com/your-organization
$env:ADO_COLLECTION_URL = "https://dev.azure.com/your-organization"

# Azure DevOps Personal Access Token (PAT)
# Create at: https://dev.azure.com/your-organization/_usersSettings/tokens
# Required scopes:
#   - Project and team: Read, write, & manage
#   - Code: Full
#   - Work items: Read, write, & manage
#   - Graph: Read
#   - Security: Manage
$env:ADO_PAT = "your-azure-devops-pat-here"

# ===================================================================
# GitLab Configuration
# ===================================================================

# GitLab instance URL
# Examples:
#   GitLab.com:  https://gitlab.com
#   Self-hosted: https://gitlab.example.com
$env:GITLAB_BASE_URL = "https://gitlab.com"

# GitLab Personal Access Token
# Create at: https://gitlab.com/-/profile/personal_access_tokens
# Required scopes:
#   - api (for project access)
#   - read_repository (for Git operations)
$env:GITLAB_PAT = "your-gitlab-pat-here"

# ===================================================================
# Optional Configuration
# ===================================================================

# Azure DevOps API Version (if needed for older servers)
# Supported values: 6.0, 7.0, 7.1 (default)
# $env:ADO_API_VERSION = "7.1"

# ===================================================================
# Validation
# ===================================================================

Write-Host "Environment variables configured:" -ForegroundColor Green
Write-Host "  ADO_COLLECTION_URL: $env:ADO_COLLECTION_URL" -ForegroundColor Cyan
Write-Host "  ADO_PAT: $(if ($env:ADO_PAT) { '***' + $env:ADO_PAT.Substring($env:ADO_PAT.Length - 4) } else { 'NOT SET' })" -ForegroundColor Cyan
Write-Host "  GITLAB_BASE_URL: $env:GITLAB_BASE_URL" -ForegroundColor Cyan
Write-Host "  GITLAB_PAT: $(if ($env:GITLAB_PAT) { '***' + $env:GITLAB_PAT.Substring($env:GITLAB_PAT.Length - 4) } else { 'NOT SET' })" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now run the migration script:" -ForegroundColor Yellow
Write-Host "  .\devops.ps1 -Mode preflight -GitLabProject 'mygroup/myproject' -AdoProject 'MyProject'" -ForegroundColor White
Write-Host ""
Write-Host "Security Reminder:" -ForegroundColor Red
Write-Host "  - Never commit setup-env.ps1 with real credentials" -ForegroundColor Red
Write-Host "  - Use .gitignore to exclude your environment files" -ForegroundColor Red
Write-Host "  - Rotate PATs regularly" -ForegroundColor Red
