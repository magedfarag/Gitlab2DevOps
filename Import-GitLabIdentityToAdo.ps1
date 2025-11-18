<#
.SYNOPSIS
    Import GitLab identity data into Azure DevOps Server.

.DESCRIPTION
    This script imports previously exported GitLab users, groups, and memberships
    into Azure DevOps Server. It creates AD groups, adds users, and configures
    Azure DevOps project groups with proper nesting and permissions.

.PARAMETER ExportFolder
    Directory containing the exported JSON files from Export-GitLabIdentity.ps1.

.PARAMETER AdoProjectName
    Azure DevOps project name to import identity data into.

.PARAMETER AdGroupPrefix
    Prefix for Active Directory groups (default: "ADO").

.PARAMETER AdoGroupPrefix
    Prefix for Azure DevOps groups (default: "GitLab-Migrated").

.PARAMETER WhatIf
    Preview what would be imported without making changes.

.EXAMPLE
    .\Import-GitLabIdentityToAdo.ps1 -ExportFolder ".\exports" -AdoProjectName "MyProject"

.NOTES
    Requires: Core.Rest, AzureDevOps modules
    Must be run with appropriate AD and Azure DevOps permissions
    Part of Gitlab2DevOps migration toolkit
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExportFolder,

    [Parameter(Mandatory = $true)]
    [string]$AdoProjectName,

    [Parameter(Mandatory = $false)]
    [string]$AdGroupPrefix = "ADO",

    [Parameter(Mandatory = $false)]
    [string]$AdoGroupPrefix = "GitLab-Migrated",

    [switch]$WhatIf
)

# Import required modules
$scriptRoot = Split-Path $PSScriptRoot -Parent
$coreRestPath = Join-Path $scriptRoot "modules\core\Core.Rest.psm1"
$azureDevOpsPath = Join-Path $scriptRoot "modules\AzureDevOps\AzureDevOps.psm1"
$loggingPath = Join-Path $scriptRoot "modules\core\Logging.psm1"

foreach ($module in @($coreRestPath, $azureDevOpsPath, $loggingPath)) {
    if (Test-Path $module) {
        Import-Module $module -Force -ErrorAction Stop
    }
}

# Import ActiveDirectory module
Import-Module ActiveDirectory -ErrorAction Stop

# Initialize Core.Rest
try {
    Initialize-CoreRest
} catch {
    Write-Warning "Failed to initialize Core.Rest: $_"
}

# Helper functions
function ConvertTo-SafeName {
    param([Parameter(Mandatory)][string]$Name)
    $safe = $Name -replace "[\\\/:;@#\*\?\[\]\|<>""']", "_"
    $safe = $safe.Trim()
    return $safe
}

function Map-GitLabRoleToAdoBaseGroup {
    param([Parameter(Mandatory)][string]$GitLabRole)

    switch ($GitLabRole.ToLower()) {
        "guest" { return "Readers" }
        "reporter" { return "Readers" }
        "developer" { return "Contributors" }
        "maintainer" { return "Contributors" }
        "owner" { return "Project Administrators" }
        default { return "Contributors" }
    }
}

function Find-AdoGraphSubject {
    param(
        [Parameter(Mandatory)][string]$SearchTerm,
        [ValidateSet("user","group")][string]$SubjectType = "user"
    )

    $subjectTypes = if ($SubjectType -eq "user") { "user" } else { "group" }

    try {
        $relUrl = "/_apis/graph/$subjectTypes`?search=$([uri]::EscapeDataString($SearchTerm))&api-version=7.0-preview.1"
        $data = Invoke-AdoRest GET $relUrl
        return $data.value | Select-Object -First 1
    } catch {
        Write-Verbose "Failed to find ADO graph subject '$SearchTerm': $_"
        return $null
    }
}

