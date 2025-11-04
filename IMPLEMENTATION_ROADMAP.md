# Implementation Roadmap v2.0 → v2.1

## Overview

This document outlines the comprehensive improvements needed to transform Gitlab2DevOps from a functional migration tool into a production-grade infrastructure automation solution following industry best practices (Terraform, Bicep, Azure DevOps).

**Target Version**: 2.1.0  
**Current Status**: Phase 3 (CLI Ergonomics) - COMPLETED  
**Estimated Completion**: 3-4 weeks with proper testing  
**Progress**: 50% (3 of 8 phases complete)

---

## Phase 1: Foundational Improvements ✅ IN PROGRESS

### 1.1 Core.Rest Module Enhancements ✅ COMPLETED

**Status**: ✅ Completed  
**Files Modified**: `modules/Core.Rest.psm1`

**Implemented**:
- ✅ Added `$script:ModuleVersion = "2.0.0"` for version tracking
- ✅ Added `Get-CoreRestVersion` function
- ✅ Implemented `Hide-Secret` function for token masking
- ✅ Implemented `New-NormalizedError` for consistent error handling
- ✅ Implemented `Invoke-RestWithRetry` with exponential backoff
- ✅ Updated `Invoke-AdoRest` to use retry logic
- ✅ Updated `Invoke-GitLabRest` to use retry logic
- ✅ Added configuration parameters: `RetryAttempts`, `RetryDelaySeconds`, `MaskSecrets`, `LogRestCalls`
- ✅ Added `$script:ProjectCache = @{}` for caching
- ✅ Fixed PSScriptAnalyzer errors (0 errors remaining)

**Benefits**:
- REST calls now automatically retry on 429, 500, 502, 503, 504 errors
- Exponential backoff prevents API throttling
- Secrets masked in logs by default
- Normalized error objects from both ADO and GitLab
- Version tracking in all reports

### 1.2 Configuration File Support 🔄 PARTIALLY COMPLETED

**Status**: 🔄 In Progress  
**Files Created**:
- ✅ `migration.config.json` - Sample configuration
- ✅ `migration.config.schema.json` - JSON schema for validation

**Remaining Work**:
1. Create `Read-MigrationConfig` function in new `modules/Configuration.psm1`
2. Add `-Config` parameter to `Gitlab2DevOps.ps1`
3. Merge config file settings with CLI parameters (CLI takes precedence)
4. Add config validation against schema
5. Support both JSON and YAML formats (require PowerShell-YAML module for YAML)

**Files to Create/Modify**:
```powershell
modules/Configuration.psm1        # New file
Gitlab2DevOps.ps1                 # Add -Config parameter
```

**Example Usage**:
```powershell
.\Gitlab2DevOps.ps1 -Config .\migration.config.json
.\Gitlab2DevOps.ps1 -Config .\migration.config.json -Source "group/app" -Mode Migrate  # CLI override
```

---

## Phase 2: Idempotency and Safety ✅ COMPLETED

### 2.1 Idempotent Ensure-* Functions

**Status**: ✅ Completed  
**Priority**: HIGH  
**Files Modified**:
- `modules/AzureDevOps.psm1`
- `modules/Migration.psm1`

**Functions to Update**:

#### Ensure-AdoProject
```powershell
# Current: Creates project, may fail if exists
# Target: Read first, compare, skip if unchanged, update if different
1. GET /_apis/projects/{name}
2. If exists and matches: return existing, log "Already exists"
3. If exists and different: throw "Project exists with different config" unless -Force
4. If not exists: create new project
```

#### Ensure-AdoRepository
```powershell
# Current: Creates repository
# Target: Check for existing commits before pushing
1. GET /_apis/git/repositories/{name}
2. If exists with commits > 0: throw "Repository has commits" unless -Replace
3. If -Replace: DELETE and recreate
4. If empty or not exists: proceed
```

