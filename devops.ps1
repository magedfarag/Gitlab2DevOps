# ============================
#  Azure DevOps on-prem 3-step bootstrap & migration
#  1) Prepare GitLab project
#  2) Create & initialize Azure DevOps project
#  3) Mirror GitLab project -> Azure Repos (all refs)
# ============================

param(
    [string]$CollectionUrl = ($env:ADO_COLLECTION_URL -or "https://devops.example.com/DefaultCollection"),
    [string]$AdoPat = ($env:ADO_PAT -or ""),
    [string]$GitLabBaseUrl = ($env:GITLAB_BASE_URL -or "https://gitlab.example.com"),
    [string]$GitLabToken = ($env:GITLAB_PAT -or ""),
    [string]$AdoApiVersion = "7.1",
    [int]$BuildDefinitionId = 0,
    [string]$SonarStatusContext = "",
    [switch]$SkipCertificateCheck
)

# -----------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Validate required configuration
if ([string]::IsNullOrWhiteSpace($AdoPat)) {
    Write-Host "[ERROR] Azure DevOps PAT is required!"
    Write-Host "        Set it via -AdoPat parameter or `$env:ADO_PAT environment variable"
    Write-Host "        Example: `$env:ADO_PAT = 'your-pat-here'"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($GitLabToken)) {
    Write-Host "[ERROR] GitLab token is required!"
    Write-Host "        Set it via -GitLabToken parameter or `$env:GITLAB_PAT environment variable"
    Write-Host "        Example: `$env:GITLAB_PAT = 'your-token-here'"
    exit 1
}

Write-Host "[INFO] Configuration loaded successfully"
Write-Host "       Azure DevOps: $CollectionUrl (API v$AdoApiVersion)"
Write-Host "       GitLab: $GitLabBaseUrl"
if ($SkipCertificateCheck) {
    Write-Host "       SSL Certificate Check: DISABLED (not recommended for production)"
}
Write-Host ""

function New-AuthHeader {
  param([string]$pat)
  $pair  = ":$pat"
  $bytes = [Text.Encoding]::ASCII.GetBytes($pair)
  @{ Authorization = "Basic $([Convert]::ToBase64String($bytes))"
     "Content-Type" = "application/json" }
}
$AdoHeaders = New-AuthHeader -pat $AdoPat

function Invoke-AdoRest {
  param(
    [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','PATCH','DELETE')][string]$Method,
    [Parameter(Mandatory)][string]$Path,      # starts with /_apis or /{project}/_apis
    [object]$Body = $null,
    [switch]$Preview
  )
  $api = if ($Preview) { "$AdoApiVersion-preview.1" } else { $AdoApiVersion }
  
  $queryString = if ($Path -like '*api-version=*') { '' } else { "?api-version=$api" }
  $uri = $CollectionUrl.TrimEnd('/') + $Path + $queryString
  
  if ($null -ne $Body -and ($Body -isnot [string])) { 
    $Body = ($Body | ConvertTo-Json -Depth 100) 
  }
  
  $invokeParams = @{
    Method = $Method
    Uri = $uri
    Headers = $AdoHeaders
    Body = $Body
  }
  
  if ($SkipCertificateCheck) {
    $invokeParams.SkipCertificateCheck = $true
  }
  
  try {
    $response = Invoke-RestMethod @invokeParams
    Write-Verbose "[ADO REST] $Method $Path -> SUCCESS"
    return $response
  } catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $statusDesc = $_.Exception.Response.StatusDescription
    Write-Host "[ERROR] ADO REST $Method $Path -> HTTP $statusCode $statusDesc"
    throw
  }
}

function Invoke-GitLab {
  param([Parameter(Mandatory)][string]$Path) # begins with /api/v4/...
  if (-not $GitLabToken) { throw "GitLab token not set." }
  $headers = @{ 'PRIVATE-TOKEN' = $GitLabToken }
  $uri = $GitLabBaseUrl.TrimEnd('/') + $Path
  
  $invokeParams = @{
    Method = 'GET'
    Uri = $uri
    Headers = $headers
  }
  
  if ($SkipCertificateCheck) {
    $invokeParams.SkipCertificateCheck = $true
  }
  
  try {
    Invoke-RestMethod @invokeParams
  } catch {
    # If GitLab returns a structured error (JSON), surface it more clearly
    $resp = $_.Exception.Response
    if ($resp -ne $null) {
      try {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
      } catch { $body = $null }
      $status = $resp.StatusCode.value__ 2>$null
      $statusText = $resp.StatusDescription 2>$null
      $msg = if ($body -and $body.message) { $body.message } else { $body }
      throw "GitLab API error GET $uri -> HTTP $status $statusText : $msg"
    }
    throw
  }
}

# --------------- ADO: Core helpers ---------------
function Wait-Operation([string]$Id) {
  for ($i=0; $i -lt 60; $i++) {
    $op = Invoke-AdoRest GET "/_apis/operations/$Id"
    if ($op.status -in 'succeeded','failed','cancelled') { return $op }
    Start-Sleep 3
  }
  throw "Timeout waiting for operation $Id"
}

function Ensure-Project([string]$Name) {
  $list = Invoke-AdoRest GET "/_apis/projects?`$top=5000"
  $p = $list.value | ? { $_.name -eq $Name }
  if ($p) { return $p }
  $body = @{
    name = $Name
    description = "Provisioned by automation"
    capabilities = @{
      versioncontrol  = @{ sourceControlType = "Git" }
      processTemplate = @{ templateTypeId = "6b724908-ef14-45cf-84f8-768b5384da45" } # Agile
    }
  }
  $resp = Invoke-AdoRest POST "/_apis/projects" -Body $body
  $final = Wait-Operation $resp.id
  if ($final.status -ne 'succeeded') { throw "Project creation failed." }
  Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Name))"
}

function Get-ProjectDescriptor([string]$ProjectId) {
  (Invoke-AdoRest GET "/_apis/graph/descriptors/$ProjectId").value
}

function Get-BuiltInGroupDesc([string]$ProjDesc,[string]$GroupName) {
  $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&`$top=200"
  ($groups.value | ? { $_.principalName -like "*\[$GroupName]" }).descriptor
}

function Ensure-Group([string]$ProjDesc,[string]$DisplayName) {
  $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&`$top=200"
  $existing = $groups.value | ? { $_.displayName -eq $DisplayName }
  if ($existing) { return $existing }
  Invoke-AdoRest POST "/_apis/graph/groups" -Body @{
    displayName    = $DisplayName
    description    = "Auto-provisioned group: $DisplayName"
    scopeDescriptor= $ProjDesc
  }
}

function Ensure-Membership([string]$Container,[string]$Member) {
  try { 
    Invoke-AdoRest PUT "/_apis/graph/memberships/$Member/$Container" 
  } catch { 
    if ($_.Exception.Response.StatusCode.value__ -eq 409) {
      # 409 Conflict means membership already exists, which is expected
      Write-Host "[INFO] Membership already exists: $Member -> $Container"
    } else {
      throw
    }
  }
}

# --------------- Areas, Wiki, Templates, Policies ---------------
function Ensure-Area([string]$Project,[string]$Area) {
  try { Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas/$([uri]::EscapeDataString($Area))" } 
  catch { Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas" -Body @{ name = $Area } }
}

function Ensure-ProjectWiki([string]$ProjId,[string]$Project) {
  $w = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis"
  $projWiki = $w.value | ? { $_.type -eq 'projectWiki' }
  if ($projWiki) { return $projWiki }
  Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis" -Body @{ name="$Project.wiki"; type="projectWiki"; projectId=$ProjId }
}

function Upsert-WikiPage([string]$Project,[string]$WikiId,[string]$Path,[string]$Markdown) {
  $enc = [uri]::EscapeDataString($Path)
  Invoke-AdoRest PUT "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?path=$enc" -Body @{ content=$Markdown } | Out-Null
}

function Ensure-TeamTemplates([string]$Project,[string]$Team) {
  $base = "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/wit/templates"
  $existing = Invoke-AdoRest GET $base
  $byName = @{}; $existing.value | % { $byName[$_.name] = $_ }
  if (-not $byName.ContainsKey('User Story – DoR/DoD')) {
    Invoke-AdoRest POST $base -Body @{
      name='User Story – DoR/DoD'; description='Template with Acceptance Criteria'
      workItemTypeName='User Story'
      fields=@{
        'System.Title'='As a <role>, I want <capability> so that <outcome>'
        'System.Description'="## Context`n`n## Definition of Ready`n- [ ] ...`n`n## Definition of Done`n- [ ] ..."
        'Microsoft.VSTS.Common.AcceptanceCriteria'="- [ ] Given ... When ... Then ..."
        'Microsoft.VSTS.Common.Priority'=2; 'System.Tags'='template;user-story'
      }
    } | Out-Null
  }
  if (-not $byName.ContainsKey('Bug – Triaging')) {
    Invoke-AdoRest POST $base -Body @{
      name='Bug – Triaging'; description='Bug template with repro steps'
      workItemTypeName='Bug'
      fields=@{
        'System.Title'='[BUG] <brief>'; 'Microsoft.VSTS.TCM.ReproSteps'="### Expected`n### Actual`n### Steps`n1. ..."
        'Microsoft.VSTS.Common.Severity'='3 - Medium'; 'Microsoft.VSTS.Common.Priority'=2; 'System.Tags'='template;bug'
      }
    } | Out-Null
  }
}

# Policy type IDs (Microsoft documented)
$POLICY_REQUIRED_REVIEWERS = 'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd'
$POLICY_BUILD_VALIDATION  = '0609b952-1397-4640-95ec-e00a01b2f659'
$POLICY_COMMENT_RESOLUTION= 'c6a1889d-b943-48DE-8ECA-6E5AC81B08B6'
$POLICY_WORK_ITEM_LINK    = 'fd2167ab-b0be-447a-8ec8-39368250530e'
$POLICY_STATUS_CHECK      = 'caae6c6e-4c53-40e6-94f0-6d7410830a9b'

function Ensure-Repo([string]$Project,[string]$ProjId,[string]$RepoName,[switch]$AllowExisting) {
  $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories"
  $existing = $repos.value | ? { $_.name -eq $RepoName }
  if ($existing) { 
    if ($AllowExisting) {
      Write-Host "[INFO] Repository '$RepoName' already exists. Will sync/update content."
      return $existing
    } else {
      return $existing
    }
  }
  Write-Host "[INFO] Creating new repository: $RepoName"
  Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -Body @{ name=$RepoName; project=@{ id=$ProjId } }
}

function Get-RepoDefaultBranch([string]$Project,[string]$RepoId) {
  $r = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId"
  if ($r.defaultBranch) { $r.defaultBranch } else { 'refs/heads/main' }
}

function Ensure-BranchPolicies([string]$Project,[string]$RepoId,[string]$Ref,[int]$Min=2,[int]$BuildId,[string]$StatusContext){
  $cfgs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations"
  $scope = @{ repositoryId=$RepoId; refName=$Ref; matchKind="exact" }
  function Exists([string]$id){ $cfgs.value | ? { $_.type.id -eq $id -and $_.settings.scope[0].refName -eq $Ref } }

  if (-not (Exists $POLICY_REQUIRED_REVIEWERS)) {
    Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
      isEnabled=$true; isBlocking=$true; type=@{ id=$POLICY_REQUIRED_REVIEWERS }
      settings=@{ minimumApproverCount=[Math]::Max(1,$Min); creatorVoteCounts=$false; allowDownvotes=$true; resetOnSourcePush=$false; scope=@($scope) }
    } | Out-Null
  }
  if (-not (Exists $POLICY_WORK_ITEM_LINK)) {
    Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
      isEnabled=$true; isBlocking=$true; type=@{ id=$POLICY_WORK_ITEM_LINK }; settings=@{ scope=@($scope) }
    } | Out-Null
  }
  if (-not (Exists $POLICY_COMMENT_RESOLUTION)) {
    Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
      isEnabled=$true; isBlocking=$true; type=@{ id=$POLICY_COMMENT_RESOLUTION }; settings=@{ scope=@($scope) }
    } | Out-Null
  }
  if ($BuildId -gt 0 -and -not (Exists $POLICY_BUILD_VALIDATION)) {
    Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
      isEnabled=$true; isBlocking=$true; type=@{ id=$POLICY_BUILD_VALIDATION }
      settings=@{ displayName="CI validation"; validDuration=0; queueOnSourceUpdateOnly=$false; buildDefinitionId=$BuildId; scope=@($scope) }
    } | Out-Null
  }
  if ($StatusContext -and -not (Exists $POLICY_STATUS_CHECK)) {
    Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
      isEnabled=$true; isBlocking=$true; type=@{ id=$POLICY_STATUS_CHECK }
      settings=@{ statusName=$StatusContext; invalidateOnSourceUpdate=$true; scope=@($scope) }
    } | Out-Null
  }
}

