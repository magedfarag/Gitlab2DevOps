<#
.SYNOPSIS
    Security groups and permissions management

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
    
    Uses Core Teams REST API instead of Graph API for better on-premise compatibility.
    Microsoft docs confirm Graph API is unreliable for on-premise servers.
    
    RBAC Configuration: Manual UI configuration recommended for on-premise servers
    - Graph REST API: Unconfirmed for on-premise (only cloud examples in docs)
    - TFSSecurity: Requires server admin access
    - az devops CLI: Cloud-only
    - Manual UI: Most reliable for all environments
#>

# Helper: Create team (security group) if missing
function New-AdoTeamIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [string]$TeamName,
        [string]$Description = "Created by migration toolkit"
    )
    if ([string]::IsNullOrWhiteSpace($Project) -or [string]::IsNullOrWhiteSpace($TeamName)) {
        Write-Warning "[Security] Project or TeamName is empty. Cannot create team."
        return $false
    }
    $projEnc = [uri]::EscapeDataString($Project)
    $teamEnc = [uri]::EscapeDataString($TeamName)
    try {
        $teams = Invoke-AdoRest GET "/_apis/projects/$projEnc/teams"
        if ($teams.value | Where-Object { $_.name -eq $TeamName }) {
            Write-Verbose "[Security] Team '$TeamName' already exists in project '$Project'"
            return $true
        }
        $body = @{ name = $TeamName; description = $Description }
        $result = Invoke-AdoRest POST "/_apis/projects/$projEnc/teams" -Body $body
        Write-Host "[INFO] Created team '$TeamName' in project '$Project'" -ForegroundColor Green
        return $result
    } catch {
        Write-Warning "[Security] Failed to create team '$TeamName' in project '$Project': $_"
        return $false
    }
}

#Requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Get-AdoSecurityGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )
    
    # Use Security API (vssps) instead of Graph API for better on-premise compatibility
    # This works on both cloud and on-premise servers
    $projEnc = [uri]::EscapeDataString($Project)
    try {
        $groups = Invoke-AdoRest GET "/_apis/projects/$projEnc/teams"
        return $groups.value
    }
    catch {
        Write-Verbose "[Security] Failed to retrieve security groups: $_"
        return @()
    }
}

#>
function Get-AdoTeamMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$TeamName
    )
    
    # Use Core Teams API - works on both cloud and on-premise
    if ([string]::IsNullOrWhiteSpace($Project) -or [string]::IsNullOrWhiteSpace($TeamName)) {
        Write-Warning "[Security] Project or TeamName is empty. Cannot get team members."
        return @()
    }
    $projEnc = [uri]::EscapeDataString($Project)
    $teamEnc = [uri]::EscapeDataString($TeamName)
    try {
        $members = Invoke-AdoRest GET "/_apis/projects/$projEnc/teams/$teamEnc/members"
        return $members.value
    }
    catch {
        Write-Verbose "[Security] Failed to retrieve team members: $_"
        return @()
    }
}

#>
function Add-Adoteammember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$TeamName,
        
        [Parameter(Mandatory)]
        [string]$UserEmail
    )
    
    # Add member to team using Security API (not Graph API)
    # This approach works on both cloud and on-premise servers
    if ([string]::IsNullOrWhiteSpace($Project) -or [string]::IsNullOrWhiteSpace($TeamName) -or [string]::IsNullOrWhiteSpace($UserEmail)) {
        Write-Warning "[Security] Project, TeamName, or UserEmail is empty. Cannot add team member."
        return
    }
    $projEnc = [uri]::EscapeDataString($Project)
    $teamEnc = [uri]::EscapeDataString($TeamName)
    try {
        # First, get the team object
        $team = Invoke-AdoRest GET "/_apis/projects/$projEnc/teams/$teamEnc"
        $teamId = $null
        if ($team -and $team.PSObject.Properties['id']) {
            $teamId = $team.id
        } elseif ($team -is [System.Collections.IDictionary] -and $team.ContainsKey('id')) {
            $teamId = $team['id']
        }
        if (-not $teamId -or [string]::IsNullOrWhiteSpace($teamId)) {
            Write-Warning "[Security] Could not resolve team ID for '$TeamName' in project '$Project'. Skipping member assignment and REST call."
            # Defensive: Do NOT build or call REST API with empty/malformed teamId
            # Fallback: Add user to Readers group at collection level
            Write-Warning "[Security] Team ID not found for '$TeamName'. Adding $UserEmail to Readers group at collection level."
            $readersGroupName = "Readers"
            $readersGroup = Get-AdoSecurityGroups -Project $Project | Where-Object { $_.name -eq $readersGroupName }
            if ($readersGroup -and $readersGroup.PSObject.Properties['id'] -and -not [string]::IsNullOrWhiteSpace($readersGroup.id)) {
                $readersGroupId = $readersGroup.id
                $body = @{ userPrincipalName = $UserEmail }
                $readersApiUrl = "/_apis/teams/$readersGroupId/members"
                $readersApiUrl = $readersApiUrl -replace '\?api-version=.*$', ''
                try {
                    Invoke-AdoRest POST $readersApiUrl -Body $body
                    Write-Host "[SUCCESS] Added $UserEmail to Readers group (collection-level)" -ForegroundColor Green
                } catch {
                    Write-Warning "[Security] Failed to add $UserEmail to Readers group: $_"
                }
            } else {
                Write-Warning "[Security] Could not find Readers group in project '$Project'. User $UserEmail not added."
            }
            return
        }
        # Add user to Contributors group (team members are added via security groups)
        $body = @{ userPrincipalName = $UserEmail }
        if ([string]::IsNullOrWhiteSpace($teamId)) {
            Write-Warning "[Security] Refusing to build REST API URL with empty or invalid teamId for '$TeamName'. Skipping REST call."
            return
        }
        $teamApiUrl = "/_apis/teams/$teamId/members"
        $teamApiUrl = $teamApiUrl -replace '\?api-version=.*$', '' # Remove any accidental api-version
        Invoke-AdoRest POST $teamApiUrl -Body $body
        Write-Host "[SUCCESS] Added $UserEmail to team $TeamName" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -match '409|already exists|AlreadyExists') {
            Write-Verbose "[Security] User $UserEmail is already a member of team $TeamName"
        }
        else {
            Write-Warning "[Security] Failed to add $UserEmail to team $TeamName : $_"
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-AdoSecurityGroups',
    'Get-AdoTeamMembers',
    'Add-Adoteammember',
    'New-AdoTeamIfMissing'
)
