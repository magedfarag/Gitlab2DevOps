# GitLab to Azure DevOps Migration Tool

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> **Enterprise-grade migration tool for seamless GitLab to Azure DevOps transitions**

## Overview

This PowerShell-based automation tool provides a comprehensive 3-step migration process from GitLab (self-managed or GitLab.com) to Azure DevOps Server (on-premises or cloud). The tool handles everything from initial project analysis to complete repository migration with full policy setup, security configurations, and enterprise-grade audit trails.

### Why This Tool?

- ✅ **Zero Credential Exposure**: Built with security-first approach
- ✅ **Pre-Migration Validation**: Never start a migration that will fail
- ✅ **Bulk Migration Support**: Migrate dozens of projects efficiently
- ✅ **Complete Audit Trail**: Every operation logged with timestamps
- ✅ **Production Tested**: Follows Microsoft & GitLab best practices
- ✅ **Open Source**: Community-driven and transparent

## Quick Start

```powershell
# 1. Set credentials as environment variables (recommended)
$env:ADO_COLLECTION_URL = "https://dev.azure.com/your-org"
$env:ADO_PAT = "your-ado-pat-here"
$env:GITLAB_BASE_URL = "https://gitlab.com"
$env:GITLAB_PAT = "your-gitlab-token-here"

# 2. Generate pre-migration report
.\devops.ps1 -Mode preflight -GitLabProject "mygroup/myproject" -AdoProject "MyProject"

# 3. Review the report at migrations/mygroup-myproject/reports/preflight-report.json

# 4. Execute migration
.\devops.ps1 -Mode migrate -GitLabProject "mygroup/myproject" -AdoProject "MyProject"
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
- [Project Structure](#project-structure)
- [Pre-Migration Report Format](#pre-migration-report-format)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [Security Features](#security-features)
- [Contributing](#contributing)
- [License](#license)

## Additional Documentation

- 📖 [Quick Reference Guide](QUICK_REFERENCE.md) - Common commands and quick tips
- 📦 [Bulk Migration Config](BULK_MIGRATION_CONFIG.md) - Detailed bulk configuration format
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
   .\devops.ps1 -Mode preflight -GitLabProject "mygroup/myproject" -AdoProject "MyProject"
   ```

That's it! You're ready to start migrating.

## Configuration

### 1. Initial Setup

You can configure the tool using **environment variables** (recommended for security) or **parameters**:

#### Option A: Using Environment Variables (Recommended)
```powershell
# Set environment variables
$env:ADO_COLLECTION_URL = "https://devops.example.com/DefaultCollection"
$env:ADO_PAT = "your-azure-devops-pat-here"
$env:GITLAB_BASE_URL = "https://gitlab.example.com"
$env:GITLAB_PAT = "your-gitlab-pat-here"

# Run the script
.\devops.ps1
```

#### Option B: Using Parameters
```powershell
.\devops.ps1 -CollectionUrl "https://devops.example.com/DefaultCollection" `
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
.\devops.ps1
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
.\devops.ps1
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
.\devops.ps1
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
   .\devops.ps1 -Mode bulkMigrate -ConfigFile "bulk-migration-config.json"
   ```

#### Option B: Interactive Bulk Preparation

#### Step 1: Bulk Preparation
```powershell
.\devops.ps1
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
.\devops.ps1
# Choose option 5
```

**What this does:**
- Lists available bulk migration templates
- Allows editing of migration configuration
- Lets you customize repository names and settings
- Validates template before execution

#### Step 3: Execute Bulk Migration
```powershell
.\devops.ps1
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
├── devops.ps1                    # Main migration script
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
.\devops.ps1 -SkipCertificateCheck
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