# Logging Enhancements for reset-dashboards.ps1

## Overview
Comprehensive logging has been added to `scripts/reset-dashboards.ps1` to track progress at every level of execution, including query manipulation, dashboard operations, and REST API calls.

## Changes Summary

### 1. **Progress Logging at Project Level**
- **Location**: Main orchestration loop (lines ~1290-1310)
- **Features**:
  - `[PROJECTS]` - Total projects found from collection
  - `[FILTER]` - Filter application (include/exclude) with remaining count
  - `[PROJECT]` - Processing status with index tracking (e.g., `[1/10]`)
  - `[PROJECT-SKIP]` - Skipped projects with reasons
  - All messages include project name and ID for traceability

### 2. **Sub-Progress Bars for Teams**
- **Location**: Team iteration loop (lines ~1312-1320)
- **Features**:
  - `Write-Progress` with nested IDs (ParentId=1, Id=2) for visual hierarchy
  - Team index counter showing `[teamIndex/totalTeams]`
  - Team name and ID displayed for identification
  - Verbose logs for team processing start/completion
  - Status messages like:
    - `[TEAM-CLEANUP]` - Temporary dashboard cleanup
    - `[TEAM-READ]` - Current dashboard reading
    - `[TEAM-RECOMMEND]` - Recommended dashboard generation
    - `[TEAM-RESET]` or `[TEAM-MERGE]` - Mode selection

### 3. **Dashboard Operation Tracking**
- **Temporary Dashboard Creation Phase**:
  - `[TEAM-CREATE-TMP]` - Phase 1 of 3 label
  - Sub-progress bar (Id=3) with dashboard index `[dashIndex/recommended.Count]`
  - `[CREATE]` - Individual dashboard creation with ID tracking
  - `[DASHBOARD-CREATE]` - Verbose logs showing widget count and success/failure
  - Dry-run mode indication

- **Old Dashboard Deletion Phase**:
  - `[TEAM-DELETE]` - Phase 2 of 3 label
  - `[READ]` - Dashboard count after temp creation
  - `[DELETE]` - Individual deletion with count tracking
  - Dry-run awareness

- **Dashboard Rename Phase**:
  - `[TEAM-RENAME]` - Phase 3 of 3 label
  - `[RENAME]` - Individual rename operations with source/target names
  - `[DASHBOARD-RENAME]` - Verbose logs for debugging rename issues

### 4. **Query Manipulation Tracking**
- **Query Cleanup**:
  - `[QUERY-CLEANUP]` - Cleanup operation start
  - Item count in folder being examined
  - Individual query deletion logs with reason (temporary/legacy)
  - Cleaned count summary

- **Query Creation/Renaming**:
  - `[QUERY-CREATE]` - Multi-step query creation process
  - Step logs for:
    - Removing leftover temporary queries
    - Creating new query with temporary name
    - Deleting conflicting final-named queries
    - Renaming from temporary to final name
    - Success/failure at each step with IDs

### 5. **REST API Call Logging**
- **Location**: `Invoke-AdoRest` function (lines ~168-180)
- **Features**:
  - `[REST]` - Method and URI for each call
  - `[REST-INVOKE]` - Execution indicator
  - `[REST-IGNORED]` - 404 responses that are ignored
  - `[REST-ERROR]` - Error details with exception message

### 6. **Helper Function Logging**
- **Get-AdoProjects**: `[PROJECTS]` tags for count tracking
- **Get-AdoTeams**: `[TEAMS]` tags with project context
- **Get-AdoDashboards**: `[DASHBOARDS]` tags with team context
- **Remove-AdoDashboard**: `[DASHBOARD-DELETE]` tags
- **Get-SharedQueriesFolderId**: `[QUERIES]` tags for folder ID retrieval
- **Clean-TempDashboards**: `[CLEANUP-TEMP]` tags with count
- **Clean-OldQueries**: `[QUERY-CLEANUP]` tags

## Logging Levels

### Write-Host (User-facing output)
- Project/Team level progress
- Dashboard phase indicators
- Summary statistics
- Critical status information
- Color-coded for easy reading:
  - Green: Success/Completion
  - Yellow: Processing/Warnings
  - Cyan: Information/Statistics
  - DarkGray: Secondary operations
  - DarkGreen: Created items
  - DarkYellow: Deleted items
  - Magenta: Project processing

### Write-Verbose (Diagnostic output)
- REST API call details
- Query manipulation steps
- Team/Project completion markers
- Dashboard operation details
- Error context
- *Enable with: `-Verbose` parameter or `$VerbosePreference = 'Continue'`*

## Output Examples

