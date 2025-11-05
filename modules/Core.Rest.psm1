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
    Version: 2.0.0
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
    $script:SkipCertificateCheck = $SkipCertificateCheck
    $script:RetryAttempts = $RetryAttempts
    $script:RetryDelaySeconds = $RetryDelaySeconds
    $script:MaskSecrets = $MaskSecrets
    $script:LogRestCalls = $LogRestCalls
    $script:ProjectCache = @{}
    
    # Initialize ADO headers
    $script:AdoHeaders = New-AuthHeader -Pat $AdoPat
    
    Write-Verbose "[Core.Rest] Module initialized (v$script:ModuleVersion)"
    Write-Verbose "[Core.Rest] ADO API Version: $AdoApiVersion"
    Write-Verbose "[Core.Rest] Retry: $RetryAttempts attempts, ${RetryDelaySeconds}s delay"
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
        throw "GitLab token not available. Call Initialize-CoreRest first."
    }
    
    return $script:GitLabToken
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
        [string]$Text
    )
    
    if (-not $script:MaskSecrets -or [string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    
    # Mask common token patterns
    $masked = $Text
    $masked = $masked -replace 'glpat-[a-zA-Z0-9_\-]+', 'glpat-***'
    $masked = $masked -replace 'ado_pat=[^&\s]+', 'ado_pat=***'
    $masked = $masked -replace 'Authorization: Basic [A-Za-z0-9+/=]+', 'Authorization: Basic ***'
    $masked = $masked -replace 'PRIVATE-TOKEN[''"]?\s*[:=]\s*[''"]?[a-zA-Z0-9_\-]+', 'PRIVATE-TOKEN: ***'
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
    if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $message = $Exception.Exception.Message
        $actualException = $Exception.Exception
    }
    elseif ($Exception.Message) {
        $message = $Exception.Message
        $actualException = $Exception
    }
    elseif ($Exception.Exception) {
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
                    $body = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
                    
                    if ($body.message) {
                        $message = $body.message
                    }
                    elseif ($body.error) {
                        $message = $body.error
                    }
                    elseif ($body.error_description) {
                        $message = $body.error_description
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
        
        [Parameter(Mandatory)]
        [ValidateSet('ado', 'gitlab')]
        [string]$Side
    )
    
    $attempt = 0
    $maxAttempts = $script:RetryAttempts + 1
    
    while ($attempt -lt $maxAttempts) {
        $attempt++
        
        try {
            $invokeParams = @{
                Method  = $Method
                Uri     = $Uri
                Headers = $Headers
                Body    = $Body
            }
            
            if ($script:SkipCertificateCheck) {
                $invokeParams.SkipCertificateCheck = $true
            }
            
            if ($script:LogRestCalls) {
                $maskedUri = Hide-Secret -Text $Uri
                Write-Verbose "[REST] $Side $Method $maskedUri (attempt $attempt/$maxAttempts)"
            }
            
            # Measure request duration
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-RestMethod @invokeParams
            $stopwatch.Stop()
            
            if ($script:LogRestCalls) {
                $durationMs = [int]$stopwatch.ElapsedMilliseconds
                $maskedUri = Hide-Secret -Text $Uri
                Write-Verbose "[REST] ✓ $Side $Method $maskedUri → 200 ($durationMs ms)"
            }
            
            return $response
        }
        catch {
            $normalizedError = New-NormalizedError -Exception $_ -Side $Side -Endpoint $Uri
            $status = $normalizedError.status
            
            # Log failed REST call
            if ($script:LogRestCalls) {
                $maskedUri = Hide-Secret -Text $Uri
                Write-Verbose "[REST] ✗ $Side $Method $maskedUri → $status"
            }
            
            # Fallback to curl for connection issues when SkipCertificateCheck is enabled
            # PowerShell's Invoke-RestMethod sometimes fails with SSL even with -SkipCertificateCheck
            $isConnectionError = $_.Exception.Message -match "connection was forcibly closed|Unable to read data from the transport|SSL|certificate"
            
            if ($script:SkipCertificateCheck -and $status -eq 0 -and $isConnectionError) {
                
                if ($attempt -eq 1) {
                    Write-Warning "[$Side] Invoke-RestMethod connection issue detected - falling back to curl"
                }
                
                try {
                    # Build curl command
                    $curlArgs = @('-k', '-s', '-X', $Method, '--max-time', '30')
                    
                    # Add headers
                    foreach ($key in $Headers.Keys) {
                        $curlArgs += '-H'
                        $curlArgs += "$key`: $($Headers[$key])"
                    }
                    
                    # Add body for POST/PUT/PATCH
                    if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
                        $curlArgs += '-H'
                        $curlArgs += 'Content-Type: application/json'
                        $curlArgs += '-d'
                        $curlArgs += $Body
                    }
                    
                    $curlArgs += $Uri
                    
                    if ($script:LogRestCalls) {
                        Write-Verbose "[REST] Using curl fallback: curl $($curlArgs -join ' ')"
                    }
                    
                    # Execute curl and filter progress output
                    $curlOutput = & curl @curlArgs 2>&1 | Where-Object { 
                        $_ -is [string] -and 
                        $_ -notmatch '^\s*%' -and 
                        $_ -notmatch '^\s*Total' -and 
                        $_ -notmatch '^\s*Dload' -and 
                        $_ -notmatch '^\s*0\s+0' -and 
                        $_ -notmatch '^\s*100\s+' -and
                        $_.Trim() -ne ''
                    }
                    
                    $jsonString = $curlOutput -join ''
                    
                    if ([string]::IsNullOrWhiteSpace($jsonString)) {
                        throw "Empty response from curl"
                    }
                    
                    $response = $jsonString | ConvertFrom-Json
                    
                    if ($script:LogRestCalls) {
                        Write-Verbose "[REST] ✓ $Side $Method (curl) → 200"
                    }
                    
                    return $response
                }
                catch {
                    Write-Verbose "[REST] curl fallback failed: $_"
                    # Fall through to normal error handling
                }
            }
            
            # Retry on transient failures
            $shouldRetry = $status -in @(429, 500, 502, 503, 504) -and $attempt -lt $maxAttempts
            
            if ($shouldRetry) {
                $delay = $script:RetryDelaySeconds * [Math]::Pow(2, $attempt - 1)
                Write-Warning "[$Side] HTTP $status - Retrying in ${delay}s (attempt $attempt/$maxAttempts)"
                Start-Sleep -Seconds $delay
            }
            else {
                # Final failure or non-retryable error
                $maskedEndpoint = $normalizedError.endpoint
                Write-Error "[$Side] ✗ REST $Method $maskedEndpoint → HTTP $status : $($normalizedError.message)"
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
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Pat
    )
    
    $pair = ":$Pat"
    $bytes = [Text.Encoding]::ASCII.GetBytes($pair)
    
    @{
        Authorization = "Basic $([Convert]::ToBase64String($bytes))"
        'Content-Type' = "application/json"
    }
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
        
        [switch]$Preview
    )
    
    $api = if ($Preview) { "$script:AdoApiVersion-preview.1" } else { $script:AdoApiVersion }
    
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
    
    $uri = $script:CollectionUrl.TrimEnd('/') + $Path + $queryString
    
    if ($null -ne $Body -and ($Body -isnot [string])) {
        $Body = ($Body | ConvertTo-Json -Depth 100)
    }
    
    return Invoke-RestWithRetry -Method $Method -Uri $uri -Headers $script:AdoHeaders -Body $Body -Side 'ado'
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
        throw "GitLab token not set. Call Initialize-CoreRest first."
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
    'Get-CoreRestVersion',
    'Get-GitLabToken',
    'Hide-Secret',
    'New-AuthHeader',
    'Invoke-AdoRest',
    'Invoke-GitLabRest',
    'Clear-GitCredentials'
)
