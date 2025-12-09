# Menu Structure Documentation

## Overview
The `Menu.psm1` module provides an interactive menu system for the GitLab to Azure DevOps migration toolkit. The module is organized into logical sections with helper functions for improved readability and maintainability.

## File Structure

### 1. Module Header (Lines 1-50)
- **Synopsis & Description**: Module purpose and capabilities
- **Module Imports**: Core.Rest, Migration.Core, AzureDevOps, TeamPacks, ProjectInitialization
- **Module Variables**: Script-level connection and configuration variables

### 2. Helper Functions (Lines 51-150)
Extracted UI and utility functions for better code organization:

#### Display Functions
- **Show-MenuHeader**: Displays the cyan-bordered tool header
- **Show-MenuOptions**: Renders all 15 menu options organized by category
  - Migration Preparation & Execution (Options 1-4)
  - User & Identity Management (Options 5-7, 15)
  - Project Enhancement (Options 8-9)
  - Automation & Batch Operations (Options 10-13)

#### Input Functions
- **Get-MenuChoice**: Prompts user and handles quit commands (q/quit/exit)

#### Utility Functions
- **Get-ProjectRoot**: Calculates repository root path from module location

### 3. Main Menu Function (Lines 151-200)
- **Show-MigrationMenu**: Entry point that orchestrates menu display and option routing
  - Displays header and options
  - Gets user choice
  - Routes to appropriate handler function via switch statement

### 4. Menu Option Handlers (Lines 201-1700)
Each option is implemented as a dedicated function following naming convention: `Invoke-Option{N}-{Description}`

#### Preparation Options
- **Invoke-Option1-PrepareSingle**: Single project preparation workflow
  - Progress tracking with Write-Progress
  - Self-contained folder structure
  - Documentation extraction
  - Report generation
  - Team resource provisioning

- **Invoke-Option2-PrepareBulk**: Bulk project preparation (delegates to workflow module)

- **Invoke-Option10-BulkPreparationFromConfig**: Unattended preparation from projects.json

#### Project Management Options
- **Invoke-Option3-CreateDevOpsProject**: Create ADO project with team packs
  - Handles no-preparation scenario (independent project creation)
  - Excel work item import support
  - Displays prepared projects with structure indicators (v2.1.0 vs legacy)
  - Project creation workflow

- **Invoke-Option4-StartPlannedMigration**: Execute repository migration
  - Single vs bulk migration routing
  - Refresh preparation option
  - Post-migration reporting

#### User Management Options
- **Invoke-Option5-ExportUserInfo**: Export GitLab users/groups to JSON
  - Three export modes: Minimal, Standard, Complete
  - Configurable export scope

- **Invoke-Option6-ImportUserInfo**: Full AD + ADO user import
  - Active Directory OU/group creation
  - Azure DevOps group mapping (3-step process)
  - Comprehensive logging and reporting

- **Invoke-Option7-ImportUserInfoAdoOnly**: ADO-only import (skip AD changes)
  - Maps existing AD groups to ADO groups
  - Faster for environments with pre-existing AD structure

- **Invoke-Option15-ResetUserPasswords**: Password reset with email notifications
  - Interactive wizard for SMTP configuration
  - Dry-run mode for safe testing
  - CSV export with audit trail
  - Confirmation requirement for production execution

#### Enhancement Options
- **Invoke-Option8-AddTeamPacks**: Provision team resources for existing projects
  - Wikis, queries, dashboards
  - Business/Development/Security/Management packs

- **Invoke-Option9-ImportRequirements**: Import work items from Excel
  - Project selection
  - File and worksheet specification
  - Team assignment

#### Automation Options
- **Invoke-Option11-UnattendedImport**: End-to-end unattended migration from config
- **Invoke-Option12-SyncRepos**: Batch repository sync from projects.json mapping
- **Invoke-Option13-CreateDashboards**: Batch dashboard provisioning

### 5. Team Pack Menu (Lines 1700-1850)
- **Invoke-TeamPackMenu**: Sub-menu for selecting team initialization packs
  - Business pack
  - Development pack
  - Security pack
  - Management pack
  - All packs

### 6. Utility Functions (Lines 1850-2100)
- **Invoke-ExcelImportForProject**: Reusable Excel import helper
- **Invoke-Option9PreparationRefresh**: Re-run preparation phase for Option 9
  - Supports both single and bulk refresh
  - Updates reports and documentation

### 7. Module Exports (Lines 2100+)
```powershell
Export-ModuleMember -Function @(
    'Show-MigrationMenu',
    'Invoke-TeamPackMenu'
)
```

## Key Design Patterns

