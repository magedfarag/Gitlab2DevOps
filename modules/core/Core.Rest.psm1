<#
.SYNOPSIS
    Core REST API helpers for GitLab and Azure DevOps communication.

.DESCRIPTION
    This module provides foundational REST API functions used by both GitLab
    and Azure DevOps modules. Includes authentication, HTTP request wrappers,
    retry logic, error normalization, and common utilities.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Author: Migration Team
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Script version (written to all reports and manifests)
$script:ModuleVersion = "2.0.0"

# Module-level variables (set by Initialize-CoreRest)
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabBaseUrl = $null
$script:GitLabToken = $null
$script:AdoApiVersion = $null
$script:SkipCertificateCheck = $false
$script:AdoHeaders = $null
$script:RetryAttempts = 3
$script:RetryDelaySeconds = 5
$script:MaskSecrets = $true
$script:LogRestCalls = $false
$script:ProjectCache = @{}
$script:AdoApiVersionDetected = $null
# Public convenience config object to avoid callers referencing an unset script: variable
# Some modules (older code paths) access $script:coreRestConfig directly; define a safe default.
$script:coreRestConfig = @{
    CollectionUrl = $null
    AdoPat = $null
    GitLabBaseUrl = $null
    GitLabToken = $null
    AdoApiVersion = $null
    SkipCertificateCheck = $script:SkipCertificateCheck
    RetryAttempts = $script:RetryAttempts
    RetryDelaySeconds = $script:RetryDelaySeconds
    MaskSecrets = $script:MaskSecrets
    LogRestCalls = $script:LogRestCalls
}

<#
.SYNOPSIS
    Initializes the Core.Rest module with configuration parameters.

.DESCRIPTION
    Must be called before using any other functions in this module.
    Sets up authentication headers and API endpoints.

.PARAMETER CollectionUrl
    Azure DevOps collection URL.

.PARAMETER AdoPat
    Azure DevOps Personal Access Token.

.PARAMETER GitLabBaseUrl
    GitLab instance base URL.

.PARAMETER GitLabToken
    GitLab Personal Access Token.

.PARAMETER AdoApiVersion
    Azure DevOps REST API version (default: 7.1).

.PARAMETER SkipCertificateCheck
    Skip TLS certificate validation (not recommended for production).

.PARAMETER RetryAttempts
    Number of retry attempts for failed REST calls (default: 3).

.PARAMETER RetryDelaySeconds
    Initial delay between retries in seconds (exponential backoff, default: 5).

.PARAMETER MaskSecrets
    Mask tokens and secrets in logs (default: $true).

.PARAMETER LogRestCalls
    Log all REST API calls with URLs and responses (default: $false).

.EXAMPLE
    Initialize-CoreRest -CollectionUrl "https://dev.azure.com/org" -AdoPat $pat -LogRestCalls
#>
function Initialize-CoreRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CollectionUrl,
        
        [Parameter(Mandatory)]
        [string]$AdoPat,
        
        [Parameter(Mandatory)]
        [string]$GitLabBaseUrl,
        
        [Parameter(Mandatory)]
        [string]$GitLabToken,
        
        [string]$AdoApiVersion = "7.1",
        
        [switch]$SkipCertificateCheck,
        
        [int]$RetryAttempts = 3,
        
        [int]$RetryDelaySeconds = 5,
        
        [bool]$MaskSecrets = $true,
        
        [switch]$LogRestCalls
    )
    
    $script:CollectionUrl = $CollectionUrl
    $script:AdoPat = $AdoPat
    $script:GitLabBaseUrl = $GitLabBaseUrl
    $script:GitLabToken = $GitLabToken
    $script:AdoApiVersion = $AdoApiVersion
    $script:SkipCertificateCheck = $SkipCertificateCheck.IsPresent
    $script:RetryAttempts = $RetryAttempts
    $script:RetryDelaySeconds = $RetryDelaySeconds
    $script:MaskSecrets = $MaskSecrets
    $script:LogRestCalls = $LogRestCalls
    $script:ProjectCache = @{}
    
    # Initialize ADO headers
    $script:AdoHeaders = New-AuthHeader -Pat $AdoPat
    
    Write-Verbose "[Core.Rest] Module initialized (v$script:ModuleVersion)"
    Write-Verbose "[Core.Rest] ADO API Version: $AdoApiVersion"
    # Note: Preserve detected API version cache across re-initializations to reduce API calls
    # Cache is cleared only on new PowerShell session (when $script:AdoApiVersionDetected is naturally $null)
    Write-Verbose "[Core.Rest] SkipCertificateCheck: $($script:SkipCertificateCheck)"
    Write-Verbose "[Core.Rest] Retry: $RetryAttempts attempts, ${RetryDelaySeconds}s delay"
    Write-Host "[INFO] Core.Rest initialized - SkipCertificateCheck = $($script:SkipCertificateCheck)" -ForegroundColor Cyan

    # Populate the public convenience config object for backward compatibility
    $script:coreRestConfig = @{
        CollectionUrl        = $script:CollectionUrl
        AdoPat               = $script:AdoPat
        GitLabBaseUrl        = $script:GitLabBaseUrl
        GitLabToken          = $script:GitLabToken
        AdoApiVersion        = $script:AdoApiVersion
        SkipCertificateCheck = $script:SkipCertificateCheck
        RetryAttempts        = $script:RetryAttempts
        RetryDelaySeconds    = $script:RetryDelaySeconds
        MaskSecrets          = $script:MaskSecrets
        LogRestCalls         = $script:LogRestCalls
    }
}

<#
.SYNOPSIS
    Ensures the Core.Rest module is initialized and returns the config.

.DESCRIPTION
    Many callers assume a populated configuration object is available as
    $script:coreRestConfig or via Get-CoreRestConfig. This helper centralizes
    the check and provides a helpful actionable message if not initialized.

.OUTPUTS
    Hashtable with core REST configuration.
#>
function Ensure-CoreRestInitialized {
    [CmdletBinding()]
    param()

    # If Initialize-CoreRest has been called, the convenience object will be set
    if ($null -ne $script:coreRestConfig -and $script:coreRestConfig.CollectionUrl) {
        return $script:coreRestConfig
    }

    # Attempt to build a best-effort config from individual script variables
    $built = @{
        CollectionUrl        = $script:CollectionUrl
        AdoPat               = $script:AdoPat
        GitLabBaseUrl        = $script:GitLabBaseUrl
        GitLabToken          = $script:GitLabToken
        AdoApiVersion        = $script:AdoApiVersion
        SkipCertificateCheck = $script:SkipCertificateCheck
        RetryAttempts        = $script:RetryAttempts
        RetryDelaySeconds    = $script:RetryDelaySeconds
        MaskSecrets          = $script:MaskSecrets
        LogRestCalls         = $script:LogRestCalls
    }

    # If CollectionUrl is missing, that's fatal for building URIs
    if ([string]::IsNullOrWhiteSpace($built.CollectionUrl)) {
        $msg = New-ActionableError -ErrorType 'TokenNotSet' -Details @{ TokenType = 'ADO' }
        throw "Core REST not initialized. $msg"
    }

    # If AdoPat is missing, warn but allow read-only operations to continue in test environments.
    if ([string]::IsNullOrWhiteSpace($built.AdoPat)) {
        Write-Warning "AdoPat not configured; proceeding without PAT for read-only operations (tests may provide mocks)."
    }

    # Cache and return
    $script:coreRestConfig = $built
    return $script:coreRestConfig
}