# Git security namespace and DENY for BA
$NS_GIT = '2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87'
$GIT_BITS = @{ GenericContribute=4; ForcePush=8; PullRequestContribute=262144 }
function Ensure-RepoDeny([string]$ProjectId,[string]$RepoId,[string]$GroupDescriptor,[int]$DenyBits) {
  $token = "repoV2/$ProjectId/$RepoId"
  
  # First, verify the group descriptor exists and get current permissions
  try {
    $currentAcl = Invoke-AdoRest GET "/_apis/securitynamespaces/$NS_GIT/accesscontrolentries?token=$([uri]::EscapeDataString($token))&descriptors=$([uri]::EscapeDataString($GroupDescriptor))"
    Write-Host "[INFO] Current ACL for group $GroupDescriptor on repo $RepoId"
    if ($currentAcl.value.Count -gt 0) {
      Write-Host "[INFO] Current permissions - Allow: $($currentAcl.value[0].allow), Deny: $($currentAcl.value[0].deny)"
    } else {
      Write-Host "[INFO] No existing permissions found for this group"
    }
  } catch {
    Write-Host "[WARN] Could not retrieve current ACL (group may not exist): $_"
  }
  
  # Apply the deny permissions
  Write-Host "[INFO] Applying deny permissions (bits: $DenyBits) to group $GroupDescriptor"
  Invoke-AdoRest POST "/_apis/securitynamespaces/$NS_GIT/accesscontrolentries" -Body @{
    token=$token; merge=$true; accessControlEntries=@(@{ descriptor=$GroupDescriptor; allow=0; deny=$DenyBits })
  } | Out-Null
  Write-Host "[INFO] Deny permissions successfully applied"
}

# --------------- GITLAB (prepare + migrate) ---------------
function Clear-GitCredentials {
  param(
    [Parameter(Mandatory)][string]$RepoPath,
    [Parameter(Mandatory)][string]$RemoteName = "ado"
  )
  <#
    Removes PAT credentials from Git config to prevent credential exposure.
    Called after Git operations complete.
  #>
  if (Test-Path $RepoPath) {
    Push-Location $RepoPath
    try {
      # Remove the http extraheader that contains the PAT
      $remotes = git remote 2>$null
      if ($remotes -contains $RemoteName) {
        $remoteUrl = git remote get-url $RemoteName 2>$null
        if ($remoteUrl) {
          git config --unset-all "http.$remoteUrl.extraheader" 2>$null | Out-Null
          Write-Host "[INFO] Cleared credentials from Git config for remote '$RemoteName'"
        }
      }
    } catch {
      Write-Host "[WARN] Failed to clear Git credentials: $_"
    } finally {
      Pop-Location
    }
  }
}

function New-MigrationPreReport {
  param(
    [Parameter(Mandatory)][string]$GitLabPath,
    [Parameter(Mandatory)][string]$AdoProject,
    [Parameter(Mandatory)][string]$AdoRepoName,
    [string]$OutputPath = (Join-Path (Get-Location) "migration-precheck-$((Get-Date).ToString('yyyyMMdd-HHmmss')).json"),
    [switch]$AllowSync
  )

  Write-Host "[INFO] Generating pre-migration report..."
  
  # 1. GitLab project facts
  $gl = Get-GitLabProject $GitLabPath  # will throw clearly if token/path wrong

  # 2. Azure DevOps project existence
  $adoProjects = Invoke-AdoRest GET "/_apis/projects?`$top=5000"
  $adoProj     = $adoProjects.value | Where-Object { $_.name -eq $AdoProject }

  # 3. Repo name collision
  $repoExists  = $false
  if ($adoProj) {
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($AdoProject))/_apis/git/repositories"
    $repoExists = $repos.value | Where-Object { $_.name -eq $AdoRepoName }
  }

  $report = [pscustomobject]@{
    timestamp          = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    gitlab_path        = $GitLabPath
    gitlab_size_mb     = [math]::Round(($gl.statistics.repository_size / 1MB), 2)
    gitlab_lfs_enabled = $gl.lfs_enabled
    gitlab_visibility  = $gl.visibility
    gitlab_default_branch = $gl.default_branch
    ado_project        = $AdoProject
    ado_project_exists = [bool]$adoProj
    ado_repo_name      = $AdoRepoName
    ado_repo_exists    = [bool]$repoExists
    sync_mode          = $AllowSync
    ready_to_migrate   = if ($AllowSync) { [bool]$adoProj } else { ($adoProj -and -not $repoExists) }
    blocking_issues    = @()
  }

  # Add blocking issues
  if (-not $adoProj) {
    $report.blocking_issues += "Azure DevOps project '$AdoProject' does not exist"
  }
  if ($repoExists -and -not $AllowSync) {
    $report.blocking_issues += "Repository '$AdoRepoName' already exists in project '$AdoProject'. Use -AllowSync to update existing repository."
  } elseif ($repoExists -and $AllowSync) {
    Write-Host "[INFO] Sync mode enabled: Repository '$AdoRepoName' will be updated with latest changes from GitLab"
  }

  $report | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
  Write-Host "[INFO] Pre-migration report written to $OutputPath"
  
  # Display summary
  Write-Host "[INFO] Pre-migration Summary:"
  Write-Host "       GitLab: $GitLabPath ($($report.gitlab_size_mb) MB)"
  Write-Host "       Azure DevOps: $AdoProject -> $AdoRepoName"
  Write-Host "       Ready to migrate: $($report.ready_to_migrate)"
  
  if ($report.blocking_issues.Count -gt 0) {
    Write-Host "[ERROR] Blocking issues found:"
    foreach ($issue in $report.blocking_issues) {
      Write-Host "        - $issue"
    }
    throw "Precheck failed – resolve blocking issues before proceeding with migration."
  }
  
  return $report
}

function Get-GitLabProject([string]$PathWithNamespace) {
  $enc = [uri]::EscapeDataString($PathWithNamespace)  # encodes '/' to %2F as required
  $fullPath = "/api/v4/projects/$enc" + "?statistics=true"
  try {
    Invoke-GitLab $fullPath
  } catch {
    # Common causes: incorrect path, project is private and token lacks access, or token scope
    Write-Host "[ERROR] Failed to fetch GitLab project '$PathWithNamespace'."
    Write-Host "        Request URI: $GitLabBaseUrl$fullPath"
    Write-Host "        Error: $_"
    Write-Host "        Suggestions:"
    Write-Host "          - Verify the project path is correct (group/subgroup/project)."
    Write-Host "          - Ensure the GitLab token has 'api' scope and can access the project."
    Write-Host "          - If the project is private, confirm the token user is a member or has access."
    throw
  }
}

function Test-GitLabAuth {
  <#
    Simple helper to validate the base URL and token can reach the GitLab instance and list accessible projects.
    Usage: Test-GitLabAuth
  #>
  if (-not $GitLabToken) { throw "GitLab token not set." }
  $headers = @{ 'PRIVATE-TOKEN' = $GitLabToken }
  $uri = $GitLabBaseUrl.TrimEnd('/') + "/api/v4/projects?membership=true&per_page=5"
  try {
    $res = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
    Write-Host "[OK] GitLab auth successful. Returned $(($res | Measure-Object).Count) project(s)."
    $res | Select-Object -Property id,path_with_namespace,visibility | Format-Table -AutoSize
  } catch {
    $resp = $_.Exception.Response
    if ($resp -ne $null) {
      try {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction SilentlyContinue
      } catch { $body = $null }
      $status = $resp.StatusCode.value__ 2>$null
      $statusText = $resp.StatusDescription 2>$null
      $msg = if ($body -and $body.message) { $body.message } else { $body }
      throw "GitLab auth test failed GET $uri -> HTTP $status $statusText : $msg"
    }
    throw
  }
}

