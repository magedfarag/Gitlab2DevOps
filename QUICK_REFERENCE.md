# Quick Reference

A compact reference for frequently used commands and parameters.

## Core Parameters

- Mode: Operation to execute (Preflight, Initialize, Migrate, BulkPrepare, BulkMigrate, BusinessInit)
- Source: GitLab project path (group/project)
- Project: Azure DevOps project name
- AllowSync: Enable experimental sync mode for repeated runs
- Force: Skip blocking issue checks and proceed

## Examples

```powershell
# Preflight only
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/project"

# Initialize destination without migrating code
.\Gitlab2DevOps.ps1 -Mode Initialize -Source "group/project" -Project "ADOProject"

# Full migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "ADOProject"

# Business initialization for an existing ADO project
.\Gitlab2DevOps.ps1 -Mode BusinessInit -Project "ADOProject"
```
