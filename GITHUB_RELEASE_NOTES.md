# Release Notes for v2.0.0

## 🎉 Version 2.0.0 - Enterprise Security & Sync Mode

**Release Date**: November 4, 2025

This major release introduces enterprise-grade security enhancements and a powerful sync mode capability for keeping Azure DevOps repositories synchronized with GitLab sources.

---

## 🚀 What's New

### Sync Mode for Re-running Migrations

The most significant addition in v2.0.0 is the ability to **re-run migrations** to sync Azure DevOps repositories with updated GitLab sources.

#### Key Features:
- **`-AllowSync` Parameter**: Enable sync mode for single or bulk migrations
- **Migration History Tracking**: Complete audit trail of all syncs with timestamps
- **Non-Destructive Updates**: Preserves Azure DevOps configurations while updating content
- **Interactive Prompts**: Simple Y/N prompts in menu mode

#### What Gets Preserved:
✅ Repository settings and permissions  
✅ Branch policies and security groups  
✅ Work item templates  
✅ Project wiki  
✅ All migration configuration files  

#### What Gets Updated:
🔄 Repository content (commits, branches, tags)  
🔄 Git references to match GitLab  
🔄 Migration summary with history  

#### Usage:
```powershell
# Single project sync
.\Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Project" -AllowSync

# Bulk sync
.\Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "config.json" -AllowSync

# Interactive mode with prompts
.\Gitlab2DevOps.ps1
```

📖 **Full Documentation**: See [SYNC_MODE_GUIDE.md](SYNC_MODE_GUIDE.md)

---

## 🔒 Security Enhancements

### 1. Zero Hardcoded Credentials
- All credentials now use environment variables
- Automatic credential cleanup after operations
- Fail-fast validation before any changes

### 2. Pre-Migration Validation
- Mandatory `New-MigrationPreReport` validates prerequisites
- Blocking issues prevent migration from starting
- Comprehensive preflight reports (JSON format)

### 3. Configurable API Version
- Support for Azure DevOps API versions: 6.0, 7.0, 7.1
- Use `-AdoApiVersion` parameter for compatibility
- Default: 7.1 (latest)

### 4. SSL Certificate Handling
- `-SkipCertificateCheck` for on-premises environments
- Support for private CA certificates
- Secure by default

### 5. Enhanced Error Handling
- Comprehensive REST API status code logging
- Defensive ACL checks before writing
- Explicit 409 conflict handling in Graph API
- PowerShell strict mode enabled

### 6. Credential Cleanup
- `Clear-GitCredentials` removes PATs from `.git/config`
- No credential persistence after operations
- Secure credential lifecycle management

---

## 📦 Bulk Migration Improvements

### Enhanced Configuration Format

**New Structure:**
```json
{
  "targetAdoProject": "ConsolidatedProject",
  "migrations": [
    {
      "gitlabProject": "org/repo1",
      "adoRepository": "Repo1",
      "preparation_status": "SUCCESS"
    },
    {
      "gitlabProject": "org/repo2",
      "adoRepository": "Repo2",
      "preparation_status": "SUCCESS"
    }
  ]
}
```

**Key Changes:**
- Added `targetAdoProject` at root level for clarity
- Renamed `adoProject` to `adoRepository` (more accurate)
- Added `preparation_status` field (SUCCESS/FAILED/PENDING)
- Backward compatible with old format

📖 **Configuration Guide**: See [BULK_MIGRATION_CONFIG.md](BULK_MIGRATION_CONFIG.md)

---

## 📚 Documentation

### New Documentation Files:
- **SYNC_MODE_GUIDE.md** - Complete sync mode documentation (364 lines)
- **SYNC_IMPLEMENTATION_SUMMARY.md** - Technical implementation details
- **BULK_MIGRATION_CONFIG.md** - Bulk configuration format guide
- **COMMIT_MESSAGE.md** - Git commit guidance
- **GITHUB_RELEASE_NOTES.md** - This file

### Updated Documentation:
- **README.md** - Added sync mode section, updated features list
- **QUICK_REFERENCE.md** - Added sync command examples
- **CHANGELOG.md** - Complete v2.0.0 changelog
- **CONTRIBUTING.md** - Development guidelines
- **PROJECT_SUMMARY.md** - Architecture overview

---

## 🛠️ Breaking Changes

**None!** This release is fully backward compatible.

- Scripts without `-AllowSync` work exactly as before
- Old bulk config format still supported
- Existing workflows unchanged
- New features are opt-in only

---

## 🐛 Bug Fixes

### Fixed Issues:
1. **Query String Parameters**: Corrected `$` to `?` in REST API URL construction
2. **Graph API Membership**: Explicit handling of 409 conflicts preventing silent failures
3. **ACL Validation**: Added defensive checks before writing repository ACLs
4. **Credential Persistence**: Git credentials now properly cleaned up after operations
5. **Silent API Failures**: Enhanced error logging for all REST API calls

---

## 📊 Migration History Tracking

Each sync operation is now tracked in JSON format:

```json
{
  "migration_type": "SYNC",
  "migration_count": 3,
  "last_sync": "2024-11-04T14:30:00",
  "previous_migrations": [
    {
      "migration_start": "2024-10-01T10:00:00",
      "migration_end": "2024-10-01T10:15:00",
      "status": "SUCCESS",
      "type": "INITIAL"
    },
    {
      "migration_start": "2024-10-15T11:30:00",
      "migration_end": "2024-10-15T11:42:00",
      "status": "SUCCESS",
      "type": "SYNC"
    },
    {
      "migration_start": "2024-11-04T14:28:00",
      "migration_end": "2024-11-04T14:30:00",
      "status": "SUCCESS",
      "type": "SYNC"
    }
  ]
}
```

---

## 🎯 Use Cases Enabled

