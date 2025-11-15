<#
.SYNOPSIS
    GitLab project analysis and preparation functions.

.DESCRIPTION
    This module handles all GitLab-specific operations including project fetching,
    repository download, and preflight report generation. It has no knowledge of
    Azure DevOps and focuses solely on source data preparation.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Ensure Core.Rest & Logging functions are available (explicit import avoids session coupling)
$coreDir = Split-Path $PSScriptRoot -Parent
$corePath = Join-Path $coreDir 'core\Core.Rest.psm1'
$loggingPath = Join-Path $coreDir 'core\Logging.psm1'
foreach ($dep in @($corePath, $loggingPath)) {
    try {
        if (Test-Path $dep) {
            Import-Module -WarningAction SilentlyContinue $dep -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Verbose "[GitLab] Could not import dependency '$dep': $_"
    }
}

# Initialize GitLab-specific script variables
try {
    $script:PlainToken = Get-GitLabToken
} catch {
    Write-Verbose "[GitLab] GitLab token not available yet: $_"
}

<#
.SYNOPSIS
    Retrieves GitLab project information with statistics.

.DESCRIPTION
    Fetches detailed project metadata from GitLab including repository size,
    LFS status, and configuration. Provides helpful error messages for common issues.

.PARAMETER PathWithNamespace
    Full project path (e.g., "group/subgroup/project").

.OUTPUTS
    GitLab project object with statistics.

.EXAMPLE
    Get-GitLabProject "my-group/my-project"
#>
function Get-GitLabProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PathWithNamespace
    )
    
    $enc = [uri]::EscapeDataString($PathWithNamespace)  # encodes '/' to %2F as required
    $fullPath = "/api/v4/projects/$enc" + "?statistics=true"
    
    try {
        $resp = Invoke-GitLabRest -Method GET -Endpoint $fullPath
    }
    catch {
        Write-Host "[ERROR] Failed to fetch GitLab project '$PathWithNamespace'." -ForegroundColor Red
        Write-Host "        Suggestions:" -ForegroundColor Yellow
        Write-Host "          - Verify the project path is correct (group/subgroup/project)." -ForegroundColor Yellow
        Write-Host "          - Ensure the GitLab token has 'api' scope and can access the project." -ForegroundColor Yellow
        Write-Host "          - If the project is private, confirm the token user is a member or has access." -ForegroundColor Yellow
        throw "[ERROR] Failed to fetch GitLab project '$PathWithNamespace'."
    }

    # Validate response shape
    if ($null -eq $resp) {
        Write-Host "[ERROR] GitLab returned an empty response for '$PathWithNamespace'." -ForegroundColor Red
        Write-Host "        Ensure the token has access and the project exists." -ForegroundColor Yellow
        throw "Empty response from GitLab for $PathWithNamespace"
    }

    # Check if response indicates an error
    if ($resp.Data -and ($resp.Data | Get-Member -Name 'message' -MemberType Properties -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] GitLab API error for '$PathWithNamespace': $($resp.Data.message)" -ForegroundColor Red
        Write-Host "        Verify the project path is correct and the token has access." -ForegroundColor Yellow
        throw "GitLab API error: $($resp.Data.message)"
    }

    # If a raw string was returned, attempt to parse JSON for more useful diagnostics
    if ($resp -is [string]) {
        $maybe = $null
        try { $maybe = $resp | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $maybe = $null }
        if ($maybe) { $resp = $maybe }
        else {
            # Non-JSON successful response (unexpected)
            Write-Host "[ERROR] GitLab returned non-JSON response for '$PathWithNamespace'." -ForegroundColor Red
            Write-Host "        Response (truncated): $($resp.ToString().Substring(0, [Math]::Min(400, $resp.ToString().Length)))" -ForegroundColor DarkYellow
            throw "Non-JSON response from GitLab for $PathWithNamespace"
        }
    }

    # Ensure we have an object with expected properties
    if (-not ($resp.Data | Get-Member -Name 'id' -MemberType Properties -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] Unexpected GitLab response shape for '$PathWithNamespace'. Missing 'id' property." -ForegroundColor Red
        Write-Host "        Response object type: $($resp.Data.GetType().FullName)" -ForegroundColor Yellow
        if ($resp.Data) {
            Write-Host "        Response properties: $($resp.Data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name -Join ', ')" -ForegroundColor Yellow
        }
        throw "Unexpected response shape from GitLab for $PathWithNamespace"
    }

    return $resp.Data
}


