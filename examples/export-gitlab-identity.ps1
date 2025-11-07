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

.PARAMETER IncludeMemberRoles
  When specified, export custom member roles using /api/v4/member_roles.

.NOTES
  - Pure PowerShell (Invoke-WebRequest / Invoke-RestMethod) to stay compatible with Windows PowerShell 5.1.
  - All JSON files are UTF-8 (no BOM), indented. No access tokens are written to disk.
  - For /members/all access issues (401/403/404), falls back to /members and records the fallback in metadata.
  - Inherited membership flag is computed by comparing /members/all vs direct /members.
  - This script does NOT export CI pipelines, issues, or merge requests.
#>

[CmdletBinding(DefaultParameterSetName='PlainToken')]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$GitLabBaseUrl,

    [Parameter(Mandatory=$true, ParameterSetName='PlainToken')]
    [ValidateNotNullOrEmpty()]
    [string]$GitLabToken,

    [Parameter(Mandatory=$true, ParameterSetName='SecureToken')]
    [System.Security.SecureString]$GitLabTokenSecure,

    [Parameter(Mandatory=$false)]
    [string]$OutDirectory,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1,1000)]
    [int]$PageSize = 100,

    [switch]$IncludeMemberRoles
)

# ---------------------------
# Constants & Globals
# ---------------------------
$Script:ScriptVersion = '1.0.0'
$Script:StartedAtUtc = (Get-Date).ToUniversalTime()
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Invoke-WebRequest:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['Invoke-RestMethod:ErrorAction'] = 'Stop'

# Normalize base URL (no trailing slash)
if ($GitLabBaseUrl.EndsWith('/')) {
    $GitLabBaseUrl = $GitLabBaseUrl.TrimEnd('/')
}

# Materialize token value from secure/plain
$PlainToken = $null
if ($PSCmdlet.ParameterSetName -eq 'SecureToken') {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($GitLabTokenSecure)
    try {
        $PlainToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}
else {
    $PlainToken = $GitLabToken
}

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

# ---------------------------
# Logging helpers
# ---------------------------
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line
}

# ---------------------------
# JSON save helper (UTF-8 no BOM)
# ---------------------------
function Save-Json {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Data
    )
    $json = $Data | ConvertTo-Json -Depth 20
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

# ---------------------------
# HTTP Helper: Invoke GitLab REST and return parsed JSON + headers
# Uses Invoke-WebRequest to access pagination headers (X-Next-Page, X-Total, ...)
# ---------------------------
function Invoke-GitLabRest {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method,
        [Parameter(Mandatory=$true)][string]$Endpoint,  # e.g. '/users'
        [hashtable]$Query = @{},
        [int]$MaxRetries = 3
    )

    $uriBuilder = New-Object System.UriBuilder("$GitLabBaseUrl/api/v4$Endpoint")
    if ($Query -and $Query.Count -gt 0) {
        # Build query string safely
        $nv = New-Object System.Collections.Specialized.NameValueCollection
        foreach ($k in $Query.Keys) {
            $v = if ($Query[$k] -ne $null) { [string]$Query[$k] } else { '' }
            $nv.Add([string]$k, $v)
        }
        $qs = [System.Web.HttpUtility]::ParseQueryString('')
        $qs.Add($nv)
        $uriBuilder.Query = $qs.ToString()
    }
    $uri = $uriBuilder.Uri.AbsoluteUri

    $headers = @{
        'Private-Token' = $PlainToken  # GitLab recommended PAT header
        'Accept'        = 'application/json'
    }

    $attempt = 0
    $delay = 1
    while ($true) {
        try {
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -UseBasicParsing
            $contentType = ($resp.Headers['Content-Type'])
            $raw = $resp.Content
            $data = if ($raw) { $raw | ConvertFrom-Json } else { $null }
            return [pscustomobject]@{
                Data    = $data
                Headers = $resp.Headers
                Status  = $resp.StatusCode
                Uri     = $uri
            }
        }
        catch {
            $attempt++
            # Parse web exception
            $webEx = $_.Exception
            $statusCode = $null
            $errorBody = $null
            
            if ($webEx.Response -and $webEx.Response.StatusCode) {
                $statusCode = [int]$webEx.Response.StatusCode
                # Try to read response body for detailed error message
                try {
                    $stream = $webEx.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                } catch {
                    $errorBody = $_.ErrorDetails.Message
                }
            }
            
            # Fallback to ErrorDetails if no response body
            if (-not $errorBody) {
                $errorBody = $_.ErrorDetails.Message ?? $_.Exception.Message
            }

            if ($statusCode -eq 429 -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try { $retryAfter = [int]$webEx.Response.Headers['Retry-After'] } catch {}
                if ($retryAfter -lt 1) { $retryAfter = $delay }
                Write-Log "429 Too Many Requests on $uri. Retrying in $retryAfter sec... (attempt $attempt/$MaxRetries)" 'WARN'
                Start-Sleep -Seconds $retryAfter
                $delay = [Math]::Min($delay * 2, 30)
                continue
            }

            # For 401/403, write clear error and allow caller to decide (we'll record in metadata)
            if ($statusCode -in 401,403) {
                $logMsg = "Access denied ($statusCode) calling $uri"
                if ($errorBody) { $logMsg += " - $errorBody" }
                Write-Log $logMsg 'ERROR'
                return [pscustomobject]@{ Data = $null; Headers = $null; Status = $statusCode; Uri = $uri }
            }

            # Other errors bubble up with enhanced message
            if ($errorBody) {
                throw "HTTP $statusCode on $uri`: $errorBody"
            }
            throw
        }
    }
}

