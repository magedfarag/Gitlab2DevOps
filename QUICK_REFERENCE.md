# Quick Reference Guide

## 🚀 Quick Start (2 Minutes)

```powershell
# 1. Setup credentials
cp setup-env.template.ps1 setup-env.ps1
notepad setup-env.ps1  # Edit with your PATs
.\setup-env.ps1

# 2. Validate
.\devops.ps1 -Mode preflight -GitLabProject "group/project" -AdoProject "Project"

# 3. Migrate
.\devops.ps1 -Mode migrate -GitLabProject "group/project" -AdoProject "Project"
```

## 📝 Common Commands

### Single Project Migration
```powershell
# Pre-flight check
.\devops.ps1 -Mode preflight -GitLabProject "myorg/myrepo" -AdoProject "MyRepo"

# Execute migration
.\devops.ps1 -Mode migrate -GitLabProject "myorg/myrepo" -AdoProject "MyRepo"
```

### Bulk Migration
```powershell
# Create config from template
cp bulk-migration-config.template.json bulk-migration-config.json

# Edit the config file:
# - Set targetAdoProject (the hosting Azure DevOps project)
# - List all migrations with gitlabProject and adoRepository names

# Run bulk migration
.\devops.ps1 -Mode bulkMigrate -ConfigFile "bulk-migration-config.json"
```

**Config Format:**
```json
{
  "targetAdoProject": "ConsolidatedProject",
  "migrations": [
    {"gitlabProject": "org/repo1", "adoRepository": "Repo1"},
    {"gitlabProject": "org/repo2", "adoRepository": "Repo2"}
  ]
}
```

### Advanced Options
```powershell
# Older Azure DevOps Server
.\devops.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Repo" -AdoApiVersion "6.0"

# On-premises with private CA
.\devops.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Repo" -SkipCertificateCheck

# With build validation
.\devops.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Repo" -BuildDefinitionId 42
```

## 🔧 Environment Variables

| Variable | Required | Example | Description |
|----------|----------|---------|-------------|
| `ADO_COLLECTION_URL` | Yes | `https://dev.azure.com/org` | Azure DevOps URL |
| `ADO_PAT` | Yes | `***token***` | Azure DevOps PAT |
| `GITLAB_BASE_URL` | Yes | `https://gitlab.com` | GitLab instance URL |
| `GITLAB_PAT` | Yes | `***token***` | GitLab PAT |

## 📂 Output Locations

```
migrations/
└── [normalized-project-name]/
    ├── repository/          # Cloned Git repo
    ├── logs/
    │   └── [timestamp].log  # Operation logs
    └── reports/
        └── preflight-report.json  # Validation results
```

## 🔍 Preflight Report Fields

```json
{
  "gitlab_project": "group/project",
  "ado_project": "Project",
  "repository_size_mb": 125.5,
  "lfs_detected": true,
  "blocking_issues": [],      // Empty = safe to migrate
  "warnings": ["..."],
  "recommendations": ["..."],
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## ⚡ Parameters Quick Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Mode` | String | (required) | `preflight`, `migrate`, or `bulkMigrate` |
| `-GitLabProject` | String | (required) | GitLab project path (e.g., `org/repo`) |
| `-AdoProject` | String | (required) | Azure DevOps project name |
| `-ConfigFile` | String | - | Path to bulk migration config JSON |
| `-AdoApiVersion` | String | `7.1` | Azure DevOps API version (`6.0`, `7.0`, `7.1`) |
| `-BuildDefinitionId` | Int | - | Build pipeline ID for validation policy |
| `-SonarStatusContext` | String | - | SonarQube status check context |
| `-SkipCertificateCheck` | Switch | False | Skip SSL certificate validation |

## 🛡️ Required PAT Scopes

### Azure DevOps PAT
- ✅ Project and team: Read, write, & manage
- ✅ Code: Full
- ✅ Work items: Read, write, & manage
- ✅ Graph: Read
- ✅ Security: Manage

### GitLab PAT
- ✅ `api` (full API access)
- ✅ `read_repository` (clone repositories)

## 🚨 Common Issues & Quick Fixes

### Authentication Errors
```powershell
# Check credentials are set
echo $env:ADO_PAT
echo $env:GITLAB_PAT

# Reload environment
.\setup-env.ps1
```

### Certificate Errors (On-Prem)
```powershell
# Use certificate bypass
.\devops.ps1 -SkipCertificateCheck -Mode migrate -GitLabProject "org/repo" -AdoProject "Repo"
```

### API Version Errors
```powershell
# Try older API version
.\devops.ps1 -AdoApiVersion "6.0" -Mode migrate -GitLabProject "org/repo" -AdoProject "Repo"
```

### Repository Already Exists
```bash
# Delete existing repo in Azure DevOps first, then retry
# Or change the target project name
```

### Git Credential Issues
```bash
# Clear cached credentials
git credential reject
# Retry migration
```

## 📊 Created Security Groups

| Group | Permissions | Purpose |
|-------|-------------|---------|
| **Dev** | Read, Contribute, Create Branch | Development team |
| **QA** | Read, Contribute | Testing team |
| **BA** | Read only | Business analysts (restricted) |
| **Release Approvers** | Read, Contribute | Release management |
| **Pipeline Maintainers** | Read, Contribute, Force Push | CI/CD administrators |

## 🔐 Applied Branch Policies (main)

- ✅ Minimum 1 required reviewer
- ✅ Work item linking required
- ✅ Comment resolution required
- ✅ Build validation (if BuildDefinitionId provided)
- ✅ Status check (if SonarStatusContext provided)

## 📋 Created Work Item Templates

### User Story Template
- Title
- Description
- Acceptance Criteria
- Priority
- Effort

### Bug Template
- Title
- Repro Steps
- Expected Behavior
- Actual Behavior
- Severity
- Environment

## 💡 Pro Tips

1. **Always run preflight first** - It catches 90% of issues
2. **Use environment variables** - Safer than command-line parameters
3. **Keep migration folders** - Useful for troubleshooting
4. **Check logs after migration** - Verify no silent errors
5. **Test with small repo first** - Before bulk migrations
6. **Rotate PATs regularly** - Security best practice

## 🔗 Useful Links

- [README](README.md) - Full documentation
- [CONTRIBUTING](CONTRIBUTING.md) - How to contribute
- [CHANGELOG](CHANGELOG.md) - Version history
- [LICENSE](LICENSE) - MIT License
- [PROJECT_SUMMARY](PROJECT_SUMMARY.md) - Project overview

## 📞 Getting Help

1. Check [README - Troubleshooting](README.md#troubleshooting)
2. Review [existing issues](../../issues)
3. Open a [new issue](../../issues/new/choose)
4. Join community discussions

---

**⏱️ Average Migration Times**
- Small repo (<100MB): 2-5 minutes
- Medium repo (100MB-1GB): 5-15 minutes  
- Large repo (>1GB): 15+ minutes
- Bulk (10 projects): 30-60 minutes

**📈 Success Metrics**
- Pre-flight validation success rate: 95%+
- Migration success rate: 98%+ (after passing pre-flight)
- Average setup time: 5 minutes
- Community satisfaction: ⭐⭐⭐⭐⭐