### 1. Function Naming Convention
All menu option handlers follow the pattern: `Invoke-Option{Number}-{ShortDescription}`
- Examples: `Invoke-Option1-PrepareSingle`, `Invoke-Option15-ResetUserPasswords`
- Makes code navigation and debugging easier

### 2. Progress Tracking
Options with multi-step workflows use `Write-Progress` with consistent patterns:
```powershell
Write-Progress -Activity "Operation Name" -Status "Current step..." -PercentComplete 50 -Id 1
Write-Progress -Activity "Operation Name" -Status "Complete!" -PercentComplete 100 -Id 1 -Completed
```

### 3. Error Handling
- Try-catch blocks with user-friendly error messages
- Warnings for non-critical failures
- Validation before executing destructive operations

### 4. User Feedback
Consistent color coding:
- **Cyan**: Section headers and informational prompts
- **Green**: Success messages
- **Yellow**: Warnings and legacy structure indicators
- **Red**: Errors
- **Gray**: Supplementary information

### 5. Idempotency
Most operations check for existing state and skip or update appropriately:
- Project existence checks before creation
- Prepared project filtering
- Configuration validation

## Benefits of Current Structure

### Readability
- Clear separation of concerns with dedicated handler functions
- Helper functions reduce code duplication
- Consistent naming and formatting

### Maintainability
- Each option is self-contained in its own function
- Easy to add new options without modifying existing code
- Region markers clearly delineate sections

### Testability
- Individual handler functions can be unit tested
- Helper functions can be validated independently
- Mock-friendly design

### Extensibility
- New menu options can be added by:
  1. Adding display line to `Show-MenuOptions`
  2. Creating `Invoke-Option{N}-{Description}` function
  3. Adding case to switch statement in `Show-MigrationMenu`
  4. No changes needed to other functions

## Navigation Tips

### Finding Option Implementation
1. Option 5 → Search for `Invoke-Option5-`
2. Option 15 → Search for `Invoke-Option15-`
3. Team Pack Menu → Search for `Invoke-TeamPackMenu`

### Finding Helper Functions
- Search for `#region Helper Functions`
- All helpers start with `Show-`, `Get-`, or utility names

### Finding Module Configuration
- Search for `#region Module Variables`
- Search for `#region Module Imports`

## Common Modification Scenarios

### Adding a New Menu Option
```powershell
# 1. Add to Show-MenuOptions function
Write-Host " 16) New Feature" -ForegroundColor White -NoNewline
Write-Host "│ Description of feature" -ForegroundColor Gray

# 2. Create handler function
function Invoke-Option16-NewFeature {
    Write-Host "=== NEW FEATURE ===" -ForegroundColor Cyan
    # Implementation here
}

# 3. Add to switch statement in Show-MigrationMenu
'16' { Invoke-Option16-NewFeature }

# 4. Update error message range
"[ERROR] Invalid choice. Please select a number between 1 and 16, or 'q' to quit."
```

### Modifying Option Behavior
1. Locate `Invoke-Option{N}-{Description}` function
2. Modify implementation within that function
3. No changes needed elsewhere unless changing user prompts

### Adding Helper Function
```powershell
# Add to #region Helper Functions section
<#
.SYNOPSIS
    Brief description.
#>
function New-HelperFunction {
    param([string]$Input)
    # Implementation
}
```

## Testing Recommendations

### Interactive Testing
```powershell
# Run menu and select option
.\Gitlab2DevOps.ps1
# Select option number or 'q' to quit

# Direct function invocation for testing
Import-Module .\modules\Migration\Menu\Menu.psm1
Invoke-Option1-PrepareSingle
```

### Unit Testing (Pester)
```powershell
Describe "Menu Helpers" {
    It "Get-MenuChoice returns null on quit" {
        Mock Read-Host { 'q' }
        $result = Get-MenuChoice
        $result | Should -Be $null
    }
}
```

## Best Practices

1. **Always use helper functions** for display operations to maintain consistency
2. **Add progress tracking** for any operation taking more than 5 seconds
3. **Validate user input** before executing operations
4. **Use try-catch** for external operations (file I/O, API calls)
5. **Provide clear feedback** with color-coded messages
6. **Update MENU_STRUCTURE.md** when adding new options or modifying structure
7. **Follow naming conventions** for discoverability

## Related Documentation
- `README.md`: General usage and features
- `docs/cli-usage.md`: Command-line interface documentation
- `CONTRIBUTING.md`: Development guidelines
- `PASSWORD_RESET_GUIDE.md`: Option 15 detailed documentation
- `AD-Structure-MindMap.md`: Option 6/7 AD/ADO mapping details
