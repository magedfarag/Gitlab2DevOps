# Environment Configuration Guide

This guide explains how to use `.env` files for configuration instead of environment variables or command-line parameters.

## Quick Start

1. **Copy the example file:**
   ```powershell
   Copy-Item .env.example .env
   ```

2. **Edit `.env` with your credentials:**
   ```bash
   # Open in your favorite editor
   notepad .env
   # or
   code .env
   ```

3. **Fill in your values:**
   ```bash
   ADO_COLLECTION_URL=https://dev.azure.com/your-organization
   ADO_PAT=your-actual-pat-here
   GITLAB_BASE_URL=https://gitlab.com
   GITLAB_PAT=your-actual-token-here
   ```

4. **Run the migration script:**
   ```powershell
   .\Gitlab2DevOps.ps1
   ```
   
   The script automatically detects and loads `.env` files!

---

## Configuration Priority

Configuration is loaded in the following priority order (highest to lowest):

1. **Command-line parameters** (highest priority)
   ```powershell
   .\Gitlab2DevOps.ps1 -AdoPat "override-value"
   ```

2. **Environment variables**
   ```powershell
   $env:ADO_PAT = "env-value"
   ```

3. **.env.local file** (local overrides, gitignored)
   ```bash
   # .env.local
   ADO_PAT=local-override
   ```

4. **.env file** (default configuration, gitignored)
   ```bash
   # .env
   ADO_PAT=default-value
   ```

5. **Script defaults** (lowest priority)

---

## File Formats

### Standard .env Format

```bash
# Comments start with #
# Empty lines are ignored

# Simple key=value pairs
ADO_COLLECTION_URL=https://dev.azure.com/my-org
GITLAB_BASE_URL=https://gitlab.com

# Values with spaces (use quotes)
PROJECT_NAME="My Project Name"

# Multi-word values
DESCRIPTION="This is a longer description with spaces"

# No quotes needed for URLs
ADO_PAT=abcdef123456789
GITLAB_PAT=glpat-xyz123abc456
```

### Variable Expansion

You can reference other variables using `${VAR}` syntax:

```bash
# Base configuration
ADO_ORG=my-organization
ADO_COLLECTION_URL=https://dev.azure.com/${ADO_ORG}

# GitLab project
GITLAB_GROUP=engineering
GITLAB_PROJECT=app-backend
GITLAB_FULL_PATH=${GITLAB_GROUP}/${GITLAB_PROJECT}
```

### Supported Formats

| Format | Example | Notes |
|--------|---------|-------|
| Simple | `KEY=value` | Most common |
| Quoted | `KEY="value"` | For values with spaces |
| Single quotes | `KEY='value'` | Literal strings |
| Variable expansion | `KEY=${OTHER}` | References other vars |
| Comments | `# Comment` | Start with # |
| Empty lines | | Ignored |

---

## Required Configuration

### Minimal .env File

```bash
# Azure DevOps
ADO_COLLECTION_URL=https://dev.azure.com/your-org
ADO_PAT=your-ado-pat-here

# GitLab
GITLAB_BASE_URL=https://gitlab.com
GITLAB_PAT=your-gitlab-token-here
```

### Full .env File (All Options)

```bash
# ============================
# Azure DevOps Configuration
# ============================
ADO_COLLECTION_URL=https://dev.azure.com/your-org
ADO_PAT=your-ado-pat-here
ADO_API_VERSION=7.1

# ============================
# GitLab Configuration
# ============================
GITLAB_BASE_URL=https://gitlab.com
GITLAB_PAT=your-gitlab-token-here

# ============================
# Optional Settings
# ============================
SKIP_CERTIFICATE_CHECK=false
DEFAULT_BRANCH=main
GIT_TIMEOUT=600

# Telemetry (opt-in)
TELEMETRY_ENABLED=false
TELEMETRY_SESSION=Migration-2024

# Logging
LOG_LEVEL=Info
LOG_DIR=./logs
```

---

## Security Best Practices

### ✅ DO