#
# Sets minimal ADO context (CollectionUrl + ProjectName) for callers that do not run Initialize-CoreRest
#
function Set-AdoContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$CollectionUrl,
        [Parameter()][string]$ProjectName
    )

    $script:CollectionUrl = $CollectionUrl
    if ($PSBoundParameters.ContainsKey('ProjectName') -and $ProjectName) {
        $script:ProjectName = $ProjectName
    }

    # Keep the convenience config object in sync for backward compatibility
    if ($null -eq $script:coreRestConfig) { $script:coreRestConfig = @{ } }
    $script:coreRestConfig.CollectionUrl = $script:CollectionUrl
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $script:coreRestConfig.ProjectName = $script:ProjectName }

    Write-Verbose "[Core.Rest] Set-AdoContext: CollectionUrl set to $($script:CollectionUrl)"
    if ($script:ProjectName) { Write-Verbose "[Core.Rest] Set-AdoContext: ProjectName set to $($script:ProjectName)" }

    # If a PAT is present in the script scope, ensure headers are created so Invoke-AdoRest can run safely
    try {
        if ($script:AdoPat) {
            $script:AdoHeaders = New-AuthHeader -Pat $script:AdoPat
            Write-Verbose "[Core.Rest] Set-AdoContext: AdoHeaders initialized"
        }
    }
    catch {
        Write-Verbose "[Core.Rest] Unable to initialize AdoHeaders in Set-AdoContext: $_"
    }
}

<#
.SYNOPSIS
    Detect the highest Azure DevOps REST API version supported by the server.

.DESCRIPTION
    Attempts a small, cheap GET against a commonly-available endpoint using
    descending API version candidates. Caches the detected version in
    $script:AdoApiVersionDetected to avoid repeated probes.

.OUTPUTS
    String API version (e.g., '7.2')
#>
function Detect-AdoMaxApiVersion {
    [CmdletBinding()]
    param()

    if ($script:AdoApiVersionDetected) { return $script:AdoApiVersionDetected }

    # Candidates ordered oldest -> newest for tenants that only support older versions
    # Prefer conservative versions first to avoid repeated 400 responses from unsupported newer versions
    $candidates = @('7.1','7.2','7.3','7.0','6.0')

    foreach ($cand in $candidates) {
        try {
            # Use a cheap endpoint: list projects with $top=1
            $testUri = $script:CollectionUrl.TrimEnd('/') + "/_apis/projects?`$top=1&api-version=$cand"
            $headers = $script:AdoHeaders.Clone()
            # Use Invoke-RestWithRetry directly to avoid recursion into Invoke-AdoRest
            $resp = Invoke-RestWithRetry -Method 'GET' -Uri $testUri -Headers $headers -Side 'ado' -MaxAttempts 1 -DelaySeconds 1
            if ($resp) {
                $script:AdoApiVersionDetected = $cand
                Write-Verbose "[Core.Rest] Detected ADO API version: $cand"
                return $cand
            }
        }
        catch {
            # This is expected for unsupported versions on some servers; log as debug to keep transcripts clean
            Write-Debug "[Core.Rest] Candidate API version $cand not supported: $_"
            continue
        }
    }

    # Fallback to configured value
    $script:AdoApiVersionDetected = $script:AdoApiVersion
    Write-Verbose "[Core.Rest] Falling back to configured ADO API version: $script:AdoApiVersionDetected"
    return $script:AdoApiVersionDetected
}

<#
.SYNOPSIS
    Gets the module version.

.DESCRIPTION
    Returns the current module version string.

.OUTPUTS
    String version number.

.EXAMPLE
    $version = Get-CoreRestVersion
#>
function Get-CoreRestVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    return $script:ModuleVersion
}

<#
.SYNOPSIS
    Returns the current Core.Rest configuration.

.DESCRIPTION
    Exposes the connection settings that were provided to Initialize-CoreRest
    so that other runspaces can reinitialize themselves (e.g., thread jobs).

.OUTPUTS
    Hashtable containing configuration values (may contain $null values if
    Initialize-CoreRest has not been called yet).

.EXAMPLE
    $config = Get-CoreRestConfig
    Initialize-CoreRest @config
#>
function Get-CoreRestConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    # Return the convenience object if present (avoids "variable not set" when callers use $script:coreRestConfig)
    if ($null -ne $script:coreRestConfig) { return $script:coreRestConfig }

    # Fallback: build and return a config from individual script variables
    return @{
        CollectionUrl        = $script:CollectionUrl
        AdoPat               = $script:AdoPat
        GitLabBaseUrl        = $script:GitLabBaseUrl
        GitLabToken          = $script:GitLabToken
        AdoApiVersion        = $script:AdoApiVersion
        SkipCertificateCheck = $script:SkipCertificateCheck
        RetryAttempts        = $script:RetryAttempts
        RetryDelaySeconds    = $script:RetryDelaySeconds
        MaskSecrets          = $script:MaskSecrets
        LogRestCalls         = $script:LogRestCalls
    }
}

<#
.SYNOPSIS
    Creates an actionable error message with recovery suggestions.

.DESCRIPTION
    Formats error messages with specific recovery steps based on error type.
    Helps users quickly resolve common issues.

.PARAMETER ErrorType
    Type of error: GitNotFound, GitLFSRequired, ProjectNotFound, RepoNotFound,
    AuthFailed, NetworkError, GitPushFailed, WikiCreateFailed, APIError

.PARAMETER Details
    Specific details about the error (e.g., project name, status code)

.OUTPUTS
    Formatted error message with actionable steps.

.EXAMPLE
    New-ActionableError -ErrorType "ProjectNotFound" -Details @{ ProjectName = "MyProject" }
