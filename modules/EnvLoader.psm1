<#
.SYNOPSIS
    Loads configuration from .env files.

.DESCRIPTION
    Provides functionality to read .env files and populate environment variables
    or return a configuration hashtable. Supports:
    - Standard KEY=VALUE format
    - Comments (lines starting with #)
    - Empty lines
    - Quoted values (single or double quotes)
    - Variable expansion using ${VAR} syntax
    - Multiple .env files with priority

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 1.0.0
    
.EXAMPLE
    Import-DotEnvFile -Path ".env"
    
.EXAMPLE
    $config = Import-DotEnvFile -Path ".env" -AsHashtable
    
.EXAMPLE
    Import-DotEnvFile -Path @(".env", ".env.local") -SetEnvironmentVariables
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Imports configuration from .env file(s).

.DESCRIPTION
    Reads .env files and either sets environment variables or returns a configuration hashtable.
    Files are processed in order, with later files overriding earlier ones.

.PARAMETER Path
    Path(s) to .env file(s). Can be a single file or array of files.

.PARAMETER SetEnvironmentVariables
    If specified, sets environment variables for the current process.
    Default is to only return a hashtable.

.PARAMETER AsHashtable
    Returns configuration as a hashtable instead of setting environment variables.
    This is the default behavior when SetEnvironmentVariables is not specified.

.PARAMETER AllowOverwrite
    When setting environment variables, allow overwriting existing ones.
    Default is to preserve existing environment variables.

.PARAMETER Encoding
    File encoding to use when reading .env files.
    Default is UTF8.

.OUTPUTS
    Hashtable of configuration key-value pairs.

.EXAMPLE
    # Load .env file and return as hashtable
    $config = Import-DotEnvFile -Path ".env"
    Write-Host "GitLab URL: $($config.GITLAB_BASE_URL)"

.EXAMPLE
    # Load .env file and set environment variables
    Import-DotEnvFile -Path ".env" -SetEnvironmentVariables
    Write-Host "GitLab URL: $env:GITLAB_BASE_URL"

.EXAMPLE
    # Load multiple files with priority (.env.local overrides .env)
    Import-DotEnvFile -Path @(".env", ".env.local") -SetEnvironmentVariables

.EXAMPLE
    # Allow overwriting existing environment variables
    Import-DotEnvFile -Path ".env" -SetEnvironmentVariables -AllowOverwrite
#>
function Import-DotEnvFile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,
        
        [switch]$SetEnvironmentVariables,
        
        [switch]$AsHashtable,
        
        [switch]$AllowOverwrite,
        
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )
    
    $config = @{}
    
    foreach ($filePath in $Path) {
        if (-not (Test-Path $filePath)) {
            Write-Warning "[EnvLoader] File not found: $filePath"
            continue
        }
        
        Write-Verbose "[EnvLoader] Loading: $filePath"
        
        try {
            $lines = Get-Content -Path $filePath -Encoding $Encoding -ErrorAction Stop
            
            foreach ($line in $lines) {
                # Skip empty lines and comments
                if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
                    continue
                }
                
                # Parse KEY=VALUE
                if ($line -match '^([^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    # Remove quotes if present
                    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                        $value = $value.Substring(1, $value.Length - 2)
                    }
                    
                    # Variable expansion: replace ${VAR} or $VAR with values
                    $value = Expand-EnvVariables -Value $value -Config $config
                    
                    $config[$key] = $value
                    Write-Verbose "[EnvLoader] Loaded: $key"
                }
            }
            
            Write-Host "[EnvLoader] Successfully loaded: $filePath" -ForegroundColor Green
            
        } catch {
            Write-Warning "[EnvLoader] Failed to read $filePath : $_"
        }
    }
    
    # Set environment variables if requested
    if ($SetEnvironmentVariables) {
        foreach ($key in $config.Keys) {
            $existingValue = [Environment]::GetEnvironmentVariable($key, [EnvironmentVariableTarget]::Process)
            
            if ($null -ne $existingValue -and -not $AllowOverwrite) {
                Write-Verbose "[EnvLoader] Skipping $key (already set)"
                continue
            }
            
            [Environment]::SetEnvironmentVariable($key, $config[$key], [EnvironmentVariableTarget]::Process)
            Write-Verbose "[EnvLoader] Set environment variable: $key"
        }
        
        Write-Host "[EnvLoader] Environment variables updated: $($config.Count) variables" -ForegroundColor Cyan
    }
    
    return $config
}

<#
.SYNOPSIS
    Expands variables within a value string.

.DESCRIPTION
    Internal helper function to expand ${VAR} and $VAR references in values.

.PARAMETER Value
    The value string to expand.

.PARAMETER Config
    Current configuration hashtable for variable lookup.

.OUTPUTS
    Expanded string value.
#>
function Expand-EnvVariables {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Value,
        
        [hashtable]$Config
    )
    
    # Expand ${VAR} syntax
    $result = $Value -replace '\$\{([^}]+)\}', {
        param($match)
        $varName = $match.Groups[1].Value
        
        # Check config first, then environment
        if ($Config.ContainsKey($varName)) {
            return $Config[$varName]
        }
        
        $envValue = [Environment]::GetEnvironmentVariable($varName, [EnvironmentVariableTarget]::Process)
        if ($null -ne $envValue) {
            return $envValue
        }
        
        # Return original if not found
        return $match.Value
    }
    
    # Expand $VAR syntax (simple variables)
    $result = $result -replace '\$([A-Za-z_][A-Za-z0-9_]*)', {
        param($match)
        $varName = $match.Groups[1].Value
        
        # Check config first, then environment
        if ($Config.ContainsKey($varName)) {
            return $Config[$varName]
        }
        
        $envValue = [Environment]::GetEnvironmentVariable($varName, [EnvironmentVariableTarget]::Process)
        if ($null -ne $envValue) {
            return $envValue
        }
        
        # Return original if not found
        return $match.Value
    }
    
    return $result
}

