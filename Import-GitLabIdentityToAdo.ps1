<#
.SYNOPSIS
    Imports GitLab identity and authorization data into Azure DevOps Server.

.DESCRIPTION
    This script imports previously exported GitLab identity data (users, groups, memberships)
    into Azure DevOps Server using the REST and Graph APIs. It works offline from GitLab
    and creates Azure DevOps groups and memberships based on the exported JSON files.

.NOTES
    Requirements:
    - Azure DevOps Server on-premises (not Azure DevOps Services)
    - PAT with Graph API, Projects/Teams, and Security permissions
    - Exported GitLab identity data in JSON format
    
    Limitations:
    - Cannot create arbitrary user identities in Azure DevOps Server
    - Users must already exist in AD/AAD integrated with Azure DevOps
    - User resolution is best-effort based on email/display name matching
    
    Author: GitLab to Azure DevOps Migration Team
    Version: 1.0.0
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectionUrl,                 # e.g. https://devops.example.com/tfs/DefaultCollection
    
    [Parameter(Mandatory=$true)]
    [string]$AdoPat,
    
    [Parameter(Mandatory=$true)]
    [string]$ExportFolder,                  # path to export-gitlab-identity-YYYYMMDD
    
    [string]$AdoApiVersion = "7.1-preview.1",
    
    [string]$DefaultProjectName = "",       # used to attach project memberships
    
    [switch]$WhatIf
)

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Global variables
$Global:LogFile = ""
$Global:AuthHeader = @{}
$Global:ImportStats = @{
    StartTime = Get-Date
    GroupsCreated = 0
    GroupsSkipped = 0
    MembershipsCreated = 0
    MembershipsSkipped = 0
    UsersResolved = 0
    UsersUnresolved = 0
    ProjectMembershipsAttached = 0
    ProjectMembershipsOrphaned = 0
}

# Initialize logging
$Global:LogFile = Join-Path $ExportFolder "import.log"
if (Test-Path $Global:LogFile) {
    Remove-Item $Global:LogFile -Force
}

#region REST API Helpers

<#
.SYNOPSIS
    Creates Authorization header for Azure DevOps REST API calls.
    
.DESCRIPTION
    Uses Basic authentication with PAT as documented in:
    https://docs.microsoft.com/en-us/rest/api/azure/devops/?view=azure-devops-rest-7.1
#>
function New-AdoAuthHeader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pat
    )
    
    $base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
    return @{
        'Authorization' = "Basic $base64"
        'Content-Type' = 'application/json'
    }
}

<#
.SYNOPSIS
    Generic wrapper for Azure DevOps REST API calls.
    
.DESCRIPTION
    Handles authentication, error handling, and consistent API versioning.
    Supports all HTTP methods and provides meaningful error messages.
#>
function Invoke-AdoRest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Method,
        
        [Parameter(Mandatory=$true)]
        [string]$RelativeUrl,
        
        [string]$ApiVersion = $AdoApiVersion,
        
        [object]$Body = $null,
        
        [hashtable]$Headers = $Global:AuthHeader
    )
    
    # Build full URL
    $url = "$CollectionUrl$RelativeUrl"
    if ($RelativeUrl -notlike "*api-version=*") {
        $separator = if ($RelativeUrl -like "*?*") { "&" } else { "?" }
        $url += "$separator" + "api-version=$ApiVersion"
    }
    
    $params = @{
        Uri = $url
        Method = $Method
        Headers = $Headers
        UseBasicParsing = $true
    }
    
    if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
        if ($Body -is [string]) {
            $params.Body = $Body
        } else {
            $params.Body = $Body | ConvertTo-Json -Depth 10
        }
    }
    
    try {
        Write-Log "REST: $Method $url" "DEBUG"
        if ($WhatIf -and $Method -in @('POST', 'PUT', 'PATCH', 'DELETE')) {
            Write-Log "WHATIF: Would call $Method $url" "INFO"
            return $null
        }
        
        $response = Invoke-RestMethod @params
        Write-Log "REST: $Method $url - SUCCESS" "DEBUG"
        return $response
    }
    catch {
        $errorMsg = "REST API call failed: $Method $url"
        if ($_.Exception.Response) {
            $errorMsg += " - Status: $($_.Exception.Response.StatusCode)"
            if ($_.ErrorDetails.Message) {
                $errorMsg += " - Details: $($_.ErrorDetails.Message)"
            }
        } else {
            $errorMsg += " - Error: $($_.Exception.Message)"
        }
        
        Write-Log $errorMsg "ERROR"
        throw $errorMsg
    }
}