#>
function New-ActionableError {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GitNotFound', 'GitLFSRequired', 'ProjectNotFound', 'RepoNotFound', 
                     'AuthFailed', 'NetworkError', 'GitPushFailed', 'WikiCreateFailed', 
                     'APIError', 'TokenNotSet', 'TemplateNotFound')]
        [string]$ErrorType,
        
        [Parameter(Mandatory)]
        [hashtable]$Details
    )
    
    $message = switch ($ErrorType) {
        'GitNotFound' {
            @"
Git executable not found on PATH.

Recovery steps:
  1. Install Git: https://git-scm.com/download/win
  2. Restart PowerShell after installation
  3. Verify with: git --version
"@
        }
        
        'GitLFSRequired' {
            @"
Git LFS (Large File Storage) required but not found.
Repository contains $($Details.LFSSizeMB) MB of LFS data.

Recovery steps:
  1. Install Git LFS: https://git-lfs.github.com/
  2. Run: git lfs install
  3. Verify with: git lfs version
  4. Re-run preparation step
"@
        }
        
        'ProjectNotFound' {
            @"
Azure DevOps project '$($Details.ProjectName)' not found.

Recovery steps:
  1. Check project name spelling (case-sensitive)
  2. Verify you have access to the project
  3. Create project first using Option 2 (Initialize Azure DevOps Project)
  4. List available projects: az devops project list
"@
        }
        
        'RepoNotFound' {
            @"
Repository '$($Details.RepoName)' not found in project '$($Details.ProjectName)'.

Recovery steps:
  1. Check repository name spelling
  2. Verify repository exists in Azure DevOps
  3. Check your access permissions
  4. Create repository first or use -AllowSync flag
"@
        }
        
        'AuthFailed' {
            $target = if ($Details.Target -eq 'GitLab') { 'GitLab' } else { 'Azure DevOps' }
            @"
Authentication failed for $target.

Recovery steps:
  1. Verify PAT token is valid and not expired
  2. Check token has required permissions:
     - Azure DevOps: Code (Read & Write), Project (Read)
     - GitLab: api, read_repository
  3. Re-run Initialize-CoreRest with correct token
  4. Check token in environment: `$env:ADO_PAT or `$env:GITLAB_PAT
"@
        }
        
        'NetworkError' {
            @"
Network connection failed to $($Details.Target).

Recovery steps:
  1. Check network connectivity: ping $($Details.Hostname)
  2. Verify firewall/proxy settings
  3. For on-premise servers, check VPN connection
  4. Test URL in browser: $($Details.Url)
  5. If using SSL/TLS, server may need -SkipCertificateCheck
"@
        }
        
        'GitPushFailed' {
            @"
Git push to Azure DevOps failed.

Recovery steps:
  1. Verify PAT has Code (Write) permission
  2. Check branch policies aren't blocking the push
  3. Ensure repository isn't locked
  4. Verify remote URL is correct
  5. Check network connectivity
  6. Try manual push: git push ado --mirror
"@
        }
        
        'WikiCreateFailed' {
            @"
Failed to create wiki page '$($Details.PagePath)'.

Recovery steps:
  1. Check project has wiki enabled
  2. Verify PAT has Wiki (Read & Write) permission
  3. Check page path is valid (no special characters)
  4. Ensure wiki repository exists
  5. Try creating page manually in Azure DevOps UI
"@
        }
        
        'TokenNotSet' {
            $tokenType = if ($Details.TokenType -eq 'GitLab') { 'GITLAB_PAT' } else { 'ADO_PAT' }
            @"
$($Details.TokenType) token not configured.

Recovery steps:
  1. Set environment variable: `$env:$tokenType = 'your-token-here'
  2. Or add to .env file: $tokenType=your-token-here
  3. Or pass via parameter: -$($Details.TokenType)Pat 'your-token-here'
  4. Verify with: `$env:$tokenType (should show masked value)
  5. Re-run Initialize-CoreRest
"@
        }
        
        'TemplateNotFound' {
            @"
Template file '$($Details.TemplateName)' not found.

Recovery steps:
  1. Check template name spelling: $($Details.TemplateName)
  2. Verify template exists in: $($Details.TemplatePath)
  3. Use -TemplateDirectory parameter for custom location
  4. System will fall back to embedded template automatically
"@
        }
        
        'APIError' {
            @"
API request failed: $($Details.Method) $($Details.Endpoint)
Status: $($Details.StatusCode) - $($Details.StatusText)

Recovery steps:
  1. Check endpoint URL is correct
  2. Verify API version compatibility
  3. Ensure token has required permissions
  4. Check server is accessible
  5. Review detailed error: $($Details.ErrorMessage)
  6. Retry operation (automatic retry may have been exhausted)
"@
        }
    }
    
    return $message
}

<#
.SYNOPSIS
    Validates an Azure DevOps repository name.

.DESCRIPTION
    Checks if a repository name meets Azure DevOps naming requirements:
    - Only alphanumeric characters, hyphens, underscores, and periods
    - Cannot start with underscore or period
    - Cannot end with period
    - Maximum 64 characters
    - Cannot contain reserved characters: / \ : * ? " < > | # $ } { , + = [ ]

.PARAMETER RepoName
    The repository name to validate.

.PARAMETER ThrowOnError
    If specified, throws an exception on validation failure. Otherwise returns $false.

.OUTPUTS
    Boolean indicating if the name is valid (if -ThrowOnError not specified).

.EXAMPLE
    Test-AdoRepositoryName "my-repo-123"  # Returns $true
    
.EXAMPLE
    Test-AdoRepositoryName "_invalid" -ThrowOnError  # Throws exception
#>
function Test-AdoRepositoryName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$RepoName,
        
        [switch]$ThrowOnError
    )
    
    $errors = @()
    
    # Check length
    if ($RepoName.Length -gt 64) {
        $errors += "Repository name exceeds 64 characters (length: $($RepoName.Length))"
    }
    
    if ($RepoName.Length -eq 0) {
        $errors += "Repository name cannot be empty"
    }
    
    # Check for invalid starting characters
    if ($RepoName -match '^[._]') {
        $errors += "Repository name cannot start with underscore or period"
    }
    
    # Check for invalid ending characters
    if ($RepoName -match '\.$') {
        $errors += "Repository name cannot end with period"
    }
    
    # Check for invalid characters (Azure DevOps restrictions)
    $invalidChars = @('/', '\', ':', '*', '?', '"', '<', '>', '|', '#', '$', '}', '{', ',', '+', '=', '[', ']', '@', '!', '%', '^', '&', '(', ')', ' ')
    foreach ($char in $invalidChars) {
        if ($RepoName.Contains($char)) {
            $errors += "Repository name contains invalid character: '$char'"
            break
        }
    }
    
    # Check for valid pattern (alphanumeric, hyphen, underscore, period only)
    if ($RepoName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*[a-zA-Z0-9]$' -and $RepoName.Length -gt 1) {
        # Allow single character names if alphanumeric
        if (-not ($RepoName.Length -eq 1 -and $RepoName -match '^[a-zA-Z0-9]$')) {
            $errors += "Repository name must contain only alphanumeric characters, hyphens, underscores, and periods"
        }
    }
    
    if ($errors.Count -gt 0) {
        if ($ThrowOnError) {
            $errorMsg = @"
Invalid Azure DevOps repository name: '$RepoName'

Validation errors:
$($errors | ForEach-Object { "  • $_" } | Out-String)

Azure DevOps naming rules:
  • Only alphanumeric characters, hyphens (-), underscores (_), and periods (.)
  • Cannot start with underscore or period
  • Cannot end with period
  • Maximum 64 characters
  • No spaces or special characters: / \ : * ? " < > | # $ } { , + = [ ] @ ! % ^ & ( )

Valid examples:
  • my-repo
  • MyRepository
  • app_backend
  • project-api-v2
"@
            throw $errorMsg
        }
        return $false
    }
    
    return $true
}

<#
.SYNOPSIS
    Gets the GitLab token for authentication.

.DESCRIPTION
    Returns the GitLab PAT token that was configured during module initialization.
    Used internally by other modules that need to authenticate with GitLab (e.g., git clone).

.OUTPUTS
    String GitLab personal access token.

.EXAMPLE
    $token = Get-GitLabToken
#>
function Get-GitLabToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    if ([string]::IsNullOrWhiteSpace($script:GitLabToken)) {
        $errorMsg = New-ActionableError -ErrorType 'TokenNotSet' -Details @{ TokenType = 'GitLab' }
        throw $errorMsg
    }
    
    return $script:GitLabToken
}

<#
.SYNOPSIS
    Gets the SkipCertificateCheck setting.

.DESCRIPTION
    Returns whether SSL certificate validation should be skipped.
    Used by other modules when making direct HTTP calls (e.g., git operations).

.OUTPUTS
    Boolean indicating if certificate validation should be skipped.

.EXAMPLE
    $skipCert = Get-SkipCertificateCheck
#>
function Get-SkipCertificateCheck {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    return $script:SkipCertificateCheck
}

<#
.SYNOPSIS
    Masks secrets in a URL or string.

.DESCRIPTION
    Replaces tokens and sensitive data with asterisks for safe logging.

.PARAMETER Text
    Text to mask.

.OUTPUTS
    Masked string.

.EXAMPLE
    $safe = Hide-Secret -Text "https://api.com?token=glpat-abc123"
