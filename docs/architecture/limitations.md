# Limitations and Scope

## What This Tool Does

Gitlab2DevOps is designed for **Git repository migration** with minimal effort:

✅ **Core Functionality**:
- Migrate Git repository with full history (all commits, branches, tags)
- Convert GitLab branch protection → Azure DevOps branch policies
- Configure default branch and basic repository settings
- Preserve commit SHAs, author information, and timestamps
- Batch migrate multiple projects efficiently

✅ **Production Features**:
- Idempotent operations (safe to re-run)
- Caching for performance optimization
- Comprehensive logging and audit trails
- CLI automation support
- Retry logic with exponential backoff

---

## What This Tool Does NOT Do

Understanding these limitations helps set proper expectations.

### 1. Work Item Management

❌ **Does NOT Migrate**:
- GitLab Issues → Azure DevOps Work Items
- Issue comments, attachments, labels
- Milestones, epics, boards
- Issue relationships and dependencies

**Why**: Different data models require complex mapping. Azure DevOps has customizable work item types that don't directly map to GitLab issues.

**Alternative**: Manual recreation or third-party tools like [Opshub](https://www.opshub.com/).

---

### 2. Merge Requests / Pull Requests

❌ **Does NOT Migrate**:
- Merge Requests → Pull Requests
- MR comments, approvals, review history
- Code review discussions
- MR status (open, merged, closed)

**Why**: Pull requests are live objects tied to active branches. Historical MRs lose context after migration.

**Alternative**: 
- Close all open MRs before migration
- Document important MR decisions in commit messages

---

### 3. CI/CD Pipelines

❌ **Does NOT Migrate**:
- `.gitlab-ci.yml` → Azure Pipelines YAML
- Pipeline runs, job history
- Environment variables, secrets
- Deployment history

**Why**: GitLab CI and Azure Pipelines use fundamentally different syntax and features.

**Alternative**: Manually recreate pipelines using Azure Pipelines YAML. Consider this an opportunity to optimize your CI/CD.

---

### 4. Wikis

❌ **Does NOT Migrate**:
- Project wikis
- Wiki page history
- Wiki attachments

**Why**: Wikis are separate Git repositories in both systems but with different structures.

**Future**: Wiki migration is planned for v3.0.

**Alternative**: Export wiki as Markdown and import manually.

---

### 5. Project Settings

❌ **Does NOT Migrate**:
- Project description, avatar
- Member permissions (users, groups)
- Webhooks, integrations
- Protected tags
- Project-level variables

**Why**: Different permission models and settings structures.

**Alternative**: Configure manually in Azure DevOps after migration.

---

### 6. Large File Storage

❌ **Limited Support**:
- Git LFS (Large File Storage)
- GitLab Package Registry
- Container Registry images

**Why**: LFS requires separate authentication and storage configuration.

**Workaround**: Manually configure LFS after migration if needed.

---

### 7. Advanced Branch Policies

❌ **Limited Scope**:
- Only basic branch policies are created (approvers, build validation, comment resolution)
- Does NOT replicate all GitLab protection settings exactly
- No automatic status check migration

**Why**: Azure DevOps branch policies are more configurable than GitLab protections.

**Alternative**: Customize policies after migration in Azure DevOps portal.

---

### 8. Security Features

❌ **Does NOT Migrate**:
- Security scanning results
- Dependency scanning
- License compliance data
- Secret detection alerts

**Why**: Different security tooling and integrations.

**Alternative**: Configure Azure DevOps security tools (Defender for DevOps, etc.).

---

### 9. GitLab-Specific Features

❌ **Does NOT Migrate**:
- GitLab Pages
- GitLab Container Registry
- GitLab Packages
- Feature flags
- Error tracking (Sentry integration)

**Why**: No direct Azure DevOps equivalents.

**Alternative**: Use Azure-equivalent services (Azure Static Web Apps, Azure Container Registry, Azure Artifacts).

---

## What About Incremental/Delta Migrations?

❌ **Not Supported**: This tool does NOT support incremental updates after initial migration.

**Why**: The migration is designed as a one-time cutover, not continuous sync.

**Implication**: After migration:
1. Continue development in Azure DevOps
2. Decommission GitLab repository (archive or delete)
3. Do NOT push changes back to GitLab

---

## Best Practices Given Limitations

### Pre-Migration Checklist

1. **Close Open MRs**: Merge or close all open merge requests
2. **Document Decisions**: Important discussions → commit messages or wiki
3. **Export Issues**: Export issue list for manual recreation if needed
4. **Archive Old Pipelines**: Download pipeline artifacts if required
5. **Notify Team**: Set expectations about what won't migrate

### Post-Migration Tasks

1. **Recreate Pipelines**: Set up Azure Pipelines YAML
2. **Configure Security**: Enable Azure DevOps security scanning
3. **Set Permissions**: Configure users, groups, and branch policies
4. **Test Thoroughly**: Verify all branches and tags migrated correctly
5. **Archive GitLab**: Mark old repository as read-only

---

## When NOT to Use This Tool

Consider alternatives if you need:
- **Full project migration** including issues/MRs → Use commercial tools like [Opshub](https://www.opshub.com/)
- **Continuous sync** between GitLab and Azure DevOps → Use [Azure DevOps Git sync](https://learn.microsoft.com/en-us/azure/devops/repos/git/import-git-repository)
- **GitLab backup** → Use [GitLab backup/restore](https://docs.gitlab.com/ee/administration/backup_restore/)

---

## Scope Summary

| Feature | Supported | Notes |
|---------|-----------|-------|
| Git repository | ✅ Full | All branches, tags, history |
| Branch protection | ✅ Partial | Basic policies only |
| Issues/Work Items | ❌ No | Manual recreation required |
| Merge/Pull Requests | ❌ No | Close before migration |
| CI/CD Pipelines | ❌ No | Recreate in Azure Pipelines |
| Wikis | ❌ No | Planned for v3.0 |
| Users/Permissions | ❌ No | Configure in Azure DevOps |
| Project settings | ❌ No | Manual configuration |
| Git LFS | ⚠️ Limited | Requires manual setup |

---

## Questions?

- **Feature Requests**: [GitHub Issues](https://github.com/magedfarag/Gitlab2DevOps/issues)
- **Clarifications**: See [Troubleshooting](troubleshooting.md)
- **Architecture**: See [Design Decisions](architecture/design-decisions.md)

---

[← Back to Documentation Index](README.md)
