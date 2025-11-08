# Excel Requirements Template

This document describes the Excel format for importing work items into Azure DevOps using the `Import-AdoWorkItemsFromExcel` function.

## Excel File Format

**Worksheet Name**: `Requirements` (default, can be customized)

### Column Order (Recommended)

For easiest use, arrange columns in this exact order:

1. **LocalId** - Unique identifier for parent linking
2. **ParentLocalId** - Link to parent's LocalId (empty for top-level items)
3. **WorkItemType** - Epic, Feature, User Story, Test Case, Task, Bug, Issue
4. **Title** - Work item title (REQUIRED)
5. **Description** - Detailed description (HTML supported)
6. **AreaPath** - Area path (e.g., "MyProject\\Frontend")
7. **IterationPath** - Iteration path (e.g., "MyProject\\Sprint 1")
8. **State** - New, Active, Resolved, Closed
9. **Priority** - 1 (highest) to 4 (lowest)
10. **StoryPoints** - User Story only
11. **BusinessValue** - Epic/Feature (0-10000)
12. **ValueArea** - Business or Architectural
13. **Risk** - High, Medium, Low
14. **StartDate** - Start date
15. **FinishDate** - Finish date
16. **TargetDate** - Target date
17. **DueDate** - Due date
18. **OriginalEstimate** - Hours
19. **RemainingWork** - Hours
20. **CompletedWork** - Hours
21. **TestSteps** - Test Case only (format: "Action|Expected;;Action|Expected")
22. **Tags** - Semicolon-separated (e.g., "backend;security;sprint1")

**Note**: The script checks if each cell has a value before adding the field, so you can omit columns you don't need.

### Field Mappings to Azure DevOps

| Excel Column | Azure DevOps Field | Notes |
|--------------|-------------------|-------|
| **LocalId** | (internal mapping) | Unique integer per row (1, 2, 3...) for parent linking |
| **ParentLocalId** | System.LinkTypes.Hierarchy-Reverse | Empty for Epics, otherwise parent's LocalId |
| **WorkItemType** | System.WorkItemType | Epic, Feature, User Story, Test Case (Agile) |
| **Title** | System.Title | **REQUIRED** |
| **Description** | System.Description | HTML accepted |
| **AreaPath** | System.AreaPath | Must exist in project |
| **IterationPath** | System.IterationPath | Must exist in project |
| **State** | System.State | New, Active, Resolved, Closed |
| **Priority** | Microsoft.VSTS.Common.Priority | Integer 1-4 |
| **StoryPoints** | Microsoft.VSTS.Scheduling.StoryPoints | User Story only |
| **BusinessValue** | Microsoft.VSTS.Common.BusinessValue | Epics/Features (0-10000) |
| **ValueArea** | Microsoft.VSTS.Common.ValueArea | Business or Architectural |
| **Risk** | Microsoft.VSTS.Common.Risk | High, Medium, Low |
| **StartDate** | Microsoft.VSTS.Scheduling.StartDate | DateTime |
| **FinishDate** | Microsoft.VSTS.Scheduling.FinishDate | DateTime |
| **TargetDate** | Microsoft.VSTS.Scheduling.TargetDate | DateTime |
| **DueDate** | Microsoft.VSTS.Scheduling.DueDate | DateTime |
| **OriginalEstimate** | Microsoft.VSTS.Scheduling.OriginalEstimate | Hours (decimal) |
| **RemainingWork** | Microsoft.VSTS.Scheduling.RemainingWork | Hours (decimal) |
| **CompletedWork** | Microsoft.VSTS.Scheduling.CompletedWork | Hours (decimal) |
| **TestSteps** | Microsoft.VSTS.TCM.Steps | Test Case only (see format below) |
| **Tags** | System.Tags | Semicolon-separated |

### Test Steps Format

For Test Case work items, use this format in the **TestSteps** column:

```
Action 1|Expected 1;;Action 2|Expected 2;;Action 3|Expected 3
```

**Example**:
```
Login|User logged in;;Navigate to dashboard|Dashboard displayed;;Logout|User logged out
```

The script automatically converts this to the XML format Azure DevOps requires for `Microsoft.VSTS.TCM.Steps`.

### Required vs Optional Columns