function Add-AdoGroupMember {
    param(
        [Parameter(Mandatory)][string]$MemberDescriptor,
        [Parameter(Mandatory)][string]$ContainerDescriptor
    )

    if ($WhatIf) {
        Write-Host "[WHATIF] Would add member to ADO group" -ForegroundColor Yellow
        return
    }

    try {
        $relUrl = "/_apis/graph/memberships/$MemberDescriptor/$ContainerDescriptor`?api-version=7.0-preview.1"
        Invoke-AdoRest PUT $relUrl -Body $null -ExpectNoContent | Out-Null
    } catch {
        Write-Warning "Failed to add member to ADO group: $_"
    }
}

function Ensure-AdGroupWithMembers {
    param(
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][string]$OuDn,
        [Parameter(Mandatory)][string[]]$UserPrincipalNames
    )

    $safeName = ConvertTo-SafeName -Name $GroupName

    $group = Get-ADGroup -Filter "Name -eq '$safeName'" -ErrorAction SilentlyContinue
    if (-not $group) {
        if ($WhatIf) {
            Write-Host "[WHATIF] Would create AD group: $safeName in $OuDn" -ForegroundColor Yellow
        } else {
            Write-Host "[INFO] Creating AD group: $safeName" -ForegroundColor Cyan
            $group = New-ADGroup -Name $safeName `
                                 -SamAccountName $safeName `
                                 -GroupScope Global `
                                 -GroupCategory Security `
                                 -Path $OuDn `
                                 -ErrorAction Stop
        }
    } else {
        Write-Host "[INFO] AD group exists: $safeName" -ForegroundColor DarkGray
    }

    foreach ($upn in $UserPrincipalNames | Sort-Object -Unique) {
        if ([string]::IsNullOrWhiteSpace($upn)) { continue }

        try {
            $user = Get-ADUser -Filter "UserPrincipalName -eq '$upn'" -ErrorAction Stop
        } catch {
            Write-Warning "AD user not found for UPN: $upn"
            continue
        }

        if ($WhatIf) {
            Write-Host "[WHATIF] Would add user $upn to group $safeName" -ForegroundColor Yellow
        } else {
            $isMember = (Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.DistinguishedName -eq $user.DistinguishedName })
            if (-not $isMember) {
                Write-Host "[INFO] Adding $upn to AD group $safeName" -ForegroundColor Green
                Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
            }
        }
    }

    return $group
}

function Get-AdoProjectByName {
    param([Parameter(Mandatory)][string]$ProjectName)

    try {
        $relUrl = "/_apis/projects`?api-version=7.0"
        $data = Invoke-AdoRest GET $relUrl
        $project = $data.value | Where-Object { $_.name -eq $ProjectName }
        return $project
    } catch {
        Write-Warning "Failed to find ADO project '$ProjectName': $_"
        return $null
    }
}

function Get-AdoProjectGroup {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$GroupDisplayName
    )

    try {
        $relUrl = "/_apis/projects/$ProjectId/groups`?api-version=7.0-preview.1"
        $data = Invoke-AdoRest GET $relUrl
        $grp = $data.value | Where-Object { $_.displayName -eq $GroupDisplayName }
        return $grp
    } catch {
        Write-Warning "Failed to find ADO project group '$GroupDisplayName': $_"
        return $null
    }
}

function Ensure-AdoCustomProjectGroup {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$CustomGroupName,
        [string]$Description = ""
    )

    try {
        # Get project descriptor
        $relProjectGraph = "/_apis/graph/descriptors/$ProjectId`?api-version=7.0-preview.1"
        $projectDescInfo = Invoke-AdoRest GET $relProjectGraph
        $projectDescriptor = $projectDescInfo.value

        # Search existing groups
        $searchUrl = "/_apis/graph/groups`?scopeDescriptor=$projectDescriptor&subjectTypes=group&api-version=7.0-preview.1"
        $groups = Invoke-AdoRest GET $searchUrl

        $existing = $groups.value | Where-Object { $_.displayName -eq $CustomGroupName }
        if ($existing) {
            return $existing
        }

        if ($WhatIf) {
            Write-Host "[WHATIF] Would create ADO project group: $CustomGroupName" -ForegroundColor Yellow
            return $null
        }

        $body = @{
            scopeDescriptor = $projectDescriptor
            displayName = $CustomGroupName
            description = $Description
        }

        $createUrl = "/_apis/graph/groups`?api-version=7.0-preview.1"
        $newGroup = Invoke-AdoRest POST $createUrl -Body $body

        return $newGroup
    } catch {
        Write-Warning "Failed to create ADO project group '$CustomGroupName': $_"
        return $null
    }
}

