
<#
Azure DevOps Server 2022 inventory (on-prem, collection URL).

Outputs 5 CSV files:
- projects.csv
- repositories.csv
- project-users.csv
- project-permissions.csv
- git-policies.csv
#>

[CmdletBinding()]
param(
    [string]$CollectionUrl,

    # PAT with: Project & Team, Code, Security, Identity, Policy
    [string]$Pat,

    [string]$EnvPath   = ".\.env",
    [string]$OutputFolder     = ".\ado-inventory",
    [int]$ProjectsPageSize    = 50,
    [string]$ApiVersion       = "7.0"   # Azure DevOps Server 2022 supports up to 7.0 
)

$ErrorActionPreference = 'Stop'
Write-Host "[INFO] Loading environment from '$EnvPath'..." -ForegroundColor Cyan

$envVars = @{}
Get-Content $EnvPath |
    Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') } |
    ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) {
            $key   = $parts[0].Trim()
            $value = $parts[1].Trim()
            if ($key) { $envVars[$key] = $value }
        }
    }

if (-not $envVars.ADO_COLLECTION_URL) {
    throw "ADO_COLLECTION_URL missing in .env."
}
if (-not $envVars.ADO_PAT) {
    throw "ADO_PAT missing in .env."
}

$CollectionUrl = $envVars.ADO_COLLECTION_URL.TrimEnd('/')
$Pat           = $envVars.ADO_PAT

Write-Host "[INFO] ADO_COLLECTION_URL = $CollectionUrl" -ForegroundColor Green

if (-not (Test-Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory | Out-Null
}

# ------------ Auth header ------------
$base64Auth = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":$Pat")
)
$global:ADOHeaders = @{
    Authorization = "Basic $base64Auth"
}

# ------------ Generic REST wrapper ------------
function Invoke-AdoRestJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','PATCH','DELETE')]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Uri,
        [object]$Body = $null,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    do {
        $attempt++
        try {
            Write-Verbose "[REST] $Method $Uri (attempt $attempt)"

            $params = @{
                Method      = $Method
                Uri         = $Uri
                Headers     = $global:ADOHeaders
                TimeoutSec  = 120
            }

            if ($null -ne $Body) {
                $params.Body        = ($Body | ConvertTo-Json -Depth 10)
                $params.ContentType = "application/json"
            }

            return Invoke-RestMethod @params
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }
            Write-Warning "[WARN] $Method $Uri failed (attempt $attempt, status $statusCode): $($_.Exception.Message)"

            # For 4xx except 429, do not hammer the server
            if ($attempt -ge $MaxRetries -or (($statusCode -ge 400 -and $statusCode -lt 500) -and $statusCode -ne 429)) {
                throw
            }

            Start-Sleep -Seconds (2 * $attempt)
        }
    } while ($true)
}

# ------------ Tech detection from repo root items ------------
function Get-TechnologiesFromItems {
    param(
        [Parameter(Mandatory)]
        [array]$Items
    )

    # HashSet works fine on PowerShell 5/7, we enumerate it (no ToArray)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in $Items) {
        if (-not $item.path) { continue }
        $fileName = [System.IO.Path]::GetFileName([string]$item.path)

        switch -Regex ($fileName) {
            '\.csproj$'              { $set.Add("C#")        | Out-Null; $set.Add(".NET")           | Out-Null }
            '\.sln$'                 { $set.Add(".NET")      | Out-Null }
            '\.vbproj$'              { $set.Add("VB.NET")    | Out-Null; $set.Add(".NET")           | Out-Null }
            '\.fsproj$'              { $set.Add("F#")        | Out-Null; $set.Add(".NET")           | Out-Null }
            '\.cs$'                  { $set.Add("C#")        | Out-Null }
            'global\.json$'          { $set.Add(".NET")      | Out-Null }
            'appsettings\.json$'     { $set.Add(".NET")      | Out-Null }
            'web\.config$'           { $set.Add("ASP.NET")   | Out-Null }

            'package\.json$'         { $set.Add("Node.js")   | Out-Null; $set.Add("JavaScript")     | Out-Null }
            '\.ts$'                  { $set.Add("TypeScript")| Out-Null }
            '\.js$'                  { $set.Add("JavaScript")| Out-Null }
            'angular\.json$'         { $set.Add("Angular")   | Out-Null }

            'pom\.xml$'              { $set.Add("Java")      | Out-Null; $set.Add("Maven")          | Out-Null }
            '\.java$'                { $set.Add("Java")      | Out-Null }

            'requirements\.txt$'     { $set.Add("Python")    | Out-Null }
            '\.py$'                  { $set.Add("Python")    | Out-Null }

            '\.sql$'                 { $set.Add("SQL")       | Out-Null }

            'Dockerfile$'            { $set.Add("Docker")           | Out-Null }
            'docker-compose\.'       { $set.Add("Docker Compose")   | Out-Null }

            'azure-pipelines\.ya?ml$'{ $set.Add("Azure Pipelines") | Out-Null }

            '\.bicep$'               { $set.Add("Bicep")            | Out-Null }
            '\.tf$'                  { $set.Add("Terraform")        | Out-Null }

            '\.php$'                 { $set.Add("PHP")              | Out-Null }
            '\.go$'                  { $set.Add("Go")               | Out-Null }
            '\.rb$'                  { $set.Add("Ruby")             | Out-Null }
        }
    }

    return $set
}

