# ConfigLoader.psm1 - Load and validate configuration files

<#
.SYNOPSIS
    Loads Azure DevOps project settings from JSON configuration file.

.DESCRIPTION
    Reads project-settings.json and validates the configuration.
    Falls back to embedded defaults if file not found or invalid.

.PARAMETER ConfigFile
    Path to custom configuration file. If not provided, uses default config from module.

.EXAMPLE
    $config = Get-ProjectSettings
    # Returns default configuration

.EXAMPLE
    $config = Get-ProjectSettings -ConfigFile "my-settings.json"
    # Returns custom configuration
#>
function Get-ProjectSettings {
    [CmdletBinding()]
    param(
        [string]$ConfigFile
    )
    
    # Build absolute path: modules/core -> modules/AzureDevOps/config
    $modulesRoot = Split-Path $PSScriptRoot -Parent
    $defaultConfigPath = Join-Path $modulesRoot "AzureDevOps\config\project-settings.json"
    $configPath = if ($ConfigFile) { $ConfigFile } else { $defaultConfigPath }
    
    if (-not (Test-Path $configPath)) {
        Write-Warning "Configuration file not found: $configPath"
        Write-Warning "Using embedded defaults"
        return Get-DefaultProjectSettings
    }
    
    try {
        $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        
        # Validate required properties
        if (-not $config.areas -or $config.areas.Count -eq 0) {
            throw "Configuration must have at least one area defined"
        }
        if (-not $config.iterations) {
            throw "Configuration must have iterations defined"
        }
        if (-not $config.processTemplate) {
            throw "Configuration must have processTemplate defined"
        }
        
        Write-Verbose "[Get-ProjectSettings] Loaded configuration from: $configPath"
        return $config
    }
    catch {
        Write-Warning "Failed to load configuration from $configPath : $_"
        Write-Warning "Using embedded defaults"
        return Get-DefaultProjectSettings
    }
}

<#
.SYNOPSIS
    Loads branch policy settings from JSON configuration file.

.DESCRIPTION
    Reads branch-policies.json and validates the configuration.
    Falls back to embedded defaults if file not found or invalid.

.PARAMETER ConfigFile
    Path to custom configuration file. If not provided, uses default config from module.

.EXAMPLE
    $config = Get-BranchPolicySettings
    # Returns default configuration

.EXAMPLE
    $config = Get-BranchPolicySettings -ConfigFile "my-policies.json"
    # Returns custom configuration
#>
function Get-BranchPolicySettings {
    [CmdletBinding()]
    param(
        [string]$ConfigFile
    )
    
    # Build absolute path: modules/core -> modules/AzureDevOps/config
    $modulesRoot = Split-Path $PSScriptRoot -Parent
    $defaultConfigPath = Join-Path $modulesRoot "AzureDevOps\config\branch-policies.json"
    $configPath = if ($ConfigFile) { $ConfigFile } else { $defaultConfigPath }
    
    if (-not (Test-Path $configPath)) {
        Write-Warning "Configuration file not found: $configPath"
        Write-Warning "Using embedded defaults"
        return Get-DefaultBranchPolicySettings
    }
    
    try {
        $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        
        # Validate required properties
        if (-not $config.branchPolicies) {
            throw "Configuration must have branchPolicies defined"
        }
        
        Write-Verbose "[Get-BranchPolicySettings] Loaded configuration from: $configPath"
        return $config
    }
    catch {
        Write-Warning "Failed to load configuration from $configPath : $_"
        Write-Warning "Using embedded defaults"
        return Get-DefaultBranchPolicySettings
    }
}

<#
.SYNOPSIS
    Returns default project settings (embedded fallback).

.DESCRIPTION
    Provides hardcoded default configuration when JSON file is not available.
#>
function Get-DefaultProjectSettings {
    return @{
        areas = @(
            @{ name = "Frontend"; description = "User interface and client-side code" },
            @{ name = "Backend"; description = "Server-side logic and APIs" },
            @{ name = "Infrastructure"; description = "DevOps, CI/CD, and cloud infrastructure" },
            @{ name = "Documentation"; description = "Technical documentation and wiki content" }
        )
        iterations = @{
            sprintCount = 6
            sprintDurationDays = 14
            sprintPrefix = "Sprint"
        }
        processTemplate = "Agile"
        defaultRepository = @{
            defaultBranch = "main"
            initializeWithReadme = $true
        }
        team = @{
            defaultTeamSuffix = " Team"
        }
    }
}

<#
.SYNOPSIS
    Returns default branch policy settings (embedded fallback).

.DESCRIPTION
    Provides hardcoded default configuration when JSON file is not available.
#>
function Get-DefaultBranchPolicySettings {
    return @{
        branchPolicies = @{
            requiredReviewers = @{
                enabled = $true
                isBlocking = $true
                minimumApproverCount = 2
                creatorVoteCounts = $false
                allowDownvotes = $true
                resetOnSourcePush = $false
            }
            workItemLinking = @{
                enabled = $true
                isBlocking = $true
            }
            commentResolution = @{
                enabled = $true
                isBlocking = $true
            }
            buildValidation = @{
                enabled = $false
                isBlocking = $true
                buildDefinitionId = 0
                displayName = "CI validation"
                validDuration = 0
                queueOnSourceUpdateOnly = $false
            }
            statusCheck = @{
                enabled = $false
                isBlocking = $false
                statusName = ""
                statusGenre = "SonarQube"
                applicableFor = "refs/heads/main"
            }
            mergeStrategy = @{
                noFastForward = $true
                squash = $false
                rebase = $false
                rebaseMerge = $false
            }
        }
        repositorySecurity = @{
            denyGroups = @{
                BA = @{
                    denyDirectPush = $true
                    denyForcePush = $true
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Exports current project settings to a JSON file.

.DESCRIPTION
    Creates a JSON configuration file from a settings hashtable.
    Useful for creating custom configurations.

.PARAMETER Settings
    Hashtable containing project settings.

.PARAMETER OutputPath
    Path where JSON file will be written.

.EXAMPLE
    $settings = Get-DefaultProjectSettings
    $settings.areas += @{ name = "Mobile"; description = "Mobile apps" }
    Export-ProjectSettings -Settings $settings -OutputPath "custom-settings.json"
#>
function Export-ProjectSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    try {
        $json = $Settings | ConvertTo-Json -Depth 10
        Set-Content -Path $OutputPath -Value $json -Encoding UTF8
        Write-Host "[SUCCESS] Configuration exported to: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export configuration: $_"
    }
}

<#
.SYNOPSIS
    Exports branch policy settings to a JSON file.

.DESCRIPTION
    Creates a JSON configuration file from branch policy settings hashtable.

.PARAMETER Settings
    Hashtable containing branch policy settings.

.PARAMETER OutputPath
    Path where JSON file will be written.

.EXAMPLE
    $settings = Get-DefaultBranchPolicySettings
    $settings.branchPolicies.requiredReviewers.minimumApproverCount = 1
    Export-BranchPolicySettings -Settings $settings -OutputPath "custom-policies.json"
#>
function Export-BranchPolicySettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    try {
        $json = $Settings | ConvertTo-Json -Depth 10
        Set-Content -Path $OutputPath -Value $json -Encoding UTF8
        Write-Host "[SUCCESS] Configuration exported to: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to export configuration: $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProjectSettings',
    'Get-BranchPolicySettings',
    'Get-DefaultProjectSettings',
    'Get-DefaultBranchPolicySettings',
    'Export-ProjectSettings',
    'Export-BranchPolicySettings'
)