### With Normal Output (Write-Host)
```
[PROCESSING] Starting to process 5 project(s)...
[PROJECT] [1/5] Processing: MyProject [ID: 12345]
[PROJECT] Found 3 team(s) in project MyProject
    [TEAM] [1/3] Processing: TeamA [ID: team-a]
      [TEAM-RECOMMEND] Generated 4 recommended dashboard(s)
      [TEAM-RESET] FORCE MODE: Resetting dashboards for team 'TeamA'...
      [TEAM-CREATE-TMP] Creating temporary dashboards (Phase 1 of 3)...
        [CREATE] [1/4] Creating temporary dashboard: '[TMP] Business Product'
          -> Created TMP dashboard ID: dashboard-id-123
      [TEAM-DELETE] Deleting old dashboards (Phase 2 of 3)...
        [DELETE] [1] Deleting old dashboard: 'OldDashboard' [ID: old-dash-id]
      [TEAM-RENAME] Renaming temporary dashboards (Phase 3 of 3)...
        [RENAME] [1] Renaming: '[TMP] Business Product' -> 'Business Product'
          -> Successfully renamed (ID: dashboard-id-123)

[COMPLETE] Dashboard operation completed!
[SUMMARY] Statistics:
  - Projects Processed: 5
  - Teams Processed: 12
  - Dashboards Created: 48
  - Dashboards Deleted: 15
  - DryRun Mode: False
  - Reset Mode: True
```

### With Verbose Output (Selected `-Verbose`)
```
[REST] GET /project/_apis/projects
[REST-INVOKE] Executing GET request to https://collection/_apis/projects?$top=1000
[PROJECTS] Found 5 project(s)
[PROJECTS] Fetching all projects from collection...
[PROJECT] Starting project processing: MyProject
[TEAMS] Fetching teams for project 12345...
[TEAM] Starting team processing: TeamA in project MyProject
[QUERY-CLEANUP] Cleaning old/temporary queries from project 12345, folder folder-id...
[QUERY-CREATE] Removing any leftover temporary query: [TMP] Product Backlog Health
[QUERY-CREATE] Creating new query: [TMP] Product Backlog Health with WIQL pattern
[QUERY-CREATE] Successfully created temporary query with ID: query-id-456
[QUERY-CREATE] Renaming query from '[TMP] Product Backlog Health' to final name 'Product Backlog Health'
[QUERY-CREATE] Successfully renamed query to: Product Backlog Health (ID: query-id-456)
[TEAM] Completed team processing: TeamA
[PROJECT] Completed project processing: MyProject
[COMPLETE] Dashboard reset/creation process finished. Projects: 5, Teams: 12, Created: 48, Deleted: 15
```

## Sub-Progress Bars

The script implements a three-level progress bar hierarchy:

1. **Primary Level (Id=1)**: Projects being processed
   - Shows overall completion percentage
   - Displays current project name

2. **Secondary Level (Id=2, ParentId=1)**: Teams within current project
   - Shows team completion percentage
   - Nested under project progress bar
   - Displays current team name

3. **Tertiary Level (Id=3, ParentId=2)**: Dashboards being created/renamed
   - Shows dashboard completion percentage
   - Nested under team progress bar
   - Displays current dashboard name

This provides clear visual feedback for multi-level operations without console clutter.

## Usage Examples

### Default (normal output)
```powershell
.\scripts\reset-dashboards.ps1 -EnvPath ".env" -ClearExistingDashboards
```

### With verbose logging
```powershell
.\scripts\reset-dashboards.ps1 -EnvPath ".env" -ClearExistingDashboards -Verbose
```

### Dry-run with verbose logging
```powershell
.\scripts\reset-dashboards.ps1 -EnvPath ".env" -ClearExistingDashboards -DryRun -Verbose
```

### With project filtering and verbose logging
```powershell
.\scripts\reset-dashboards.ps1 -EnvPath ".env" -ProjectInclude @("Project1", "Project2") -Verbose
```

## Benefits

1. **Visibility**: Every operation level is logged for complete traceability
2. **Debugging**: Verbose mode provides diagnostic information for troubleshooting
3. **Performance Monitoring**: Progress bars show real-time processing status
4. **Error Tracking**: All errors are logged with context
5. **Audit Trail**: Complete record of what was created/deleted and when
6. **User Feedback**: Clear status messages keep operators informed
7. **Query Tracking**: Detailed logging of query creation, deletion, and renaming
8. **REST Monitoring**: All REST API calls are logged for debugging

## Technical Details

- **Tag Format**: `[CATEGORY-ACTION]` for consistent parsing and filtering
- **Progress Bar IDs**: 1 (projects), 2 (teams), 3 (dashboards) for hierarchy
- **Colors**: Used for visual distinction without affecting `-Verbose` output
- **Verbose Prefix**: All `-Verbose` messages use standardized tag format
- **Backward Compatible**: Changes don't affect existing functionality or error handling