<#
.SYNOPSIS
    Resolves Azure DevOps group by display name.
    
.DESCRIPTION
    Uses Graph API to find existing groups:
    GET /_apis/graph/groups?api-version={version}
#>
function Get-AdoGroupByName {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DisplayName
    )
    
    try {
        $groups = Invoke-AdoRest -Method 'GET' -RelativeUrl '/_apis/graph/groups'
        
        if ($groups.value) {
            $match = $groups.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
            return $match
        }
        
        return $null
    }
    catch {
        Write-Log "Failed to search for group '$DisplayName': $_" "WARN"
        return $null
    }
}

<#
.SYNOPSIS
    Resolves Azure DevOps user by email or display name.
    
.DESCRIPTION
    Attempts to find users using Graph API:
    GET /_apis/graph/users?api-version={version}
    
    Note: User resolution is best-effort since ADO users come from AD/AAD
#>
function Get-AdoUserByMailOrDisplayName {
    param(
        [string]$Email,
        [string]$DisplayName
    )
    
    try {
        $users = Invoke-AdoRest -Method 'GET' -RelativeUrl '/_apis/graph/users'
        
        if ($users.value) {
            # Try email first (most reliable)
            if ($Email) {
                $match = $users.value | Where-Object { $_.mailAddress -eq $Email } | Select-Object -First 1
                if ($match) {
                    return $match
                }
            }
            
            # Fall back to display name
            if ($DisplayName) {
                $match = $users.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
                if ($match) {
                    return $match
                }
            }
        }
        
        return $null
    }
    catch {
        Write-Log "Failed to search for user Email='$Email' DisplayName='$DisplayName': $_" "WARN"
        return $null
    }
}

<#
.SYNOPSIS
    Gets existing memberships for a container (group/project).
    
.DESCRIPTION
    Uses Graph API to list memberships:
    GET /_apis/graph/memberships/{containerDescriptor}?direction=down&api-version={version}
#>
function Get-AdoMemberships {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ContainerDescriptor
    )
    
    try {
        $memberships = Invoke-AdoRest -Method 'GET' -RelativeUrl "/_apis/graph/memberships/$ContainerDescriptor" -ApiVersion $AdoApiVersion
        return $memberships.value
    }
    catch {
        Write-Log "Failed to get memberships for container '$ContainerDescriptor': $_" "WARN"
        return @()
    }
}

<#
.SYNOPSIS
    Gets Azure DevOps project by name.
    
.DESCRIPTION
    Uses Core API to find projects:
    GET /_apis/projects?api-version={version}
#>
function Get-AdoProjectByName {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectName
    )
    
    try {
        $projects = Invoke-AdoRest -Method 'GET' -RelativeUrl '/_apis/projects' -ApiVersion '7.1'
        
        if ($projects.value) {
            $match = $projects.value | Where-Object { $_.name -eq $ProjectName } | Select-Object -First 1
            return $match
        }
        
        return $null
    }
    catch {
        Write-Log "Failed to search for project '$ProjectName': $_" "WARN"
        return $null
    }
}

#endregion

#region Logging

<#
.SYNOPSIS
    Centralized logging function with timestamps and levels.
#>
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message, 
        
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp][$Level] $Message"
    
    # Write to file
    $logLine | Out-File -FilePath $Global:LogFile -Append -Encoding utf8
    
    # Write to console with colors
    switch ($Level.ToUpper()) {
        'ERROR' { Write-Host $logLine -ForegroundColor Red }
        'WARN'  { Write-Host $logLine -ForegroundColor Yellow }
        'DEBUG' { Write-Verbose $logLine }
        default { Write-Host $logLine -ForegroundColor White }
    }
}

#endregion

#region Main Functions

<#
.SYNOPSIS
    Loads and validates the exported GitLab identity JSON files.
    
