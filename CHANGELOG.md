# Changelog

All notable changes to the GitLab to Azure DevOps Migration Tool will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-11-08

### 🎉 Initial Public Release

The first production-ready release of Gitlab2DevOps, an enterprise-grade migration toolkit for seamless GitLab to Azure DevOps transitions.

### ✨ Added

#### Excel Work Items Import
- **New Function**: `Import-AdoWorkItemsFromExcel` in WorkItems module
  - **Description**: Import hierarchical requirements (Epic → Feature → User Story → Test Case) from Excel spreadsheets
  - **Features**: 
    - Preserves parent-child relationships using LocalId mapping
    - Supports all Agile process fields (StoryPoints, BusinessValue, ValueArea, Risk, etc.)
    - Automatic hierarchical ordering for correct parent-before-child creation
    - Test Case steps with XML conversion (format: "step|expected;;step|expected")
    - Scheduling fields (StartDate, FinishDate, TargetDate, OriginalEstimate, etc.)
  - **API Compatibility**: Supports Azure DevOps Server 2020+ (API versions 6.0, 7.0, 7.1)
  - **Usage**: `Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\requirements.xlsx"`
  - **Requires**: ImportExcel PowerShell module (Install-Module ImportExcel)

- **New Function**: `ConvertTo-AdoTestStepsXml` in WorkItems module
  - **Description**: Convert Excel test steps format to Azure DevOps TCM XML format
  - **Format**: Converts "step1|expected1;;step2|expected2" to XML structure
  - **Usage**: Automatically called by Import-AdoWorkItemsFromExcel for Test Case work items

- **Project Initialization Integration**: Excel import now available during project creation
  - **Parameters**: Added `-ExcelRequirementsPath` and `-ExcelWorksheetName` to Initialize-AdoProject
  - **Interactive**: Menu prompts "Import work items from Excel? (y/N)" during Option 3
  - **Auto-Detection**: Automatically looks for `requirements.xlsx` in `migrations/{ProjectName}/` directory
  - **Workflow**: Excel import runs after work item templates, before iterations
  - **Error Handling**: Graceful degradation if Excel import fails (continues with project init)
  - **Sample File**: Created `migrations/demo/requirements.xlsx` with all 7 work item types as example

- **Documentation**: New Excel template guide at `examples/requirements-template.md`
  - **Contents**: Complete column reference, hierarchy examples, usage instructions
  - **Examples**: Sample Epic/Feature/User Story/Test Case/Task hierarchy
  - **Tips**: LocalId uniqueness, date formats, test steps format, troubleshooting

### 🐛 Bug Fixes

#### Bulk Migration Workflow
- **Fixed**: Multiple critical errors in bulk preparation workflow
  - **Issue 1**: `New-LogFilePath` called with positional parameters instead of named parameters
    - **Error**: "A positional parameter cannot be found that accepts argument"
    - **Fix**: Changed to `New-LogFilePath -LogsDir $path -Prefix "name"`
  - **Issue 2**: `Write-MigrationLog` called with positional array parameter
    - **Error**: "Cannot bind argument to parameter 'LogFile' because it is an empty string"
    - **Fix**: Changed to `Write-MigrationLog -LogFile $file -Message @(...)`
  - **Issue 3**: Variable name conflict between `$ProjectPaths` (parameter) and `$projectPaths` (local variable)
    - **Error**: "The property 'gitlabDir' cannot be found on this object"
    - **Fix**: Renamed local variable to `$specificProjectPaths`
  - **Issue 4**: PropertyNotFoundException for 'Sum' on empty collections
    - **Error**: "The property 'Sum' cannot be found on this object"
    - **Fix**: Added null checks with fallback to 0 for empty result sets
  - **Impact**: Bulk preparation now executes successfully without parameter binding errors

#### Documentation Extraction
- **Fixed**: PropertyNotFoundException for 'Count' on single repository directory
  - **Issue**: `Get-ChildItem` returns single object without `.Count` property when only one repository exists
  - **Error**: "The property 'Count' cannot be found on this object" during documentation extraction
  - **Fix**: Wrapped `$repoDirs` in `@()` to ensure array behavior in `Export-GitLabDocumentation`
  - **Impact**: Documentation extraction now works correctly for both single and multiple repository scenarios