function Invoke-GitLabRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method,
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [hashtable]$Query = @{},
        [int]$MaxRetries = 3
    )

    # Ensure token is available
    if (-not $script:PlainToken) {
        Write-Verbose "[Invoke-GitLabRest] Fetching GitLab token..."
        $script:PlainToken = Get-GitLabToken
    }

    $gitLabBaseUrl = Get-GitLabBaseUrl
    $gitLabApiVersion = Get-GitLabApiVersion
    Write-Verbose "[Invoke-GitLabRest] Base URL: $gitLabBaseUrl"
    Write-Verbose "[Invoke-GitLabRest] API Version: $gitLabApiVersion"
    Write-Verbose "[Invoke-GitLabRest] Endpoint: $Endpoint"
    $uriBuilder = New-Object System.UriBuilder("$gitLabBaseUrl$Endpoint")
    if ($Query -and $Query -is [hashtable] -and $Query.Count -gt 0) {
        Write-Verbose "[Invoke-GitLabRest] Building query string..."
        $nv = New-Object System.Collections.Specialized.NameValueCollection
        foreach ($k in $Query.Keys) {
            $v = if ($null -ne $Query[$k]) { [string]$Query[$k] } else { '' }
            $nv.Add([string]$k, $v)
            Write-Verbose "[Invoke-GitLabRest] Query param: $k = $v"
        }
        $qs = [System.Web.HttpUtility]::ParseQueryString('')
        $qs.Add($nv)
        $uriBuilder.Query = $qs.ToString()
    }
    $uri = $uriBuilder.Uri.AbsoluteUri
    Write-Verbose "[Invoke-GitLabRest] Final URI: $uri"

    $headers = @{
        'Private-Token' = $script:PlainToken
        'Accept'        = 'application/json'
    }
    Write-Verbose "[Invoke-GitLabRest] Headers: $(($headers | Out-String).Trim())"

    $attempt = 0
    $delay = 1
    Write-Log "[GitLabRest] Starting $Method $uri" 'DEBUG'
    Write-Verbose "[Invoke-GitLabRest] Starting $Method $uri"
    while ($true) {
        try {
            Write-Log "[GitLabRest] Attempt $($attempt+1): $Method $uri" 'DEBUG'
            Write-Verbose "[Invoke-GitLabRest] Attempt $($attempt+1): $Method $uri"
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -UseBasicParsing
            Write-Log "[GitLabRest] Response status: $($resp.StatusCode)" 'DEBUG'
            Write-Verbose "[Invoke-GitLabRest] Response status: $($resp.StatusCode)"
            $raw = $resp.Content
            $data = if ($raw) { $raw | ConvertFrom-Json } else { $null }
            Write-Log "[GitLabRest] Success: $Method $uri" 'INFO'
            Write-Verbose "[Invoke-GitLabRest] Success: $Method $uri"
            return [pscustomobject]@{
                Data    = $data
                Headers = $resp.Headers
                Status  = $resp.StatusCode
                Uri     = $uri
            }
        }
        catch {
            $attempt++
            $webEx = $_.Exception
            $statusCode = $null
            $errorBody = $null

            Write-Log "[GitLabRest] Exception on $Method $($uri): $($_.Exception.Message)" 'ERROR'
            Write-Verbose "[Invoke-GitLabRest] Exception: $($_.Exception.Message)"

            if ($webEx.Response -and $webEx.Response.StatusCode) {
                $statusCode = [int]$webEx.Response.StatusCode
                Write-Verbose "[Invoke-GitLabRest] HTTP Status: $statusCode"
                try {
                    $stream = $webEx.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                    Write-Log "[GitLabRest] Error body: $errorBody" 'DEBUG'
                    Write-Verbose "[Invoke-GitLabRest] Error body: $errorBody"
                }
                catch {
                    Write-Verbose "checking error Message at line 190"
                    $errorBody = $_.ErrorDetails.Message
                    Write-Log "[GitLabRest] Error details fallback: $errorBody" 'DEBUG'
                    Write-Verbose "[Invoke-GitLabRest] Error details fallback: $errorBody"
                }
            }

            if (-not $errorBody) {
                Write-Verbose "checking error Message at line 196"
                $errorBody = $_.ErrorDetails.Message ?? $_.Exception.Message
                Write-Log "[GitLabRest] No error body, using message: $errorBody" 'DEBUG'
                Write-Verbose "[Invoke-GitLabRest] No error body, using message: $errorBody"
            }

            if ($statusCode -eq 429 -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try { $retryAfter = [int]$webEx.Response.Headers['Retry-After'] } catch {}
                if ($retryAfter -lt 1) { $retryAfter = $delay }
                Write-Log "429 Too Many Requests on $uri. Retrying in $retryAfter sec... (attempt $attempt/$MaxRetries)" 'WARN'
                Write-Verbose "[Invoke-GitLabRest] 429 Too Many Requests. Retrying in $retryAfter sec... (attempt $attempt/$MaxRetries)"
                Start-Sleep -Seconds $retryAfter
                $delay = [Math]::Min($delay * 2, 30)
                continue
            }

            if ($statusCode -in 401,403) {
                $logMsg = "Access denied ($statusCode) calling $uri"
                if ($errorBody) { $logMsg += " - $errorBody" }
                Write-Log $logMsg 'ERROR'
                Write-Verbose "[Invoke-GitLabRest] Access denied ($statusCode): $errorBody"
                return [pscustomobject]@{ Data = $null; Headers = $null; Status = $statusCode; Uri = $uri }
            }

            if ($errorBody) {
                Write-Log "[GitLabRest] HTTP $statusCode on $($uri): $errorBody" 'ERROR'
                Write-Verbose "[Invoke-GitLabRest] HTTP $statusCode on $($uri): $errorBody"
                throw "HTTP $statusCode on $($uri): $errorBody"
            }
            Write-Log "[GitLabRest] Unknown error on $Method $($uri): $($_.Exception.Message)" 'ERROR'
            Write-Verbose "[Invoke-GitLabRest] Unknown error on $Method $($uri): $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Tests GitLab authentication and lists accessible projects.

.DESCRIPTION
    Validates that the GitLab base URL and token can successfully authenticate
    and retrieve projects. Useful for troubleshooting connectivity issues.

.EXAMPLE
    Test-GitLabAuth
#>
function Test-GitLabAuth {
    [CmdletBinding()]
    param()
    
    try {
        $uri = "/api/v4/projects?membership=true&per_page=5"
        $res = Invoke-GitLabRest -Method GET -Endpoint $uri
        
        Write-Host "[OK] GitLab auth successful. Returned $(($res | Measure-Object).Count) project(s)." -ForegroundColor Green
        $res | Select-Object -Property id, path_with_namespace, visibility | Format-Table -AutoSize
    }
    catch {
        Write-Host "[ERROR] GitLab authentication test failed." -ForegroundColor Red
        throw
    }
}

<#
.SYNOPSIS
    Downloads and prepares a GitLab project for migration.

.DESCRIPTION
    Creates project folder structure, downloads repository as mirror clone,
    and generates detailed preflight report with size, LFS status, and metadata.

.PARAMETER SrcPath
    GitLab project path (e.g., "group/project").

.EXAMPLE
    Initialize-GitLab "my-group/my-project"
#>
function Initialize-GitLab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [Alias('SrcPath')]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$CustomBaseDir,
        
        [Parameter()]
        [string]$CustomProjectName
    )
    
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $errorMsg = New-ActionableError -ErrorType 'GitNotFound' -Details @{}
        throw $errorMsg
    }
    
    $p = Get-GitLabProject $ProjectPath
    
    # Create project metadata report (use defensive accessors in case GitLab returned partial data)
    $projPath = if ($p -and $p.path_with_namespace) { $p.path_with_namespace } else { $ProjectPath }
    $httpUrl = if ($p -and $p.http_url_to_repo) { $p.http_url_to_repo } else { '' }
    $defaultBranch = if ($p -and $p.default_branch) { $p.default_branch } else { '' }
    $visibility = if ($p -and $p.visibility) { $p.visibility } else { 'private' }
    $lfsEnabled = if ($p -and ($p.PSObject.Properties.Name -contains 'lfs_enabled')) { $p.lfs_enabled } else { $false }

    $repoSizeBytes = 0
    $lfsSizeBytes = 0
    if ($p -and ($p.PSObject.Properties.Name -contains 'statistics') -and $p.statistics) {
        try {
            if ($p.statistics.repository_size) { $repoSizeBytes = [int64]$p.statistics.repository_size }
        } catch { $repoSizeBytes = 0 }
        try {
            if ($p.statistics.lfs_objects_size) { $lfsSizeBytes = [int64]$p.statistics.lfs_objects_size }
        } catch { $lfsSizeBytes = 0 }
    }

    $repoSizeMB = [math]::Round(($repoSizeBytes / 1MB), 2)
    $lfsSizeMB = [math]::Round(($lfsSizeBytes / 1MB), 2)

    $openIssues = if ($p -and $p.PSObject.Properties.Name -contains 'open_issues_count') { $p.open_issues_count } else { 0 }
    $lastActivity = if ($p -and $p.PSObject.Properties.Name -contains 'last_activity_at') { $p.last_activity_at } else { '' }

    $report = [pscustomobject]@{
        project            = $projPath
        http_url_to_repo   = $httpUrl
        default_branch     = $defaultBranch
        visibility         = $visibility
        lfs_enabled        = $lfsEnabled
        repo_size_MB       = $repoSizeMB
        lfs_size_MB        = $lfsSizeMB
        open_issues        = $openIssues
        last_activity      = $lastActivity
        preparation_time   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    
    # Determine folder structure
    $projectName = if ($CustomProjectName) { $CustomProjectName } else { $p.path }
    
    if (-not $CustomBaseDir) {
        throw "[Initialize-GitLab] CustomBaseDir is required. This function only supports v2.1.0 self-contained structure."
    }
    
    # v2.1.0 self-contained mode: CustomBaseDir is ADO container, CustomProjectName is GitLab subfolder
    # Structure: CustomBaseDir/{CustomProjectName}/reports/ and repository/
    # Logs are at ADO container level: CustomBaseDir/logs/
    $projectDir = Join-Path $CustomBaseDir $projectName
    $reportsDir = Join-Path $projectDir "reports"
    $logsDir = Join-Path $CustomBaseDir "logs"  # Container-level logs
    $repoDir = Join-Path $projectDir "repository"
    
    if (-not (Test-Path $projectDir)) {
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        Write-Host "[INFO] Created GitLab project directory: $projectDir"
    }
    
    # Create subdirectories for organization
    # In v2.1.0, create both logs/ at container level and reports/ in GitLab subfolder
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }
    
    # Save preflight report in project-specific reports folder
    $reportFile = Join-Path $reportsDir "preflight-report.json"
    $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
    Write-Host "[OK] Preflight report written: $reportFile"
    
    # Get GitLab token from Core.Rest module (now parameterless, .env-driven)
    try {
        $gitLabToken = Get-GitLabToken
    }
    catch {
        # Token error already has actionable message from Core.Rest
        throw
    }

    # Download repository for migration preparation
    $gitUrl = $p.http_url_to_repo -replace '^https://', "https://oauth2:$gitLabToken@"
    
    if (Test-Path $repoDir) {
        Write-Host "[INFO] Repository directory exists, checking status..."

        # Ensure variable is initialized to avoid unbound variable access later
        $needsClone = $false

        # Check if it's a valid git repository
        $isValidRepo = $false
        Push-Location $repoDir
        try {
            $null = git rev-parse --git-dir 2>$null
            $isValidRepo = $?
        }
        catch {
            $isValidRepo = $false
        }
        Pop-Location
        
        if ($isValidRepo) {
            Write-Host "[INFO] Valid repository found, updating..."
            Push-Location $repoDir
            try {
                # Fetch latest changes
                git remote set-url origin $gitUrl 2>$null
                # Respect invalid certificate setting for on-prem GitLab
                $skipCert = $false
                try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
                if ($skipCert) {
                    git -c http.sslVerify=false fetch --all --prune
                }
                else {
                    git fetch --all --prune
                }
                $fetchSuccess = $?
                
                if ($fetchSuccess) {
                    Write-Host "[SUCCESS] Repository updated successfully (reused existing clone)" -ForegroundColor Green
                }
                else {
                    throw "git fetch failed"
                }
            }
            catch {
                Write-Host "[WARN] Failed to update existing repository: $_"
                Write-Host "[INFO] Will re-clone repository..."
                Pop-Location
                Remove-Item -Recurse -Force $repoDir
                $needsClone = $true
            }
            if (-not $needsClone) { Pop-Location }
        }
        else {
            Write-Host "[WARN] Directory exists but is not a valid git repository, removing..."
            Remove-Item -Recurse -Force $repoDir
        }
    }
    
    if (-not (Test-Path $repoDir)) {
        Write-Host "[INFO] Downloading repository (mirror clone)..."
        Write-Host "       Size: $($report.repo_size_MB) MB"
        if ($report.lfs_enabled -and $report.lfs_size_MB -gt 0) {
            Write-Host "       LFS data: $($report.lfs_size_MB) MB"
            if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
                Write-Host "[WARN] Git LFS not found but repository uses LFS. Install git-lfs for complete migration." -ForegroundColor Yellow
            }
        }
        
        try {
            # Respect invalid certificate setting for on-prem GitLab
            $skipCert = $false
            try { $skipCert = (Get-SkipCertificateCheck) } catch { $skipCert = $false }
            if ($skipCert) {
                git -c http.sslVerify=false clone --mirror $gitUrl $repoDir
            }
            else {
                git clone --mirror $gitUrl $repoDir
            }
            Write-Host "[OK] Repository downloaded to: $repoDir"
            
            # Update report with local repository info
            $report | Add-Member -NotePropertyName "local_repo_path" -NotePropertyValue $repoDir
            $report | Add-Member -NotePropertyName "download_time" -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
        }
        catch {
            Write-Host "[ERROR] Failed to download repository: $_" -ForegroundColor Red
            Write-Host "[INFO] Migration can still proceed but will require fresh download in Option 3"
        }
    }
    
    # Capture preparation start time
    $prepStartTime = Get-Date
    
    # Validate Git access (quick check) BEFORE creating log
    Write-Host "[INFO] Validating Git access..."
    $gitValidationResult = "SUCCESS"
    $gitValidationError = $null
    try {
        $skipCert = (Get-SkipCertificateCheck) -or $false
        if ($skipCert) {
            git -c http.sslVerify=false ls-remote $gitUrl HEAD | Out-Null
        } else {
            git ls-remote $gitUrl HEAD | Out-Null
        }
        Write-Host "[OK] Git access validated."
    } catch {
        $gitValidationResult = "FAILED"
        $gitValidationError = $_.ToString()
        Write-Warning "[WARN] Git access validation failed: $_"
        Write-Warning "[INFO] Migration can still proceed but may require fresh download in Option 3"
    }
    
    # Get environment info
    $psVersion = $PSVersionTable.PSVersion.ToString()
    $gitVersion = try { (git --version).Split(' ')[-1] } catch { "Unknown" }
    
    # Calculate preparation duration
    $prepEndTime = Get-Date
    $prepDuration = $prepEndTime - $prepStartTime
    
    # Check LFS details
    $lfsObjectsCount = 0
    $lfsWarning = $null
    if ($report.lfs_enabled -and (Test-Path $repoDir)) {
        try {
            Push-Location $repoDir
            $lfsObjects = git lfs ls-files 2>$null
            $lfsObjectsCount = if ($lfsObjects) { ($lfsObjects | Measure-Object).Count } else { 0 }
            if ($report.lfs_size_MB -eq 0 -and $lfsObjectsCount -gt 0) {
                $lfsWarning = "WARNING: LFS enabled with objects but reported size is 0 MB - possible analysis issue"
            } elseif ($report.lfs_enabled -and $lfsObjectsCount -eq 0) {
                $lfsWarning = "NOTE: LFS enabled but no LFS objects found in repository"
            }
        } catch {
            $lfsObjectsCount = -1  # Error checking
            $lfsWarning = "WARNING: Could not check LFS objects: $_"
        } finally {
            Pop-Location
        }
    }
    
    # Get file sizes
    $reportSize = if (Test-Path $reportFile) { [math]::Round((Get-Item $reportFile).Length / 1KB, 2) } else { 0 }
    $logSize = 0  # Will be calculated after writing
    
    # Create preparation log with enhanced details
    $prepLogFile = Join-Path $logsDir "preparation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $logContent = @(
        "=== GitLab Project Preparation Log ==="
        "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Preparation Start: $($prepStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        "Preparation End: $($prepEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        "Duration: $($prepDuration.ToString('hh\:mm\:ss')) ($([math]::Round($prepDuration.TotalSeconds, 1)) seconds)"
        ""
        "Environment:"
        "- PowerShell Version: $psVersion"
        "- Git Version: $gitVersion"
        "- Operating System: $([Environment]::OSVersion.VersionString)"
        ""
        "Project Details:"
        "- Project: $($p.path_with_namespace)"
        "- GitLab URL: $($p.http_url_to_repo)"
        "- Project Directory: $projectDir"
        "- Repository Size: $($report.repo_size_MB) MB"
        "- LFS Enabled: $($report.lfs_enabled)"
        "- LFS Size: $($report.lfs_size_MB) MB"
        "- LFS Objects Count: $(if ($lfsObjectsCount -eq -1) { 'Error checking' } elseif ($lfsObjectsCount -eq 0) { 'No LFS objects found' } else { $lfsObjectsCount })"
        if ($lfsWarning) { "- LFS Note: $lfsWarning" }
        "- Default Branch: $($report.default_branch)"
        "- Visibility: $($report.visibility)"
        "- Last Activity: $($report.last_activity.ToString('yyyy-MM-dd HH:mm:ss'))"
        ""
        "Validation Results:"
        "- Git Access: $gitValidationResult"
    )
    
    if ($gitValidationResult -eq "FAILED") {
        $logContent += "- Git Error: $gitValidationError"
    }
    
    $logContent += @(
        ""
        "Files Created:"
        "- Report: $reportFile ($reportSize KB)"
        if (Test-Path $repoDir) { "- Repository: $repoDir" }
        "- Log: $prepLogFile"
        ""
        "Preparation Steps Performed:"
        "1. Retrieved project metadata from GitLab API"
        "2. Downloaded repository mirror (bare clone)"
        "3. Analyzed repository structure and size"
        "4. Generated preflight report with statistics"
        "5. Validated Git access to source repository"
        "6. Created preparation log"
    )
    
    # Add documentation extraction info if performed
    if ($CustomBaseDir) {
        $logContent += "7. Extracted documentation files to container docs folder"
    }
    
    $logContent += @(
        ""
        "Status: SUCCESS"
        ""
        "=== Preparation Completed Successfully ==="
    )
    
    $logContent | Out-File -FilePath $prepLogFile -Encoding utf8
    
    # Update log size
    $logSize = [math]::Round((Get-Item $prepLogFile).Length / 1KB, 2)
    (Get-Content $prepLogFile) -replace [regex]::Escape("- Log: $prepLogFile"), "- Log: $prepLogFile ($logSize KB)" | Out-File -FilePath $prepLogFile -Encoding utf8
    
    # Summary
    Write-Host ""
    Write-Host "=== PREPARATION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Project: $($p.path_with_namespace)"
    Write-Host "Project folder: $projectDir"
    Write-Host "Size: $($report.repo_size_MB) MB"
    if ($report.lfs_enabled) { Write-Host "LFS: $($report.lfs_size_MB) MB" }
    Write-Host "Default branch: $($report.default_branch)"
    Write-Host "Visibility: $($report.visibility)"
    Write-Host ""
    Write-Host "Generated files:"
    Write-Host "  Report: $reportFile"
    Write-Host "  Log: $prepLogFile"
    if (Test-Path $repoDir) { Write-Host "  Repository: $repoDir" }
    Write-Host "===========================" -ForegroundColor Cyan

    # After preparation, optionally extract documentation files for bulk container
    # If CustomBaseDir provided, create container-level docs folder and extract
    # supported documentation files for this repository into container/docs/<repoName>/
    $docExtractionResult = $null
    try {
        if ($CustomBaseDir) {
            Write-Host "[INFO] Extracting documentation files..."
            $docExtractionResult = Extract-DocumentationFromRepo -RepositoryPath $repoDir -TargetDocsDir (Join-Path $CustomBaseDir "docs" $projectName) -RepoName $projectName
            Write-Host "[OK] Documentation extraction completed: $($docExtractionResult.extracted) files extracted from $($docExtractionResult.total) found"
        }
    }
    catch {
        $docExtractionResult = @{ extracted = 0; total = 0; error = $_.ToString() }
        Write-Warning "[WARN] Documentation extraction step failed for $($projectName): $_"
    }
    
    # Update log with documentation extraction results
    if ($docExtractionResult) {
        $docLogEntry = if ($docExtractionResult.ContainsKey('error') -and $docExtractionResult['error']) {
            "7. Documentation extraction: FAILED - $($docExtractionResult['error'])"
        } else {
            "7. Documentation extraction: SUCCESS - $($docExtractionResult['extracted']) files extracted from $($docExtractionResult['total']) found"
        }
        (Get-Content $prepLogFile) -replace "6. Created preparation log", "6. Created preparation log`n$docLogEntry" | Out-File -FilePath $prepLogFile -Encoding utf8
    }
}