function Prepare-GitLab([string]$SrcPath) {
  <#
    Downloads GitLab project and analyzes it for migration readiness.
    Creates project folder structure, downloads repository, and generates detailed report.
    Usage: Prepare-GitLab "group/project-name"
  #>
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found on PATH." }
  $p = Get-GitLabProject $SrcPath
  
  # Create project metadata report
  $report = [pscustomobject]@{
    project            = $p.path_with_namespace
    http_url_to_repo   = $p.http_url_to_repo
    default_branch     = $p.default_branch
    visibility         = $p.visibility
    lfs_enabled        = $p.lfs_enabled
    repo_size_MB       = [math]::Round(($p.statistics.repository_size/1MB),2)
    lfs_size_MB        = [math]::Round(($p.statistics.lfs_objects_size/1MB),2)
    open_issues        = $p.open_issues_count
    last_activity      = $p.last_activity_at
    preparation_time   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  }
  
  # Create project-specific folder structure
  $migrationsDir = Join-Path (Get-Location) "Migrations"
  $projectName = $p.path  # Use the project name (last part of path)
  $projectDir = Join-Path $migrationsDir $projectName
  
  if (-not (Test-Path $projectDir)) {
    New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
    Write-Host "[INFO] Created project directory: $projectDir"
  }
  
  # Create subdirectories for organization
  $reportsDir = Join-Path $projectDir "reports"
  $logsDir = Join-Path $projectDir "logs" 
  $repoDir = Join-Path $projectDir "repository"
  
  @($reportsDir, $logsDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
      New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
  }
  
  # Save preflight report in project-specific reports folder
  $reportFile = Join-Path $reportsDir "preflight-report.json"
  $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
  Write-Host "[OK] Preflight report written: $reportFile"
  
  # Download repository for migration preparation
  $gitUrl = $p.http_url_to_repo -replace '^https://', "https://oauth2:$GitLabToken@"
  
  if (Test-Path $repoDir) {
    Write-Host "[INFO] Repository directory exists, updating..."
    Push-Location $repoDir
    try {
      # Fetch latest changes
      git remote set-url origin $gitUrl
      git fetch --all --prune
      Write-Host "[OK] Repository updated successfully"
    } catch {
      Write-Host "[WARN] Failed to update existing repository: $_"
      Write-Host "[INFO] Will re-clone repository..."
      Pop-Location
      Remove-Item -Recurse -Force $repoDir
      $needsClone = $true
    }
    if (-not $needsClone) { Pop-Location }
  }
  
  if (-not (Test-Path $repoDir)) {
    Write-Host "[INFO] Downloading repository (mirror clone)..."
    Write-Host "       Size: $($report.repo_size_MB) MB"
    if ($report.lfs_enabled -and $report.lfs_size_MB -gt 0) {
      Write-Host "       LFS data: $($report.lfs_size_MB) MB"
      if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
        Write-Host "[WARN] Git LFS not found but repository uses LFS. Install git-lfs for complete migration."
      }
    }
    
    try {
      git clone --mirror $gitUrl $repoDir
      Write-Host "[OK] Repository downloaded to: $repoDir"
      
      # Update report with local repository info
      $report | Add-Member -NotePropertyName "local_repo_path" -NotePropertyValue $repoDir
      $report | Add-Member -NotePropertyName "download_time" -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
      
    } catch {
      Write-Host "[ERROR] Failed to download repository: $_"
      Write-Host "[INFO] Migration can still proceed but will require fresh download in Option 3"
    }
  }
  
  # Create preparation log
  $prepLogFile = Join-Path $logsDir "preparation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
  @(
    "=== GitLab Project Preparation Log ==="
    "Timestamp: $(Get-Date)"
    "Project: $($p.path_with_namespace)"
    "GitLab URL: $($p.http_url_to_repo)"
    "Project Directory: $projectDir"
    "Repository Size: $($report.repo_size_MB) MB"
    "LFS Enabled: $($report.lfs_enabled)"
    "LFS Size: $($report.lfs_size_MB) MB"
    "Default Branch: $($report.default_branch)"
    "Visibility: $($report.visibility)"
    "Last Activity: $($report.last_activity)"
    ""
    "Files Created:"
    "- Report: $reportFile"
    if (Test-Path $repoDir) { "- Repository: $repoDir" }
    "- Log: $prepLogFile"
    ""
    "=== Preparation Completed Successfully ==="
  ) | Out-File -FilePath $prepLogFile -Encoding utf8
  
  # Validate Git access (quick check)
  Write-Host "[INFO] Validating Git access..."
  git ls-remote $gitUrl HEAD | Out-Null
  Write-Host "[OK] Git access validated."
  
  # Summary
  Write-Host ""
  Write-Host "=== PREPARATION SUMMARY ==="
  Write-Host "Project: $($p.path_with_namespace)"
  Write-Host "Project folder: $projectDir"
  Write-Host "Size: $($report.repo_size_MB) MB"
  if ($report.lfs_enabled) { Write-Host "LFS: $($report.lfs_size_MB) MB" }
  Write-Host "Default branch: $($report.default_branch)"
  Write-Host "Visibility: $($report.visibility)"
  Write-Host ""
  Write-Host "Generated files:"
  Write-Host "  Report: $reportFile"
  Write-Host "  Log: $prepLogFile"
  if (Test-Path $repoDir) { Write-Host "  Repository: $repoDir" }
  Write-Host "==========================="
}

function Init-Project([string]$DestProject,[string]$RepoName) {
  <#
    Creates and sets up Azure DevOps project with complete organizational structure.
    Includes: RBAC groups, areas, wiki, work item templates, branch policies, and security restrictions.
    Usage: Init-Project "MyProject" "my-repo"
  #>
  $proj = Ensure-Project $DestProject
  $projId = $proj.id
  $desc  = Get-ProjectDescriptor $projId
  $descContrib = Get-BuiltInGroupDesc $desc "Contributors"
  $descProjAdm = Get-BuiltInGroupDesc $desc "Project Administrators"

  $grpDev  = Ensure-Group $desc "Dev"
  $grpQA   = Ensure-Group $desc "QA"
  $grpBA   = Ensure-Group $desc "BA"
  $grpRel  = Ensure-Group $desc "Release Approvers"
  $grpPipe = Ensure-Group $desc "Pipeline Maintainers"

  # Nesting (Dev/QA/BA -> Contributors). Pipeline Maintainers -> Project Administrators.
  Ensure-Membership $descContrib $grpDev.descriptor
  Ensure-Membership $descContrib $grpQA.descriptor
  Ensure-Membership $descContrib $grpBA.descriptor
  Ensure-Membership $descProjAdm $grpPipe.descriptor

  # Areas
  "Requirements","Development","QA" | % { Ensure-Area $DestProject $_ | Out-Null }

  # Wiki & Home
  $wiki = Ensure-ProjectWiki $projId $DestProject
  $wikiHome = @"
# $DestProject

## Conventions
- **PRs**: ≥2 reviewers, linked work item, all comments resolved
- **CI**: build validation on PR (if configured)
- **Security**: required status checks (if configured)
"@
  Upsert-WikiPage $DestProject $wiki.id "Home" $wikiHome

  # Templates (Default team + 'BA' if a team exists)
  $teams = Invoke-AdoRest GET "/_apis/projects/$projId/teams"
  $defaultTeam = ($teams.value | Select-Object -First 1).name
  Ensure-TeamTemplates $DestProject $defaultTeam
  Ensure-TeamTemplates $DestProject "BA"

  # Repo (to receive migration)
  $repo = Ensure-Repo $DestProject $projId $RepoName
  $defaultRef = Get-RepoDefaultBranch $DestProject $repo.id

  # Branch policies
  Ensure-BranchPolicies $DestProject $repo.id $defaultRef 2 $BuildDefinitionId $SonarStatusContext

  # BA must not be able to push/PR
  $deny = ($GIT_BITS.GenericContribute + $GIT_BITS.ForcePush + $GIT_BITS.PullRequestContribute)
  Ensure-RepoDeny $projId $repo.id $grpBA.descriptor $deny

  Write-Host "[OK] Project '$DestProject' initialized (RBAC, areas, wiki, templates, policies, repo '$RepoName')."
}

