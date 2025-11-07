# Release Notes - Gitlab2DevOps v2.1.0

**Release Date**: November 7, 2025  
**Release Type**: Major Feature Release with Breaking Changes

---

## 🎉 Overview

Version 2.1.0 represents a significant milestone in the evolution of Gitlab2DevOps, focusing on **self-contained migration structures**, **modular architecture**, and **production-ready documentation templates**. This release introduces breaking changes to improve portability, maintainability, and user experience.

### Key Highlights

- 👥 **NEW**: User Identity Migration - Export GitLab users/groups, import to Azure DevOps Server
- ⚠️ **Breaking Change**: Self-contained folder structures for all migrations
- 📦 **Module Restructuring**: 51.6% size reduction (10,763 → 5,174 lines)
- 📚 **43 Wiki Templates**: ~18,000 lines of production-ready documentation
- 🎯 **4 Team Initialization Packs**: Business, Dev, Security, Management
- 🔧 **Enhanced Automation**: Improved CLI workflows and error handling
- 📊 **Better Observability**: Structure indicators, auto-detection, migration guidance

---

## ⚠️ BREAKING CHANGES

### Self-Contained Folder Structures

**What Changed**: Both single and bulk migrations now use hierarchical, self-contained folder structures.

#### Before (v2.0.x - Flat Structure)
```
migrations/
├── my-project/               # Single project (flat)
│   ├── reports/
│   ├── logs/
│   └── repository/
└── bulk-prep-ProjectName/    # Bulk preparation (flat with prefix)
    ├── bulk-migration-template.json
    └── project1/
        └── repository/
```

#### After (v2.1.0 - Self-Contained Structure)
```
migrations/
├── MyDevOpsProject/          # Azure DevOps project (parent)
│   ├── migration-config.json
│   ├── reports/              # Project-level reports
│   ├── logs/                 # Project-level logs
│   └── my-gitlab-project/    # GitLab project (child)
│       ├── reports/          # GitLab-specific reports
│       └── repository/
└── ConsolidatedProject/      # Bulk migration (self-contained)
    ├── bulk-migration-config.json
    ├── reports/
    ├── logs/
    ├── project1/             # GitLab project 1
    │   ├── reports/
    │   └── repository/
    └── project2/             # GitLab project 2
        ├── reports/
        └── repository/
```

### Migration Path

1. **New Migrations (v2.1.0+)**: Automatically use self-contained structures
2. **Existing Migrations (v2.0.x)**: Displayed with `[legacy]` indicator in Option 2 menu
3. **Converting Legacy Projects**: Re-prepare using Option 1 to convert to v2.1.0 structure

**Benefits of New Structure**:
- ✅ Clear 1:1 relationship between Azure DevOps and GitLab projects
- ✅ Self-contained: Archive/move entire project by moving one folder
- ✅ Consistent structure for single and bulk migrations
- ✅ Support for multiple GitLab projects per Azure DevOps project

---

## 🚀 What's New

### 1. User Identity Migration ⭐ **NEW FEATURE**

Complete GitLab-to-Azure DevOps identity workflow for on-premise Azure DevOps Server:

**Export User Information** (Menu Option 5):
- Export GitLab users, groups, and memberships to JSON files
- Three export profiles: Minimal (users/groups), Standard (+projects), Complete (+memberships)
- Offline operation (no Azure DevOps connection required)
- Creates timestamped export directories with structured JSON files
- Integrates with existing `examples/export-gitlab-identity.ps1`

**Import User Information** (Menu Option 6):
- Import exported JSON data into Azure DevOps Server
- Two modes: Dry Run (preview) and Execute (actual import)
- File validation with clear error messages
- User resolution (requires Active Directory integration)
- Integrates with existing `Import-GitLabIdentityToAdo.ps1`

**Menu Integration**:
- Updated interactive menu from 5 to 7 options
- Robust path resolution from module location to project root
- Exit option moved to Option 7

**Documentation**: Comprehensive guide in `docs/USER_EXPORT_IMPORT.md`

### 2. Self-Contained Migration Structures

