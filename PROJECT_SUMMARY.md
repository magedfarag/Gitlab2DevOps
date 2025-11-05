# GitLab to Azure DevOps Migration Tool - Project Summary

## 🎯 Project Purpose

This open-source PowerShell tool automates the complete migration of projects from GitLab (self-hosted or GitLab.com) to Azure DevOps Server (on-premises or cloud). It handles everything from initial validation to final repository setup with enterprise security features.

## ✨ Key Highlights

### Enterprise-Grade Features
- ✅ **Pre-Migration Validation**: Blocks execution if prerequisites fail
- ✅ **Zero Credential Exposure**: Environment variable-based configuration
- ✅ **Automatic Credential Cleanup**: Removes PATs from Git config
- ✅ **Comprehensive Audit Trail**: Detailed logging with timestamps
- ✅ **Bulk Migration Support**: Migrate multiple projects efficiently
- ✅ **Configurable API Versions**: Support for Azure DevOps 6.0, 7.0, 7.1

### Security Features
- No hardcoded credentials
- Fail-fast validation
- REST API status code logging
- Defensive ACL checks before writes
- PowerShell strict mode enabled
- SSL certificate handling for on-prem environments

### RBAC & Governance
- Automated security group creation (Dev, QA, BA, Release Approvers, Pipeline Maintainers)
- Branch policies (required reviewers, work item linking, build validation)
- Repository-level permissions
- Work item templates (User Story, Bug)
- Project wiki with conventions

## 📊 Project Statistics

### Codebase
- **Main Script**: `Gitlab2DevOps.ps1` (2200+ lines with modules)
- **Functions**: 15+ core functions
- **Documentation**: 500+ lines (README, CONTRIBUTING, CHANGELOG)
- **Language**: PowerShell 5.1+

### Integrations
- **Azure DevOps REST API**: v6.0, v7.0, v7.1
- **GitLab REST API**: v4
- **Git**: Core functionality + Git LFS support
- **Graph API**: For RBAC management

## 🏗️ Architecture

### Core Components

1. **Validation Engine** (`New-MigrationPreReport`)
   - Pre-flight checks before any changes
   - JSON report generation
   - Blocking issue detection

2. **Migration Orchestrator** (`Migrate-One`, `Bulk-Migrate-FromConfig`)
   - Single and bulk project handling
   - Workspace management
   - Error recovery

3. **Security Manager** (`Ensure-RepoDeny`, `Clear-GitCredentials`)
   - ACL configuration
   - Credential cleanup
   - Group membership management

4. **REST API Layer** (`Invoke-AdoRest`, `Invoke-GitLab`)
   - Unified API calling
   - Status code logging
   - Error handling

### Workflow

```
1. Preflight Validation
   ├── Check GitLab project existence
   ├── Analyze repository size/LFS
   ├── Validate credentials
   └── Generate JSON report

2. Project Setup
   ├── Create Azure DevOps project
   ├── Create security groups
   ├── Configure RBAC
   └── Setup wiki

3. Repository Migration
   ├── Clone from GitLab
   ├── Create Azure DevOps repository
   ├── Push all refs (branches, tags)
   ├── Migrate LFS objects
   ├── Apply branch policies
   ├── Cleanup credentials
   └── Generate migration report
```

## 📁 File Structure

```
Gitlab2DevOps/
├── Gitlab2DevOps.ps1                       # Main migration script
├── README.md                               # Comprehensive documentation
├── CHANGELOG.md                            # Version history
├── CONTRIBUTING.md                         # Contribution guidelines
├── LICENSE                                 # MIT License
├── .gitignore                              # Git ignore rules
├── .gitattributes                          # Line ending configuration
├── bulk-migration-config.template.json     # Bulk migration template
├── setup-env.template.ps1                  # Environment setup script
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── question.md
│   └── PULL_REQUEST_TEMPLATE.md
└── migrations/                             # Generated during use (gitignored)
    └── [project-name]/
        ├── repository/                     # Cloned GitLab repo
        ├── logs/                           # Operation logs
        └── reports/                        # JSON reports
```

## 🚀 Usage Patterns

