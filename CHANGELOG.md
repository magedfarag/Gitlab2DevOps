# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2024-XX-XX

### 🎉 Major Release - Enterprise Security & Open Source

This release represents a complete security hardening and open source preparation of the migration tool.

### Added
- **Pre-Migration Validation**: Mandatory `New-MigrationPreReport` function that validates all prerequisites before migration
- **Credential Management**: Environment variable support for all sensitive configuration
- **Credential Cleanup**: `Clear-GitCredentials` function removes PATs from `.git/config` after operations
- **Configurable API Version**: Support for Azure DevOps API versions 6.0, 7.0, and 7.1 via `-AdoApiVersion` parameter
- **SSL Certificate Handling**: `-SkipCertificateCheck` parameter for on-premises environments with private CAs
- **Enhanced Error Handling**: Comprehensive REST API status code logging for all operations
- **Defensive ACL Checks**: `Ensure-RepoDeny` now reads existing ACLs before applying changes
- **Graph Membership Handling**: Explicit 409 conflict handling in `Ensure-Membership` function
- **Strict Mode**: PowerShell strict mode enabled for improved error detection
- **Bulk Migration**: Configuration file support with `bulk-migration-config.template.json`
- **Comprehensive Documentation**: 
  - Enhanced README with security features section
  - CONTRIBUTING.md with development guidelines
  - LICENSE (MIT)
  - CHANGELOG.md
  - Code of conduct guidelines

### Changed
- **Breaking**: All hardcoded credentials removed - must use environment variables or parameters
- **Breaking**: Pre-flight validation now blocks migration instead of showing warnings
- **Breaking**: Script exits immediately if required credentials are missing
- REST API query strings corrected: `?` instead of `$` in URL construction
- Default Azure DevOps/GitLab URLs changed to `example.com` placeholders
- All organization-specific references removed (ministry, mod.gov.sa)
- Enhanced `Invoke-AdoRest` with try-catch and status code logging
- Improved `Invoke-GitLab` with SSL certificate handling

### Fixed
- Query string parameter separator in REST API calls
- Graph API membership errors causing migration failures
- Missing validation before repository ACL writes
- Git credentials persisting in repository config after migration
- Silent failures in REST API calls without proper logging

### Security
- ✅ Zero hardcoded credentials
- ✅ Automatic credential cleanup after operations
- ✅ Fail-fast validation before any changes
- ✅ Comprehensive audit logging
- ✅ Defensive permission checks
- ✅ Strict mode error detection
- ✅ Configurable certificate validation

## [1.0.0] - Initial Release

### Added
- Basic single-project migration from GitLab to Azure DevOps
- Interactive console menu for migration operations
- Repository cloning and pushing functionality
- Basic RBAC group creation (Dev, QA, BA, Release Approvers, Pipeline Maintainers)
- Branch policy configuration (required reviewers, work item linking)
- Work item template setup (User Story, Bug)
- Project wiki creation
- Git LFS detection and support
- Basic bulk migration workflow
- JSON-based migration reports

### Features
- Three-step migration process (prepare → create → migrate)
- Support for multiple Git refs (branches, tags)
- Build validation policy integration
- SonarQube status check support
- Customizable security group permissions

---

## Version History Summary

- **v2.0.0**: Enterprise security hardening, open source preparation, comprehensive documentation
- **v1.0.0**: Initial working migration tool with basic features

## Migration Guide

### Upgrading from v1.x to v2.0

**Required Changes:**

1. **Remove hardcoded credentials** from any scripts or documentation:
   ```powershell
   # Old (v1.x) - DON'T USE
   .\devops.ps1 -AdoPat "hardcoded-token" -GitLabToken "hardcoded-token"
   
   # New (v2.0) - Use environment variables
   $env:ADO_PAT = "your-token"
   $env:GITLAB_PAT = "your-token"
   .\devops.ps1
   ```

2. **Update URL parameters** if using hardcoded defaults:
   ```powershell
   # Set your actual URLs
   $env:ADO_COLLECTION_URL = "https://your-devops-server.com/DefaultCollection"
   $env:GITLAB_BASE_URL = "https://your-gitlab-server.com"
   ```

3. **Expect blocking validation**: Pre-flight reports now stop execution if issues found (instead of warnings)

**New Features to Adopt:**

- Use `-AdoApiVersion` if running older Azure DevOps Server (6.0 or 7.0)
- Use `-SkipCertificateCheck` if in on-premises environment with private CA
- Use `bulk-migration-config.json` for simpler bulk migrations
- Review comprehensive logs with REST API status codes for troubleshooting

**No Breaking Changes:**
- All existing command-line parameters still supported
- Migration workflow remains the same (preflight → migrate)
- JSON report formats unchanged
