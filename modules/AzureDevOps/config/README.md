# Azure DevOps Configuration Files

This directory contains JSON configuration files that control how Azure DevOps projects are initialized during migration.

## Configuration Files

### 1. project-settings.json

Controls project structure and team settings:

- **Areas**: Work item area paths (e.g., Frontend, Backend, Infrastructure)
- **Iterations**: Sprint configuration (count, duration, naming)
- **Process Template**: Agile, Scrum, CMMI, or Basic
- **Default Repository**: Branch name and initialization settings
- **Team**: Team naming conventions

**Example customization**:
```json
{
  "areas": [
    { "name": "Mobile", "description": "Mobile apps" },
    { "name": "API", "description": "REST APIs" },
    { "name": "Database", "description": "Data layer" }
  ],
  "iterations": {
    "sprintCount": 8,
    "sprintDurationDays": 10,
    "sprintPrefix": "Iteration"
  },
  "processTemplate": "Scrum"
}
```

### 2. branch-policies.json

Controls branch protection and repository security:

- **Required Reviewers**: Minimum approvers, voting rules
- **Work Item Linking**: Enforce work item references in PRs
- **Comment Resolution**: Require comment resolution before merge
- **Build Validation**: CI/CD build checks
- **Status Checks**: External validation (e.g., SonarQube)
- **Merge Strategy**: Allowed merge types (merge commit, squash, rebase)
- **Repository Security**: Permission restrictions for specific groups

**Example customization**:
```json
{
  "branchPolicies": {
    "requiredReviewers": {
      "enabled": true,
      "minimumApproverCount": 1
    },
    "buildValidation": {
      "enabled": true,
      "buildDefinitionId": 42
    },
    "mergeStrategy": {
      "squash": true,
      "noFastForward": false
    }
  }
}
```

## Usage

### Option 1: Use Default Configurations

Simply run the migration tool - it will use the default configurations in this folder.

### Option 2: Customize Before Migration

1. **Copy configuration files**:
   ```powershell
   Copy-Item modules/AzureDevOps/config/project-settings.json my-project-settings.json
   Copy-Item modules/AzureDevOps/config/branch-policies.json my-branch-policies.json
   ```

2. **Edit the copies** to match your organization's standards

3. **Use custom configurations** (future feature):
   ```powershell
   .\Gitlab2DevOps.ps1 -ProjectSettingsFile my-project-settings.json -BranchPoliciesFile my-branch-policies.json
   ```

### Option 3: Organization-Wide Defaults

Create custom defaults for your organization:

1. Fork this repository
2. Modify the JSON files in `modules/AzureDevOps/config/`
3. Commit your organization's standards
4. Use your fork for all migrations

## Schema Validation

Each JSON file has a corresponding `.schema.json` file that provides:

- IntelliSense in VS Code and other editors
- Validation of configuration values
- Documentation of each setting
- Allowed values and defaults

VS Code will automatically validate your configurations if you have the JSON Language Features extension enabled.

## Common Customizations

### Different Process Templates

**For Scrum teams**:
```json
{
  "processTemplate": "Scrum",
  "iterations": {
    "sprintCount": 6,
    "sprintDurationDays": 14,
    "sprintPrefix": "Sprint"
  }
}
```

**For CMMI projects**:
```json
{
  "processTemplate": "CMMI"
}
```

### Relaxed Branch Policies (For Small Teams)

```json
{
  "branchPolicies": {
    "requiredReviewers": {
      "enabled": true,
      "minimumApproverCount": 1
    },
    "workItemLinking": {
      "enabled": false
    },
    "commentResolution": {
      "enabled": false
    }
  }
}
```

### Strict Enterprise Policies

```json
{
  "branchPolicies": {
    "requiredReviewers": {
      "enabled": true,
      "minimumApproverCount": 3,
      "resetOnSourcePush": true
    },
    "buildValidation": {
      "enabled": true,
      "isBlocking": true,
      "buildDefinitionId": 42
    },
    "statusCheck": {
      "enabled": true,
      "isBlocking": true,
      "statusName": "SonarQube/quality-gate",
      "statusGenre": "SonarQube"
    }
  }
}
```

### Custom Area Structure

```json
{
  "areas": [
    { "name": "Platform", "description": "Core platform services" },
    { "name": "Services", "description": "Microservices" },
    { "name": "Portal", "description": "Web portal" },
    { "name": "Mobile", "description": "Mobile apps (iOS/Android)" },
    { "name": "Integration", "description": "Third-party integrations" },
    { "name": "Operations", "description": "DevOps and monitoring" }
  ]
}
```

## Best Practices

1. **Version control your configurations**: Store your customized JSON files in a separate repository
2. **Document deviations**: If you change defaults, document why in your team wiki
3. **Test with a pilot project**: Try custom configurations on a test project first
4. **Align with standards**: Match your organization's development standards
5. **Keep it simple**: Start with defaults, only customize what's necessary

## Validation

To validate your configuration files:

```powershell
# PowerShell validation example
$config = Get-Content project-settings.json | ConvertFrom-Json
# Verify required properties exist
if (-not $config.areas -or $config.areas.Count -eq 0) {
    throw "At least one area is required"
}
```

## Future Enhancements

Planned features:

- [ ] Configuration profiles (starter, standard, enterprise)
- [ ] CLI parameter to specify config files
- [ ] Validation script to check configurations
- [ ] Import/export between projects
- [ ] Organization-level configuration management

## Support

For questions or issues with configurations:
- Create an issue in the repository
- Refer to Azure DevOps documentation for policy details
- Check the copilot-instructions.md for development guidance

---

*Last updated: 2025-11-06*