# Main script
try {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       GitLab Identity Import to Azure DevOps            ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    if ($WhatIf) {
        Write-Host "[WHATIF] Preview mode - no changes will be made" -ForegroundColor Yellow
        Write-Host ""
    }

    # Validate export folder
    if (-not (Test-Path $ExportFolder)) {
        throw "Export folder not found: $ExportFolder"
    }

    $usersFile = Join-Path $ExportFolder 'users.json'
    $groupsFile = Join-Path $ExportFolder 'groups.json'
    $groupMembershipsFile = Join-Path $ExportFolder 'group-memberships.json'

    if (-not (Test-Path $usersFile) -or -not (Test-Path $groupsFile)) {
        throw "Required files not found in $ExportFolder. Expected: users.json, groups.json"
    }

    Write-Host "[INFO] Loading exported data from: $ExportFolder" -ForegroundColor Cyan

    # Load data
    Write-Progress -Activity "Importing GitLab Identity" -Status "Loading exported data..." -PercentComplete 0 -Id 2

    $users = Get-Content $usersFile -Raw | ConvertFrom-Json
    $groups = Get-Content $groupsFile -Raw | ConvertFrom-Json
    $groupMemberships = @()
    if (Test-Path $groupMembershipsFile) {
        $groupMemberships = Get-Content $groupMembershipsFile -Raw | ConvertFrom-Json
    }

    Write-Host "[INFO] Loaded $($users.Count) users, $($groups.Count) groups, $($groupMemberships.Count) group memberships" -ForegroundColor Green

    # Get AD OU for groups (this should be configurable)
    $adOuDn = $env:AD_GROUP_OU_DN
    if (-not $adOuDn) {
        $adOuDn = Read-Host "Enter AD OU DN for groups (e.g., OU=DevOps,OU=Groups,DC=corp,DC=local)"
        if ([string]::IsNullOrWhiteSpace($adOuDn)) {
            throw "AD OU DN is required"
        }
    }

    # Verify ADO project exists
    Write-Progress -Activity "Importing GitLab Identity" -Status "Verifying Azure DevOps project..." -PercentComplete 10 -Id 2

    $adoProject = Get-AdoProjectByName -ProjectName $AdoProjectName
    if (-not $adoProject) {
        throw "Azure DevOps project '$AdoProjectName' not found"
    }

    $projectId = $adoProject.id
    Write-Host "[INFO] Found Azure DevOps project: $AdoProjectName (ID: $projectId)" -ForegroundColor Green

    # Process group memberships
    Write-Progress -Activity "Importing GitLab Identity" -Status "Processing group memberships..." -PercentComplete 20 -Id 2

    $processedGroups = 0
    $totalGroups = $groupMemberships.Count

    foreach ($gm in $groupMemberships) {
        $processedGroups++
        $progress = 20 + [Math]::Floor(($processedGroups / $totalGroups) * 70)
        Write-Progress -Activity "Importing GitLab Identity" -Status "Processing group $($processedGroups)/$totalGroups..." -PercentComplete $progress -Id 2

        $groupFullPath = $gm.group_full_path
        $members = $gm.members

        if (-not $members -or $members.Count -eq 0) {
            Write-Verbose "No members for group: $groupFullPath"
            continue
        }

        # Group users by access level
        $roleGroups = $members | Where-Object { $_.type -eq 'user' } | Group-Object access_level_name

        foreach ($roleGroup in $roleGroups) {
            $gitlabRole = $roleGroup.Name
            $userMembers = $roleGroup.Group

            $baseAdoGroupName = Map-GitLabRoleToAdoBaseGroup -GitLabRole $gitlabRole

            # Create AD group name
            $adGroupName = "$AdGroupPrefix-$AdoProjectName-$groupFullPath-$baseAdoGroupName"
            $adGroupName = ConvertTo-SafeName -Name $adGroupName

            # Get UPNs for users
            $userUpns = @()
            foreach ($member in $userMembers) {
                $user = $users | Where-Object { $_.id -eq $member.id } | Select-Object -First 1
                if ($user -and $user.email) {
                    $userUpns += $user.email
                }
            }

            if ($userUpns.Count -eq 0) {
                Write-Verbose "No valid UPNs found for group: $adGroupName"
                continue
            }

            Write-Host "[INFO] Processing group: $adGroupName ($($userUpns.Count) users)" -ForegroundColor Cyan

            # 1. Ensure AD group and add members
            $adGroup = Ensure-AdGroupWithMembers -GroupName $adGroupName -OuDn $adOuDn -UserPrincipalNames $userUpns

            # 2. Find built-in ADO project group
            $builtInGroup = Get-AdoProjectGroup -ProjectId $projectId -GroupDisplayName $baseAdoGroupName
            if (-not $builtInGroup) {
                Write-Warning "Built-in project group '$baseAdoGroupName' not found in project '$AdoProjectName'"
                continue
            }

            # 3. Ensure custom ADO project group
            $customGroupName = "$AdoGroupPrefix-$AdoProjectName-$groupFullPath-$baseAdoGroupName"
            $customGroupName = ConvertTo-SafeName -Name $customGroupName

            $adoCustomGroup = Ensure-AdoCustomProjectGroup -ProjectId $projectId -CustomGroupName $customGroupName `
                -Description "Migrated from GitLab group '$groupFullPath' role '$gitlabRole'"

            if (-not $adoCustomGroup) {
                Write-Warning "Failed to create custom ADO group: $customGroupName"
                continue
            }

            # 4. Nest custom group into built-in group
            $builtInDesc = $builtInGroup.descriptor
            $customDesc = $adoCustomGroup.descriptor

            Write-Host "[INFO] Nesting custom group into '$baseAdoGroupName'" -ForegroundColor Cyan
            Add-AdoGroupMember -MemberDescriptor $customDesc -ContainerDescriptor $builtInDesc

            # 5. Add AD group to custom ADO group
            if ($adGroup) {
                $adoAdGroupSubject = Find-AdoGraphSubject -SearchTerm $adGroup.Name -SubjectType "group"
                if ($adoAdGroupSubject) {
                    $adGroupDesc = $adoAdGroupSubject.descriptor
                    Write-Host "[INFO] Adding AD group to custom ADO group" -ForegroundColor Cyan
                    Add-AdoGroupMember -MemberDescriptor $adGroupDesc -ContainerDescriptor $customDesc
                } else {
                    Write-Warning "Could not find AD group '$($adGroup.Name)' in ADO Graph"
                }
            }
        }
    }

    Write-Progress -Activity "Importing GitLab Identity" -Status "Import completed!" -PercentComplete 100 -Id 2 -Completed

    Write-Host ""
    Write-Host "[SUCCESS] GitLab identity import completed!" -ForegroundColor Green
    Write-Host "[INFO] Processed $($groupMemberships.Count) group memberships" -ForegroundColor Cyan

    if ($WhatIf) {
        Write-Host "[INFO] This was a preview. Use without -WhatIf to perform actual import." -ForegroundColor Yellow
    }

} catch {
    Write-Host "[ERROR] Import failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Progress -Activity "Importing GitLab Identity" -Status "Import failed!" -Id 2 -Completed
    throw
}</content>
<parameter name="filePath">c:\Projects\devops\Gitlab2DevOps\Import-GitLabIdentityToAdo.ps1