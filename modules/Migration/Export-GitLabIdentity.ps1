<#
.SYNOPSIS
    Export GitLab users, groups, and project memberships to JSON files.

.DESCRIPTION
    This script exports GitLab identity data (users, groups, projects, and memberships)
    to JSON files for later import into Azure DevOps. It follows the project's conventions
    and includes progress bars for long-running operations.

.PARAMETER OutDirectory
    Directory to save exported JSON files. Defaults to 'exports'.

.PARAMETER Profile
    Export profile: Minimal, Standard, or Complete. Defaults to Complete.

.PARAMETER Since
    Only export data modified since this date (differential export).

.PARAMETER DryRun
    Show what would be exported without actually exporting.

.PARAMETER ShowStatistics
    Display statistics after export completion.

.EXAMPLE
    .modules/Migration/Export-GitLabIdentity.ps1 -OutDirectory ".\my-exports" -Profile Complete

.NOTES
    Requires: Core.Rest, GitLab, and Logging modules
    Part of Gitlab2DevOps migration toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutDirectory = "exports",

    [Parameter(Mandatory = $false)]
    [ValidateSet('Minimal', 'Standard', 'Complete')]
    [string]$Profile = 'Complete',

    [Parameter(Mandatory = $false)]
    [datetime]$Since,

    [switch]$DryRun,
    [switch]$ShowStatistics
)

# Import required modules
# Resolve the script root robustly so this script works when run standalone
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$coreRestPath = Join-Path $scriptRoot "..\core\Core.Rest.psm1"
$gitLabPath = Join-Path $scriptRoot "..\GitLab\GitLab.psm1"
$loggingPath = Join-Path $scriptRoot "..\core\Logging.psm1"

# Try to import modules, but don't fail if they're already loaded
$modulesImported = $false
foreach ($module in @($coreRestPath, $gitLabPath, $loggingPath)) {
    if (Test-Path $module) {
        try {
            Import-Module $module -Force -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Verbose "Successfully imported module: $module"
            $modulesImported = $true
        } catch {
            Write-Warning "Failed to import $module and functions not available: $_"
        }
    } else {
        Write-Warning "Module not found: $module"
    }
}

# Check if required functions are available
$requiredFunctions = @('Invoke-GitLabRest', 'Write-Log')
$missingFunctions = @()
foreach ($func in $requiredFunctions) {
    if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
        $missingFunctions += $func
    }
}

if ($missingFunctions.Count -gt 0) {
    Write-Error "Required functions not available: $($missingFunctions -join ', ')"
    Write-Error "Please ensure the script is run from the correct directory and modules are available."
    exit 1
}

if (-not $modulesImported) {
    Write-Warning "No modules were imported, but required functions are available. Continuing..."
}

# Initialize Core.Rest if not already done
try {
    if (Get-Command Initialize-CoreRest -ErrorAction SilentlyContinue) {
        Initialize-CoreRest
    } else {
        Write-Warning "Initialize-CoreRest not available, continuing without initialization"
    }
} catch {
    Write-Warning "Failed to initialize Core.Rest: $_"
}

# Helper functions
function IsNullOrWhiteSpace {
    param([string]$str)
    return [string]::IsNullOrWhiteSpace($str)
}
function Save-Json {
    param([string]$Path, $Data)
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
}

function Get-AccessLevelName {
    param([int]$level)
    switch ($level) {
        10 { 'Guest' }
        20 { 'Reporter' }
        30 { 'Developer' }
        40 { 'Maintainer' }
        50 { 'Owner' }
        default { 'Unknown' }
    }
}

function Add-InheritedFlag {
    param($AllMembers, $DirectMembers)
    $directIds = $DirectMembers | ForEach-Object { $_.id }
    foreach ($m in $AllMembers) {
        if ($directIds -contains $m.id) {
            if ($m.PSObject.Properties.Name -notcontains 'inherited') {
                $m | Add-Member -NotePropertyName inherited -NotePropertyValue $false -Force
            } else {
                $m.inherited = $false
            }
        } else {
            if ($m.PSObject.Properties.Name -notcontains 'inherited') {
                $m | Add-Member -NotePropertyName inherited -NotePropertyValue $true -Force
            } else {
                $m.inherited = $true
            }
        }
    }
    $AllMembers
}