### Simple Single Project
```powershell
# Load credentials
.\setup-env.ps1

# Validate and migrate
.\Gitlab2DevOps.ps1 -Mode preflight -GitLabProject "org/project" -AdoProject "Project"
.\Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/project" -AdoProject "Project"
```

### Bulk Migration
```powershell
# Create config from template
cp bulk-migration-config.template.json bulk-migration-config.json

# Edit config (set targetAdoProject and list all migrations)
notepad bulk-migration-config.json

# Config format:
# {
#   "targetAdoProject": "ConsolidatedProject",  # Single hosting project
#   "migrations": [
#     {"gitlabProject": "org/repo1", "adoRepository": "Repo1"},
#     {"gitlabProject": "org/repo2", "adoRepository": "Repo2"}
#   ]
# }

# Execute bulk migration
.\Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "bulk-migration-config.json"

# Result: All repos created in ONE Azure DevOps project
```

### Advanced Configuration
```powershell
# On-premises with older API version and custom CA
.\Gitlab2DevOps.ps1 -Mode migrate `
    -GitLabProject "org/project" `
    -AdoProject "Project" `
    -AdoApiVersion "6.0" `
    -SkipCertificateCheck `
    -BuildDefinitionId 42 `
    -SonarStatusContext "sonarqube/status"
```

## 🔒 Security Model

### Credential Management
1. **Input**: Environment variables (recommended) or parameters
2. **Validation**: Script validates at startup, exits if missing
3. **Usage**: In-memory only, never written to files
4. **Cleanup**: Git credentials removed from `.git/config` after push
5. **Logging**: PATs never appear in logs (masked as `***`)

### Pre-Migration Validation
- Prevents migrations that will fail
- Checks GitLab project accessibility
- Validates Azure DevOps permissions
- Confirms repository doesn't exist
- Blocks execution if issues found

### Audit Trail
- All operations logged with timestamps
- REST API status codes recorded
- Group membership changes tracked
- ACL modifications documented
- Migration reports in JSON format

## 🌟 Production Readiness

### What Makes This Production-Ready?

1. **Fail-Fast Design**: Validates before making any changes
2. **Idempotent Operations**: Safe to retry if failures occur
3. **Comprehensive Logging**: Full audit trail for compliance
4. **Error Recovery**: Graceful handling of API failures
5. **Credential Security**: No exposure in logs or Git config
6. **Version Flexibility**: Works with legacy Azure DevOps versions
7. **Certificate Handling**: Supports on-prem with private CAs

### What's NOT Included?

- **Rollback Mechanism**: Once migrated, manual cleanup required
- **Work Item Migration**: Only templates, not historical work items
- **CI/CD Pipeline Migration**: Build definitions must be recreated
- **User Mapping**: Group memberships use default assignments
- **GitLab Issues/MRs**: Not migrated to Azure DevOps work items

## 📈 Future Roadmap

### Community Suggestions Welcome

- Unit test coverage
- CI/CD pipeline with GitHub Actions
- Work item history migration
- GitLab CI/CD → Azure Pipelines conversion
- User mapping configuration
- Rollback/cleanup automation
- Docker containerization
- Progress bars for bulk migrations
- Email notifications on completion
- Dry-run mode for testing

## 🤝 Community Contribution Areas

### Good First Issues
- Add more error message translations
- Improve documentation examples
- Add PowerShell help comments
- Create video tutorials

### Advanced Contributions
- Implement unit tests with Pester
- Add pipeline migration support
- Create work item migration feature
- Build GitHub Actions workflow
- Add progress indicators

### Documentation Contributions
- Translate to other languages
- Create troubleshooting guides
- Write migration best practices
- Document edge cases

## 📜 License & Attribution

**License**: MIT License  
**Copyright**: 2024 GitLab to Azure DevOps Migration Tool Contributors

This project is free to use, modify, and distribute. See [LICENSE](LICENSE) for full details.

## 🙏 Acknowledgments

Built with contributions from the DevOps community. Special thanks to:
- Microsoft for Azure DevOps REST API documentation
- GitLab for comprehensive API documentation
- PowerShell community for best practices
- All contributors and users who provide feedback

---

**Made with ❤️ for the DevOps community**

For questions, issues, or contributions, please visit the GitHub repository.