| Required | Optional |
|----------|----------|
| LocalId | ParentLocalId |
| WorkItemType | Description |
| Title | AreaPath, IterationPath |
|  | State, Priority |
|  | All other fields |

**Important**: Only **LocalId**, **WorkItemType**, and **Title** are truly required. All other columns are optional and can be left empty.

## Example Excel Data

### Complete Example with All Columns

Here's a sample showing all columns in the recommended order:

| LocalId | ParentLocalId | WorkItemType | Title | Description | AreaPath | IterationPath | State | Priority | StoryPoints | BusinessValue | ValueArea | Risk | StartDate | FinishDate | TargetDate | DueDate | OriginalEstimate | RemainingWork | CompletedWork | TestSteps | Tags |
|---------|---------------|--------------|-------|-------------|----------|---------------|-------|----------|-------------|---------------|-----------|------|-----------|------------|------------|---------|------------------|---------------|---------------|-----------|------|
| 1 | | Epic | User Management | Complete user authentication system | MyProject | MyProject | New | 1 | | 1000 | Business | Medium | 2025-01-15 | 2025-03-31 | 2025-03-31 | | | | | | security;authentication |
| 2 | 1 | Feature | User Login | OAuth2 and local authentication | MyProject\\Backend | MyProject\\Sprint 1 | Active | 1 | | 500 | Business | Low | 2025-01-15 | 2025-02-15 | 2025-02-15 | | | | | | backend;oauth |
| 3 | 2 | User Story | Login Page UI | Responsive login form with validation | MyProject\\Frontend | MyProject\\Sprint 1 | Active | 1 | 5 | | Business | | 2025-01-20 | 2025-01-27 | | | 16 | 8 | 8 | | frontend;ui |
| 4 | 3 | Test Case | Valid Login Test | Test successful login flow | MyProject\\QA | MyProject\\Sprint 1 | New | 1 | | | | | | | | | | | | Enter username\|Username entered;;Enter password\|Password entered;;Click login\|User logged in | testing;login |
| 5 | 2 | User Story | OAuth Integration | Google and Microsoft OAuth | MyProject\\Backend | MyProject\\Sprint 2 | New | 1 | 8 | | Business | Medium | 2025-02-01 | 2025-02-14 | | | 32 | 32 | 0 | | backend;oauth;integration |

### Minimal Example (Required Fields Only)

| LocalId | ParentLocalId | WorkItemType | Title |
|---------|---------------|--------------|-------|
| 1 | | Epic | User Management |
| 2 | 1 | Feature | User Login |
| 3 | 2 | User Story | Login Page UI |
| 4 | 3 | Test Case | Valid Login Test |

### Epics (Level 1)

| LocalId | WorkItemType | Title | Description | BusinessValue | ValueArea | State | Tags |
|---------|--------------|-------|-------------|---------------|-----------|-------|------|
| 1 | Epic | User Management | Complete user authentication and authorization | 1000 | Business | New | security;authentication |
| 2 | Epic | Reporting Dashboard | Analytics and reporting features | 800 | Business | New | analytics;reporting |

### Features (Level 2)

| LocalId | ParentLocalId | WorkItemType | Title | Description | BusinessValue | State | Tags |
|---------|---------------|--------------|-------|-------------|---------------|-------|------|
| 10 | 1 | Feature | User Login | OAuth2 and local authentication | 500 | New | backend;oauth |
| 11 | 1 | Feature | User Registration | Self-service user registration | 300 | New | backend;registration |
| 20 | 2 | Feature | Sales Reports | Monthly and quarterly sales reports | 400 | New | reporting;sales |

### User Stories (Level 3)

| LocalId | ParentLocalId | WorkItemType | Title | Description | StoryPoints | Priority | State | Tags |
|---------|---------------|--------------|-------|-------------|-------------|----------|-------|------|
| 100 | 10 | User Story | Login Page UI | Create responsive login page | 5 | 1 | New | frontend;ui |
| 101 | 10 | User Story | OAuth Integration | Integrate Google/Microsoft OAuth | 8 | 1 | New | backend;oauth |
| 110 | 11 | User Story | Registration Form | Create user registration form | 5 | 2 | New | frontend;ui |

