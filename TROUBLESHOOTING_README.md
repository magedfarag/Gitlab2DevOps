# Azure DevOps Troubleshooting Script

This script diagnoses issues with Azure DevOps REST API functions in the Gitlab2DevOps toolkit.

## Quick Start

```powershell
# For Azure DevOps Cloud
.\Troubleshoot-AzureDevOps.ps1 -CollectionUrl "https://dev.azure.com/your-org" -PersonalAccessToken "your-pat-here"

# For Azure DevOps Server (on-premise)
.\Troubleshoot-AzureDevOps.ps1 -CollectionUrl "https://your-server/DefaultCollection" -PersonalAccessToken "your-pat" -SkipCertificateCheck
```

## What It Tests

1. **Environment Information** - PowerShell version, OS, paths
2. **Module Imports** - Verifies all required modules can be loaded
3. **Network Connectivity** - Tests basic TCP connection to Azure DevOps server
4. **Core.Rest Initialization** - Tests module initialization with your credentials
5. **Basic Connectivity** - Tests basic API connectivity
6. **Invoke-AdoRest Direct** - Tests core REST function with multiple endpoints
7. **Get-AdoProjectList** - Tests the specific failing function
8. **Initialize-AdoProject Minimal** - Tests project initialization (WhatIf mode)

## Common Issues & Solutions

### "You cannot call a method on a null-valued expression"

This error typically indicates the Core.Rest module wasn't properly initialized before calling Azure DevOps functions.

**Solution:**
- Ensure `Initialize-CoreRest` is called before using `Invoke-AdoRest`
- Check that CollectionUrl and PersonalAccessToken are provided
- Verify the PAT has correct permissions

### Authentication Failures

**Symptoms:** HTTP 401, 403 errors

**Solutions:**
- Verify Personal Access Token is valid and not expired
- Ensure PAT has "Read" permissions for projects
- Check token scope (should include "Project and Team" or "All scopes")

### SSL/TLS Certificate Issues

**Symptoms:** Connection forcibly closed, certificate validation errors

**Solutions:**
- Use `-SkipCertificateCheck` for on-premise servers with self-signed certificates
- For production, install proper certificates

### Network Connectivity Issues

**Symptoms:** Connection timeout, DNS resolution failures

**Solutions:**
- Verify Azure DevOps server URL is correct
- Check firewall/proxy settings
- Ensure server is accessible from your network

## Output

The script generates:
- **Console output** with real-time test results
- **JSON report** saved to `troubleshooting-report-YYYYMMDD-HHMMSS.json` with detailed diagnostics

## Example Output

```
Azure DevOps Troubleshooting Script v1.0.0
Started at: 11/11/2025 12:00:00

==========================================
TEST: Environment Information
==========================================
✅ PASS: Environment Check

==========================================
TEST: Get-AdoProjectList Function
==========================================
❌ FAIL: Get-AdoProjectList - Function failed: You cannot call a method on a null-valued expression

==========================================
TROUBLESHOOTING REPORT SUMMARY
==========================================
Test Results: 7/8 passed

Failed Tests:
  ❌ Get-AdoProjectList: Function failed: You cannot call a method on a null-valued expression
```

## Interpreting Results

- **All tests pass** ✅ - Functions should work correctly
- **Some tests fail** ⚠️ - Review specific failures and apply suggested solutions
- **Network/Basic connectivity fails** - Check server access and credentials
- **Get-AdoProjectList fails** - Usually indicates initialization or authentication issues

## Advanced Usage

### Verbose Output
```powershell
.\Troubleshoot-AzureDevOps.ps1 -CollectionUrl "https://..." -PersonalAccessToken "..." -Verbose
```

### With Certificate Skip
```powershell
.\Troubleshoot-AzureDevOps.ps1 -CollectionUrl "https://ado-server/DefaultCollection" -PersonalAccessToken "..." -SkipCertificateCheck
```

## Integration with Main Script

If troubleshooting reveals issues, you can apply fixes to your main Gitlab2DevOps.ps1 script:

```powershell
# Ensure proper initialization
Initialize-CoreRest -CollectionUrl $adoUrl -AdoPat $adoPat -SkipCertificateCheck:$skipCert

# Then use functions
$projects = Get-AdoProjectList
Initialize-AdoProject -DestProject "MyProject" -RepoName "my-repo"
```