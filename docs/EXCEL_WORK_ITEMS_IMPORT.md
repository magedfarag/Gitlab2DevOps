# Excel Work Items Import Guide

Import hierarchical work items (Epics, Features, User Stories, Test Cases) from Excel spreadsheets into Azure DevOps during project creation.

## Quick Start

### 1. Prepare Your Excel File

Create an Excel file (`.xlsx` or `.xls`) with a worksheet named **"Requirements"** (default name, customizable).

**File Location Options**:
- **Auto-Detection** (Recommended): Place `requirements.xlsx` in `migrations/{ProjectName}/` directory
- **Explicit Path**: Provide path via `-ExcelRequirementsPath` parameter
- **Interactive**: Enter path when prompted during project creation

**Minimum required columns**:
- `LocalId` - Unique integer (1, 2, 3...)
- `WorkItemType` - Epic, Feature, User Story, Test Case, Task, Bug, Issue
- `Title` - Work item title

**Example**:

| LocalId | ParentLocalId | WorkItemType | Title |
|---------|---------------|--------------|-------|
| 1 | | Epic | User Authentication |
| 2 | 1 | Feature | Login System |
| 3 | 2 | User Story | Login Page UI |

### 2. Import During Project Creation (Interactive)

```bash
.\Gitlab2DevOps.ps1
```

1. Select **Option 3** (Create DevOps Project)
2. Enter project name: **"demo"**
3. Enter repository name: **"my-repo"**

**Automatic Import** (if `migrations/demo/requirements.xlsx` exists):
- The tool automatically detects and imports the Excel file
- No prompts needed - seamless integration

**Manual Import** (if no Excel file detected):
- When prompted: **"Import work items from Excel? (y/N)"** → Enter **y**
- Enter path to Excel file: `C:\requirements.xlsx`
- Enter worksheet name (or press Enter for default "Requirements")

### 3. Auto-Detection Feature (Recommended)

Place your Excel file in the project's migration folder for automatic detection:

**Folder Structure**:
```
migrations/
└── YourProjectName/
    ├── requirements.xlsx    ← Place Excel file here
    ├── reports/
    └── logs/
```

**Benefits**:
- ✅ Automatic detection during project initialization
- ✅ No manual path entry needed
- ✅ Self-contained project structure
- ✅ Easy to track requirements alongside migration artifacts

**Example**:
```powershell
# 1. Prepare your Excel file
Copy-Item "C:\my-requirements.xlsx" "migrations\demo\requirements.xlsx"

# 2. Create project (auto-detects Excel file)
Initialize-AdoProject -DestProject "demo" -RepoName "my-repo"
# Output:
# [INFO] 🔍 Auto-detected Excel file in project directory: requirements.xlsx
# [INFO] 📊 Importing work items from Excel...
# [SUCCESS] ✅ Imported 7 work items from Excel
```

### 4. Import Using PowerShell Function

```powershell
# After project exists
Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\requirements.xlsx"

# During project initialization with explicit path
Initialize-AdoProject -DestProject "MyProject" `
                      -RepoName "my-repo" `
                      -ExcelRequirementsPath "C:\requirements.xlsx" `
                      -ExcelWorksheetName "Requirements"