#>
function Hide-Secret {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,
        
        # Optional explicit secret to mask for compatibility with older tests
        [string]$Secret
    )
    
    if (-not $script:MaskSecrets -or [string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    
    $masked = $Text
    
    # If an explicit secret was provided, mask it first (URL userinfo and plain text)
    if ($Secret) {
        $safeSecret = [Regex]::Escape($Secret)
        $masked = [Regex]::Replace($masked, $safeSecret, '***')
        # Also handle userinfo form oauth2:token@host
        $masked = $masked -replace ":$safeSecret@", ':***@'
    }
    
    # Mask common token patterns
    $masked = $masked -replace 'glpat-[a-zA-Z0-9_\-]+', 'glpat-***'
    $masked = $masked -replace 'ado_pat=[^&\s]+', 'ado_pat=***'
    $masked = $masked -replace 'Authorization: Basic [A-Za-z0-9+/=]+', 'Authorization: Basic ***'
    $masked = $masked -replace 'PRIVATE-TOKEN[''\"]?\s*[:=]\s*[''\"]?[a-zA-Z0-9_\-]+', 'PRIVATE-TOKEN: ***'
    $masked = $masked -replace ':[a-zA-Z0-9_\-]{20,}@', ':***@'
    
    return $masked
}

<#
.SYNOPSIS
    Normalizes an error response from ADO or GitLab.

.DESCRIPTION
    Converts raw HTTP exceptions into a standardized error object.

.PARAMETER Exception
    The exception object from Invoke-RestMethod.

.PARAMETER Side
    The API side ('ado' or 'gitlab').

.PARAMETER Endpoint
    The endpoint that failed.

.OUTPUTS
    Hashtable with side, endpoint, status, message properties.

.EXAMPLE
    $error = New-NormalizedError -Exception $_ -Side 'ado' -Endpoint '/_apis/projects'
#>
function New-NormalizedError {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $Exception,
        
        [Parameter(Mandatory)]
        [ValidateSet('ado', 'gitlab')]
        [string]$Side,
        
        [Parameter(Mandatory)]
        [string]$Endpoint
    )
    
    $status = 0
    $message = "Unknown error"
    
    # Handle different error object types
    if ($Exception -is [string]) {
        $message = [string]$Exception
        $actualException = $null
    }
    elseif ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $message = $Exception.Exception.Message
        $actualException = $Exception.Exception
    }
    elseif ($Exception -and ($Exception | Get-Member -Name 'Message' -MemberType Properties -ErrorAction SilentlyContinue)) {
        $message = $Exception.Message
        $actualException = $Exception
    }
    elseif ($Exception -and ($Exception | Get-Member -Name 'Exception' -MemberType Properties -ErrorAction SilentlyContinue)) {
        $message = $Exception.Exception.Message
        $actualException = $Exception.Exception
    }
    else {
        $message = $Exception.ToString()
        $actualException = $Exception
    }
    
    # Try to extract HTTP status and response body
    try {
        if ($actualException -and (Get-Member -InputObject $actualException -Name 'Response' -MemberType Properties)) {
            if ($actualException.Response) {
                try {
                    $status = [int]$actualException.Response.StatusCode.value__
                }
                catch {
                    # Status code not available
                }
                
                # Try to extract error message from response body
                try {
                    $reader = New-Object System.IO.StreamReader($actualException.Response.GetResponseStream())
                    $reader.BaseStream.Position = 0
                    $rawBody = $reader.ReadToEnd()
                    # Expose raw body string for callers that want to log diagnostic info
                    if ($rawBody) {
                        try {
                            $body = $rawBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                        }
                        catch {
                            $body = $null
                        }

                        if ($body -and $body.message) {
                            $message = $body.message
                        }
                        elseif ($body -and $body.error) {
                            $message = $body.error
                        }
                        elseif ($body -and $body.error_description) {
                            $message = $body.error_description
                        }
                    }
                }
                catch {
                    # Keep original message
                }
            }
        }
    }
    catch {
        # If we can't access Response property, keep original error message
        Write-Verbose "[Core.Rest] Could not extract response details: $_"
    }
    
    return @{
        side     = $Side
        endpoint = Hide-Secret -Text $Endpoint
        status   = $status
        message  = $message
        rawBody  = (if ($rawBody) { $rawBody } else { $null })
    }
}

<#
.SYNOPSIS
    Writes raw curl output to a log file when JSON parsing fails.

.DESCRIPTION
    Creates a detailed log file with raw curl output, extracted JSON string,
    and error details for debugging JSON parsing failures.

.PARAMETER Side
    API side ('ado' or 'gitlab').

.PARAMETER Uri
    The URI that was called.

.PARAMETER Method
    HTTP method used.

.PARAMETER OutputArray
    Raw curl output array.

.PARAMETER JsonString
    Extracted JSON string that failed to parse.

.PARAMETER ErrorMessage
    The error message from JSON parsing failure.

.EXAMPLE
    Write-RawCurlOutputToLog -Side 'ado' -Uri $uri -Method 'GET' -OutputArray $outputArray -JsonString $jsonString -ErrorMessage $_
#>
function Write-RawCurlOutputToLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ado', 'gitlab')]
        [string]$Side,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [array]$OutputArray,

        [Parameter(Mandatory)]
        [string]$JsonString,

        [Parameter(Mandatory)]
        [string]$ErrorMessage
    )

    try {
        # Create logs directory if it doesn't exist
        $logsDir = Join-Path $PSScriptRoot "..\logs"
        if (-not (Test-Path $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        }

        # Generate timestamped log file name
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $logFileName = "curl-debug-$Side-$timestamp.log"
        $logFilePath = Join-Path $logsDir $logFileName

        # Build log content
        $logContent = @"
=== CURL DEBUG LOG ===
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Side: $Side
Method: $Method
URI: $(Hide-Secret -Text $Uri)

=== RAW CURL OUTPUT ===
$($OutputArray -join "`n")

=== EXTRACTED JSON STRING ===
$JsonString

=== JSON PARSING ERROR ===
$ErrorMessage

=== END LOG ===
"@

        # Write to log file
        $logContent | Out-File -FilePath $logFilePath -Encoding UTF8 -Force

        Write-Warning "[$Side] Raw curl output logged to: $logFilePath"
    }
    catch {
        Write-Warning "[$Side] Failed to write curl debug log: $_"
    }
}

<#
.SYNOPSIS
    Invokes a REST call with retry logic and exponential backoff.

.DESCRIPTION
    Wraps Invoke-RestMethod with automatic retry on transient failures (500, 503, 429).

.PARAMETER Method
    HTTP method.

.PARAMETER Uri
    Full URI.

.PARAMETER Headers
    Request headers.

.PARAMETER Body
    Request body.

.PARAMETER Side
    API side for error normalization ('ado' or 'gitlab').

.OUTPUTS
    API response object.

.EXAMPLE
    $result = Invoke-RestWithRetry -Method GET -Uri $uri -Headers $headers -Side 'ado'