# ------------ Identity helpers (server-compatible pattern) ------------
# Azure DevOps Server exposes Identities at {collection}/_apis/identities with api-version up to 7.0. 

$descriptorCache      = @{}  # descriptor -> identity
$groupMembershipCache = @{}  # groupId   -> member identities

function Get-IdentitiesByDescriptor {
    param(
        [Parameter(Mandatory)]
        [string[]]$Descriptors
    )

    $toLookup = $Descriptors | Where-Object { -not $descriptorCache.ContainsKey($_) }
    if (-not $toLookup -or $toLookup.Count -eq 0) { return }

    $chunkSize = 40
    for ($i = 0; $i -lt $toLookup.Count; $i += $chunkSize) {
        $chunk = $toLookup[$i..([Math]::Min($i + $chunkSize - 1, $toLookup.Count - 1))]
        $uri   = "$CollectionUrl/_apis/identities?descriptors=$([string]::Join(',', $chunk))&queryMembership=none&api-version=$ApiVersion"
        $resp  = Invoke-AdoRestJson -Method GET -Uri $uri
        foreach ($id in $resp.value) {
            $descriptorCache[$id.descriptor] = $id
        }
    }
}

function Get-GroupMembers {
    param(
        [Parameter(Mandatory)]
        $GroupIdentity  # identity from identities API
    )

    $groupId = [string]$GroupIdentity.id
    if ($groupMembershipCache.ContainsKey($groupId)) {
        return $groupMembershipCache[$groupId]
    }

    $uri  = "$CollectionUrl/_apis/identities?identityIds=$groupId&queryMembership=expanded&api-version=$ApiVersion"
    $resp = Invoke-AdoRestJson -Method GET -Uri $uri
    if (-not $resp.value -or -not $resp.value[0].members) {
        $groupMembershipCache[$groupId] = @()
        return @()
    }

    $memberDescriptors = @($resp.value[0].members)
    if ($memberDescriptors.Count -eq 0) {
        $groupMembershipCache[$groupId] = @()
        return @()
    }

    Get-IdentitiesByDescriptor -Descriptors $memberDescriptors
    $members = @()
    foreach ($d in $memberDescriptors) {
        if ($descriptorCache.ContainsKey($d)) {
            $members += $descriptorCache[$d]
        }
    }

    $groupMembershipCache[$groupId] = $members
    return $members
}

function Add-UserToProjectMap {
    param(
        [hashtable]$UserMap,
        [Parameter(Mandatory)]$Identity,
        [string]$SourceType,
        [string]$SourceName,
        [bool]$IsTeamAdmin = $false
    )

    if (-not $Identity) { return }
    $id = [string]$Identity.id
    if (-not $id) { return }

    if (-not $UserMap.ContainsKey($id)) {
        $UserMap[$id] = @{
            Id          = $id
            DisplayName = $Identity.displayName
            UniqueName  = $Identity.uniqueName
            Descriptor  = $Identity.descriptor
            SubjectKind = $Identity.subjectKind
            Teams       = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            Groups      = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            IsTeamAdmin = $false
            Sources     = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        }
    }

    $entry = $UserMap[$id]
    switch ($SourceType) {
        'Team'  { $entry.Teams.Add($SourceName)  | Out-Null }
        'Group' { $entry.Groups.Add($SourceName) | Out-Null }
    }
    if ($IsTeamAdmin) { $entry.IsTeamAdmin = $true }
    if ($SourceName)  { $entry.Sources.Add("$($SourceType):$SourceName") | Out-Null }
}

# ------------ Data containers ------------
$projectRows = New-Object System.Collections.Generic.List[object]
$repoRows    = New-Object System.Collections.Generic.List[object]
$userRows    = New-Object System.Collections.Generic.List[object]
$permRows    = New-Object System.Collections.Generic.List[object]
$policyRows  = New-Object System.Collections.Generic.List[object]

