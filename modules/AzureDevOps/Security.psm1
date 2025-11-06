<#
.SYNOPSIS
    Security groups and permissions management

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Get-AdoBuiltInGroupDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjDesc,
        
        [Parameter(Mandatory)]
        [string]$GroupName
    )
    
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&``$top=200"
    ($groups.value | Where-Object { $_.principalName -like "*\[$GroupName]" }).descriptor
}

#>
function Ensure-AdoGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjDesc,
        
        [Parameter(Mandatory)]
        [string]$DisplayName
    )
    
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&``$top=200"
    $existing = $groups.value | Where-Object { $_.displayName -eq $DisplayName }
    
    if ($existing) {
        Write-Verbose "[AzureDevOps] Group '$DisplayName' already exists"
        return $existing
    }
    
    Write-Host "[INFO] Creating group '$DisplayName'"
    Invoke-AdoRest POST "/_apis/graph/groups" -Body @{
        displayName     = $DisplayName
        description     = "Auto-provisioned group: $DisplayName"
        scopeDescriptor = $ProjDesc
    }
}

#>
function Ensure-AdoMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Container,
        
        [Parameter(Mandatory)]
        [string]$Member
    )
    
    try {
        Invoke-AdoRest PUT "/_apis/graph/memberships/$Member/$Container"
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Verbose "[AzureDevOps] Membership already exists"
        }
        else {
            throw
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-AdoBuiltInGroupDescriptor',
    'Ensure-AdoGroup',
    'Ensure-AdoMembership'
)