**New Configuration Files**:
- `migration-config.json` (single projects) - Stores project metadata
- `bulk-migration-config.json` (bulk migrations) - Renamed from `bulk-migration-template.json`

**New Functions**:
- `Get-BulkProjectPaths()` - Path management for bulk migrations
- `Get-ProjectPaths()` - Dual parameter sets (New vs Legacy)

**Auto-Detection**:
- Menus automatically detect v2.1.0 vs legacy structures
- Structure indicators: `[v2.1.0]` (green) vs `[legacy]` (yellow)
- Helpful migration guidance displayed when legacy structures detected

### 2. Module Restructuring (51.6% Reduction)

**Before**: Monolithic `AzureDevOps.psm1` (10,763 lines)

**After**: 7 Focused Sub-Modules (5,174 lines total)
- `Core.psm1` (256 lines) - REST foundation, error handling, retries
- `Security.psm1` (84 lines) - Token masking, credential cleanup
- `Projects.psm1` (415 lines) - Project creation, areas, iterations
- `Repositories.psm1` (905 lines) - Repository management, branch policies
- `Wikis.psm1` (318 lines) - Wiki page creation and management
- `WorkItems.psm1` (1,507 lines) - Work items, queries, templates
- `Dashboards.psm1` (676 lines) - Dashboard creation for all teams

**Benefits**:
- 🎯 Clear separation of concerns
- 📝 Easier to navigate and maintain
- 🧪 Improved testability
- 🔄 Faster development cycles

### 3. 43 Production-Ready Wiki Templates (~18,000 lines)

Extracted to external markdown files for easy customization:

**Business Wiki** (10 templates):
- Welcome, Decision Log, Risks & Issues, Glossary
- Ways of Working, KPIs & Success Metrics, Training Quick Start
- Communication Templates, Cutover Timeline, Post-Cutover Summary

**Dev Wiki** (7 templates):
- ADR Template, Dev Setup Guide, API Documentation
- Git Workflow, Code Review Checklist, Troubleshooting, Dependencies

**Security Wiki** (7 templates):
- Security Policies, Threat Modeling, Security Testing
- Incident Response, Compliance Checklist, Secret Management, Security Champions

**Management Wiki** (8 templates):
- Program Overview, Sprint Planning, Capacity Planning, Roadmap
- RAID Log, Stakeholder Communications, Retrospectives, Metrics Dashboard

**Best Practices Wiki** (6 templates):
- Code Standards, Performance Optimization, Error Handling
- Logging Standards, Testing Strategies, Documentation Guidelines

**QA Guidelines Wiki** (5 templates):
- QA Overview, Test Strategy, Test Data Management
- Automation Framework, Bug Lifecycle

### 4. Team Initialization Packs

Four specialized provisioning modes for existing Azure DevOps projects:

**BusinessInit**:
- 10 wiki pages (governance, reporting, communication)
- 8 shared queries (sprint commitment, unestimated stories, epics)
- Business dashboard with key metrics
- 3 short iterations (2 weeks each)

**DevInit**:
- 7 wiki pages (technical documentation, workflows)
- Dev dashboard (PR metrics, code quality, test results)
- 5 dev-focused queries (PR reviews, technical debt)
- Enhanced repository files (.gitignore, .editorconfig, CONTRIBUTING.md, CODEOWNERS)

**SecurityInit**:
- 7 wiki pages (security policies, threat modeling, compliance)
- Security queries (vulnerabilities, security incidents)
- Security dashboard
- Incident response templates

**ManagementInit**:
- 8 wiki pages (program overview, planning, stakeholder communications)
- 6 program management queries (roadmap, capacity, RAID)
- Executive dashboard
- Sprint and release planning templates

---

## 🔧 Improvements

### Interactive Menu Enhancements

**Option 2 (Initialize)**:
- Now displays structure type (`[v2.1.0]` or `[legacy]`)
- Shows helpful migration guidance for legacy projects
- Improved project selection workflow

**Option 1 (Prepare)**:
- Prompts for both Azure DevOps and GitLab project names
- Creates `migration-config.json` automatically
- Better error handling and validation