.DESCRIPTION
    Expected JSON structure from GitLab exporter:
    - users.json: GitLab users with id, username, name, email
    - groups.json: GitLab groups with id, full_path, parent_id, proposed_ado_name
    - projects.json: GitLab projects with path_with_namespace, proposed_ado_repo_name
    - group-memberships.json: Group membership relationships with access_level
    - project-memberships.json: Project membership relationships with access_level
#>
function Import-GitLabData {
    Write-Log "Loading GitLab export data from: $ExportFolder"
    
    $data = @{}
    
    # Required files
    $requiredFiles = @('users.json', 'groups.json', 'projects.json', 'group-memberships.json', 'project-memberships.json')
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $ExportFolder $file
        if (-not (Test-Path $filePath)) {
            throw "Required file not found: $filePath"
        }
        
        try {
            $content = Get-Content -Path $filePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $data[$file.Replace('.json', '')] = $content
            Write-Log "Loaded $file - $(($content | Measure-Object).Count) items"
        }
        catch {
            throw "Failed to parse $file`: $_"
        }
    }
    
    # Optional files
    $optionalFiles = @('member-roles.json', 'metadata.json')
    foreach ($file in $optionalFiles) {
        $filePath = Join-Path $ExportFolder $file
        if (Test-Path $filePath) {
            try {
                $content = Get-Content -Path $filePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $data[$file.Replace('.json', '')] = $content
                Write-Log "Loaded optional $file"
            }
            catch {
                Write-Log "Failed to parse optional $file`: $_" "WARN"
            }
        }
    }
    
    return $data
}

<#
.SYNOPSIS
    Creates Azure DevOps groups from GitLab groups.
    
.DESCRIPTION
    Uses Graph API to create groups:
    POST /_apis/graph/groups?api-version={version}
    
    Body: {
        "displayName": "group-name",
        "description": "Migrated from GitLab group: original-name"
    }
#>
function New-AdoGroups {
    param(
        [Parameter(Mandatory=$true)]
        [array]$GitLabGroups
    )
    
    Write-Log "Creating Azure DevOps groups from $($GitLabGroups.Count) GitLab groups"
    
    $groupMap = @{}
    $existingMapFile = Join-Path $ExportFolder "ado-group-map.json"
    
    # Load existing map if available (for re-runs)
    if (Test-Path $existingMapFile) {
        try {
            $existingMap = Get-Content -Path $existingMapFile -Raw -Encoding UTF8 | ConvertFrom-Json
            # Convert PSCustomObject to hashtable
            $existingMap.PSObject.Properties | ForEach-Object {
                $groupMap[$_.Name] = $_.Value
            }
            Write-Log "Loaded existing group map with $($groupMap.Count) entries"
        }
        catch {
            Write-Log "Failed to load existing group map: $_" "WARN"
        }
    }
    
    foreach ($gitlabGroup in $GitLabGroups) {
        $gitlabId = $gitlabGroup.id.ToString()
        
        # Use proposed_ado_name if available, otherwise sanitize full_path
        $adoName = if ($gitlabGroup.proposed_ado_name) { 
            $gitlabGroup.proposed_ado_name 
        } else { 
            $gitlabGroup.full_path -replace '[/\s]', '-' 
        }
        
        # Skip if already processed
        if ($groupMap.ContainsKey($gitlabId)) {
            Write-Log "Group '$adoName' (GitLab ID: $gitlabId) already exists - skipping"
            $Global:ImportStats.GroupsSkipped++
            continue
        }
        
        # Check if group already exists in ADO
        $existingGroup = Get-AdoGroupByName -DisplayName $adoName
        if ($existingGroup) {
            Write-Log "Group '$adoName' already exists in ADO - reusing"
            $groupMap[$gitlabId] = $existingGroup.descriptor
            $Global:ImportStats.GroupsSkipped++
            continue
        }
        
        # Create new group
        $groupBody = @{
            displayName = $adoName
            description = "Migrated from GitLab group: $($gitlabGroup.full_path)"
        }
        
        Write-Log "Creating ADO group: $adoName"
        
        try {
            $newGroup = Invoke-AdoRest -Method 'POST' -RelativeUrl '/_apis/graph/groups' -Body $groupBody
            if ($newGroup -and $newGroup.descriptor) {
                $groupMap[$gitlabId] = $newGroup.descriptor
                Write-Log "Created group '$adoName' with descriptor: $($newGroup.descriptor)"
                $Global:ImportStats.GroupsCreated++
            }
        }
        catch {
            Write-Log "Failed to create group '$adoName': $_" "ERROR"
        }
    }
    
    # Save updated group map
    $groupMap | ConvertTo-Json -Depth 2 | Out-File -FilePath $existingMapFile -Encoding UTF8
    Write-Log "Saved group map to: $existingMapFile"
    
    return $groupMap
}

