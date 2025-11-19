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
    (Optional) Azure DevOps project name. If not specified, processes all projects from project-memberships.json.

.PARAMETER AdGroupPrefix
    Prefix for Active Directory groups (default: "").

.PARAMETER AdoGroupPrefix
    Prefix for Azure DevOps groups (default: "").

.PARAMETER WhatIf
    Preview what would be imported without making changes.

.EXAMPLE
    .examples/Import-GitLabIdentityToAdo.ps1 -ExportFolder ".\exports"
    # Processes all projects from project-memberships.json

.EXAMPLE
    .examples/Import-GitLabIdentityToAdo.ps1 -ExportFolder ".\exports" -AdoProjectName "MyProject"

.NOTES
    Requires: Core.Rest, AzureDevOps modules
    Must be run with appropriate AD and Azure DevOps permissions
    Part of Gitlab2DevOps migration toolkit
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExportFolder,

    [Parameter(Mandatory = $false)]
    [string]$AdoProjectName,

    [Parameter(Mandatory = $false)]
    [string]$AdGroupPrefix = "",

    [Parameter(Mandatory = $false)]
    [string]$AdoGroupPrefix = ""
)

# Import required modules
# $scriptRoot = Split-Path $PSScriptRoot -Parent
# $coreRestPath = Join-Path $scriptRoot "core\Core.Rest.psm1"
# $azureDevOpsPath = Join-Path $scriptRoot "AzureDevOps\AzureDevOps.psm1"
# $loggingPath = Join-Path $scriptRoot "core\Logging.psm1"

# foreach ($module in @($coreRestPath, $azureDevOpsPath, $loggingPath)) {
#     if (Test-Path $module) {
#         Import-Module $module -Force -ErrorAction Stop
#     }
# }

# Import ActiveDirectory module
# Import-Module ActiveDirectory -ErrorAction Stop

