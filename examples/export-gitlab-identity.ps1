<#!
.SYNOPSIS
  Export GitLab identities and effective permissions for offline reconstruction in Azure DevOps Server.

.DESCRIPTION
  This script runs ONCE while GitLab is reachable and exports identity/authorization data to a timestamped
  folder (UTF-8 JSON files). The output is designed to be consumed later by a separate, offline script that
  creates users, groups and memberships in Azure DevOps Server. No Azure DevOps calls are performed here.

  GitLab API references (authoritative for data export):
   - Users:            https://docs.gitlab.com/api/users/
   - Groups:           https://docs.gitlab.com/api/groups/
   - Group members:    https://docs.gitlab.com/api/members/#list-all-members-of-a-group-or-project
                        (using /groups/:id/members and /groups/:id/members/all)
   - Projects:         https://docs.gitlab.com/api/projects/
   - Project members:  https://docs.gitlab.com/api/members/#list-all-members-of-a-group-or-project
                        (using /projects/:id/members and /projects/:id/members/all)
   - Custom roles:     https://docs.gitlab.com/api/member_roles/

  ADO target shape (reference only, NOT called here):
   - Azure DevOps Graph (groups/memberships) to be used later by an import script.
     Docs: https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/groups/list?view=azure-devops-rest-7.1
           https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/groups/create?view=azure-devops-rest-7.1
           https://learn.microsoft.com/en-us/rest/api/azure/devops/graph/memberships/add?view=azure-devops-rest-7.1

  IMPORTANT NOTE (Azure DevOps on-prem):
   Some on-prem Azure DevOps Servers have limited/absent Graph API capabilities. This export focuses on
   identities/permissions and shapes extra fields like proposed_ado_name and proposed_ado_repo_name so a
   downstream importer can choose either Graph APIs (where available) or alternative Core Teams APIs.

.OUTPUT
  export-gitlab-identity-YYYYMMDD-HHmmss/ (example)
   - users.json                 (array)
   - groups.json                (array, includes proposed_ado_name)
   - projects.json              (array, includes proposed_ado_repo_name)
   - group-memberships.json     (array of { group_id, group_full_path, members: [...] })
   - project-memberships.json   (array of { project_id, path_with_namespace, members: [...] })
   - member-roles.json          (array; written only when -IncludeMemberRoles)
   - metadata.json              (object; script version, counts, fallbacks, paging info, etc.)
   - export.log                 (text; timestamps and summary)

.PARAMETER GitLabBaseUrl
  Base URL of GitLab (e.g. https://gitlab.example.com). Do NOT include trailing slash.

.PARAMETER GitLabToken
  GitLab Personal Access Token (string). Use either -GitLabToken or -GitLabTokenSecure.

.PARAMETER GitLabTokenSecure
  GitLab Personal Access Token as SecureString. Use either -GitLabToken or -GitLabTokenSecure.

.PARAMETER OutDirectory
  Output folder. Defaults to .\\export-gitlab-identity-<timestamp> under current directory.

.PARAMETER PageSize
  Page size for paged endpoints (default 100).

.PARAMETER ApiVersion
  GitLab API version to use (default 'v4'). Future-proofing for v5.

.PARAMETER ApiVersion
  GitLab API version to use. Defaults to 'v4'. Future-proofing for v5.

.PARAMETER Profile
  Export profile preset: 'Minimal' (users/groups only), 'Standard' (adds projects), 'Complete' (adds memberships/roles). 
  Defaults to 'Complete'. Use Minimal for faster exports when only identity data is needed.

.PARAMETER Since
  Export only resources modified since this date (ISO format: 2024-01-01 or full ISO-8601).
  Useful for incremental/differential exports to keep ADO in sync with GitLab.

.PARAMETER IncludeMemberRoles
  When specified, export custom member roles using /api/v4/member_roles.

.PARAMETER Resume
  When specified, checks for existing export files and skips phases that have already completed.
  Useful for recovering from script failures without re-exporting everything.

.PARAMETER DryRun
  When specified, queries only resource counts without exporting data. Shows estimated API calls,
  time, and rate limit consumption. Useful for previewing export scope before execution.

.PARAMETER ShowStatistics
  When specified, displays export statistics summary at the end including top groups by member count,
  largest projects, and permission distribution.

.NOTES
  - Pure PowerShell (Invoke-WebRequest / Invoke-RestMethod) to stay compatible with Windows PowerShell 5.1.
  - All JSON files are UTF-8 (no BOM), indented. No access tokens are written to disk.
  - For /members/all access issues (401/403/404), falls back to /members and records the fallback in metadata.
  - Inherited membership flag is computed by comparing /members/all vs direct /members.
  - This script does NOT export CI pipelines, issues, or merge requests.
#>

[CmdletBinding(DefaultParameterSetName='PlainToken')]
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

Import-Module "C:\Projects\devops\Gitlab2DevOps\modules\core\Core.Rest.psm1" -Force -ErrorAction Stop
Import-Module "C:\Projects\devops\Gitlab2DevOps\modules\GitLab\GitLab.psm1" -Force -ErrorAction Stop

# ---------------------------
# Helper Functions (available even when script is dot-sourced)
# ---------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    if ($script:logFile) {
        Add-Content -LiteralPath $script:logFile -Value $line
    }
}