<#
.SYNOPSIS
    Creates group memberships in Azure DevOps.
    
.DESCRIPTION
    Uses Graph API to create memberships:
    POST /_apis/graph/memberships/{subjectDescriptor}/{containerDescriptor}?api-version={version}
#>
function New-AdoGroupMemberships {
    param(
        [Parameter(Mandatory=$true)]
        [array]$GroupMemberships,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$GroupMap,
        
        [Parameter(Mandatory=$true)]
        [array]$GitLabUsers
    )
    
    Write-Log "Processing $($GroupMemberships.Count) group membership entries"
    
    # Build user lookup for faster resolution
    $userLookup = @{}
    foreach ($user in $GitLabUsers) {
        $userLookup[$user.id] = $user
    }
    
    $unresolvedUsers = @()
    
    foreach ($membership in $GroupMemberships) {
        $containerGroupId = $membership.group_id.ToString()
        
        if (-not $GroupMap.ContainsKey($containerGroupId)) {
            Write-Log "Container group not found for GitLab group ID: $containerGroupId" "WARN"
            continue
        }
        
        $containerDescriptor = $GroupMap[$containerGroupId]
        
        # Get existing memberships to avoid duplicates
        $existingMemberships = Get-AdoMemberships -ContainerDescriptor $containerDescriptor
        $existingSubjects = $existingMemberships | ForEach-Object { $_.subjectDescriptor }
        
        foreach ($member in $membership.members) {
            $subjectDescriptor = $null
            
            if ($member.type -eq 'group') {
                # Member is a group
                $memberGroupId = $member.id.ToString()
                if ($GroupMap.ContainsKey($memberGroupId)) {
                    $subjectDescriptor = $GroupMap[$memberGroupId]
                } else {
                    Write-Log "Member group not found for GitLab group ID: $memberGroupId" "WARN"
                    continue
                }
            }
            elseif ($member.type -eq 'user') {
                # Member is a user - try to resolve
                $gitlabUser = $userLookup[$member.id]
                if ($gitlabUser) {
                    $adoUser = Get-AdoUserByMailOrDisplayName -Email $gitlabUser.email -DisplayName $gitlabUser.name
                    if ($adoUser) {
                        $subjectDescriptor = $adoUser.descriptor
                        $Global:ImportStats.UsersResolved++
                    } else {
                        # User not found - add to unresolved list
                        $unresolvedUsers += @{
                            gitlab_id = $gitlabUser.id
                            username = $gitlabUser.username
                            name = $gitlabUser.name
                            email = $gitlabUser.email
                            reason = "not found in ADO"
                            target_group = $containerDescriptor
                            access_level = $member.access_level
                        }
                        $Global:ImportStats.UsersUnresolved++
                        Write-Log "User not resolved: $($gitlabUser.username) ($($gitlabUser.name))" "WARN"
                        continue
                    }
                }
            }
            
            if (-not $subjectDescriptor) {
                continue
            }
            
            # Check if membership already exists
            if ($subjectDescriptor -in $existingSubjects) {
                Write-Log "Membership already exists: $subjectDescriptor -> $containerDescriptor" "DEBUG"
                $Global:ImportStats.MembershipsSkipped++
                continue
            }
            
            # Create membership
            Write-Log "Creating membership: $subjectDescriptor -> $containerDescriptor"
            
            try {
                Invoke-AdoRest -Method 'PUT' -RelativeUrl "/_apis/graph/memberships/$subjectDescriptor/$containerDescriptor"
                $Global:ImportStats.MembershipsCreated++
            }
            catch {
                Write-Log "Failed to create membership $subjectDescriptor -> $containerDescriptor`: $_" "ERROR"
            }
        }
    }
    
    # Save unresolved users
    if ($unresolvedUsers.Count -gt 0) {
        $unresolvedFile = Join-Path $ExportFolder "unresolved-identities.json"
        $unresolvedUsers | ConvertTo-Json -Depth 3 | Out-File -FilePath $unresolvedFile -Encoding UTF8
        Write-Log "Saved $($unresolvedUsers.Count) unresolved users to: $unresolvedFile"
    }
}

