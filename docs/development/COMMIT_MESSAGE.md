GitLab to Azure DevOps Migration Tool v2.0.0

This release introduces comprehensive sync mode capabilities, enhanced error handling, and enterprise-grade reliability improvements.

🚀 Major Features:
- Sync Mode: Re-run migrations to update existing Azure DevOps repositories
- Dynamic Process Template Resolution: Supports all Azure DevOps templates (Agile/Scrum/CMMI/Basic)
- SSL/TLS Resilience: Automatic curl fallback for certificate issues
- HTTP Request Logging: Comprehensive API interaction tracking

🔧 Improvements:
- Enhanced error handling with color-coded output
- Idempotent operations for safe re-execution
- Migration history tracking and audit trails
- Comprehensive test suite (83 tests, 100% pass rate)
- Enterprise security with credential masking

🐛 Bug Fixes:
- Process template GUID mismatch on on-premise servers
- Work item type detection failures
- 404 error display improvements for expected scenarios
- Connection retry logic for unreliable network environments

📚 Documentation:
- Complete sync mode guide with examples
- CLI usage documentation and automation examples
- Architecture documentation and contribution guidelines
- Quick reference guide for common operations

⚠️ Breaking Changes:
- Requires PowerShell 5.1+ (Windows PowerShell or PowerShell Core)
- Environment variable configuration recommended over CLI parameters
- Migration workspace structure changes for better organization

🔗 Migration Guide:
Existing users should review CHANGELOG.md for detailed migration instructions.

For complete usage information, see README.md and SYNC_MODE_GUIDE.md.