<#
.SYNOPSIS
    Creates a template .env file with common configuration options.

.DESCRIPTION
    Generates a .env.example or .env file with all supported configuration options
    and helpful comments.

.PARAMETER Path
    Path where the template file should be created.
    Default is ".env.example".

.PARAMETER Force
    Overwrite existing file if it exists.

.EXAMPLE
    New-DotEnvTemplate
    
.EXAMPLE
    New-DotEnvTemplate -Path ".env" -Force
#>
function New-DotEnvTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = ".env.example",
        
        [switch]$Force
    )
    
    if ((Test-Path $Path) -and -not $Force) {
        Write-Warning "[EnvLoader] File already exists: $Path (use -Force to overwrite)"
        return
    }
    
    $template = @"
# ============================
# GitLab to Azure DevOps Migration Configuration
# ============================
# Copy this file to .env and fill in your values
# IMPORTANT: Never commit .env files with real credentials to version control!

# Azure DevOps Configuration
# ---------------------------
# Your Azure DevOps organization URL
# On-premise example: https://devops.example.com/DefaultCollection
# Cloud example: https://dev.azure.com/your-organization
ADO_COLLECTION_URL=https://dev.azure.com/your-organization

# Azure DevOps Personal Access Token (PAT)
# Requires: Code (Read & Write), Project and Team (Read, Write & Manage)
# Generate at: {ADO_URL}/_usersSettings/tokens
ADO_PAT=your-azure-devops-pat-here

# Azure DevOps API Version (optional, default: 7.1)
# ADO_API_VERSION=7.1


# GitLab Configuration
# --------------------
# Your GitLab instance URL
# Cloud: https://gitlab.com
# Self-hosted: https://gitlab.example.com
GITLAB_BASE_URL=https://gitlab.com

# GitLab Personal Access Token (PAT)
# Requires: api, read_api, read_repository, write_repository scopes
# Generate at: {GITLAB_URL}/-/profile/personal_access_tokens
GITLAB_PAT=your-gitlab-pat-here


# Optional: Migration Settings
# -----------------------------
# Skip SSL certificate validation (not recommended for production)
# SKIP_CERTIFICATE_CHECK=false

# Default branch name for new repositories
# DEFAULT_BRANCH=main

# Git clone/push timeout in seconds
# GIT_TIMEOUT=600


# Optional: Telemetry Settings
# -----------------------------
# Enable telemetry collection (opt-in, local only)
# TELEMETRY_ENABLED=false

# Telemetry session name
# TELEMETRY_SESSION=Migration-\$(Get-Date -Format 'yyyyMMdd-HHmmss')


# Optional: Logging Settings
# ---------------------------
# Log level: Debug, Info, Warning, Error
# LOG_LEVEL=Info

# Log output directory
# LOG_DIR=./logs


# Variable Expansion Example
# --------------------------
# You can reference other variables using \${VAR} syntax
# FULL_API_URL=\${ADO_COLLECTION_URL}/_apis/projects
"@

    if ($PSCmdlet.ShouldProcess($Path, "Create .env template")) {
        try {
            $template | Out-File -FilePath $Path -Encoding UTF8 -Force
            Write-Host "[EnvLoader] Created template: $Path" -ForegroundColor Green
            Write-Host "[EnvLoader] Copy this to .env and fill in your credentials" -ForegroundColor Cyan
        } catch {
            Write-Error "[EnvLoader] Failed to create template: $_"
        }
    }
}

<#
.SYNOPSIS
    Validates that required configuration variables are present.

.DESCRIPTION
    Checks that all required configuration keys are present and not empty.

.PARAMETER Config
    Configuration hashtable to validate.

.PARAMETER RequiredKeys
    Array of required key names.

.OUTPUTS
    Boolean indicating whether all required keys are present.

.EXAMPLE
    $config = Import-DotEnvFile -Path ".env"
    if (-not (Test-DotEnvConfig -Config $config -RequiredKeys @('ADO_PAT', 'GITLAB_PAT'))) {
        Write-Error "Missing required configuration"
    }
#>
function Test-DotEnvConfig {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,
        
        [Parameter(Mandatory)]
        [string[]]$RequiredKeys
    )
    
    $allPresent = $true
    
    foreach ($key in $RequiredKeys) {
        if (-not $Config.ContainsKey($key)) {
            Write-Warning "[EnvLoader] Missing required configuration: $key"
            $allPresent = $false
        }
        elseif ([string]::IsNullOrWhiteSpace($Config[$key])) {
            Write-Warning "[EnvLoader] Empty required configuration: $key"
            $allPresent = $false
        }
    }
    
    return $allPresent
}

Export-ModuleMember -Function @(
    'Import-DotEnvFile',
    'New-DotEnvTemplate',
    'Test-DotEnvConfig'
)
