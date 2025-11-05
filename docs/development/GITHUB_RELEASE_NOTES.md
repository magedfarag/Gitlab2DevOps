# GitLab to Azure DevOps Migration Tool v2.0.0

## 🎯 What's New

### Sync Mode Capability
- **Re-run migrations** to keep Azure DevOps repositories up to date with GitLab
- **Migration history tracking** with comprehensive audit trails
- **Safe repository updates** with existing content preservation
- **Bulk sync operations** for enterprise-scale repository management

### Enterprise Reliability
- **SSL/TLS resilience** with automatic curl fallback for certificate issues
- **Dynamic process template resolution** supporting all Azure DevOps templates
- **Enhanced error handling** with color-coded output and actionable messages
- **Comprehensive logging** with HTTP request/response tracking

### Developer Experience
- **83-test suite** with 100% pass rate ensuring reliability
- **CLI automation mode** for CI/CD pipeline integration
- **Interactive menu mode** for guided operations
- **Comprehensive documentation** with quick start guides

## 🔧 Technical Improvements

### Architecture Enhancements
- Modular PowerShell design with strict separation of concerns
- REST API foundation with intelligent fallback mechanisms
- Idempotent operations safe for repeated execution
- Enterprise security with credential masking and audit trails

### API Integration
- **GitLab REST API v4** integration with comprehensive error handling
- **Azure DevOps REST API v7.1** with on-premise server compatibility
- **Automatic retry logic** for transient network failures
- **Rate limiting awareness** with exponential backoff

### Migration Features
- **Full Git history preservation** including branches, tags, and commits
- **LFS support** for large file repositories
- **Branch policy configuration** with intelligent defaults
- **Work item template creation** based on process template selection

## 🛠️ What's Included

### Core Scripts
- `Gitlab2DevOps.ps1` - Main entry point with CLI and interactive modes
- `setup-env.template.ps1` - Environment configuration template
- `verify-publication-ready.ps1` - Pre-publication validation script

### PowerShell Modules
- `Core.Rest.psm1` - REST API foundation with SSL handling
- `GitLab.psm1` - GitLab API integration and data access
- `AzureDevOps.psm1` - Azure DevOps API integration and configuration
- `Migration.psm1` - Migration orchestration and workflow management
- `Logging.psm1` - Structured logging and audit trail generation

### Documentation
- Complete setup and usage guides
- Sync mode operational documentation
- CLI automation examples and best practices
- Architecture overview and contribution guidelines

### Configuration Templates
- Bulk migration configuration with JSON schema validation
- Environment setup with security best practices
- GitHub templates for issues and pull requests

## 🚀 Getting Started

### Quick Setup
```powershell
# 1. Clone the repository
git clone https://github.com/your-org/gitlab2devops.git
cd gitlab2devops

# 2. Configure environment
cp setup-env.template.ps1 setup-env.ps1
# Edit setup-env.ps1 with your tokens

# 3. Run first migration
.\Gitlab2DevOps.ps1
```

### Sync Mode Usage
```powershell
# Update existing repository
.\Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Project" -AllowSync

# Bulk sync multiple repositories
.\Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "repos.json" -AllowSync
```

## 📋 Requirements

### System Requirements
- **PowerShell 5.1+** (Windows PowerShell or PowerShell Core)
- **Git 2.0+** for repository operations
- **Network access** to both GitLab and Azure DevOps servers

### Credentials Required
- **GitLab Personal Access Token** with `read_repository` scope
- **Azure DevOps Personal Access Token** with project and repository permissions

### Supported Platforms
- **Azure DevOps Server** (on-premise) - Primary target
- **Azure DevOps Services** (cloud) - Secondary support
- **GitLab Community/Enterprise** editions

## 🔒 Security Features

### Credential Protection
- Environment variable configuration prevents credential leakage
- Automatic token masking in logs and console output
- Secure credential cleanup after git operations
- No hardcoded secrets or default credentials

### Enterprise Compliance
- Complete audit trails with timestamped operation logs
- Migration history preservation for compliance reporting
- Safe defaults requiring explicit confirmation for destructive operations
- SSL certificate validation bypass for controlled enterprise environments

## 📚 Documentation

### User Guides
- [README.md](README.md) - Complete setup and usage documentation
- [SYNC_MODE_GUIDE.md](SYNC_MODE_GUIDE.md) - Sync mode operational guide
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Common operations quick reference
- [BULK_MIGRATION_CONFIG.md](BULK_MIGRATION_CONFIG.md) - Bulk migration configuration

### Developer Resources
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines and development setup
- [CHANGELOG.md](CHANGELOG.md) - Version history and migration guides
- [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Architecture and technical overview
- [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) - Development progress and roadmap

### Examples and Templates
- [examples/cli-usage.ps1](examples/cli-usage.ps1) - CLI automation examples
- [examples/advanced-features.md](examples/advanced-features.md) - Advanced usage scenarios
- Configuration templates for common deployment patterns

## 🐛 Bug Fixes

### Critical Fixes
- **Process template GUID resolution** now works correctly on on-premise Azure DevOps Server
- **Work item type detection** handles all standard process templates
- **SSL certificate handling** provides reliable fallback for enterprise environments
- **404 error handling** properly distinguishes expected vs. unexpected errors

### Reliability Improvements
- Enhanced connection retry logic for unstable network environments
- Improved error messages with actionable troubleshooting guidance
- Better handling of concurrent operations and resource conflicts
- Robust cleanup of temporary files and git credentials

## ⚠️ Breaking Changes

### Configuration Changes
- Environment variable configuration now recommended over CLI parameters
- Migration workspace structure updated for better organization
- Some CLI parameter names standardized for consistency

### System Requirements
- PowerShell 5.1+ now required (upgraded from 4.0)
- Git 2.0+ required for enhanced repository operations
- Azure DevOps REST API v7.1 required for full feature compatibility

### Migration Guide
Existing users should review [CHANGELOG.md](CHANGELOG.md) for detailed upgrade instructions and compatibility notes.

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Setting up the development environment
- Running the test suite
- Submitting bug reports and feature requests
- Code style and documentation standards

## 📞 Support

- **Issues**: Report bugs via GitHub Issues with provided templates
- **Discussions**: Feature requests and general questions via GitHub Discussions
- **Documentation**: Comprehensive guides available in the repository
- **Examples**: Real-world usage examples in the `examples/` directory

## 🙏 Acknowledgments

Special thanks to the DevOps community for feedback, testing, and contributions that made this release possible.

---

**Full Changelog**: [v1.0.0...v2.0.0](https://github.com/your-org/gitlab2devops/compare/v1.0.0...v2.0.0)