function Save-Json {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Data
    )
    $json = $Data | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Invoke-GitLabPagedRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [hashtable]$Query = @{}
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $more = $true
    $startTime = Get-Date

    $meta = [ordered]@{
        endpoint             = $Endpoint
        page_size            = $script:PageSize
        total                = $null
        total_pages          = $null
        collected_pages      = 0
        total_time_ms        = 0
        avg_time_per_page_ms = 0
        retry_count          = 0
        rate_limit_remaining = $null
        rate_limit_reset     = $null
        link_header          = $null
    }

    while ($more) {
        $pageStartTime = Get-Date
        $queryWithPage = @{
            per_page = $script:PageSize
            page     = $page
        }
        foreach ($k in $Query.Keys) { $queryWithPage[$k] = $Query[$k] }

        $resp = Invoke-GitLabRest -Method GET -Endpoint $Endpoint -Query $queryWithPage
        if ($resp.Status -in 401,403) {
            return [pscustomobject]@{ Items = $null; Meta = $meta; Denied = $true; Last = $resp }
        }

        $data = $resp.Data
        if ($null -eq $data) { break }
        if ($data -is [array]) { $items.AddRange($data) } else { $items.Add($data) }

        $h = $resp.Headers
        $nextPage = $h['X-Next-Page']
        $total = $h['X-Total']
        $totalPages = $h['X-Total-Pages']
        $rateLimitRemaining = $h['RateLimit-Remaining']
        $rateLimitReset = $h['RateLimit-Reset']
        $linkHeader = $h['Link']

        $nextPage = $nextPage -is [array] ? $nextPage[0] : $nextPage
        $total = $total -is [array] ? $total[0] : $total
        $totalPages = $totalPages -is [array] ? $totalPages[0] : $totalPages
        $rateLimitRemaining = $rateLimitRemaining -is [array] ? $rateLimitRemaining[0] : $rateLimitRemaining
        $rateLimitReset = $rateLimitReset -is [array] ? $rateLimitReset[0] : $rateLimitReset
        $linkHeader = $linkHeader -is [array] ? $linkHeader[0] : $linkHeader

        if ($total) { $meta.total = [int]$total }
        if ($totalPages) { $meta.total_pages = [int]$totalPages }
        if ($rateLimitRemaining) { $meta.rate_limit_remaining = [int]$rateLimitRemaining }
        if ($rateLimitReset) { $meta.rate_limit_reset = $rateLimitReset }
        if ($linkHeader -and -not $meta.link_header) { $meta.link_header = $linkHeader }

        $meta.collected_pages++

        $pageTime = ((Get-Date) - $pageStartTime).TotalMilliseconds
        Write-Verbose "Page $page fetched in $([Math]::Round($pageTime, 2))ms (rate limit remaining: $rateLimitRemaining)"

        if ([string]::IsNullOrWhiteSpace($nextPage)) {
            $more = $false
        }
        else {
            $page = [int]$nextPage
        }
    }

    $meta.total_time_ms = [int]((Get-Date) - $startTime).TotalMilliseconds
    if ($meta.collected_pages -gt 0) {
        $meta.avg_time_per_page_ms = [int]($meta.total_time_ms / $meta.collected_pages)
    }

    return [pscustomobject]@{ Items = $items.ToArray(); Meta = $meta; Denied = $false; Last = $resp }
}