# ---------------------------
# Paged request helper aggregates items using X-Next-Page headers
# Uses List<T> instead of array concatenation to avoid O(n²) memory allocation
# Captures rate limit headers and timing for diagnostics
# ---------------------------
function Invoke-GitLabPagedRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Endpoint,
        [hashtable]$Query = @{}
    )
    # Use List<T> for O(1) amortized append instead of O(n) array copy with +=
    $items = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $more = $true
    $startTime = Get-Date

    $meta = [ordered]@{
        endpoint            = $Endpoint
        page_size           = $PageSize
        total               = $null
        total_pages         = $null
        collected_pages     = 0
        total_time_ms       = 0
        avg_time_per_page_ms = 0
        retry_count         = 0
        rate_limit_remaining = $null
        rate_limit_reset     = $null
        link_header          = $null
    }

    while ($more) {
        $pageStartTime = Get-Date
        $queryWithPage = @{
            per_page = $PageSize
            page     = $page
        }
        foreach ($k in $Query.Keys) { $queryWithPage[$k] = $Query[$k] }

        $resp = Invoke-GitLabRest -Method GET -Endpoint $Endpoint -Query $queryWithPage
        if ($resp.Status -in 401,403) {
            # Caller will interpret this as a denied endpoint
            return [pscustomobject]@{ Items = $null; Meta = $meta; Denied = $true; Last = $resp }
        }

        $data = $resp.Data
        if ($data -eq $null) { break }
        # AddRange for arrays, Add for single items - O(1) amortized
        if ($data -is [array]) { $items.AddRange($data) } else { $items.Add($data) }

        # Headers
        $h = $resp.Headers
        $nextPage = $h['X-Next-Page']
        $total = $h['X-Total']
        $totalPages = $h['X-Total-Pages']
        $rateLimitRemaining = $h['RateLimit-Remaining']
        $rateLimitReset = $h['RateLimit-Reset']
        $linkHeader = $h['Link']
        
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
    
    # Convert List<T> to array for compatibility with rest of script
    return [pscustomobject]@{ Items = $items.ToArray(); Meta = $meta; Denied = $false; Last = $resp }
}

# ---------------------------
# Initialize metadata
# ---------------------------
$metadata = [ordered]@{
    script_version         = $Script:ScriptVersion
    started_utc            = $Script:StartedAtUtc.ToString('o')
    completed_utc          = $null
    gitlab_base_url        = $GitLabBaseUrl
    token_user             = $null
    page_size              = $PageSize
    counts                 = [ordered]@{ users = 0; groups = 0; projects = 0; group_memberships = 0; project_memberships = 0; member_roles = 0 }
    skipped                = [ordered]@{ users = @(); groups = @(); projects = @() }
    fallbacks              = [ordered]@{ groups_members_all_denied = @(); projects_members_all_denied = @() }
    notes                  = @()
}

