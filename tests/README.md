# Pester Test Configuration

This directory contains automated tests for the Gitlab2DevOps migration toolkit.

## Test Structure

```
tests/
├── Core.Rest.Tests.ps1       # REST API helpers, authentication, retry logic
├── Logging.Tests.ps1          # Logging, reporting, observability
├── AzureDevOps.Tests.ps1      # Azure DevOps API functions (future)
├── GitLab.Tests.ps1           # GitLab API functions (future)
└── Integration.Tests.ps1      # End-to-end migration tests (future)
```

## Running Tests

### Run All Tests

```powershell
# Install Pester if not already installed
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester
```

### Run Specific Test File

```powershell
Invoke-Pester -Path .\tests\Core.Rest.Tests.ps1
```

### Run with Code Coverage

```powershell
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = ".\modules\*.psm1"
$config.CodeCoverage.OutputFormat = "JaCoCo"
$config.CodeCoverage.OutputPath = ".\coverage.xml"

Invoke-Pester -Configuration $config
```

### Run Tagged Tests

```powershell
# Run only unit tests (fast)
Invoke-Pester -Tag "Unit"

# Run only integration tests (slow, requires API access)
Invoke-Pester -Tag "Integration"
```

## Test Categories

### Unit Tests
- **Tag**: `Unit`
- **Speed**: Fast (< 1 second per test)
- **Dependencies**: None (uses mocks)
- **Coverage**: Individual functions, error handling, edge cases

### Integration Tests
- **Tag**: `Integration`
- **Speed**: Slow (may take minutes)
- **Dependencies**: Requires API credentials and network access
- **Coverage**: End-to-end workflows, API interactions

## Writing Tests

### Test Naming Convention

```powershell
Describe "FunctionName" {
    Context "When specific condition" {
        It "Should expected behavior" {
            # Arrange
            $input = "test"
            
            # Act
            $result = FunctionName -Input $input
            
            # Assert
            $result | Should -Be "expected"
        }
    }
}
```

### Mocking External Calls

```powershell
BeforeAll {
    # Mock REST API calls
    Mock Invoke-RestMethod {
        return @{ status = "success" }
    }
}

It "Should call API once" {
    $result = MyFunction
    Should -Invoke Invoke-RestMethod -Times 1
}
```

### Test Data

Use `$TestDrive` for temporary files:

```powershell
BeforeEach {
    $testFile = Join-Path $TestDrive "test.json"
    @{ test = $true } | ConvertTo-Json | Out-File $testFile
}
```

## Coverage Goals

| Module | Target Coverage | Current Coverage |
|--------|----------------|------------------|
| Core.Rest | 80% | ✅ 75% |
| Logging | 70% | ✅ 70% |
| AzureDevOps | 60% | 🔴 0% |
| GitLab | 60% | 🔴 0% |
| Migration | 50% | 🔴 0% |
| **Overall** | **60%** | **🟡 30%** |

## CI Integration

Tests run automatically on:
- Pull requests (all tests)
- Main branch push (all tests + coverage)
- Manual workflow dispatch

See `.github/workflows/ci.yml` for CI configuration.

## Troubleshooting

### "Module not found"
Ensure you're running tests from the repository root:
```powershell
cd C:\Projects\devops\Gitlab2DevOps
Invoke-Pester
```

### "Pester version mismatch"
Ensure Pester 5.x is installed:
```powershell
Get-Module Pester -ListAvailable
# If version < 5.0, update:
Install-Module Pester -Force -SkipPublisherCheck
```

### "Tests fail with API errors"
Integration tests require valid credentials. Either:
1. Set environment variables for test credentials
2. Run only unit tests: `Invoke-Pester -Tag "Unit"`

## Contributing

When adding new features:
1. Write tests first (TDD approach)
2. Aim for 60%+ coverage on new code
3. Add both unit and integration tests
4. Update this README if adding new test files

---

Last updated: November 4, 2025