function Migrate-One([string]$SrcPath,[string]$DestProject,[switch]$AllowSync) {
  <#
    Migrates a single GitLab project to Azure DevOps repository.
    Uses cached preparation data if available, applies policies and security restrictions.
    Supports re-running to sync updates from GitLab.
    Usage: Migrate-One "group/project" "DestinationProject" [-AllowSync]
  #>
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git not found on PATH." }
  
  # ENFORCE PRE-MIGRATION REPORT REQUIREMENT
  $repoName = ($SrcPath -split '/')[-1]
  try {
    $preReport = New-MigrationPreReport -GitLabPath $SrcPath -AdoProject $DestProject -AdoRepoName $repoName -AllowSync:$AllowSync
    Write-Host "[OK] Pre-migration validation passed"
    if ($AllowSync -and $preReport.ado_repo_exists) {
      Write-Host "[INFO] SYNC MODE: Will update existing repository with latest changes"
    }
  } catch {
    Write-Host "[ERROR] Pre-migration validation failed: $_"
    throw "Migration cannot proceed without successful pre-migration validation"
  }
  
  # Determine project-specific folders
  $migrationsDir = Join-Path (Get-Location) "Migrations"
  $projectName = ($SrcPath -split '/')[-1]
  $projectDir = Join-Path $migrationsDir $projectName
  $reportsDir = Join-Path $projectDir "reports"
  $logsDir = Join-Path $projectDir "logs"
  $repoDir = Join-Path $projectDir "repository"
  
  # Ensure project directories exist
  @($projectDir, $reportsDir, $logsDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
      New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
  }
  
  # Check for existing preflight report
  $preflightFile = Join-Path $reportsDir "preflight-report.json"
  $useLocalRepo = $false
  $gl = $null
  
  if (Test-Path $preflightFile) {
    Write-Host "[INFO] Found project directory: $projectDir"
    Write-Host "[INFO] Using preflight report: $preflightFile"
    $preflightData = Get-Content $preflightFile | ConvertFrom-Json
    
    # Validate repository size and warn if large
    if ($preflightData.repo_size_MB -gt 100) {
      Write-Host "[WARN] Large repository detected: $($preflightData.repo_size_MB) MB"
    }
    
    # Check LFS requirements
    if ($preflightData.lfs_enabled -and $preflightData.lfs_size_MB -gt 0) {
      if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
        throw "Git LFS required but not found. Repository has $($preflightData.lfs_size_MB) MB of LFS data."
      }
      Write-Host "[INFO] Git LFS detected: $($preflightData.lfs_size_MB) MB of LFS objects"
    }
    
    # Use cached project data
    $gl = [pscustomobject]@{
      path = $preflightData.project.Split('/')[-1]
      http_url_to_repo = $preflightData.http_url_to_repo
      path_with_namespace = $preflightData.project
    }
    
    # Check if local repository exists from Option 1
    if (Test-Path $repoDir) {
      Write-Host "[INFO] Found local repository from preparation step"
      Write-Host "[INFO] Updating local repository with latest changes..."
      
      $gitUrl = $gl.http_url_to_repo -replace '^https://', "https://oauth2:$GitLabToken@"
      Push-Location $repoDir
      try {
        git remote set-url origin $gitUrl
        git fetch --all --prune
        Write-Host "[OK] Local repository updated successfully"
        $useLocalRepo = $true
      } catch {
        Write-Host "[WARN] Failed to update local repository: $_"
        Write-Host "[INFO] Will download fresh copy..."
        Pop-Location
        $useLocalRepo = $false
      }
      if ($useLocalRepo) { Pop-Location }
    }
  } else {
    Write-Host "[WARN] No preflight report found. Strongly recommend running Option 1 first."
    Write-Host "[INFO] Fetching GitLab project data..."
    $gl = Get-GitLabProject $SrcPath
  }

  $proj = Ensure-Project $DestProject
  $projId = $proj.id
  $repoName = $gl.path

  # Create migration log in project-specific logs folder
  $logFile = Join-Path $logsDir "migration-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
  $startTime = Get-Date
  
  @(
    "=== Azure DevOps Migration Log ==="
    "Migration started: $startTime"
    "Source GitLab: $($gl.path_with_namespace)"
    "Source URL: $($gl.http_url_to_repo)"
    "Destination ADO Project: $DestProject"
    "Destination Repository: $repoName"
    "Project Directory: $projectDir"
    "Using local repo: $useLocalRepo"
    if ($useLocalRepo) { "Local repository: $repoDir" }
    ""
    "=== Migration Process ==="
  ) | Out-File -FilePath $logFile -Encoding utf8

  # Ensure ADO repo exists (allow existing if sync mode)
  $repo = Ensure-Repo $DestProject $projId $repoName -AllowExisting:$AllowSync
  $defaultRef = Get-RepoDefaultBranch $DestProject $repo.id
  
  $isSync = $AllowSync -and $preReport.ado_repo_exists
  if ($isSync) {
    Write-Host "[INFO] Sync mode: Updating existing repository"
    "=== SYNC MODE: Updating existing repository ===" | Out-File -FilePath $logFile -Append -Encoding utf8
  }

  try {
    if ($useLocalRepo) {
      # Use pre-downloaded repository (much faster!)
      Write-Host "[INFO] Using pre-downloaded repository for migration"
      "Using existing local repository: $repoDir" | Out-File -FilePath $logFile -Append -Encoding utf8
      $sourceRepo = $repoDir
    } else {
      # Fallback: download repository now
      Write-Host "[INFO] Downloading repository for migration..."
      $gitUrl = $gl.http_url_to_repo -replace '^https://', "https://oauth2:$GitLabToken@"
      $sourceRepo = Join-Path $env:TEMP ("migration-" + [Guid]::NewGuid() + ".git")
      "Downloading to temporary directory: $sourceRepo" | Out-File -FilePath $logFile -Append -Encoding utf8
      
      git clone --mirror $gitUrl $sourceRepo
      "Download completed successfully" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
    
    # Configure Azure DevOps remote and push
    $adoRemote = "$CollectionUrl/$([uri]::EscapeDataString($DestProject))/_git/$([uri]::EscapeDataString($repoName))"
    Push-Location $sourceRepo
    
    # Add or update Azure DevOps remote
    git remote remove ado 2>$null | Out-Null  # Remove if exists
    git remote add ado $adoRemote
    git config http.$adoRemote.extraheader "AUTHORIZATION: basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AdoPat")))"
    
    Write-Host "[INFO] Pushing all refs to Azure DevOps..."
    "Pushing to Azure DevOps: $adoRemote" | Out-File -FilePath $logFile -Append -Encoding utf8
    git push ado --mirror
    "Git refs push completed" | Out-File -FilePath $logFile -Append -Encoding utf8

    if (Get-Command git-lfs -ErrorAction SilentlyContinue) {
      Write-Host "[INFO] Processing Git LFS objects..."
      "Processing LFS objects" | Out-File -FilePath $logFile -Append -Encoding utf8
      git lfs fetch --all 2>$null | Out-Null
      git lfs push ado --all
      "LFS push completed" | Out-File -FilePath $logFile -Append -Encoding utf8
    }
    
    # Clean Git credentials from config before leaving
    Clear-GitCredentials -RepoPath $sourceRepo -RemoteName "ado"
    "Git credentials cleaned from config" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Pop-Location
    
    # Cleanup temporary download (but keep pre-downloaded repo)
    if (-not $useLocalRepo -and (Test-Path $sourceRepo)) {
      Remove-Item -Recurse -Force $sourceRepo
      "Temporary directory cleaned up" | Out-File -FilePath $logFile -Append -Encoding utf8
    }

    # Apply branch policies
    "Applying branch policies..." | Out-File -FilePath $logFile -Append -Encoding utf8
    Ensure-BranchPolicies $DestProject $repo.id $defaultRef 2 $BuildDefinitionId $SonarStatusContext

    # Apply security restrictions
    "Applying security restrictions..." | Out-File -FilePath $logFile -Append -Encoding utf8
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$(Get-ProjectDescriptor $projId)&`$top=200"
    $ba = $groups.value | ? { $_.displayName -eq 'BA' }
    if ($ba) {
      $deny = ($GIT_BITS.GenericContribute + $GIT_BITS.ForcePush + $GIT_BITS.PullRequestContribute)
      Ensure-RepoDeny $projId $repo.id $ba.descriptor $deny
      "BA group restrictions applied" | Out-File -FilePath $logFile -Append -Encoding utf8
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Create migration summary report
    $summaryFile = Join-Path $reportsDir "migration-summary.json"
    
    # Load existing summary if this is a sync operation
    $previousMigrations = @()
    if ($isSync -and (Test-Path $summaryFile)) {
      try {
        $existingSummary = Get-Content $summaryFile | ConvertFrom-Json
        if ($existingSummary.previous_migrations) {
          $previousMigrations = $existingSummary.previous_migrations
        } elseif ($existingSummary.migration_start) {
          # Convert single migration to array
          $previousMigrations = @([pscustomobject]@{
            migration_start = $existingSummary.migration_start
            migration_end = $existingSummary.migration_end
            duration_minutes = $existingSummary.duration_minutes
            status = $existingSummary.status
          })
        }
      } catch {
        Write-Host "[WARN] Could not read previous migration history: $_"
      }
    }
    
    # Add current migration to history
    if ($isSync) {
      $previousMigrations += [pscustomobject]@{
        migration_start = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        migration_end = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
        duration_minutes = [math]::Round($duration.TotalMinutes, 2)
        status = "SUCCESS"
        type = "SYNC"
      }
    }
    
    $summary = [pscustomobject]@{
      source_project = $gl.path_with_namespace
      source_url = $gl.http_url_to_repo
      destination_project = $DestProject
      destination_repo = $repoName
      migration_type = if ($isSync) { "SYNC" } else { "INITIAL" }
      migration_start = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
      migration_end = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
      duration_minutes = [math]::Round($duration.TotalMinutes, 2)
      used_local_repo = $useLocalRepo
      local_repo_path = if ($useLocalRepo) { $repoDir } else { $null }
      migration_log = $logFile
      status = "SUCCESS"
      migration_count = if ($isSync) { $previousMigrations.Count } else { 1 }
      previous_migrations = if ($isSync -and $previousMigrations.Count -gt 0) { $previousMigrations } else { $null }
      last_sync = if ($isSync) { $endTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
    }
    $summary | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $summaryFile
    
    @(
      ""
      "=== Migration Summary ==="
      "Migration completed: $endTime"
      "Total duration: $($duration.ToString('hh\:mm\:ss')) ($([math]::Round($duration.TotalMinutes, 2)) minutes)"
      "Used local repository: $useLocalRepo"
      if ($useLocalRepo) { "Local repository preserved at: $repoDir" }
      "Migration summary: $summaryFile"
      "Status: SUCCESS"
      ""
      "=== Files Generated ==="
      "Migration log: $logFile"
      "Summary report: $summaryFile"
      if (Test-Path $preflightFile) { "Preflight report: $preflightFile" }
      "=== Migration Completed Successfully ==="
    ) | Out-File -FilePath $logFile -Append -Encoding utf8

    if ($isSync) {
      Write-Host "[DONE] Synced '$SrcPath' -> '$DestProject' repo '$repoName' (sync #$($summary.migration_count))"
    } else {
      Write-Host "[DONE] Migrated '$SrcPath' -> '$DestProject' repo '$repoName' (all refs mirrored)"
    }
    Write-Host "[INFO] Project folder: $projectDir"
    Write-Host "[INFO] Migration log: $logFile"
    Write-Host "[INFO] Summary report: $summaryFile"
    Write-Host "[INFO] Duration: $($duration.ToString('hh\:mm\:ss'))"
    if ($useLocalRepo) {
      Write-Host "[INFO] Local repository preserved at: $repoDir"
    }
    if ($isSync -and $summary.previous_migrations) {
      Write-Host "[INFO] Previous migrations: $($summary.previous_migrations.Count)"
    }
    
  } catch {
    $errorTime = Get-Date
    $duration = $errorTime - $startTime
    
    # Create error summary
    $errorSummaryFile = Join-Path $reportsDir "migration-error.json"
    $errorSummary = [pscustomobject]@{
      source_project = $gl.path_with_namespace
      destination_project = $DestProject
      migration_start = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
      error_time = $errorTime.ToString('yyyy-MM-dd HH:mm:ss')
      duration_minutes = [math]::Round($duration.TotalMinutes, 2)
      error_message = $_.ToString()
      migration_log = $logFile
      status = "FAILED"
    }
    $errorSummary | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $errorSummaryFile
    
    @(
      ""
      "=== Migration Failed ==="
      "Migration failed: $errorTime"
      "Duration before failure: $($duration.ToString('hh\:mm\:ss'))"
      "Error: $_"
      "Error summary: $errorSummaryFile"
      "Status: FAILED"
    ) | Out-File -FilePath $logFile -Append -Encoding utf8
    
    # Cleanup on error (but preserve pre-downloaded repo)
    if (-not $useLocalRepo -and $sourceRepo -and (Test-Path $sourceRepo)) {
      Pop-Location -ErrorAction SilentlyContinue
      Remove-Item -Recurse -Force $sourceRepo -ErrorAction SilentlyContinue
    }
    
    Write-Host "[ERROR] Migration failed. Check project folder: $projectDir"
    Write-Host "[ERROR] Migration log: $logFile"
    Write-Host "[ERROR] Error summary: $errorSummaryFile"
    throw
  }
}

# --------------- BULK PREPARATION (multiple GitLab projects) ---------------
function Bulk-Prepare-GitLab([array]$ProjectPaths, [string]$DestProjectName) {
  <#
    Downloads and analyzes multiple GitLab projects for bulk migration.
    Creates consolidated template file and individual project preparations.
    Usage: Bulk-Prepare-GitLab @("group1/project1", "group2/project2") "MyDevOpsProject"
  #>
  
  if ($ProjectPaths.Count -eq 0) {
    throw "No projects specified for bulk preparation."
  }
  
  if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
    throw "Destination DevOps project name is required for bulk preparation."
  }
  
  Write-Host "=== BULK PREPARATION STARTING ==="
  Write-Host "Destination Project: $DestProjectName"
  Write-Host "Projects to prepare: $($ProjectPaths.Count)"
  Write-Host ""
  
  # Create bulk preparation folder using DevOps project name
  $migrationsDir = Join-Path (Get-Location) "Migrations"
  $bulkPrepDir = Join-Path $migrationsDir "bulk-prep-$DestProjectName"
  
  # Check if preparation already exists
  if (Test-Path $bulkPrepDir) {
    Write-Host "⚠️  Existing preparation found for '$DestProjectName'"
    Write-Host "   Folder: $bulkPrepDir"
    $choice = Read-Host "Continue and update existing preparation? (y/N)"
    if ($choice -notmatch '^[Yy]') {
      Write-Host "Bulk preparation cancelled."
      return
    }
    Write-Host "Updating existing preparation..."
  } else {
    Write-Host "Creating new preparation for '$DestProjectName'..."
    New-Item -ItemType Directory -Path $bulkPrepDir -Force | Out-Null
  }
  
  # Create bulk preparation log
  $bulkLogFile = Join-Path $bulkPrepDir "bulk-preparation.log"
  $startTime = Get-Date
  
  @(
    "=== GitLab Bulk Preparation Log ==="
    "Bulk preparation started: $startTime"
    "Destination DevOps Project: $DestProjectName"
    "Projects to prepare: $($ProjectPaths.Count)"
    ""
    "=== Project List ==="
  ) | Out-File -FilePath $bulkLogFile -Encoding utf8
  
  # Log all projects first
  foreach ($projectPath in $ProjectPaths) {
    "- $projectPath" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  }
  "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  
  $results = @()
  $projects = @()
  $successCount = 0
  $failureCount = 0
  
  # Process each project
  for ($i = 0; $i -lt $ProjectPaths.Count; $i++) {
    $projectPath = $ProjectPaths[$i]
    $projectNum = $i + 1
    $projectName = ($projectPath -split '/')[-1]
    
    Write-Host "[$projectNum/$($ProjectPaths.Count)] Preparing: $projectPath"
    "=== Project $projectNum/$($ProjectPaths.Count): $projectPath ===" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    "Start time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    try {
      # Check if project already prepared
      $projectDir = Join-Path $migrationsDir $projectName
      if (Test-Path $projectDir) {
        Write-Host "    Project already prepared, updating..."
        "Project already exists, updating: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      } else {
        Write-Host "    Downloading and analyzing project..."
        "Preparing new project..." | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      }
      
      # Run preparation for this project
      Prepare-GitLab $projectPath
      
      # Read the generated preflight report
      $preflightFile = Join-Path $projectDir "reports" "preflight-report.json"
      if (Test-Path $preflightFile) {
        $preflightData = Get-Content $preflightFile | ConvertFrom-Json
        
        # Add to bulk template
        $projects += [pscustomobject]@{
          gitlab_path = $projectPath
          ado_repo_name = $projectName
          description = "Migrated from $projectPath"
          repo_size_MB = $preflightData.repo_size_MB
          lfs_enabled = $preflightData.lfs_enabled
          lfs_size_MB = $preflightData.lfs_size_MB
          default_branch = $preflightData.default_branch
          visibility = $preflightData.visibility
          preparation_status = "SUCCESS"
        }
        
        $result = [pscustomobject]@{
          gitlab_project = $projectPath
          status = "SUCCESS"
          repo_size_MB = $preflightData.repo_size_MB
          lfs_size_MB = $preflightData.lfs_size_MB
          preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $successCount++
        
        Write-Host "    ✅ SUCCESS: $projectPath ($($preflightData.repo_size_MB) MB)"
      } else {
        throw "Preflight report not found after preparation"
      }
      
      $results += $result
      "Status: SUCCESS" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
    } catch {
      # Add failed project to template with error status
      $projects += [pscustomobject]@{
        gitlab_path = $projectPath
        ado_repo_name = $projectName
        description = "FAILED: $($_.ToString())"
        preparation_status = "FAILED"
        error_message = $_.ToString()
      }
      
      $result = [pscustomobject]@{
        gitlab_project = $projectPath
        status = "FAILED"
        error_message = $_.ToString()
        preparation_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      }
      $results += $result
      $failureCount++
      
      Write-Host "    ❌ FAILED: $projectPath"
      Write-Host "       Error: $_"
      "Status: FAILED" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "Error: $_" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    }
  }
  
  # Create consolidated bulk migration template
  $templateFile = Join-Path $bulkPrepDir "bulk-migration-template.json"
  $template = [pscustomobject]@{
    description = "Bulk migration template for '$DestProjectName' - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    destination_project = $DestProjectName
    preparation_summary = [pscustomobject]@{
      total_projects = $ProjectPaths.Count
      successful_preparations = $successCount
      failed_preparations = $failureCount
      total_size_MB = ($projects | Where-Object { $_.repo_size_MB } | Measure-Object -Property repo_size_MB -Sum).Sum
      total_lfs_MB = ($projects | Where-Object { $_.lfs_size_MB } | Measure-Object -Property lfs_size_MB -Sum).Sum
      preparation_time = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    projects = $projects
  }
  
  $template | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $templateFile
  
  # Create summary report
  $endTime = Get-Date
  $duration = $endTime - $startTime
  $summaryFile = Join-Path $bulkPrepDir "preparation-summary.json"
  
  $summary = [pscustomobject]@{
    preparation_start = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    preparation_end = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
    duration_minutes = [math]::Round($duration.TotalMinutes, 2)
    total_projects = $ProjectPaths.Count
    successful_preparations = $successCount
    failed_preparations = $failureCount
    success_rate = [math]::Round(($successCount / $ProjectPaths.Count) * 100, 1)
    total_size_MB = ($projects | Where-Object { $_.repo_size_MB } | Measure-Object -Property repo_size_MB -Sum).Sum
    results = $results
  }
  
  $summary | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $summaryFile
  
  # Final log entries
  @(
    "=== BULK PREPARATION SUMMARY ==="
    "Bulk preparation completed: $endTime"
    "Total duration: $($duration.ToString('hh\:mm\:ss')) ($([math]::Round($duration.TotalMinutes, 2)) minutes)"
    "Total projects: $($ProjectPaths.Count)"
    "Successful: $successCount"
    "Failed: $failureCount"
    "Success rate: $([math]::Round(($successCount / $ProjectPaths.Count) * 100, 1))%"
    "Template file: $templateFile"
    "Summary report: $summaryFile"
    "=== BULK PREPARATION COMPLETED ==="
  ) | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  
  # Display final results
  Write-Host ""
  Write-Host "=== BULK PREPARATION RESULTS ==="
  Write-Host "Destination Project: $DestProjectName"
  Write-Host "Total projects: $($ProjectPaths.Count)"
  Write-Host "✅ Successful: $successCount"
  Write-Host "❌ Failed: $failureCount"
  Write-Host "Success rate: $([math]::Round(($successCount / $ProjectPaths.Count) * 100, 1))%"
  Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
  if ($summary.total_size_MB -gt 0) {
    Write-Host "Total repository size: $($summary.total_size_MB) MB"
  }
  Write-Host ""
  Write-Host "Generated files:"
  Write-Host "  📋 Migration template: $templateFile"
  Write-Host "  📊 Preparation summary: $summaryFile"
  Write-Host "  📝 Preparation log: $bulkLogFile"
  Write-Host ""
  Write-Host "Next steps:"
  Write-Host "  1. Use Option 2 to create your Azure DevOps project: $DestProjectName"
  Write-Host "  2. Use Option 5 to review/edit the migration template"
  Write-Host "  3. Use Option 6 to execute the bulk migration"
  Write-Host "=================================="
}

# --------------- BULK MIGRATION (multiple GitLab projects to one ADO project) ---------------
function Bulk-Migrate-FromConfig([object]$config,[string]$DestProject,[switch]$AllowSync) {
  # Validate config object - support both old and new format
  $migrations = $null
  if ($config.migrations) {
    # New format: { targetAdoProject, migrations: [ {gitlabProject, adoRepository, preparation_status} ] }
    $migrations = $config.migrations
    if (-not $DestProject -and $config.targetAdoProject) {
      $DestProject = $config.targetAdoProject
    }
  } elseif ($config.projects) {
    # Legacy format: { projects: [ {gitlab_path, ado_repo_name} ] }
    $migrations = $config.projects
  }
  
  if (-not $migrations -or $migrations.Count -eq 0) {
    throw "No migrations found in configuration. Please add migrations to the config file."
  }
  
  if ([string]::IsNullOrWhiteSpace($DestProject)) {
    throw "Destination project not specified. Set 'targetAdoProject' in config or provide -DestProject parameter."
  }
  
  if ($AllowSync) {
    Write-Host "[INFO] SYNC MODE ENABLED: Existing repositories will be updated with latest changes"
  }
  
  Write-Host "=== BULK MIGRATION STARTING ==="
  Write-Host "Destination Project: $DestProject"
  Write-Host "Projects to migrate: $($migrations.Count)"
  Write-Host ""
  
  # Ensure destination project exists
  $proj = Ensure-Project $DestProject
  $projId = $proj.id
  
  # Create bulk migration folder
  $migrationsDir = Join-Path (Get-Location) "Migrations"
  $bulkDir = Join-Path $migrationsDir "bulk-migration-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  New-Item -ItemType Directory -Path $bulkDir -Force | Out-Null
  
  # Create bulk migration log
  $bulkLogFile = Join-Path $bulkDir "bulk-migration.log"
  $startTime = Get-Date
  
  @(
    "=== Azure DevOps Bulk Migration Log ==="
    "Bulk migration started: $startTime"
    "Destination ADO Project: $DestProject"
    "Projects to migrate: $($migrations.Count)"
    ""
    "=== Project List ==="
  ) | Out-File -FilePath $bulkLogFile -Encoding utf8
  
  # Log all projects first
  foreach ($projectConfig in $migrations) {
    # Support both old and new property names
    $srcPath = if ($projectConfig.gitlabProject) { $projectConfig.gitlabProject } else { $projectConfig.gitlab_path }
    $repoName = if ($projectConfig.adoRepository) { $projectConfig.adoRepository } 
                elseif ($projectConfig.ado_repo_name) { $projectConfig.ado_repo_name } 
                else { ($srcPath -split '/')[-1] }
    "- $srcPath → $repoName" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  }
  "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  
  $results = @()
  $successCount = 0
  $failureCount = 0
  
  # Process each project
  for ($i = 0; $i -lt $migrations.Count; $i++) {
    $projectConfig = $migrations[$i]
    # Support both old and new property names
    $srcPath = if ($projectConfig.gitlabProject) { $projectConfig.gitlabProject } else { $projectConfig.gitlab_path }
    $repoName = if ($projectConfig.adoRepository) { $projectConfig.adoRepository } 
                elseif ($projectConfig.ado_repo_name) { $projectConfig.ado_repo_name } 
                else { ($srcPath -split '/')[-1] }
    $projectNum = $i + 1
    
    Write-Host "[$projectNum/$($migrations.Count)] Processing: $srcPath → $repoName"
    "=== Project $projectNum/$($migrations.Count): $srcPath ===" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    "Start time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    try {
      # ENFORCE PRE-MIGRATION REPORT REQUIREMENT
      Write-Host "    Validating migration prerequisites..."
      try {
        $preReport = New-MigrationPreReport -GitLabPath $srcPath -AdoProject $DestProject -AdoRepoName $repoName -AllowSync:$AllowSync
        if ($AllowSync -and $preReport.ado_repo_exists) {
          Write-Host "    [SYNC] Will update existing repository"
          "SYNC MODE: Will update existing repository" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        }
        "Pre-migration validation passed" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      } catch {
        "Pre-migration validation failed: $_" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        throw "Pre-migration validation failed: $_"
      }
      
      # Use existing project folder if available
      $projectName = ($srcPath -split '/')[-1]
      $projectDir = Join-Path $migrationsDir $projectName
      
      if (Test-Path $projectDir) {
        Write-Host "    Using existing project data from: $projectDir"
        "Using existing project data: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      } else {
        Write-Host "    Preparing project (downloading repository)..."
        "No existing data found, preparing project..." | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
        Prepare-GitLab $srcPath
      }
      
      # Get project data
      $gl = Get-GitLabProject $srcPath
      
      # Create repository with custom name if specified (or use existing if sync mode)
      $isSync = $AllowSync -and $preReport.ado_repo_exists
      if ($isSync) {
        Write-Host "    Updating existing repository: $repoName"
        "SYNC: Updating existing repository" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      } else {
        Write-Host "    Creating repository: $repoName"
      }
      $repo = Ensure-Repo $DestProject $projId $repoName -AllowExisting:$AllowSync
      $defaultRef = Get-RepoDefaultBranch $DestProject $repo.id
      
      # Migrate repository
      Write-Host "    Migrating repository content..."
      $repoDir = Join-Path $projectDir "repository"
      $gitUrl = $gl.http_url_to_repo -replace '^https://', "https://oauth2:$GitLabToken@"
      
      if (Test-Path $repoDir) {
        # Update existing repository
        Push-Location $repoDir
        git remote set-url origin $gitUrl
        git fetch --all --prune
        Pop-Location
        $sourceRepo = $repoDir
      } else {
        # Download repository
        $sourceRepo = Join-Path $env:TEMP ("bulk-migration-" + [Guid]::NewGuid() + ".git")
        git clone --mirror $gitUrl $sourceRepo
      }
      
      # Push to Azure DevOps
      $adoRemote = "$CollectionUrl/$([uri]::EscapeDataString($DestProject))/_git/$([uri]::EscapeDataString($repoName))"
      Push-Location $sourceRepo
      
      git remote remove ado 2>$null | Out-Null
      git remote add ado $adoRemote
      git config http.$adoRemote.extraheader "AUTHORIZATION: basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AdoPat")))"
      
      git push ado --mirror
      
      # Handle LFS if needed
      if (Get-Command git-lfs -ErrorAction SilentlyContinue) {
        git lfs fetch --all 2>$null | Out-Null
        git lfs push ado --all
      }
      
      # Clean Git credentials from config before leaving
      Clear-GitCredentials -RepoPath $sourceRepo -RemoteName "ado"
      "Git credentials cleaned from config" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
      Pop-Location
      
      # Cleanup temporary repo if used
      if ($sourceRepo -ne $repoDir -and (Test-Path $sourceRepo)) {
        Remove-Item -Recurse -Force $sourceRepo
      }
      
      # Apply branch policies
      Ensure-BranchPolicies $DestProject $repo.id $defaultRef 2 $BuildDefinitionId $SonarStatusContext
      
      # Apply security restrictions
      $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$(Get-ProjectDescriptor $projId)&`$top=200"
      $ba = $groups.value | ? { $_.displayName -eq 'BA' }
      if ($ba) {
        $deny = ($GIT_BITS.GenericContribute + $GIT_BITS.ForcePush + $GIT_BITS.PullRequestContribute)
        Ensure-RepoDeny $projId $repo.id $ba.descriptor $deny
      }
      
      $result = [pscustomobject]@{
        gitlab_project = $srcPath
        ado_repository = $repoName
        status = "SUCCESS"
        message = "Migration completed successfully"
        end_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      }
      $results += $result
      $successCount++
      
      Write-Host "    ✅ SUCCESS: $srcPath → $repoName"
      "Status: SUCCESS" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
    } catch {
      $result = [pscustomobject]@{
        gitlab_project = $srcPath
        ado_repository = $repoName
        status = "FAILED"
        message = $_.ToString()
        end_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      }
      $results += $result
      $failureCount++
      
      Write-Host "    ❌ FAILED: $srcPath → $repoName"
      Write-Host "       Error: $_"
      "Status: FAILED" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "Error: $_" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    }
  }
  
  # Create summary report
  $endTime = Get-Date
  $duration = $endTime - $startTime
  $summaryFile = Join-Path $bulkDir "bulk-migration-summary.json"
  
  $summary = [pscustomobject]@{
    destination_project = $DestProject
    migration_start = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    migration_end = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
    duration_minutes = [math]::Round($duration.TotalMinutes, 2)
    total_projects = $migrations.Count
    successful_migrations = $successCount
    failed_migrations = $failureCount
    success_rate = [math]::Round(($successCount / $migrations.Count) * 100, 1)
    results = $results
  }
  
  $summary | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $summaryFile
  
  # Final log entries
  @(
    "=== BULK MIGRATION SUMMARY ==="
    "Bulk migration completed: $endTime"
    "Total duration: $($duration.ToString('hh\:mm\:ss')) ($([math]::Round($duration.TotalMinutes, 2)) minutes)"
    "Total projects: $($migrations.Count)"
    "Successful: $successCount"
    "Failed: $failureCount"
    "Success rate: $([math]::Round(($successCount / $migrations.Count) * 100, 1))%"
    "Summary report: $summaryFile"
    "=== BULK MIGRATION COMPLETED ==="
  ) | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  
  # Display final results
  Write-Host ""
  Write-Host "=== BULK MIGRATION RESULTS ==="
  Write-Host "Total projects: $($migrations.Count)"
  Write-Host "✅ Successful: $successCount"
  Write-Host "❌ Failed: $failureCount"
  Write-Host "Success rate: $([math]::Round(($successCount / $migrations.Count) * 100, 1))%"
  Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
  Write-Host ""
  Write-Host "Reports saved to: $bulkDir"
  Write-Host "  Bulk log: $bulkLogFile"
  Write-Host "  Summary: $summaryFile"
  Write-Host "=========================="
}

