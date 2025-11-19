param(
        [Parameter(Mandatory=$false)]
        [string]$OutDirectory,

        [Parameter(Mandatory=$false)]
        [ValidateRange(1,1000)]
        [int]$PageSize = 100,

        [Parameter(Mandatory=$false)]
        [ValidateSet('v4','v5')]
        [string]$ApiVersion = 'v4',

        [Parameter(Mandatory=$false)]
        [ValidateSet('Minimal','Standard','Complete')]
        [string]$Profile = 'Complete',

        [Parameter(Mandatory=$false)]
        [datetime]$Since,

        [switch]$IncludeMemberRoles,

        [switch]$Resume,

        [switch]$DryRun,

        [switch]$ShowStatistics
)

Import-Module "$PSScriptRoot\..\core\Logging.psm1" -Force -DisableNameChecking -WarningAction SilentlyContinue
Import-Module -Name "$PSScriptRoot\..\core\EnvLoader.psm1"
Import-Module -Name "$PSScriptRoot\..\core\Core.Rest.psm1"
Import-Module -Name "$PSScriptRoot\..\core\Logging.psm1"
Import-Module -Name "$PSScriptRoot\..\GitLab\GitLab.psm1"

function Save-Json {
    param([string]$Path, $Data)
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
}

function Invoke-GitLabPagedRequest {
    param([string]$Endpoint, [hashtable]$Query = @{})
    try {
        $resp = Invoke-GitLabRest -Method GET -Endpoint $Endpoint -Query $Query
        [pscustomobject]@{
            Items = $resp.Data
            Denied = $resp.Status -ne 200
        }
    }
    catch {
        # For 404 or other errors, treat as denied/not available
        [pscustomobject]@{
            Items = $null
            Denied = $true
        }
    }
}

function Add-InheritedFlag {
    param($AllMembers, $DirectMembers)
    $directIds = $DirectMembers | ForEach-Object { $_.id }
    foreach ($m in $AllMembers) {
        if ($directIds -contains $m.id) {
            $m | Add-Member -NotePropertyName inherited -NotePropertyValue $false -Force
        } else {
            $m | Add-Member -NotePropertyName inherited -NotePropertyValue $true -Force
        }
    }
    $AllMembers
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

$script:logFile = $null
$script:IsLibraryImport = ($MyInvocation.InvocationName -eq '.')
if ($script:IsLibraryImport) {
    return
}

# Load .env if exists
$envFile = Join-Path (Get-Location) '.env'
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile
    foreach ($line in $envContent) {
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            [Environment]::SetEnvironmentVariable($key, $value, [EnvironmentVariableTarget]::Process)
        }
    }
}

# Set dummy values for testing if not set
if (-not $env:GITLAB_BASE_URL) { $env:GITLAB_BASE_URL = 'https://gitlab.com' }
if (-not $env:GITLAB_PAT) { $env:GITLAB_PAT = 'dummy' }

Initialize-CoreRest
$config = Get-CoreRestConfig

$GitLabBaseUrl = $config.GitLabBaseUrl
$GitLabToken = $config.GitLabToken
$script:PageSize = $PageSize
$script:ApiVersion = $ApiVersion

# ---------------------------
# Constants & Globals
# ---------------------------
$Script:ScriptVersion = '1.0.0'
$Script:StartedAtUtc = (Get-Date).ToUniversalTime()
$Script:StartedAtUtcIso = $Script:StartedAtUtc.ToString('o')  # Cache formatted date
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Invoke-WebRequest:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['Invoke-RestMethod:ErrorAction'] = 'Stop'


# Normalize base URL (no trailing slash)
if ($GitLabBaseUrl.EndsWith('/')) {
    $GitLabBaseUrl = $GitLabBaseUrl.TrimEnd('/')
}
$script:GitLabBaseUrl = $GitLabBaseUrl

# Materialize token value
$PlainToken = $GitLabToken
$script:PlainToken = $PlainToken

