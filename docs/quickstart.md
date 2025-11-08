# Quick Start Guide

Get started with Gitlab2DevOps in 5 minutes.

## Prerequisites

- PowerShell 5.1 or later
- Git 2.20+ installed and in PATH
- ImportExcel module (for work items import): `Install-Module -Name ImportExcel -Scope CurrentUser`
- Network access to GitLab and Azure DevOps instances

## Step 1: Obtain API Tokens

### GitLab Personal Access Token
1. Go to GitLab → User Settings → Access Tokens
2. Create token with `read_api` and `read_repository` scopes
3. Save token securely

### Azure DevOps Personal Access Token
1. Go to Azure DevOps → User Settings → Personal Access Tokens
2. Create token with:
   - **Code**: Read, Write, Manage
   - **Project**: Read, Write, Manage
3. Save token securely

## Step 2: Configure Credentials

Create `migration.config.json` in the script directory:

```json
{
  "gitlab": {
    "base_url": "https://gitlab.example.com",
    "token": "glpat-XXXXXXXXXXXXXXXXXXXX"
  },
  "ado": {
    "organization": "https://dev.azure.com/yourorg",
    "token": "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
  }
}
```

> ⚠️ **Security**: Never commit this file to version control. Add to `.gitignore`.

## Step 3: Run Your First Migration

### Interactive Mode (Recommended for First-Time Users)

```powershell
.\Gitlab2DevOps.ps1
```

Follow the menu prompts:
1. Select **1. Single Project Migration**
2. Enter GitLab project path (e.g., `my-group/my-project`)
3. Review preflight report
4. Choose **Initialize** if no blocking issues
5. Choose **Migrate** to complete migration

### CLI Mode (Quick Migration)

```powershell
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "my-group/my-project" -Project "MyADOProject"
```

This single command:
- Runs preflight checks
- Creates Azure DevOps project
- Migrates repository with full history
- Configures branch policies
- Generates migration report

## Step 4: Verify Migration

1. **Check Azure DevOps**: Open the project in Azure DevOps portal
2. **Review Logs**: Check `migrations/<project>/logs/migration.log`
3. **Read Report**: Open `migrations/<project>/reports/migration-report.json`

## What Gets Migrated?

✅ **Yes**:
- Git repository (all branches, tags, history)
- Branch protection rules → Branch policies
- Default branch configuration

❌ **No** (by design):
- Issues / Work Items
- Merge Requests / Pull Requests
- CI/CD Pipelines
- Wikis (optional in future)

See [Limitations](architecture/limitations.md) for complete list.

## Next Steps

- **Bulk Migrations**: [Bulk Migrations Guide](bulk-migrations.md)
- **CLI Automation**: [CLI Usage](cli-usage.md)
- **Configuration**: [Configuration Reference](configuration.md)
- **Troubleshooting**: [Common Issues](troubleshooting.md)

## Common First-Run Issues

### "Authentication failed"
- Verify tokens are valid and not expired
- Check token scopes match requirements
- Ensure URLs don't have trailing slashes

### "Project already exists"
- Use `-Replace` flag to delete and recreate
- Or choose different project name

### "Repository is empty"
- Ensure GitLab project has at least 1 commit
- Check repository permissions

See [Troubleshooting](troubleshooting.md) for more solutions.

---

[← Back to Documentation Index](README.md)
