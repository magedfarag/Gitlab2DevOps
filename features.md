# GitLab to Azure DevOps Migration Tool - Features

## Overview

The GitLab to Azure DevOps Migration Tool is an enterprise-grade solution for migrating GitLab projects to Azure DevOps Server (on-premises) or Azure DevOps Cloud. The tool provides comprehensive migration capabilities with full project initialization, governance, and team collaboration features.

## Core Migration Capabilities

### Single Project Migration
- **Pre-migration validation** via `New-MigrationPreReport` - analyzes GitLab project compatibility and generates blocking issue reports
- **Repository migration** with full Git history preservation (commits, branches, tags)
- **Automatic cleanup** of Azure DevOps default repositories using `Remove-AdoDefaultRepository`
- **Branch governance** enforcement with minimum reviewer policies, work item linking, and comment resolution requirements
- **Build validation** integration with optional external status checks (SonarQube, etc.)
- **Comprehensive observability** with structured logging, JSON summaries, HTML reports, and portfolio dashboards

### Bulk Migration Workflow
- **Bulk preparation** from `projects.json` configuration files with automatic path resolution
- **Parallel processing** of multiple GitLab projects with consolidated metadata storage
- **Bulk execution** reusing single-project migration logic for consistency
- **Portfolio reporting** with per-project HTML status pages and consolidated dashboards
- **Error resilience** with individual project failure handling and summary reporting

### Unattended Batch Migration (Option 9)
- **Automated discovery** of all prepared migration projects via `Get-PreparedProjects`
- **Headless execution** with suppressed interactive prompts for CI/CD integration
- **Complete project enhancement** - automatically applies all four team initialization packs (Business, Development, Security, Management) after successful migration
- **Excel work item import** - auto-detects `requirements.xlsx` files and populates backlogs using `Import-AdoWorkItemsFromExcel`
- **Progress tracking** with success/failure counts and detailed execution summaries

## Command Line Interface (CLI) Operations

The tool supports comprehensive CLI operations for automation and scripting scenarios:

### CLI Mode Operations
- **Preflight**: `.\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/project"` - Pre-migration analysis without execution
- **Initialize**: `.\Gitlab2DevOps.ps1 -Mode Initialize -Source "group/project" -Project "MyProject"` - Project setup with governance
- **Migrate**: `.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "MyProject"` - Complete single project migration
- **BulkPrepare**: `.\Gitlab2DevOps.ps1 -Mode BulkPrepare` - Interactive bulk preparation workflow
- **BulkMigrate**: `.\Gitlab2DevOps.ps1 -Mode BulkMigrate` - Execute bulk migration from prepared configuration

### Team Initialization Modes
- **BusinessInit**: `.\Gitlab2DevOps.ps1 -Mode BusinessInit -Project "MyProject"` - Business team resources and processes
- **DevInit**: `.\Gitlab2DevOps.ps1 -Mode DevInit -Project "MyProject"` - Development team tools and workflows
- **SecurityInit**: `.\Gitlab2DevOps.ps1 -Mode SecurityInit -Project "MyProject"` - Security policies and scanning
- **ManagementInit**: `.\Gitlab2DevOps.ps1 -Mode ManagementInit -Project "MyProject"` - PMO and executive reporting

### CLI Control Flags
- **`-Force`**: Override preflight validation and blocking issues
- **`-Replace`**: Destructive repository recreation (removes existing repository)
- **`-AllowSync`**: Enable synchronization of existing repositories
- **`-WhatIf`**: Preview mode without executing changes

### Authentication & Configuration
- **GitLab**: `-GitLabToken` parameter or `$env:GITLAB_PAT` environment variable
- **Azure DevOps**: `-AdoPat` parameter or `$env:ADO_PAT` environment variable
- **Base URLs**: `-GitLabBaseUrl` and `-AdoBaseUrl` for custom endpoints
- **SSL Handling**: Automatic fallback to `curl -k` for on-premise servers with certificate issues

