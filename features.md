# Features

## Migration Automation

### Single Project Migration (`modules/Migration/Workflows/SingleMigration.psm1`)
- Pre-migration validation via `New-MigrationPreReport`, producing `pre-migration-report.json` and blocking on missing prerequisites.
- Automatic removal of the Azure DevOps default repository (when present) before provisioning a clean target via `Remove-AdoDefaultRepository`.
- Repository provisioning/push flow: create or reuse the repo, clone cached GitLab mirror, push all refs/tags with PAT-authenticated remotes, and clean credentials on completion.
- Branch governance: applies minimum-reviewer, work-item-link, and comment-resolution policies plus optional build/status checks on the default branch.
- Observability per run: structured log file (`logs/migration-*.log`), success/error JSON summaries, HTML project report, refreshed `migrations/index.html`, and optional init summary metrics.

### Bulk Preparation & Execution (`Prepare-MigrationsFromConfig.ps1`, `modules/Migration/Workflows/BulkMigration.psm1`)
- Option 8 triggers unattended preparation from `projects.json`, resolves config paths automatically, and forces refreshes for every listed GitLab path.
- Bulk preparation stores per-project metadata, cached repos, and a consolidated `bulk-migration-config.json` with size, LFS, branch, and status data.
- Bulk execution reuses `Invoke-SingleMigration` per repository, captures execution logs, appends `migration_results`, and writes an `execution_summary` plus `bulk-execution-init-summary.json`.
- Per-project HTML status pages are regenerated after each successful bulk migration alongside the portfolio dashboard.

### Unattended Migration Run (Interactive Option 9, `modules/Migration/Menu/Menu.psm1`)
- Discovers all prepared single and bulk entries via `Get-PreparedProjects`, skipping anything already marked as migrated.
- Temporarily suppresses confirmation prompts/WhatIf to enable headless execution.
- Handles single and bulk preparations in the same batch, recording success/failure counts and printing a run summary.
- When the prepared item is **single-project**, Option 9 simply invokes `Invoke-SingleMigration`, so every capability listed in *Single Project Migration* (repo cleanup, policy enforcement, observability assets, etc.) is executed automatically with no functional differences from a manual run.
- When the prepared item is **bulk**, Option 9 routes through `Invoke-BulkMigrationWorkflow`, which itself drives `Invoke-SingleMigration` for every repo during execution; as a result, the behaviors described in both the *Single Project Migration* and *Bulk Preparation & Execution* sections occur for each target Azure DevOps project.
- After each successful migration (single or bulk), Option 9 now automatically applies **all** initialization packs (Business, Development, Security, Management) so every Azure DevOps project gets the full set of wikis, queries, dashboards, repo files, and readiness reports without any additional prompts.

## Identity Management Options (`docs/USER_EXPORT_IMPORT.md`)

- **Option 5 – Export User Information**
  - Profiles: Minimal (users/groups), Standard (+projects), Complete (+all memberships).
  - Outputs timestamped folders containing `users.json`, `groups.json`, `projects.json`, `group-memberships.json`, `project-memberships.json`, `metadata.json`, and `export.log`.
- **Option 6 – Import User Information**
  - Modes: Dry Run (preview) or Execute (apply changes).
  - Validates source files, creates Azure DevOps groups, and maps memberships based on earlier exports.

## Initialization & Team Packs (`modules/Migration/TeamPacks/TeamPacks.psm1`)

### Business Pack
- **Wiki pages**
  - [x] Business-Welcome
  - [x] Decision-Log
  - [x] Risks-Issues
  - [x] Glossary
  - [x] Ways-of-Working
  - [x] KPIs-and-Success
  - [x] Training-Quick-Start
  - [x] Communication-Templates
  - [x] Post-Cutover-Summary
- **Shared queries**
  - [x] My Active Work
  - [x] Team Backlog
  - [x] Active Bugs
  - [x] Ready for Review
  - [x] Blocked Items
  - [x] Current Sprint Commitment
  - [x] Unestimated Stories
  - [x] Epics by Target Date
- Seeds three 2-week iterations, provisions a stakeholder dashboard, updates the project summary wiki, and saves `business-init-summary.json` plus `business-init-metrics.json`.

### Development Pack
- **Wiki pages**
  - [x] Architecture-Decision-Records
  - [x] Development-Setup
  - [x] API-Documentation
  - [x] Git-Workflow
  - [x] Code-Review-Checklist
  - [x] Troubleshooting
  - [x] Dependencies
- **Queries**
  - [x] My PRs Awaiting Review
  - [x] PRs I Need to Review
  - [x] Technical Debt
  - [x] Recently Completed
  - [x] Code Review Feedback
- **Repository files**
  - [x] `.gitignore` (project-type aware)
  - [x] `.editorconfig`
  - [x] `CONTRIBUTING.md`
  - [x] `CODEOWNERS`
- Generates a development dashboard, updates the summary wiki, and writes `dev-init-summary.json` plus `dev-init-metrics.json`.

### Security Pack
- **Wiki pages**
  - [x] Security-Policies
  - [x] Threat-Modeling-Guide
  - [x] Security-Testing-Checklist
  - [x] Incident-Response-Plan
  - [x] Compliance-Requirements
  - [x] Secret-Management
  - [x] Security-Champions-Program
