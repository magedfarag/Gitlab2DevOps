# Changelog

All notable changes to the GitLab to Azure DevOps Migration Tool will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2025-11-08

### 🎉 Initial Public Release

The first production-ready release of Gitlab2DevOps, an enterprise-grade migration toolkit for seamless GitLab to Azure DevOps transitions.

### ✨ Features

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

- **12 Core Modules**: Modular architecture with clear separation of concerns
- **7 Sub-Modules**: Focused Azure DevOps adapters
- **43 Wiki Templates**: ~18,000 lines of production-ready documentation
- **100% Test Coverage**: 29/29 tests passing
- **PowerShell Best Practices**: Approved verbs, strict mode, proper error handling

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
