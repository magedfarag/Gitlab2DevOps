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
function Add-AdoTeamMember {
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
    $projEnc = [uri]::EscapeDataString($Project)
    $teamEnc = [uri]::EscapeDataString($TeamName)
    
    try {
        # First, get the team ID
        $team = Invoke-AdoRest GET "/_apis/projects/$projEnc/teams/$teamEnc"
        
        # Add user to Contributors group (team members are added via security groups)
        # Format: [ProjectName]\Contributors
        $groupName = "[$Project]\Contributors"
        
        # Use Security Namespace API to add member
        $body = @{
            userPrincipalName = $UserEmail
        }
        
        Invoke-AdoRest POST "/_apis/teams/$($team.id)/members" -Body $body
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
    'Add-AdoTeamMember'
)