#>
function Invoke-RestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Uri,
        
        [Parameter(Mandatory)]
        [hashtable]$Headers,
        
        [object]$Body = $null,
        
        [ValidateSet('ado', 'gitlab')]
        [string]$Side = 'ado',
        
        # Optional overrides for retry behavior (for testing or advanced scenarios)
        [int]$MaxAttempts,
        [int]$DelaySeconds
    )
    
    $attempt = 0
    $effectiveMaxAttempts = if ($PSBoundParameters.ContainsKey('MaxAttempts')) { [Math]::Max(1, $MaxAttempts) } else { $script:RetryAttempts + 1 }
    $baseDelay = if ($PSBoundParameters.ContainsKey('DelaySeconds')) { [Math]::Max(0, $DelaySeconds) } else { $script:RetryDelaySeconds }
    
    while ($attempt -lt $effectiveMaxAttempts) {
        $attempt++
        
        try {
            $invokeParams = @{
                Method  = $Method
                Uri     = $Uri
                Headers = $Headers
            }
            
            # Add body only for methods that support it
            if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
                $invokeParams.Body = $Body
            }
            
            # CRITICAL: Always add SkipCertificateCheck for ADO calls when configured
            # This MUST be present for every request to on-premise servers with self-signed certs
            if ($script:SkipCertificateCheck -eq $true) {
                $invokeParams.SkipCertificateCheck = $true
                Write-Verbose "[Core.Rest] ✓ SkipCertificateCheck=TRUE added to request"
            }
            else {
                Write-Verbose "[Core.Rest] ✗ SkipCertificateCheck=FALSE (script var = $script:SkipCertificateCheck)"
            }
            
            # Log request before sending
            $maskedUri = Hide-Secret -Text $Uri
            $skipCertStatus = if ($invokeParams.ContainsKey('SkipCertificateCheck')) { "SSL:Skip" } else { "SSL:Verify" }
            $methodColor = switch ($Method) {
                'GET' { 'Cyan' }
                'POST' { 'Green' }
                'PUT' { 'Yellow' }
                'PATCH' { 'Magenta' }
                'DELETE' { 'Red' }
                default { 'White' }
            }
            
            Write-Host "[$Side] → $Method $maskedUri" -ForegroundColor $methodColor -NoNewline
            if ($script:LogRestCalls) {
                Write-Host " ($skipCertStatus, attempt $attempt/$effectiveMaxAttempts)" -ForegroundColor Gray
                if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
                    Write-Verbose "[REST] Request body: $($Body.Substring(0, [Math]::Min(500, $Body.Length)))..."
                }
            } else {
                Write-Host ""
            }
            
            # Measure request duration
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-RestMethod @invokeParams
            $stopwatch.Stop()
            
            # Log response summary
            $durationMs = [int]$stopwatch.ElapsedMilliseconds
            $durationColor = if ($durationMs -lt 500) { 'Green' } elseif ($durationMs -lt 2000) { 'Yellow' } else { 'Red' }
            Write-Host "[$Side] ← 200 OK " -ForegroundColor Green -NoNewline
            Write-Host "($durationMs ms)" -ForegroundColor $durationColor
            
            if ($script:LogRestCalls) {
                # Log response highlights - use .Length instead of .Count for safety
                $responseType = $response.GetType().Name
                if ($response.PSObject.Properties['value'] -and $response.value -is [array]) {
                    $itemCount = if ($response.value) { $response.value.Length } else { 0 }
                    Write-Verbose "[REST] Response: $itemCount items in array"
                } elseif ($response -is [array]) {
                    $itemCount = if ($response) { $response.Length } else { 0 }
                    Write-Verbose "[REST] Response: $itemCount items"
                } elseif ($response.PSObject.Properties['count']) {
                    Write-Verbose "[REST] Response: count=$($response.count)"
                } else {
                    Write-Verbose "[REST] Response: $responseType"
                }
            }
            
            return $response
        }
        catch {
            $normalizedError = New-NormalizedError -Exception $_ -Side $Side -Endpoint $Uri
            $status = $normalizedError.status
            $errorMsg = $_.Exception.Message
            
            # Log failed REST call with status code
            # Use less alarming colors for expected errors (404 on GET, retryable errors)
            $statusColor = if ($status -in @(429, 500, 502, 503, 504)) { 
                'Yellow'  # Retryable errors
            } elseif ($status -eq 404 -and $Method -eq 'GET') { 
                'DarkYellow'  # Expected 404s on GET (idempotent checks)
            } else { 
                'Red'  # Real errors
            }
            
            if ($status -gt 0) {
                Write-Host "[$Side] ← $status ERROR" -ForegroundColor $statusColor -NoNewline
                Write-Host " ($($normalizedError.message.Substring(0, [Math]::Min(80, $normalizedError.message.Length))))" -ForegroundColor Gray
            } else {
                Write-Host "[$Side] ✗ Connection error: $($errorMsg.Substring(0, [Math]::Min(80, $errorMsg.Length)))" -ForegroundColor Red
            }
            
            if ($script:LogRestCalls) {
                Write-Verbose "[REST] Full error: $($normalizedError.message)"
            }
            
            # Detect connection errors for curl fallback decision
            $isConnectionError = $errorMsg -match "connection was forcibly closed|Unable to read data from the transport|SSL|certificate|An error occurred while sending the request"
            Write-Verbose "[Core.Rest] Curl fallback check: SkipCert=$script:SkipCertificateCheck, Status=$status, IsConnErr=$isConnectionError"
            Write-Verbose "[Core.Rest] Error message: $errorMsg"
            
            # Fallback to curl for connection issues when SkipCertificateCheck is enabled
            # PowerShell's Invoke-RestMethod sometimes fails with SSL even with -SkipCertificateCheck
            if ($script:SkipCertificateCheck -eq $true -and $isConnectionError) {
                
                if ($attempt -eq 1) {
                    Write-Host "[$Side] ⚠ SSL/TLS fallback to curl" -ForegroundColor Yellow
                    Write-Verbose "[$Side] Original error: $($_.Exception.Message)"
                }
                
                try {
                    # Log curl request
                    Write-Host "[$Side] → $Method $maskedUri (curl -k)" -ForegroundColor DarkCyan
                    # Build curl command
                    # -k: skip SSL verification
                    # -s: silent (no progress bar)
                    # -S: show errors even in silent mode
                    # -i: include HTTP headers in output (to see response code)
                    # -w: write out HTTP code at the end
                    # Use an easily-parsable trailer line for HTTP code
                    # Ensure curl writes the HTTP_CODE on its own line (prepend newline) to avoid it being
                    # appended to the JSON body which breaks ConvertFrom-Json ("Additional text encountered...").
                    $curlArgs = @('-k', '-s', '-S', '-i', '-w', '\nHTTP_CODE:%{http_code}', '-X', $Method, '--max-time', '30')
                    
                    # For Azure DevOps, use Basic auth with PAT
                    # For GitLab, use headers
                    if ($Side -eq 'ado') {
                        # Azure DevOps uses Basic auth with empty username and PAT as password
                        # IMPORTANT: Must pass as separate arguments to ensure proper variable expansion
                        $curlArgs += '-u'
                        $curlArgs += ":$($script:AdoPat)"
                        $curlArgs += '-H'
                        $curlArgs += 'Content-Type: application/json'
                        Write-Verbose "[Core.Rest] Using curl with Basic auth, PAT length: $($script:AdoPat.Length) chars"
                    }
                    else {
                        # GitLab uses PRIVATE-TOKEN header
                        foreach ($key in $Headers.Keys) {
                            $curlArgs += '-H'
                            $curlArgs += "$key`: $($Headers[$key])"
                        }
                    }
                    
                    # Add body for POST/PUT/PATCH
                    if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
                        if ($Side -ne 'ado') {
                            $curlArgs += '-H'
                            $curlArgs += 'Content-Type: application/json'
                        }
                        $curlArgs += '-d'
                        $curlArgs += $Body
                        Write-Verbose "[Core.Rest] POST body length: $($Body.Length) chars"
                    }
                    
                    $curlArgs += $Uri
                    
                    Write-Verbose "[Core.Rest] curl command: curl -k -s -X $Method '$maskedUri'"
                    
                    # Execute curl - capture ALL output including errors
                    $curlStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $curlOutput = & curl @curlArgs 2>&1
                    $curlStopwatch.Stop()
                    
                    # Debug: Check if curl is available
                    if ($LASTEXITCODE -eq 127 -or $LASTEXITCODE -eq 9009) {
                        throw "curl command not found. Please install curl and ensure it's in PATH."
                    }
                    
                    # Safely handle output (may be single object or array)
                    # CRITICAL: Avoid .Count property access - it can fail on non-array objects
                    try {
                        $outputArray = @($curlOutput)
                        # Use type checking instead of .Count property which can fail
                        $isValidArray = ($null -ne $outputArray) -and (($outputArray -is [array] -and $outputArray.Length -gt 0) -or ($outputArray -isnot [array] -and $outputArray))
                        $outputCount = if ($isValidArray) { 
                            if ($outputArray -is [array]) { $outputArray.Length } else { 1 } 
                        } else { 0 }
                        Write-Verbose "[Core.Rest] curl raw output: $outputCount lines (type: $($outputArray.GetType().Name))"
                        Write-Verbose "[Core.Rest] curl exit code: $LASTEXITCODE"
                    }
                    catch {
                        Write-Verbose "[Core.Rest] Error processing curl output: $_"
                        $outputArray = @()
                        $outputCount = 0
                        $isValidArray = $false
                    }
                    
                    # Convert to string array - ENSURE it's always an array
                    # CRITICAL: Use if/else to handle null/empty cases properly
                    if ($isValidArray) {
                        $tempLines = $outputArray | Where-Object { $_ -is [string] } | ForEach-Object { $_.ToString() }
                        $outputLines = if ($tempLines) { @($tempLines) } else { @() }
                    } else {
                        $outputLines = @()
                    }
                    
                    # Safe line count - use .Length which works reliably on arrays
                    $lineCount = if ($outputLines -and $outputLines -is [array]) { 
                        $outputLines.Length 
                    } elseif ($outputLines) { 
                        1 
                    } else { 
                        0 
                    }
                    Write-Verbose "[Core.Rest] curl output string lines: $lineCount"
                    
                    # Extract HTTP status code from the write-out line
                    # HTTP code marker might be on the last line or appended to body; search anywhere
                    $httpCode = 0
                    if ($outputLines -and $lineCount -gt 0) {
                        foreach ($line in $outputLines) {
                            if ($line -match 'HTTP_CODE:(\d{3})') { $httpCode = [int]$Matches[1] }
                        }
                    }
                    
                    Write-Verbose "[Core.Rest] curl HTTP code: $httpCode"
                    
                    # Find where the JSON body starts (after headers, after blank line)
                    # HTTP response format: HTTP/1.1 200 OK\nHeaders...\n\nBody
                    $bodyStartIndex = -1
                    $foundBlankLine = $false
                    
                    if ($lineCount -gt 0) {
                        for ($i = 0; $i -lt $lineCount; $i++) {
                            $currentLine = $outputLines[$i]
                            
                            # Skip HTTP status line (e.g., "HTTP/1.1 404 Not Found")
                            if ($currentLine -match '^HTTP/\d\.\d \d{3}') {
                                Write-Verbose "[Core.Rest] Found HTTP status line at index $i"
                                continue
                            }
                            
                            # Blank line marks end of headers
                            if ([string]::IsNullOrWhiteSpace($currentLine)) {
                                if ($i -gt 0) {
                                    $foundBlankLine = $true
                                    $bodyStartIndex = $i + 1
                                    Write-Verbose "[Core.Rest] Found blank line (end of headers) at index $i, body starts at $bodyStartIndex"
                                    break
                                }
                            }
                        }
                    }
                    
                    # Extract JSON body - skip HTTP_CODE marker, HTTP headers, and empty lines
                    # CRITICAL: Must filter aggressively to avoid "Additional text" JSON parse errors
                    Write-Verbose "[Core.Rest] Extracting JSON from curl output (bodyStart: $bodyStartIndex, lineCount: $lineCount)"
                    
                    # Strategy: Find first line starting with { or [ regardless of blank line detection
                    # This handles cases where blank line detection fails or headers slip through
                    $jsonStarted = $false
                    $jsonLines = @($outputLines | Where-Object { 
                        $currentLine = $_
                        
                        # Skip HTTP_CODE marker always
                        if ($currentLine -match '^HTTP_CODE:') {
                            return $false
                        }
                        
                        # Skip HTTP status lines
                        if ($currentLine -match '^HTTP/\d\.\d') {
                            return $false
                        }
                        
                        # Skip typical HTTP headers (Header-Name: value)
                        if ($currentLine -match '^[A-Za-z][A-Za-z0-9-]+\s*:') {
                            return $false
                        }
                        
                        # Once JSON starts, include everything
                        if ($jsonStarted) {
                            return $true
                        }
                        
                        # Look for JSON start (opening brace or bracket)
                        if ($currentLine -match '^\s*[{\[]') {
                            $jsonStarted = $true
                            Write-Verbose "[Core.Rest] JSON body starts at line: $currentLine"
                            return $true
                        }
                        
                        # Skip empty lines before JSON starts
                        return $false
                    })
                    
                    # Safe count for verbose logging
                    $filteredCount = if ($jsonLines -and $jsonLines -is [array]) { $jsonLines.Length } elseif ($jsonLines) { 1 } else { 0 }
                    Write-Verbose "[Core.Rest] Filtered JSON lines: $filteredCount"
                    
                    $jsonString = $jsonLines -join "`n"

                    # Defensive cleanup: sometimes curl write-out or stray characters can be appended
                    # to the JSON body (for example 'HTTP_CODE:200' without a newline). Strip any
                    # trailing HTTP_CODE marker and trim any non-JSON trailing characters by
                    # truncating after the last closing brace/bracket.
                    try {
                        # Remove trailing HTTP_CODE marker if present on same line
                        $jsonString = $jsonString -replace '\s*HTTP_CODE:\d{3}\s*$', ''

                        # Truncate after the last '}' or ']' to remove any trailing garbage
                        $lastBrace = $jsonString.LastIndexOf('}')
                        $lastBracket = $jsonString.LastIndexOf(']')
                        $lastPos = [Math]::Max($lastBrace, $lastBracket)
                        if ($lastPos -gt -1 -and $lastPos -lt ($jsonString.Length - 1)) {
                            $jsonString = $jsonString.Substring(0, $lastPos + 1)
                        }
                    }
                    catch {
                        Write-Verbose "[Core.Rest] Warning: failed defensive JSON cleanup: $_"
                    }

                    Write-Verbose "[Core.Rest] Extracted JSON length: $($jsonString.Length) chars"
                    # Safe count - use .Length instead of .Count
                    $jsonLineCount = if ($jsonLines -and $jsonLines -is [array]) { $jsonLines.Length } elseif ($jsonLines) { 1 } else { 0 }
                    Write-Verbose "[Core.Rest] JSON lines extracted: $jsonLineCount"
                    
                    if ($script:LogRestCalls -and $jsonString.Length -gt 0) {
                        Write-Verbose "[Core.Rest] First 200 chars of JSON: $($jsonString.Substring(0, [Math]::Min(200, $jsonString.Length)))"
                    }
                    
                    # Log curl response
                    $curlDurationMs = [int]$curlStopwatch.ElapsedMilliseconds
                    if ($httpCode -ge 200 -and $httpCode -lt 300) {
                        Write-Host "[$Side] ← $httpCode OK (curl, $curlDurationMs ms)" -ForegroundColor Green
                    } elseif ($httpCode -ge 400) {
                        Write-Host "[$Side] ← $httpCode ERROR (curl, $curlDurationMs ms)" -ForegroundColor Red
                    } else {
                        Write-Host "[$Side] ← $httpCode (curl, $curlDurationMs ms)" -ForegroundColor Yellow
                    }
                    
                    if ([string]::IsNullOrWhiteSpace($jsonString)) {
                        Write-Warning "[$Side] curl HTTP $httpCode with empty body"
                        
                        # Log raw output for debugging
                        if ($script:LogRestCalls) {
                            Write-Verbose "[Core.Rest] Raw curl output (first 500 chars):"
                            $rawOutput = ($outputArray | ForEach-Object { $_.ToString() }) -join "`n"
                            Write-Verbose $rawOutput.Substring(0, [Math]::Min(500, $rawOutput.Length))
                        }
                        
                        # Check if this is a network error (connection reset, timeout, etc.)
                        $isNetworkError = $outputArray | Where-Object { 
                            $_ -match 'Connection was reset' -or 
                            $_ -match 'Recv failure' -or
                            $_ -match 'Connection timed out' -or
                            $_ -match 'Failed to connect' -or
                            $_ -match 'SSL' -or
                            $_ -match 'certificate'
                        }
                        
                        if ($isNetworkError -or $httpCode -eq 0) {
                            # Treat as 503 Service Unavailable for retry logic
                            $status = 503
                            $errorDetail = if ($isNetworkError) { $isNetworkError[0] } else { "Connection reset (HTTP $httpCode)" }
                            throw "Network error - $errorDetail"
                        }
                        elseif ($httpCode -ge 400) {
                            $status = $httpCode
                            throw "HTTP $httpCode - Empty error response from server"
                        } 
                        else {
                            throw "Empty response from curl (HTTP $httpCode)"
                        }
                    }
                    
                    try {
                        # First try standard JSON parsing
                        $response = $jsonString | ConvertFrom-Json -ErrorAction Stop
                        
                        if ($script:LogRestCalls) {
                            # Log response highlights for curl - use .Length instead of .Count
                            if ($response.PSObject.Properties['value'] -and $response.value -is [array]) {
                                $itemCount = if ($response.value) { $response.value.Length } else { 0 }
                                Write-Verbose "[REST] Response: $itemCount items in array"
                            } elseif ($response -is [array]) {
                                $itemCount = if ($response) { $response.Length } else { 0 }
                                Write-Verbose "[REST] Response: $itemCount items"
                            } else {
                                Write-Verbose "[REST] Response: $($response.GetType().Name)"
                            }
                        }
                        
                        return $response
                    }
                    catch [System.ArgumentException] {
                        # Handle JSON with empty property names by using -AsHashTable (PowerShell 7+)
                        if ($_.Exception.Message -like "*empty string*" -or $_.Exception.Message -like "*property name*") {
                            try {
                                Write-Verbose "[$Side] Retrying JSON parsing with -AsHashTable due to empty property names"
                                $response = $jsonString | ConvertFrom-Json -AsHashTable -ErrorAction Stop
                                return $response
                            }
                            catch {
                                Write-Warning "[$Side] Failed to parse JSON with -AsHashTable: $_"
                                if ($script:LogRestCalls) {
                                    Write-Verbose "[Core.Rest] JSON string (first 500 chars): $($jsonString.Substring(0, [Math]::Min(500, $jsonString.Length)))"
                                }
                                # Log raw curl output to file for debugging
                                Write-RawCurlOutputToLog -Side $Side -Uri $Uri -Method $Method -OutputArray $outputArray -JsonString $jsonString -ErrorMessage $_
                                # Treat as 503 for retry
                                $status = 503
                                throw "Invalid JSON response from server (contains empty property names)"
                            }
                        }
                        else {
                            throw
                        }
                    }
                    catch {
                        Write-Warning "[$Side] Failed to parse JSON response: $_"
                        if ($script:LogRestCalls) {
                            Write-Verbose "[Core.Rest] JSON string (first 500 chars): $($jsonString.Substring(0, [Math]::Min(500, $jsonString.Length)))"
                        }
                        # Log raw curl output to file for debugging
                        Write-RawCurlOutputToLog -Side $Side -Uri $Uri -Method $Method -OutputArray $outputArray -JsonString $jsonString -ErrorMessage $_
                        # Treat as 503 for retry
                        $status = 503
                        throw "Invalid JSON response from server"
                    }
                }
                catch {
                    Write-Warning "[$Side] curl fallback also failed: $_"
                    # $status might have been set to 503 for retryable network errors
                    # Fall through to retry logic
                }
            }
            
            # Retry on transient failures
            $shouldRetry = $status -in @(429, 500, 502, 503, 504) -and $attempt -lt $effectiveMaxAttempts
            
            if ($shouldRetry) {
                # Exponential backoff with jitter to avoid thundering herd
                $delayBase = $baseDelay * [Math]::Pow(2, $attempt - 1)
                $jitter = Get-Random -Minimum 0 -Maximum ([Math]::Max(1, [int]($delayBase * 0.2)))
                $delay = [int]$delayBase + $jitter
                Write-Host "[$Side] ⟳ Retry in ${delay}s (attempt $attempt/$effectiveMaxAttempts)" -ForegroundColor Yellow
                if ($delay -gt 0) { Start-Sleep -Seconds $delay }
            }
            else {
                # Final failure or non-retryable error
                # 404 on GET is often expected (idempotent checks), so show less alarming message
                if ($Method -eq 'GET' -and $status -eq 404) {
                    Write-Verbose "[$Side] Resource not found (404) - this may be expected for idempotent operations"
                } else {
                    Write-Host "[$Side] ✗ Request failed" -ForegroundColor Red
                }
                
                if ($script:LogRestCalls) {
                    $maskedEndpoint = $normalizedError.endpoint
                    Write-Error "[$Side] REST $Method $maskedEndpoint → HTTP $status : $($normalizedError.message)"
                }
                throw
            }
        }
    }
}