**Option 3 (Migrate)**:
- Auto-detects v2.1.0 vs legacy structure
- Improved progress indicators
- Enhanced error messages

### CLI Mode Enhancements

**New Modes**:
- `BusinessInit` - Provision business assets
- `DevInit` - Provision development assets
- `SecurityInit` - Provision security assets
- `ManagementInit` - Provision management assets

**Improved Error Handling**:
- Clearer error messages with actionable guidance
- Better SSL/TLS error handling with curl fallback
- Enhanced retry logic for network issues

### Documentation Updates

**Updated Files**:
- `README.md` - New folder structure examples, breaking change notice
- `CHANGELOG.md` - Comprehensive v2.1.0 release notes
- `docs/cli-usage.md` - Updated output paths for all modes
- `.github/copilot-instructions.md` - Implementation guidelines for v2.1.0

**New Documentation**:
- `docs/RELEASE_NOTES_v2.1.0.md` (this file)
- Updated folder structure diagrams
- Migration path from v2.0.x

---

## 🐛 Bug Fixes

- Fixed version numbers in all 15 modules (now 2.1.0)
- Corrected artifact paths in CI/CD examples
- Improved PowerShell 5.1 compatibility
- Enhanced error handling for empty repositories

---

## 📊 Statistics

- **Lines of Code**: ~25,000 lines across all modules
- **Wiki Templates**: 43 files (~18,000 lines)
- **Modules**: 15 modules (7 sub-modules + 8 core)
- **Functions**: 50+ exported functions
- **Tests**: 83 tests (60 passing, 7 pre-existing failures)
- **Documentation**: 20+ markdown files
- **Module Reduction**: 51.6% (10,763 → 5,174 lines in AzureDevOps.psm1)

---

## 🚀 Upgrade Guide

### For New Users

No action required - v2.1.0 is the recommended version.

### For Existing Users (v2.0.x)

#### Option 1: Continue with Legacy Structure
- Existing migrations will continue to work
- Display shows `[legacy]` indicator
- No immediate action required

#### Option 2: Migrate to v2.1.0 Structure (Recommended)
1. **Re-prepare projects**:
   ```powershell
   # Run Option 1 (Prepare) for each project
   # Provide both Azure DevOps and GitLab project names when prompted
   ```

2. **Verify structure**:
   ```powershell
   # Run Option 2 (Show Prepared Projects)
   # Look for [v2.1.0] indicator (green)
   ```

3. **Complete migration**:
   ```powershell
   # Run Option 3 (Migrate) as usual
   # System auto-detects v2.1.0 structure
   ```

4. **Clean up legacy projects** (optional):
   ```powershell
   # Archive or delete old flat structure folders
   ```

---

## 🔮 Future Roadmap

### Planned for v2.2.0
- Test failure fixes (team initialization exports)
- Enhanced idempotency for all operations
- Performance optimizations
- Additional wiki templates

### Under Consideration
- Wiki content migration (currently not supported)
- Work item migration (complex data model mapping)
- Advanced branching strategies
- Multi-repository consolidation

---

## 🙏 Acknowledgments

Thank you to all contributors, testers, and early adopters who helped shape v2.1.0!

**Special Thanks**:
- Community feedback on folder structure improvements
- Testing team for extensive validation
- Documentation reviewers for clarity improvements

---

## 📝 Resources

- **GitHub Repository**: https://github.com/YOUR_ORG/Gitlab2DevOps
- **Documentation**: [docs/README.md](README.md)
- **Quick Start Guide**: [docs/quickstart.md](quickstart.md)
- **CLI Usage Guide**: [docs/cli-usage.md](cli-usage.md)
- **Changelog**: [CHANGELOG.md](../CHANGELOG.md)

---

## 📧 Support

**Issues & Bug Reports**: GitHub Issues  
**Questions**: GitHub Discussions  
**Documentation**: [docs/](./docs/)

---

**Released by**: Migration Team  
**License**: MIT  
**Version**: 2.1.0
