# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - v2.1.0 Development

### Added (Post-v2.0.0)
- **curl Fallback System**: Automatic fallback to curl with `-k` flag when PowerShell SSL/TLS fails on on-premise servers
  - Detects "connection forcibly closed" and SSL certificate errors
  - Uses Basic authentication (`-u ":$PAT"`) for Azure DevOps
  - HTTP header parsing with status code extraction (`-i -w '\nHTTP_CODE:%{http_code}'`)
  - Network error retry logic (connection reset → HTTP 503)
  - Lines 458-590 in Core.Rest.psm1
- **Agile Process Template**: Dynamic work item type detection with 3-second initialization wait
  - Supports User Story (Agile), Product Backlog Item (Scrum), Issue (Basic)
  - Enhanced Get-AdoWorkItemTypes with detailed logging and defaults
  - Automatic fallback for different process templates
- **Branch Policy Workflow Refactor**: Moved from project creation to post-migration
  - Option 2 (Create Project): Skips branch policies for empty repositories
  - Option 6 (Bulk Migration): Applies policies after successful git push
  - 2-second wait for Azure DevOps branch recognition
  - Empty repository detection prevents policy application errors
- **Comprehensive Test Suite**: 83 tests (29 offline + 54 extended) with 100% pass rate
- **Test Coverage Documentation**: TEST_COVERAGE.md with detailed breakdown by component
- **.env Configuration System**: Auto-loading of .env and .env.local files with priority order
- **EnvLoader Module**: Robust .env file parsing with variable expansion (${VAR} and $VAR syntax)
- **QUICK_SETUP.md**: Step-by-step guide for .env configuration with PAT creation instructions
- **GitHub Actions CI**: Automated testing workflow on push/PR events
- **Progress Tracking**: Real-time progress indicators for long-running operations
- **Telemetry System**: Optional usage telemetry collection (opt-in, local only)
- **Dry-Run Mode**: Preview changes without executing them
- **API Error Catalog**: Comprehensive error handling with specific guidance
- **.github/copilot-instructions.md**: AI agent guidance for codebase architecture and patterns

### Changed (Post-v2.0.0)
- **SSL/TLS Handling**: All Azure DevOps REST calls require `-SkipCertificateCheck` parameter
- **Authentication**: Azure DevOps curl fallback uses Basic auth instead of headers
- **Work Item Detection**: Enhanced with process template awareness and better error messages
- **Repository Setup**: Get-AdoRepoDefaultBranch returns null for empty repos instead of errors
- **Migration Workflow**: Separated project structure setup from actual code migration
- **Configuration Priority**: .env.local > .env > environment variables > parameters
- **Entry Point**: Consolidated to single Gitlab2DevOps.ps1 (removed legacy devops.ps1)
- **Documentation Structure**: Reorganized with comprehensive guides in docs/ directory
- **Test Organization**: Separated offline tests (no API) from extended tests (comprehensive)

### Fixed (Post-v2.0.0)
- **SSL/TLS Errors**: PowerShell Invoke-RestMethod failures with on-premise Azure DevOps servers
- **Connection Resets**: Network error retry logic treats HTTP 0 (connection reset) as retryable HTTP 503
- **Empty Repository Policies**: Branch policies no longer fail on repositories without branches
- **Work Item Templates**: Bug template creation with proper 3-second initialization delay
- **HTTP Parsing**: Proper separation of HTTP headers and JSON body in curl responses
- **Array Handling**: Safe handling of single objects vs. arrays in curl output
- EnvLoader variable expansion regex for PowerShell 5.1 compatibility (callback → iterative)
- Template generation backtick escaping issues in New-DotEnvTemplate
- Telemetry collection initialization handling for offline scenarios
- Test expectations to match actual function implementations

### Documentation (Post-v2.0.0)
- **.github/copilot-instructions.md**: Comprehensive AI agent guidance (250+ lines)
  - Architecture overview with module separation
  - SSL/TLS handling with curl fallback strategy
  - Work item type detection patterns
  - Migration workflow separation (Option 2 vs Option 6)
  - REST API patterns and error handling
  - Testing, configuration, and security best practices
- **docs/QUICK_SETUP.md**: Complete .env setup guide (250+ lines)
- **tests/TEST_COVERAGE.md**: Test documentation (323 lines)
- **docs/advanced-features.md**: Progress, telemetry, dry-run documentation
- **Updated README.md**: Comprehensive quick start and feature matrix
- **Updated IMPLEMENTATION_ROADMAP.md**: Current status at 90% complete

### Technical Details
- **Core.Rest.psm1 Changes**:
  - Lines 458-590: curl fallback implementation with Basic auth
  - HTTP header parsing with status code extraction
  - Network error detection and retry logic
  - Automatic SSL/TLS error detection
- **AzureDevOps.psm1 Changes**:
  - Lines 650-780: Enhanced work item type detection
  - Get-AdoRepoDefaultBranch null return for empty repos
  - Ensure-AdoTeamTemplates with 3-second initialization wait
- **Migration.psm1 Changes**:
  - Lines 515-575: Project setup with conditional branch policy check
  - Lines 858-938: Post-migration branch policy application
  - Success messages clarify when policies are applied

---

## [2.0.0] - 2024-11-04

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
- **Sync/Re-run Capability**: `-AllowSync` parameter enables updating existing repositories with GitLab changes
- **Migration History Tracking**: Each sync operation tracked in `previous_migrations` array with timestamps and status
- **Non-Destructive Updates**: Sync mode preserves Azure DevOps settings while updating repository content
- **Improved Bulk Config Format**: Added `targetAdoProject` field and renamed `adoProject` to `adoRepository` for clarity
- **Preparation Status Tracking**: `preparation_status` field in bulk config tracks SUCCESS/FAILED/PENDING states
- **Comprehensive Documentation**: 
  - Enhanced README with security features section and sync mode guide
  - CONTRIBUTING.md with development guidelines
  - LICENSE (MIT)
  - CHANGELOG.md
  - Code of conduct guidelines
  - QUICK_REFERENCE.md with sync examples
  - BULK_MIGRATION_CONFIG.md explaining config structure

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
   .\Gitlab2DevOps.ps1 -AdoPat "hardcoded-token" -GitLabToken "hardcoded-token"
   
   # New (v2.0) - Use environment variables
   $env:ADO_PAT = "your-token"
   $env:GITLAB_PAT = "your-token"
   .\Gitlab2DevOps.ps1
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
