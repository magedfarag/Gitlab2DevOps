<#
.SYNOPSIS
    Core REST API helpers for GitLab and Azure DevOps communication.

.DESCRIPTION
    This module provides foundational REST API functions used by both GitLab
    and Azure DevOps modules. Includes authentication, HTTP request wrappers,
    and common utilities.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Author: Migration Team
    Version: 2.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Module-level variables (set by Initialize-CoreRest)
$script:CollectionUrl = $null
$script:AdoPat = $null
$script:GitLabBaseUrl = $null
$script:GitLabToken = $null
$script:AdoApiVersion = $null
$script:SkipCertificateCheck = $false
$script:AdoHeaders = $null

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

.EXAMPLE
    Initialize-CoreRest -CollectionUrl "https://dev.azure.com/org" -AdoPat $pat
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
        
        [switch]$SkipCertificateCheck
    )
    
    $script:CollectionUrl = $CollectionUrl
    $script:AdoPat = $AdoPat
    $script:GitLabBaseUrl = $GitLabBaseUrl
    $script:GitLabToken = $GitLabToken
    $script:AdoApiVersion = $AdoApiVersion
    $script:SkipCertificateCheck = $SkipCertificateCheck
    
    # Initialize ADO headers
    $script:AdoHeaders = New-AuthHeader -Pat $AdoPat
    
    Write-Verbose "[Core.Rest] Module initialized"
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
    authentication, and API versioning.

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
    
    $invokeParams = @{
        Method  = $Method
        Uri     = $uri
        Headers = $script:AdoHeaders
        Body    = $Body
    }
    
    if ($script:SkipCertificateCheck) {
        $invokeParams.SkipCertificateCheck = $true
    }
    
    try {
        $response = Invoke-RestMethod @invokeParams
        Write-Verbose "[ADO REST] $Method $Path -> SUCCESS"
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDesc = $_.Exception.Response.StatusDescription
        Write-Host "[ERROR] ADO REST $Method $Path -> HTTP $statusCode $statusDesc" -ForegroundColor Red
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
    
    try {
        Invoke-RestMethod @invokeParams
    }
    catch {
        # If GitLab returns a structured error (JSON), surface it more clearly
        $resp = $_.Exception.Response
        if ($null -ne $resp) {
            try {
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $body = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            catch {
                $body = $null
            }
            $status = $resp.StatusCode.value__ 2>$null
            $statusText = $resp.StatusDescription 2>$null
            $msg = if ($body -and $body.message) { $body.message } else { $body }
            throw "GitLab API error GET $uri -> HTTP $status $statusText : $msg"
        }
        throw
    }
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
        $input = "url=$remoteUrl`n`n"
        $input | git credential reject 2>$null
        
        Write-Host "[INFO] Credentials cleared successfully"
    }
    else {
        Write-Verbose "[Core.Rest] Remote '$RemoteName' not found, skipping credential cleanup"
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Initialize-CoreRest',
    'New-AuthHeader',
    'Invoke-AdoRest',
    'Invoke-GitLabRest',
    'Clear-GitCredentials'
)