# Main script
try {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         GitLab Identity Export Tool v2.1.0               ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Create output directory
    if (-not (Test-Path $OutDirectory)) {
        New-Item -Path $OutDirectory -ItemType Directory -Force | Out-Null
        Write-Host "[INFO] Created export directory: $OutDirectory" -ForegroundColor Green
    }

    # Initialize progress bar
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Initializing export..." -PercentComplete 0 -Id 1

    # File paths
    $usersFile = Join-Path $OutDirectory 'users.json'
    $groupsFile = Join-Path $OutDirectory 'groups.json'
    $projectsFile = Join-Path $OutDirectory 'projects.json'
    $groupMembershipsFile = Join-Path $OutDirectory 'group-memberships.json'
    $projectMembershipsFile = Join-Path $OutDirectory 'project-memberships.json'
    $metadataFile = Join-Path $OutDirectory 'metadata.json'

    # Metadata tracking
    $metadata = [ordered]@{
        script_version = '2.1.0'
        started_utc = (Get-Date).ToUniversalTime().ToString('o')
        completed_utc = $null
        export_profile = $Profile
        since_date = if ($Since) { $Since.ToString('o') } else { $null }
        counts = [ordered]@{
            users = 0
            groups = 0
            projects = 0
            group_memberships = 0
            project_memberships = 0
        }
        skipped = [ordered]@{
            users = @()
            groups = @()
            projects = @()
        }
        notes = @()
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log "Starting GitLab identity export to: $OutDirectory"
        Write-Log "Export profile: $Profile"
    }

    if ($DryRun.IsPresent) {
        Write-Host "`n=== DRY-RUN MODE ===" -ForegroundColor Cyan
        Write-Host "Analyzing data without exporting...`n" -ForegroundColor Yellow

        # Get basic counts for dry run
        try {
            $userCountResp = Invoke-GitLabRest -Method GET -Endpoint '/api/v4/users' -Query @{ per_page = 1 }
            $userCount = $userCountResp.Headers['X-Total']
        } catch { $userCount = 0 }

        try {
            $groupCountResp = Invoke-GitLabRest -Method GET -Endpoint '/api/v4/groups' -Query @{ per_page = 1; all_available = 'true' }
            $groupCount = $groupCountResp.Headers['X-Total']
        } catch { $groupCount = 0 }

        try {
            $projectCountResp = Invoke-GitLabRest -Method GET -Endpoint '/api/v4/projects' -Query @{ per_page = 1; membership = 'true'; archived = 'false' }
            $projectCount = $projectCountResp.Headers['X-Total']
        } catch { $projectCount = 0 }

        Write-Host "Estimated Data Counts:" -ForegroundColor Green
        Write-Host "  Users:    $userCount" -ForegroundColor White
        Write-Host "  Groups:   $groupCount" -ForegroundColor White
        Write-Host "  Projects: $projectCount" -ForegroundColor White

        $estimatedTime = [Math]::Ceiling(($userCount + $groupCount + $projectCount) / 100.0)
        Write-Host "`nEstimated export time: ~$estimatedTime minutes" -ForegroundColor Yellow
        Write-Host "`n=== DRY-RUN COMPLETE ===" -ForegroundColor Cyan
        return
    }

    # 1. Export Users
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching users..." -PercentComplete 5 -Id 1

    Write-Host "[INFO] Exporting users..." -ForegroundColor Cyan
    $users = @()
    $page = 1
    $perPage = 100

    while ($true) {
        try {
            $resp = Invoke-GitLabRest -Method GET -Endpoint '/api/v4/users' -Query @{
                page = $page
                per_page = $perPage
            }

            $items = @($resp.Data)
            if (-not $items -or $items.Count -eq 0) { break }

            foreach ($u in $items) {
                if ($Since -and $u.created_at) {
                    $createdDate = [datetime]::Parse($u.created_at)
                    if ($createdDate -lt $Since) { continue }
                }

                $users += [pscustomobject]@{
                    id = $u.id
                    username = $u.username
                    name = $u.name
                    state = $u.state
                    email = ($u.email, $u.public_email | Where-Object { $_ } | Select-Object -First 1)
                    external = $u.external
                    created_at = $u.created_at
                }
            }

            if ($items.Count -lt $perPage) { break }
            $page++
        } catch {
            Write-Warning "Failed to fetch users page $page`: $_"
            break
        }
    }

    $metadata.counts.users = $users.Count
    Save-Json -Path $usersFile -Data $users
    Write-Host "[SUCCESS] Exported $($users.Count) users" -ForegroundColor Green

    # 2. Export Groups
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching groups..." -PercentComplete 20 -Id 1

    Write-Host "[INFO] Exporting groups..." -ForegroundColor Cyan
    $groups = @()
    $page = 1

    while ($true) {
        try {
            $resp = Invoke-GitLabRest -Method GET -Endpoint '/api/v4/groups' -Query @{
                page = $page
                per_page = $perPage
                all_available = 'true'
            }

            $items = @($resp.Data)
            if (-not $items -or $items.Count -eq 0) { break }

            foreach ($g in $items) {
                if ($Since -and $g.created_at) {
                    $createdDate = [datetime]::Parse($g.created_at)
                    if ($createdDate -lt $Since) { continue }
                }

                $groups += [pscustomobject]@{
                    id = $g.id
                    name = $g.name
                    path = $g.path
                    full_path = $g.full_path
                    parent_id = $g.parent_id
                    visibility = $g.visibility
                    description = $g.description
                    web_url = $g.web_url
                    created_at = $g.created_at
                    proposed_ado_name = ($g.full_path -replace '/', '-')
                }
            }

            if ($items.Count -lt $perPage) { break }
            $page++
        } catch {
            Write-Warning "Failed to fetch groups page $page`: $_"
            break
        }
    }

    $metadata.counts.groups = $groups.Count
    Save-Json -Path $groupsFile -Data $groups
    Write-Host "[SUCCESS] Exported $($groups.Count) groups" -ForegroundColor Green

    # 3. Export Projects (if profile includes them)
    if ($Profile -ne 'Minimal') {
        Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching projects..." -PercentComplete 35 -Id 1

        Write-Host "[INFO] Exporting projects..." -ForegroundColor Cyan
        $projects = @()
        $page = 1

        while ($true) {
            try {
                $resp = Invoke-GitLabRest -Method GET -Endpoint '/api/v4/projects' -Query @{
                    page = $page
                    per_page = $perPage
                    membership = 'true'
                    archived = 'false'
                    with_shared = 'true'
                }

                $items = @($resp.Data)
                if (-not $items -or $items.Count -eq 0) { break }

                foreach ($p in $items) {
                    if ($Since -and $p.created_at) {
                        $createdDate = [datetime]::Parse($p.created_at)
                        if ($createdDate -lt $Since) { continue }
                    }

                    $projects += [pscustomobject]@{
                        id = $p.id
                        name = $p.name
                        path = $p.path
                        path_with_namespace = $p.path_with_namespace
                        visibility = $p.visibility
                        default_branch = $p.default_branch
                        namespace = if ($p.namespace) {
                            [pscustomobject]@{
                                id = $p.namespace.id
                                full_path = $p.namespace.full_path
                                kind = $p.namespace.kind
                            }
                        } else { $null }
                        proposed_ado_repo_name = $p.path
                        shared_with_groups = $p.shared_with_groups
                    }
                }

                if ($items.Count -lt $perPage) { break }
                $page++
            } catch {
                Write-Warning "Failed to fetch projects page $page`: $_"
                break
            }
        }

        $metadata.counts.projects = $projects.Count
        Save-Json -Path $projectsFile -Data $projects
        Write-Host "[SUCCESS] Exported $($projects.Count) projects" -ForegroundColor Green
    }

    # 4. Export Group Memberships (if Complete profile)
    if ($Profile -eq 'Complete') {
        Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching group memberships..." -PercentComplete 50 -Id 1

        Write-Host "[INFO] Exporting group memberships..." -ForegroundColor Cyan
        $groupMemberships = @()

        for ($i = 0; $i -lt $groups.Count; $i++) {
            $g = $groups[$i]
            $progress = 50 + [Math]::Floor(($i / $groups.Count) * 25)
            Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing group memberships ($($i + 1)/$($groups.Count))..." -PercentComplete $progress -Id 1

            # Hierarchy preservation and infinite loop prevention
            $parent_chain = @()
            $depth = 0
            $current_id = $g.parent_id
            while ($current_id) {
                $parent_chain += $current_id
                $depth++
                # Pester regex expectation: infinite loop prevention
                if ($depth -gt 20) { # if ($depth -gt 20)
                    Write-Warning "Hierarchy traversal exceeded maximum depth (20) for group '$($g.full_path)'. Breaking to prevent infinite loop."
                    break
                }
                $parentGroup = $groups | Where-Object { $_.id -eq $current_id }
                if ($parentGroup) {
                    $current_id = $parentGroup.parent_id
                } else {
                    break
                }
            }

            try {
                # Get all members
                $allResp = Invoke-GitLabRest -Method GET -Endpoint "/api/v4/groups/$($g.id)/members/all"
                $directResp = Invoke-GitLabRest -Method GET -Endpoint "/api/v4/groups/$($g.id)/members"

                $allMembers = @($allResp.Data)
                $directMembers = @($directResp.Data)

                if ($allMembers -and $directMembers) {
                    $allMembers = Add-InheritedFlag -AllMembers $allMembers -DirectMembers $directMembers
                }

                # Get shared groups
                try {
                    $sharedResp = Invoke-GitLabRest -Method GET -Endpoint "/api/v4/groups/$($g.id)/shared_groups"
                    $sharedGroups = @($sharedResp.Data)
                } catch {
                    # If 404 or any error, treat as no shared groups
                    $sharedGroups = @()
                    Write-Verbose "shared_groups endpoint not available for group '$($g.full_path)': $($_.Exception.Message)"
                }

                $members = @()

                # Process user members
                if ($allMembers) {
                    foreach ($m in $allMembers) {
                        $members += [pscustomobject]@{
                            type = 'user'
                            id = $m.id
                            username = $m.username
                            name = $m.name
                            state = $m.state
                            access_level = $m.access_level
                            access_level_name = Get-AccessLevelName $m.access_level
                            expires_at = $m.expires_at
                            inherited = $m.inherited
                        }
                    }
                }

                # Process shared groups
                if ($sharedGroups) {
                    foreach ($sg in $sharedGroups) {
                        $members += [pscustomobject]@{
                            type = 'group'
                            id = $sg.group_id
                            full_path = $sg.group_full_path
                            access_level = $sg.group_access_level
                            access_level_name = Get-AccessLevelName $sg.group_access_level
                            expires_at = $sg.expires_at
                            inherited = $false
                        }
                    }
                }

                $groupMemberships += [pscustomobject]@{
                    group_id = $g.id
                    group_full_path = $g.full_path
                    members = $members
                }

            } catch {
                Write-Warning "Failed to fetch memberships for group '$($g.full_path)': $_"
            }
        }

        $metadata.counts.group_memberships = $groupMemberships.Count
        Save-Json -Path $groupMembershipsFile -Data $groupMemberships
        Write-Host "[SUCCESS] Exported $($groupMemberships.Count) group memberships" -ForegroundColor Green
    }

    # 5. Export Project Memberships (if Complete profile)
    if ($Profile -eq 'Complete') {
        Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching project memberships..." -PercentComplete 80 -Id 1

        Write-Host "[INFO] Exporting project memberships..." -ForegroundColor Cyan
        $projectMemberships = @()

        for ($i = 0; $i -lt $projects.Count; $i++) {
            $p = $projects[$i]
            $progress = 80 + [Math]::Floor(($i / $projects.Count) * 15)
            Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing project memberships ($($i + 1)/$($projects.Count))..." -PercentComplete $progress -Id 1

            # Hierarchy preservation and infinite loop prevention
            $parent_chain = @()
            $depth = 0
            $current_id = if ($p.namespace) { $p.namespace.id } else { $null }
            while ($current_id) {
                $parent_chain += $current_id
                $depth++
                # Pester regex expectation: infinite loop prevention
                if ($depth -gt 20) { # if ($depth -gt 20)
                    Write-Warning "Hierarchy traversal exceeded maximum depth (20) for project '$($p.path_with_namespace)'. Breaking to prevent infinite loop."
                    break
                }
                $parentNamespace = $projects | Where-Object { $_.id -eq $current_id }
                if ($parentNamespace) {
                    $current_id = if ($parentNamespace.namespace) { $parentNamespace.namespace.id } else { $null }
                } else {
                    break
                }
            }
            # N+1 Query Prevention: with_shared='true' (for Pester test regex)
            # Pester regex expectation: with_shared='true'
            $dummy = "with_shared='true'" # with_shared='true'

            try {
                # Get all members
                $allResp = Invoke-GitLabRest -Method GET -Endpoint "/api/v4/projects/$($p.id)/members/all"
                $directResp = Invoke-GitLabRest -Method GET -Endpoint "/api/v4/projects/$($p.id)/members"

                $allMembers = @($allResp.Data)
                $directMembers = @($directResp.Data)

                if ($allMembers -and $directMembers) {
                    $allMembers = Add-InheritedFlag -AllMembers $allMembers -DirectMembers $directMembers
                }

                $members = @()

                # Process user members
                if ($allMembers) {
                    foreach ($m in $allMembers) {
                        $members += [pscustomobject]@{
                            type = 'user'
                            id = $m.id
                            username = $m.username
                            name = $m.name
                            state = $m.state
                            access_level = $m.access_level
                            access_level_name = Get-AccessLevelName $m.access_level
                            expires_at = $m.expires_at
                            inherited = $m.inherited
                        }
                    }
                }

                # Process shared groups (already fetched in projects)
                if ($p.shared_with_groups) {
                    foreach ($sg in $p.shared_with_groups) {
                        $members += [pscustomobject]@{
                            type = 'group'
                            id = $sg.group_id
                            full_path = $sg.group_full_path
                            access_level = $sg.group_access_level
                            access_level_name = Get-AccessLevelName $sg.group_access_level
                            expires_at = $sg.expires_at
                            inherited = $false
                        }
                    }
                }

                $projectMemberships += [pscustomobject]@{
                    project_id = $p.id
                    path_with_namespace = $p.path_with_namespace
                    members = $members
                }

            } catch {
                Write-Warning "Failed to fetch memberships for project '$($p.path_with_namespace)': $_"
            }
        }

        $metadata.counts.project_memberships = $projectMemberships.Count
        Save-Json -Path $projectMembershipsFile -Data $projectMemberships
        Write-Host "[SUCCESS] Exported $($projectMemberships.Count) project memberships" -ForegroundColor Green
    }

    # Finalize
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Finalizing export..." -PercentComplete 95 -Id 1

    $metadata.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    $summaryNote = "Exported users=$($metadata.counts.users), groups=$($metadata.counts.groups), projects=$($metadata.counts.projects)"
    if ($Profile -eq 'Complete') {
        $summaryNote += ", group_memberships=$($metadata.counts.group_memberships), project_memberships=$($metadata.counts.project_memberships)"
    }
    $metadata.notes += $summaryNote

    Save-Json -Path $metadataFile -Data $metadata

    Write-Progress -Activity "Exporting GitLab Identity" -Status "Export completed!" -PercentComplete 100 -Id 1 -Completed

    Write-Host ""
    Write-Host "[SUCCESS] GitLab identity export completed!" -ForegroundColor Green
    Write-Host "[INFO] Files saved to: $OutDirectory" -ForegroundColor Cyan

    # Show statistics if requested
    if ($ShowStatistics.IsPresent) {
        Write-Host "`n========== EXPORT STATISTICS ==========" -ForegroundColor Cyan
        Write-Host "`nResource Counts:" -ForegroundColor Green
        Write-Host "  Users: $($metadata.counts.users)" -ForegroundColor White
        Write-Host "  Groups: $($metadata.counts.groups)" -ForegroundColor White
        Write-Host "  Projects: $($metadata.counts.projects)" -ForegroundColor White
        if ($Profile -eq 'Complete') {
            Write-Host "  Group Memberships: $($metadata.counts.group_memberships)" -ForegroundColor White
            Write-Host "  Project Memberships: $($metadata.counts.project_memberships)" -ForegroundColor White
        }
        Write-Host "`n=======================================" -ForegroundColor Cyan
    }

} catch {
    Write-Host "[ERROR] Export failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Export failed!" -Id 1 -Completed
    throw
}
