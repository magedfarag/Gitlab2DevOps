# Sync Mode Guide

This guide documents the experimental synchronization mode (AllowSync) for Gitlab2DevOps.

> Status: Experimental. Not recommended for production migrations.

## AllowSync

The `-AllowSync` switch enables a limited synchronization workflow intended for repeated pushes from GitLab to Azure DevOps.

## Usage Examples

```powershell
# Enable sync mode during migrate
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "ADOProject" -AllowSync
```

## Migration History

When sync mode is used, migration history should be recorded to allow tracking repeated runs:

- `migration_count`: Number of successful sync runs
- `previous_migrations`: Array of timestamps and summaries
- `last_sync`: Timestamp of the latest sync

## Configuration Preservation

Sync mode preserves key configuration and credentials between runs, using environment variables and .env files where appropriate.

## Workflow

### Pre-Validation

Validate that the source and destination are reachable and that credentials are valid. Produce a dry-run preview when requested.

### Repository Update

Fetch and push new commits, branches, and tags to Azure DevOps without destructive resets.

### History Recording

Append an entry to the migration history (e.g., within reports) noting changes in this run.

### Completion

Summarize results and surface any issues found. Retain audit logs for review.