function Bulk-Migrate([string]$ConfigFile,[string]$DestProject,[switch]$AllowSync) {
  <#
    Executes bulk migration from a prepared template file.
    Skips projects that failed preparation and validates prerequisites.
    Supports re-running to sync updates from GitLab.
    Usage: Bulk-Migrate "bulk-migration-template.json" "MyDevOpsProject" [-AllowSync]
  #>
  
  if (-not (Test-Path $ConfigFile)) {
    throw "Configuration file not found: $ConfigFile. Please create it first using Option 4 (bulk preparation)."
  }
  
  # Read migration configuration
  $config = Get-Content $ConfigFile | ConvertFrom-Json
  
  # Support both old and new config formats
  $migrations = $null
  if ($config.migrations) {
    # New format: { targetAdoProject, migrations: [ {gitlabProject, adoRepository, preparation_status} ] }
    $migrations = $config.migrations
    if (-not $DestProject -and $config.targetAdoProject) {
      $DestProject = $config.targetAdoProject
    }
    # Filter by preparation status if present, otherwise treat all as ready
    if ($migrations[0].preparation_status) {
      $readyProjects = $migrations | Where-Object { $_.preparation_status -eq "SUCCESS" }
      $failedProjects = $migrations | Where-Object { $_.preparation_status -eq "FAILED" }
    } else {
      # No preparation_status means direct migration (all ready)
      $readyProjects = $migrations
      $failedProjects = @()
    }
  } elseif ($config.projects) {
    # Old format with preparation workflow
    $migrations = $config.projects
    $readyProjects = $migrations | Where-Object { $_.preparation_status -eq "SUCCESS" }
    $failedProjects = $migrations | Where-Object { $_.preparation_status -eq "FAILED" }
  } else {
    throw "Invalid configuration format. Expected 'migrations' or 'projects' array in config file."
  }
  
  if (-not $migrations -or $migrations.Count -eq 0) {
    throw "No migrations found in configuration file."
  }
  
  if ($readyProjects.Count -eq 0) {
    throw "No projects are ready for migration. All projects have failed preparation. Please run Option 4 again."
  }
  
  if ([string]::IsNullOrWhiteSpace($DestProject)) {
    throw "Destination project not specified. Set 'targetAdoProject' in config or provide via menu."
  }
  
  Write-Host "=== BULK MIGRATION STARTING ==="
  Write-Host "Template file: $(Split-Path $ConfigFile -Leaf)"
  Write-Host "Destination Project: $DestProject"
  Write-Host "Total projects in template: $($migrations.Count)"
  Write-Host "✅ Ready for migration: $($readyProjects.Count)"
  if ($failedProjects.Count -gt 0) {
    Write-Host "❌ Skipping failed preparations: $($failedProjects.Count)"
  }
  Write-Host ""
  
  # Ensure destination project exists
  Write-Host "Verifying Azure DevOps project..."
  $proj = Ensure-Project $DestProject
  $projId = $proj.id
  Write-Host "✅ Project verified: $DestProject (ID: $projId)"
  Write-Host ""
  
  # Create bulk migration folder
  $migrationsDir = Join-Path (Get-Location) "Migrations"
  $bulkDir = Join-Path $migrationsDir "bulk-execution-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  New-Item -ItemType Directory -Path $bulkDir -Force | Out-Null
  
  # Create bulk migration log
  $bulkLogFile = Join-Path $bulkDir "bulk-execution.log"
  $startTime = Get-Date
  
  @(
    "=== Azure DevOps Bulk Migration Execution Log ==="
    "Execution started: $startTime"
    "Destination ADO Project: $DestProject (ID: $projId)"
    "Template file: $ConfigFile"
    "Total projects: $($migrations.Count)"
    "Ready for migration: $($readyProjects.Count)"
    "Failed preparations (skipped): $($failedProjects.Count)"
    ""
    "=== Ready Projects List ==="
  ) | Out-File -FilePath $bulkLogFile -Encoding utf8
  
  # Log ready projects
  foreach ($projectConfig in $readyProjects) {
    # Support both old and new property names
    $srcPath = if ($projectConfig.gitlabProject) { $projectConfig.gitlabProject } else { $projectConfig.gitlab_path }
    $repoName = if ($projectConfig.adoRepository) { $projectConfig.adoRepository } 
                elseif ($projectConfig.ado_repo_name) { $projectConfig.ado_repo_name } 
                else { ($srcPath -split '/')[-1] }
    "- $srcPath → $repoName" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  }
  
  if ($failedProjects.Count -gt 0) {
    "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    "=== Skipped Projects (Failed Preparation) ===" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    foreach ($projectConfig in $failedProjects) {
      $srcPath = if ($projectConfig.gitlabProject) { $projectConfig.gitlabProject } else { $projectConfig.gitlab_path }
      $errorMsg = if ($projectConfig.error_message) { $projectConfig.error_message } else { "Unknown preparation error" }
      "- $srcPath (Error: $errorMsg)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    }
  }
  
  "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  
  $results = @()
  $successCount = 0
  $failureCount = 0
  $skippedCount = $failedProjects.Count
  
  # Process each ready project
  for ($i = 0; $i -lt $readyProjects.Count; $i++) {
    $projectConfig = $readyProjects[$i]
    # Support both old and new property names
    $srcPath = if ($projectConfig.gitlabProject) { $projectConfig.gitlabProject } else { $projectConfig.gitlab_path }
    $repoName = if ($projectConfig.adoRepository) { $projectConfig.adoRepository } 
                elseif ($projectConfig.ado_repo_name) { $projectConfig.ado_repo_name } 
                else { ($srcPath -split '/')[-1] }
    $projectNum = $i + 1
    $projectName = ($srcPath -split '/')[-1]
    
    Write-Host "[$projectNum/$($readyProjects.Count)] Migrating: $srcPath → $repoName"
    "=== Project $projectNum/$($readyProjects.Count): $srcPath ===" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    "Start time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    "Target repository: $repoName" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    
    try {
      # Verify project preparation exists
      $projectDir = Join-Path $migrationsDir $projectName
      
      if (-not (Test-Path $projectDir)) {
        throw "Project preparation not found. Expected folder: $projectDir. Please run Option 4 to prepare this project."
      }
      
      $repoDir = Join-Path $projectDir "repository"
      if (-not (Test-Path $repoDir)) {
        throw "Repository not found in preparation. Expected folder: $repoDir. Please run Option 4 again."
      }
      
      Write-Host "    ✅ Using prepared data from: $projectDir"
      "Using prepared data: $projectDir" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
      # Create Azure DevOps repository (or update existing if sync mode)
      Write-Host "    Ensuring repository exists in Azure DevOps..."
      "Ensuring ADO repository: $repoName" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
      $repo = Ensure-Repo $DestProject $projId $repoName -AllowExisting:$AllowSync
      $repoId = $repo.id
      
      if ($AllowSync) {
        Write-Host "    [SYNC MODE] Repository will be updated with latest changes"
        "SYNC MODE: Updating existing repository" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      }
      
      Write-Host "    ✅ Repository created: $repoName (ID: $repoId)"
      
      # Push repository content to Azure DevOps
      Write-Host "    Pushing repository content..."
      "Pushing to ADO repository..." | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
      Push-Repository $repoDir $DestProject $repoName
      
      Write-Host "    ✅ Repository content pushed successfully"
      "Repository push completed" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
      # Get project metadata for final reporting
      $repoSize = if ($projectConfig.repo_size_MB) { $projectConfig.repo_size_MB } else { "Unknown" }
      $lfsSize = if ($projectConfig.lfs_size_MB) { $projectConfig.lfs_size_MB } else { 0 }
      
      $result = [pscustomobject]@{
        gitlab_project = $srcPath
        ado_repository = $repoName
        ado_project = $DestProject
        status = "SUCCESS"
        repo_size_MB = $repoSize
        lfs_size_MB = $lfsSize
        migration_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      }
      $results += $result
      $successCount++
      
      Write-Host "    ✅ MIGRATION COMPLETE: $srcPath → $repoName"
      "Status: SUCCESS" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      
    } catch {
      $result = [pscustomobject]@{
        gitlab_project = $srcPath
        ado_repository = $repoName
        ado_project = $DestProject
        status = "FAILED"
        error_message = $_.ToString()
        migration_time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      }
      $results += $result
      $failureCount++
      
      Write-Host "    ❌ MIGRATION FAILED: $srcPath"
      Write-Host "       Error: $_"
      "Status: FAILED" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "Error: $_" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "End time: $(Get-Date)" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
      "" | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
    }
  }
  
  # Create final migration report
  $endTime = Get-Date
  $duration = $endTime - $startTime
  $reportFile = Join-Path $bulkDir "migration-report.json"
  
  $report = [pscustomobject]@{
    template_file = $ConfigFile
    destination_project = $DestProject
    migration_start = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    migration_end = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
    duration_minutes = [math]::Round($duration.TotalMinutes, 2)
    total_projects = $migrations.Count
    ready_for_migration = $readyProjects.Count
    successful_migrations = $successCount
    failed_migrations = $failureCount
    skipped_preparations = $skippedCount
    success_rate = if ($readyProjects.Count -gt 0) { [math]::Round(($successCount / $readyProjects.Count) * 100, 1) } else { 0 }
    results = $results
  }
  
  $report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $reportFile
  
  # Final log entries
  @(
    "=== BULK MIGRATION SUMMARY ==="
    "Migration completed: $endTime"
    "Total duration: $($duration.ToString('hh\:mm\:ss')) ($([math]::Round($duration.TotalMinutes, 2)) minutes)"
    "Total projects in template: $($migrations.Count)"
    "Ready for migration: $($readyProjects.Count)"
    "Successful migrations: $successCount"
    "Failed migrations: $failureCount"
    "Skipped (failed preparation): $skippedCount"
    "Success rate: $($report.success_rate)%"
    "Report file: $reportFile"
    "=== BULK MIGRATION COMPLETED ==="
  ) | Out-File -FilePath $bulkLogFile -Append -Encoding utf8
  
  # Display final results
  Write-Host ""
  Write-Host "=== BULK MIGRATION RESULTS ==="
  Write-Host "Template: $(Split-Path $ConfigFile -Leaf)"
  Write-Host "Destination: $DestProject"
  Write-Host "Duration: $($duration.ToString('hh\:mm\:ss'))"
  Write-Host ""
  Write-Host "Projects in template: $($migrations.Count)"
  Write-Host "✅ Successful migrations: $successCount"
  Write-Host "❌ Failed migrations: $failureCount"
  Write-Host "⏭️  Skipped (failed prep): $skippedCount"
  Write-Host "Success rate: $($report.success_rate)%"
  Write-Host ""
  Write-Host "Generated files:"
  Write-Host "  📊 Migration report: $reportFile"
  Write-Host "  📝 Execution log: $bulkLogFile"
  Write-Host ""
  if ($successCount -gt 0) {
    Write-Host "✅ Migration completed! Check your Azure DevOps project: $DestProject"
  }
  if ($failureCount -gt 0) {
    Write-Host "⚠️  Some migrations failed. Check the logs for details."
  }
  Write-Host "=================================="
}