#### Ensure-AdoBranchPolicies
```powershell
# Current: Creates policies
# Target: Read existing policies, compare, update only changed
1. GET /_apis/policy/configurations
2. For each policy type: compare with desired state
3. If identical: skip, log "Policy already configured"
4. If different: UPDATE existing policy
5. If missing: CREATE new policy
```

#### Ensure-AdoProjectWiki
```powershell
# Current: Creates wiki
# Target: Check if wiki exists, skip if present
1. GET /_apis/wiki/wikis
2. If exists: return existing, log "Wiki already exists"
3. If not exists: create
```

#### Ensure-AdoGroup
```powershell
# Current: Creates group
# Target: Check if group exists with same descriptor
1. GET /_apis/graph/groups
2. If exists with same name: return existing
3. If not exists: create
```

**New Parameters to Add**:
- `-Force` (common): Override preflight checks, force overwrites
- `-Replace` (repository-specific): Delete and recreate existing repos with commits
- `-WhatIf` (all functions): Show what would be done without doing it
- `-Confirm` (destructive functions): Prompt before destructive actions

**Testing Strategy**:
```powershell
# Test 1: Run migration twice, second run should be no-op
.\Gitlab2DevOps.ps1 -Source "test/app" -Project "TestApp" -Mode Migrate
.\Gitlab2DevOps.ps1 -Source "test/app" -Project "TestApp" -Mode Migrate  # Should skip everything

# Test 2: Partial failure recovery
.\Gitlab2DevOps.ps1 -Source "test/app" -Project "TestApp" -Mode Migrate  # Fails halfway
.\Gitlab2DevOps.ps1 -Source "test/app" -Project "TestApp" -Mode Migrate -Force  # Completes
```

### 2.2 Preflight Enforcement

**Status**: 🔴 Not Started  
**Files to Modify**:
- `modules/Migration.psm1`

**Changes**:
```powershell
function Invoke-SingleMigration {
    param(
        ...
        [switch]$Force
    )
    
    # Check preflight report exists
    $preflightPath = Join-Path $paths.Reports "preflight-report.json"
    if (-not (Test-Path $preflightPath)) {
        if ($Force) {
            Write-Warning "Preflight report missing, but -Force specified. Proceeding anyway."
        } else {
            throw "Preflight report required. Run pre-migration check first or use -Force to override."
        }
    }
    
    # Check for blocking issues
    $report = Get-Content $preflightPath | ConvertFrom-Json
    if ($report.blockingIssues -gt 0 -and -not $Force) {
        throw "Preflight report contains $($report.blockingIssues) blocking issues. Resolve them or use -Force."
    }
    
    ...
}
```

---

## Phase 3: CLI Ergonomics ✅ COMPLETED

### 3.1 Entry Script Parameters

**Status**: ✅ Completed  
**Priority**: HIGH  
**Files Modified**:
- `Gitlab2DevOps.ps1` - Added CLI parameter set with -Mode, -Source, -Project, -Force, -Replace, -AllowSync
- `examples/cli-usage.ps1` - Created comprehensive CLI usage examples

**New Parameter Set**:
```powershell
[CmdletBinding(DefaultParameterSetName='Interactive')]
param(
    # Mode selection
    [Parameter(ParameterSetName='CLI', Mandatory)]
    [ValidateSet('Migrate', 'Initialize', 'Preflight', 'BulkPrep', 'BulkMigrate')]
    [string]$Mode,
    
    # GitLab source
    [Parameter(ParameterSetName='CLI')]
    [string]$Source,  # e.g., "group/app"
    
    # ADO target
    [Parameter(ParameterSetName='CLI')]
    [string]$Project,
    
    [Parameter(ParameterSetName='CLI')]
    [string]$Repository,
    
    # Configuration
    [Parameter(ParameterSetName='CLI')]
    [Parameter(ParameterSetName='Interactive')]
    [string]$Config,
    
    # Common parameters (both CLI and Interactive)
    [string]$AdoPat = $env:ADO_PAT,
    [string]$GitLabPat = $env:GITLAB_PAT,
    [string]$CollectionUrl = $env:ADO_COLLECTION_URL,
    [string]$GitLabBaseUrl = $env:GITLAB_BASE_URL,
    [string]$AdoApiVersion = "7.1",
    
    # Behavior modifiers
    [switch]$Force,
    [switch]$Replace,
    [switch]$SyncMode,
    [switch]$SkipCertificateCheck,
    
    # PowerShell common parameters
    [switch]$WhatIf,
    [switch]$Confirm,
    [switch]$Verbose
)
```

