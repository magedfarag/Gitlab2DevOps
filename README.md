# GitLab to Azure DevOps Migration Tool# GitLab to Azure DevOps Migration Tool



[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)

[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[![Version](https://img.shields.io/badge/Version-2.1.0-brightgreen.svg)](CHANGELOG.md)[![Version](https://img.shields.io/badge/Version-2.1.0-green.svg)](CHANGELOG.md)

[![Tests](https://img.shields.io/badge/Tests-29%2F29%20Passing-success.svg)]()[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> **Enterprise-grade migration toolkit for seamless GitLab to Azure DevOps transitions**

> **Enterprise-grade migration toolkit for seamless GitLab to Azure DevOps transitions**

Migrate Git repositories with full history, branch policies, and comprehensive audit trails. Built for **on-premise Azure DevOps servers** with SSL/TLS challenges, featuring automatic **curl fallback** and robust retry logic.

Migrate Git repositories with full history, LFS support, and comprehensive project initialization. Built for **on-premise Azure DevOps servers** with SSL/TLS challenges, featuring automatic **curl fallback** and robust retry logic.

---

---

## 🎯 Why Gitlab2DevOps?

## ✨ Key Features

| Feature | Description |

- 🔒 **Security-First**: Zero credential exposure, automatic token masking, comprehensive audit trails|---------|-------------|

- 🛡️ **SSL/TLS Resilience**: Automatic curl fallback for on-premise servers with certificate issues| 🔒 **Security-First** | Zero credential exposure, token masking, audit trails |

- ✅ **Idempotent Operations**: Safe to re-run, preview mode, comprehensive validation| 🛡️ **SSL/TLS Resilience** | Automatic curl fallback for on-premise servers with certificate issues |

- ⚡ **High Performance**: Smart caching, optimized cloning, efficient bulk processing| ✅ **Idempotent Operations** | Safe to re-run, `-WhatIf` preview, `-Force` override |

- 🤖 **CLI & Interactive**: Full automation support with user-friendly interactive menus| ⚡ **Performance Optimized** | Project caching, repository reuse, 2-5x faster re-runs |

- 📊 **Complete Observability**: Detailed logs, structured reports, migration tracking| 🤖 **CLI Automation** | 10 modes including Business/Dev/Security/Management Init |

- 🔄 **Bulk Migration**: Process dozens of projects with a single command| 📊 **Full Observability** | Run manifests, REST timing, structured logs |

- 📚 **Rich Templates**: 43+ wiki templates and 4 team initialization packs| 🔄 **Bulk Migration** | Process dozens of projects with single command |

| 📚 **43 Wiki Templates** | ~18,000 lines of production-ready documentation |

---

---

## 🚀 Quick Start

## ⚠️ v2.1.0 Breaking Change

### Prerequisites

**Self-contained folder structures** are now used for all migrations. See [Project Structure](#project-structure) for details.

- PowerShell 5.1+ (Windows) or PowerShell Core 7+ (cross-platform)

- Git 2.20+ installed and in PATH- Single migrations: `migrations/{AdoProject}/{GitLabProject}/`

- Access to GitLab and Azure DevOps (PATs required)- Bulk migrations: `migrations/{AdoProject}/{Project1,Project2,...}/`

- Git LFS (optional, for LFS-enabled repositories)- Legacy projects (v2.0.x) can be detected and re-prepared



### Installation---



```powershell## 📚 Documentation

# Clone the repository

git clone https://github.com/magedfarag/Gitlab2DevOps.git**New to Gitlab2DevOps?** Start here:

cd Gitlab2DevOps

- 🚀 **[Quick Start Guide](docs/quickstart.md)** - Get running in 5 minutes

# Set up environment (copy and edit .env)- 📖 **[CLI Usage](docs/cli-usage.md)** - Command-line automation examples

Copy-Item .env.example .env- ⚠️ **[Limitations](docs/architecture/limitations.md)** - What this tool does NOT do

# Edit .env with your PATs and URLs- 🛠️ **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions



# Run interactive mode**Complete Documentation:**

.\Gitlab2DevOps.ps1- [Installation Guide](docs/installation.md)

```- [Configuration Reference](docs/configuration.md)

- [Interactive Mode](docs/interactive-mode.md)

### Quick Migration Example- [Bulk Migrations](docs/bulk-migrations.md)

- [Advanced Features](examples/advanced-features.md) - Progress tracking, telemetry, dry-run

```powershell- [API Error Catalog](docs/api-errors.md) - Troubleshooting guide

# Interactive mode (recommended for first-time users)- [API Reference](docs/api-reference.md)

.\Gitlab2DevOps.ps1- [Architecture Overview](docs/architecture/modules.md)



# CLI automation mode---

.\Gitlab2DevOps.ps1 -Mode Migrate `

    -Source "my-group/my-project" `## ⚡ Quick Start

    -Project "MyAzureDevOpsProject"

``````powershell

# 1. Configure credentials (create migration.config.json)

---@{

    gitlab = @{

## 📋 What Gets Migrated        base_url = "https://gitlab.example.com"

        token = "glpat-XXXXXXXXXXXXXXXXXXXX"

| ✅ Migrated | ❌ Not Migrated | 🔜 Planned (v3.0) |    }

|-------------|-----------------|-------------------|    ado = @{

| Git repositories | Issues/Work Items | CI/CD pipeline conversion |        organization = "https://dev.azure.com/yourorg"

| Full commit history | Merge Requests | User permissions mapping |        token = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

| All branches | CI/CD pipelines | Container registry |    }

| All tags | Container registry | Package registry |} | ConvertTo-Json | Out-File migration.config.json

| LFS objects | Package registry | Group-level settings |

| Repository settings | Webhooks | Automated rollback |# 2. Run preflight check

| Default branch | User permissions | |.\Gitlab2DevOps.ps1 -Mode Preflight -Source "my-group/my-project"



---# 3. Execute migration

.\Gitlab2DevOps.ps1 -Mode Migrate -Source "my-group/my-project" -Project "MyADOProject"

## 🏗️ Project Structure```



Gitlab2DevOps uses **self-contained folder structures** for all migrations:Optional: Provision team-specific initialization packs in an existing ADO project:



### Single Project Migration```powershell

# Business team assets (10 wiki pages, 8 queries, dashboard)

```./Gitlab2DevOps.ps1 -Mode BusinessInit -Project "MyADOProject"

migrations/

└── MyAzureDevOpsProject/          # Azure DevOps project (parent)# Development team assets (7 wiki pages, technical documentation)

    ├── migration-config.json      # Project metadata./Gitlab2DevOps.ps1 -Mode DevInit -Project "MyADOProject"

    ├── reports/                   # Migration reports

    │   └── migration-summary.json# Security team assets (7 wiki pages, security queries, dashboard)

    ├── logs/                      # Operation logs./Gitlab2DevOps.ps1 -Mode SecurityInit -Project "MyADOProject"

    │   └── migration-YYYYMMDD-HHMMSS.log

    └── my-gitlab-project/         # GitLab project (subfolder)# Management/PMO assets (8 wiki pages, 6 queries, executive dashboard)

        ├── reports/               # GitLab-specific reports./Gitlab2DevOps.ps1 -Mode ManagementInit -Project "MyADOProject"

        │   └── preflight-report.json```

        └── repository/            # Bare Git mirror

```📖 **New to this tool?** → [Full Quick Start Guide](docs/quickstart.md)



### Bulk Migration---



```## ✨ What Gets Migrated?

migrations/

└── ConsolidatedProject/           # Azure DevOps project (parent)### ✅ Included

    ├── bulk-migration-config.json # Bulk configuration

    ├── reports/                   # Analysis results| Item | Details |

    ├── logs/                      # Operation logs|------|---------|

    ├── frontend-app/              # GitLab project 1| **Git Repository** | All commits, branches, tags with full history |

    │   └── repository/| **Branch Protection** | Converted to Azure DevOps branch policies |

    ├── backend-api/               # GitLab project 2| **Default Branch** | Preserved from GitLab configuration |

    │   └── repository/| **Repository Settings** | Basic metadata and configuration |

    └── infrastructure/            # GitLab project 3

        └── repository/### ❌ Not Included

```

| Item | Why Not? | Alternative |

**Benefits**: Self-contained, portable, easy to archive, clear parent-child relationships.|------|----------|-------------|

| **Issues / Work Items** | Different data models | Manual recreation |

---| **Merge Requests / PRs** | Live objects, lose context | Close before migration |

| **CI/CD Pipelines** | Different syntax | Recreate in Azure Pipelines |

## 🎯 Usage Modes| **Wikis** | Separate repositories | Planned for v3.0 |



### Interactive Menu📖 **Full scope details:** [Limitations Documentation](docs/architecture/limitations.md)



```powershell---

.\Gitlab2DevOps.ps1

```## 🚀 Features



**Available Options:**### Core Capabilities

1. **Prepare Project** - Analyze and clone GitLab project

2. **Create Azure DevOps Project** - Initialize with templates- **Idempotent Operations**: Safe to re-run with `-Force` and `-Replace` flags

3. **Complete Migration** - Push code and configure- **CLI Automation**: 10 modes (Preflight, Initialize, Migrate, BulkPrepare, BulkMigrate, BusinessInit, DevInit, SecurityInit, ManagementInit, MenuMode)

4. **Bulk Preparation** - Analyze multiple projects- **User Identity Migration**: ⭐ **NEW** Export GitLab users/groups to JSON, import to Azure DevOps Server

5. **List Prepared Projects** - View migration status- **Progress Tracking**: Visual progress bars with ETA for long-running operations

6. **Bulk Execution** - Migrate multiple projects- **Telemetry Analytics**: Opt-in metrics collection for performance analysis (local only)

7. **Initialize Business Team** - Wiki + work items + dashboard- **Dry-Run Preview**: Generate HTML/JSON reports before migration with size estimates

8. **Initialize Dev Team** - Technical documentation + workflows- **API Error Catalog**: Comprehensive troubleshooting guide with 25+ documented errors

9. **Initialize Security Team** - Security policies + compliance- **Performance Caching**: 15-minute project cache, repository reuse

10. **Initialize Management Team** - Executive dashboards + reports- **Audit Trails**: Run manifests with execution metadata

- **REST Observability**: Timing measurements, status code logging

### CLI Automation- **Bulk Migration**: Process multiple projects efficiently

- **Modular Architecture**: 7 sub-modules (Core, Security, Projects, Repositories, Wikis, WorkItems, Dashboards)

```powershell- **JSON Configuration**: Project settings, branch policies, and templates via configuration files

# Single project migration

.\Gitlab2DevOps.ps1 -Mode Migrate `### Production-Grade Features

    -Source "group/project" `

    -Project "ADOProject"| Feature | Description |

|---------|-------------|

# Bulk migration| **REST Resilience** | Exponential backoff, retry logic, error normalization |

.\Gitlab2DevOps.ps1 -Mode BulkPrep `| **Configuration Files** | JSON schema with validation, sensitive data in separate files |

    -Config "bulk-config.json" `| **Versioning** | Semantic versioning, compatibility checks |

    -Project "ConsolidatedProject"| **Security** | Token masking, credential cleanup, no hardcoded secrets |

| **Logging** | Standardized levels (DEBUG/INFO/WARN/ERROR/SUCCESS) |

.\Gitlab2DevOps.ps1 -Mode BulkExec `

    -Project "ConsolidatedProject"---



# Team initialization## 📦 What This Tool Does NOT Do

.\Gitlab2DevOps.ps1 -Mode BusinessInit -Project "ADOProject"

.\Gitlab2DevOps.ps1 -Mode DevInit -Project "ADOProject"Understanding limitations helps set proper expectations:

.\Gitlab2DevOps.ps1 -Mode SecurityInit -Project "ADOProject"

.\Gitlab2DevOps.ps1 -Mode ManagementInit -Project "ADOProject"❌ **Does NOT migrate:**

```- GitLab Issues → Azure DevOps Work Items

- Merge Requests → Pull Requests (close before migration)

---- CI/CD pipelines (recreate manually)

- Wikis (planned for v3.0)

## 🏢 Team Initialization Packs- Project settings, permissions, webhooks



### Business Team Pack❌ **Does NOT support:**

- 📊 **10 wiki templates**: Requirements, user stories, acceptance criteria- Incremental/delta migrations after initial cutover

- 📝 **4 work item types**: Epic, Feature, User Story, Bug- Continuous sync between GitLab and Azure DevOps

- 📈 **Custom dashboard**: Business metrics and KPIs- Git LFS without manual configuration



### Dev Team Pack✅ **What it DOES:**

- 🔧 **7 wiki templates**: Architecture, API docs, deployment guides- Migrate complete Git history (commits, branches, tags)

- 🛠️ **Comprehensive workflows**: CI/CD, code review, branching strategy- Convert branch protection → branch policies

- 📊 **Dev dashboard**: Build status, test coverage, velocity- Provide audit trails and comprehensive logging

- Enable bulk migration workflows

### Security Team Pack

- 🔐 **7 wiki templates**: Security policies, incident response📖 **Full details:** [Limitations and Scope](docs/architecture/limitations.md)

- ✅ **Security configurations**: Branch policies, scanning setup

- 📋 **Compliance dashboard**: Vulnerability tracking, audit logs---



### Management Team Pack## 📖 Overview

- 📈 **8 wiki templates**: Project charter, roadmap, status reports

- 🎯 **Executive dashboards**: Portfolio health, resource allocation**API Integration:** Uses official [Microsoft Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/) and [GitLab REST API v4](https://docs.gitlab.com/ee/api/rest/) with Personal Access Tokens (PATs).

- 📊 **KPI tracking**: Delivery metrics, quality indicators

## Quick Start

---

### Option 1: Using .env File (Recommended)

## 🔧 Configuration

```powershell

### Environment Variables# 1. Create .env file from template

Copy-Item .env.example .env

Create a `.env` file (copy from `.env.example`):

# 2. Edit .env with your credentials

```bashnotepad .env

# GitLab Configuration

GITLAB_URL=https://gitlab.example.com# 3. Run preflight check

GITLAB_PAT=your-gitlab-personal-access-token.\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"



# Azure DevOps Configuration# 4. Execute migration

ADO_URL=https://dev.azure.com/your-org.\Gitlab2DevOps.ps1 -Mode Migrate -Source "mygroup/myproject" -Project "MyProject"

# OR for on-premise:```

# ADO_URL=https://your-ado-server.example.com/your-collection

ADO_PAT=your-azure-devops-personal-access-token### Option 2: Using Environment Variables



# Optional: Git LFS```powershell

GIT_LFS_SKIP_SMUDGE=1  # Skip downloading LFS during clone# 1. Set credentials as environment variables

```$env:ADO_COLLECTION_URL = "https://dev.azure.com/your-org"

$env:ADO_PAT = "your-ado-pat-here"

### Bulk Migration Config$env:GITLAB_BASE_URL = "https://gitlab.com"

$env:GITLAB_PAT = "your-gitlab-token-here"

Create `bulk-migration-config.json`:

# 2. Run preflight check

```json.\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"

{

  "destination_project": "ConsolidatedProject",# 3. Execute migration

  "projects": [.\Gitlab2DevOps.ps1 -Mode Migrate -Source "mygroup/myproject" -Project "MyProject"

    {```

      "gitlab_path": "group/frontend-app",

      "ado_repo_name": "frontend-app",📖 **First time?** Jump to [Step-by-Step Guide](#usage) for detailed instructions.  

      "description": "Frontend application"⚡ **Need quick commands?** Check the [Quick Reference Guide](QUICK_REFERENCE.md).  

    },📦 **Bulk migrations?** See [Bulk Migration Config Guide](BULK_MIGRATION_CONFIG.md).

    {

      "gitlab_path": "group/backend-api",## Table of Contents

      "ado_repo_name": "backend-api",

      "description": "Backend REST API"- [Features](#features)

    }- [Prerequisites](#prerequisites)

  ]- [Installation](#installation)

}- [Configuration](#configuration)

```- [Usage](#usage)

  - [Single Project Migration](#single-project-migration)

---  - [Bulk Migration](#bulk-migration-workflow)

  - [Re-running Migrations (Sync Mode)](#re-running-migrations-sync-mode)

## 📖 Documentation- [Project Structure](#project-structure)

- [Pre-Migration Report Format](#pre-migration-report-format)

### Getting Started- [Advanced Configuration](#advanced-configuration)

- 📘 [Quick Start Guide](docs/quickstart.md) - 5-minute setup- [Troubleshooting](#troubleshooting)

- 🎓 [Quick Setup](docs/QUICK_SETUP.md) - Detailed installation- [Security Features](#security-features)

- 📋 [CLI Usage Guide](docs/cli-usage.md) - Automation examples- [Contributing](#contributing)

- [License](#license)

### Configuration & Guides

- ⚙️ [Environment Configuration](docs/env-configuration.md)## 📚 Documentation

- 📦 [Bulk Migration Guide](docs/guides/BULK_MIGRATION_CONFIG.md)

- 👥 [Team Productivity Guide](docs/guides/TEAM_PRODUCTIVITY_GUIDE.md)### User Guides

- 📥 [User Import/Export](docs/USER_EXPORT_IMPORT.md)- 🔄 [Sync Mode Guide](docs/guides/SYNC_MODE_GUIDE.md) - Re-running migrations and keeping repositories in sync

- 📦 [Bulk Migration Configuration](docs/guides/BULK_MIGRATION_CONFIG.md) - Migrating multiple repositories

### Reference- ⚡ [Quick Reference](docs/reference/QUICK_REFERENCE.md) - Common commands and parameters

- 📚 [Work Item Templates](docs/WORK_ITEM_TEMPLATES.md)- 📋 [Work Item Templates](docs/WORK_ITEM_TEMPLATES.md) - Using standardized templates

- 🔍 [Quick Reference](docs/reference/QUICK_REFERENCE.md)

- 📊 [Project Summary](docs/reference/PROJECT_SUMMARY.md)### Technical Documentation

- ⚠️ [Limitations](docs/architecture/limitations.md)- 🏗️ [Project Summary](docs/reference/PROJECT_SUMMARY.md) - Architecture and technical overview

- 🗺️ [Implementation Roadmap](docs/development/IMPLEMENTATION_ROADMAP.md) - Development progress

### API & Troubleshooting- 📝 [Changelog](CHANGELOG.md) - Version history and migration guides

- 🔌 [API Error Reference](docs/api-errors.md)

- 🔧 [Best Practices](docs/BEST_PRACTICES_ALIGNMENT.md)### Contributing

- 🤝 [Contributing Guide](CONTRIBUTING.md) - How to contribute to this project

---- 📖 [Publishing Guide](docs/development/PUBLISHING_GUIDE.md) - Release process for maintainers



## 🏗️ Architecture### All Documentation

- 📚 [Documentation Index](docs/README.md) - Complete documentation directory

### Module Organization

## Features

```

modules/### 🚀 **Complete Migration Workflow**

├── Migration.psm1          # Main orchestration module- **Step 1**: GitLab project preparation and analysis

├── adapters/               # External system adapters- **Step 2**: Azure DevOps project creation with full organizational setup

│   ├── AzureDevOps.psm1   # ADO adapter (aggregates sub-modules)- **Step 3**: Repository migration with all refs, branches, and Git LFS support

│   ├── GitLab.psm1        # GitLab adapter

│   └── AzureDevOps/       # ADO sub-modules### 📊 **Project Analysis & Reporting**

│       ├── Core.psm1      # REST foundation- Repository size analysis and LFS detection

│       ├── Security.psm1  # Token masking- Comprehensive preflight reports (JSON format)

│       ├── Projects.psm1  # Project management- Migration logs with detailed timestamps

│       ├── Repositories.psm1  # Repository operations- Success/failure tracking with error diagnostics

│       ├── Wikis.psm1     # Wiki management

│       ├── WorkItems.psm1 # Work item operations### 🏢 **Enterprise-Ready Setup**

│       └── Dashboards.psm1 # Dashboard creation- **RBAC Groups**: Dev, QA, BA, Release Approvers, Pipeline Maintainers

├── core/                  # Core infrastructure- **Branch Policies**: Required reviewers, work item linking, build validation

│   ├── ConfigLoader.psm1  # JSON configuration loader- **Security Restrictions**: BA group cannot push/create PRs

│   ├── Core.Rest.psm1     # REST API with curl fallback- **Work Item Templates**: Complete Agile template set (User Story, Task, Bug, Epic, Feature, Test Case)

│   ├── EnvLoader.psm1     # Environment loader- **Project Wiki**: Automated setup with conventions documentation

│   └── Logging.psm1       # Logging and reporting- **Test Plan**: 4 test suites (Regression, Smoke, Integration, UAT)

├── dev/                   # Development utilities- **QA Queries**: 8 specialized queries for testing workflow

│   ├── DryRunPreview.psm1 # Migration preview- **QA Dashboard**: Comprehensive testing metrics with 8 widgets

│   ├── HtmlReporting.psm1 # HTML report generation- **Test Configurations**: 13 browser/OS/environment configurations

│   ├── ProgressTracking.psm1 # Progress tracking

│   └── Telemetry.psm1     # Telemetry collection### 📚 **Team Initialization Packs** ⭐ NEW in v2.1.0

├── Migration/             # Migration workflows- **Business Init**: 10 wiki pages (Welcome, Decision Log, Risks, Glossary, Ways of Working, KPIs, Training, Communication Templates, Cutover Timeline, Post-Cutover Summary) + 8 queries + dashboard

│   ├── Initialization/    # Project initialization- **Dev Init**: 7 wiki pages (ADR, Dev Setup, API Docs, Git Workflow, Code Review, Troubleshooting, Dependencies) + technical documentation

│   ├── TeamPacks/         # Team-specific templates- **Security Init**: 7 wiki pages (Security Policies, Threat Modeling, Security Testing, Incident Response, Compliance, Secret Management, Security Champions) + security queries + dashboard

│   └── Workflows/         # Migration workflows- **Management Init**: 8 wiki pages (Program Overview, Sprint Planning, Capacity Planning, Roadmap, RAID Log, Stakeholder Communications, Retrospectives, Metrics Dashboard) + 6 program management queries + executive dashboard

└── templates/             # Configuration templates- **Best Practices**: 6 wiki pages (Code Standards, Performance Optimization, Error Handling, Logging Standards, Testing Strategies, Documentation Guidelines)

```- **QA Guidelines**: 5 wiki pages (QA Overview, Test Strategy, Test Data Management, Automation Framework, Bug Lifecycle)

- **Total**: 43 wiki templates with ~18,000 lines of production-ready content

### Key Design Principles

### 📦 **Bulk Migration Support**

- **Modular Architecture**: Clear separation of concerns (adapters/core/workflows)- Multi-project preparation and analysis

- **Adapter Pattern**: GitLab and AzureDevOps modules never depend on each other- Consolidated migration templates

- **Idempotency**: All operations are safe to re-run- Batch processing with individual project tracking

- **Error Resilience**: Automatic retry with exponential backoff, curl fallback- Automated error handling and recovery

- **Security**: Token masking, credential cleanup, audit trails

- **Observability**: Structured logs, detailed reports, progress tracking### 🔧 **Advanced Features**

- Git LFS support with automatic detection

---- All Git refs migration (branches, tags, commit history)

- Build validation policy integration

## 🧪 Testing- SonarQube status check support

- Customizable security policies

```powershell

# Run all tests## Prerequisites

Invoke-Pester -Path '.\tests' -Output Detailed

### Required Software

# Run specific test suite- **PowerShell 5.1** or later

Invoke-Pester -Path '.\tests\OfflineTests.ps1' -Output Detailed- **Git** (with git-lfs for LFS repositories)

- **Network access** to both GitLab and Azure DevOps instances

# Run with coverage

Invoke-Pester -Configuration @{### Required Credentials

    Run = @{ Path = '.\tests\*.Tests.ps1' }- **Azure DevOps Personal Access Token (PAT)** with:

    CodeCoverage = @{   - Project and team: Read, write, & manage

        Enabled = $true  - Code: Full

        Path = '.\modules\*.psm1'  - Work items: Read, write, & manage

    }  - Graph: Read

}  - Security: Manage

```

- **GitLab Personal Access Token** with:

**Current Test Status**: 29/29 passing (100%) ✅  - `api` scope for project access

  - `read_repository` scope for Git operations

---

## Installation

## 🛡️ Security Best Practices

### Quick Install

1. **Never commit credentials**: Use `.env` file (git-ignored by default)

2. **Use PATs with minimal scope**: 1. **Clone the repository**:

   - GitLab: `read_api`, `read_repository`   ```powershell

   - Azure DevOps: `Code (Read & Write)`, `Project and Team (Read, Write, & Manage)`   git clone https://github.com/your-org/gitlab-to-azuredevops-migration.git

3. **Rotate tokens regularly**: Best practice is 90-day rotation   cd gitlab-to-azuredevops-migration

4. **Review audit logs**: Check `logs/` directory after each migration   ```

5. **Clean up credentials**: Tool automatically clears Git credentials after use

2. **Verify prerequisites**:

---   ```powershell

   # Check PowerShell version (should be 5.1+)

## 🤝 Contributing   $PSVersionTable.PSVersion

   

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.   # Check Git installation

   git --version

### Quick Contribution Guide   

   # Check Git LFS (optional, but recommended)

1. Fork the repository   git lfs version

2. Create a feature branch (`git checkout -b feature/amazing-feature`)   ```

3. Make your changes

4. Run tests (`Invoke-Pester -Path '.\tests' -Output Detailed`)3. **Set up credentials**:

5. Commit with conventional commits (`feat:`, `fix:`, `docs:`, etc.)   ```powershell

6. Push to your fork   # Copy the environment template

7. Open a Pull Request   cp setup-env.template.ps1 setup-env.ps1

   

---   # Edit setup-env.ps1 with your credentials (use notepad, VS Code, etc.)

   notepad setup-env.ps1

## 📝 Changelog   

   # Load the environment variables

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.   .\setup-env.ps1

   ```

**Latest Release**: v2.1.0   

- Self-contained folder structures   See [Configuration](#configuration) section for detailed credential setup.

- 43 wiki templates

- 4 team initialization packs4. **Run your first migration**:

- PowerShell approved verbs   ```powershell

- 100% test pass rate   # Generate pre-flight report

   .\Gitlab2DevOps.ps1 -Mode Preflight -Source "mygroup/myproject"

---   ```



## 📄 LicenseThat's it! You're ready to start migrating.



This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.## Configuration



---### 1. Initial Setup



## 🙏 AcknowledgmentsYou can configure the tool using **.env files** (recommended), **environment variables**, or **parameters**:



- Built with ❤️ for DevOps teams migrating to Azure DevOps#### Option A: Using .env File (Recommended - Most Secure)

- Designed for on-premise environments with SSL/TLS challenges```powershell

- Inspired by real-world enterprise migration experiences# 1. Create .env file from template

Copy-Item .env.example .env

---

# 2. Edit .env with your credentials

## 📞 Supportnotepad .env

# OR

- 📖 **Documentation**: Start with [Quick Start Guide](docs/quickstart.md)code .env

- 🐛 **Bug Reports**: [Open an issue](https://github.com/magedfarag/Gitlab2DevOps/issues)

- 💡 **Feature Requests**: [Open an issue](https://github.com/magedfarag/Gitlab2DevOps/issues)# 3. Run the script (automatically loads .env)

- 💬 **Questions**: Check [API Error Reference](docs/api-errors.md) and documentation.\Gitlab2DevOps.ps1

```

---

Your `.env` file should look like:

<div align="center">```bash

# Azure DevOps Configuration

**⭐ Star this repo if it helped your migration! ⭐**ADO_COLLECTION_URL=https://dev.azure.com/your-org

ADO_PAT=your-azure-devops-pat-here

Made with ❤️ by [Maged Farag](https://github.com/magedfarag)

# GitLab Configuration

</div>GITLAB_BASE_URL=https://gitlab.com

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
- Creates test plan with 4 test suites (Regression, Smoke, Integration, UAT) ⭐ NEW
- Creates 8 QA queries and QA dashboard for testing workflow ⭐ NEW
- Configures 13 test configurations for cross-platform testing ⭐ NEW
- Adds QA Guidelines wiki page with testing documentation ⭐ NEW
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

### ⚠️ v2.1.0 Breaking Change: Self-Contained Folder Structures

Starting in v2.1.0, both single and bulk migrations use **self-contained folder hierarchies** for better organization and portability:

**Single Migration Structure:**
```
Gitlab2DevOps/
├── Gitlab2DevOps.ps1
├── modules/                      # PowerShell modules
└── migrations/                   # Migration workspace
    └── MyDevOpsProject/          # Azure DevOps project (parent)
        ├── migration-config.json # Project metadata
        ├── reports/              # Project-level reports
        ├── logs/                 # Project-level logs
        └── my-gitlab-project/    # GitLab project (child)
            ├── reports/          # GitLab-specific reports
            │   └── preflight-report.json
            └── repository/       # Bare Git mirror
```

**Bulk Migration Structure:**
```
migrations/
└── ConsolidatedProject/          # Azure DevOps project (parent)
    ├── bulk-migration-config.json
    ├── reports/
    │   └── preparation-summary.json
    ├── logs/
    │   └── bulk-preparation-YYYYMMDD-HHMMSS.log
    ├── frontend-app/             # GitLab project 1
    │   ├── reports/
    │   │   └── preflight-report.json
    │   └── repository/
    ├── backend-api/              # GitLab project 2
    │   ├── reports/
    │   │   └── preflight-report.json
    │   └── repository/
    └── infrastructure/           # GitLab project 3
        ├── reports/
        │   └── preflight-report.json
        └── repository/
```

**Benefits:**
- ✅ Clear 1:1 relationship: DevOps project → GitLab projects
- ✅ Self-contained: Archive/move entire project by moving one folder
- ✅ Consistent structure for single and bulk migrations
- ✅ Support for multiple GitLab projects per DevOps project

**Migration Path:** Legacy projects (v2.0.x flat structure) will display with `[legacy]` indicator in Option 2 menu. Re-prepare using Option 1 to convert to v2.1.0 structure.

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
Comprehensive templates for all Agile work item types:
- **User Story**: Definition of Ready/Done, acceptance criteria with Gherkin scenarios
- **Task**: Implementation checklist, dependency tracking, effort estimation
- **Bug**: Structured reproduction steps, environment details, triage information
- **Epic**: Strategic initiatives with success metrics and risk assessment
- **Feature**: Product capabilities with user value and requirements breakdown
- **Test Case**: Quality validation with structured test steps and prerequisites

Each template includes standardized fields, descriptions, and team collaboration features.

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