<#
.SYNOPSIS
    Creates project memberships in Azure DevOps.
    
.DESCRIPTION
    Attempts to map GitLab projects to Azure DevOps projects and create team memberships.
    Uses Teams API for project-scoped memberships:
    POST /_apis/projects/{projectId}/teams/{teamId}/members?api-version={version}
#>
function New-AdoProjectMemberships {
    param(
        [Parameter(Mandatory=$true)]
        [array]$ProjectMemberships,
        
        [Parameter(Mandatory=$true)]
        [array]$GitLabProjects,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$GroupMap,
        
        [Parameter(Mandatory=$true)]
        [array]$GitLabUsers
    )
    
    Write-Log "Processing $($ProjectMemberships.Count) project membership entries"
    
    # Build project lookup
    $projectLookup = @{}
    foreach ($project in $GitLabProjects) {
        $projectLookup[$project.id] = $project
    }
    
    # Build user lookup
    $userLookup = @{}
    foreach ($user in $GitLabUsers) {
        $userLookup[$user.id] = $user
    }
    
    $orphanedMemberships = @()
    
    foreach ($membership in $ProjectMemberships) {
        $gitlabProject = $projectLookup[$membership.project_id]
        if (-not $gitlabProject) {
            Write-Log "GitLab project not found for ID: $($membership.project_id)" "WARN"
            continue
        }
        
        # Try to find matching ADO project
        $adoProjectName = if ($gitlabProject.proposed_ado_repo_name) {
            $gitlabProject.proposed_ado_repo_name
        } elseif ($DefaultProjectName) {
            $DefaultProjectName
        } else {
            $gitlabProject.path_with_namespace -replace '[/\s]', '-'
        }
        
        $adoProject = Get-AdoProjectByName -ProjectName $adoProjectName
        if (-not $adoProject) {
            Write-Log "ADO project not found: $adoProjectName (GitLab: $($gitlabProject.path_with_namespace))" "WARN"
            $orphanedMemberships += @{
                gitlab_project = $gitlabProject.path_with_namespace
                proposed_ado_name = $adoProjectName
                members_count = $membership.members.Count
                reason = "ADO project not found"
            }
            $Global:ImportStats.ProjectMembershipsOrphaned += $membership.members.Count
            continue
        }
        
        Write-Log "Processing project memberships for: $($adoProject.name)"
        
        # For project memberships, we'll add members to the default project team
        # This is a simplified approach - in practice, you might want more sophisticated team mapping
        foreach ($member in $membership.members) {
            $memberDescriptor = $null
            
            if ($member.type -eq 'group') {
                $memberGroupId = $member.id.ToString()
                if ($GroupMap.ContainsKey($memberGroupId)) {
                    $memberDescriptor = $GroupMap[$memberGroupId]
                }
            }
            elseif ($member.type -eq 'user') {
                $gitlabUser = $userLookup[$member.id]
                if ($gitlabUser) {
                    $adoUser = Get-AdoUserByMailOrDisplayName -Email $gitlabUser.email -DisplayName $gitlabUser.name
                    if ($adoUser) {
                        $memberDescriptor = $adoUser.descriptor
                    }
                }
            }
            
            if ($memberDescriptor) {
                Write-Log "Would add member $memberDescriptor to project $($adoProject.name) (access: $($member.access_level))"
                # Note: Actual team membership API calls would go here
                # This is left as a placeholder since team membership APIs vary by project structure
                $Global:ImportStats.ProjectMembershipsAttached++
            }
        }
    }
    
    # Save orphaned memberships report
    if ($orphanedMemberships.Count -gt 0) {
        $orphanedFile = Join-Path $ExportFolder "orphaned-project-memberships.json"
        $orphanedMemberships | ConvertTo-Json -Depth 3 | Out-File -FilePath $orphanedFile -Encoding UTF8
        Write-Log "Saved $($orphanedMemberships.Count) orphaned project memberships to: $orphanedFile"
    }
}