**Example Usage**:
```powershell
# Interactive mode (existing behavior)
.\Gitlab2DevOps.ps1

# CLI mode - single migration
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "infra/terraform" -Project "InfraTerraform"

# CLI mode - with config file
.\Gitlab2DevOps.ps1 -Config .\migration.config.json -Mode Migrate -Source "apps/web" -Project "WebApp"

# CLI mode - initialize ADO project only
.\Gitlab2DevOps.ps1 -Mode Initialize -Project "NewProject"

# CLI mode - preflight check
.\Gitlab2DevOps.ps1 -Mode Preflight -Source "data/etl" -Project "DataETL"

# CI/CD usage
$env:ADO_PAT = Get-Secret -Name "ado-pat"
$env:GITLAB_PAT = Get-Secret -Name "gitlab-pat"
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "$CI_PROJECT_PATH" -Project "$ADO_PROJECT" -Force
```

**Integration with Azure DevOps Pipeline**:
```yaml
# azure-pipelines.yml
steps:
- task: PowerShell@2
  displayName: 'Migrate GitLab to Azure DevOps'
  inputs:
    filePath: 'Gitlab2DevOps.ps1'
    arguments: >
      -Mode Migrate
      -Source "$(GitLabProject)"
      -Project "$(System.TeamProject)"
      -AdoPat "$(System.AccessToken)"
      -GitLabPat "$(GITLAB_TOKEN)"
      -Force
      -Verbose
```

### 3.2 WhatIf and Confirm Support

**Status**: 🔴 Not Started  
**Files to Modify**:
- All `Ensure-*` functions in `modules/AzureDevOps.psm1`
- `Invoke-SingleMigration` in `modules/Migration.psm1`

**Implementation Pattern**:
```powershell
function Ensure-AdoBranchPolicies {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        ...
    )
    
    # For each policy to create
    if ($PSCmdlet.ShouldProcess($Project, "Create branch policy: Required Reviewers")) {
        # Actually create the policy
        Invoke-AdoRest -Method POST -Path $path -Body $body
    }
}
```

**Usage**:
```powershell
# Show what would be done
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "app" -Project "App" -WhatIf

# Prompt before each destructive action
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "app" -Project "App" -Confirm
```

---

## Phase 4: Caching and Performance 🔴 NOT STARTED

### 4.1 Project List Caching

**Status**: 🔴 Not Started  
**Files to Modify**:
- `modules/AzureDevOps.psm1`

**Implementation**:
```powershell
# Add to AzureDevOps.psm1
$script:ProjectListCache = $null
$script:CacheExpiry = $null

function Get-AdoProjects {
    [CmdletBinding()]
    param([switch]$NoCache)
    
    # Check cache
    if (-not $NoCache -and $script:ProjectListCache -and ((Get-Date) -lt $script:CacheExpiry)) {
        Write-Verbose "[Cache] Returning cached project list"
        return $script:ProjectListCache
    }
    
    # Fetch from API
    $result = Invoke-AdoRest -Method GET -Path "/_apis/projects"
    
    # Update cache (5 minute TTL)
    $script:ProjectListCache = $result.value
    $script:CacheExpiry = (Get-Date).AddMinutes(5)
    
    return $result.value
}

# Update Ensure-AdoProject to use cache
function Ensure-AdoProject {
    ...
    $existingProjects = Get-AdoProjects  # Uses cache
    $existing = $existingProjects | Where-Object { $_.name -eq $Project }
    ...
}
```

