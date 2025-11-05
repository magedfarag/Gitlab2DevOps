# GitLab to Azure DevOps Migration Tool

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.1.0--dev-orange.svg)](CHANGELOG.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> **Enterprise-grade migration toolkit for seamless GitLab to Azure DevOps transitions**

Migrate Git repositories with full history, branch policies, and comprehensive audit trails. Built for **on-premise Azure DevOps servers** with SSL/TLS challenges, featuring automatic **curl fallback** and robust retry logic.

---

## 🎯 Why Gitlab2DevOps?

| Feature | Description |
|---------|-------------|
| 🔒 **Security-First** | Zero credential exposure, token masking, audit trails |
| 🛡️ **SSL/TLS Resilience** | Automatic curl fallback for on-premise servers with certificate issues |
| ✅ **Idempotent Operations** | Safe to re-run, `-WhatIf` preview, `-Force` override |
| ⚡ **Performance Optimized** | Project caching, repository reuse, 2-5x faster re-runs |
| 🤖 **CLI Automation** | 5 modes, GitHub Actions/Azure Pipelines ready |
| 📊 **Full Observability** | Run manifests, REST timing, structured logs |
| 🔄 **Bulk Migration** | Process dozens of projects with single command |

---

## 📚 Documentation

**New to Gitlab2DevOps?** Start here:

- 🚀 **[Quick Start Guide](docs/quickstart.md)** - Get running in 5 minutes
- 📖 **[CLI Usage](docs/cli-usage.md)** - Command-line automation examples
- ⚠️ **[Limitations](docs/architecture/limitations.md)** - What this tool does NOT do
- 🛠️ **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

**Complete Documentation:**
- [Installation Guide](docs/installation.md)
- [Configuration Reference](docs/configuration.md)
- [Interactive Mode](docs/interactive-mode.md)
- [Bulk Migrations](docs/bulk-migrations.md)
- [Advanced Features](examples/advanced-features.md) - Progress tracking, telemetry, dry-run
- [API Error Catalog](docs/api-errors.md) - Troubleshooting guide
- [API Reference](docs/api-reference.md)
- [Architecture Overview](docs/architecture/modules.md)

---

## ⚡ Quick Start

```powershell
# 1. Configure credentials (create migration.config.json)
@{
    gitlab = @{
        base_url = "https://gitlab.example.com"
        token = "glpat-XXXXXXXXXXXXXXXXXXXX"
    }
    ado = @{
        organization = "https://dev.azure.com/yourorg"
        token = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
} | ConvertTo-Json | Out-File migration.config.json

# 2. Run preflight check
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "my-group/my-project"

# 3. Execute migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "my-group/my-project" -Project "MyADOProject"
```

📖 **New to this tool?** → [Full Quick Start Guide](docs/quickstart.md)

---

## ✨ What Gets Migrated?

### ✅ Included

| Item | Details |
|------|---------|
| **Git Repository** | All commits, branches, tags with full history |
| **Branch Protection** | Converted to Azure DevOps branch policies |
| **Default Branch** | Preserved from GitLab configuration |
| **Repository Settings** | Basic metadata and configuration |

### ❌ Not Included

| Item | Why Not? | Alternative |
|------|----------|-------------|
| **Issues / Work Items** | Different data models | Manual recreation |
| **Merge Requests / PRs** | Live objects, lose context | Close before migration |
| **CI/CD Pipelines** | Different syntax | Recreate in Azure Pipelines |
| **Wikis** | Separate repositories | Planned for v3.0 |

📖 **Full scope details:** [Limitations Documentation](docs/architecture/limitations.md)

---

## 🚀 Features

### Core Capabilities

- **Idempotent Operations**: Safe to re-run with `-Force` and `-Replace` flags
- **CLI Automation**: 5 modes (Preflight, Initialize, Migrate, BulkPrepare, BulkMigrate)
- **Progress Tracking**: Visual progress bars with ETA for long-running operations
- **Telemetry Analytics**: Opt-in metrics collection for performance analysis (local only)
- **Dry-Run Preview**: Generate HTML/JSON reports before migration with size estimates
- **API Error Catalog**: Comprehensive troubleshooting guide with 25+ documented errors
- **Performance Caching**: 15-minute project cache, repository reuse
- **Audit Trails**: Run manifests with execution metadata
- **REST Observability**: Timing measurements, status code logging
- **Bulk Migration**: Process multiple projects efficiently

### Production-Grade Features

| Feature | Description |
|---------|-------------|
| **REST Resilience** | Exponential backoff, retry logic, error normalization |
| **Configuration Files** | JSON schema with validation, sensitive data in separate files |
| **Versioning** | Semantic versioning, compatibility checks |
| **Security** | Token masking, credential cleanup, no hardcoded secrets |
| **Logging** | Standardized levels (DEBUG/INFO/WARN/ERROR/SUCCESS) |

---

## 📦 What This Tool Does NOT Do

Understanding limitations helps set proper expectations:

❌ **Does NOT migrate:**
- GitLab Issues → Azure DevOps Work Items
- Merge Requests → Pull Requests (close before migration)
- CI/CD pipelines (recreate manually)
- Wikis (planned for v3.0)
- Project settings, permissions, webhooks

❌ **Does NOT support:**
- Incremental/delta migrations after initial cutover
- Continuous sync between GitLab and Azure DevOps
- Git LFS without manual configuration

✅ **What it DOES:**
- Migrate complete Git history (commits, branches, tags)
- Convert branch protection → branch policies
- Provide audit trails and comprehensive logging
- Enable bulk migration workflows

📖 **Full details:** [Limitations and Scope](docs/architecture/limitations.md)

---

## 📖 Overview

**API Integration:** Uses official [Microsoft Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/) and [GitLab REST API v4](https://docs.gitlab.com/ee/api/rest/) with Personal Access Tokens (PATs).

## Quick Start

### Option 1: Using .env File (Recommended)

```powershell
# 1. Create .env file from template
Copy-Item .env.example .env

# 2. Edit .env with your credentials
notepad .env

# 3. Run preflight check
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"

# 4. Execute migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "mygroup/myproject" -Project "MyProject"
```

### Option 2: Using Environment Variables

```powershell
# 1. Set credentials as environment variables
$env:ADO_COLLECTION_URL = "https://dev.azure.com/your-org"
$env:ADO_PAT = "your-ado-pat-here"
$env:GITLAB_BASE_URL = "https://gitlab.com"
$env:GITLAB_PAT = "your-gitlab-token-here"

# 2. Run preflight check
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"

# 3. Execute migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "mygroup/myproject" -Project "MyProject"
```

📖 **First time?** Jump to [Step-by-Step Guide](#usage) for detailed instructions.  
⚡ **Need quick commands?** Check the [Quick Reference Guide](QUICK_REFERENCE.md).  
📦 **Bulk migrations?** See [Bulk Migration Config Guide](BULK_MIGRATION_CONFIG.md).

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Single Project Migration](#single-project-migration)
  - [Bulk Migration](#bulk-migration-workflow)
  - [Re-running Migrations (Sync Mode)](#re-running-migrations-sync-mode)
- [Project Structure](#project-structure)
- [Pre-Migration Report Format](#pre-migration-report-format)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [Security Features](#security-features)
- [Contributing](#contributing)
- [License](#license)

## 📚 Additional Resources

- �️ [Implementation Roadmap](IMPLEMENTATION_ROADMAP.md) - Development progress and future features
- 📋 [Project Summary](PROJECT_SUMMARY.md) - Architecture and technical overview  
- 📝 [Changelog](CHANGELOG.md) - Version history and migration guides
- 🤝 [Contributing](CONTRIBUTING.md) - How to contribute to this project

## Features

### 🚀 **Complete Migration Workflow**
- **Step 1**: GitLab project preparation and analysis
- **Step 2**: Azure DevOps project creation with full organizational setup
- **Step 3**: Repository migration with all refs, branches, and Git LFS support

### 📊 **Project Analysis & Reporting**
- Repository size analysis and LFS detection
- Comprehensive preflight reports (JSON format)
- Migration logs with detailed timestamps
- Success/failure tracking with error diagnostics

### 🏢 **Enterprise-Ready Setup**
- **RBAC Groups**: Dev, QA, BA, Release Approvers, Pipeline Maintainers
- **Branch Policies**: Required reviewers, work item linking, build validation
- **Security Restrictions**: BA group cannot push/create PRs
- **Work Item Templates**: Pre-configured User Story and Bug templates
- **Project Wiki**: Automated setup with conventions documentation

### 📦 **Bulk Migration Support**
- Multi-project preparation and analysis
- Consolidated migration templates
- Batch processing with individual project tracking
- Automated error handling and recovery

### 🔧 **Advanced Features**
- Git LFS support with automatic detection
- All Git refs migration (branches, tags, commit history)
- Build validation policy integration
- SonarQube status check support
- Customizable security policies

## Prerequisites

### Required Software
- **PowerShell 5.1** or later
- **Git** (with git-lfs for LFS repositories)
- **Network access** to both GitLab and Azure DevOps instances

### Required Credentials
- **Azure DevOps Personal Access Token (PAT)** with:
  - Project and team: Read, write, & manage
  - Code: Full
  - Work items: Read, write, & manage
  - Graph: Read
  - Security: Manage

- **GitLab Personal Access Token** with:
  - `api` scope for project access
  - `read_repository` scope for Git operations

## Installation

### Quick Install

1. **Clone the repository**:
   ```powershell
   git clone https://github.com/your-org/gitlab-to-azuredevops-migration.git
   cd gitlab-to-azuredevops-migration
   ```

2. **Verify prerequisites**:
   ```powershell
   # Check PowerShell version (should be 5.1+)
   $PSVersionTable.PSVersion
   
   # Check Git installation
   git --version
   
   # Check Git LFS (optional, but recommended)
   git lfs version
   ```

3. **Set up credentials**:
   ```powershell
   # Copy the environment template
   cp setup-env.template.ps1 setup-env.ps1
   
   # Edit setup-env.ps1 with your credentials (use notepad, VS Code, etc.)
   notepad setup-env.ps1
   
   # Load the environment variables
   .\setup-env.ps1
   ```
   
   See [Configuration](#configuration) section for detailed credential setup.

4. **Run your first migration**:
   ```powershell
   # Generate pre-flight report
   .\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"
   ```

That's it! You're ready to start migrating.

## Configuration

### 1. Initial Setup

You can configure the tool using **.env files** (recommended), **environment variables**, or **parameters**:

#### Option A: Using .env File (Recommended - Most Secure)
```powershell
# 1. Create .env file from template
Copy-Item .env.example .env

# 2. Edit .env with your credentials
notepad .env
# OR
code .env

# 3. Run the script (automatically loads .env)
.\Gitlab2DevOps.ps1
```

Your `.env` file should look like:
```bash
# Azure DevOps Configuration
ADO_COLLECTION_URL=https://dev.azure.com/your-org
ADO_PAT=your-azure-devops-pat-here

# GitLab Configuration
GITLAB_BASE_URL=https://gitlab.com
GITLAB_PAT=your-gitlab-pat-here
```

**Benefits:**
- ✅ Keeps secrets out of command history
- ✅ Easy to manage multiple environments (.env.local, .env.production)
- ✅ Automatically gitignored (never commit credentials)
- ✅ Simple to share templates with team (.env.example)

📖 **Full .env guide:** [Environment Configuration Documentation](docs/env-configuration.md)

#### Option B: Using Environment Variables
```powershell
# Set environment variables
$env:ADO_COLLECTION_URL = "https://devops.example.com/DefaultCollection"
$env:ADO_PAT = "your-azure-devops-pat-here"
$env:GITLAB_BASE_URL = "https://gitlab.example.com"
$env:GITLAB_PAT = "your-gitlab-pat-here"

# Run the script
.\Gitlab2DevOps.ps1
```

#### Option C: Using Parameters
```powershell
.\Gitlab2DevOps.ps1 -CollectionUrl "https://devops.example.com/DefaultCollection" `
             -AdoPat "your-azure-devops-pat" `
             -GitLabBaseUrl "https://gitlab.example.com" `
             -GitLabToken "your-gitlab-pat" `
             -AdoApiVersion "7.1" `
             -BuildDefinitionId 42 `
             -SonarStatusContext "sonarqube/quality_gate"
```

#### Additional Parameters:
- `-AdoApiVersion`: API version (default: "7.1", use "6.0" for Azure DevOps Server 2020)
- `-BuildDefinitionId`: Build definition ID for PR validation (default: 42, use 0 to skip)
- `-SonarStatusContext`: SonarQube status check context (default: "", use "" to skip)
- `-SkipCertificateCheck`: Skip SSL certificate validation for on-prem with private CA

### 2. Security Configuration
The tool automatically configures enterprise-grade security:

- **Required Reviewers**: Minimum 2 reviewers for all PRs
- **Work Item Linking**: All PRs must link to work items
- **Comment Resolution**: All comments must be resolved before merge
- **Build Validation**: Optional CI/CD integration
- **Status Checks**: Optional external tool integration (SonarQube, etc.)

## Usage Guide

### Single Project Migration

#### Step 1: Prepare GitLab Project
```powershell
.Gitlab2DevOps.ps1
# Choose option 1
Enter Source GitLab project path: group/my-project
```

**What this does:**
- Downloads and analyzes the GitLab project
- Creates local mirror repository
- Generates preflight report with size, LFS, and metadata
- Sets up project-specific folder structure in `migrations/`

#### Step 2: Initialize Azure DevOps Project
```powershell
.Gitlab2DevOps.ps1
# Choose option 2
Enter Source GitLab project path: group/my-project
Enter Destination Azure DevOps project name: MyProject
```

**What this does:**
- Creates Azure DevOps project with Agile process template
- Sets up RBAC groups (Dev, QA, BA, Release Approvers, Pipeline Maintainers)
- Creates project areas (Requirements, Development, QA)
- Initializes project wiki with conventions
- Creates work item templates
- Configures target repository with branch policies
- Applies security restrictions

#### Step 3: Execute Migration
```powershell
.Gitlab2DevOps.ps1
# Choose option 3
Enter Source GitLab project path: group/my-project
Enter Destination Azure DevOps project name: MyProject
```

**What this does:**
- Uses prepared repository data (from Step 1) for faster migration
- Pushes all Git refs (branches, tags, commit history) to Azure DevOps
- Migrates Git LFS objects if present
- Applies final branch policies and security settings
- Generates comprehensive migration report

### Bulk Migration Workflow

#### Option A: Using Configuration File (Recommended)

1. **Create configuration file** (use the provided template):
   ```powershell
   cp bulk-migration-config.template.json bulk-migration-config.json
   ```
   
   📖 See [BULK_MIGRATION_CONFIG.md](BULK_MIGRATION_CONFIG.md) for detailed configuration format documentation.

2. **Edit configuration** with your projects:
   ```json
   {
     "targetAdoProject": "ConsolidatedProject",
     "migrations": [
       {
         "gitlabProject": "organization/frontend-app",
         "adoRepository": "FrontendApp"
       },
       {
         "gitlabProject": "organization/backend-api",
         "adoRepository": "BackendAPI"
       },
       {
         "gitlabProject": "devops/infrastructure",
         "adoRepository": "Infrastructure"
       }
     ]
   }
   ```
   
   > **Note**: All repositories will be created in the **single** Azure DevOps project specified in `targetAdoProject`.

3. **Execute bulk migration**:
   ```powershell
   .Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "bulk-migration-config.json"
   ```

#### Option B: Interactive Bulk Preparation

#### Step 1: Bulk Preparation
```powershell
.Gitlab2DevOps.ps1
# Choose option 4
Enter Destination Azure DevOps project name: ConsolidatedProject
# Enter multiple GitLab project paths (one per line)
Project 1: organization/frontend-app
Project 2: organization/backend-api
Project 3: organization/mobile-app
Project 4: [empty line to finish]
```

**What this does:**
- Downloads and analyzes multiple GitLab projects
- Creates individual project preparations
- Generates consolidated bulk migration template
- Provides size analysis and feasibility report

#### Step 2: Review Migration Template
```powershell
.Gitlab2DevOps.ps1
# Choose option 5
```

**What this does:**
- Lists available bulk migration templates
- Allows editing of migration configuration
- Lets you customize repository names and settings
- Validates template before execution

#### Step 3: Execute Bulk Migration
```powershell
.Gitlab2DevOps.ps1
# Choose option 6
# Select prepared template
# Confirm destination project
```

**What this does:**
- Creates single Azure DevOps project with multiple repositories
- Migrates all prepared projects using cached data
- Applies consistent policies across all repositories
- Generates consolidated migration report

## Project Structure

```
Gitlab2DevOps/
├── Gitlab2DevOps.ps1             # Main migration script
├── .gitignore                    # Git ignore configuration
├── README.md                     # This documentation
└── migrations/                   # Migration workspace
    ├── project-name/             # Individual project folders
    │   ├── reports/              # JSON reports and analysis
    │   │   ├── preflight-report.json
    │   │   └── migration-summary.json
    │   ├── logs/                 # Detailed operation logs
    │   │   ├── preparation-YYYYMMDD-HHMMSS.log
    │   │   └── migration-YYYYMMDD-HHMMSS.log
    │   └── repository/           # Local Git mirror (bare repository)
    ├── bulk-prep-ProjectName/    # Bulk preparation workspace
    │   ├── bulk-migration-template.json
    │   ├── preparation-summary.json
    │   └── bulk-preparation.log
    └── bulk-execution-YYYYMMDD-HHMMSS/  # Bulk migration results
        ├── migration-report.json
        └── bulk-execution.log
```

## Generated Reports

### Preflight Report (JSON)
```json
{
  "project": "group/project-name",
  "http_url_to_repo": "https://gitlab.example.com/group/project.git",
  "default_branch": "main",
  "visibility": "private",
  "lfs_enabled": true,
  "repo_size_MB": 150.5,
  "lfs_size_MB": 45.2,
  "open_issues": 25,
  "last_activity": "2025-11-03T10:30:00.000Z",
  "preparation_time": "2025-11-03 14:30:15"
}
```

### Migration Summary (JSON)
```json
{
  "source_project": "group/project-name",
  "destination_project": "MyDevOpsProject",
  "migration_start": "2025-11-03 15:00:00",
  "migration_end": "2025-11-03 15:05:30",
  "duration_minutes": 5.5,
  "status": "SUCCESS"
}
```

## Re-running Migrations (Sync Mode)

The tool supports re-running migrations to sync Azure DevOps repositories with updated GitLab sources. This is useful when:
- The GitLab source project has been updated with new commits
- Additional branches or tags have been added
- You need to refresh the repository content while preserving Azure DevOps configurations

### How Sync Mode Works

**Sync mode preserves:**
- All existing Azure DevOps repository settings
- Branch policies and permissions
- Work item templates and security groups
- Migration history and configuration files in the `migrations/` folder

**Sync mode updates:**
- Repository content (commits, branches, tags)
- Git references to match current GitLab state

### Single Project Sync

**Command Line:**
```powershell
.Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/my-repo" -AdoProject "ConsolidatedProject" -AllowSync
```

**Interactive Menu:**
1. Choose option 3 (Single Migration)
2. Enter your GitLab project path and Azure DevOps project name
3. When prompted "Allow sync of existing repository? (Y/N)", answer `Y`

### Bulk Migration Sync

**Command Line:**
```powershell
.Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "bulk-migration-config.json" -AllowSync
```

**Interactive Menu:**
1. Choose option 6 (Execute Bulk Migration)
2. Select your prepared template file
3. When prompted "Allow sync of existing repositories? (Y/N)", answer `Y`

### Migration History Tracking

Each sync operation is tracked in the migration summary JSON file:

```json
{
  "migration_type": "SYNC",
  "migration_count": 3,
  "last_sync": "2024-01-15T10:30:00",
  "previous_migrations": [
    {
      "migration_start": "2024-01-01T09:00:00",
      "migration_end": "2024-01-01T09:15:00",
      "status": "SUCCESS",
      "type": "INITIAL"
    },
    {
      "migration_start": "2024-01-08T14:20:00",
      "migration_end": "2024-01-08T14:28:00",
      "status": "SUCCESS",
      "type": "SYNC"
    }
  ]
}
```

### When NOT to Use Sync Mode

❌ **Do not use sync mode if:**
- You want to prevent accidental overwrites of existing repositories
- The Azure DevOps repository has local changes that shouldn't be overwritten
- You're unsure if the target repository already exists

✅ **Safe to use when:**
- You intentionally want to update an existing repository
- The Azure DevOps repository is purely a mirror of GitLab
- You need to refresh content from the authoritative GitLab source

## Advanced Configuration

### Custom Branch Policies
Modify the `Ensure-BranchPolicies` function to customize:
- Minimum reviewer count
- Required status checks
- Build validation settings
- Comment resolution requirements

### Security Groups and Permissions
The tool creates these groups automatically:
- **Dev**: Contributors with full development access
- **QA**: Contributors with testing and review access
- **BA**: Contributors with read-only repository access (cannot push/PR)
- **Release Approvers**: Special group for release management
- **Pipeline Maintainers**: Project administrators for CI/CD

### Work Item Templates
Pre-configured templates include:
- **User Story**: With Definition of Ready/Done checklist
- **Bug**: With structured reproduction steps and triage fields

## Troubleshooting

### Common Issues

#### 1. **Authentication Errors**
```
Error: GitLab API error GET -> HTTP 401 Unauthorized
```
**Solution**: 
- Verify GitLab token has `api` scope and can access the project
- Ensure token hasn't expired
- Check that the token user has at least Reporter access to the project

#### 2. **Large Repository Warnings**
```
WARN: Large repository detected: 500 MB
```
**Solution**: Ensure adequate network bandwidth and disk space. Consider using Step 1 preparation during off-peak hours.

#### 3. **Git LFS Requirements**
```
Error: Git LFS required but not found
```
**Solution**: Install Git LFS: `git lfs install`

#### 4. **Azure DevOps Permission Issues**
```
Error: TF401027: You need the Generic Contribute permission
```
**Solution**: 
- Verify Azure DevOps PAT has all required permissions listed in Prerequisites
- Ensure PAT hasn't expired
- Check that the PAT has Full scope for Code and Project management

### Logs and Diagnostics

All operations generate detailed logs in the `migrations/*/logs/` folders:
- **Preparation logs**: Download progress, repository analysis
- **Migration logs**: Git operations, policy application, error details
- **Bulk operation logs**: Multi-project status and aggregated results

### Recovery and Retry

The tool is designed for safe retry:
- **Preparation Step**: Can be run multiple times to update local repository
- **Migration Step**: Uses cached preparation data, safe to retry if network issues occur
- **Bulk Operations**: Individual project failures don't affect other projects

## Best Practices

### Before Migration
1. **Test with small repositories first**
2. **Verify network connectivity to both GitLab and Azure DevOps**
3. **Ensure sufficient disk space** (2x repository size recommended)
4. **Coordinate with teams** for minimal disruption

### During Migration
1. **Run preparation step during off-peak hours** for large repositories
2. **Monitor logs** for any issues or warnings
3. **Keep migration windows short** by using prepared data

### After Migration
1. **Verify all branches and tags** migrated correctly
2. **Test Git LFS objects** if applicable
3. **Validate branch policies** are applied correctly
4. **Update team documentation** with new repository URLs

## Support and Maintenance

### Regular Maintenance
- **Update PATs** before expiration
- **Review security policies** quarterly
- **Clean up old migration data** from `migrations/` folder

### Customization
The script is modular and can be customized for:
- Different Azure DevOps process templates
- Custom security group configurations
- Alternative branch policy settings
- Integration with additional tools

### Version History
- **Initial Release**: Basic single-project migration
- **Current Version**: Full enterprise features with bulk migration support

## Security Features

### Production-Ready Enhancements
This tool has been hardened with enterprise security features:

1. **No Hardcoded Credentials**: All sensitive data via environment variables or parameters
2. **Credential Cleanup**: Automatic removal of PATs from Git config after operations
3. **Pre-Migration Validation**: Mandatory validation before any changes are made
4. **Fail-Fast Approach**: Stops immediately if prerequisites aren't met
5. **Audit Logging**: Comprehensive REST API status code logging
6. **Defensive ACL Checks**: Verifies group descriptors before applying permissions
7. **Strict Mode**: PowerShell strict mode enabled for better error detection
8. **Configurable API Version**: Support for different Azure DevOps Server versions
9. **SSL Certificate Handling**: Optional certificate validation for on-prem environments

### Running in Secure Environments

For on-premises environments with private Certificate Authorities:
```powershell
.Gitlab2DevOps.ps1 -SkipCertificateCheck
```

**⚠️ Warning**: Only use `-SkipCertificateCheck` in trusted environments. Do not use in production without proper certificate management.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or create issues for bugs and feature requests.

### Development Guidelines
- Follow PowerShell best practices
- Add comprehensive error handling
- Include verbose logging for troubleshooting
- Update documentation for new features
- Test with different Azure DevOps Server versions

## License

MIT License - See [LICENSE](LICENSE) file for details

## Contributors

This project is made possible by contributors from the community. Thank you! 🙏

---

**Made with ❤️ by the community, for the community**

*For detailed contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md)*

This tool is open source and free to use. While designed for enterprise environments, it can be adapted for any use case.

## Support

- **Issues**: Report bugs and request features via GitHub Issues
- **Documentation**: See README.md and inline code comments
- **Community**: Share your experience and improvements

## Acknowledgments

Built with enterprise security and reliability in mind, following Microsoft's official REST API documentation and GitLab API best practices.

---

**Made with ❤️ for the DevOps community**