```

## Sample Excel File

A complete sample is available at: `migrations/demo/requirements.xlsx`

This sample includes one row for each work item type:
- 1 Epic (top level)
- 1 Feature (under Epic)
- 1 User Story (under Feature)
- 1 Task (under User Story)
- 1 Bug (under User Story)
- 1 Test Case (under User Story)
- 1 Issue (under Feature)

Use this as a template for your own requirements.

## Excel Column Reference

### Recommended Column Order

1. **LocalId** - Integer (1, 2, 3...)
2. **ParentLocalId** - Integer (empty for Epics)
3. **WorkItemType** - Text (Epic, Feature, User Story, Test Case)
4. **Title** - Text (REQUIRED)
5. **Description** - Text/HTML
6. **AreaPath** - Text (e.g., "MyProject\\Frontend")
7. **IterationPath** - Text (e.g., "MyProject\\Sprint 1")
8. **State** - Text (New, Active, Resolved, Closed)
9. **Priority** - Integer (1-4, where 1 is highest)
10. **StoryPoints** - Number (User Story only)
11. **BusinessValue** - Integer (0-10000, for Epics/Features)
12. **ValueArea** - Text (Business or Architectural)
13. **Risk** - Text (High, Medium, Low)
14. **StartDate** - Date
15. **FinishDate** - Date
16. **TargetDate** - Date
17. **DueDate** - Date
18. **OriginalEstimate** - Number (hours)
19. **RemainingWork** - Number (hours)
20. **CompletedWork** - Number (hours)
21. **TestSteps** - Text (special format, Test Case only)
22. **Tags** - Text (semicolon-separated)

**Note**: Only LocalId, WorkItemType, and Title are required. All other columns are optional.

### Azure DevOps Field Mappings

| Excel Column | Azure DevOps Field |
|--------------|-------------------|
| LocalId | (internal use only) |
| ParentLocalId | System.LinkTypes.Hierarchy-Reverse |
| WorkItemType | System.WorkItemType |
| Title | System.Title |
| Description | System.Description |
| AreaPath | System.AreaPath |
| IterationPath | System.IterationPath |
| State | System.State |
| Priority | Microsoft.VSTS.Common.Priority |
| StoryPoints | Microsoft.VSTS.Scheduling.StoryPoints |
| BusinessValue | Microsoft.VSTS.Common.BusinessValue |
| ValueArea | Microsoft.VSTS.Common.ValueArea |
| Risk | Microsoft.VSTS.Common.Risk |
| StartDate | Microsoft.VSTS.Scheduling.StartDate |
| FinishDate | Microsoft.VSTS.Scheduling.FinishDate |
| TargetDate | Microsoft.VSTS.Scheduling.TargetDate |
| DueDate | Microsoft.VSTS.Scheduling.DueDate |
| OriginalEstimate | Microsoft.VSTS.Scheduling.OriginalEstimate |
| RemainingWork | Microsoft.VSTS.Scheduling.RemainingWork |
| CompletedWork | Microsoft.VSTS.Scheduling.CompletedWork |
| TestSteps | Microsoft.VSTS.TCM.Steps |
| Tags | System.Tags |

## Test Steps Format

For **Test Case** work items, use this format in the TestSteps column:

```
Action 1|Expected 1;;Action 2|Expected 2;;Action 3|Expected 3
```

**Example**:
```
Enter username|Username field populated;;Enter password|Password field populated;;Click login button|User redirected to dashboard
```

**Breakdown**:
- Use `|` (pipe) to separate action from expected result
- Use `;;` (double semicolon) to separate steps
- The script automatically converts this to Azure DevOps XML format

## Complete Example

### Excel Data

| LocalId | ParentLocalId | WorkItemType | Title | Description | Priority | StoryPoints | TestSteps | Tags |
|---------|---------------|--------------|-------|-------------|----------|-------------|-----------|------|
| 1 | | Epic | User Management | Complete authentication system | 1 | | | security;auth |
| 2 | 1 | Feature | Login System | OAuth and local login | 1 | | | backend;oauth |
| 3 | 2 | User Story | Login UI | Create login form | 1 | 5 | | frontend;ui |
| 4 | 3 | Test Case | Valid Login | Test successful login | 1 | | Login\|Credentials entered;;Submit\|Dashboard shown | testing;login |

### PowerShell Command

```powershell
Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\requirements.xlsx"
```

### Result

```
[INFO] Importing work items from Excel: C:\requirements.xlsx
[INFO] Found 4 rows in Excel
[INFO] Processing 4 work items in hierarchical order
  ✅ Created Epic #1001: User Management
  ✅ Created Feature #1002: Login System
  ✅ Created User Story #1003: Login UI
  ✅ Created Test Case #1004: Valid Login