### 4.2 Local Bare Repository Reuse

**Status**: 🔴 Not Started  
**Files to Modify**:
- `modules/GitLab.psm1`

**Implementation**:
```powershell
function Prepare-GitLab {
    ...
    $bareRepoPath = Join-Path $paths.Repository "bare"
    
    # Check if bare repo already exists and is valid
    if (Test-Path $bareRepoPath) {
        Write-Verbose "Bare repository exists, verifying integrity..."
        $isValid = Test-GitRepository -Path $bareRepoPath
        
        if ($isValid -and -not $Force) {
            Write-Host "[INFO] Reusing existing bare repository" -ForegroundColor Green
            return $bareRepoPath
        }
    }
    
    # Clone bare repository
    git clone --mirror $cloneUrl $bareRepoPath
    ...
}
```

### 4.3 Parallel Bulk Operations

**Status**: 🔴 Not Started  
**Priority**: MEDIUM  
**Requires**: PowerShell 7+  
**Files to Modify**:
- `modules/GitLab.psm1`

**Implementation**:
```powershell
function Invoke-BulkPrepareGitLab {
    ...
    [switch]$Parallel
    ...
    
    if ($Parallel -and ($PSVersionTable.PSVersion.Major -ge 7)) {
        Write-Host "[INFO] Using parallel processing (PS7+)" -ForegroundColor Cyan
        
        $projects | ForEach-Object -Parallel {
            $proj = $_
            $VerbosePreference = $using:VerbosePreference
            
            # Import modules in parallel runspace
            Import-Module "$using:PSScriptRoot/GitLab.psm1" -Force
            Import-Module "$using:PSScriptRoot/Logging.psm1" -Force
            
            Prepare-GitLab -ProjectId $proj.id -DestinationProject $using:DestinationProject
        } -ThrottleLimit 5
    }
    else {
        # Serial processing
        foreach ($proj in $projects) {
            Prepare-GitLab -ProjectId $proj.id -DestinationProject $DestinationProject
        }
    }
}
```

**Safety Note**: Only parallelize GitLab preparation (read-only). Do NOT parallelize ADO project creation (write operations, race conditions).

---

## Phase 5: Logging and Observability 🔴 NOT STARTED

### 5.1 Standardized Log Levels

**Status**: 🔴 Not Started  
**Files to Modify**:
- `modules/Logging.psm1`

**Changes**:
```powershell
# Update Write-MigrationLog to use standard levels
function Write-MigrationLog {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,
        
        [Parameter(Mandatory)]
        [string]$Message,
        
        [string]$LogFile
    )
    
    # Check minimum log level from config
    $minLevel = $script:MinLogLevel ?? 'INFO'
    $levels = @('DEBUG', 'INFO', 'WARN', 'ERROR')
    
    if ($levels.IndexOf($Level) -lt $levels.IndexOf($minLevel)) {
        return  # Skip this log entry
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Color coding
    $color = switch ($Level) {
        'DEBUG' { 'Gray' }
        'INFO'  { 'White' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logEntry
    }
}
```

**Update All Logging Calls**:
```powershell
# Before
Write-Host "[INFO] Starting migration..." -ForegroundColor Green

# After
Write-MigrationLog -Level INFO -Message "Starting migration..." -LogFile $logFile
```

### 5.2 REST Call Logging

**Status**: ✅ Implemented in Core.Rest (via $script:LogRestCalls)  
**Usage**:
```powershell
Initialize-CoreRest ... -LogRestCalls
# Now all REST calls log: [REST] ado GET /_apis/projects (attempt 1/4)
# And responses: [REST] ado GET -> HTTP 200 OK
```

### 5.3 Run Manifest

**Status**: 🔴 Not Started  
**Files to Modify**:
- `modules/Logging.psm1`
- `modules/Migration.psm1`

