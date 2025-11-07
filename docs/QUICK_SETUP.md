# Quick Setup Guide - Using .env File

This guide will help you set up the migration tool using .env files (recommended method).

## Why Use .env Files?

✅ **Security**: Never commit credentials to version control  
✅ **Simplicity**: One file for all configuration  
✅ **Flexibility**: Easy to switch between environments (.env.local, .env.production)  
✅ **Team-Friendly**: Share .env.example template without exposing secrets  
✅ **Clean History**: Credentials don't appear in shell history  

---

## Step 1: Create Your .env File

```powershell
# Copy the template
Copy-Item .env.example .env
```

---

## Step 2: Fill In Your Credentials

Open `.env` in your favorite editor:

```powershell
# Use Notepad
notepad .env

# OR use VS Code
code .env
```

### Required Configuration

Edit these values in your `.env` file:

```bash
# Azure DevOps Configuration
ADO_COLLECTION_URL=https://dev.azure.com/your-organization
ADO_PAT=your-azure-devops-pat-here

# GitLab Configuration
GITLAB_BASE_URL=https://gitlab.com
GITLAB_PAT=your-gitlab-pat-here
```

### How to Get Your Personal Access Tokens

#### Azure DevOps PAT
1. Go to `https://dev.azure.com/your-organization/_usersSettings/tokens`
2. Click **+ New Token**
3. Set **Scopes**:
   - Code: **Read & Write**
   - Project and Team: **Read, Write & Manage**
4. Copy the token to `ADO_PAT` in your .env file

#### GitLab PAT
1. Go to `https://gitlab.com/-/profile/personal_access_tokens` (or your GitLab instance)
2. Click **Add new token**
3. Set **Scopes**:
   - `api`
   - `read_api`
   - `read_repository`
   - `write_repository`
4. Copy the token to `GITLAB_PAT` in your .env file

---

## Step 3: Verify Configuration

Test that your .env file is loaded correctly:

```powershell
# Run the script - it will auto-load .env
.\Gitlab2DevOps.ps1

# You should see:
# [INFO] Loading configuration from .env file(s)...
```

---

## Step 4: Run Your First Migration

### Option A: Interactive Mode (Easiest)

```powershell
# Just run the script
.\Gitlab2DevOps.ps1

# Follow the menu:
# 1. Prepare GitLab Project (Preflight)
# 2. Initialize Azure DevOps Project  
# 3. Migrate Single Project
```

### Option B: CLI Mode (For Automation)

```powershell
# Step 1: Preflight check
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"

# Step 2: Initialize ADO project
.\Gitlab2DevOps.ps1 -Mode Initialize -Source "mygroup/myproject" -Project "MyProject"

# Step 3: Execute migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "mygroup/myproject" -Project "MyProject"
```

---

## Advanced: Multiple Environments

### Development Environment

Create `.env.local` (this overrides `.env`):

```bash
# Development/Testing
ADO_COLLECTION_URL=https://dev.azure.com/dev-org
ADO_PAT=dev-pat-here
GITLAB_BASE_URL=https://gitlab-dev.example.com
GITLAB_PAT=dev-gitlab-pat
```

### Production Environment

Keep production values in `.env`:

```bash
# Production
ADO_COLLECTION_URL=https://dev.azure.com/prod-org
ADO_PAT=prod-pat-here
GITLAB_BASE_URL=https://gitlab.com
GITLAB_PAT=prod-gitlab-pat
```

**Priority Order**: `.env.local` > `.env` > environment variables > parameters

---

## Optional Configuration

Add these to your `.env` file if needed:

```bash
# API Version (default: 7.1)
ADO_API_VERSION=7.1

# Skip SSL validation (for self-signed certs)
SKIP_CERTIFICATE_CHECK=false

# Telemetry (opt-in, local only)
TELEMETRY_ENABLED=false

# Logging
LOG_LEVEL=Info
```

---

## Security Best Practices

### ✅ DO:
- Use `.env` for local development
- Use `.env.local` for machine-specific overrides
- Keep `.env.example` up to date (without real credentials)
- Use separate PATs for dev/staging/production
- Rotate your PATs regularly (every 90 days)

### ❌ DON'T:
- Never commit `.env` or `.env.local` to Git (they're gitignored)
- Never share your PATs via email/chat
- Never use production PATs in development
- Never store PATs in code or documentation

---

## Troubleshooting

### .env file not loaded?

**Check:**
1. File is named `.env` (not `env` or `.env.txt`)
2. File is in the same directory as `Gitlab2DevOps.ps1`
3. Run script again and look for: `[INFO] Loading configuration from .env file(s)...`

**Debug:**
```powershell
# Verify .env file exists
Test-Path .env

# Check file contents (be careful - contains secrets!)
Get-Content .env

# Manually test EnvLoader module
Import-Module .\modules\core\EnvLoader.psm1
$config = Import-DotEnvFile -Path ".env"
$config
```

### PAT not working?

**Check:**
1. Token hasn't expired (check Azure DevOps / GitLab settings)
2. Token has correct scopes/permissions
3. No extra spaces in `.env` file around `=`
4. Token is on same line as key (no line breaks)

**Test:**
```powershell
# Test Azure DevOps connection
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:ADO_PAT"))
}
Invoke-RestMethod -Uri "$env:ADO_COLLECTION_URL/_apis/projects?api-version=7.1" -Headers $headers

# Test GitLab connection
$headers = @{ "PRIVATE-TOKEN" = $env:GITLAB_PAT }
Invoke-RestMethod -Uri "$env:GITLAB_BASE_URL/api/v4/projects" -Headers $headers
```

### Environment variable conflict?

If you have existing environment variables that conflict with .env:

```powershell
# Clear environment variables first
Remove-Item Env:ADO_PAT -ErrorAction SilentlyContinue
Remove-Item Env:GITLAB_PAT -ErrorAction SilentlyContinue
Remove-Item Env:ADO_COLLECTION_URL -ErrorAction SilentlyContinue
Remove-Item Env:GITLAB_BASE_URL -ErrorAction SilentlyContinue

# Then run script
.\Gitlab2DevOps.ps1
```

---

## Next Steps

✅ Configuration complete? Continue to:
- [README.md](../README.md) - Full documentation
- [QUICK_REFERENCE.md](../QUICK_REFERENCE.md) - Command examples
- [SYNC_MODE_GUIDE.md](../SYNC_MODE_GUIDE.md) - Update existing repositories
- [BULK_MIGRATION_CONFIG.md](../BULK_MIGRATION_CONFIG.md) - Migrate multiple projects

---

## Need Help?

- 📖 [Full .env documentation](env-configuration.md)
- 🐛 [Troubleshooting guide](../README.md#troubleshooting)
- 💬 [GitHub Issues](https://github.com/magedfarag/Gitlab2DevOps/issues)