<#
.SYNOPSIS
    Prepares multiple GitLab projects for bulk migration.

.DESCRIPTION
    Downloads and analyzes multiple GitLab projects, creating a consolidated
    template file for bulk migration and individual project preparations.

.PARAMETER ProjectPaths
    Array of GitLab project paths.

.PARAMETER DestProjectName
    Target Azure DevOps project name.

.EXAMPLE
    Invoke-BulkPrepareGitLab -ProjectPaths @("group1/proj1", "group2/proj2") -DestProjectName "MyDevOpsProject"
#>
function Invoke-BulkPrepareGitLab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ProjectPaths,

        [Parameter(Mandatory)]
        [string]$DestProjectName,

        [Parameter()]
        [switch]$Force
    )
    
    if ($ProjectPaths.Count -eq 0) {
        throw "No projects specified for bulk preparation."
    }
    
    if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
        throw "Destination DevOps project name is required for bulk preparation."
    }
    
    Write-Host "=== BULK PREPARATION STARTING ===" -ForegroundColor Cyan
    Write-Host "Destination Project: $DestProjectName"
    Write-Host "Projects to prepare: $($ProjectPaths.Count)"
    Write-Host ""
    
    # Create self-contained bulk preparation folder structure
    $bulkPaths = Get-BulkProjectPaths -AdoProject $DestProjectName
    $bulkPrepDir = $bulkPaths.containerDir
    $configFile = $bulkPaths.configFile
    
    # Check if preparation already exists
    if (Test-Path $configFile) {
        Write-Host "⚠️  Existing preparation found for '$DestProjectName'" -ForegroundColor Yellow
        Write-Host "   Folder: $bulkPrepDir"
        if (-not $Force.IsPresent) {
            $choice = Read-Host "Continue and update existing preparation? (y/N)"
            if ($choice -notmatch '^[Yy]') {
                Write-Host "Bulk preparation cancelled."
                return
            }
            Write-Host "Updating existing preparation..."
        }
        else {
            Write-Host "Force mode: updating existing preparation without prompting..."
        }
    }
    else {
        Write-Host "Creating new self-contained preparation for '$DestProjectName'..."
    }
    
    # Create bulk preparation log in logs folder
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $bulkLogFile = Join-Path $bulkPaths.logsDir "bulk-preparation-$timestamp.log"
    $startTime = Get-Date
    
    @(
        "=== GitLab Bulk Preparation Log ==="
        "Bulk preparation started: $startTime"
        "Destination DevOps Project: $DestProjectName"
        "Projects to prepare: $($ProjectPaths.Count)"
        ""
        "=== Project List ==="
    ) | Out-File -FilePath $bulkLogFile -Encoding utf8
    
    # Log all projects first
    foreach ($projectPath in $ProjectPaths) {
        "- $projectPath" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    }
    "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    $results = @()
    $projects = @()
    $successCount = 0
    $failureCount = 0
    
    # Process each project
    for ($i = 0; $i -lt $ProjectPaths.Count; $i++) {
        $projectPath = $ProjectPaths[$i]
        $projectNum = $i + 1
        $projectName = ($projectPath -split '/')[-1]
        
        Write-Host "[$projectNum/$($ProjectPaths.Count)] Preparing: $projectPath"
        "=== Project $projectNum/$($ProjectPaths.Count): $projectPath ===" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        "Start time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        
        try {
            # Check if project already prepared in self-contained structure
            $gitlabPaths = Get-BulkProjectPaths -AdoProject $DestProjectName -GitLabProject $projectName
            $projectDir = $gitlabPaths.gitlabDir
            $repoDir = $gitlabPaths.repositoryDir
            
            if (Test-Path $repoDir) {
                Write-Host "    Project already prepared, updating..."
                "Project already exists, updating: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            }
            else {
                Write-Host "    Downloading and analyzing project..."
                "Preparing new project in self-contained structure: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            }
            
            # Run preparation for this project using bulk-specific path
            Initialize-GitLab -ProjectPath $projectPath -CustomBaseDir $bulkPrepDir -CustomProjectName $projectName
            
            # Read the generated preflight report from bulk structure
            $preflightFile = Join-Path $projectDir "reports" "preflight-report.json"
            if (Test-Path $preflightFile) {
                $preflightData = Get-Content $preflightFile | ConvertFrom-Json
                
                try {
                    $projectConfig = [pscustomobject]@{
                        ado_project      = $DestProjectName
                        gitlab_project   = $projectPath
                        gitlab_repo_name = $projectName
                        migration_type   = "BULK_CHILD"
                        created_date     = $projectStartTime.ToString('yyyy-MM-dd HH:mm:ss')
                        last_updated     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                        status           = "PREPARED"
                        repo_size_MB     = $preflightData.repo_size_MB
                        lfs_enabled      = $preflightData.lfs_enabled
                        lfs_size_MB      = $preflightData.lfs_size_MB
                        default_branch   = $preflightData.default_branch
                        visibility       = $preflightData.visibility
                    }
                    $projectConfigPath = Join-Path $projectDir "migration-config.json"
                    $projectConfig | ConvertTo-Json -Depth 6 | Set-Content -Path $projectConfigPath -Encoding UTF8
                }
                catch {
                    Write-Verbose "[BulkPrepare] Failed to write per-project config for $($projectName): $_"
                }
                
                # Add to bulk template
                $projects += [pscustomobject]@{
                    gitlab_path       = $projectPath
                    ado_repo_name     = $projectName
                    description       = "Migrated from $projectPath"
                    repo_size_MB      = $preflightData.repo_size_MB
                    lfs_enabled       = $preflightData.lfs_enabled
                    lfs_size_MB       = $preflightData.lfs_size_MB
                    default_branch    = $preflightData.default_branch
                    visibility        = $preflightData.visibility
                    preparation_status = "SUCCESS"
                }
                
                $result = [pscustomobject]@{
                    gitlab_project   = $projectPath
                    status           = "SUCCESS"
                    repo_size_MB     = $preflightData.repo_size_MB
                    lfs_size_MB      = $preflightData.lfs_size_MB
                    preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                }
                $successCount++
                
                Write-Host "    ✅ SUCCESS: $projectPath ($($preflightData.repo_size_MB) MB)" -ForegroundColor Green
            }
            else {
                throw "Preflight report not found after preparation"
            }
            
            $results += $result
            "Status: SUCCESS" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        }
        catch {
            # Add failed project to template with error status
            $projects += [pscustomobject]@{
                gitlab_path        = $projectPath
                ado_repo_name      = $projectName
                description        = "FAILED: $($_.ToString())"
                preparation_status = "FAILED"
                error_message      = $_.ToString()
            }
            
            $result = [pscustomobject]@{
                gitlab_project   = $projectPath
                status           = "FAILED"
                error_message    = $_.ToString()
                preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            }
            $results += $result
            $failureCount++
            
            Write-Host "    ❌ FAILED: $projectPath" -ForegroundColor Red
            Write-Host "       Error: $_" -ForegroundColor Red
            "Status: FAILED" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "Error: $_" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
            "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8

            try {
                $failedConfig = [pscustomobject]@{
                    ado_project      = $DestProjectName
                    gitlab_project   = $projectPath
                    gitlab_repo_name = $projectName
                    migration_type   = "BULK_CHILD"
                    created_date     = $projectStartTime.ToString('yyyy-MM-dd HH:mm:ss')
                    last_updated     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                    status           = "FAILED"
                    error_message    = $_.ToString()
                }
                $failedConfigPath = Join-Path $projectDir "migration-config.json"
                $failedConfig | ConvertTo-Json -Depth 6 | Set-Content -Path $failedConfigPath -Encoding UTF8
            }
            catch {
                Write-Verbose "[BulkPrepare] Failed to write failure config for $($projectName): $_"
            }
        }
    }
    
    # Create bulk migration config (renamed from template for clarity)
    # Calculate totals safely (only for successful preparations)
    $successfulProjects = $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' -and $_.repo_size_MB }
    $totalSizeMB = if ($successfulProjects) {
        ($successfulProjects | Measure-Object -Property repo_size_MB -Sum).Sum
    } else { 0 }
    
    $successfulProjectsWithLfs = $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' -and $_.lfs_size_MB }
    $totalLfsMB = if ($successfulProjectsWithLfs) {
        ($successfulProjectsWithLfs | Measure-Object -Property lfs_size_MB -Sum).Sum
    } else { 0 }
    
    $config = [pscustomobject]@{
        description         = "Bulk migration configuration for '$DestProjectName' - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        destination_project = $DestProjectName
        migration_type      = "BULK"
        preparation_summary = [pscustomobject]@{
            total_projects          = $ProjectPaths.Count
            successful_preparations = $successCount
            failed_preparations     = $failureCount
            total_size_MB           = $totalSizeMB
            total_lfs_MB            = $totalLfsMB
            preparation_time        = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
        projects            = $projects
    }
    
    $config | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $configFile

    # Also create/update the top-level migration-config.json used by single-migration workflow
    $totalEndTime = Get-Date
    $overallStatus = if ($successCount -eq $ProjectPaths.Count -and $ProjectPaths.Count -gt 0) {
        'PREPARED'
    }
    elseif ($successCount -gt 0) {
        'PARTIAL'
    }
    elseif ($failureCount -gt 0) {
        'FAILED'
    }
    else {
        'UNKNOWN'
    }

    $primaryProject = $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' } | Select-Object -First 1
    if (-not $primaryProject -and $projects.Count -gt 0) {
        $primaryProject = $projects[0]
    }

    $gitlabPathValue = if ($primaryProject) { $primaryProject.gitlab_path } elseif ($ProjectPaths.Count -gt 0) { $ProjectPaths[0] } else { $DestProjectName }
    $adoRepoValue = if ($primaryProject) { $primaryProject.ado_repo_name } elseif ($ProjectPaths.Count -gt 0) { ($ProjectPaths[0] -split '/')[-1] } else { $DestProjectName }

    $topLevelConfig = [pscustomobject]@{
        ado_project          = $DestProjectName
        gitlab_project       = $gitlabPathValue
        gitlab_repo_name     = $adoRepoValue
        migration_type       = "BULK"
        created_date         = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        last_updated         = $totalEndTime.ToString('yyyy-MM-dd HH:mm:ss')
        status               = $overallStatus
        project_count        = $ProjectPaths.Count
        successful_projects  = $successCount
        failed_projects      = $failureCount
        preparation_summary  = $config.preparation_summary
        projects             = $config.projects
    }

    $topLevelConfigPath = Join-Path $bulkPaths.containerDir "migration-config.json"
    $topLevelConfig | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $topLevelConfigPath
    
    # Create summary report in reports folder
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $summaryFile = Join-Path $bulkPaths.reportsDir "preparation-summary.json"
    
    $summary = [pscustomobject]@{
        preparation_start       = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        preparation_end         = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
        duration_minutes        = [math]::Round($duration.TotalMinutes, 2)
        total_projects          = $ProjectPaths.Count
        successful_preparations = $successCount
        failed_preparations     = $failureCount
        success_rate            = [math]::Round(($successCount / $ProjectPaths.Count) * 100, 1)
        total_size_MB           = $totalSizeMB
        results                 = $results
    }
    
    $summary | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $summaryFile
    
    # Final log entries
    @(
        "=== BULK PREPARATION SUMMARY ==="
        "Bulk preparation completed: $endTime"
        "Total duration: $($duration.ToString('hh\:mm\:ss')) ($([math]::Round($duration.TotalMinutes, 2)) minutes)"
        "Total projects: $($ProjectPaths.Count)"
        "Successful: $successCount"
        "Failed: $failureCount"
        "Success rate: $([math]::Round(($successCount / $ProjectPaths.Count) * 100, 1))%"
        "Config file: $configFile"
        "Summary report: $summaryFile"
        "=== BULK PREPARATION COMPLETED ==="
    ) | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    # Display final results
    Write-Host ""
    Write-Host "=== BULK PREPARATION RESULTS ===" -ForegroundColor Cyan
    Write-Host "Destination Project: $DestProjectName"
    Write-Host "Container folder: $bulkPrepDir" -ForegroundColor Cyan
    Write-Host "Total projects: $($ProjectPaths.Count)"
    Write-Host "✅ Successful: $successCount" -ForegroundColor Green
    Write-Host "❌ Failed: $failureCount" -ForegroundColor Red
    Write-Host "Success rate: $([math]::Round(($successCount / $ProjectPaths.Count) * 100, 1))%"
    Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
    if ($summary.total_size_MB -gt 0) {
        Write-Host "Total repository size: $($summary.total_size_MB) MB"
    }
    Write-Host ""
    Write-Host "Self-contained structure:" -ForegroundColor Yellow
    Write-Host "  � Container: migrations/$DestProjectName/"
    Write-Host "     ├── 📋 bulk-migration-config.json"
    Write-Host "     ├── 📊 reports/preparation-summary.json"
    Write-Host "     ├── 📝 logs/bulk-preparation-*.log"
    foreach ($proj in $projects | Where-Object { $_.preparation_status -eq 'SUCCESS' } | Select-Object -First 3) {
        Write-Host "     ├── 📂 $($proj.ado_repo_name)/repository/"
    }
    if ($successCount -gt 3) {
        Write-Host "     └── ... ($($successCount - 3) more)"
    }
    Write-Host ""
    
    if ($failureCount -gt 0) {
        Write-Host "⚠️  Some projects failed preparation. Review the log file for details." -ForegroundColor Yellow
        Write-Host "   You can fix the issues and re-run preparation to update the config." -ForegroundColor Yellow
    }
    
    Write-Host "Next step: Use Option 6 (Bulk Migration Execution) to migrate all repositories" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Extracts documentation files from prepared GitLab repositories into a centralized docs folder.

.DESCRIPTION
    Scans all prepared GitLab project repositories and copies documentation files
    (docx, pdf, xlsx, pptx) into a centralized docs folder at the Azure DevOps project level.
    Creates subfolders for each repository to maintain organization.

.PARAMETER AdoProject
    Azure DevOps project name (container folder).

.PARAMETER DocExtensions
    Array of file extensions to extract (default: docx, pdf, xlsx, pptx).

.OUTPUTS
    Hashtable with extraction statistics.

.EXAMPLE
    Export-GitLabDocumentation -AdoProject "MyProject"
#>
function Export-GitLabDocumentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [Parameter()]
        [string[]]$DocExtensions = @('docx', 'pdf', 'xlsx', 'pptx', 'doc', 'xls', 'ppt')
    )
    
    Write-Host "[INFO] Starting documentation extraction for project: $AdoProject" -ForegroundColor Cyan
    
    # Get bulk project paths to find container directory
    $bulkPaths = Get-BulkProjectPaths -AdoProject $AdoProject
    $containerDir = $bulkPaths.containerDir
    
    if (-not (Test-Path $containerDir)) {
        Write-Host "[ERROR] Container directory not found: $containerDir" -ForegroundColor Red
        Write-Host "        Make sure the project has been prepared first." -ForegroundColor Yellow
        return $null
    }
    
    # Create docs folder at project level
    $docsDir = Join-Path $containerDir "docs"
    if (-not (Test-Path $docsDir)) {
        New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
        Write-Host "[INFO] Created documentation folder: $docsDir" -ForegroundColor Green
    }
    
    # Statistics
    $stats = @{
        total_files = 0
        total_size_MB = 0
        repositories_processed = 0
        files_by_type = @{}
    }
    
    # Find all repository directories
    $repoDirs = @(Get-ChildItem -Path $containerDir -Directory | Where-Object {
        $repoPath = Join-Path $_.FullName "repository"
        Test-Path $repoPath
    })
    
    if ($repoDirs.Count -eq 0) {
        Write-Host "[WARN] No repository directories found in: $containerDir" -ForegroundColor Yellow
        return $stats
    }
    
    Write-Host "[INFO] Found $($repoDirs.Count) repository directories to scan" -ForegroundColor Cyan
    
    foreach ($repoDir in $repoDirs) {
        $repoName = $repoDir.Name
        $repositoryPath = Join-Path $repoDir.FullName "repository"
        
        Write-Host "[INFO] Scanning repository: $repoName" -ForegroundColor Gray
        
        # Check if this is a bare repository (standard for migrations)
        $isBareRepo = Test-Path (Join-Path $repositoryPath "HEAD")
        
        if ($isBareRepo) {
            # For bare repositories, use git ls-tree to find files
            try {
                Push-Location $repositoryPath
                
                # Get list of all files from HEAD
                $gitFiles = git ls-tree -r --name-only HEAD 2>$null
                
                if ($LASTEXITCODE -eq 0 -and $gitFiles) {
                    # Filter for documentation files
                    $docFiles = @($gitFiles | Where-Object {
                        $extension = [System.IO.Path]::GetExtension($_).TrimStart('.').ToLower()
                        $DocExtensions -contains $extension
                    })
                    
                    if ($docFiles.Count -gt 0) {
                        Write-Host "  [INFO] Found $($docFiles.Count) documentation files" -ForegroundColor Cyan
                        
                        foreach ($filePath in $docFiles) {
                            try {
                                # Extract just the filename for flat structure in docs folder
                                $fileName = [System.IO.Path]::GetFileName($filePath)
                                $targetPath = Join-Path $docsDir $fileName
                                
                                # If file already exists, append repository name to avoid conflicts
                                if (Test-Path $targetPath) {
                                    $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                                    $fileExt = [System.IO.Path]::GetExtension($fileName)
                                    $fileName = "${fileNameWithoutExt}_${repoName}${fileExt}"
                                    $targetPath = Join-Path $docsDir $fileName
                                }
                                
                                # Extract file from git using git show with output redirection
                                # Use Start-Process to properly handle binary file extraction
                                $gitArgs = @("show", "HEAD:$filePath")
                                $process = Start-Process -FilePath "git" -ArgumentList $gitArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $targetPath -RedirectStandardError "NUL"
                                
                                if ($process.ExitCode -eq 0 -and (Test-Path $targetPath)) {
                                    $fileInfo = Get-Item $targetPath
                                    
                                    # Verify file has content
                                    if ($fileInfo.Length -gt 0) {
                                        # Update statistics
                                        $stats.total_files++
                                        $stats.total_size_MB += [math]::Round(($fileInfo.Length / 1MB), 2)
                                        
                                        $extension = [System.IO.Path]::GetExtension($filePath).TrimStart('.').ToLower()
                                        if (-not $stats.files_by_type.ContainsKey($extension)) {
                                            $stats.files_by_type[$extension] = 0
                                        }
                                        $stats.files_by_type[$extension]++
                                        
                                        Write-Host "    ✓ $fileName" -ForegroundColor Green
                                    }
                                    else {
                                        Write-Warning "    ✗ Failed to extract $fileName (file is empty)"
                                        Remove-Item $targetPath -Force -ErrorAction SilentlyContinue
                                    }
                                }
                                else {
                                    Write-Warning "    ✗ Failed to extract $fileName from repository"
                                }
                            }
                            catch {
                                Write-Warning "    ✗ Failed to extract $fileName : $_"
                            }
                        }
                    }
                    else {
                        Write-Host "  [INFO] No documentation files found" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "  [WARN] Could not read repository contents" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Warning "  [ERROR] Failed to process bare repository: $_"
            }
            finally {
                Pop-Location
            }
        }
        else {
            # For non-bare repositories (working directory exists), use file system scan
            $docFiles = @(Get-ChildItem -Path $repositoryPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $extension = $_.Extension.TrimStart('.').ToLower()
                $DocExtensions -contains $extension
            })
            
            if ($docFiles.Count -gt 0) {
                Write-Host "  [INFO] Found $($docFiles.Count) documentation files" -ForegroundColor Cyan
                
                foreach ($file in $docFiles) {
                    try {
                        # Extract just the filename for flat structure in docs folder
                        $fileName = $file.Name
                        $targetPath = Join-Path $docsDir $fileName
                        
                        # If file already exists, append repository name to avoid conflicts
                        if (Test-Path $targetPath) {
                            $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                            $fileExt = $file.Extension
                            $fileName = "${fileNameWithoutExt}_${repoName}${fileExt}"
                            $targetPath = Join-Path $docsDir $fileName
                        }
                        
                        # Copy file
                        Copy-Item -Path $file.FullName -Destination $targetPath -Force
                        
                        # Update statistics
                        $stats.total_files++
                        $stats.total_size_MB += [math]::Round(($file.Length / 1MB), 2)
                        
                        $extension = $file.Extension.TrimStart('.').ToLower()
                        if (-not $stats.files_by_type.ContainsKey($extension)) {
                            $stats.files_by_type[$extension] = 0
                        }
                        $stats.files_by_type[$extension]++
                        
                        Write-Host "    ✓ $fileName" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "    ✗ Failed to copy $fileName : $_"
                    }
                }
            }
            else {
                Write-Host "  [INFO] No documentation files found" -ForegroundColor Gray
            }
        }
        
        $stats.repositories_processed++
    }
    
    # Display summary
    Write-Host ""
    Write-Host "=== DOCUMENTATION EXTRACTION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Repositories scanned: $($stats.repositories_processed)"
    Write-Host "Total files extracted: $($stats.total_files)"
    Write-Host "Total size: $($stats.total_size_MB) MB"
    
    if ($stats.files_by_type.Count -gt 0) {
        Write-Host ""
        Write-Host "Files by type:" -ForegroundColor Cyan
        foreach ($ext in $stats.files_by_type.Keys | Sort-Object) {
            Write-Host "  .$ext : $($stats.files_by_type[$ext]) files" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Documentation folder: $docsDir" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Cyan
    
    return $stats
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-GitLabProject',
    'Test-GitLabAuth',
    'Initialize-GitLab',
    'Invoke-BulkPrepareGitLab',
    'Export-GitLabDocumentation',
    'Extract-DocumentationFromRepo'
)

#
# Helper: Extract documentation files from a repository into target docs dir
# Filters: extensions (docx,pdf,xlsx,pptx), filename must contain English or Arabic letters,
#          filename must not contain more than 7 numeric digits, and extracted file size > 0
#
function Extract-DocumentationFromRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath,

        [Parameter(Mandatory)]
        [string]$TargetDocsDir,

        [Parameter()]
        [string]$RepoName = ''
    )

    # Supported extensions
    $extensions = @('docx','pdf','xlsx','pptx')

    if (-not (Test-Path $RepositoryPath)) {
        Write-Verbose "[Docs] Repository path not found: $RepositoryPath"
        return @{ total = 0; extracted = 0 }
    }

    # Ensure target docs dir
    if (-not (Test-Path $TargetDocsDir)) { New-Item -ItemType Directory -Path $TargetDocsDir -Force | Out-Null }

    $extractedCount = 0
    $totalFound = 0

    # Determine if bare repo (contains HEAD file) or working tree
    $isBare = Test-Path (Join-Path $RepositoryPath 'HEAD')

    if ($isBare) {
        Push-Location $RepositoryPath
        try {
            $gitFiles = git ls-tree -r --name-only HEAD 2>$null
            if (-not $gitFiles) { return @{ total = 0; extracted = 0 } }

            foreach ($f in $gitFiles) {
                $ext = [System.IO.Path]::GetExtension($f).TrimStart('.').ToLower()
                if (-not ($extensions -contains $ext)) { continue }
                $totalFound++

                $fileName = [System.IO.Path]::GetFileName($f)
                $nameOnly = [System.IO.Path]::GetFileNameWithoutExtension($f)

                # Filter: must contain at least one English or Arabic letter
                $hasEnglish = $nameOnly -match '[A-Za-z]'
                $hasArabic = $nameOnly -match '[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]'
                if (-not ($hasEnglish -or $hasArabic)) { continue }

                # Digit count <= 7
                $digitCount = ([regex]::Matches($nameOnly, '\d')).Count
                if ($digitCount -gt 7) { continue }

                # Extract file contents via git show to a temp file then verify size
                $tempOut = Join-Path $TargetDocsDir $fileName
                try {
                    # Use git show to extract
                    git show "HEAD:$f" > $tempOut 2>$null
                    if ((Test-Path $tempOut) -and ((Get-Item $tempOut).Length -gt 0)) {
                        $extractedCount++
                    }
                    else {
                        # Remove zero-length file
                        if (Test-Path $tempOut) { Remove-Item $tempOut -Force -ErrorAction SilentlyContinue }
                    }
                }
                catch {
                    Write-Verbose "[Docs] Failed to extract $f : $_"
                }
            }
        }
        finally { Pop-Location }
    }
    else {
        # Non-bare repo: scan filesystem
        $files = Get-ChildItem -Path $RepositoryPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $extensions -contains ($_.Extension.TrimStart('.').ToLower()) }
        foreach ($file in $files) {
            $totalFound++
            $fileName = $file.Name
            $nameOnly = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

            # Filter for english or arabic letters
            $hasEnglish = $nameOnly -match '[A-Za-z]'
            $hasArabic = $nameOnly -match '[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]'
            if (-not ($hasEnglish -or $hasArabic)) { continue }

            $digitCount = ([regex]::Matches($nameOnly, '\d')).Count
            if ($digitCount -gt 7) { continue }

            if ($file.Length -gt 0) {
                $targetPath = Join-Path $TargetDocsDir $fileName
                try { Copy-Item -Path $file.FullName -Destination $targetPath -Force; $extractedCount++ } catch { Write-Verbose "[Docs] Failed to copy $($file.FullName): $_" }
            }
        }
    }

    Write-Verbose "[Docs] Found $totalFound candidate files, extracted $extractedCount to $TargetDocsDir"
    return @{ total = $totalFound; extracted = $extractedCount }
}