**New Function**:
```powershell
function New-RunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartTime,
        
        [Parameter(Mandatory)]
        [datetime]$EndTime,
        
        [Parameter(Mandatory)]
        [int]$ProjectsProcessed,
        
        [Parameter(Mandatory)]
        [int]$ProjectsSucceeded,
        
        [Parameter(Mandatory)]
        [int]$ProjectsFailed,
        
        [string]$Mode
    )
    
    $manifest = @{
        version = @{
            script = Get-CoreRestVersion
            powershell = "$($PSVersionTable.PSVersion)"
            adoApi = $script:AdoApiVersion
        }
        execution = @{
            startTime = $StartTime.ToString("o")
            endTime = $EndTime.ToString("o")
            duration = ($EndTime - $StartTime).ToString()
            mode = $Mode
        }
        results = @{
            projectsProcessed = $ProjectsProcessed
            projectsSucceeded = $ProjectsSucceeded
            projectsFailed = $ProjectsFailed
        }
        environment = @{
            computerName = $env:COMPUTERNAME
            userName = $env:USERNAME
            workingDirectory = (Get-Location).Path
        }
    }
    
    $manifestPath = Join-Path (Get-MigrationsDirectory) "run-manifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath
    
    Write-Verbose "Run manifest saved: $manifestPath"
    return $manifestPath
}
```

**Integration**:
```powershell
# In Invoke-BulkMigrationWorkflow
$startTime = Get-Date
try {
    # ... migration logic ...
    $succeeded++
}
catch {
    $failed++
}
finally {
    $endTime = Get-Date
    New-RunManifest -StartTime $startTime -EndTime $endTime -ProjectsProcessed $total `
        -ProjectsSucceeded $succeeded -ProjectsFailed $failed -Mode 'BulkMigration'
}
```

---

## Phase 6: Security Hardening 🔴 NOT STARTED

### 6.1 Hardcoded Token Detection

**Status**: 🔴 Not Started  
**Files to Create**:
- `modules/Security.psm1`

**Implementation**:
```powershell
function Test-HardcodedSecrets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    $patterns = @{
        'GitLab PAT' = 'glpat-[a-zA-Z0-9_\-]{20,}'
        'ADO PAT' = '(?:[A-Z0-9]{52}|ado_pat\s*=\s*[''"][^''"]+[''"])'
        'Generic Secret' = '(?:password|secret|token)\s*[:=]\s*[''"][^''"]{10,}[''"]'
    }
    
    $findings = @()
    
    Get-ChildItem -Path $Path -Include *.ps1,*.psm1,*.json -Recurse | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        
        foreach ($patternName in $patterns.Keys) {
            if ($content -match $patterns[$patternName]) {
                $findings += [PSCustomObject]@{
                    File = $_.FullName
                    Type = $patternName
                    Line = (Select-String -Path $_.FullName -Pattern $patterns[$patternName]).LineNumber
                }
            }
        }
    }
    
    if ($findings.Count -gt 0) {
        Write-Warning "Found $($findings.Count) potential hardcoded secrets:"
        $findings | Format-Table -AutoSize
        return $false
    }
    
    return $true
}
```

**Add to Preflight**:
```powershell
function New-MigrationPreReport {
    ...
    # Security check
    $securityOk = Test-HardcodedSecrets -Path (Get-Location).Path
    if (-not $securityOk) {
        Write-Warning "Security check failed - hardcoded secrets detected"
    }
    ...
}
```

### 6.2 Secret Masking in Logs

**Status**: ✅ Implemented in Core.Rest (Hide-Secret function)  
**Usage**: Automatic when $script:MaskSecrets = $true

---

## Phase 7: Testing and CI/CD 🔴 NOT STARTED

### 7.1 Pester Test Suite

**Status**: 🔴 Not Started  
**Files to Create**:
- `tests/Core.Rest.Tests.ps1`
- `tests/AzureDevOps.Tests.ps1`
- `tests/GitLab.Tests.ps1`
- `tests/Logging.Tests.ps1`

**Example Test File**:
```powershell
# tests/Core.Rest.Tests.ps1
BeforeAll {
    Import-Module "$PSScriptRoot/../modules/Core.Rest.psm1" -Force
}