<#
.SYNOPSIS
    Creates a basic authentication header for Azure DevOps.

.DESCRIPTION
    Generates a Base64-encoded authorization header from a Personal Access Token.

.PARAMETER Pat
    Personal Access Token.

.OUTPUTS
    Hashtable with Authorization and Content-Type headers.

.EXAMPLE
    $headers = New-AuthHeader -Pat "your-pat-here"
#>
function New-AuthHeader {
    [CmdletBinding(DefaultParameterSetName='Ado')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ParameterSetName='Ado')]
        [Parameter(Mandatory, ParameterSetName='GitLab')]
        [string]$Pat,
        
        [Parameter(ParameterSetName='Ado')]
        [ValidateSet('ado','gitlab')]
        [string]$Type = 'ado',
        
        # Optional API version header for backward compatibility with some tests
        [Parameter(ParameterSetName='Ado')]
        [string]$ApiVersion
    )
    
    if ($Type -eq 'gitlab') {
        return @{ 'PRIVATE-TOKEN' = $Pat }
    }
    
    $pair = ":$Pat"
    $bytes = [Text.Encoding]::ASCII.GetBytes($pair)
    $hdr = @{
        Authorization = "Basic $([Convert]::ToBase64String($bytes))"
        'Content-Type' = "application/json"
    }
    if ($ApiVersion) { $hdr['api-version'] = $ApiVersion }
    return $hdr
}

