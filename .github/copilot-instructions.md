# Copilot Instructions for Gitlab2DevOps

## Architecture Overview

This is an **enterprise-grade GitLab-to-Azure DevOps migration toolkit** for on-premise Azure DevOps Server with SSL/TLS challenges. The codebase uses **modular PowerShell architecture** with strict separation of concerns:

- **`Core.Rest.psm1`**: Foundation REST API layer with **curl fallback** for SSL/TLS issues. When PowerShell `Invoke-RestMethod` fails with certificate errors, automatically falls back to `curl -k` with retry logic.
- **`GitLab.psm1`**: Source system adapter (no Azure DevOps knowledge)
- **`AzureDevOps.psm1`**: Destination system adapter (no GitLab knowledge)  
- **`Migration.psm1`**: Orchestration layer coordinating GitLab → Azure DevOps workflow
- **`Logging.psm1`**: Structured logging, reports, and audit trails

**Critical**: These modules are **intentionally decoupled**. GitLab and AzureDevOps modules never import each other.

## SSL/TLS Handling (CRITICAL)

On-premise Azure DevOps servers often have certificate issues. **All Azure DevOps REST calls MUST use `-SkipCertificateCheck`**:

```powershell
# CORRECT - Always add -SkipCertificateCheck for ADO calls
Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -SkipCertificateCheck
```

When PowerShell fails with SSL errors, the code **automatically falls back to curl**:
- Detection: Checks for "connection forcibly closed" or "An error occurred while sending the request"
- Fallback: Uses `curl -k -s -S -i -w '\nHTTP_CODE:%{http_code}' -X $Method` with Basic auth
- Retry: Treats connection resets (HTTP 0) as retryable (HTTP 503) with exponential backoff
- Authentication: For Azure DevOps, uses `-u ":$PAT"` (Basic auth), not headers

**Never remove or skip `-SkipCertificateCheck`** from Azure DevOps API calls.

### Expected 404 Errors
Some 404 errors are **normal and expected** during idempotent operations:
- **Area checks**: `GET /areas/{name}` returns 404 if area doesn't exist yet (expected)
- **Graph API**: Returns 404 on some on-premise servers (feature not available)
- **Repository checks**: Returns 404 for new repositories

These are handled gracefully by try-catch blocks:
- 404 errors on GET requests are shown in **DarkYellow** (not Red)
- No "Request failed permanently" message for expected 404s
- Users are notified at the start that 404s are normal: `[NOTE] You may see some 404 errors - these are normal when checking if resources already exist`

## Work Item Type Detection and Process Templates

Projects use **Agile process template by default**. Process template GUIDs are **queried dynamically** from the server because they differ between Azure DevOps Cloud and on-premise servers:

**CRITICAL**: Process template GUIDs vary by server! Always resolve template names to GUIDs by querying `/_apis/process/processes`.

```powershell
# Get available processes and find Agile
$processes = Invoke-AdoRest GET "/_apis/process/processes"
$agile = $processes.value | Where-Object { $_.name -eq 'Agile' }
$templateId = $agile.id  # Use this GUID for project creation

# Create project with correct template
Ensure-AdoProject -Name "MyProject" -ProcessTemplate "Agile"  # Function resolves name to GUID
```

**Work Item Types by Process Template**:
- **Agile**: User Story, Task, Bug, Epic, Feature, Test Case, Issue
- **Scrum**: Product Backlog Item, Task, Bug, Epic, Feature, Test Case, Impediment
- **CMMI**: Requirement, Task, Bug, Epic, Feature, Test Case, Issue, Risk, Review, Change Request
- **Basic**: Issue, Task, Epic

Wait **10 seconds** after project creation before querying work item types to allow initialization.

## Migration Workflow Separation

**Option 2 (Create Project)**: Creates empty Azure DevOps project structure:
- ✅ Project with Agile template
- ✅ Areas (Frontend, Backend, Infrastructure, Documentation)
- ✅ Wiki with welcome page
- ✅ Comprehensive work item templates (User Story, Task, Bug, Epic, Feature, Test Case)
- ✅ Empty repository
- ❌ **Skips branch policies** (no branches yet)

**Option 6 (Bulk Migration)**: Performs actual code migration:
- ✅ Clones GitLab repository
- ✅ Pushes code to Azure DevOps (`git push ado --mirror`)
- ✅ **Applies branch policies AFTER successful push**
- ✅ Waits 2 seconds for Azure DevOps to recognize branches
- ✅ Configures policies on default branch

**Never apply branch policies to empty repositories** - check for `$defaultRef` existence first.

## REST API Patterns

### Azure DevOps API
```powershell
# Use Invoke-AdoRest wrapper (handles auth + retry + curl fallback)
$result = Invoke-AdoRest GET "/ProjectName/_apis/git/repositories"
$result = Invoke-AdoRest POST "/ProjectName/_apis/git/repositories" -Body $repoConfig
```