- ✅ Keep `.env` files **out of version control** (already in .gitignore)
- ✅ Use `.env.example` as a template (no real secrets)
- ✅ Use different `.env.local` for local development
- ✅ Set restrictive file permissions:
  ```powershell
  # Windows: Remove inheritance and grant only your user
  icacls .env /inheritance:r /grant:r "$env:USERNAME:F"
  ```
- ✅ Rotate tokens regularly
- ✅ Use tokens with **minimum required permissions**

### ❌ DON'T

- ❌ **Never** commit `.env` files with real credentials
- ❌ Don't share `.env` files via email/chat
- ❌ Don't store `.env` files in cloud storage
- ❌ Don't use production credentials in `.env.example`
- ❌ Don't grant broad token permissions

---

## Multiple Environment Support

### Development vs Production

Create separate files for different environments:

```
.env.example      # Template (committed to git)
.env              # Default (gitignored)
.env.local        # Local overrides (gitignored)
.env.development  # Dev environment (gitignored)
.env.production   # Production (gitignored)
```

### Loading Specific Environment

```powershell
# Load production config
.\Gitlab2DevOps.ps1 -EnvFile ".env.production"

# Load development config
.\Gitlab2DevOps.ps1 -EnvFile ".env.development"

# Load from custom location
.\Gitlab2DevOps.ps1 -EnvFile "C:\secure\config.env"
```

---

## PowerShell Module Usage

### Manual Loading

```powershell
# Import the module
Import-Module .\modules\core\EnvLoader.psm1

# Load .env and get configuration as hashtable
$config = Import-DotEnvFile -Path ".env"
Write-Host "GitLab URL: $($config.GITLAB_BASE_URL)"

# Load and set environment variables
Import-DotEnvFile -Path ".env" -SetEnvironmentVariables
Write-Host "GitLab URL: $($env:GITLAB_BASE_URL)"

# Load multiple files with priority
Import-DotEnvFile -Path @(".env", ".env.local") -SetEnvironmentVariables
```

### Create Template

```powershell
# Generate .env.example
New-DotEnvTemplate

# Create .env file (use with caution!)
New-DotEnvTemplate -Path ".env" -Force
```

### Validate Configuration

```powershell
$config = Import-DotEnvFile -Path ".env"

# Check required keys
$isValid = Test-DotEnvConfig -Config $config -RequiredKeys @(
    'ADO_PAT',
    'GITLAB_PAT',
    'ADO_COLLECTION_URL',
    'GITLAB_BASE_URL'
)

if (-not $isValid) {
    Write-Error "Missing required configuration!"
    exit 1
}
```

---

## Troubleshooting

### Configuration Not Loading

**Problem**: `.env` file exists but values aren't being used.

**Solutions**:
1. Check file name is exactly `.env` (no extra extensions)
2. Verify file is in the same directory as `Gitlab2DevOps.ps1`
3. Check for syntax errors (no spaces around `=`)
4. Ensure values don't have trailing spaces

```powershell
# Debug: Show what would be loaded
Import-Module .\modules\core\EnvLoader.psm1
$config = Import-DotEnvFile -Path ".env" -Verbose
$config | Format-Table -AutoSize
```

### File Not Found

**Problem**: "File not found: .env"

**Solutions**:
1. Create the file: `Copy-Item .env.example .env`
2. Check you're in the correct directory
3. Verify file isn't hidden

```powershell
# List all files including hidden
Get-ChildItem -Force | Where-Object Name -like ".env*"
```

### Values Not Overriding

**Problem**: Command-line parameters or environment variables take precedence.

**Understanding Priority**:
```powershell
# Highest priority - always used
.\Gitlab2DevOps.ps1 -AdoPat "command-line-value"

# Next priority
$env:ADO_PAT = "environment-value"
.\Gitlab2DevOps.ps1

# Lowest priority - only used if not set above
# .env file: ADO_PAT=env-file-value
```

### Variable Expansion Not Working

**Problem**: `${VAR}` not being replaced.