<#
.SYNOPSIS
    Invokes an Azure DevOps REST API call.

.DESCRIPTION
    Wrapper around Invoke-RestMethod with ADO-specific error handling,
    authentication, API versioning, and automatic retry logic.

.PARAMETER Method
    HTTP method (GET, POST, PUT, PATCH, DELETE).

.PARAMETER Path
    API path starting with /_apis or /{project}/_apis.

.PARAMETER Body
    Request body (will be converted to JSON if not already a string).

.PARAMETER Preview
    Use preview API version.

.OUTPUTS
    API response object.

.EXAMPLE
    Invoke-AdoRest -Method GET -Path "/_apis/projects"
#>
function Invoke-AdoRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [object]$Body = $null,

        [switch]$Preview,

        # Optional: explicit API version string (e.g. '7.1-preview.3' or '7.2').
        # If provided, it takes priority over Detect-AdoMaxApiVersion/Preview.
        [string]$ApiVersion,

        # Optional overrides for retry behavior (passed to Invoke-RestWithRetry)
        [int]$MaxAttempts,
        [int]$DelaySeconds,

        [string]$ContentType
    )
    
    # Ensure core rest initialized and get a stable config object (avoids relying on module script: vars across modules)
    try {
        $coreRestConfig = Ensure-CoreRestInitialized
    }
    catch {
        throw
    }

    # Determine API version to use. Priority:
    # 1. Explicit -ApiVersion parameter
    # 2. -Preview switch (append preview suffix to detected version)
    # 3. Detected max API version from server
    if ($ApiVersion) {
        $api = $ApiVersion
    }
    else {
        $detected = Detect-AdoMaxApiVersion
        if ($Preview) {
            # Use a conservative preview suffix; callers may pass explicit ApiVersion for different previews
            $api = "$detected-preview.3"
        }
        else {
            $api = $detected
        }
    }
    
    # Determine query string separator based on whether Path already has query parameters
    if ($Path -like '*api-version=*') {
        $queryString = ''
    }
    elseif ($Path -like '*`?*') {
        $queryString = "&api-version=$api"
    }
    else {
        $queryString = "?api-version=$api"
    }
    
    if ($null -eq $script:CollectionUrl) {
        Write-Verbose "[Invoke-AdoRest] CollectionUrl is null"
    }
    else {
        try { Write-Verbose "[Invoke-AdoRest] CollectionUrl type: $($script:CollectionUrl.GetType().FullName)" } catch { }
    }

    $collectionUrl = $coreRestConfig.CollectionUrl
    if ($null -eq $collectionUrl) { throw "Core REST not initialized with a CollectionUrl" }
    $uri = $collectionUrl.TrimEnd('/') + $Path + $queryString
    
    if ($null -ne $Body -and ($Body -isnot [string])) {
        $Body = ($Body | ConvertTo-Json -Depth 100)
    }
    
    # Ensure headers exists (tests may initialize minimal context without headers)
    if (-not $script:AdoHeaders) {
        if ($coreRestConfig.AdoPat) {
            try { $script:AdoHeaders = New-AuthHeader -Pat $coreRestConfig.AdoPat } catch { $script:AdoHeaders = @{} }
        }
        else {
            $script:AdoHeaders = @{}
        }
    }

    # Clone headers and add custom Content-Type if specified
    $headers = $script:AdoHeaders.Clone()
    if ($ContentType) {
        $headers['Content-Type'] = $ContentType
        Write-Verbose "[Invoke-AdoRest] Using custom Content-Type: $ContentType"
    }
    
    try {
        # Build parameters for Invoke-RestWithRetry and only include overrides when provided
        $irtParams = @{
            Method  = $Method
            Uri     = $uri
            Headers = $headers
            Body    = $Body
            Side    = 'ado'
        }
        if ($PSBoundParameters.ContainsKey('MaxAttempts')) { $irtParams['MaxAttempts'] = $MaxAttempts }
        if ($PSBoundParameters.ContainsKey('DelaySeconds')) { $irtParams['DelaySeconds'] = $DelaySeconds }

        return Invoke-RestWithRetry @irtParams
    }
    catch {
        Write-Error "[Core.Rest] Invoke-RestWithRetry failed. CollectionUrl present: $([bool]$script:CollectionUrl); AdoHeaders present: $([bool]$script:AdoHeaders); Headers keys: $($script:AdoHeaders.Keys -join ',')"
        throw
    }
}