## Identity Management (Options 5 & 6)

### Export User Information (Option 5)
- **Export profiles**: Minimal (users/groups), Standard (+projects), Complete (+memberships)
- **Output formats**: Timestamped JSON files with metadata and operation logs
- **Offline operation**: GitLab-only connectivity, no Azure DevOps dependency
- **Incremental exports**: Multiple export runs supported for data updates

### Import User Information (Option 6)
- **Preview mode**: Dry-run capability to validate import operations
- **Azure DevOps integration**: Creates groups and manages memberships
- **User resolution**: Requires users to exist in Active Directory/Azure AD
- **Validation**: Pre-import file existence and format checking

## Team Initialization Packs

### Business Team Pack
**Wiki Pages** (9 total):
- Business-Welcome, Decision-Log, Risks-Issues, Glossary
- Ways-of-Working, KPIs-and-Success, Training-Quick-Start
- Communication-Templates, Post-Cutover-Summary

**Shared Queries** (8 total):
- My Active Work, Team Backlog, Active Bugs, Ready for Review
- Blocked Items, Current Sprint Commitment, Unestimated Stories, Epics by Target Date

**Additional Features**:
- 3-week iteration seeding, stakeholder dashboard creation
- Project summary wiki updates with `business-init-summary.json` and metrics reporting

### Development Team Pack
**Wiki Pages** (7 total):
- Architecture-Decision-Records, Development-Setup, API-Documentation
- Git-Workflow, Code-Review-Checklist, Troubleshooting, Dependencies

**Shared Queries** (5 total):
- My PRs Awaiting Review, PRs I Need to Review, Technical Debt
- Recently Completed, Code Review Feedback

**Repository Files** (4 total):
- `.gitignore` (project-type aware), `.editorconfig`, `CONTRIBUTING.md`, `CODEOWNERS`

**Additional Features**:
- Development dashboard creation, project summary updates
- Project type detection for appropriate `.gitignore` templates

### Security Team Pack
**Wiki Pages** (7 total):
- Security-Policies, Threat-Modeling-Guide, Security-Testing-Checklist
- Incident-Response-Plan, Compliance-Requirements, Secret-Management, Security-Champions-Program

**Shared Queries** (5 total):
- Security Bugs (Priority 0-1), Vulnerability Backlog, Security Review Required
- Compliance Items, Security Debt

**Repository Files** (4 total):
- `SECURITY.md`, `security-scan-config.yml`, `.trivyignore`, `.snyk`

**Additional Features**:
- Security dashboard creation, compliance artifact scaffolding
- Shift-left security practices integration

### Management Team Pack
**Wiki Pages** (8 total):
- Program-Overview, Sprint-Planning, Capacity-Planning, Roadmap
- RAID-Log, Stakeholder-Communications, Retrospectives, Metrics-Dashboard

**Shared Queries** (6 total):
- Program Status, Sprint Progress, Active Risks, Open Issues
- Cross-Team Dependencies, Milestone Tracker

**Additional Features**:
- Executive dashboard creation, PMO infrastructure setup
- Program management and stakeholder reporting capabilities

### Team Pack Enhancement (Option 7)
- **Existing project discovery**: Lists all available Azure DevOps projects
- **Individual pack selection**: Choose specific packs or install all simultaneously
- **Idempotent operations**: Safe re-application to existing projects
- **Project validation**: Verifies project existence before enhancement

## Work Item Management

### Work Item Templates
Comprehensive templates for all Agile process work item types:
- **User Story**: Definition of Ready/Done checklists, acceptance criteria, Gherkin-ready sections
- **Task**: Implementation checklists, work tracking, dependency management
- **Bug**: Structured reproduction steps, severity/priority fields, environment capture
- **Epic**: Success metrics, scope breakdown, risk assessment
- **Feature**: Requirement decomposition, user value articulation
- **Test Case**: Test steps, prerequisites, validation criteria

