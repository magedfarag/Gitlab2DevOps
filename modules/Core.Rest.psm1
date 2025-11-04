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
    $message = $Exception.Message
    
    if ($Exception.Exception.Response) {
        $status = [int]$Exception.Exception.Response.StatusCode.value__
        
        # Try to extract error message from response body
        try {
            $reader = New-Object System.IO.StreamReader($Exception.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $body = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($body.message) {
                $message = $body.message
            }
            elseif ($body.error) {
                $message = $body.error
            }
        }
        catch {
            # Keep original message
        }
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
            
            $response = Invoke-RestMethod @invokeParams
            
            if ($script:LogRestCalls) {
                Write-Verbose "[REST] $side $Method -> HTTP 200 OK"
            }
            
            return $response
        }
        catch {
            $normalizedError = New-NormalizedError -Exception $_ -Side $Side -Endpoint $Uri
            $status = $normalizedError.status
            
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
                Write-Error "[$Side] REST $Method $maskedEndpoint -> HTTP $status : $($normalizedError.message)"
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
    
    $queryString = if ($Path -like '*api-version=*') { '' } else { "?api-version=$api" }
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
    'Hide-Secret',
    'New-AuthHeader',
    'Invoke-AdoRest',
    'Invoke-GitLabRest',
    'Clear-GitCredentials'
)