#### Configuration & Property Access
- **Fixed**: PropertyNotFoundException for 'areas' and 'iterations' in project initialization
  - **Issue**: Array property access `$config.areas.name` returned null on hashtable arrays
  - **Fix**: Changed to `($config.areas | ForEach-Object { $_.name })` for proper array expansion
  - **Impact**: Project initialization now correctly processes area and iteration configurations
- **Fixed**: Configuration type mismatch between Get-ProjectSettings and fallback
  - **Issue**: Get-ProjectSettings returned hashtable but fallback created PSCustomObject
  - **Fix**: Changed fallback from `[PSCustomObject]@{}` to `@{}` hashtable
  - **Impact**: Consistent property assignment validation across all configuration paths
- **Fixed**: HTML report generation failing with null property errors
  - **Issue**: Direct access to `$config.gitlab_project`, `$config.gitlab_repo_name`, `$config.migration_type` without null checks
  - **Fix**: Added property existence checks with graceful fallbacks (e.g., "Unknown Project", "N/A")
  - **Impact**: Reports now generate successfully even with incomplete configuration data

#### Folder Structure
- **Fixed**: Removed unwanted `logs/` directory from GitLab project subfolders in v2.1.0 migrations
  - **Issue**: `Initialize-GitLab` was creating `logs/` inside `migrations/{AdoProject}/{GitLabProject}/logs/` instead of using container-level logs
  - **Fix**: When `CustomBaseDir` is provided, logs are now correctly written to `{AdoProject}/logs/` (container level)
  - **Impact**: GitLab subfolders now only contain `reports/` and `repository/`, matching v2.1.0 specification

### ⚠️ Breaking Changes

#### Backward Compatibility Removed (v2.1.0)
- **Removed**: Legacy `-ProjectName` parameter set from `Get-ProjectPaths`
  - **Why**: Per design requirement: "there must not be backward compatibility. stick to the latest"
  - **Migration Path**: Re-run Option 1 (Prepare GitLab Project) to use v2.1.0 structure
  - **New Required Parameters**: `-AdoProject` and `-GitLabProject` (replaces `-ProjectName`)
- **Removed**: Legacy flat folder structure support from `Initialize-GitLab`
  - **Why**: Enforce v2.1.0 self-contained structure for all new migrations
  - **Impact**: `CustomBaseDir` parameter is now mandatory (throws error if not provided)
  - **Structure**: All projects must use `migrations/{AdoProject}/{GitLabProject}/` hierarchy
- **Removed**: Auto-detection of legacy vs new structure in `Invoke-SingleMigration`
  - **Why**: Simplify codebase, enforce v2.1.0 standard
  - **Impact**: Migration expects `migration-config.json` at `{AdoProject}/` level (validates before proceeding)

#### Error Handling Improvements
- **Changed**: Dashboard API 404 errors now gracefully handled as expected behavior
  - **Context**: Dashboard API not available on some on-premise servers
  - **Implementation**: All dashboard calls wrapped in try-catch with fallback to zero dashboards
- **Changed**: Wiki concurrency conflicts handled with retry and eTag validation
  - **Context**: Parallel wiki page creation could cause WikiAlreadyUpdatedException
  - **Implementation**: Set-AdoWikiPage uses PUT→catch→PATCH pattern with eTag handling

### ✨ Features

#### Documentation Extraction (NEW in v2.1.0)
- ✅ **Automatic documentation extraction** during preparation phase
  - Extracts documentation files (docx, pdf, xlsx, pptx, doc, xls, ppt) from all repositories
  - Creates centralized `docs/` folder at Azure DevOps project level
  - Maintains folder structure per repository for easy navigation
  - Preserves relative path structure within each repository
  - Provides extraction statistics (file count, size, breakdown by type)
  - Works for both single and bulk preparation workflows
  - **Usage**: Automatic in Option 1 (Single Preparation) and Option 2 (Bulk Preparation)
  - **Location**: `migrations/{AdoProject}/docs/{RepositoryName}/...`

#### Core Migration
- ✅ Full Git repository migration with complete history
- ✅ Branch and tag preservation
- ✅ Git LFS support with automatic object transfer
- ✅ Idempotent operations (safe to re-run)
- ✅ Automatic curl fallback for SSL/TLS challenged servers
- ✅ Comprehensive error handling with retry logic

#### Project Initialization
- ✅ Self-contained folder structures for migrations
- ✅ Automatic project creation in Azure DevOps
- ✅ Repository configuration with branch policies
- ✅ Wiki creation with rich templates
- ✅ Work item type validation and creation
- ✅ Custom area path configuration