- **Queries**
  - [x] Security Bugs (Priority 0-1)
  - [x] Vulnerability Backlog
  - [x] Security Review Required
  - [x] Compliance Items
  - [x] Security Debt
- **Repository files**
  - [x] `SECURITY.md`
  - [x] `security-scan-config.yml`
  - [x] `.trivyignore`
  - [x] `.snyk`
- Adds a security dashboard, updates the summary wiki, and captures `security-init-summary.json` plus `security-init-metrics.json`.

### Management Pack
- **Wiki pages**
  - [x] Program-Overview
  - [x] Sprint-Planning
  - [x] Capacity-Planning
  - [x] Roadmap
  - [x] RAID-Log
  - [x] Stakeholder-Communications
  - [x] Retrospectives
  - [x] Metrics-Dashboard
- **Queries**
  - [x] Program Status
  - [x] Sprint Progress
  - [x] Active Risks
  - [x] Open Issues
  - [x] Cross-Team Dependencies
  - [x] Milestone Tracker
- Produces a leadership dashboard, updates the summary wiki, and emits `management-init-summary.json` plus `management-init-metrics.json`.

## Work Item Templates (`docs/WORK_ITEM_TEMPLATES.md`)
- [x] **User Story – DoR/DoD:** includes Definition of Ready/Done checklists, acceptance criteria blocks, and Gherkin-ready sections.
- [x] **Task – Implementation:** prescribes implementation checklist, remaining work tracking, and dependency notes.
- [x] **Bug – Triaging & Resolution:** enforces structured repro steps, severity/priority fields, and environment capture.
- [x] **Epic – Strategic Initiative:** captures success metrics, scope breakdown, and risk assessment.
- [x] **Feature – Product Capability:** standardizes requirement decomposition and user value articulation.
- [x] **Test Case – Quality Validation:** prepopulates test steps, prerequisites, and validation criteria.

## Repository Governance & Security
- Default repository cleanup for new projects ensures migrations always target an empty Git repo.
- Consistent enforcement of required reviewer, work-item-link, and comment-resolution policies, plus optional build validation and external status checks.
- Security-specific repo scaffolding (scan configs, Trivy, Snyk) keeps compliance artifacts in source control.

## Reporting & Observability
- Per-migration assets: `preflight-report.json`, `migration-summary.json`, `migration-error.json`, HTML status pages, `migration-init-summary.json`, and structured logs.
- Portfolio-level assets: auto-refreshed `migrations/index.html`, bulk execution summaries, and init metrics for each team pack.
- User export/import logs and metadata capture traceability for identity migrations.

## Excel Work Item Import (`modules/AzureDevOps/WorkItems.psm1`)

### Requirements.xlsx Processing
- **Excel File Reading**: Reads work items from Excel spreadsheets (.xlsx/.xls format) with support for custom worksheet names (defaults to "Requirements")
- **Hierarchical Work Item Creation**: Supports parent-child relationships using LocalId/ParentLocalId columns for Epic → Feature → User Story → Test Case hierarchies
- **Work Item Type Resolution**: Automatically maps Excel work item types to Azure DevOps project-available types (Agile, Scrum, CMMI, Basic process templates)
- **Field Mapping**: Comprehensive field support including:
  - Core fields: Title, Description, State, Priority, Assigned To
  - Agile fields: Story Points, Business Value, Value Area, Risk
  - Scheduling: Start Date, Finish Date, Target Date, Due Date, Original Estimate, Remaining Work, Completed Work
  - Test Case fields: Test Steps (Excel format: "step1|expected1;;step2|expected2")
  - Custom fields: Tags, Effort tracking, Business-specific fields

### Azure DevOps Integration
- **Project Context Detection**: Automatically determines project areas, iterations, and team settings
- **Classification Node Management**: Creates default Area and Iteration structures if missing (with fallback to project root)
- **Current Iteration Assignment**: Attempts to assign work items to current team sprint when available
- **Work Item Relationships**: Establishes parent-child links between imported work items
- **Idempotent Operations**: Safely handles re-imports without creating duplicates
- **Error Handling**: Comprehensive error reporting with debug logs for failed imports

### Validation & Safety Features
- **Excel File Validation**: Validates file existence and format before processing
- **Field Validation**: Checks allowed values for State, Priority, and custom fields against Azure DevOps project rules
- **Cycle Detection**: Prevents circular parent-child relationships
- **Progress Tracking**: Real-time progress reporting with success/error counts
- **Debug Diagnostics**: Detailed failure logs with JSON payloads for troubleshooting

### Usage Examples
```powershell
# Basic import with default settings
Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\requirements.xlsx"

# Advanced import with custom worksheet and API version
Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\reqs.xlsx" -WorksheetName "Sprint1" -ApiVersion "6.0"
```

### Expected Excel Format
| LocalId | WorkItemType | Title | ParentLocalId | State | Priority | Description | StoryPoints | Tags |
|---------|--------------|-------|---------------|-------|----------|-------------|-------------|------|
| E1 | Epic | User Management | | New | 1 | Epic for user features | | epic |
| F1 | Feature | Authentication | E1 | New | 2 | Login/logout features | | feature |
| US1 | User Story | User Login | F1 | Active | 3 | As a user I can log in | 5 | frontend |
| TC1 | Test Case | Login Test | US1 | Design | 2 | Test login functionality | | test |