function Create-BulkConfig([string]$ConfigFile) {
  # Validate config file path
  if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    Write-Host "[ERROR] Configuration file path cannot be empty."
    return
  }
  
  # Create a sample configuration file
  $sampleConfig = [pscustomobject]@{
    description = "Bulk migration configuration for GitLab to Azure DevOps"
    projects = @(
      [pscustomobject]@{
        gitlab_path = "group1/project1"
        ado_repo_name = "Project1-Repo"
        description = "First project migration"
      },
      [pscustomobject]@{
        gitlab_path = "group2/project2" 
        ado_repo_name = "Project2-Repo"
        description = "Second project migration"
      },
      [pscustomobject]@{
        gitlab_path = "group3/project3"
        # ado_repo_name is optional - will use GitLab project name if not specified
        description = "Third project migration using GitLab project name"
      }
    )
  }
  
  $sampleConfig | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $ConfigFile
  Write-Host "[INFO] Sample configuration created: $ConfigFile"
  Write-Host "[INFO] Edit this file to specify your GitLab projects and desired Azure DevOps repository names."
  Write-Host ""
  Write-Host "Configuration format:"
  Write-Host "  gitlab_path: Path to GitLab project (group/project)"
  Write-Host "  ado_repo_name: Desired repository name in Azure DevOps (optional)"
  Write-Host "  description: Description for documentation (optional)"
}
# --------------- Enhanced menu with proper bulk workflow ---------------
Write-Host "`nSelect action:"
Write-Host "  1) Download & analyze single GitLab project (prepare for migration)"
Write-Host "  2) Create & setup Azure DevOps project with policies"
Write-Host "  3) Migrate single GitLab project to Azure DevOps"
Write-Host "  4) Download & analyze multiple GitLab projects (bulk preparation)"
Write-Host "  5) Review & update bulk migration template"
Write-Host "  6) Execute bulk migration from prepared template"
$choice = Read-Host "Enter 1, 2, 3, 4, 5, or 6"