Write-Log "Export started. Output directory: $OutDirectory"

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
# 1) Export Users (GET /users - paged)
# ---------------------------
Write-Log 'Fetching users (GET /api/v4/users)...'
$usersResp = Invoke-GitLabPagedRequest -Endpoint '/users'
if ($usersResp.Denied) {
    Write-Log 'Access denied to /users. Continuing without users.' 'ERROR'
    $users = @()
}
else {
    $usersRaw = $usersResp.Items
    $users = foreach ($u in $usersRaw) {
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
# Write metadata checkpoint after users phase
Save-Json -Path $metadataFile -Data $metadata

# ---------------------------
# 2) Export Groups (GET /groups - paged)
# ---------------------------
Write-Log 'Fetching groups (GET /api/v4/groups)...'
$groupsResp = Invoke-GitLabPagedRequest -Endpoint '/groups' -Query @{ all_available = 'true' }
if ($groupsResp.Denied) {
    Write-Log 'Access denied to /groups. Continuing without groups.' 'ERROR'
    $groups = @()
}
else {
    $groupsRaw = $groupsResp.Items
    # Build parent lookup for hierarchy computation
    $groupLookup = @{}
    foreach ($g in $groupsRaw) { $groupLookup[[string]$g.id] = $g }
    
    $groups = foreach ($g in $groupsRaw) {
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
# Write metadata checkpoint after groups phase
Save-Json -Path $metadataFile -Data $metadata

# ---------------------------
# 3) Export Projects (GET /projects - paged)
# ---------------------------
Write-Log 'Fetching projects (GET /api/v4/projects)...'
# membership=true limits to projects the token can access; with_shared=false avoids N+1 later
# NOTE: We do NOT use simple=true because we need shared_with_groups data to avoid N+1 query pattern
$projectsResp = Invoke-GitLabPagedRequest -Endpoint '/projects' -Query @{ membership='true'; archived='false'; with_shared='true' }
if ($projectsResp.Denied) {
    Write-Log 'Access denied to /projects. Continuing without projects.' 'ERROR'
    $projects = @()
}
else {
    $projectsRaw = $projectsResp.Items
    $projects = foreach ($p in $projectsRaw) {
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
# Write metadata checkpoint after projects phase
Save-Json -Path $metadataFile -Data $metadata

# ---------------------------
# Helper: compute member inherited flag (all vs direct)
# ---------------------------
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

# ---------------------------
# Helper: Convert GitLab access level integer to name
# GitLab: 10=Guest, 20=Reporter, 30=Developer, 40=Maintainer, 50=Owner
# ---------------------------
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

# ---------------------------
# 4) Export Group Memberships (users + group links)
# ---------------------------
Write-Log 'Exporting group memberships...'
$groupMemberships = @()
foreach ($g in $groups) {
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
# Write metadata checkpoint after group memberships phase
Save-Json -Path $metadataFile -Data $metadata

# ---------------------------
# 5) Export Project Memberships (users + group shares)
# ---------------------------
Write-Log 'Exporting project memberships...'
$projectMemberships = @()
foreach ($p in $projects) {
    $pid = $p.id
    $ppath = $p.path_with_namespace

    # Users: all vs direct
    $pmAllResp = Invoke-GitLabPagedRequest -Endpoint "/projects/$pid/members/all"
    $pmDirectResp = Invoke-GitLabPagedRequest -Endpoint "/projects/$pid/members"

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

# ---------------------------
# 6) Export Custom Member Roles (optional)
# ---------------------------
if ($IncludeMemberRoles.IsPresent) {
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
else {
    Write-Log 'Skipping custom member roles (not requested).'
}

# ---------------------------
# 7) Write metadata.json and finalize
# ---------------------------
$metadata.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
$summaryNote = "Exported users=$($metadata.counts.users), groups=$($metadata.counts.groups), projects=$($metadata.counts.projects), group_memberships=$($metadata.counts.group_memberships), project_memberships=$($metadata.counts.project_memberships)."
$summaryNote2 = "Membership entry totals: group_entries=$($metadata.counts.group_membership_entries), project_entries=$($metadata.counts.project_membership_entries)."
$metadata.notes += $summaryNote
$metadata.notes += $summaryNote2
Save-Json -Path $metadataFile -Data $metadata
Write-Log "Metadata saved -> $metadataFile"

Write-Log 'Export completed successfully.'

} # End try block
finally {
    # Clean up sensitive token from memory
    if ($PlainToken) {
        $PlainToken = $null
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