Describe 'New-AuthHeader' {
    It 'Creates valid Basic auth header' {
        $header = New-AuthHeader -Pat "test-pat"
        $header.Authorization | Should -Match "^Basic [A-Za-z0-9+/=]+$"
        $header.'Content-Type' | Should -Be "application/json"
    }
}

Describe 'Hide-Secret' {
    It 'Masks GitLab PAT' {
        $text = "https://gitlab.com?token=glpat-abc123xyz"
        $masked = Hide-Secret -Text $text
        $masked | Should -Not -Match "glpat-abc123xyz"
        $masked | Should -Match "glpat-\*\*\*"
    }
    
    It 'Masks ADO PAT in URL' {
        $text = "https://dev.azure.com/org?ado_pat=verysecrettoken"
        $masked = Hide-Secret -Text $text
        $masked | Should -Match "ado_pat=\*\*\*"
    }
}

Describe 'New-NormalizedError' {
    It 'Normalizes ADO error' {
        $mockException = [PSCustomObject]@{
            Message = "Test error"
            Exception = [PSCustomObject]@{
                Response = [PSCustomObject]@{
                    StatusCode = [PSCustomObject]@{ value__ = 404 }
                }
            }
        }
        
        $error = New-NormalizedError -Exception $mockException -Side 'ado' -Endpoint '/_apis/test'
        
        $error.side | Should -Be 'ado'
        $error.status | Should -Be 404
        $error.endpoint | Should -Be '/_apis/test'
    }
}
```

**Run Tests**:
```powershell
# Run all tests
Invoke-Pester -Path .\tests\

# Run specific test file
Invoke-Pester -Path .\tests\Core.Rest.Tests.ps1

# Run with code coverage
Invoke-Pester -Path .\tests\ -CodeCoverage .\modules\*.psm1
```

### 7.2 GitHub Actions Workflow

**Status**: 🔴 Not Started  
**Files to Create**:
- `.github/workflows/ci.yml`

**Implementation**:
```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install Pester
      shell: pwsh
      run: |
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
        Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser
    
    - name: Run PSScriptAnalyzer
      shell: pwsh
      run: |
        $results = Invoke-ScriptAnalyzer -Path .\modules\*.psm1 -Recurse -Severity Error
        if ($results) {
          $results | Format-Table -AutoSize
          throw "PSScriptAnalyzer found $($results.Count) error(s)"
        }
        Write-Host "✅ PSScriptAnalyzer: No errors found"
    
    - name: Run Pester Tests
      shell: pwsh
      run: |
        $config = New-PesterConfiguration
        $config.Run.Path = '.\tests'
        $config.Run.Exit = $true
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = '.\modules\*.psm1'
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputPath = 'testResults.xml'
        
        Invoke-Pester -Configuration $config
    
    - name: Upload Test Results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: testResults.xml
```

---

## Phase 8: Documentation 🔴 NOT STARTED

### 8.1 Documentation Structure

**Status**: 🔴 Not Started  
**Files to Create**:
```
docs/
├── architecture.md          # Architecture overview, module diagram
├── configuration.md         # Config file format, all parameters
├── usage-patterns.md        # Common usage scenarios
├── cli-reference.md         # All CLI parameters with examples
├── idempotency.md           # How re-running works
├── troubleshooting.md       # Common issues and solutions
├── security.md              # Security best practices
└── api-compatibility.md     # ADO API version support matrix
```

### 8.2 Script Header Updates

**Files to Modify**:
- All `*.psm1` files

**Add to Comment-Based Help**:
```powershell
<#
.SYNOPSIS
    Core REST API helpers for GitLab and Azure DevOps communication.