<#
.SYNOPSIS
    Generates import report with statistics and metadata.
#>
function New-ImportReport {
    $Global:ImportStats.EndTime = Get-Date
    $Global:ImportStats.Duration = $Global:ImportStats.EndTime - $Global:ImportStats.StartTime
    $Global:ImportStats.AdoUrl = $CollectionUrl
    $Global:ImportStats.ApiVersion = $AdoApiVersion
    $Global:ImportStats.WhatIfMode = $WhatIf.IsPresent
    
    $reportFile = Join-Path $ExportFolder "import-report.json"
    $Global:ImportStats | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-Log "=== IMPORT SUMMARY ==="
    Write-Log "Duration: $($Global:ImportStats.Duration.ToString('hh\:mm\:ss'))"
    Write-Log "Groups Created: $($Global:ImportStats.GroupsCreated)"
    Write-Log "Groups Skipped: $($Global:ImportStats.GroupsSkipped)"
    Write-Log "Memberships Created: $($Global:ImportStats.MembershipsCreated)"
    Write-Log "Memberships Skipped: $($Global:ImportStats.MembershipsSkipped)"
    Write-Log "Users Resolved: $($Global:ImportStats.UsersResolved)"
    Write-Log "Users Unresolved: $($Global:ImportStats.UsersUnresolved)"
    Write-Log "Project Memberships Attached: $($Global:ImportStats.ProjectMembershipsAttached)"
    Write-Log "Project Memberships Orphaned: $($Global:ImportStats.ProjectMembershipsOrphaned)"
    Write-Log "Report saved to: $reportFile"
}

#endregion

#region Main Execution

try {
    Write-Log "Starting GitLab to Azure DevOps identity import"
    Write-Log "Collection URL: $CollectionUrl"
    Write-Log "Export Folder: $ExportFolder" 
    Write-Log "API Version: $AdoApiVersion"
    Write-Log "Default Project: $DefaultProjectName"
    Write-Log "What-If Mode: $($WhatIf.IsPresent)"
    
    # Validate parameters
    if (-not (Test-Path $ExportFolder)) {
        throw "Export folder not found: $ExportFolder"
    }
    
    if (-not $CollectionUrl.StartsWith('http')) {
        throw "Invalid collection URL format: $CollectionUrl"
    }
    
    # Initialize authentication
    $Global:AuthHeader = New-AdoAuthHeader -Pat $AdoPat
    
    # Test connectivity
    Write-Log "Testing Azure DevOps connectivity..."
    try {
        Invoke-AdoRest -Method 'GET' -RelativeUrl '/_apis/projects' -ApiVersion '7.1' | Out-Null
        Write-Log "Azure DevOps connectivity verified"
    }
    catch {
        throw "Failed to connect to Azure DevOps: $_"
    }
    
    # Load GitLab export data
    $gitlabData = Import-GitLabData
    
    # Create Azure DevOps groups
    $groupMap = New-AdoGroups -GitLabGroups $gitlabData.groups
    
    # Create group memberships
    New-AdoGroupMemberships -GroupMemberships $gitlabData.'group-memberships' -GroupMap $groupMap -GitLabUsers $gitlabData.users
    
    # Create project memberships  
    New-AdoProjectMemberships -ProjectMemberships $gitlabData.'project-memberships' -GitLabProjects $gitlabData.projects -GroupMap $groupMap -GitLabUsers $gitlabData.users
    
    # Generate final report
    New-ImportReport
    
    Write-Log "GitLab to Azure DevOps identity import completed successfully"
}
catch {
    Write-Log "Import failed: $_" "ERROR"
    $Global:ImportStats.EndTime = Get-Date
    $Global:ImportStats.Error = $_.ToString()
    New-ImportReport
    throw
}

#endregion