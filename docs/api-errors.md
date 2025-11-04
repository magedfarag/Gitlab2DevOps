# API Error Catalog

Comprehensive reference for GitLab and Azure DevOps API errors encountered during migration.

## Table of Contents
- [GitLab API Errors](#gitlab-api-errors)
- [Azure DevOps API Errors](#azure-devops-api-errors)
- [Git Operation Errors](#git-operation-errors)
- [Network and Authentication Errors](#network-and-authentication-errors)
- [Troubleshooting Guide](#troubleshooting-guide)

---

## GitLab API Errors

### 401 Unauthorized
**Cause**: Invalid or expired GitLab Personal Access Token (PAT).

**Error Message**:
```
401 Unauthorized
```

**Resolution**:
1. Verify token in GitLab Settings → Access Tokens
2. Ensure token has `api` scope
3. Check token expiration date
4. Generate new token if expired
5. Update `migration.config.json` with new token

**Prevention**:
- Use tokens with longer expiration periods
- Set calendar reminders before token expiry
- Document token rotation procedures

---

### 403 Forbidden
**Cause**: Token lacks required permissions or project access.

**Error Message**:
```
403 Forbidden - {"message":"403 Forbidden"}
```

**Resolution**:
1. Verify project visibility (Private/Internal/Public)
2. Check user membership in project
3. Confirm token has required scopes:
   - `api` - Full API access
   - `read_repository` - Read repository data
   - `read_api` - Read-only API access
4. For private projects, ensure user is added as member (Developer+ role)

**Prevention**:
- Use tokens with `api` scope for migrations
- Audit project memberships before migration
- Test token access with preflight checks

---

### 404 Not Found
**Cause**: Project path incorrect or project does not exist.

**Error Message**:
```
404 Project Not Found - {"message":"404 Project Not Found"}
```

**Resolution**:
1. Verify project path format: `group/subgroup/project`
2. Check for typos in project name
3. Confirm project hasn't been renamed or moved
4. Use GitLab web UI to verify exact path
5. URL-encode special characters (e.g., spaces → `%20`)

**Prevention**:
- Copy project paths directly from GitLab UI
- Use `Test-GitLabAuth` to list accessible projects
- Run preflight validation before migration

---

### 429 Rate Limited
**Cause**: Too many API requests within time window.

**Error Message**:
```
429 Too Many Requests - {"message":"429 Too Many Requests"}
```

**Resolution**:
1. Wait for rate limit window to reset (typically 1 minute)
2. Reduce concurrent API calls
3. Implement exponential backoff (already built into Core.Rest module)
4. For bulk migrations, add delays between projects

**GitLab Rate Limits**:
- **Free tier**: 300 requests per minute per user
- **Premium**: 600 requests per minute per user
- **Ultimate**: 1000+ requests per minute per user

**Prevention**:
- Use caching for project lists (15-minute cache)
- Batch operations when possible
- Schedule bulk migrations during off-peak hours

---

### 500 Internal Server Error
**Cause**: GitLab server error or temporary outage.

**Error Message**:
```
500 Internal Server Error
```

**Resolution**:
1. Check GitLab status page: https://status.gitlab.com
2. Wait and retry after 5-10 minutes
3. Contact GitLab support if persistent
4. Use `-Force` flag to skip validation (with caution)

**Prevention**:
- Monitor GitLab status before large migrations
- Implement retry logic with exponential backoff (built-in)
- Schedule migrations during GitLab maintenance windows

---

## Azure DevOps API Errors

### 401 Unauthorized
**Cause**: Invalid or expired Azure DevOps PAT.

**Error Message**:
```
401 Unauthorized - TF400813: The user is not authorized to access this resource.
```

**Resolution**:
1. Verify PAT in Azure DevOps → User Settings → Personal Access Tokens
2. Ensure PAT has required scopes:
   - **Code**: Read & write
   - **Project and Team**: Read, write, & manage
   - **Wiki**: Read & write
3. Check PAT expiration date
4. Regenerate PAT if expired
5. Update `migration.config.json` with new PAT

**Prevention**:
- Use PATs with full access for migrations
- Set maximum expiration (1 year)
- Use Azure Key Vault for PAT storage in production

---

### 403 Forbidden
**Cause**: PAT lacks permissions or user lacks project access.

**Error Message**:
```
403 Forbidden - TF401019: The Git repository with name or identifier X does not exist or you do not have permissions for the operation you are attempting.
```

**Resolution**:
1. Verify user is Project Administrator or Project Contributor
2. Check PAT scopes (must include Code, Project, Wiki)
3. For organization-level operations, verify Collection Administrator role
4. Ensure project exists before repository operations

**Prevention**:
- Use PATs from accounts with Project Administrator role
- Run `Ensure-AdoProject` before repository operations
- Test PAT permissions with small test project

---

### 409 Conflict
**Cause**: Resource already exists (project, repository, branch policy).

**Error Message**:
```
409 Conflict - TF400948: A project with the name 'X' already exists.
```

**Common Scenarios**:
1. **Project already exists**: Use `-Force` with `Ensure-AdoProject`
2. **Repository already exists**: Use `-AllowSync` with `Invoke-SingleMigration`
3. **Branch policy already exists**: Policy update (not create)

**Resolution**:
1. Check if resource exists before creation
2. Use idempotent functions (Ensure-* pattern)
3. Use `-Replace` flag to overwrite existing resources
4. For migrations, use `-AllowSync` to update existing repos

**Prevention**:
- Always run preflight checks before migration
- Use `Ensure-*` functions (idempotent by design)
- Check resource existence in scripts

---

### 404 Not Found
**Cause**: Project, repository, or resource does not exist.

**Error Message**:
```
404 Not Found - TF400813: Resource not found.
```

**Resolution**:
1. Verify project name spelling and casing
2. Ensure project was created successfully
3. Wait 2-3 seconds after project creation for API consistency
4. Check organization URL is correct
5. Verify repository ID format: `{projectId}/{repoId}`

**Prevention**:
- Use `Ensure-AdoProject` before repository operations
- Store project IDs from creation responses
- Add delays after async operations

---

### 429 Rate Limited
**Cause**: Too many API requests within time window.

**Error Message**:
```
429 Too Many Requests - TF20503: The request has been throttled. Please wait and retry.
```

**Resolution**:
1. Wait for rate limit reset (typically 5 seconds)
2. Exponential backoff is automatic in Core.Rest module
3. Reduce parallel operations
4. Contact Microsoft for rate limit increase

**Azure DevOps Rate Limits**:
- **Default**: 200 requests per minute per user per organization
- **Throttling**: Gradual slowdown before hard limit
- **Retry-After header**: Indicates wait time

**Prevention**:
- Use project list caching (15-minute TTL)
- Batch operations when possible
- Monitor rate limit headers in responses

---

### 500 Internal Server Error
**Cause**: Azure DevOps service error.

**Error Message**:
```
500 Internal Server Error - TF53010: The following error has occurred in a Team Foundation component or extension.
```

**Resolution**:
1. Check Azure DevOps status: https://status.dev.azure.com
2. Wait and retry after 5-10 minutes
3. Check service health notifications
4. Contact Microsoft support if persistent

**Prevention**:
- Monitor Azure DevOps status before migrations
- Implement retry logic (built-in)
- Schedule migrations during low-traffic hours

---

## Git Operation Errors

### Authentication Failed
**Cause**: Git credentials expired or invalid during clone/push.

**Error Message**:
```
fatal: Authentication failed for 'https://...'
```

**Resolution**:
1. Verify GitLab token is current
2. Verify Azure DevOps PAT is current
3. Check token format in URL: `https://oauth2:TOKEN@gitlab.com/...`
4. For Azure DevOps: `https://:PAT@dev.azure.com/...`
5. Clear Git credential cache: `git credential-cache exit`

**Prevention**:
- Validate tokens before git operations
- Use credential helpers for secure storage
- Clear credentials after operations (built-in cleanup)

---

### Large Repository Timeout
**Cause**: Repository clone exceeds timeout threshold.

**Error Message**:
```
fatal: the remote end hung up unexpectedly
fatal: early EOF
```

**Resolution**:
1. Increase Git timeout: `git config --global http.postBuffer 524288000`
2. Use `--depth 1` for shallow clone (testing only)
3. Clone during low-traffic hours
4. Check network connectivity
5. Use local network if possible

**Large Repository Thresholds**:
- **Warning**: > 100 MB
- **Large**: > 500 MB
- **Very Large**: > 1 GB (requires special handling)

**Prevention**:
- Review repository size in preflight report
- Schedule large clones during off-peak hours
- Consider repository cleanup before migration

---

### LFS Objects Missing
**Cause**: Git LFS not installed or LFS objects not downloaded.

**Error Message**:
```
Error downloading object: ... : Smudge error
```

**Resolution**:
1. Install Git LFS: `git lfs install`
2. Verify LFS is enabled: `git lfs version`
3. Pull LFS objects: `git lfs pull`
4. Check GitLab LFS storage quota
5. Verify token has LFS access

**Prevention**:
- Check `lfs_enabled` in preflight report
- Install Git LFS before migrations
- Verify LFS quota before migration

---

### Ref Update Failed
**Cause**: Branch protection or push restrictions in destination.

**Error Message**:
```
error: failed to push some refs to '...'
```

**Resolution**:
1. Check branch policies on destination
2. Temporarily disable branch policies during migration
3. Use force push for mirror migrations: `git push --mirror --force`
4. Verify PAT has force push permissions
5. Check repository lock status

**Prevention**:
- Apply branch policies AFTER migration
- Use `Ensure-AdoBranchPolicies` post-migration
- Document policy requirements in advance

---

## Network and Authentication Errors

### SSL Certificate Verification Failed
**Cause**: Self-signed certificate or certificate trust issue.

**Error Message**:
```
SSL certificate problem: unable to get local issuer certificate
```

**Resolution**:
1. Install certificate in Windows certificate store
2. Temporarily disable SSL verification (not recommended):
   ```powershell
   $env:GIT_SSL_NO_VERIFY = "true"
   ```
3. Configure Git to use specific CA bundle:
   ```bash
   git config --global http.sslCAInfo C:\path\to\ca-bundle.crt
   ```

**Prevention**:
- Use trusted CA certificates in production
- Configure certificate trust before migration
- Document certificate requirements

---

### Connection Timeout
**Cause**: Network latency or firewall blocking connection.

**Error Message**:
```
Failed to connect to ... port 443: Connection timed out
```

**Resolution**:
1. Check network connectivity: `Test-NetConnection dev.azure.com -Port 443`
2. Verify firewall rules allow HTTPS (443)
3. Check proxy settings if behind corporate proxy
4. Try from different network (VPN, etc.)
5. Contact network administrator

**Prevention**:
- Test connectivity before bulk migrations
- Configure firewall rules in advance
- Document network requirements

---

### Proxy Authentication Required
**Cause**: Corporate proxy requires authentication.

**Error Message**:
```
407 Proxy Authentication Required
```

**Resolution**:
1. Configure Git proxy:
   ```bash
   git config --global http.proxy http://proxy.company.com:8080
   git config --global http.proxyAuthMethod basic
   ```
2. Set environment variables:
   ```powershell
   $env:HTTP_PROXY = "http://user:pass@proxy:8080"
   $env:HTTPS_PROXY = "http://user:pass@proxy:8080"
   ```
3. Use integrated Windows authentication if supported

**Prevention**:
- Configure proxy settings before migration
- Test proxy connectivity
- Document proxy requirements

---

## Troubleshooting Guide

### Diagnostic Steps

#### 1. Verify API Access
```powershell
# Test GitLab
Test-GitLabAuth

# Test Azure DevOps (manual check)
$headers = @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("":$AdoPat)))" }
Invoke-RestMethod -Uri "https://dev.azure.com/{org}/_apis/projects?api-version=7.0" -Headers $headers
```

#### 2. Check Configuration
```powershell
# Verify config file
$config = Get-Content migration.config.json | ConvertFrom-Json
$config | Format-List

# Test URLs
Test-NetConnection dev.azure.com -Port 443
Test-NetConnection gitlab.com -Port 443
```

#### 3. Run Preflight Validation
```powershell
# Single project
Prepare-GitLab "group/project"

# Check reports
Get-Content migrations/project/reports/preflight-report.json | ConvertFrom-Json | Format-List
```

#### 4. Enable Verbose Logging
```powershell
# Enable verbose output
$VerbosePreference = "Continue"

# Run migration with verbose logging
Invoke-SingleMigration -SrcPath "group/project" -DestProject "MyProject" -Verbose
```

#### 5. Check Logs
```powershell
# View migration log
Get-Content migrations/project/logs/migration-*.log

# View preparation log
Get-Content migrations/project/logs/preparation-*.log
```

### Common Solutions

#### Token Expired
1. Generate new token
2. Update `migration.config.json`
3. Restart PowerShell session
4. Re-run migration

#### Project Not Found
1. Verify exact project path in GitLab UI
2. Check for typos
3. Use `Test-GitLabAuth` to list projects
4. Confirm user has access

#### Rate Limited
1. Wait 1-5 minutes
2. Reduce concurrent operations
3. Enable caching: `Get-AdoProjectList -UseCache`
4. Schedule migrations during off-peak hours

#### Large Repository Fails
1. Check size in preflight report
2. Increase timeout: `git config --global http.timeout 300`
3. Use wired connection instead of WiFi
4. Clone during off-peak hours

### Emergency Procedures

#### Migration Failed Mid-Process
1. Check logs for specific error
2. Verify destination repository state
3. Use `-AllowSync` to resume/retry
4. Manual rollback if needed:
   ```powershell
   # Delete repository in Azure DevOps UI
   # Re-run migration with -Force
   Invoke-SingleMigration -SrcPath "..." -DestProject "..." -Force
   ```

#### Bulk Migration Failures
1. Review `bulk-migration-results-*.json`
2. Identify failed projects
3. Fix issues (tokens, permissions, etc.)
4. Re-run failed projects individually
5. Update template with corrections

---

## Support Resources

### GitLab
- API Documentation: https://docs.gitlab.com/ee/api/
- Status Page: https://status.gitlab.com
- Support: https://about.gitlab.com/support/

### Azure DevOps
- API Documentation: https://learn.microsoft.com/en-us/rest/api/azure/devops/
- Status Page: https://status.dev.azure.com
- Support: https://azure.microsoft.com/en-us/support/devops/

### Git
- Documentation: https://git-scm.com/doc
- LFS: https://git-lfs.github.com/

---

## Contributing

Found a new error? Please contribute to this catalog:
1. Document error message
2. Explain cause
3. Provide resolution steps
4. Add prevention tips
5. Submit PR with updates

---

**Last Updated**: 2024-11-04  
**Version**: 2.0.0
