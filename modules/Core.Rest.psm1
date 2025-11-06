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
    Write-Verbose "[Core.Rest] SkipCertificateCheck: $($script:SkipCertificateCheck)"
    Write-Verbose "[Core.Rest] Retry: $RetryAttempts attempts, ${RetryDelaySeconds}s delay"
    Write-Host "[INFO] Core.Rest initialized - SkipCertificateCheck = $($script:SkipCertificateCheck)" -ForegroundColor Cyan
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
                    $curlArgs = @('-k', '-s', '-S', '-i', '-w', 'HTTP_CODE:%{http_code}', '-X', $Method, '--max-time', '30')
                    
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
                    catch {
                        Write-Warning "[$Side] Failed to parse JSON response: $_"
                        if ($script:LogRestCalls) {
                            Write-Verbose "[Core.Rest] JSON string (first 500 chars): $($jsonString.Substring(0, [Math]::Min(500, $jsonString.Length)))"
                        }
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
    'Get-SkipCertificateCheck',
    'Hide-Secret',
    'New-NormalizedError',
    'New-AuthHeader',
    'Invoke-RestWithRetry',
    'Invoke-AdoRest',
    'Invoke-GitLabRest',
    'Clear-GitCredentials'
)