### 1. Daily Automated Syncs
Keep Azure DevOps repositories automatically updated with GitLab changes:
```powershell
# Windows scheduled task
.\Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "production.json" -AllowSync
```

### 2. Gradual Migration Strategy
Maintain GitLab as source of truth during transition:
- Initial migration creates Azure DevOps repos
- Regular syncs keep them current
- Teams continue working in GitLab
- Zero disruption during migration period

### 3. Disaster Recovery
Maintain current backups in Azure DevOps:
- Periodic syncs ensure backups are up-to-date
- Test recovery procedures without risk
- Quick restoration from Azure DevOps if needed

### 4. Multi-Platform Development
Work in both platforms simultaneously:
- Develop in GitLab (source of truth)
- Mirror in Azure DevOps for CI/CD
- Sync on demand or on schedule

---

## 📈 Statistics

### Code Changes:
- **Gitlab2DevOps.ps1**: ~150 lines modified/added (5 functions enhanced)
- **Documentation**: ~471 new lines across 4 files
- **Total Impact**: ~621 lines of production-ready code and documentation

### Functions Enhanced:
1. `Ensure-Repo` - Added `-AllowExisting` parameter
2. `New-MigrationPreReport` - Added sync validation logic
3. `Migrate-One` - Added history tracking
4. `Bulk-Migrate-FromConfig` - Added sync support
5. `Bulk-Migrate` - Added sync support

### Interactive Menu Updates:
- Option 3: Single migration with sync prompt
- Option 6: Bulk migration with sync prompt

---

## 🔧 Technical Details

### Migration History Schema:
- `migration_type`: "INITIAL" or "SYNC"
- `migration_count`: Total number of migrations performed
- `last_sync`: ISO 8601 timestamp of most recent sync
- `previous_migrations`: Array of all historical migrations

### Validation Flow:
```
User Request → Validation → Repo Check → Sync Decision → Execute → Track History
```

### Safety Features:
- ✅ Explicit user consent required
- ✅ Confirmation prompts in interactive mode
- ✅ Complete operation logging
- ✅ Rollback information preserved
- ✅ Non-destructive by design

---

## 🚦 Upgrade Instructions

### From v1.x to v2.0.0:

**No action required!** v2.0.0 is fully backward compatible.

**Optional**: To use new sync features:
1. Update your environment with `.\setup-env.ps1`
2. Review [SYNC_MODE_GUIDE.md](SYNC_MODE_GUIDE.md)
3. Try sync mode: `.\Gitlab2DevOps.ps1 -Mode migrate ... -AllowSync`

**Recommended**: Update bulk configs to new format:
```json
{
  "targetAdoProject": "YourProject",  // New field
  "migrations": [
    {
      "gitlabProject": "org/repo",
      "adoRepository": "Repo",          // Renamed from adoProject
      "preparation_status": "SUCCESS"   // New field
    }
  ]
}
```

---

## 📝 Changelog Summary

### Added ✨
- Sync mode with `-AllowSync` parameter
- Migration history tracking
- `SYNC_MODE_GUIDE.md` documentation
- `preparation_status` field in bulk configs
- `targetAdoProject` field in bulk configs
- Interactive sync prompts
- Environment variable credential support
- Pre-migration validation
- Configurable API versions
- SSL certificate handling
- Comprehensive error logging

### Changed 🔄
- Bulk config format (backward compatible)
- `adoProject` → `adoRepository` in configs
- Default credentials now use environment variables
- Validation now blocks instead of warns

### Fixed 🐛
- Query string separators in REST APIs
- Graph API 409 conflict handling
- ACL validation before writes
- Credential cleanup after operations
- Silent REST API failures

### Security 🔒
- Zero hardcoded credentials
- Automatic credential cleanup
- Fail-fast validation
- Defensive permission checks
- PowerShell strict mode

---

## 🙏 Acknowledgments

This release was made possible by:
- Enterprise security requirements and best practices
- Community feedback on bulk migration workflows
- Production use cases requiring sync capabilities
- Microsoft and GitLab API documentation
- Open source community standards

---

## 📞 Support & Resources

### Documentation:
- **Quick Start**: [README.md](README.md)
- **Sync Mode**: [SYNC_MODE_GUIDE.md](SYNC_MODE_GUIDE.md)
- **Quick Reference**: [QUICK_REFERENCE.md](QUICK_REFERENCE.md)
- **Bulk Config**: [BULK_MIGRATION_CONFIG.md](BULK_MIGRATION_CONFIG.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)

### Getting Help:
- 🐛 **Bug Reports**: Use GitHub Issues with bug report template
- 💡 **Feature Requests**: Use GitHub Issues with feature request template
- ❓ **Questions**: Use GitHub Issues with question template
- 🤝 **Contributions**: See [CONTRIBUTING.md](CONTRIBUTING.md)

### Links:
- **Repository**: https://github.com/magedfarag/Gitlab2DevOps
- **License**: [MIT License](LICENSE)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)

---

## 🎊 What's Next?

Potential future enhancements (not committed):
- API rate limiting and retry logic
- Webhook integration for automatic sync triggers
- Differential sync (only changed refs)
- Multi-threaded bulk operations
- Web UI for migration management
- Sync conflict resolution strategies

**Want to contribute?** Check out [CONTRIBUTING.md](CONTRIBUTING.md)!

---

**Full Changelog**: https://github.com/magedfarag/Gitlab2DevOps/compare/v1.0.0...v2.0.0

**Installation**:
```powershell
git clone https://github.com/magedfarag/Gitlab2DevOps.git
cd Gitlab2DevOps
.\setup-env.ps1  # Configure credentials
.\Gitlab2DevOps.ps1     # Start interactive menu
```

**Happy Migrating! 🚀**