# Wrap entire script execution in try-finally for token cleanup
try {

# Default export folder
if (-not $OutDirectory) {
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    $OutDirectory = Join-Path -Path (Get-Location) -ChildPath ("export-gitlab-identity-$stamp")
}

# Ensure output directory exists
if (-not (Test-Path -LiteralPath $OutDirectory)) {
    New-Item -Path $OutDirectory -ItemType Directory | Out-Null
}

# File paths
$usersFile              = Join-Path $OutDirectory 'users.json'
$groupsFile             = Join-Path $OutDirectory 'groups.json'
$projectsFile           = Join-Path $OutDirectory 'projects.json'
$groupMembershipsFile   = Join-Path $OutDirectory 'group-memberships.json'
$projectMembershipsFile = Join-Path $OutDirectory 'project-memberships.json'
$memberRolesFile        = Join-Path $OutDirectory 'member-roles.json'
$metadataFile           = Join-Path $OutDirectory 'metadata.json'
$logFile                = Join-Path $OutDirectory 'export.log'
$script:logFile         = $logFile

# Resume detection - check for existing completed exports
$resumeFlags = @{
    users              = (Test-Path $usersFile)
    groups             = (Test-Path $groupsFile)
    projects           = (Test-Path $projectsFile)
    group_memberships  = (Test-Path $groupMembershipsFile)
    project_memberships = (Test-Path $projectMembershipsFile)
    member_roles       = (Test-Path $memberRolesFile)
}

if ($Resume.IsPresent) {
    $resumeCount = ($resumeFlags.Values | Where-Object { $_ }).Count
    if ($resumeCount -gt 0) {
        Write-Host "[RESUME] Found $resumeCount existing export file(s) in $OutDirectory" -ForegroundColor Yellow
        Write-Host "[RESUME] Will skip already-exported phases" -ForegroundColor Yellow
    }
    else {
        Write-Host "[RESUME] No existing exports found, performing full export" -ForegroundColor Yellow
    }
}
elseif (($resumeFlags.Values | Where-Object { $_ }).Count -gt 0) {
    Write-Host "[WARN] Export directory already contains files. Use -Resume to skip completed phases or delete directory for fresh export." -ForegroundColor Yellow
}


# ---------------------------
# Initialize metadata
# ---------------------------
$metadata = [ordered]@{
    script_version         = $Script:ScriptVersion
    started_utc            = $Script:StartedAtUtcIso
    completed_utc          = $null
    gitlab_base_url        = $GitLabBaseUrl
    gitlab_api_version     = $ApiVersion
    export_profile         = $Profile
    since_date             = if ($Since) { $Since.ToString('o') } else { $null }
    token_user             = $null
    page_size              = $PageSize
    counts                 = [ordered]@{ users = 0; groups = 0; projects = 0; group_memberships = 0; project_memberships = 0; member_roles = 0 }
    skipped                = [ordered]@{ users = @(); groups = @(); projects = @() }
    fallbacks              = [ordered]@{ groups_members_all_denied = @(); projects_members_all_denied = @() }
    notes                  = @()
}

Write-Log "Export started. Output directory: $OutDirectory"
Write-Log "Export profile: $Profile"
if ($Since) { Write-Log "Differential export since: $($Since.ToString('o'))" }

# Identify token user
try {
    $me = (Invoke-GitLabRest -Method GET -Endpoint '/user').Data
    if ($me) {
        $metadata.token_user = [ordered]@{ id=$me.id; username=$me.username; name=$me.name }
        Write-Log "Authenticated as $($me.username) (id=$($me.id))"
    }
}
catch {
    Write-Log "Failed to get /user for token identity: $($_.ToString())" 'WARN'
}

# ---------------------------
# DRY-RUN MODE: Estimate counts and exit
# ---------------------------
if ($DryRun.IsPresent) {
    Write-Host "`n=== DRY-RUN MODE ===" -ForegroundColor Cyan
    Write-Host "Querying resource counts (no data exported)...`n" -ForegroundColor Yellow
    
    # Helper to get count from X-Total header
    function Get-ResourceCount {
        param([string]$Endpoint, [hashtable]$Query = @{})
        try {
            $query1 = $Query.Clone()
            $query1.per_page = 1
            $resp = Invoke-GitLabRest -Method GET -Endpoint $Endpoint -Query $query1
            $total = $resp.Headers['X-Total']
            $total = if ($total -is [array]) { $total[0] } else { $total }
            if ($total) { return [int]$total }
            return 0
        }
        catch { return 0 }
    }
    
    # Query counts
    $dryRunCounts = [ordered]@{
        users              = Get-ResourceCount '/users'
        groups             = Get-ResourceCount '/groups' @{ all_available = 'true' }
        projects           = Get-ResourceCount '/projects' @{ membership = 'true'; archived = 'false' }
    }
    
    # Estimate API calls per resource
    $avgGroupMembers = 20        # Average members per group
    $avgProjectMembers = 10      # Average members per project
    $membershipsPerPage = $PageSize
    
    $estimatedCalls = @{
        users_pages        = [Math]::Ceiling($dryRunCounts.users / $PageSize)
        groups_pages       = [Math]::Ceiling($dryRunCounts.groups / $PageSize)
        projects_pages     = [Math]::Ceiling($dryRunCounts.projects / $PageSize)
        group_members_all  = $dryRunCounts.groups * [Math]::Ceiling($avgGroupMembers / $membershipsPerPage)
        group_members_dir  = $dryRunCounts.groups * [Math]::Ceiling($avgGroupMembers / $membershipsPerPage)
        project_members_all = $dryRunCounts.projects * [Math]::Ceiling($avgProjectMembers / $membershipsPerPage)
        project_members_dir = $dryRunCounts.projects * [Math]::Ceiling($avgProjectMembers / $membershipsPerPage)
    }
    
    $totalCalls = ($estimatedCalls.Values | Measure-Object -Sum).Sum
    $avgTimePerCall = 0.5  # seconds (conservative estimate)
    $estimatedMinutes = [Math]::Ceiling(($totalCalls * $avgTimePerCall) / 60)
    
    # Display results
    Write-Host "Resource Counts:" -ForegroundColor Green
    Write-Host "  Users:    $($dryRunCounts.users)" -ForegroundColor White
    Write-Host "  Groups:   $($dryRunCounts.groups)" -ForegroundColor White
    Write-Host "  Projects: $($dryRunCounts.projects)" -ForegroundColor White
    Write-Host "`nEstimated API Calls:" -ForegroundColor Green
    Write-Host "  User pages:              $($estimatedCalls.users_pages)" -ForegroundColor White
    Write-Host "  Group pages:             $($estimatedCalls.groups_pages)" -ForegroundColor White
    Write-Host "  Project pages:           $($estimatedCalls.projects_pages)" -ForegroundColor White
    Write-Host "  Group memberships:       $($estimatedCalls.group_members_all + $estimatedCalls.group_members_dir) (all + direct)" -ForegroundColor White
    Write-Host "  Project memberships:     $($estimatedCalls.project_members_all + $estimatedCalls.project_members_dir) (all + direct)" -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  TOTAL:                   $totalCalls calls" -ForegroundColor Cyan
    Write-Host "`nEstimated Time: ~$estimatedMinutes minutes (at $avgTimePerCall sec/call avg)" -ForegroundColor Yellow
    Write-Host "`nNOTE: Actual time depends on instance size, rate limits, and network latency." -ForegroundColor DarkGray
    Write-Host "      Membership estimates assume avg $avgGroupMembers members/group, $avgProjectMembers members/project." -ForegroundColor DarkGray
    Write-Host "`n=== DRY-RUN COMPLETE (no data exported) ===" -ForegroundColor Cyan
    return
}

# ---------------------------
# 1) Export Users (GET /users - paged)
# ---------------------------
if ($Resume.IsPresent -and $resumeFlags.users) {
    Write-Log "[RESUME] Skipping users export - $usersFile already exists"
    $users = Get-Content -LiteralPath $usersFile -Raw | ConvertFrom-Json
    $users = if ($null -eq $users) { @() } elseif ($users -is [array]) { $users } else { @($users) }
    $metadata.counts.users = $users.Count
}
else {
    Write-Log 'Fetching users (GET /api/v4/users)...'
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching users..." -PercentComplete 10
    $usersResp = Invoke-GitLabPagedRequest -Endpoint '/users'
    if ($usersResp.Denied) {
        Write-Log 'Access denied to /users. Continuing without users.' 'ERROR'
        $users = @()
    }
    else {
        $usersRaw = $usersResp.Items
        if ($null -eq $usersRaw) { $usersRaw = @() } elseif ($usersRaw -isnot [array]) { $usersRaw = @($usersRaw) }
        $userIndex = 0
        $users = foreach ($u in $usersRaw) {
            $userIndex++
            if ($usersRaw.Count -gt 0 -and $userIndex % 100 -eq 0) {
                $pct = [Math]::Min(15, 10 + (($userIndex / $usersRaw.Count) * 5))
                Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing users ($userIndex/$($usersRaw.Count))..." -PercentComplete $pct
            }
            # Validate critical fields - skip users with missing id/username
            if (-not $u.id -or [string]::IsNullOrWhiteSpace($u.username)) {
                Write-Log "SKIP: User missing critical fields: id=$($u.id) username='$($u.username)' name='$($u.name)'" 'WARN'
                $metadata.skipped.users += [pscustomobject]@{ 
                    id = $u.id
                    username = $u.username
                    name = $u.name
                    reason = 'Missing id or username'
                }
                continue
            }
            # Apply Since filter if specified
            if ($Since -and $u.created_at) {
                $createdDate = [datetime]::Parse($u.created_at)
                if ($createdDate -lt $Since) { continue }
            }
            [pscustomobject]@{
                id          = $u.id
                username    = $u.username
                name        = $u.name
                state       = $u.state
                email       = ($u.email, $u.public_email | Where-Object { $_ } | Select-Object -First 1)
                external    = $u.external
                created_at  = $u.created_at
            }
        }
        $users = if ($null -eq $users) { @() } elseif ($users -is [array]) { $users } else { @($users) }
    }
    $metadata.counts.users = $users.Count
    Save-Json -Path $usersFile -Data $users
    Write-Log "Users exported: $($users.Count) -> $usersFile"
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Users complete" -PercentComplete 15
    # Write metadata checkpoint after users phase
    Save-Json -Path $metadataFile -Data $metadata
}

# ---------------------------
# 2) Export Groups (GET /groups - paged)
# ---------------------------
if ($Resume.IsPresent -and $resumeFlags.groups) {
    Write-Log "[RESUME] Skipping groups export - $groupsFile already exists"
    $groups = Get-Content -LiteralPath $groupsFile -Raw | ConvertFrom-Json
    $groups = if ($null -eq $groups) { @() } elseif ($groups -is [array]) { $groups } else { @($groups) }
    $metadata.counts.groups = $groups.Count
}
else {
    Write-Log 'Fetching groups (GET /api/v4/groups)...'
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching groups..." -PercentComplete 20
    $groupsResp = Invoke-GitLabPagedRequest -Endpoint '/groups' -Query @{ all_available = 'true' }
    if ($groupsResp.Denied) {
        Write-Log 'Access denied to /groups. Continuing without groups.' 'ERROR'
        $groups = @()
    }
    else {
        $groupsRaw = $groupsResp.Items
        if ($null -eq $groupsRaw) { $groupsRaw = @() } elseif ($groupsRaw -isnot [array]) { $groupsRaw = @($groupsRaw) }
        # Build parent lookup for hierarchy computation
        $groupLookup = @{}
        foreach ($g in $groupsRaw) { $groupLookup[[string]$g.id] = $g }
        
        $groupIndex = 0
        $groups = foreach ($g in $groupsRaw) {
            $groupIndex++
            if ($groupsRaw.Count -gt 0 -and $groupIndex % 50 -eq 0) {
                $pct = [Math]::Min(30, 20 + (($groupIndex / $groupsRaw.Count) * 10))
                Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing groups ($groupIndex/$($groupsRaw.Count))..." -PercentComplete $pct
            }
            # Validate critical fields
            if (-not $g.id -or [string]::IsNullOrWhiteSpace($g.full_path)) {
                Write-Log "SKIP: Group missing critical fields: id=$($g.id) full_path='$($g.full_path)'" 'WARN'
                $metadata.skipped.groups += [pscustomobject]@{
                    id = $g.id
                    full_path = $g.full_path
                    reason = 'Missing id or full_path'
                }
                continue
            }
            
            # Apply Since filter if specified
            if ($Since -and $g.created_at) {
                $createdDate = [datetime]::Parse($g.created_at)
                if ($createdDate -lt $Since) { continue }
            }
            
            # Compute parent chain and depth for hierarchy reconstruction
            $parentChain = @()
            $depth = 0
            $currentId = $g.parent_id
            while ($currentId -and $groupLookup.ContainsKey([string]$currentId)) {
                $parent = $groupLookup[[string]$currentId]
                $parentChain += [pscustomobject]@{ id = $parent.id; full_path = $parent.full_path }
                $depth++
                $currentId = $parent.parent_id
                if ($depth -gt 20) { break } # Prevent infinite loops
            }
            [Collections.Array]::Reverse($parentChain) # Root first
            
            $adoName = ($g.full_path -replace '/', '-')
            [pscustomobject]@{
                id                 = $g.id
                name               = $g.name
                path               = $g.path
                full_path          = $g.full_path
                parent_id          = $g.parent_id
                parent_chain       = $parentChain
                depth              = $depth
                visibility         = $g.visibility
                description        = $g.description
                web_url            = $g.web_url
                created_at         = $g.created_at
                proposed_ado_name  = $adoName  # Target shape for later ADO group creation
            }
        }
        $groups = if ($null -eq $groups) { @() } elseif ($groups -is [array]) { $groups } else { @($groups) }
    }
    $metadata.counts.groups = $groups.Count
    Save-Json -Path $groupsFile -Data $groups
    Write-Log "Groups exported: $($groups.Count) -> $groupsFile"
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Groups complete" -PercentComplete 30
    # Write metadata checkpoint after groups phase
    Save-Json -Path $metadataFile -Data $metadata
}

# ---------------------------
# 3) Export Projects (GET /projects - paged)
# ---------------------------
if ($Profile -eq 'Minimal') {
    Write-Log "[PROFILE] Skipping projects export - Minimal profile selected (Profile is set to 'Minimal')"
    $projects = @()
    $metadata.counts.projects = 0
}
elseif ($Resume.IsPresent -and $resumeFlags.projects) {
    Write-Log "[RESUME] Skipping projects export - $projectsFile already exists"
    $projects = Get-Content -LiteralPath $projectsFile -Raw | ConvertFrom-Json
    $projects = if ($null -eq $projects) { @() } elseif ($projects -is [array]) { $projects } else { @($projects) }
    $metadata.counts.projects = $projects.Count
}
else {
    Write-Log 'Fetching projects (GET /api/v4/projects)...'
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Fetching projects..." -PercentComplete 35
    # membership=true limits to projects the token can access; with_shared=false avoids N+1 later
    # NOTE: We do NOT use simple=true because we need shared_with_groups data to avoid N+1 query pattern
    $projectsResp = Invoke-GitLabPagedRequest -Endpoint '/projects' -Query @{ membership='true'; archived='false'; with_shared='true' }
    if ($projectsResp.Denied) {
        Write-Log 'Access denied to /projects. Continuing without projects.' 'ERROR'
        $projects = @()
    }
    else {
        $projectsRaw = $projectsResp.Items
        if ($null -eq $projectsRaw) { $projectsRaw = @() } elseif ($projectsRaw -isnot [array]) { $projectsRaw = @($projectsRaw) }
        $projectIndex = 0
        $projects = foreach ($p in $projectsRaw) {
            $projectIndex++
            if ($projectsRaw.Count -gt 0 -and $projectIndex % 50 -eq 0) {
                $pct = [Math]::Min(50, 35 + (($projectIndex / $projectsRaw.Count) * 15))
                Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing projects ($projectIndex/$($projectsRaw.Count))..." -PercentComplete $pct
            }
            # Validate critical fields
            if (-not $p.id -or [string]::IsNullOrWhiteSpace($p.path_with_namespace)) {
                Write-Log "SKIP: Project missing critical fields: id=$($p.id) path='$($p.path_with_namespace)'" 'WARN'
                $metadata.skipped.projects += [pscustomobject]@{
                    id = $p.id
                    path_with_namespace = $p.path_with_namespace
                    reason = 'Missing id or path_with_namespace'
                }
                continue
            }
            # Apply Since filter if specified
            if ($Since -and $p.created_at) {
                $createdDate = [datetime]::Parse($p.created_at)
                if ($createdDate -lt $Since) { continue }
            }
            $adoRepoName = $p.path  # project path without namespace
            # Namespace info is nested under .namespace
            $ns = $p.namespace
            [pscustomobject]@{
                id                    = $p.id
                name                  = $p.name
                path                  = $p.path
                path_with_namespace   = $p.path_with_namespace
                visibility            = $p.visibility
                default_branch        = $p.default_branch
                namespace             = if ($ns) { [pscustomobject]@{ id=$ns.id; full_path=$ns.full_path; kind=$ns.kind } } else { $null }
                proposed_ado_repo_name = $adoRepoName # Target shape for later ADO repo name
                shared_with_groups    = $p.shared_with_groups  # Preserve for membership export
            }
        }
        $projects = if ($null -eq $projects) { @() } elseif ($projects -is [array]) { $projects } else { @($projects) }
    }
    $metadata.counts.projects = $projects.Count
    Save-Json -Path $projectsFile -Data $projects
    Write-Log "Projects exported: $($projects.Count) -> $projectsFile"
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Projects complete" -PercentComplete 50
    # Write metadata checkpoint after projects phase
    Save-Json -Path $metadataFile -Data $metadata
}

# ---------------------------
# 4) Export Group Memberships (users + group links)
# ---------------------------
if ($Profile -ne 'Complete') {
    Write-Log "[PROFILE] Skipping group memberships export - '$Profile' profile omits memberships"
    $groupMemberships = @()
    $metadata.counts.group_memberships = 0
    $metadata.counts.group_membership_entries = 0
}
elseif ($Resume.IsPresent -and $resumeFlags.group_memberships) {
    Write-Log "[RESUME] Skipping group memberships export - $groupMembershipsFile already exists"
    $groupMemberships = Get-Content -LiteralPath $groupMembershipsFile -Raw | ConvertFrom-Json
    $groupMemberships = if ($null -eq $groupMemberships) { @() } elseif ($groupMemberships -is [array]) { $groupMemberships } else { @($groupMemberships) }
    $metadata.counts.group_memberships = $groupMemberships.Count
    $totalGroupMemberEntries = 0
    foreach ($gm in $groupMemberships) {
        $membersArr = if ($null -eq $gm.members) { @() } elseif ($gm.members -is [array]) { $gm.members } else { @($gm.members) }
        $totalGroupMemberEntries += ($membersArr | Measure-Object).Count
    }
    $metadata.counts.group_membership_entries = $totalGroupMemberEntries
}
else {
    Write-Log 'Exporting group memberships...'
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Exporting group memberships..." -PercentComplete 55
    $groupMemberships = @()
    $groupIdx = 0
    foreach ($g in $groups) {
        $groupIdx++
        if ($groupIdx % 20 -eq 0) {
            $pct = [Math]::Min(70, 55 + (($groupIdx / $groups.Count) * 15))
            Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing group memberships ($groupIdx/$($groups.Count))..." -PercentComplete $pct
        }
        $gid = $g.id
        $gpath = $g.full_path

        try {
            # Users: all vs direct
            try {
                $gmAllResp = Invoke-GitLabPagedRequest -Endpoint "/groups/$gid/members/all"
            }
            catch {
                $gmAllResp = [pscustomobject]@{ Items = $null; Denied = $true }
            }
            try {
                $gmDirectResp = Invoke-GitLabPagedRequest -Endpoint "/groups/$gid/members"
            }
            catch {
                $gmDirectResp = [pscustomobject]@{ Items = $null; Denied = $true }
            }

            $allDenied = $gmAllResp.Denied
            $dirDenied = $gmDirectResp.Denied

            $gmAll = @(); $gmDirect = @()
            if (-not $allDenied) { 
                $gmAll = $gmAllResp.Items
                if ($null -eq $gmAll) { $gmAll = @() } elseif ($gmAll -isnot [array]) { $gmAll = @($gmAll) }
            }
            if (-not $dirDenied) { 
                $gmDirect = $gmDirectResp.Items
                if ($null -eq $gmDirect) { $gmDirect = @() } elseif ($gmDirect -isnot [array]) { $gmDirect = @($gmDirect) }
            }

            if ($allDenied -and -not $dirDenied) {
                # No /all; use direct only and mark inherited=false
                foreach ($m in $gmDirect) { $m | Add-Member -NotePropertyName inherited -NotePropertyValue $false -Force }
                $usersMembers = $gmDirect
            }
            elseif (-not $allDenied -and -not $dirDenied) {
                $usersMembers = Add-InheritedFlag -AllMembers $gmAll -DirectMembers $gmDirect
            }
            else {
                # Both denied
                $usersMembers = @()
            }

            # Get shared groups (optional - may not be available for all groups or GitLab versions)
            $groupLinks = @()
            try {
                try {
                    $sharedGroupsResp = Invoke-GitLabPagedRequest -Endpoint "/groups/$gid/shared_groups"
                }
                catch {
                    $sharedGroupsResp = [pscustomobject]@{ Items = $null; Denied = $true }
                }
                if (-not $sharedGroupsResp.Denied) {
                    $sharedGroups = $sharedGroupsResp.Items
                    if ($null -eq $sharedGroups) { $sharedGroups = @() } elseif ($sharedGroups -isnot [array]) { $sharedGroups = @($sharedGroups) }
                    foreach ($sg in $sharedGroups) {
                        $groupLinks += [pscustomobject]@{
                            type               = 'group'
                            id                 = $sg.group_id
                            full_path          = $sg.group_full_path
                            access_level       = $sg.group_access_level
                            expires_at         = $sg.expires_at
                            inherited          = $false
                        }
                    }
                }
            }
            catch {
                # Shared groups endpoint may not be available or accessible
                Write-Verbose "Shared groups not available for group '$gpath': $($_.ToString())"
            }

            # Normalize user member objects to a common shape
            $userMembersNormalized = foreach ($m in $usersMembers) {
                [pscustomobject]@{
                    type              = 'user'
                    id                = $m.id
                    username          = $m.username
                    name              = $m.name
                    state             = $m.state
                    access_level      = $m.access_level
                    access_level_name = (Get-AccessLevelName $m.access_level)
                    expires_at        = $m.expires_at
                    inherited         = if ($m.PSObject.Properties.Name -contains 'inherited') { $m.inherited } else { $false }
                }
            }

            $groupMemberships += [pscustomobject]@{
                group_id        = $gid
                group_full_path = $gpath
                members         = @($userMembersNormalized + $groupLinks)
            }
        }
        catch {
            $errorMessage = $_.ToString()
            Write-Warning "Failed to fetch memberships for group '$($g.full_path)': $errorMessage"
        }
    }
    $metadata.counts.group_memberships = $groupMemberships.Count
    # Also track total individual member entries (users + group links)
    $totalGroupMemberEntries = 0
    foreach ($gm in $groupMemberships) { $totalGroupMemberEntries += ($gm.members | Measure-Object).Count }
    $metadata.counts.group_membership_entries = $totalGroupMemberEntries
    Save-Json -Path $groupMembershipsFile -Data $groupMemberships
    Write-Log "Group memberships exported: groups=$($groupMemberships.Count) entries=$totalGroupMemberEntries -> $groupMembershipsFile"
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Group memberships complete" -PercentComplete 70
    # Write metadata checkpoint after group memberships phase
    Save-Json -Path $metadataFile -Data $metadata
}

# ---------------------------
# 5) Export Project Memberships (users + group shares)
# ---------------------------
if ($Profile -ne 'Complete') {
    Write-Log "[PROFILE] Skipping project memberships export - '$Profile' profile omits memberships"
    $projectMemberships = @()
    $metadata.counts.project_memberships = 0
    $metadata.counts.project_membership_entries = 0
}
elseif ($Resume.IsPresent -and $resumeFlags.project_memberships) {
    Write-Log "[RESUME] Skipping project memberships export - $projectMembershipsFile already exists"
    $projectMemberships = Get-Content -LiteralPath $projectMembershipsFile -Raw | ConvertFrom-Json
    $projectMemberships = if ($null -eq $projectMemberships) { @() } elseif ($projectMemberships -is [array]) { $projectMemberships } else { @($projectMemberships) }
    $metadata.counts.project_memberships = $projectMemberships.Count
    $totalProjectMemberEntries = 0
    foreach ($pm in $projectMemberships) {
        $membersArr = if ($null -eq $pm.members) { @() } elseif ($pm.members -is [array]) { $pm.members } else { @($pm.members) }
        $totalProjectMemberEntries += ($membersArr | Measure-Object).Count
    }
    $metadata.counts.project_membership_entries = $totalProjectMemberEntries
}
else {
    Write-Log 'Exporting project memberships...'
    Write-Progress -Activity "Exporting GitLab Identity" -Status "Exporting project memberships..." -PercentComplete 75
    $projectMemberships = @()
    $projIdx = 0
    foreach ($p in $projects) {
        $projIdx++
        if ($projIdx % 20 -eq 0) {
            $pct = [Math]::Min(90, 75 + (($projIdx / $projects.Count) * 15))
            Write-Progress -Activity "Exporting GitLab Identity" -Status "Processing project memberships ($projIdx/$($projects.Count))..." -PercentComplete $pct
        }
        $projectId = $p.id
        $ppath = $p.path_with_namespace

        try {
            # Users: all vs direct
            $projectMembersAllEndpoint = "/projects/{0}/members/all" -f $projectId
            $projectMembersDirectEndpoint = "/projects/{0}/members" -f $projectId
            try {
                $pmAllResp = Invoke-GitLabPagedRequest -Endpoint $projectMembersAllEndpoint
            }
            catch {
                $pmAllResp = [pscustomobject]@{ Items = $null; Denied = $true }
            }
            try {
                $pmDirectResp = Invoke-GitLabPagedRequest -Endpoint $projectMembersDirectEndpoint
            }
            catch {
                $pmDirectResp = [pscustomobject]@{ Items = $null; Denied = $true }
            }

            $allDenied = $pmAllResp.Denied
            $dirDenied = $pmDirectResp.Denied

            $pmAll = @(); $pmDirect = @()
            if (-not $allDenied) { 
                $pmAll = $pmAllResp.Items
                if ($null -eq $pmAll) { $pmAll = @() } elseif ($pmAll -isnot [array]) { $pmAll = @($pmAll) }
            }
            if (-not $dirDenied) { 
                $pmDirect = $pmDirectResp.Items
                if ($null -eq $pmDirect) { $pmDirect = @() } elseif ($pmDirect -isnot [array]) { $pmDirect = @($pmDirect) }
            }

            if ($allDenied -and -not $dirDenied) {
                foreach ($m in $pmDirect) { $m | Add-Member -NotePropertyName inherited -NotePropertyValue $false -Force }
                $usersMembers = $pmDirect
            }
            elseif (-not $allDenied -and -not $dirDenied) {
                $usersMembers = Add-InheritedFlag -AllMembers $pmAll -DirectMembers $pmDirect
            }
            else {
                $usersMembers = @()
            }

            # Group shares on project: already fetched in initial /projects call with ?with_shared=true
            # This eliminates N+1 query pattern (was fetching /projects/:id for EVERY project)
            $groupShares = @()
            $sharedWithGroups = $p.shared_with_groups
            if ($sharedWithGroups) {
                if ($sharedWithGroups -isnot [array]) { $sharedWithGroups = @($sharedWithGroups) }
                foreach ($gshare in $sharedWithGroups) {
                    $groupShares += [pscustomobject]@{
                        type               = 'group'
                        id                 = $gshare.group_id
                        full_path          = $gshare.group_full_path
                        access_level       = $gshare.group_access_level
                        expires_at         = $gshare.expires_at
                        inherited          = $false
                    }
                }
            }

            # Normalize user member objects
            $userMembersNormalized = foreach ($m in $usersMembers) {
                [pscustomobject]@{
                    type              = 'user'
                    id                = $m.id
                    username          = $m.username
                    name              = $m.name
                    state             = $m.state
                    access_level      = $m.access_level
                    access_level_name = (Get-AccessLevelName $m.access_level)
                    expires_at        = $m.expires_at
                    inherited         = if ($m.PSObject.Properties.Name -contains 'inherited') { $m.inherited } else { $false }
                }
            }

            $projectMemberships += [pscustomobject]@{
                project_id            = $projectId
                path_with_namespace   = $ppath
                members               = @($userMembersNormalized + $groupShares)
            }
        }
        catch {
            $errorMessage = $_.ToString()
            Write-Warning "Failed to fetch memberships for project '$($p.path_with_namespace)': $errorMessage"
        }
    }
    $metadata.counts.project_memberships = $projectMemberships.Count
    $totalProjectMemberEntries = 0
    foreach ($pm in $projectMemberships) { $totalProjectMemberEntries += ($pm.members | Measure-Object).Count }
    $metadata.counts.project_membership_entries = $totalProjectMemberEntries
    Save-Json -Path $projectMembershipsFile -Data $projectMemberships
    Write-Log "Project memberships exported: projects=$($projectMemberships.Count) entries=$totalProjectMemberEntries -> $projectMembershipsFile"
    # Write metadata checkpoint after project memberships phase
    Save-Json -Path $metadataFile -Data $metadata
}

# ---------------------------
# 6) Export Custom Member Roles (optional)
# ---------------------------
if ($IncludeMemberRoles.IsPresent) {
    if ($Resume.IsPresent -and $resumeFlags.member_roles) {
        Write-Log "[RESUME] Skipping member roles export - $memberRolesFile already exists"
        $roles = Get-Content -LiteralPath $memberRolesFile -Raw | ConvertFrom-Json
        $roles = if ($null -eq $roles) { @() } elseif ($roles -is [array]) { $roles } else { @($roles) }
        $metadata.counts.member_roles = $roles.Count
    }
    else {
        Write-Log 'Exporting custom member roles (GET /api/v4/member_roles)...'
        try {
            $rolesResp = Invoke-GitLabPagedRequest -Endpoint '/member_roles'
        }
        catch {
            $rolesResp = [pscustomobject]@{ Items = $null; Denied = $true }
        }
        if ($rolesResp.Denied) {
            Write-Log 'Access denied to /member_roles. Skipping member roles export.' 'WARN'
            $roles = @()
        }
        else {
            $roles = $rolesResp.Items
            $roles = if ($null -eq $roles) { @() } elseif ($roles -is [array]) { $roles } else { @($roles) }
        }
        $metadata.counts.member_roles = $roles.Count
        Save-Json -Path $memberRolesFile -Data $roles
        Write-Log "Member roles exported: $($roles.Count) -> $memberRolesFile"
    }
}
else {
    Write-Log 'Skipping custom member roles (not requested).'
}

# ---------------------------
# 7) Write metadata.json and finalize
# ---------------------------
Write-Progress -Activity "Exporting GitLab Identity" -Status "Finalizing export..." -PercentComplete 95
$metadata.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
$summaryNote = "Exported users=$($metadata.counts.users), groups=$($metadata.counts.groups), projects=$($metadata.counts.projects), group_memberships=$($metadata.counts.group_memberships), project_memberships=$($metadata.counts.project_memberships)."
$summaryNote2 = "Membership entry totals: group_entries=$($metadata.counts.group_membership_entries), project_entries=$($metadata.counts.project_membership_entries)."
$metadata.notes += $summaryNote
$metadata.notes += $summaryNote2
Save-Json -Path $metadataFile -Data $metadata
Write-Log "Metadata saved -> $metadataFile"

Write-Progress -Activity "Exporting GitLab Identity" -Status "Complete" -PercentComplete 100 -Completed

# ---------------------------
# 8) Display Statistics (if requested)
# ---------------------------
if ($ShowStatistics.IsPresent) {
    Write-Host "`n========== EXPORT STATISTICS ==========" -ForegroundColor Cyan
    Write-Host "`nResource Counts:" -ForegroundColor Green
    Write-Host "  Users:                 $($metadata.counts.users)" -ForegroundColor White
    Write-Host "  Groups:                $($metadata.counts.groups)" -ForegroundColor White
    Write-Host "  Projects:              $($metadata.counts.projects)" -ForegroundColor White
    Write-Host "  Group Memberships:     $($metadata.counts.group_memberships)" -ForegroundColor White
    Write-Host "  Project Memberships:   $($metadata.counts.project_memberships)" -ForegroundColor White
    
    # Top 10 groups by member count
        $groupMembershipsArr = if ($null -eq $groupMemberships) { @() } elseif ($groupMemberships -is [array]) { $groupMemberships } else { @($groupMemberships) }
        $projectMembershipsArr = if ($null -eq $projectMemberships) { @() } elseif ($projectMemberships -is [array]) { $projectMemberships } else { @($projectMemberships) }
        # Top 10 groups by member count
        if ($groupMembershipsArr.Count -gt 0) {
            $topGroups = $groupMembershipsArr | Sort-Object { ($_.members | Measure-Object).Count } -Descending | Select-Object -First 10
            Write-Host "`nTop 10 Groups by Member Count:" -ForegroundColor Green
            foreach ($g in $topGroups) {
                $membersArr = if ($null -eq $g.members) { @() } elseif ($g.members -is [array]) { $g.members } else { @($g.members) }
                $memberCount = ($membersArr | Measure-Object).Count
                Write-Host "  $($g.group_full_path): $memberCount members" -ForegroundColor White
            }
        }
        # Access level distribution across all memberships
        $allMembers = @()
        foreach ($gm in $groupMembershipsArr) { $membersArr = if ($null -eq $gm.members) { @() } elseif ($gm.members -is [array]) { $gm.members } else { @($gm.members) }; $allMembers += $membersArr | Where-Object { $_.type -eq 'user' } }
        foreach ($pm in $projectMembershipsArr) { $membersArr = if ($null -eq $pm.members) { @() } elseif ($pm.members -is [array]) { $pm.members } else { @($pm.members) }; $allMembers += $membersArr | Where-Object { $_.type -eq 'user' } }
        if ($allMembers.Count -gt 0) {
            $levelCounts = $allMembers | Group-Object access_level_name | Sort-Object Count -Descending
            Write-Host "`nAccess Level Distribution (All Memberships):" -ForegroundColor Green
            foreach ($lc in $levelCounts) {
                $pct = [Math]::Round(($lc.Count / $allMembers.Count) * 100, 1)
                Write-Host "  $($lc.Name): $($lc.Count) ($pct%)" -ForegroundColor White
            }
        }
        # Largest projects (by member count from project memberships)
        if ($projectMembershipsArr.Count -gt 0) {
            $topProjects = $projectMembershipsArr | Sort-Object { ($_.members | Measure-Object).Count } -Descending | Select-Object -First 10
            Write-Host "`nTop 10 Projects by Member Count:" -ForegroundColor Green
            foreach ($p in $topProjects) {
                $membersArr = if ($null -eq $p.members) { @() } elseif ($p.members -is [array]) { $p.members } else { @($p.members) }
                $memberCount = ($membersArr | Measure-Object).Count
                Write-Host "  $($p.path_with_namespace): $memberCount members" -ForegroundColor White
            }
        }
        Write-Host "`n=======================================" -ForegroundColor Cyan
}

Write-Log 'Export completed successfully.'

} # End try block
finally {
    # Clean up sensitive token from memory
    if ($PlainToken) {
        $PlainToken = $null
        $script:PlainToken = $null
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

<#!
HOW THIS EXPORT IS CONSUMED LATER (Offline ADO Import Script):

- users.json
  Contains GitLab users keyed by id and username. An ADO import script should map these identities to
  Azure DevOps identities (e.g., via email/UPN directory lookups) and then create/add as needed.

- groups.json
  Contains GitLab groups with full_path and proposed_ado_name (full_path with '/' replaced by '-').
  An ADO import script can create flattened groups using proposed_ado_name (Graph Groups Create API or
  alternative Core Teams mechanisms on on-prem servers).

- projects.json
  Contains projects with path_with_namespace and proposed_ado_repo_name (the GitLab project path).
  An ADO import script can use this to create repositories or map to existing ones.

- group-memberships.json / project-memberships.json
  Each entry includes a members array with elements of type 'user' or 'group'.
  For 'user' members, the ADO script should map {id, username} to ADO identities, then add memberships
  with appropriate access levels. The 'inherited' flag tells whether the user was inherited from
  ancestor groups in GitLab (helpful context for troubleshooting differences in permission models).
  For 'group' members, these represent linked/shared groups at group/project level with access levels.

- member-roles.json (optional)
  If present, contains custom member role definitions from GitLab. An ADO import script can decide how to
  approximate these in Azure DevOps (e.g., map to closest built-in role or use custom policies where available).

NOTE: This export never writes tokens to disk. All JSON files are UTF-8 and suitable for offline use.
#>
