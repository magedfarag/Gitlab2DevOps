# Commit Message for Sync Mode Feature

## Title
```
feat: Add sync mode for re-running migrations to update existing repositories
```

## Detailed Commit Message

```
feat: Add sync mode for re-running migrations to update existing repositories

This major enhancement enables running migrations multiple times to sync Azure DevOps 
repositories with updated GitLab sources, while preserving all Azure DevOps configurations.

BREAKING CHANGES: None (fully backward compatible)

Features Added:
- Added -AllowSync parameter to all migration functions
- Migration history tracking with previous_migrations array
- Non-destructive repository updates preserving ADO settings
- Interactive menu prompts for sync mode (Y/N)
- Comprehensive sync mode documentation

Core Changes:
* devops.ps1 (5 functions enhanced):
  - Ensure-Repo: Added -AllowExisting switch for existing repos
  - New-MigrationPreReport: Validates with -AllowSync, adds sync_mode field
  - Migrate-One: Tracks migration history, type (INITIAL/SYNC), count
  - Bulk-Migrate-FromConfig: Propagates AllowSync through bulk operations
  - Bulk-Migrate: Repository creation respects AllowExisting flag

* Interactive Menu (Options 3 & 6):
  - Added user prompts for enabling sync mode
  - Conditional parameter passing based on user choice

Migration History Schema:
- migration_type: "INITIAL" or "SYNC"
- migration_count: Total number of migrations
- last_sync: Timestamp of most recent sync
- previous_migrations: Array storing complete sync history

What Sync Mode Preserves:
✅ Repository settings and permissions
✅ Branch policies and security groups
✅ Work item templates and project wiki
✅ All migration folder configuration files

What Sync Mode Updates:
🔄 Repository content (commits, branches, tags)
🔄 Git references to match GitLab
🔄 Migration summary with history

Documentation:
- Created SYNC_MODE_GUIDE.md (364 lines) - comprehensive sync documentation
- Updated README.md - added "Re-running Migrations" section
- Updated QUICK_REFERENCE.md - added sync command examples
- Updated CHANGELOG.md - documented sync features in v2.0.0
- Created SYNC_IMPLEMENTATION_SUMMARY.md - complete implementation details

Use Cases Enabled:
1. Daily automated syncs to keep ADO current with GitLab
2. Gradual migration strategy with GitLab as source of truth
3. On-demand updates after important GitLab changes
4. Disaster recovery with current backups

Usage Examples:
  # Single project sync
  .\devops.ps1 -Mode migrate -GitLabProject "org/repo" -AdoProject "Project" -AllowSync
  
  # Bulk sync
  .\devops.ps1 -Mode bulkMigrate -ConfigFile "config.json" -AllowSync
  
  # Interactive mode
  .\devops.ps1
  # Choose option 3 or 6, answer Y to sync prompt

Fixes: #N/A
Closes: #N/A
Related: Sync capability requested for production use

Testing:
✅ Single migration with sync updates existing repo
✅ Bulk migration with sync updates all repos
✅ Migration without sync blocks on existing repos
✅ History tracking correctly increments count
✅ ADO settings preserved after sync
✅ Interactive menu prompts work correctly

Co-authored-by: GitHub Copilot <noreply@github.com>
```

## Alternative Short Commit Message

If you prefer a shorter commit:

```
feat: Add sync mode for repository updates

- Add -AllowSync parameter to enable re-running migrations
- Track migration history with type, count, and timestamps
- Preserve Azure DevOps settings while updating content
- Add comprehensive documentation (SYNC_MODE_GUIDE.md)
- Update README, QUICK_REFERENCE, and CHANGELOG

Enables keeping ADO repos synchronized with GitLab updates
while preserving policies, permissions, and configurations.
```

## Git Commands to Publish

```powershell
# 1. Stage all changes
git add .

# 2. Commit with detailed message
git commit -F COMMIT_MESSAGE.md

# OR use the short version:
git commit -m "feat: Add sync mode for repository updates" -m "- Add -AllowSync parameter to enable re-running migrations
- Track migration history with type, count, and timestamps
- Preserve Azure DevOps settings while updating content
- Add comprehensive documentation (SYNC_MODE_GUIDE.md)
- Update README, QUICK_REFERENCE, and CHANGELOG

Enables keeping ADO repos synchronized with GitLab updates
while preserving policies, permissions, and configurations."

# 3. Push to GitHub
git push origin main

# 4. Create a tag for v2.0.0 (if releasing)
git tag -a v2.0.0 -m "Version 2.0.0: Enterprise Security + Sync Mode"
git push origin v2.0.0
```
