# Bulk Migration Configuration Format

## Overview
This file defines how to migrate multiple GitLab projects into **a single Azure DevOps project** as separate repositories.

## Configuration Structure

```json
{
  "targetAdoProject": "ConsolidatedProject",
  "migrations": [
    {
      "gitlabProject": "organization/frontend-app",
      "adoRepository": "FrontendApp"
    },
    {
      "gitlabProject": "organization/backend-api",
      "adoRepository": "BackendAPI"
    }
  ]
}
```

## Properties Explained

### `targetAdoProject` (required)
- **Type**: String
- **Description**: The name of the **target Azure DevOps project** that will host all repositories
- **Example**: `"ConsolidatedProject"`, `"MyOrganizationRepos"`, `"Engineering"`
- **Note**: This project will be created if it doesn't exist. All repositories from the migrations array will be created within this single project.

### `migrations` (required)
- **Type**: Array of objects
- **Description**: List of GitLab projects to migrate and their target repository names

#### Migration Object Properties

##### `gitlabProject` (required)
- **Type**: String
- **Description**: Full path to the source GitLab project (group/project)
- **Format**: `"namespace/project-name"`
- **Examples**: 
  - `"organization/frontend-app"`
  - `"devops/infrastructure"`
  - `"team-alpha/mobile-app"`

##### `adoRepository` (required)
- **Type**: String
- **Description**: Name of the **repository** to create in the target Azure DevOps project
- **Format**: Repository name (no slashes)
- **Examples**: 
  - `"FrontendApp"`
  - `"Infrastructure"`
  - `"MobileApp"`
- **Note**: This is the **repository name**, NOT a project name. All repositories go into the single project specified in `targetAdoProject`.

##### `preparation_status` (optional)
- **Type**: String
- **Description**: Status of the migration preparation (set by bulk preparation workflow)
- **Values**: `"SUCCESS"` | `"FAILED"` | `"PENDING"`
- **Note**: When using Option 4 (bulk preparation), this field is automatically populated. For direct migrations, you can omit this field.

## Example: Migrating 5 Projects

```json
{
  "targetAdoProject": "EngineeringHub",
  "migrations": [
    {
      "gitlabProject": "frontend/web-portal",
      "adoRepository": "WebPortal",
      "preparation_status": "SUCCESS"
    },
    {
      "gitlabProject": "frontend/mobile-app",
      "adoRepository": "MobileApp",
      "preparation_status": "SUCCESS"
    },
    {
      "gitlabProject": "backend/api-gateway",
      "adoRepository": "APIGateway",
      "preparation_status": "SUCCESS"
    },
    {
      "gitlabProject": "backend/auth-service",
      "adoRepository": "AuthService",
      "preparation_status": "SUCCESS"
    },
    {
      "gitlabProject": "devops/infrastructure",
      "adoRepository": "Infrastructure",
      "preparation_status": "SUCCESS"
    }
  ]
}
```

**Result**: 
- Creates/uses Azure DevOps project: **EngineeringHub**
- Creates 5 repositories within that project:
  - WebPortal
  - MobileApp
  - APIGateway
  - AuthService
  - Infrastructure

## Common Patterns

### Pattern 1: Consolidating Microservices (Direct Migration)
```json
{
  "targetAdoProject": "MicroservicesPlatform",
  "migrations": [
    {"gitlabProject": "services/user-service", "adoRepository": "UserService"},
    {"gitlabProject": "services/order-service", "adoRepository": "OrderService"},
    {"gitlabProject": "services/payment-service", "adoRepository": "PaymentService"}
  ]
}
```
*Note: No `preparation_status` field - direct migration without preparation step*

### Pattern 2: Team Migration (With Preparation)
```json
{
  "targetAdoProject": "TeamAlpha",
  "migrations": [
    {"gitlabProject": "team-alpha/project-a", "adoRepository": "ProjectA", "preparation_status": "SUCCESS"},
    {"gitlabProject": "team-alpha/project-b", "adoRepository": "ProjectB", "preparation_status": "SUCCESS"},
    {"gitlabProject": "team-alpha/shared-libs", "adoRepository": "SharedLibraries", "preparation_status": "FAILED"}
  ]
}
```
*Note: With `preparation_status` - only SUCCESS items will be migrated, FAILED items skipped*