$repoIdNameMap = @{}  # repoId -> repoName

# ------------ Fetch all projects (paged) ------------
Write-Host "=== Fetching projects from $CollectionUrl (Server 2022, api-version=$ApiVersion) ==="

$allProjects = @()
$skip        = 0
do {
    $uri  = "$CollectionUrl/_apis/projects?`$top=$ProjectsPageSize&`$skip=$skip&stateFilter=All&includeCapabilities=true&api-version=$ApiVersion"
    $resp = Invoke-AdoRestJson -Method GET -Uri $uri
    if ($resp.value) {
        $allProjects += $resp.value
        $count = $resp.value.Count
        $skip += $count
        Write-Host "  Retrieved $count projects (total so far: $($allProjects.Count))"
    } else {
        $count = 0
    }
} while ($count -eq $ProjectsPageSize)

Write-Host "=== Total projects found: $($allProjects.Count) ==="

# Project security namespace id (project-level permissions). 
$projectSecurityNamespaceId = "52d39943-cb85-4d7f-8fa8-c6baac873819"

# ------------ Per-project loop ------------
foreach ($proj in $allProjects) {
    Write-Host ""
    Write-Host ">>> Project: $($proj.name)  [Id: $($proj.id)]"

    # Detailed project: capabilities include processTemplate + versioncontrol. 
    $projDetailUri = "$CollectionUrl/_apis/projects/$($proj.id)?includeCapabilities=true&includeHistory=true&api-version=$ApiVersion"
    $projDetail    = Invoke-AdoRestJson -Method GET -Uri $projDetailUri

    $processTemplateName = $null
    $processTemplateId   = $null
    $sourceControlType   = $null

    if ($projDetail.capabilities) {
        if ($projDetail.capabilities.processTemplate) {
            $processTemplateName = $projDetail.capabilities.processTemplate.templateName
            $processTemplateId   = $projDetail.capabilities.processTemplate.templateTypeId
        }
        if ($projDetail.capabilities.versioncontrol) {
            $sourceControlType = $projDetail.capabilities.versioncontrol.sourceControlType
        }
    }

    # -------- Teams & members (users per project) --------
    $userMap = @{}

    try {
        $teamsUri = "$CollectionUrl/_apis/projects/$($proj.id)/teams?api-version=$ApiVersion"
        $teams    = Invoke-AdoRestJson -Method GET -Uri $teamsUri
    }
    catch {
        Write-Warning "[WARN] Failed to list teams for $($proj.name): $($_.Exception.Message)"
        $teams = @{ value = @() }
    }

    foreach ($team in $teams.value) {
        $teamMembersUri = "$CollectionUrl/_apis/projects/$($proj.id)/teams/$($team.id)/members?api-version=$ApiVersion"
        try {
            $members = Invoke-AdoRestJson -Method GET -Uri $teamMembersUri
        }
        catch {
            Write-Warning "[WARN] Failed to list team members for team '$($team.name)' in project '$($proj.name)': $($_.Exception.Message)"
            continue
        }

        foreach ($m in $members.value) {
            $identity = $m.identity
            $isAdmin  = $false
            if ($m.PSObject.Properties.Name -contains 'isTeamAdmin') {
                $isAdmin = [bool]$m.isTeamAdmin
            }
            Add-UserToProjectMap -UserMap $userMap -Identity $identity -SourceType 'Team' -SourceName $team.name -IsTeamAdmin:$isAdmin
        }
    }

    # -------- Project-level ACLs (permissions) --------
    # Uses AccessControlLists API with project security namespace. 
    $acl = $null
    try {
        $aclUri  = "$CollectionUrl/_apis/accesscontrollists/$projectSecurityNamespaceId?token=$($proj.id)&includeExtendedInfo=true&recurse=false&api-version=$ApiVersion"
        $aclResp = Invoke-AdoRestJson -Method GET -Uri $aclUri
        if ($aclResp.value -and $aclResp.value.Count -gt 0) {
            $acl = $aclResp.value[0]
        }
    }
    catch {
        Write-Warning "[WARN] Failed to read project ACL for $($proj.name): $($_.Exception.Message)"
    }

    if ($acl -and $acl.acesDictionary) {
        $aceEntries = $acl.acesDictionary.GetEnumerator()
        $descList   = @($aceEntries | ForEach-Object { $_.Key })
        Get-IdentitiesByDescriptor -Descriptors $descList

        foreach ($entry in $aceEntries) {
            $descriptor = $entry.Key
            $ace        = $entry.Value
            if (-not $descriptorCache.ContainsKey($descriptor)) { continue }
            $identity   = $descriptorCache[$descriptor]

            $allow = [int64]$ace.allow
            $deny  = [int64]$ace.deny

            # Decode core bits for business-relevant permissions. 
            $canView       = [bool]($allow -band 1)      # View project-level info
            $canEdit       = [bool]($allow -band 2)      # Edit project-level info
            $canDeleteProj = [bool]($allow -band 4)      # Delete team project
            $canAdminBuild = [bool]($allow -band 16)     # Administer build
            $canDeleteWI   = [bool]($allow -band 8192)   # Delete work items

            $permRows.Add([PSCustomObject]@{
                ProjectId             = $proj.id
                ProjectName           = $proj.name
                IdentityDisplayName   = $identity.displayName
                IdentityUniqueName    = $identity.uniqueName
                IdentityDescriptor    = $identity.descriptor
                SubjectKind           = $identity.subjectKind
                AllowMask             = $allow
                DenyMask              = $deny
                CanViewProject        = $canView
                CanEditProject        = $canEdit
                CanDeleteProject      = $canDeleteProj
                CanAdministerBuild    = $canAdminBuild
                CanDeleteWorkItems    = $canDeleteWI
            })

            if ($identity.subjectKind -eq 'user') {
                Add-UserToProjectMap -UserMap $userMap -Identity $identity -SourceType 'ACL' -SourceName 'Project-level'
            }
            elseif ($identity.subjectKind -eq 'group' -and $identity.displayName) {
                if ($identity.displayName -like "*Project Administrators*" -or
                    $identity.displayName -like "*Project Contributors*"   -or
                    $identity.displayName -like "*Project Readers*") {

                    try {
                        $members = Get-GroupMembers -GroupIdentity $identity
                        foreach ($mem in $members) {
                            if ($mem.subjectKind -eq 'user') {
                                Add-UserToProjectMap -UserMap $userMap -Identity $mem -SourceType 'Group' -SourceName $identity.displayName
                            }
                        }
                    }
                    catch {
                        Write-Warning "[WARN] Failed to expand group '$($identity.displayName)' in project '$($proj.name)': $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    # Important limitation: Identity REST API cannot expand some external AAD/AD groups, so you will not see every individual in those groups via REST alone. 

    # -------- Repositories + tech --------
    # Git APIs are valid on Server 2022; items endpoint works with 7.0. 

    $projectTechSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $repos = @()
    try {
        $reposUri  = "$CollectionUrl/$($proj.name)/_apis/git/repositories?api-version=$ApiVersion"
        $reposResp = Invoke-AdoRestJson -Method GET -Uri $reposUri
        if ($reposResp.value) { $repos = $reposResp.value }
    }
    catch {
        Write-Warning "[WARN] Failed to list repos for project '$($proj.name)': $($_.Exception.Message)"
    }

    foreach ($repo in $repos) {
        $repoId   = $repo.id
        $repoName = $repo.name
        $repoIdNameMap[$repoId] = $repoName

        $techList = @()
        try {
            $itemsUri = "$CollectionUrl/$($proj.name)/_apis/git/repositories/$repoId/items?path=/&recursionLevel=OneLevel&includeContentMetadata=true&api-version=$ApiVersion"
            $items    = Invoke-AdoRestJson -Method GET -Uri $itemsUri
            if ($items.value) {
                $techSet = Get-TechnologiesFromItems -Items $items.value
                foreach ($t in $techSet) {
                    $projectTechSet.Add($t) | Out-Null
                }
                $techList = $techSet | Sort-Object
            }
        }
        catch {
            Write-Warning "[WARN] Failed to inspect repo '$repoName' in project '$($proj.name)': $($_.Exception.Message)"
        }

        $repoRows.Add([PSCustomObject]@{
            ProjectId          = $proj.id
            ProjectName        = $proj.name
            RepoId             = $repoId
            RepoName           = $repoName
            DefaultBranch      = $repo.defaultBranch
            RemoteUrl          = $repo.remoteUrl
            Size               = $repo.size
            IsDisabled         = $repo.isDisabled
            Technologies       = ($techList -join '; ')
        })
    }

    # -------- Git / code policies (project level) --------
    # Uses policy/configurations, which is supported for branch policies in Server and Services. 
    try {
        $polUri  = "$CollectionUrl/$($proj.name)/_apis/policy/configurations?api-version=$ApiVersion"
        $polResp = Invoke-AdoRestJson -Method GET -Uri $polUri
        foreach ($cfg in $polResp.value) {
            $policyType = $cfg.type.displayName
            $isEnabled  = [bool]$cfg.isEnabled
            $isBlocking = [bool]$cfg.isBlocking

            $scopes = $cfg.settings.scope
            if (-not $scopes) {
                $policyRows.Add([PSCustomObject]@{
                    ProjectId       = $proj.id
                    ProjectName     = $proj.name
                    PolicyId        = $cfg.id
                    PolicyType      = $policyType
                    IsEnabled       = $isEnabled
                    IsBlocking      = $isBlocking
                    RepositoryId    = $null
                    RepositoryName  = $null
                    RefName         = $null
                    MatchKind       = $null
                })
            } else {
                foreach ($s in $scopes) {
                    $repoIdScope = $s.repositoryId
                    $refName     = $s.refName
                    $matchKind   = $s.matchKind

                    $repoNameScope = $null
                    if ($repoIdScope -and $repoIdNameMap.ContainsKey($repoIdScope)) {
                        $repoNameScope = $repoIdNameMap[$repoIdScope]
                    }

                    $policyRows.Add([PSCustomObject]@{
                        ProjectId       = $proj.id
                        ProjectName     = $proj.name
                        PolicyId        = $cfg.id
                        PolicyType      = $policyType
                        IsEnabled       = $isEnabled
                        IsBlocking      = $isBlocking
                        RepositoryId    = $repoIdScope
                        RepositoryName  = $repoNameScope
                        RefName         = $refName
                        MatchKind       = $matchKind
                    })
                }
            }
        }
    }
    catch {
        Write-Warning "[WARN] Failed to read policies for project '$($proj.name)': $($_.Exception.Message)"
    }

    # -------- Project summary row --------
    $projectRows.Add([PSCustomObject]@{
        ProjectId           = $proj.id
        ProjectName         = $proj.name
        Description         = $proj.description
        State               = $proj.state
        LastUpdateTime      = $projDetail.lastUpdateTime
        Visibility          = $proj.visibility
        DefaultTeamName     = $projDetail.defaultTeam.name
        ProcessTemplateName = $processTemplateName
        ProcessTemplateId   = $processTemplateId
        SourceControlType   = $sourceControlType
        NumberOfTeams       = ($teams.value | Measure-Object).Count
        NumberOfRepos       = ($repos       | Measure-Object).Count
        Technologies        = (($projectTechSet | Sort-Object) -join '; ')
    })

    # -------- Project user rows --------
    foreach ($entry in $userMap.Values) {
        $userRows.Add([PSCustomObject]@{
            ProjectId        = $proj.id
            ProjectName      = $proj.name
            UserId           = $entry.Id
            UserDisplayName  = $entry.DisplayName
            UserUniqueName   = $entry.UniqueName
            Descriptor       = $entry.Descriptor
            SubjectKind      = $entry.SubjectKind
            Teams            = (($entry.Teams   | Sort-Object) -join '; ')
            Groups           = (($entry.Groups  | Sort-Object) -join '; ')
            IsTeamAdmin      = $entry.IsTeamAdmin
            Sources          = (($entry.Sources | Sort-Object) -join '; ')
        })
    }

    Start-Sleep -Milliseconds 200
}

# ------------ Write CSVs ------------
Write-Host ""
Write-Host "=== Writing CSV files to $OutputFolder ==="

$projectsCsvPath = Join-Path $OutputFolder "projects.csv"
$reposCsvPath    = Join-Path $OutputFolder "repositories.csv"
$usersCsvPath    = Join-Path $OutputFolder "project-users.csv"
$permsCsvPath    = Join-Path $OutputFolder "project-permissions.csv"
$policiesCsvPath = Join-Path $OutputFolder "git-policies.csv"

$projectRows | Export-Csv -Path $projectsCsvPath -NoTypeInformation -Encoding UTF8
$repoRows    | Export-Csv -Path $reposCsvPath    -NoTypeInformation -Encoding UTF8
$userRows    | Export-Csv -Path $usersCsvPath    -NoTypeInformation -Encoding UTF8
$permRows    | Export-Csv -Path $permsCsvPath    -NoTypeInformation -Encoding UTF8
$policyRows  | Export-Csv -Path $policiesCsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Done."
Write-Host "  Projects:           $projectsCsvPath"
Write-Host "  Repositories:       $reposCsvPath"
Write-Host "  Project users:      $usersCsvPath"
Write-Host "  Project permissions:$permsCsvPath"
Write-Host "  Git policies:       $policiesCsvPath"
