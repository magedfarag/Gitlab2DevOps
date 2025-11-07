# User Export/Import Menu Options

This document describes the two new menu options added to the GitLab → Azure DevOps Migration Tool for handling user identity data.

## New Menu Options

### Option 5: Export User Information

**Purpose**: Export GitLab users, groups, and memberships to JSON files for later import into Azure DevOps.

**Features**:
- Exports data to a local directory (default: `exports/`)
- Three export profile options:
  - **Minimal**: Users and groups only
  - **Standard**: Users, groups, and projects
  - **Complete**: Users, groups, projects, and all memberships
- Creates timestamped export folder with structured JSON files
- Operates offline from Azure DevOps (GitLab only)

**Files Created**:
- `users.json` - GitLab user accounts
- `groups.json` - GitLab groups with proposed Azure DevOps names
- `projects.json` - GitLab projects (Standard/Complete profiles)
- `group-memberships.json` - Group membership data (Complete profile)
- `project-memberships.json` - Project membership data (Complete profile)
- `metadata.json` - Export metadata and statistics
- `export.log` - Export operation log

### Option 6: Import User Information

**Purpose**: Import previously exported GitLab identity data into Azure DevOps Server.

**Features**:
- Reads JSON files from export directory
- Two import modes:
  - **Dry Run**: Preview what would be imported (recommended first run)
  - **Execute**: Perform actual import to Azure DevOps
- Validates required files exist before starting
- Creates Azure DevOps groups and memberships based on GitLab data
- Handles user resolution (requires users to exist in AD/AAD)

**Requirements**:
- Azure DevOps Server (on-premises)
- PAT with Graph API, Projects/Teams, and Security permissions
- Exported GitLab data from Option 5
- Users must already exist in Active Directory integrated with Azure DevOps

## Workflow

1. **Export Phase** (Option 5):
   ```
   GitLab (source) → JSON files (local storage)
   ```
   - Run while GitLab is accessible
   - Can be run multiple times (incremental exports possible)
   - No Azure DevOps connection required

2. **Import Phase** (Option 6):
   ```
   JSON files (local storage) → Azure DevOps (destination)
   ```
   - Run after GitLab migration is complete
   - Requires Azure DevOps connectivity
   - Can be run in dry-run mode first for validation

## Integration with Migration Tool

These options integrate seamlessly with the existing migration workflow:

1. **Before Migration**: Use Option 5 to export user data
2. **During Migration**: Use Options 1-4 for code/project migration
3. **After Migration**: Use Option 6 to import user identities and groups

## Error Handling

- **Path Resolution**: Automatically finds export/import scripts relative to module location
- **File Validation**: Checks for required files before starting import
- **Parameter Validation**: Validates all required parameters exist
- **Graceful Failures**: Clear error messages with actionable guidance

## Technical Implementation

- **Export Script**: `examples/export-gitlab-identity.ps1`
- **Import Script**: `Import-GitLabIdentityToAdo.ps1`
- **Menu Integration**: `modules/Migration/Menu/Menu.psm1`
- **Path Resolution**: Robust relative path calculation from module to project root
- **Parameter Mapping**: Correct parameter names for both scripts

## Security Considerations

- Uses existing GitLab token and Azure DevOps PAT from main menu
- No additional credential storage required
- Export files contain identity data - handle securely
- Import operates with provided PAT permissions only