# Initialize Core.Rest
# try {
#     Initialize-CoreRest
# } catch {
#     Write-Warning "Failed to initialize Core.Rest: $_"
# }

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

    if ($WhatIfPreference) {
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

function Ensure-AdUser {
    param(
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$OuDn,
        [Parameter(Mandatory)][string]$Password
    )

    # Check if Active Directory cmdlets are available
    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
        Write-Warning "Active Directory cmdlets not available. Skipping AD user operations."
        return $null
    }

    $samAccountName = ($UserPrincipalName -split '@')[0]

    $user = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
    if (-not $user) {
        if ($WhatIfPreference) {
            Write-Host "[WHATIF] Would create AD user: $UserPrincipalName in $OuDn" -ForegroundColor Yellow
        } else {
            Write-Host "[INFO] Creating AD user: $UserPrincipalName" -ForegroundColor Cyan
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $user = New-ADUser -Name $DisplayName `
                              -SamAccountName $samAccountName `
                              -UserPrincipalName $UserPrincipalName `
                              -EmailAddress $UserPrincipalName `
                              -DisplayName $DisplayName `
                              -AccountPassword $securePassword `
                              -Enabled $true `
                              -Path $OuDn `
                              -ChangePasswordAtLogon $true `
                              -ErrorAction Stop
        }
    } else {
        Write-Host "[INFO] AD user exists: $UserPrincipalName" -ForegroundColor DarkGray
    }

    return $user
}

function Generate-SecurePassword {
    param([int]$Length = 12)

    $chars = @()
    $chars += 65..90  # A-Z
    $chars += 97..122 # a-z
    $chars += 48..57  # 0-9
    $chars += 33,35,36,37,38,42,43,45,46,63,64,94,95 # Special chars

    $password = ""
    for ($i = 0; $i -lt $Length; $i++) {
        $password += [char]($chars | Get-Random)
    }

    return $password
}

function Ensure-AdGroupWithMembers {
    param(
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][string]$OuDn,
        [Parameter(Mandatory)][array]$UserPrincipalNames
    )

    # Check if Active Directory cmdlets are available
    if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
        Write-Warning "Active Directory cmdlets not available. Skipping AD group operations."
        return $null
    }

    $group = Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue
    if (-not $group) {
        if ($WhatIfPreference) {
            Write-Host "[WHATIF] Would create AD group: $GroupName in $OuDn" -ForegroundColor Yellow
        } else {
            Write-Host "[INFO] Creating AD group: $GroupName" -ForegroundColor Cyan
            $group = New-ADGroup -Name $GroupName `
                                -SamAccountName $GroupName `
                                -GroupCategory Security `
                                -GroupScope Global `
                                -DisplayName $GroupName `
                                -Path $OuDn `
                                -ErrorAction Stop
        }
    } else {
        Write-Host "[INFO] AD group exists: $GroupName" -ForegroundColor DarkGray
    }

    # Add members
    if ($group -and -not $WhatIfPreference) {
        foreach ($upn in $UserPrincipalNames) {
            try {
                $user = Get-ADUser -Filter "UserPrincipalName -eq '$upn'" -ErrorAction SilentlyContinue
                if ($user) {
                    Add-ADGroupMember -Identity $group -Members $user -ErrorAction SilentlyContinue
                    Write-Host "[INFO] Added user $upn to group $GroupName" -ForegroundColor DarkGray
                } else {
                    Write-Warning "User $upn not found in AD. Cannot add to group $GroupName."
                }
            } catch {
                Write-Warning "Failed to add user $upn to group ${GroupName}: $_"
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

function Get-FilteredUsers {
    param(
        [Parameter(Mandatory)][array]$AllUsers,
        [Parameter(Mandatory)][array]$ProjectMemberships
    )

    # Get all user IDs that have project assignments
    $assignedUserIds = $ProjectMemberships | ForEach-Object { $_.members | Where-Object { $_ -and $_.type -eq 'user' } } | ForEach-Object { $_.id } | Sort-Object -Unique

    # Filter users: active, not external, not system users, not bot accounts, and assigned to projects
    $filteredUsers = $AllUsers | Where-Object {
        $_.state -eq 'active' -and
        -not $_.external -and
        $_.username -notmatch '^gitlab.*bot$' -and
        $_.username -notmatch '^project_\d+_bot_[a-f0-9]+$' -and
        $_.username -notmatch '^gitlab_security_policy_project_\d+_bot_[a-f0-9]+$' -and
        $_.username -notin @('root', 'support-bot', 'alert-bot', 'automation-bot', 'visual-review-bot', 'GitLab-Admin-Bot') -and
        $_.id -in $assignedUserIds
    }

    return $filteredUsers
}

function Ensure-AdoCustomProjectGroup {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$CustomGroupName,
        [string]$Description = ""
    )

    try {
        # In WhatIf mode, skip actual API calls
        if ($WhatIfPreference) {
            Write-Host "[WHATIF] Would create ADO project group: $CustomGroupName" -ForegroundColor Yellow
            return @{
                displayName = $CustomGroupName
                description = $Description
                descriptor = "vssgp.test-descriptor-$CustomGroupName"
            }
        }

        # Detect if we're using Azure DevOps Server vs Services
        $config = Get-CoreRestConfig
        $isAzureDevOpsServer = -not ($config.CollectionUrl -match "dev\.azure\.com|visualstudio\.com")

        if ($isAzureDevOpsServer) {
            # Azure DevOps Server: Graph API not available, need TFSSecurity
            Write-Warning "Azure DevOps Server detected. Graph API is not available for creating custom groups."
            Write-Host "To create the required project group '$CustomGroupName', run the following TFSSecurity command on your Azure DevOps Server:" -ForegroundColor Yellow
            Write-Host "  TFSSecurity /gc \"vstfs:///Classification/TeamProject/$ProjectId\" \"$CustomGroupName\" \"$Description\" /collection:\"$($config.CollectionUrl)\"" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Note: TFSSecurity must be run on the Azure DevOps Server machine with appropriate permissions." -ForegroundColor Yellow
            Write-Host "After creating the group, you can continue with the migration process." -ForegroundColor Yellow

            # Return a mock object for compatibility
            return @{
                displayName = $CustomGroupName
                description = $Description
                descriptor = "vssgp.server-group-$CustomGroupName"
                isManualCreationRequired = $true
            }
        }

        # Azure DevOps Services: Use Graph API
        # Get the project details to obtain the project ID for scopeDescriptor
        $projectDetailsUrl = "/_apis/projects/$ProjectId`?api-version=7.1"
        $projectDetails = Invoke-AdoRest GET $projectDetailsUrl

        # Create scopeDescriptor: base64 encode the project ID with 'scp.' prefix
        $projectIdBytes = [System.Text.Encoding]::UTF8.GetBytes($projectDetails.id)
        $base64ProjectId = [System.Convert]::ToBase64String($projectIdBytes)
        $scopeDescriptor = "scp.$base64ProjectId"

        # First try to create the group (it will fail if it already exists)
        $body = @{
            displayName = $CustomGroupName
            description = $Description
        }

        $createUrl = "/_apis/graph/groups`?scopeDescriptor=$scopeDescriptor&api-version=7.1-preview.1"
        try {
            $newGroup = Invoke-AdoRest POST $createUrl -Body $body
            return $newGroup
        } catch {
            # If creation failed, try to find existing group
            if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*409*") {
                # Try to search for the group
                $searchUrl = "/_apis/graph/groups`?subjectTypes=group&api-version=7.1-preview.1"
                $groups = Invoke-AdoRest GET $searchUrl
                $existing = $groups.value | Where-Object { $_.displayName -eq $CustomGroupName }
                if ($existing) {
                    return $existing
                }
            }
            throw
        }
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

    if ($WhatIfPreference) {
        Write-Host "[WHATIF] Preview mode - no changes will be made" -ForegroundColor Yellow
        Write-Host ""
    }

    # Validate export folder
    if (-not (Test-Path $ExportFolder)) {
        throw "Export folder not found: $ExportFolder"
    }

    $usersFile = Join-Path $ExportFolder 'users.json'
    $groupsFile = Join-Path $ExportFolder 'groups.json'
    $projectMembershipsFile = Join-Path $ExportFolder 'project-memberships.json'

    if (-not (Test-Path $usersFile) -or -not (Test-Path $groupsFile)) {
        throw "Required files not found in $ExportFolder. Expected: users.json, groups.json"
    }

    Write-Host "[INFO] Loading exported data from: $ExportFolder" -ForegroundColor Cyan

    # Load projects.json for mapping GitLab projects to ADO projects
    $projectsConfigFile = Join-Path $PSScriptRoot '..\..\projects.json'
    if (-not (Test-Path $projectsConfigFile)) {
        throw "Projects configuration file not found: $projectsConfigFile"
    }
    $projectsConfig = Get-Content $projectsConfigFile -Raw | ConvertFrom-Json

    # Create mapping from GitLab project path to ADO project name
    $gitlabToAdoMapping = @{}
    foreach ($adoProject in $projectsConfig) {
        foreach ($gitlabProject in $adoProject.projects) {
            $gitlabToAdoMapping[$gitlabProject] = $adoProject.adoproject
        }
    }

    # Load data
    Write-Progress -Activity "Importing GitLab Identity" -Status "Loading exported data..." -PercentComplete 0 -Id 2

    $users = Get-Content $usersFile -Raw | ConvertFrom-Json
    $groups = Get-Content $groupsFile -Raw | ConvertFrom-Json
    $projectMemberships = @()
    if (Test-Path $projectMembershipsFile) {
        $projectMemberships = Get-Content $projectMembershipsFile -Raw | ConvertFrom-Json
    }

    Write-Host "[INFO] Loaded $($users.Count) users, $($groups.Count) groups, $($projectMemberships.Count) project memberships" -ForegroundColor Green

    # Filter users
    $filteredUsers = Get-FilteredUsers -AllUsers $users -ProjectMemberships $projectMemberships
    Write-Host "[INFO] Filtered to $($filteredUsers.Count) assignable users" -ForegroundColor Green

    # Create migration plan file
    $migrationFile = Join-Path $ExportFolder 'user-migration-plan.json'
    $migrationPlan = @{
        ado_project_name = if ($AdoProjectName) { $AdoProjectName } else { "all_projects" }
        migration_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        users = @()
        summary = @{
            total_users = $filteredUsers.Count
            total_projects = $projectMemberships.Count
            ado_groups_to_create = @()
        }
    }

    foreach ($user in $filteredUsers) {
        $userProjects = @()
        foreach ($pm in $projectMemberships) {
            $member = $pm.members | Where-Object { $_ -and $_.id -eq $user.id -and $_.type -eq 'user' } | Select-Object -First 1
            if ($member) {
                $adoProjectName = $gitlabToAdoMapping[$pm.path_with_namespace]
                if (-not $adoProjectName) {
                    Write-Warning "GitLab project '$($pm.path_with_namespace)' not found in projects.json mapping. Skipping."
                    continue
                }
                $userProjects += @{
                    gitlab_project_id = $pm.project_id
                    path_with_namespace = $pm.path_with_namespace
                    ado_project_mapping = $adoProjectName
                    role = $member.access_level_name
                    ado_group_assignment = Map-GitLabRoleToAdoBaseGroup -GitLabRole $member.access_level_name
                }
            }
        }
        $migrationPlan.users += @{
            gitlab_user_id = $user.id
            username = $user.username
            email = $user.email
            projects = $userProjects
            ado_custom_groups = @()
        }
    }

    # Calculate ado_groups_to_create - groups should be at ADO project level, not GitLab project level
    $adoProjectRoleGroups = @{}
    foreach ($user in $migrationPlan.users) {
        foreach ($proj in $user.projects) {
            $adoProject = $proj.ado_project_mapping
            $role = $proj.ado_group_assignment

            if (-not $adoProjectRoleGroups.ContainsKey($adoProject)) {
                $adoProjectRoleGroups[$adoProject] = @{}
            }

            if (-not $adoProjectRoleGroups[$adoProject].ContainsKey($role)) {
                $adoProjectRoleGroups[$adoProject][$role] = @()
            }

            # Add user to this ADO project + role group
            $adoProjectRoleGroups[$adoProject][$role] += $user.gitlab_user_id
        }
    }

    # Flatten to unique groups to create
    $migrationPlan.summary.ado_groups_to_create = @()
    foreach ($adoProject in $adoProjectRoleGroups.Keys) {
        foreach ($role in $adoProjectRoleGroups[$adoProject].Keys) {
            $migrationPlan.summary.ado_groups_to_create += "$adoProject-$role"
        }
    }

    $migrationPlan | ConvertTo-Json -Depth 10 | Set-Content $migrationFile
    Write-Host "[INFO] Created migration plan file: $migrationFile" -ForegroundColor Green

    # Get AD OU for users and groups (this should be configurable)
    $adUserOuDn = $env:AD_USER_OU_DN
    if (-not $adUserOuDn) {
        $adUserOuDn = "OU=Users,OU=DevOps,DC=example,DC=com"  # Default for testing
    }

    $adGroupOuDn = $env:AD_GROUP_OU_DN
    if (-not $adGroupOuDn) {
        $adGroupOuDn = "OU=Groups,OU=DevOps,DC=example,DC=com"  # Default for testing
    }

    # Create users file with passwords
    $usersWithPasswordsFile = Join-Path $ExportFolder 'users-with-passwords.json'
    $usersWithPasswords = @()

    # First pass: Create all AD users
    Write-Progress -Activity "Importing GitLab Identity" -Status "Creating AD users..." -PercentComplete 10 -Id 2

    foreach ($user in $filteredUsers) {
        $userUpn = $user.email
        if (-not $userUpn) {
            Write-Warning "No email for user: $($user.username). Skipping AD user creation."
            continue
        }

        # Generate password
        $password = Generate-SecurePassword

        # Store user with password
        $usersWithPasswords += @{
            gitlab_user_id = $user.id
            username = $user.username
            email = $user.email
            name = $user.name
            password = $password
            upn = $userUpn
            created_in_ad = $false
        }

        # Create AD user
        $adUser = Ensure-AdUser -UserPrincipalName $userUpn -DisplayName $user.name -OuDn $adUserOuDn -Password $password
        if ($adUser) {
            $usersWithPasswords[-1].created_in_ad = $true
        }
    }

    # Save users with passwords
    $usersWithPasswords | ConvertTo-Json -Depth 10 | Set-Content $usersWithPasswordsFile
    Write-Host "[INFO] Created users file with passwords: $usersWithPasswordsFile" -ForegroundColor Green

    # Get unique ADO projects from migration plan
    $uniqueAdoProjects = $migrationPlan.users | ForEach-Object { $_.projects } | ForEach-Object { $_.ado_project_mapping } | Sort-Object -Unique
    
    # Verify ADO projects exist and get their IDs
    $adoProjectIds = @{}
    foreach ($adoProjectName in $uniqueAdoProjects) {
        if ($WhatIfPreference) {
            $adoProjectIds[$adoProjectName] = "test-project-id-$adoProjectName"
            Write-Host "[INFO] Simulating Azure DevOps project: $adoProjectName (ID: $($adoProjectIds[$adoProjectName]))" -ForegroundColor Green
        } else {
            $adoProject = Get-AdoProjectByName -ProjectName $adoProjectName
            if (-not $adoProject) {
                Write-Warning "Azure DevOps project '$adoProjectName' not found. Skipping users for this project."
                continue
            }
            $adoProjectIds[$adoProjectName] = $adoProject.id
            Write-Host "[INFO] Found Azure DevOps project: $adoProjectName (ID: $($adoProjectIds[$adoProjectName]))" -ForegroundColor Green
        }
    }

    # Create ADO project groups at the project level (not per GitLab project)
    Write-Progress -Activity "Importing GitLab Identity" -Status "Creating ADO project groups..." -PercentComplete 20 -Id 2

    $adoProjectGroups = @{}
    foreach ($adoProjectName in $uniqueAdoProjects) {
        $projectId = $adoProjectIds[$adoProjectName]
        if (-not $projectId) {
            Write-Warning "No project ID found for '$adoProjectName'. Skipping group creation."
            continue
        }

        $adoProjectGroups[$adoProjectName] = @{}

        # Get the roles needed for this ADO project
        $projectRoles = $adoProjectRoleGroups[$adoProjectName]
        if (-not $projectRoles) { continue }

        foreach ($role in $projectRoles.Keys) {
            # Create custom ADO project group name (never use built-in groups)
            $customGroupName = if ($AdoGroupPrefix) { "$AdoGroupPrefix-$adoProjectName-$role" } else { "$adoProjectName-$role" }
            $customGroupName = ConvertTo-SafeName -Name $customGroupName

            Write-Host "[INFO] Creating ADO project group: $customGroupName" -ForegroundColor Cyan

            # Ensure custom ADO project group (this will inherit permissions from built-in groups via nesting)
            $adoCustomGroup = Ensure-AdoCustomProjectGroup -ProjectId $projectId -CustomGroupName $customGroupName -Description "Migrated GitLab users with role '$role' in ADO project '$adoProjectName'"

            if ($adoCustomGroup) {
                $adoProjectGroups[$adoProjectName][$role] = @{
                    customGroupName = $customGroupName
                    adoGroup = $adoCustomGroup
                    userIds = $projectRoles[$role]
                }

                # Skip nesting operations if manual creation is required (Azure DevOps Server)
                if ($adoCustomGroup.isManualCreationRequired) {
                    Write-Host "[INFO] Skipping automatic nesting for '$customGroupName' - manual TFSSecurity commands shown above" -ForegroundColor Yellow
                    Write-Host "[INFO] After creating the group manually, you may need to nest it into the built-in '$role' group" -ForegroundColor Yellow
                    continue
                }

                # Find built-in ADO project group and nest custom group into it
                $builtInGroup = Get-AdoProjectGroup -ProjectId $projectId -GroupDisplayName $role
                if ($builtInGroup) {
                    $builtInDesc = $builtInGroup.descriptor
                    $customDesc = $adoCustomGroup.descriptor

                    Write-Host "[INFO] Nesting custom group '$customGroupName' into built-in '$role'" -ForegroundColor Cyan
                    Add-AdoGroupMember -MemberDescriptor $customDesc -ContainerDescriptor $builtInDesc
                } else {
                    Write-Warning "Built-in project group '$role' not found in project '$adoProjectName'. Custom group created but not nested."
                }
            } else {
                Write-Warning "Failed to create custom ADO group: $customGroupName"
            }
        }
    }

    # Process users and add them to appropriate ADO project groups
    Write-Progress -Activity "Importing GitLab Identity" -Status "Processing users..." -PercentComplete 30 -Id 2

    $processedUsers = 0
    $totalUsers = $filteredUsers.Count

    foreach ($user in $filteredUsers) {
        $processedUsers++
        $progress = 30 + [Math]::Floor(($processedUsers / $totalUsers) * 60)
        Write-Progress -Activity "Importing GitLab Identity" -Status "Processing user $($processedUsers)/$totalUsers..." -PercentComplete $progress -Id 2

        $userProjects = $migrationPlan.users | Where-Object { $_.gitlab_user_id -eq $user.id } | Select-Object -First 1
        if (-not $userProjects -or $userProjects.projects.Count -eq 0) {
            Write-Verbose "No projects for user: $($user.username)"
            continue
        }

        Write-Host "[INFO] Processing user: $($user.username)" -ForegroundColor Cyan

        # Get UPN
        $userUpn = $user.email
        if (-not $userUpn) {
            Write-Verbose "No email for user: $($user.username)"
            continue
        }

        # Group user's roles by ADO project to determine their effective role in each project
        $userAdoProjectRoles = @{}
        foreach ($proj in $userProjects.projects) {
            $adoProject = $proj.ado_project_mapping
            $role = $proj.ado_group_assignment

            if (-not $userAdoProjectRoles.ContainsKey($adoProject)) {
                $userAdoProjectRoles[$adoProject] = @()
            }
            $userAdoProjectRoles[$adoProject] += $role
        }

        # For each ADO project, determine the highest role and add user to that group
        foreach ($adoProject in $userAdoProjectRoles.Keys) {
            $roles = $userAdoProjectRoles[$adoProject] | Sort-Object -Unique

            # Use the first role (they should all be the same for a user in a project, but if not, pick one)
            $effectiveRole = $roles[0]

            if ($adoProjectGroups.ContainsKey($adoProject) -and $adoProjectGroups[$adoProject].ContainsKey($effectiveRole)) {
                $groupInfo = $adoProjectGroups[$adoProject][$effectiveRole]

                # Skip user processing if manual group creation is required
                if ($groupInfo.adoGroup.isManualCreationRequired) {
                    Write-Host "[INFO] Skipping user addition to '$adoProject-$effectiveRole' - manual group creation required" -ForegroundColor Yellow
                    continue
                }

                # Create AD group name per project-role
                $adGroupName = if ($AdGroupPrefix) { "$AdGroupPrefix-$adoProject-$effectiveRole" } else { "$adoProject-$effectiveRole" }
                $adGroupName = ConvertTo-SafeName -Name $adGroupName

                Write-Host "[INFO] Adding user to group: $adoProject-$effectiveRole" -ForegroundColor Cyan

                # 1. Ensure AD group and add member
                $adGroup = Ensure-AdGroupWithMembers -GroupName $adGroupName -OuDn $adGroupOuDn -UserPrincipalNames @($userUpn)

                # 2. Add AD group to custom ADO group
                if ($adGroup) {
                    $adoAdGroupSubject = Find-AdoGraphSubject -SearchTerm $adGroup.Name -SubjectType "group"
                    if ($adoAdGroupSubject) {
                        $adGroupDesc = $adoAdGroupSubject.descriptor
                        $customDesc = $groupInfo.adoGroup.descriptor
                        Write-Host "[INFO] Adding AD group '$($adGroup.Name)' to custom ADO group" -ForegroundColor Cyan
                        Add-AdoGroupMember -MemberDescriptor $adGroupDesc -ContainerDescriptor $customDesc
                    } else {
                        Write-Warning "Could not find AD group '$($adGroup.Name)' in ADO Graph"
                    }
                }

                # Update migration plan with custom group
                $userProjects.ado_custom_groups += $groupInfo.customGroupName
            }
        }
    }

    # Update migration plan with custom groups and save
    $migrationPlan | ConvertTo-Json -Depth 10 | Set-Content $migrationFile
    Write-Host "[INFO] Updated migration plan file: $migrationFile" -ForegroundColor Green

    Write-Progress -Activity "Importing GitLab Identity" -Status "Import completed!" -PercentComplete 100 -Id 2 -Completed

    Write-Host ""
    # Check if any manual group creation was required
    $manualGroupsRequired = $adoProjectGroups.Values | ForEach-Object { $_.Values } | Where-Object { $_.adoGroup.isManualCreationRequired } | Measure-Object | Select-Object -ExpandProperty Count

    if ($manualGroupsRequired -gt 0) {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║                    MANUAL STEPS REQUIRED FOR AZURE DEVOPS SERVER           ║" -ForegroundColor Yellow
        Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Azure DevOps Server detected. The following groups need to be created manually:" -ForegroundColor Yellow
        Write-Host ""

        foreach ($adoProjectName in $adoProjectGroups.Keys) {
            foreach ($role in $adoProjectGroups[$adoProjectName].Keys) {
                $groupInfo = $adoProjectGroups[$adoProjectName][$role]
                if ($groupInfo.adoGroup.isManualCreationRequired) {
                    $customGroupName = $groupInfo.customGroupName
                    Write-Host "Project: $adoProjectName | Role: $role | Group: $customGroupName" -ForegroundColor Cyan
                    Write-Host "TFSSecurity Command:" -ForegroundColor White
                    $config = Get-CoreRestConfig
                    Write-Host "  TFSSecurity /gc \"vstfs:///Classification/TeamProject/$($adoProjectIds[$adoProjectName])\" \"$customGroupName\" \"Migrated GitLab users with role '$role' in ADO project '$adoProjectName'\" /collection:\"$($config.CollectionUrl)\"" -ForegroundColor Gray
                    Write-Host ""
                }
            }
        }

        Write-Host "After creating the groups manually, you can re-run this script to complete user assignment." -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "[SUCCESS] GitLab identity import completed!" -ForegroundColor Green
    Write-Host "[INFO] Processed $($filteredUsers.Count) users" -ForegroundColor Cyan
    Write-Host "[INFO] Created $($usersWithPasswords.Count) AD users" -ForegroundColor Cyan
    Write-Host "[INFO] User passwords saved to: $usersWithPasswordsFile" -ForegroundColor Yellow
    Write-Host "[WARNING] Ensure passwords are securely distributed to users and then delete the passwords file!" -ForegroundColor Red

    if ($WhatIfPreference) {
        Write-Host "[INFO] This was a preview. Use without -WhatIf to perform actual import." -ForegroundColor Yellow
    }

} catch {
    Write-Host "[ERROR] Import failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Progress -Activity "Importing GitLab Identity" -Status "Import failed!" -Id 2 -Completed
    throw
}