### Excel Work Item Import
- **Spreadsheet processing**: Reads `.xlsx`/`.xls` files with custom worksheet support
- **Hierarchical relationships**: Epic → Feature → User Story → Test Case parent-child linking
- **Work item type mapping**: Automatic mapping to Azure DevOps process templates (Agile, Scrum, CMMI, Basic)
- **Field mapping**: Core fields (Title, Description, State, Priority, Assigned To)
- **Agile fields**: Story Points, Business Value, Value Area, Risk
- **Scheduling fields**: Start/Finish/Target/Due dates, Original/Remaining/Completed work
- **Test case fields**: Excel format test steps with expected results
- **Project integration**: Automatic area/iteration setup and current sprint assignment
- **Safety features**: Idempotent operations, cycle detection, validation, progress tracking

## Repository Governance & Security

### Repository Lifecycle Management
- **Default repository cleanup**: Automatic removal of auto-created repositories in new projects
- **Branch policy enforcement**: Minimum reviewers, work item linking, comment resolution
- **Build validation**: Optional CI/CD integration with status checks
- **Security scanning**: Repository-level security configuration and compliance artifacts

### Security-First Repository Setup
- **Compliance artifacts**: SECURITY.md, scan configurations, ignore files
- **Vulnerability management**: Trivy and Snyk integration setup
- **Security champions**: Program documentation and team structure
- **Threat modeling**: Integrated security assessment frameworks

## Reporting & Observability

### Per-Migration Artifacts
- **Structured logging**: `logs/migration-*.log` with execution timelines
- **JSON summaries**: `migration-summary.json`, `migration-error.json`
- **HTML status pages**: Individual project migration reports
- **Initialization metrics**: `*-init-summary.json` and `*-init-metrics.json` files

### Portfolio-Level Reporting
- **Overview dashboard**: Auto-refreshed `migrations/index.html` with project status
- **Bulk execution summaries**: Consolidated results across multiple projects
- **Team pack metrics**: Initialization success tracking and feature adoption
- **User export/import logs**: Identity migration traceability

## Technical Architecture

### Module Organization
- **Core modules**: REST API foundation with SSL/TLS fallback, logging framework
- **GitLab integration**: Clean API client with no Azure DevOps dependencies
- **Azure DevOps operations**: Focused modules for projects, repositories, work items, wikis
- **Migration workflows**: Orchestration logic coordinating GitLab → Azure DevOps transformations
- **Team packs**: Specialized initialization modules for different team types

### Error Handling & Resilience
- **SSL/TLS compatibility**: Automatic curl fallback for on-premise certificate issues
- **Idempotent operations**: Safe re-execution without duplicate creation
- **Graceful degradation**: Best-effort mode for testing and partial environments
- **Comprehensive validation**: Pre-flight checks and blocking issue detection

### Security & Compliance
- **Credential masking**: Secure token handling with `Hide-Secret` functionality
- **Audit trails**: Complete operation logging with timestamps
- **Access control**: PAT-based authentication with minimal required permissions
- **Data protection**: Local processing with no external data transmission

## Integration & Automation

### CI/CD Pipeline Integration
- **Headless execution**: Full automation support via CLI modes
- **Exit codes**: Success/failure status for pipeline integration
- **Log aggregation**: Structured output for monitoring systems
- **Configuration management**: Environment variable and parameter-based setup

### Enterprise Deployment
- **On-premise compatibility**: Azure DevOps Server support with SSL handling
- **Active Directory integration**: User identity mapping and group management
- **Scalability**: Bulk operations for large-scale migrations
- **Monitoring**: Comprehensive reporting for enterprise governance

---

*This tool focuses on Git repository migration with full history preservation. Issues, merge requests, CI/CD pipelines, and project settings require separate handling as they involve different data models and manual recreation.*