### Test Cases (Level 4)

| LocalId | ParentLocalId | WorkItemType | Title | TestSteps | Priority | Tags |
|---------|---------------|--------------|-------|-----------|----------|------|
| 1000 | 100 | Test Case | Valid Login Test | Enter username\|Username entered;;Enter password\|Password entered;;Click login\|User logged in | 1 | testing;login |
| 1001 | 100 | Test Case | Invalid Login Test | Enter wrong password\|Password entered;;Click login\|Error message displayed | 1 | testing;login;negative |

### Tasks (Level 4)

| LocalId | ParentLocalId | WorkItemType | Title | OriginalEstimate | RemainingWork | State | Tags |
|---------|---------------|--------------|-------|------------------|---------------|-------|------|
| 2000 | 100 | Task | Create login API endpoint | 16 | 16 | New | backend;api |
| 2001 | 100 | Task | Add JWT token generation | 8 | 8 | New | backend;security |

## Hierarchy Structure

```
Epic (LocalId: 1)
├── Feature (LocalId: 10, ParentLocalId: 1)
│   ├── User Story (LocalId: 100, ParentLocalId: 10)
│   │   ├── Test Case (LocalId: 1000, ParentLocalId: 100)
│   │   └── Task (LocalId: 2000, ParentLocalId: 100)
│   └── User Story (LocalId: 101, ParentLocalId: 10)
└── Feature (LocalId: 11, ParentLocalId: 1)
    └── User Story (LocalId: 110, ParentLocalId: 11)
```

## Usage

### PowerShell Command

```powershell
# Import work items from Excel
Import-AdoWorkItemsFromExcel -Project "MyProject" `
                              -ExcelPath "C:\requirements.xlsx" `
                              -WorksheetName "Requirements"

# During project initialization
Initialize-AdoProject -DestProject "MyProject" `
                      -RepoName "my-repo" `
                      -ExcelRequirementsPath "C:\requirements.xlsx" `
                      -ExcelWorksheetName "Requirements"
```

### Interactive Menu

```
1. Run Gitlab2DevOps.ps1
2. Select Option 3 (Create DevOps Project)
3. Enter project and repository names
4. When prompted "Import work items from Excel? (y/N)", enter 'y'
5. Enter path to Excel file
6. Enter worksheet name (or press Enter for default "Requirements")
```

## Tips

1. **LocalId Uniqueness**: Ensure all LocalIds are unique across the entire worksheet
2. **Hierarchical Order**: Excel rows can be in any order - the tool automatically sorts by hierarchy
3. **Parent References**: Use ParentLocalId to link children to parents (e.g., Feature to Epic)
4. **Date Formats**: Use ISO format (YYYY-MM-DD) or Excel date format
5. **Test Steps**: Escape special characters in test steps if needed
6. **Missing Columns**: Optional columns can be omitted entirely
7. **Empty Cells**: Empty cells in optional columns are safely ignored

## Troubleshooting

### ImportExcel Module Not Found

```powershell
Install-Module ImportExcel -Scope CurrentUser
```

### Work Item Type Not Found

Ensure your process template supports the work item type:
- **Agile**: Epic, Feature, User Story, Task, Bug, Issue, Test Case
- **Scrum**: Epic, Feature, Product Backlog Item, Task, Bug, Impediment, Test Case
- **CMMI**: Epic, Feature, Requirement, Task, Bug, Issue, Risk, Review, Change Request

### Parent Not Found Warning

This occurs when ParentLocalId references a LocalId that hasn't been created yet. The tool automatically sorts by hierarchy, but ensure parent LocalIds are correct.

### Field Validation Errors

Check Azure DevOps field constraints:
- Priority: 1-4
- Business Value: 0-10000
- State: Must be valid state for work item type (New, Active, Resolved, Closed)
- Area/Iteration Path: Must exist in project (create via Azure DevOps UI first)

## See Also

- [Azure DevOps REST API - Work Items](https://learn.microsoft.com/rest/api/azure/devops/wit/work-items)
- [Agile Process Template Fields](https://learn.microsoft.com/azure/devops/boards/work-items/guidance/agile-process)
- [ImportExcel PowerShell Module](https://github.com/dfinke/ImportExcel)