<#
.SYNOPSIS
    Invokes a GitLab REST API call.

.DESCRIPTION
    Wrapper around Invoke-RestMethod with GitLab-specific error handling
    and authentication.

.PARAMETER Path
    API path starting with /api/v4/.

.OUTPUTS
    API response object.

.EXAMPLE
    Invoke-GitLabRest -Path "/api/v4/projects/123"
#>
function Invoke-GitLabRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not $script:GitLabToken) {
        $errorMsg = New-ActionableError -ErrorType 'TokenNotSet' -Details @{ TokenType = 'GitLab' }
        throw $errorMsg
    }
    
    $headers = @{ 'PRIVATE-TOKEN' = $script:GitLabToken }
    $uri = $script:GitLabBaseUrl.TrimEnd('/') + $Path
    
    $invokeParams = @{
        Method  = 'GET'
        Uri     = $uri
        Headers = $headers
    }
    
    if ($script:SkipCertificateCheck) {
        $invokeParams.SkipCertificateCheck = $true
    }
    
    return Invoke-RestWithRetry -Method 'GET' -Uri $uri -Headers $headers -Body $null -Side 'gitlab'
}

<#
.SYNOPSIS
    Clears Git credentials from Windows Credential Manager.

.DESCRIPTION
    Removes cached Git credentials to prevent authentication conflicts
    during migrations.

.PARAMETER RemoteName
    Git remote name (default: "ado").

.EXAMPLE
    Clear-GitCredentials -RemoteName "origin"
#>
function Clear-GitCredentials {
    [CmdletBinding()]
    param(
        [string]$RemoteName = "ado"
    )
    
    Write-Verbose "[Core.Rest] Clearing Git credentials for remote: $RemoteName"
    
    # Try to get the remote URL
    $remoteUrl = git remote get-url $RemoteName 2>$null
    
    if ($remoteUrl) {
        Write-Host "[INFO] Clearing cached credentials for: $remoteUrl"
        
        # Windows Credential Manager
        git credential-manager delete $remoteUrl 2>$null
        
        # Git credential helper
        $credInput = "url=$remoteUrl`n`n"
        $credInput | git credential reject 2>$null
        
        Write-Host "[INFO] Credentials cleared successfully"
    }
    else {
        Write-Verbose "[Core.Rest] Remote '$RemoteName' not found, skipping credential cleanup"
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-CoreRest',
    'Ensure-CoreRestInitialized',
    'Get-CoreRestVersion',
    'Get-CoreRestConfig',
    'Get-GitLabToken',
    'Get-SkipCertificateCheck',
    'Hide-Secret',
    'Test-AdoRepositoryName',
    'New-ActionableError',
    'New-NormalizedError',
    'New-AuthHeader',
    'Invoke-RestWithRetry',
    'Invoke-AdoRest',
    'Set-AdoContext',
    'Invoke-GitLabRest',
    'Clear-GitCredentials',
    'Write-RawCurlOutputToLog'
)