switch ($choice) {
  '1' { 
    $SourceProjectPath = Read-Host "Enter Source GitLab project path (e.g., group/my-project)"
    Prepare-GitLab $SourceProjectPath 
  }
  '2' { 
    $SourceProjectPath = Read-Host "Enter Source GitLab project path (e.g., group/my-project)"
    $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (e.g., MyProject)"
    $repoName = ($SourceProjectPath -split '/')[-1]
    Init-Project $DestProjectName $repoName 
  }
  '3' { 
    $SourceProjectPath = Read-Host "Enter Source GitLab project path (e.g., group/my-project)"
    $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (e.g., MyProject)"
    $allowSyncInput = Read-Host "Allow sync of existing repository? (Y/N, default: N)"
    $allowSyncFlag = $allowSyncInput -match '^[Yy]'
    if ($allowSyncFlag) {
      Write-Host "[INFO] Sync mode enabled - will update existing repository if it exists"
      Migrate-One $SourceProjectPath $DestProjectName -AllowSync
    } else {
      Migrate-One $SourceProjectPath $DestProjectName
    }
  }
  '4' {
    Write-Host ""
    Write-Host "=== BULK PREPARATION ==="
    Write-Host "This will download and analyze multiple GitLab projects for migration."
    Write-Host ""
    
    # Get destination project name first
    $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (e.g., ConsolidatedProject)"
    if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
      Write-Host "Project name is required."
      break
    }
    
    # Check if preparation already exists
    $migrationsDir = Join-Path (Get-Location) "Migrations"
    $bulkPrepDir = Join-Path $migrationsDir "bulk-prep-$DestProjectName"
    if (Test-Path $bulkPrepDir) {
      Write-Host ""
      Write-Host "⚠️  Existing preparation found for '$DestProjectName'"
      Write-Host "   Folder: $bulkPrepDir"
      $continueChoice = Read-Host "Continue and update existing preparation? (y/N)"
      if ($continueChoice -notmatch '^[Yy]') {
        Write-Host "Bulk preparation cancelled."
        break
      }
    }
    
    Write-Host ""
    Write-Host "Enter GitLab project paths (one per line, empty line to finish):"
    Write-Host "Format: group/project or group/subgroup/project"
    Write-Host "Example: ministry/frontend-portal"
    Write-Host ""
    
    $projectPaths = @()
    $lineNum = 1
    do {
      $projectPath = Read-Host "Project $lineNum"
      if ($projectPath.Trim() -ne "") {
        $projectPaths += $projectPath.Trim()
        $lineNum++
      }
    } while ($projectPath.Trim() -ne "")
    
    if ($projectPaths.Count -eq 0) {
      Write-Host "No projects specified."
      break
    }
    
    # Display summary
    Write-Host ""
    Write-Host "=== PREPARATION SUMMARY ==="
    Write-Host "Destination Project: $DestProjectName"
    Write-Host "Projects to prepare: $($projectPaths.Count)"
    foreach ($path in $projectPaths) {
      Write-Host "  - $path"
    }
    Write-Host ""
    
    # Confirm before proceeding
    $confirm = Read-Host "Proceed with bulk preparation? (y/N)"
    if ($confirm -match '^[Yy]') {
      Bulk-Prepare-GitLab $projectPaths $DestProjectName
    } else {
      Write-Host "Preparation cancelled."
    }
  }
  '5' {
    Write-Host ""
    Write-Host "=== BULK MIGRATION TEMPLATE MANAGER ==="
    
    # Look for existing config files
    $configFiles = @()
    $configFiles += Get-ChildItem -Path "." -Filter "*.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*config*" -or $_.Name -like "*bulk*" }
    $configFiles += Get-ChildItem -Path "Migrations" -Filter "*.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*config*" -or $_.Name -like "*bulk*" } 2>$null
    
    if ($configFiles.Count -gt 0) {
      Write-Host "Found existing configuration files:"
      for ($i = 0; $i -lt $configFiles.Count; $i++) {
        $file = $configFiles[$i]
        $relativePath = if ($file.DirectoryName -eq (Get-Location).Path) { $file.Name } else { Join-Path "Migrations" $file.Name }
        Write-Host "  $($i + 1)) $relativePath"
        
        # Try to show project count from the file
        try {
          $content = Get-Content $file.FullName | ConvertFrom-Json
          if ($content.projects) {
            Write-Host "     - Contains $($content.projects.Count) project(s)"
            if ($content.description) {
              Write-Host "     - $($content.description)"
            }
          }
        } catch {
          Write-Host "     - (Invalid JSON format)"
        }
      }
      Write-Host "  $($configFiles.Count + 1)) Create new configuration file"
      Write-Host "  0) Cancel"
      Write-Host ""
      
      do {
        $choice = Read-Host "Select option (0-$($configFiles.Count + 1))"
        $choiceNum = [int]0
        $validChoice = [int]::TryParse($choice, [ref]$choiceNum)
      } while (-not $validChoice -or $choiceNum -lt 0 -or $choiceNum -gt ($configFiles.Count + 1))
      
      if ($choiceNum -eq 0) {
        Write-Host "Cancelled."
        return
      } elseif ($choiceNum -eq ($configFiles.Count + 1)) {
        # Create new file
        $ConfigFile = Read-Host "Enter path for new config file (e.g., my-bulk-config.json)"
        if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
          Write-Host "[ERROR] Configuration file path cannot be empty."
          return
        }
        Create-BulkConfig $ConfigFile
      } else {
        # Edit existing file
        $selectedFile = $configFiles[$choiceNum - 1]
        Write-Host ""
        Write-Host "Selected: $($selectedFile.FullName)"
        Write-Host ""
        Write-Host "What would you like to do?"
        Write-Host "  1) View file contents"
        Write-Host "  2) Edit file in notepad"
        Write-Host "  3) Use this file for migration (go to Option 6)"
        Write-Host "  4) Create copy with new name"
        Write-Host "  0) Cancel"
        
        $action = Read-Host "Select action (0-4)"
        
        switch ($action) {
          '1' {
            Write-Host ""
            Write-Host "=== FILE CONTENTS ==="
            Get-Content $selectedFile.FullName | Write-Host
            Write-Host "===================="
          }
          '2' {
            Write-Host "Opening file in notepad..."
            Start-Process notepad $selectedFile.FullName -Wait
            Write-Host "File editing completed."
          }
          '3' {
            Write-Host ""
            $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (e.g., ConsolidatedProject)"
            if (-not [string]::IsNullOrWhiteSpace($DestProjectName)) {
              Bulk-Migrate $selectedFile.FullName $DestProjectName
            } else {
              Write-Host "[ERROR] Project name cannot be empty."
            }
          }
          '4' {
            $newName = Read-Host "Enter new filename (e.g., my-copy-config.json)"
            if (-not [string]::IsNullOrWhiteSpace($newName)) {
              Copy-Item $selectedFile.FullName $newName
              Write-Host "[INFO] File copied to: $newName"
            } else {
              Write-Host "[ERROR] Filename cannot be empty."
            }
          }
          '0' {
            Write-Host "Cancelled."
          }
          default {
            Write-Host "Invalid option."
          }
        }
      }
    } else {
      Write-Host "No existing configuration files found."
      Write-Host ""
      $ConfigFile = Read-Host "Enter path for new config file (e.g., bulk-config.json)"
      if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
        Write-Host "[ERROR] Configuration file path cannot be empty."
        return
      }
      Create-BulkConfig $ConfigFile
    }
  }
  '6' {
    Write-Host ""
    Write-Host "=== BULK MIGRATION EXECUTION ==="
    Write-Host "This will execute bulk migration from prepared template files."
    Write-Host ""
    
    # Look for available template files
    $templateFiles = @()
    $bulkPrepDirs = Get-ChildItem -Path "Migrations" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "bulk-prep-*" }
    
    if ($bulkPrepDirs) {
      foreach ($dir in $bulkPrepDirs) {
        $templatePath = Join-Path $dir.FullName "bulk-migration-template.json"
        if (Test-Path $templatePath) {
          $templateFiles += $templatePath
        }
      }
    }
    
    # Also look for any bulk config files in current directory
    $configFiles = Get-ChildItem -Path "." -Filter "*bulk*.json" -ErrorAction SilentlyContinue
    foreach ($file in $configFiles) {
      if ($templateFiles -notcontains $file.FullName) {
        $templateFiles += $file.FullName
      }
    }
    
    if ($templateFiles.Count -eq 0) {
      Write-Host "❌ No bulk migration template files found."
      Write-Host "Please run Option 4 (bulk preparation) first, or create a bulk config file."
      break
    }
    
    # Display available templates
    Write-Host "Available template files:"
    for ($i = 0; $i -lt $templateFiles.Count; $i++) {
      $file = $templateFiles[$i]
      $fileName = Split-Path $file -Leaf
      $folderName = Split-Path (Split-Path $file -Parent) -Leaf
      
      # Extract DevOps project name from folder name (bulk-prep-ProjectName)
      $devopsProjectName = $folderName -replace '^bulk-prep-', ''
      
      # Try to read template info
      try {
        $templateData = Get-Content $file | ConvertFrom-Json
        $projectCount = if ($templateData.projects) { $templateData.projects.Count } else { 0 }
        $successCount = if ($templateData.preparation_summary) { $templateData.preparation_summary.successful_preparations } else { "N/A" }
        $prepTime = if ($templateData.preparation_summary.preparation_time) { $templateData.preparation_summary.preparation_time } else { "Unknown" }
        Write-Host "  [$($i+1)] DevOps Project: $devopsProjectName"
        Write-Host "      Projects: $projectCount total, $successCount successful"
        Write-Host "      Prepared: $prepTime"
      } catch {
        Write-Host "  [$($i+1)] DevOps Project: $devopsProjectName"
        Write-Host "      Unable to read template info"
      }
    }
    Write-Host ""
    
    # Get user selection
    do {
      $selection = Read-Host "Select template file (1-$($templateFiles.Count))"
      $selectionNum = [int]$selection - 1
    } while ($selectionNum -lt 0 -or $selectionNum -ge $templateFiles.Count)
    
    $selectedTemplate = $templateFiles[$selectionNum]
    $selectedFolderName = Split-Path (Split-Path $selectedTemplate -Parent) -Leaf
    $selectedDevOpsProject = $selectedFolderName -replace '^bulk-prep-', ''
    
    Write-Host "Selected: Preparation for '$selectedDevOpsProject'"
    Write-Host ""
    
    # Get destination project name (default to the prepared project name)
    $defaultDestProject = $selectedDevOpsProject
    $DestProjectName = Read-Host "Enter Destination Azure DevOps project name (press Enter for '$defaultDestProject')"
    if ([string]::IsNullOrWhiteSpace($DestProjectName)) {
      $DestProjectName = $defaultDestProject
    }
    
    # Show migration summary
    try {
      $templateData = Get-Content $selectedTemplate | ConvertFrom-Json
      $successfulProjects = $templateData.projects | Where-Object { $_.preparation_status -eq "SUCCESS" }
      $failedProjects = $templateData.projects | Where-Object { $_.preparation_status -eq "FAILED" }
      
      Write-Host "=== MIGRATION PREVIEW ==="
      Write-Host "Prepared for: $selectedDevOpsProject"
      Write-Host "Destination project: $DestProjectName"
      Write-Host "Total projects in template: $($templateData.projects.Count)"
      Write-Host "✅ Ready for migration: $($successfulProjects.Count)"
      if ($failedProjects.Count -gt 0) {
        Write-Host "❌ Failed preparation (will be skipped): $($failedProjects.Count)"
      }
      Write-Host ""
      
      if ($successfulProjects.Count -eq 0) {
        Write-Host "❌ No projects are ready for migration. Please check the template file."
        break
      }
      
      Write-Host "Projects to migrate:"
      foreach ($proj in $successfulProjects) {
        Write-Host "  $($proj.gitlab_path) → $($proj.ado_repo_name)"
      }
      Write-Host ""
      
    } catch {
      Write-Host "❌ Error reading template file: $_"
      break
    }
    
    # Ask about sync mode
    $allowSyncInput = Read-Host "Allow sync of existing repositories? (Y/N, default: N)"
    $allowSyncFlag = $allowSyncInput -match '^[Yy]'
    
    if ($allowSyncFlag) {
      Write-Host "[INFO] Sync mode enabled - existing repositories will be updated"
    }
    
    # Final confirmation
    $confirm = Read-Host "Proceed with bulk migration? (y/N)"
    if ($confirm -match '^[Yy]') {
      if ($allowSyncFlag) {
        Bulk-Migrate $selectedTemplate $DestProjectName -AllowSync
      } else {
        Bulk-Migrate $selectedTemplate $DestProjectName
      }
    } else {
      Write-Host "Migration cancelled."
    }
  }
  default { Write-Host "Invalid choice." }
}