### Pattern 3: Departmental Migration
```json
{
  "targetAdoProject": "DataEngineeringDept",
  "migrations": [
    {"gitlabProject": "data/etl-pipelines", "adoRepository": "ETLPipelines", "preparation_status": "SUCCESS"},
    {"gitlabProject": "data/data-warehouse", "adoRepository": "DataWarehouse", "preparation_status": "SUCCESS"},
    {"gitlabProject": "data/analytics", "adoRepository": "Analytics", "preparation_status": "SUCCESS"}
  ]
}
```

## Visual Example

### What Bulk Migration Does

```
GitLab (Multiple Projects)          Azure DevOps (Single Project)
────────────────────────           ─────────────────────────────
📁 organization/                    📦 ConsolidatedProject/
   ├─ frontend-app       ────┐         ├─ 📘 FrontendApp (repo)
   ├─ backend-api        ────┼────►    ├─ 📘 BackendAPI (repo)
   └─ infrastructure     ────┘         └─ 📘 Infrastructure (repo)

Result: All three repos in ONE project
```

### What Single Migration Does (For Comparison)

```
GitLab (One Project)               Azure DevOps (One Project)
────────────────────               ──────────────────────────
📁 organization/                   📦 FrontendApp/
   └─ frontend-app     ────────►      └─ 📘 FrontendApp (repo)

Result: One project with one repo (default name same as project)
```

## Two Migration Approaches

### Approach 1: Direct Migration (Simple)
Create your config file manually and run migration directly:
```json
{
  "targetAdoProject": "MyProject",
  "migrations": [
    {"gitlabProject": "org/repo1", "adoRepository": "Repo1"},
    {"gitlabProject": "org/repo2", "adoRepository": "Repo2"}
  ]
}
```
- ✅ Quick and straightforward
- ✅ No preparation step needed
- ❌ No pre-validation
- ❌ No preparation status tracking

### Approach 2: Prepared Migration (Recommended for Large Migrations)
Use Option 4 (bulk preparation) to validate and prepare, which adds `preparation_status`:
```json
{
  "targetAdoProject": "MyProject",
  "migrations": [
    {"gitlabProject": "org/repo1", "adoRepository": "Repo1", "preparation_status": "SUCCESS"},
    {"gitlabProject": "org/repo2", "adoRepository": "Repo2", "preparation_status": "FAILED"}
  ]
}
```
- ✅ Pre-validation before migration
- ✅ Automatic status tracking
- ✅ Failed preparations are skipped
- ✅ Safer for large migrations

## Important Notes

### Single Project, Multiple Repositories
⚠️ **All repositories will be created in ONE Azure DevOps project.**

This means:
- If `targetAdoProject` is "MyProject", ALL repositories will be under `https://dev.azure.com/org/MyProject/_git/`
- Repository URLs will be:
  - `https://dev.azure.com/org/MyProject/_git/Repo1`
  - `https://dev.azure.com/org/MyProject/_git/Repo2`
  - etc.

### If You Want Separate Projects
If you want each GitLab project to become a **separate Azure DevOps project** (not just a repository), use single migrations instead:

```powershell
# Migration 1: GitLab org/repo1 → Azure DevOps Project1
.\Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/repo1" -AdoProject "Project1"

# Migration 2: GitLab org/repo2 → Azure DevOps Project2
.\Gitlab2DevOps.ps1 -Mode migrate -GitLabProject "org/repo2" -AdoProject "Project2"
```

## Validation

The script will validate:
- ✅ `targetAdoProject` is not empty
- ✅ Each `gitlabProject` is accessible
- ✅ Each `adoRepository` name is valid (no special characters, slashes, etc.)
- ✅ No duplicate repository names
- ✅ All GitLab projects exist and are accessible

## Usage

```powershell
# 1. Copy template
cp bulk-migration-config.template.json bulk-migration-config.json

# 2. Edit with your values
notepad bulk-migration-config.json

# 3. Run migration
.\Gitlab2DevOps.ps1 -Mode bulkMigrate -ConfigFile "bulk-migration-config.json"
```

## See Also
- [README.md](README.md#bulk-migration-workflow) - Full bulk migration documentation
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md#bulk-migration) - Quick command reference