**Check**:
1. Variable is defined before use
2. No circular references
3. Proper syntax: `${VAR}` not `$(VAR)`

```bash
# ✅ Correct order
BASE_URL=https://example.com
API_URL=${BASE_URL}/api

# ❌ Wrong order (BASE_URL not yet defined)
API_URL=${BASE_URL}/api
BASE_URL=https://example.com
```

---

## Examples

### Example 1: Basic Setup

```powershell
# 1. Copy template
Copy-Item .env.example .env

# 2. Edit .env
notepad .env

# 3. Run migration
.\Gitlab2DevOps.ps1
```

### Example 2: Multiple Projects

```powershell
# Create separate config for each project
Copy-Item .env.example .env.project-a
Copy-Item .env.example .env.project-b

# Edit each file with project-specific credentials
# ...

# Run migrations
.\Gitlab2DevOps.ps1 -EnvFile ".env.project-a"
.\Gitlab2DevOps.ps1 -EnvFile ".env.project-b"
```

### Example 3: CI/CD Pipeline

```yaml
# Azure Pipelines example
steps:
- task: PowerShell@2
  displayName: 'Setup Environment'
  inputs:
    targetType: 'inline'
    script: |
      # Create .env from pipeline variables
      @"
      ADO_COLLECTION_URL=$(ADO_COLLECTION_URL)
      ADO_PAT=$(ADO_PAT)
      GITLAB_BASE_URL=$(GITLAB_BASE_URL)
      GITLAB_PAT=$(GITLAB_PAT)
      "@ | Out-File -FilePath .env -Encoding UTF8

- task: PowerShell@2
  displayName: 'Run Migration'
  inputs:
    filePath: 'Gitlab2DevOps.ps1'
```

### Example 4: Secure Local Development

```powershell
# 1. Create .env with team-shared non-sensitive defaults
# .env (committed to git with .env.example)
ADO_COLLECTION_URL=https://dev.azure.com/dev-team
GITLAB_BASE_URL=https://gitlab-dev.example.com
TELEMETRY_ENABLED=false

# 2. Create .env.local with your personal tokens (gitignored)
# .env.local
ADO_PAT=your-personal-token
GITLAB_PAT=your-gitlab-token

# 3. Run script - automatically loads both files
.\Gitlab2DevOps.ps1
```

---

## Migration from Environment Variables

If you're currently using environment variables, migration is easy:

### Old Method (Environment Variables)

```powershell
# setup-env.ps1
$env:ADO_COLLECTION_URL = "https://dev.azure.com/my-org"
$env:ADO_PAT = "my-pat"
$env:GITLAB_BASE_URL = "https://gitlab.com"
$env:GITLAB_PAT = "my-token"

.\Gitlab2DevOps.ps1
```

### New Method (.env File)

```powershell
# 1. Create .env file with same values
# .env
ADO_COLLECTION_URL=https://dev.azure.com/my-org
ADO_PAT=my-pat
GITLAB_BASE_URL=https://gitlab.com
GITLAB_PAT=my-token

# 2. Run directly (no setup script needed)
.\Gitlab2DevOps.ps1
```

### Hybrid Approach (Both)

You can use both methods simultaneously:

```powershell
# .env (shared team config)
ADO_COLLECTION_URL=https://dev.azure.com/my-org
GITLAB_BASE_URL=https://gitlab.com

# Environment variables (personal tokens)
$env:ADO_PAT = "my-personal-pat"
$env:GITLAB_PAT = "my-personal-token"

# Run script - combines both sources
.\Gitlab2DevOps.ps1
```

---

## References

- [.env file format specification](https://www.dotenv.org/)
- [GitLab Personal Access Tokens](https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html)
- [Azure DevOps Personal Access Tokens](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate)
- [PowerShell Environment Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables)

---

## See Also

- [README.md](../README.md) - Main documentation
- [Advanced Features](advanced-features.md) - Progress tracking, telemetry, etc.
- [API Error Catalog](api-errors.md) - Troubleshooting guide