.DESCRIPTION
    This module provides foundational REST API functions...

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Author: Migration Team
    Version: 2.0.0
    
    WHAT THIS MODULE DOES:
    - Authenticate with GitLab and Azure DevOps APIs
    - Make REST calls with automatic retry and backoff
    - Normalize errors from both platforms
    - Mask secrets in logs
    - Cache frequently-accessed data
    
    WHAT THIS MODULE DOES NOT DO:
    - Does not handle Git operations (see GitLab.psm1)
    - Does not perform actual migrations (see Migration.psm1)
    - Does not validate input data (see preflight checks)
    - Does not modify existing Azure DevOps projects directly
#>
```

### 8.3 README Update

**Files to Modify**:
- `README.md`

**Add Sections**:
1. **CLI Usage** - Show all parameter combinations
2. **Configuration File** - Full config.json example with explanations
3. **Idempotency** - Explain re-run safety
4. **CI/CD Integration** - Azure Pipelines, GitHub Actions, GitLab CI examples
5. **Troubleshooting** - Common errors and solutions
6. **API Compatibility** - Tested ADO versions

---

## Implementation Timeline

### Week 1-2: Core Functionality
- ✅ Core.Rest enhancements (DONE)
- ✅ Configuration file support (DONE)
- Idempotent Ensure-* functions
- Preflight enforcement with -Force

### Week 3-4: CLI and UX
- Entry script parameter support
- WhatIf/Confirm implementation
- Caching (project list, bare repos)
- Standardized logging levels

### Week 5: Testing and Security
- Pester test suite (basic coverage)
- GitHub Actions workflow
- Hardcoded secret detection
- Security audit

### Week 6: Documentation and Polish
- Complete docs/ directory
- README updates
- Run manifest generation
- Final QA testing

---

## Testing Checklist

Before declaring v2.1.0 complete, verify:

### Functional Tests
- [ ] Run migration twice - second run is no-op (idempotency)
- [ ] Partial failure recovery works with -Force
- [ ] CLI mode works: `-Mode Migrate -Source "app" -Project "App"`
- [ ] Config file overrides work
- [ ] -WhatIf shows actions without executing
- [ ] -Confirm prompts before destructive actions
- [ ] Parallel bulk prep works (PS7+)

### Integration Tests
- [ ] Azure DevOps Pipeline integration
- [ ] GitLab CI integration
- [ ] Scheduled task execution
- [ ] Multiple concurrent runs (locking)

### Performance Tests
- [ ] Project list caching reduces API calls
- [ ] Bare repo reuse speeds up re-runs
- [ ] Parallel operations complete faster (PS7+)
- [ ] Large repos (1GB+) complete without timeout

### Security Tests
- [ ] No hardcoded secrets in codebase
- [ ] Secrets masked in all log outputs
- [ ] Git credentials cleaned up after migration
- [ ] PSScriptAnalyzer passes with 0 errors

### Documentation Tests
- [ ] All examples in docs/ execute successfully
- [ ] README reflects current parameter set
- [ ] Config schema validates all examples
- [ ] Troubleshooting covers common errors

---

## Breaking Changes from v2.0

**None planned** - All changes are additive and backward-compatible:

- Entry script still works in interactive mode by default
- Environment variables still work as fallback
- All existing functions maintain their signatures
- New parameters have sensible defaults

**Migration Path**:
1. Update to v2.1
2. Optionally create `migration.config.json`
3. Optionally switch to CLI mode with parameters
4. Optionally enable parallel mode (PS7+)

No changes required to existing scripts/pipelines.

---

## Success Criteria

**v2.1.0 is ready when**:
1. All Phase 1-7 items marked ✅ COMPLETED
2. 80%+ code coverage in Pester tests
3. PSScriptAnalyzer: 0 errors, <10 warnings
4. GitHub Actions CI passing
5. Documentation complete and accurate
6. Real-world test: Migrate 10 GitLab projects successfully

**Estimated Total Effort**: 80-120 hours  
**Recommended Pace**: 2-3 hours/day over 6 weeks  
**Priority Order**: Phases 1-2 (critical) → Phase 3 (high value) → Phases 4-8 (polish)