function Add-InheritedFlag {
    param(
        [Parameter(Mandatory=$true)][array]$AllMembers,
        [Parameter(Mandatory=$true)][array]$DirectMembers
    )
    $directIds = @{}
    foreach ($m in $DirectMembers) { $directIds[[string]$m.id] = $true }
    foreach ($m in $AllMembers) {
        $isDirect = $false
        if ($m.PSObject.Properties.Name -contains 'id') {
            $isDirect = $directIds.ContainsKey([string]$m.id)
        }
        $m | Add-Member -NotePropertyName inherited -NotePropertyValue ($isDirect -eq $false) -Force
    }
    return $AllMembers
}

function Get-AccessLevelName {
    param([int]$AccessLevel)
    switch ($AccessLevel) {
        10 { return 'Guest' }
        20 { return 'Reporter' }
        30 { return 'Developer' }
        40 { return 'Maintainer' }
        50 { return 'Owner' }
        default { return "Unknown ($AccessLevel)" }
    }
}


$script:logFile = $null
$script:IsLibraryImport = ($MyInvocation.InvocationName -eq '.')
if ($script:IsLibraryImport) {
    return
}


$config = $script:coreRestConfig
if (-not $config) {
    $config = Ensure-CoreRestInitialized
}

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
    Write-Log "Failed to get /user for token identity: $($_.Exception.Message)" 'WARN'
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
            $total = $total -is [array] ? $total[0] : $total
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
    # Ensure array shape (ConvertFrom-Json returns single object when JSON has one item)
    if ($null -eq $users) { $users = @() } else { $users = @($users) }
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
        if ($null -eq $usersRaw) { $usersRaw = @() }
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
    if ($null -eq $groups) { $groups = @() } else { $groups = @($groups) }
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
        if ($null -eq $groupsRaw) { $groupsRaw = @() }
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
    if ($null -eq $projects) { $projects = @() } else { $projects = @($projects) }
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
        if ($null -eq $projectsRaw) { $projectsRaw = @() }
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
    if ($null -eq $groupMemberships) { $groupMemberships = @() } else { $groupMemberships = @($groupMemberships) }
    $metadata.counts.group_memberships = $groupMemberships.Count
    $totalGroupMemberEntries = 0
    foreach ($gm in $groupMemberships) { $totalGroupMemberEntries += ($gm.members | Measure-Object).Count }
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

        # Users: all vs direct
        $gmAllResp = Invoke-GitLabPagedRequest -Endpoint "/groups/$gid/members/all"
        $gmDirectResp = Invoke-GitLabPagedRequest -Endpoint "/groups/$gid/members"

        $allDenied = $gmAllResp.Denied
        $dirDenied = $gmDirectResp.Denied

        $gmAll = @(); $gmDirect = @()
        if (-not $allDenied) { $gmAll = $gmAllResp.Items } else { $metadata.fallbacks.groups_members_all_denied += $gid }
        if (-not $dirDenied) { $gmDirect = $gmDirectResp.Items }

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

        # Group links (groups shared to this group)
        $sharedGroupsResp = Invoke-GitLabPagedRequest -Endpoint "/groups/$gid/shared_groups"
        $groupLinks = @()
        if (-not $sharedGroupsResp.Denied) {
            foreach ($sg in $sharedGroupsResp.Items) {
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
                inherited         = $m.inherited
            }
        }

        $groupMemberships += [pscustomobject]@{
            group_id        = $gid
            group_full_path = $gpath
            members         = @($userMembersNormalized + $groupLinks)
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
    if ($null -eq $projectMemberships) { $projectMemberships = @() } else { $projectMemberships = @($projectMemberships) }
    $metadata.counts.project_memberships = $projectMemberships.Count
    $totalProjectMemberEntries = 0
    foreach ($pm in $projectMemberships) { $totalProjectMemberEntries += ($pm.members | Measure-Object).Count }
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

        # Users: all vs direct
        $projectMembersAllEndpoint = "/projects/{0}/members/all" -f $pid
        $projectMembersDirectEndpoint = "/projects/{0}/members" -f $pid
        $pmAllResp = Invoke-GitLabPagedRequest -Endpoint $projectMembersAllEndpoint
        $pmDirectResp = Invoke-GitLabPagedRequest -Endpoint $projectMembersDirectEndpoint

        $allDenied = $pmAllResp.Denied
        $dirDenied = $pmDirectResp.Denied

        $pmAll = @(); $pmDirect = @()
        if (-not $allDenied) { $pmAll = $pmAllResp.Items } else { $metadata.fallbacks.projects_members_all_denied += $pid }
        if (-not $dirDenied) { $pmDirect = $pmDirectResp.Items }

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
        if ($p.shared_with_groups) {
            foreach ($gshare in $p.shared_with_groups) {
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
                inherited         = $m.inherited
            }
        }

        $projectMemberships += [pscustomobject]@{
            project_id            = $pid
            path_with_namespace   = $ppath
            members               = @($userMembersNormalized + $groupShares)
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
        if ($null -eq $roles) { $roles = @() } else { $roles = @($roles) }
        $metadata.counts.member_roles = $roles.Count
    }
    else {
        Write-Log 'Exporting custom member roles (GET /api/v4/member_roles)...'
        $rolesResp = Invoke-GitLabPagedRequest -Endpoint '/member_roles'
        if ($rolesResp.Denied) {
            Write-Log 'Access denied to /member_roles. Skipping member roles export.' 'WARN'
            $roles = @()
        }
        else {
            $roles = $rolesResp.Items
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
    if ($groupMemberships.Count -gt 0) {
        $topGroups = $groupMemberships | Sort-Object { ($_.members | Measure-Object).Count } -Descending | Select-Object -First 10
        Write-Host "`nTop 10 Groups by Member Count:" -ForegroundColor Green
        foreach ($g in $topGroups) {
            $memberCount = ($g.members | Measure-Object).Count
            Write-Host "  $($g.group_full_path): $memberCount members" -ForegroundColor White
        }
    }
    
    # Access level distribution across all memberships
    $allMembers = @()
    foreach ($gm in $groupMemberships) { $allMembers += $gm.members | Where-Object { $_.type -eq 'user' } }
    foreach ($pm in $projectMemberships) { $allMembers += $pm.members | Where-Object { $_.type -eq 'user' } }
    
    if ($allMembers.Count -gt 0) {
        $levelCounts = $allMembers | Group-Object access_level_name | Sort-Object Count -Descending
        Write-Host "`nAccess Level Distribution (All Memberships):" -ForegroundColor Green
        foreach ($lc in $levelCounts) {
            $pct = [Math]::Round(($lc.Count / $allMembers.Count) * 100, 1)
            Write-Host "  $($lc.Name): $($lc.Count) ($pct%)" -ForegroundColor White
        }
    }
    
    # Largest projects (by member count from project memberships)
    if ($projectMemberships.Count -gt 0) {
        $topProjects = $projectMemberships | Sort-Object { ($_.members | Measure-Object).Count } -Descending | Select-Object -First 10
        Write-Host "`nTop 10 Projects by Member Count:" -ForegroundColor Green
        foreach ($p in $topProjects) {
            $memberCount = ($p.members | Measure-Object).Count
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