### GitLab API
```powershell
# Use Invoke-GitLabRest wrapper (handles auth + retry)
$project = Invoke-GitLabRest "/api/v4/projects/$encodedPath"
```

### Error Handling
```powershell
try {
    $response = Invoke-AdoRest GET $endpoint
}
catch {
    # Errors are normalized with { side, endpoint, status, message }
    Write-Warning "[ado] Failed: $_"
    throw
}
```

## Testing with Pester

Run tests with coverage:
```powershell
Invoke-Pester -Configuration @{
    Run = @{ Path = '.\tests\*.Tests.ps1' }
    CodeCoverage = @{ 
        Enabled = $true
        Path = '.\modules\*.psm1'
        OutputFormat = 'JaCoCo'
    }
    TestResult = @{ Enabled = $true; OutputFormat = 'NUnitXml' }
}
```

Mock REST calls in tests:
```powershell
Mock Invoke-RestMethod {
    return @{ value = @( @{ name = "TestProject" } ) }
}
```

## Configuration & Credentials

**Priority order** (highest to lowest):
1. Script parameters: `-AdoPat`, `-GitLabToken`
2. Environment variables: `$env:ADO_PAT`, `$env:GITLAB_PAT`
3. `.env` file (loaded via `EnvLoader.ps1`)

**Never log or display credentials**. Use `Hide-Secret` function to mask in output:
```powershell
$maskedUrl = Hide-Secret -Text $url -Secret $token
Write-Host "Cloning from: $maskedUrl"
```

## Common Patterns

### Idempotent Operations
```powershell
# Always check existence before creating
$project = Test-AdoProjectExists -ProjectName $name
if (-not $project) {
    $project = Invoke-AdoRest POST "/_apis/projects" -Body $config
}
```

### Repository Default Branch
```powershell
# Check if repository has branches before applying policies
$defaultRef = Get-AdoRepoDefaultBranch $project $repoId
if ($defaultRef) {
    Ensure-AdoBranchPolicies -Project $project -RepoId $repoId -Ref $defaultRef
} else {
    Write-Host "[INFO] Skipping branch policies - repository has no branches yet"
}
```

### Progress Tracking
```powershell
Write-Host "[INFO] Starting operation..." -ForegroundColor Cyan
Write-Host "[SUCCESS] Operation completed" -ForegroundColor Green
Write-Warning "[WARN] Non-critical issue detected"
Write-Host "[ERROR] Operation failed" -ForegroundColor Red
```

## File Structure

```
migrations/                    # Migration workspace (gitignored)
  ├── project-name/           # Individual project preparation
  │   ├── reports/           # JSON reports (preflight, summary)
  │   ├── logs/              # Timestamped operation logs
  │   └── repository/        # Bare Git mirror (for reuse)
  └── bulk-prep-ProjectName/ # Bulk migration workspace
      └── bulk-migration-template.json

modules/
  ├── Core.Rest.psm1         # REST foundation + curl fallback
  ├── GitLab.psm1            # Source adapter
  ├── AzureDevOps.psm1       # Destination adapter
  ├── Migration.psm1         # Orchestration + menu
  └── Logging.psm1           # Reports + audit trails
```

## What NOT to Migrate

This tool **intentionally does NOT migrate**:
- Issues/Work Items (different data models)
- Merge Requests/Pull Requests (close before migration)
- CI/CD pipelines (recreate in Azure Pipelines)
- Wikis (planned for v3.0)
- User permissions (configure in Azure DevOps)

Focus on **Git repository migration with full history** (commits, branches, tags).

## Key Conventions

- **Function naming**: PascalCase with approved verbs (`Get-`, `Set-`, `New-`, `Invoke-`)
- **Parameter naming**: PascalCase (`-ProjectName`, `-AllowSync`)
- **Logging prefixes**: `[INFO]`, `[SUCCESS]`, `[WARN]`, `[ERROR]`, `[DEBUG]`
- **Error messages**: User-friendly with actionable suggestions
- **Switch parameters**: Use `.IsPresent` check: `if ($Force.IsPresent)`
- **URI encoding**: Always use `[uri]::EscapeDataString()` for path segments

## CLI vs Interactive Mode

**Interactive Mode** (default): No `-Mode` parameter, launches menu
```powershell
.\Gitlab2DevOps.ps1  # Interactive menu
```

**CLI Mode**: Automation-friendly with `-Mode` parameter
```powershell
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "ADOProject"
```

Always support both modes in new features.

## Security Best Practices

- **Token masking**: Use `Hide-Secret` for all credential output
- **Credential cleanup**: Call `Clear-GitCredentials` after git operations
- **No hardcoded secrets**: Use environment variables or parameters
- **Audit trails**: Log all operations with timestamps to `logs/` folder
- **Safe defaults**: Require explicit `-Force` for destructive operations

---

**Remember**: This is a production tool for on-premise Azure DevOps with SSL challenges. Reliability, idempotency, and clear error messages are more important than feature richness.