[SUCCESS] Imported 4 work items successfully
```

## Hierarchy Rules

1. **Epics** (Level 1) - Top-level, no parent
   - ParentLocalId: (empty)
   
2. **Features** (Level 2) - Under Epics
   - ParentLocalId: Epic's LocalId
   
3. **User Stories** (Level 3) - Under Features
   - ParentLocalId: Feature's LocalId
   
4. **Test Cases/Tasks** (Level 4) - Under User Stories
   - ParentLocalId: User Story's LocalId

**Automatic Sorting**: The script automatically sorts work items by hierarchy level, so you can enter them in any order in Excel.

## Advanced Features

### API Version Selection

For different Azure DevOps Server versions:

```powershell
# Azure DevOps Server 2020
Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\reqs.xlsx" -ApiVersion "6.0"

# Azure DevOps Server 2022+
Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\reqs.xlsx" -ApiVersion "7.0"
```

### Custom Worksheet Name

```powershell
Import-AdoWorkItemsFromExcel -Project "MyProject" `
                              -ExcelPath "C:\planning.xlsx" `
                              -WorksheetName "Sprint1Requirements"
```

### Multiple Work Item Types

The script supports all Agile process work item types:
- Epic
- Feature
- User Story
- Task
- Bug
- Issue
- Test Case

## Troubleshooting

### ImportExcel Module Not Found

**Error**: `ImportExcel module not found`

**Solution**:
```powershell
Install-Module ImportExcel -Scope CurrentUser
```

### Work Item Type Not Supported

**Error**: `Work item type 'X' not found`

**Cause**: Your process template doesn't support that work item type.

**Solution**: Use work item types supported by your process template:
- **Agile**: Epic, Feature, User Story, Task, Bug, Issue, Test Case
- **Scrum**: Epic, Feature, Product Backlog Item, Task, Bug, Impediment, Test Case
- **CMMI**: Epic, Feature, Requirement, Task, Bug, Issue, Risk, Review, Change Request

### Area/Iteration Path Not Found

**Error**: `Area path 'X' does not exist`

**Cause**: The area or iteration path doesn't exist in the project.

**Solution**: Create area and iteration paths in Azure DevOps UI first, or use Initialize-AdoProject to set them up.

### Parent Not Created Yet

**Warning**: `Parent LocalId X not yet created for work item 'Y'`

**Cause**: ParentLocalId references a LocalId that appears later in the Excel file.

**Solution**: This is automatically handled - the script sorts by hierarchy. Just ensure ParentLocalId values are correct.

### Invalid Field Value

**Error**: `Cannot bind argument to parameter 'Priority'`

**Cause**: Field value doesn't match Azure DevOps constraints.

**Solution**: Check field constraints:
- Priority: 1-4 (integer)
- BusinessValue: 0-10000 (integer)
- State: New, Active, Resolved, Closed (exact case)
- StoryPoints: Positive number

## Tips & Best Practices

1. **LocalId Uniqueness**: Ensure all LocalIds are unique across the entire worksheet
2. **Start Simple**: Begin with just LocalId, WorkItemType, and Title to test
3. **Add Fields Gradually**: Add more columns as needed (script ignores empty cells)
4. **HTML in Description**: You can paste HTML directly into the Description column
5. **Date Formats**: Use ISO format (YYYY-MM-DD) or Excel date format
6. **Test Steps**: Test the format in a single Test Case before bulk import
7. **Backup First**: Always have a backup before bulk importing work items
8. **Dry Run**: Test with a small subset (5-10 items) before full import

## See Also

- [Excel Template Documentation](../examples/requirements-template.md) - Detailed column reference with examples
- [Azure DevOps REST API - Work Items](https://learn.microsoft.com/rest/api/azure/devops/wit/work-items)
- [Agile Process Fields](https://learn.microsoft.com/azure/devops/boards/work-items/guidance/agile-process)
- [ImportExcel Module](https://github.com/dfinke/ImportExcel)

## Integration Points

This feature integrates with:
1. **Project Initialization** (Initialize-AdoProject) - Excel import during Option 3
2. **Team Packs** - Works alongside team initialization packs
3. **Work Item Templates** - Creates work items after templates are set up
4. **Iterative Development** - Can be run multiple times with different Excel files