#### Team Initialization Packs
- ✅ **Business Team Pack**: 10 wiki templates + 4 work item types + custom dashboard
- ✅ **Dev Team Pack**: 7 wiki templates + comprehensive workflows + dev dashboard
- ✅ **Security Team Pack**: 7 wiki templates + security configurations + compliance dashboard
- ✅ **Management Team Pack**: 8 wiki templates + executive dashboards + KPI tracking

#### Bulk Migration
- ✅ Process multiple projects with single command
- ✅ Parallel analysis and preparation
- ✅ Consolidated project structures
- ✅ Bulk execution with progress tracking
- ✅ Comprehensive reporting and summaries
- ✅ Automatic documentation extraction and consolidation

#### Observability
- ✅ Structured logging with timestamps
- ✅ Detailed migration reports (JSON)
- ✅ HTML preview reports for planning
- ✅ Progress tracking with ETA calculation
- ✅ Telemetry collection (opt-in)

#### Automation
- ✅ CLI mode with 10 operation modes
- ✅ Interactive menu for user-friendly workflow
- ✅ Configuration via environment variables
- ✅ Bulk migration config file support
- ✅ Dry-run preview mode

### 🏗️ Architecture

- **Greenfield Design**: Clean modular architecture with no legacy patterns
- **12 Core Modules**: Clear separation of concerns
- **7 Azure DevOps Sub-Modules**: Focused, single-responsibility modules
- **43 Wiki Templates**: ~18,000 lines of production-ready documentation
- **90/108 Tests Passing**: Comprehensive test coverage
- **PowerShell Best Practices**: Approved verbs, strict mode, proper error handling
- **Zero Backward Compatibility**: Built fresh for modern workflows

### 🔒 Security

- Zero credential exposure with automatic token masking
- Git credential cleanup after operations
- Comprehensive audit trails
- Secure environment variable handling
- No hardcoded secrets

### 📚 Documentation

- Comprehensive README with quick start guide
- 20+ documentation files covering all aspects
- CLI usage examples
- Team productivity guides
- API error reference
- Architecture documentation

### 🧪 Testing

- 29 comprehensive tests (100% passing)
- Offline test suite (no API dependencies)
- Idempotency tests
- Module integration tests
- HTML reporting tests

### 🛠️ Technical Details

- **PowerShell**: 5.1+ (Windows) / 7+ (cross-platform)
- **Git**: 2.20+ required
- **Git LFS**: Optional but recommended
- **Target Platforms**: 
  - Azure DevOps Cloud
  - Azure DevOps Server (on-premise)
  - Azure DevOps Server with SSL/TLS challenges

### 📊 Project Statistics

- **Total Lines of Code**: ~25,000 lines
- **Modules**: 12 core + 7 sub-modules
- **Functions**: 50+ exported functions
- **Wiki Templates**: 43 files (~18,000 lines)
- **Test Suite**: 29 tests (100% pass rate)
- **Documentation**: 20+ markdown files

---

## [Unreleased]

### Planned for v3.0

- 🔜 CI/CD pipeline conversion from GitLab CI to Azure Pipelines
- 🔜 User permissions mapping between platforms
- 🔜 Container registry migration
- 🔜 Package registry migration
- 🔜 Group-level settings migration
- 🔜 Automated rollback capabilities
- 🔜 Real-time sync mode for gradual migration

---

## Version History

- **v2.1.0** (2025-11-08) - Initial public release
- **v2.0.x** - Internal development releases
- **v1.x.x** - Prototype and proof-of-concept

---

## Upgrade Guide

### Migrating from v2.0.x

**Breaking Change**: v2.1.0 introduces self-contained folder structures.

**Old Structure** (v2.0.x):
```
migrations/
├── project1/
│   └── repository/
├── project2/
│   └── repository/
```

**New Structure** (v2.1.0):
```
migrations/
└── MyAzureDevOpsProject/
    ├── project1/
    │   └── repository/
    ├── project2/
    │   └── repository/
```

**Migration Path**:
1. Projects prepared with v2.0.x can still be executed
2. Re-prepare projects for v2.1.0 structure benefits
3. Use `Get-PreparedProjects` to see structure indicator

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

---

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/magedfarag/Gitlab2DevOps/issues)
- **License**: [MIT License](LICENSE)

---

<div align="center">

**Made with ❤️ for DevOps teams migrating to Azure DevOps**

</div>
