<#
.SYNOPSIS
    Idempotently provision AD OUs/groups and wire them into Azure DevOps Server using GitLab export JSON.

.DESCRIPTION
    Reads a configuration file (config-ado-ad.json) plus users.json, project-memberships.json, and projects.json.
    - Verifies environment (domain joined, ActiveDirectory module, optional domain controller).
    - Creates OU structure and AD security groups for global/collection/project roles.
    - Resolves GitLab memberships to normalized roles and AD accounts.
    - Adds users to AD groups.
    - Maps AD groups into Azure DevOps Server project security groups.

.NOTES
    Module entrypoints:
      * Invoke-GitLabIdentityToAdoImport
      * Initialize-GitLabIdentityImport (compat alias)
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve repository root (modules/Migration -> modules -> repo root)
$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$script:Report = $null
$script:DryRunEffective = $false
$script:AdoRestReady = $false

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[$ts][$Level]"
    switch ($Level) {
        'ERROR' { Write-Host "$prefix $Message" -ForegroundColor Red }
        'WARN'  { Write-Host "$prefix $Message" -ForegroundColor Yellow }
        'DEBUG' { Write-Host "$prefix $Message" -ForegroundColor Gray }
        default { Write-Host "$prefix $Message" -ForegroundColor Cyan }
    }
}

function Get-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$DryRunSwitch
    )

    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }
    $configDir = Split-Path -Parent (Resolve-Path $Path)
    $config = Get-Content -Raw $Path | ConvertFrom-Json

    $requiredKeys = 'ad','azureDevOps','roleMapping','projectMapping','userMapping','inputFiles'
    foreach ($key in $requiredKeys) {
        if (-not $config.PSObject.Properties.Name -contains $key) {
            throw "Configuration missing required key: $key"
        }
    }

    # Validate OU DNs
    $dnPattern = '^(?i)((CN|OU)=[^,]+,)*((DC)=[^,]+,)*(DC)=[^,]+$'
    foreach ($ou in $config.ad.ouDefinitions) {
        foreach ($field in @('distinguishedName','parentDn')) {
            $value = $ou.$field
            if (-not $value -or $value -notmatch $dnPattern) {
                throw "Invalid OU DN in ad.ouDefinitions $($field): $value"
            }
        }
    }
    if ($config.ad.projectOuTemplate -notmatch $dnPattern -and -not $config.ad.projectOuTemplate.Contains('{ProjectKey}')) {
        throw "Invalid ad.projectOuTemplate: $($config.ad.projectOuTemplate)"
    }

    # Validate role mapping targets exist
    $roleKeys = @($config.ad.projectRoleKeys)
    foreach ($rm in $config.roleMapping.sourceRolesToNormalizedRoles) {
        if (-not $roleKeys -or ($roleKeys -notcontains $rm.normalizedRole)) {
            throw "roleMapping.normalizedRole '$($rm.normalizedRole)' not defined in ad.projectRoleKeys"
        }
    }

    # Resolve input files
    $inputFiles = @{}
    foreach ($name in @('users','gitlabProjectMemberships','adoProjectMappings')) {
        $relPath = $config.inputFiles.$name
        if (-not $relPath) { throw "inputFiles.$name is missing in config" }
        $fullPath = if (Test-Path $relPath) { Resolve-Path $relPath } else { Resolve-Path (Join-Path $configDir $relPath) }
        if (-not $fullPath) { throw "Input file not found for ${name}: ${relPath} (resolved from $configDir)" }
        $inputFiles[$name] = $fullPath
    }

    $users = Get-Content -Raw $inputFiles['users'] | ConvertFrom-Json
    $projectMemberships = Get-Content -Raw $inputFiles['gitlabProjectMemberships'] | ConvertFrom-Json
    $projectMappings = Get-Content -Raw $inputFiles['adoProjectMappings'] | ConvertFrom-Json

    # Respect default dry-run setting
    $script:DryRunEffective = if ($DryRunSwitch.IsPresent) { $true } elseif ($PSBoundParameters.ContainsKey('DryRunSwitch')) { $DryRunSwitch.IsPresent } else { [bool]$config.safety.dryRunDefault }
    Write-Log "DryRun effective: $($script:DryRunEffective)" 'INFO'

    return [pscustomobject]@{
        Config = $config
        Users = $users
        ProjectMemberships = $projectMemberships
        ProjectMappings = $projectMappings
        ConfigDir = $configDir
    }
}

function Test-Environment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [switch]$SkipAdOperations
    )

    if ($SkipAdOperations) {
        Write-Log "Skipping AD environment validation (SkipAdOperations set)." 'INFO'
        return
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module is not available. Install RSAT-AD-PowerShell."
    }

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if (-not $cs.PartOfDomain) {
        throw "Host is not domain-joined. Join the domain before running."
    }

    if ($Config.safety.requireDomainController -eq $true) {
        $role = [int]$cs.DomainRole
        if ($role -notin @(4,5)) {
            throw "requireDomainController is true and this host is not a domain controller (DomainRole=$role)."
        }
    }
    Write-Log "Environment validation passed. Domain: $($cs.Domain)" 'INFO'
}

function Get-ProjectMaps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][array]$ProjectMappings
    )

    $adoKeyField = $Config.projectMapping.adoProjectKeyField
    $gitlabField = $Config.projectMapping.gitlabProjectListField

    $projects = @{}
    $paths = @{}

    function ConvertTo-ProjectKey([string]$Value) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        $key = $Value -replace '[^A-Za-z0-9]', '_'
        return $key.Trim('_').ToUpper()
    }

    foreach ($entry in $ProjectMappings) {
        $adoProject = $entry.$adoKeyField
        if (-not $adoProject) { continue }
        $projectKey = $null

        $explicit = $Config.projectMapping.explicitProjects | Where-Object { $_.adoProjectKey -eq $adoProject } | Select-Object -First 1
        if ($explicit -and $explicit.projectKey) {
            $projectKey = $explicit.projectKey
        } else {
            $projectKey = ConvertTo-ProjectKey $adoProject
        }

        $projInfo = [pscustomobject]@{
            AdoProjectName = $adoProject
            ProjectKey     = $projectKey
            GitLabPaths    = @($entry.$gitlabField)
            Overrides      = $explicit
        }
        $projects[$projectKey] = $projInfo

        foreach ($p in $projInfo.GitLabPaths) {
            if ($p) {
                $paths[$p.ToLower()] = $projInfo
            }
        }

        if ($explicit) {
            foreach ($ns in $explicit.gitlabNamespaces) {
                $paths[$ns.ToLower()] = $projInfo
            }
        }
    }

    return [pscustomobject]@{
        ProjectsByKey = $projects
        ProjectsByPath = $paths
    }
}

function Ensure-OUs {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][hashtable]$ProjectsByKey
    )

    foreach ($ou in $Config.ad.ouDefinitions) {
        $existing = Get-ADOrganizationalUnit -Identity $ou.distinguishedName -ErrorAction SilentlyContinue
        if (-not $existing) {
            $msg = "Create OU $($ou.distinguishedName)"
            if ($script:DryRunEffective) {
                Write-Log "[DryRun] $msg" 'INFO'
            } elseif ($PSCmdlet.ShouldProcess($ou.distinguishedName, 'Create OU')) {
                New-ADOrganizationalUnit -Name $ou.name -Path $ou.parentDn -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop | Out-Null
                $script:Report.CreatedOUs += $ou.distinguishedName
                Write-Log $msg 'INFO'
            }
        } else {
            Write-Log "OU exists: $($ou.distinguishedName)" 'DEBUG'
        }
    }

    foreach ($proj in $ProjectsByKey.Values) {
        $projectOu = $Config.ad.projectOuTemplate -replace '\{ProjectKey\}', $proj.ProjectKey
        $existingProjOu = Get-ADOrganizationalUnit -Identity $projectOu -ErrorAction SilentlyContinue
        if (-not $existingProjOu) {
            $msg = "Create project OU $projectOu"
            if ($script:DryRunEffective) {
                Write-Log "[DryRun] $msg" 'INFO'
            } elseif ($PSCmdlet.ShouldProcess($projectOu, 'Create Project OU')) {
                $namePart = ($projectOu -split ',', 2)[0] -replace '^OU=', ''
                $parentDn = ($projectOu -split ',', 2)[1]
                New-ADOrganizationalUnit -Name $namePart -Path $parentDn -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop | Out-Null
                $script:Report.CreatedOUs += $projectOu
                Write-Log $msg 'INFO'
            }
        } else {
            Write-Log "Project OU exists: $projectOu" 'DEBUG'
        }
    }
}

function Ensure-AdGroup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Name,
        [string]$Path
    )

    $existing = Get-ADGroup -Filter "SamAccountName -eq '$Name'" -ErrorAction SilentlyContinue
    if ($existing) { return $existing }

    $msg = "Create AD group $Name in $Path"
    if ($script:DryRunEffective) {
        Write-Log "[DryRun] $msg" 'INFO'
        return $null
    }
    if ($PSCmdlet.ShouldProcess($Name, 'Create AD Group')) {
        $grp = New-ADGroup -Name $Name `
            -SamAccountName $Name `
            -GroupCategory Security `
            -GroupScope Global `
            -DisplayName $Name `
            -Path $Path `
            -ErrorAction Stop
        $script:Report.CreatedGroups += $Name
        Write-Log $msg 'INFO'
        return $grp
    }
    return $null
}

function Ensure-GlobalGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Config)

    foreach ($grp in $Config.ad.globalRoleGroups) {
        Ensure-AdGroup -Name $grp.groupName -Path $grp.ouDn | Out-Null
    }
}

function Ensure-CollectionGroups {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Config)

    foreach ($grp in $Config.ad.collectionRoleGroups) {
        Ensure-AdGroup -Name $grp.groupName -Path $grp.ouDn | Out-Null
    }
}

function Ensure-ProjectGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][hashtable]$ProjectsByKey
    )

    $fmt = $Config.ad.groupNaming.projectGroupNameFormat
    foreach ($proj in $ProjectsByKey.Values) {
        $projectOu = $Config.ad.projectOuTemplate -replace '\{ProjectKey\}', $proj.ProjectKey
        foreach ($role in $Config.ad.projectRoleKeys) {
            $name = ($fmt -replace '\{ProjectKey\}', $proj.ProjectKey) -replace '\{RoleKey\}', $role
            Ensure-AdGroup -Name $name -Path $projectOu | Out-Null
        }
    }
}

function Get-NormalizedRole {
    param(
        [string]$AccessLevel,
        [pscustomobject]$Config,
        [pscustomobject]$ProjectOverride
    )

    $access = $AccessLevel.ToLower()
    $roleMap = if ($ProjectOverride -and $ProjectOverride.overrideRoleMapping) { $ProjectOverride.overrideRoleMapping.sourceRolesToNormalizedRoles } else { $Config.roleMapping.sourceRolesToNormalizedRoles }
    foreach ($entry in $roleMap) {
        foreach ($src in $entry.sourceRoles) {
            if ($src.ToLower() -eq $access) { return $entry.normalizedRole }
        }
    }
    return $null
}

function Get-UserIdentityCandidates {
    param(
        [pscustomobject]$Member,
        [array]$Users,
        [pscustomobject]$UserMapping
    )

    $manual = $UserMapping.manualOverrides | Where-Object { $_.gitlabUsername -eq $Member.username } | Select-Object -First 1
    $user = $Users | Where-Object { $_.username -eq $Member.username } | Select-Object -First 1

    $ids = [ordered]@{}
    if ($manual) {
        if ($manual.samAccountName) { $ids['samAccountName'] = $manual.samAccountName }
        if ($manual.userPrincipalName) { $ids['userPrincipalName'] = $manual.userPrincipalName }
        if ($manual.mail) { $ids['mail'] = $manual.mail }
    }

    if ($user) {
        if ($user.email) { $ids['mail'] = $user.email }
        if ($user.email) { $ids['userPrincipalName'] = $user.email }
    }

    if (-not $ids.ContainsKey('samAccountName')) {
        $ids['samAccountName'] = $UserMapping.usernameToSamPattern -replace '\{username\}', $Member.username
    }

    return [pscustomobject]@{
        Username   = $Member.username
        Display    = $user.name
        Identities = $ids
        Email      = $user.email
    }
}

function Build-RoleAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][array]$Users,
        [Parameter(Mandatory)][array]$ProjectMemberships,
        [Parameter(Mandatory)][hashtable]$ProjectsByKey,
        [Parameter(Mandatory)][hashtable]$ProjectsByPath
    )

    $assignments = @{}

    foreach ($projMembership in $ProjectMemberships) {
        $path = $projMembership.path_with_namespace
        if (-not $path) { continue }
        $projInfo = $ProjectsByPath[$path.ToLower()]
        if (-not $projInfo) {
            $script:Report.Warnings += "No project mapping for GitLab path $path"
            continue
        }

        $projectKey = $projInfo.ProjectKey
        if (-not $assignments.ContainsKey($projectKey)) {
            $assignments[$projectKey] = @{ Roles = @{}; Project = $projInfo }
        }

        foreach ($member in $projMembership.members) {
            if (-not $member) { continue }
            $normalized = Get-NormalizedRole -AccessLevel $member.access_level_name -Config $Config -ProjectOverride $projInfo.Overrides
            if (-not $normalized) {
                $script:Report.Warnings += "No normalized role for access '$($member.access_level_name)' in project $path"
                continue
            }

            if ($Config.ad.projectRoleKeys -notcontains $normalized) {
                $script:Report.Warnings += "Normalized role '$normalized' not in ad.projectRoleKeys (project $path)"
                continue
            }

            $roleBucket = $assignments[$projectKey].Roles
            if (-not $roleBucket.ContainsKey($normalized)) {
                $roleBucket[$normalized] = New-Object System.Collections.ArrayList
            }

            $candidate = Get-UserIdentityCandidates -Member $member -Users $Users -UserMapping $Config.userMapping
            $roleBucket[$normalized].Add($candidate) | Out-Null
        }
    }

    return $assignments
}

function Resolve-AdUser {
    param(
        [pscustomobject]$Candidate,
        [string[]]$IdentityOrder
    )

    foreach ($idType in $IdentityOrder) {
        $value = $Candidate.Identities[$idType]
        if (-not $value) { continue }
        $escaped = $value.Replace("'", "''")
        $filter = switch ($idType.ToLower()) {
            'mail'              { "mail -eq '$escaped'" }
            'userprincipalname' { "userPrincipalName -eq '$escaped'" }
            default             { "samAccountName -eq '$escaped'" }
        }
        $user = Get-ADUser -Filter $filter -ErrorAction SilentlyContinue
        if ($user) { return $user }
    }
    return $null
}

function Sync-AdGroupMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)]$Assignments
    )

    foreach ($projectKey in $Assignments.Keys) {
        $projInfo = $Assignments[$projectKey].Project
        $projectOu = $Config.ad.projectOuTemplate -replace '\{ProjectKey\}', $projectKey
        $groupFmt = $Config.ad.groupNaming.projectGroupNameFormat
        foreach ($roleKey in $Assignments[$projectKey].Roles.Keys) {
            $groupName = ($groupFmt -replace '\{ProjectKey\}', $projectKey) -replace '\{RoleKey\}', $roleKey
            $groupDn = (Get-ADGroup -Filter "SamAccountName -eq '$groupName'" -ErrorAction SilentlyContinue).DistinguishedName
            if (-not $groupDn) {
                $script:Report.Warnings += "AD group missing for $groupName; create step should have handled it."
                continue
            }
            foreach ($candidate in $Assignments[$projectKey].Roles[$roleKey]) {
                $user = Resolve-AdUser -Candidate $candidate -IdentityOrder $Config.userMapping.preferredIdentityOrder
                if (-not $user) {
                    $script:Report.MissingUsers += "$($candidate.Username) (project $projectKey, role $roleKey)"
                    continue
                }

                $alreadyMember = Get-ADPrincipalGroupMembership -Identity $user | Where-Object { $_.SamAccountName -eq $groupName }
                if ($alreadyMember) {
                    continue
                }

                $msg = "Add $($user.SamAccountName) to $groupName"
                if ($script:DryRunEffective) {
                    Write-Log "[DryRun] $msg" 'INFO'
                } elseif ($PSCmdlet.ShouldProcess($groupName, $msg)) {
                    Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                    $script:Report.UsersAdded += "$($user.SamAccountName)->$groupName"
                    Write-Log $msg 'INFO'
                }
            }
        }
    }
}

function Initialize-AdoRestContext {
    param([pscustomobject]$Config)

    if ($script:AdoRestReady) { return }
    $collectionEnv = $Config.azureDevOps.collectionUrlEnvVar
    $patEnv = $Config.azureDevOps.personalAccessTokenEnvVar
    $collectionUrl = [Environment]::GetEnvironmentVariable($collectionEnv)
    if (-not $collectionUrl) { throw "Azure DevOps collection URL env var '$collectionEnv' is not set." }
    if ($Config.azureDevOps.useIntegratedAuthentication -ne $true) {
        $pat = [Environment]::GetEnvironmentVariable($patEnv)
        if (-not $pat) { throw "Azure DevOps PAT env var '$patEnv' is not set." }
    }

    $coreRest = Join-Path $script:RepoRoot 'modules\Core.Rest.psm1'
    if (Test-Path $coreRest) {
        Import-Module $coreRest -Force -ErrorAction Stop
        try { Initialize-CoreRest } catch { Write-Log "Core.Rest initialization warning: $_" 'WARN' }
        $script:AdoRestReady = $true
    } else {
        throw "Core.Rest module not found at $coreRest"
    }
}

function Invoke-AdoRestCompat {
    param(
        [string]$Method,
        [string]$RelativeUrl,
        [pscustomobject]$Config,
        $Body
    )

    # Resolve collection URL from env var (same semantics as before)
    $collectionUrl = Resolve-CollectionUrl -Config $Config

    $patEnvName = $Config.azureDevOps.personalAccessTokenEnvVar
    $pat        = if ($patEnvName) { [Environment]::GetEnvironmentVariable($patEnvName) } else { $null }

    # Preferred path when running inside the server: use default credentials
    if ($Config.azureDevOps.useIntegratedAuthentication -eq $true -and -not $pat) {

        # Build absolute URL if caller passed a relative path
        if ($RelativeUrl -like 'http*') {
            $fullUrl = $RelativeUrl
        } else {
            $rel = if ($RelativeUrl.StartsWith('/')) { $RelativeUrl } else { "/$RelativeUrl" }
            $fullUrl = "$collectionUrl$rel"
        }

        $irmParams = @{
            Method               = $Method
            Uri                  = $fullUrl
            UseDefaultCredentials = $true      # run as the account executing the script
            Authentication       = 'Negotiate' # Kerberos/NTLM in domain
            ErrorAction          = 'Stop'
            Headers              = @{ 'Accept' = 'application/json' }
        }

        if ($Body) {
            if ($Body -is [string]) {
                $irmParams.Body = $Body
            } else {
                $irmParams.Body = ($Body | ConvertTo-Json -Depth 10)
            }
            $irmParams['ContentType'] = 'application/json'
        }

        return Invoke-RestMethod @irmParams
    }

    # Fallback: use Core.Rest + PAT, exactly as your original design
    Initialize-AdoRestContext -Config $Config
    return Invoke-AdoRest -Method $Method -RelativeUrl $RelativeUrl -Body $Body
}

function Resolve-CollectionUrl {
    param([pscustomobject]$Config)

    $collectionEnv = $Config.azureDevOps.collectionUrlEnvVar
    $collectionUrl = [Environment]::GetEnvironmentVariable($collectionEnv)
    if (-not $collectionUrl) {
        throw "Azure DevOps collection URL env var '$collectionEnv' is not set."
    }
    return $collectionUrl.TrimEnd('/')
}

function Resolve-TfsSecurityExecutable {
    param([pscustomobject]$Config)

    $candidates = New-Object System.Collections.ArrayList
    if ($Config.azureDevOps.PSObject.Properties.Name -contains 'tfsSecurityExe' -and $Config.azureDevOps.tfsSecurityExe) {
        $candidates.Add($Config.azureDevOps.tfsSecurityExe) | Out-Null
    }
    if ($env:TFSSecurityExe) { $candidates.Add($env:TFSSecurityExe) | Out-Null }
    $candidates.Add('TFSSecurity.exe') | Out-Null
    foreach ($path in @(
        'C:\Program Files\Azure DevOps Server 2022\Tools\TFSSecurity.exe',
        'C:\Program Files\Azure DevOps Server 2020\Tools\TFSSecurity.exe',
        'C:\Program Files\Microsoft Team Foundation Server 2018\Tools\TFSSecurity.exe'
    )) {
        $candidates.Add($path) | Out-Null
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        $cmd = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate) }
    }
    throw "TFSSecurity executable not found. Set azureDevOps.tfsSecurityExe in config, TFSSecurityExe env var, or ensure TFSSecurity.exe is on PATH."
}

function ConvertTo-NetbiosDomain {
    param([string]$DomainValue)
    if (-not $DomainValue) { return $null }
    $base = $DomainValue.Split('.')[0]
    return $base.ToUpper()
}

function Get-AdoIdentityDescriptor {
    param(
        [string]$DisplayName,
        [pscustomobject]$Config
    )
    $identity = Get-AdoIdentity -DisplayName $DisplayName -Config $Config
    if (-not $identity) { return $null }
    if ($identity.PSObject.Properties['descriptor']) { return $identity.descriptor }
    elseif ($identity -is [System.Collections.IDictionary]) { return $identity['descriptor'] }
    return $null
}

function Get-AdoIdentity {
    param(
        [string]$DisplayName,
        [pscustomobject]$Config
    )
    $encoded = [uri]::EscapeDataString($DisplayName)
    $identities = Invoke-AdoRestCompat -Method GET -RelativeUrl "/_apis/identities?searchFilter=General&filterValue=$encoded&api-version=7.0" -Config $Config

    # Defensive: handle null/odd-shaped responses without throwing on missing properties
    if (-not $identities -or -not $identities.PSObject.Properties['value'] -or -not $identities.value) {
        return $null
    }

    $items = @($identities.value)
    $match = $items | Where-Object {
        $providerDisplayName = $null
        $displayName = $null
        if ($_.PSObject.Properties['providerDisplayName']) { $providerDisplayName = $_.providerDisplayName }
        elseif ($_ -is [System.Collections.IDictionary]) { $providerDisplayName = $_['providerDisplayName'] }

        if ($_.PSObject.Properties['displayName']) { $displayName = $_.displayName }
        elseif ($_ -is [System.Collections.IDictionary]) { $displayName = $_['displayName'] }

        ($providerDisplayName -eq $DisplayName) -or ($displayName -eq $DisplayName)
    } | Select-Object -First 1

    if (-not $match) { return $null }
    return $match
}


function Ensure-CustomAdoGroup {
    param(
        [string]$ProjectName,
        [string]$GroupName,
        [string]$Description,
        [string]$CollectionUrl,
        [string]$TfsSecurityExe
    )

    # Custom ADO group identity format: [ProjectName]\GroupName
    $customGroupIdentity = "[$ProjectName]\$GroupName"
    $msg = "Creating custom ADO group $customGroupIdentity"

    if ($script:DryRunEffective) {
        Write-Log "[DryRun] $msg" 'INFO'
        if ($script:Report -and $script:Report.PSObject.Properties['CreatedAdoGroups']) {
            $script:Report.CreatedAdoGroups += "[DRYRUN] $customGroupIdentity"
        }
        return $customGroupIdentity
    }

    # Use TFSSecurity /gcr to create custom group
    $arguments = @(
        '/gcr',
        $customGroupIdentity,
        $Description,
        "/collection:$CollectionUrl"
    )

    $exitCode = $null
    try {
        & $TfsSecurityExe @arguments
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Log "TFSSecurity /gcr invocation failed for $($customGroupIdentity): $_" 'WARN'
        return $null
    }

    if ($exitCode -ne 0) {
        # Group might already exist (exit code 1), which is OK
        if ($exitCode -eq 1) {
            Write-Log "Custom ADO group $customGroupIdentity already exists (exit $exitCode)" 'DEBUG'
        } else {
            Write-Log "TFSSecurity /gcr failed for $customGroupIdentity (exit $exitCode)" 'WARN'
            return $null
        }
    } else {
        Write-Log $msg 'INFO'
    }

    if ($script:Report -and $script:Report.PSObject.Properties['CreatedAdoGroups']) {
        $script:Report.CreatedAdoGroups += $customGroupIdentity
    }

    return $customGroupIdentity
}

function Add-AdGroupToAdoGroup {
    param(
        [string]$AdGroupSam,
        [string]$AdGroupDomain,
        [string]$AdoGroupIdentity,
        [string]$CollectionUrl,
        [string]$TfsSecurityExe
    )

    # Convert DNS-style or flat domain to NetBIOS (e.g. contoso.local -> CONTOSO)
    $lookupDomain = ConvertTo-NetbiosDomain $AdGroupDomain

    # 1. Make sure the AD group exists
    $adGroup = $null
    try {
        $adGroup = Get-ADGroup -Identity $AdGroupSam -Server $lookupDomain -ErrorAction Stop
    }
    catch {
        Write-Log "AD group $lookupDomain\$AdGroupSam not found. Skipping mapping to $AdoGroupIdentity. Error: $_" 'WARN'
        if ($script:Report -and $script:Report.PSObject.Properties['MissingUsers']) {
            $script:Report.MissingUsers += "$lookupDomain\$AdGroupSam"
        }
        return $false
    }

    # Identity spec for TFSSecurity: n:DOMAIN\SamAccountName
    $identitySpec = "n:{0}\{1}" -f $lookupDomain, $AdGroupSam
    $msg = "Adding AD group $identitySpec to ADO group $AdoGroupIdentity"

    if ($script:DryRunEffective) {
        Write-Log "[DryRun] $msg" 'INFO'
        if ($script:Report -and $script:Report.PSObject.Properties['AdGroupMappings']) {
            $script:Report.AdGroupMappings += "[DRYRUN] $identitySpec -> $AdoGroupIdentity"
        }
        return $true
    }

    # 2. Call TFSSecurity /g+ to add AD group to ADO group
    $arguments = @(
        '/g+',
        $AdoGroupIdentity,
        $identitySpec,
        "/collection:$CollectionUrl"
    )

    $exitCode = $null
    try {
        & $TfsSecurityExe @arguments
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Log "TFSSecurity /g+ invocation failed for $AdoGroupIdentity + $($identitySpec): $_" 'WARN'
        return $false
    }

    if ($exitCode -ne 0) {
        Write-Log "TFSSecurity /g+ failed for $AdoGroupIdentity + $identitySpec (exit $exitCode)" 'WARN'
        return $false
    }

    if ($script:Report -and $script:Report.PSObject.Properties['AdGroupMappings']) {
        $script:Report.AdGroupMappings += "$identitySpec -> $AdoGroupIdentity"
    }
    Write-Log $msg 'INFO'
    return $true
}

function Add-CustomGroupToBuiltInGroup {
    param(
        [string]$CustomGroupIdentity,
        [string]$BuiltInGroupIdentity,
        [string]$CollectionUrl,
        [string]$TfsSecurityExe
    )

    $msg = "Adding custom ADO group $CustomGroupIdentity to built-in group $BuiltInGroupIdentity"

    if ($script:DryRunEffective) {
        Write-Log "[DryRun] $msg" 'INFO'
        if ($script:Report -and $script:Report.PSObject.Properties['CustomToBuiltInMappings']) {
            $script:Report.CustomToBuiltInMappings += "[DRYRUN] $CustomGroupIdentity -> $BuiltInGroupIdentity"
        }
        return $true
    }

    # Use TFSSecurity /g+ to add custom group to built-in group
    $arguments = @(
        '/g+',
        $BuiltInGroupIdentity,
        $CustomGroupIdentity,
        "/collection:$CollectionUrl"
    )

    $exitCode = $null
    try {
        & $TfsSecurityExe @arguments
        $exitCode = $LASTEXITCODE
    }
    catch {
        Write-Log "TFSSecurity /g+ invocation failed for $BuiltInGroupIdentity + $($CustomGroupIdentity): $_" 'WARN'
        return $false
    }

    if ($exitCode -ne 0) {
        Write-Log "TFSSecurity /g+ failed for $BuiltInGroupIdentity + $($CustomGroupIdentity) (exit $exitCode)" 'WARN'
        return $false
    }

    if ($script:Report -and $script:Report.PSObject.Properties['CustomToBuiltInMappings']) {
        $script:Report.CustomToBuiltInMappings += "$CustomGroupIdentity -> $BuiltInGroupIdentity"
    }
    Write-Log $msg 'INFO'
    return $true
}

function Sync-AdoGroupMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][hashtable]$ProjectsByKey
    )

    $collectionUrl = Resolve-CollectionUrl -Config $Config
    $tfsSecurityExe = Resolve-TfsSecurityExecutable -Config $Config
    $defaultMappings = $Config.azureDevOps.defaultAdoGroupMappings
    $fmt = $Config.ad.groupNaming.projectGroupNameFormat

    Write-Log "Starting three-step ADO group mapping process..." 'INFO'

    foreach ($proj in $ProjectsByKey.Values) {
        Write-Log "Processing project: $($proj.AdoProjectName)" 'INFO'
        $overrides = $proj.Overrides
        $adoGroupMappings = if ($overrides -and $overrides.overrideAdoGroupMappings) { $overrides.overrideAdoGroupMappings } else { $defaultMappings }
        
        foreach ($roleKey in $Config.ad.projectRoleKeys) {
            $adoBuiltInGroups = $adoGroupMappings.$roleKey
            if (-not $adoBuiltInGroups) { continue }
            
            # Parse AD group name
            $adGroupName = ($fmt -replace '\{ProjectKey\}', $proj.ProjectKey) -replace '\{RoleKey\}', $roleKey
            $adDomain = $null
            $adSam = $adGroupName
            if ($adGroupName -match '^(?<dom>[^\\]+)\\(?<sam>.+)$') {
                $adDomain = $matches.dom
                $adSam = $matches.sam
            }
            if (-not $adDomain) { $adDomain = $Config.ad.domainDnsName }
            $adDomain = ConvertTo-NetbiosDomain $adDomain

            # Use AD group SamAccountName as the custom ADO group name
            $customAdoGroupName = $adSam
            $customAdoGroupDescription = "Custom ADO group for $roleKey role (mapped from AD: $adDomain\$adSam)"

            Write-Log "Processing role: $roleKey (AD: $adDomain\$adSam)" 'INFO'

            # STEP 1: Create custom ADO group with same name as AD group
            Write-Log "  Step 1: Creating custom ADO group [$($proj.AdoProjectName)]\$customAdoGroupName" 'INFO'
            $customGroupIdentity = Ensure-CustomAdoGroup -ProjectName $proj.AdoProjectName `
                -GroupName $customAdoGroupName `
                -Description $customAdoGroupDescription `
                -CollectionUrl $collectionUrl `
                -TfsSecurityExe $tfsSecurityExe

            if (-not $customGroupIdentity) {
                Write-Log "  Failed to create/verify custom ADO group. Skipping role $roleKey." 'WARN'
                continue
            }

            # STEP 2: Add AD group to the custom ADO group
            Write-Log "  Step 2: Adding AD group $adDomain\$adSam to custom ADO group $customGroupIdentity" 'INFO'
            $adMappingSuccess = Add-AdGroupToAdoGroup -AdGroupSam $adSam `
                -AdGroupDomain $adDomain `
                -AdoGroupIdentity $customGroupIdentity `
                -CollectionUrl $collectionUrl `
                -TfsSecurityExe $tfsSecurityExe

            if (-not $adMappingSuccess) {
                Write-Log "  Failed to add AD group to custom ADO group. Skipping built-in group mappings." 'WARN'
                continue
            }

            # STEP 3: Add custom ADO group to each built-in ADO group
            foreach ($builtInGroup in $adoBuiltInGroups) {
                $builtInGroupIdentity = if ($builtInGroup -like '[*]*') { 
                    $builtInGroup 
                } else { 
                    "[{0}]\{1}" -f $proj.AdoProjectName, $builtInGroup 
                }

                Write-Log "  Step 3: Adding custom group $customGroupIdentity to built-in group $builtInGroupIdentity" 'INFO'
                $builtInMappingSuccess = Add-CustomGroupToBuiltInGroup -CustomGroupIdentity $customGroupIdentity `
                    -BuiltInGroupIdentity $builtInGroupIdentity `
                    -CollectionUrl $collectionUrl `
                    -TfsSecurityExe $tfsSecurityExe

                if (-not $builtInMappingSuccess) {
                    Write-Log "  Failed to add custom group to built-in group $builtInGroupIdentity" 'WARN'
                }
            }

            Write-Log "  Completed mapping for role: $roleKey" 'INFO'
        }
    }

    Write-Log "ADO group mapping process completed" 'INFO'
}

function Invoke-GitLabIdentityToAdoImport {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,
        [switch]$DryRun,
        [switch]$SkipAdOperations
    )

    $script:Report = [ordered]@{
        CreatedOUs                = @()
        CreatedGroups             = @()
        CreatedAdoGroups          = @()
        UsersAdded                = @()
        MissingUsers              = @()
        AdGroupMappings           = @()
        CustomToBuiltInMappings   = @()
        Warnings                  = @()
    }
    $script:DryRunEffective = $false

    $effectiveConfigPath = if ($ConfigPath) { $ConfigPath } else { Join-Path $script:RepoRoot 'config-ado-ad.json' }

    $loaded = Get-Config -Path $effectiveConfigPath -DryRunSwitch:$DryRun
    $config = $loaded.Config

    Test-Environment -Config $config -SkipAdOperations:$SkipAdOperations

    $maps = Get-ProjectMaps -Config $config -ProjectMappings $loaded.ProjectMappings

    if (-not $SkipAdOperations) {
        Ensure-OUs -Config $config -ProjectsByKey $maps.ProjectsByKey
        Ensure-GlobalGroups -Config $config
        Ensure-CollectionGroups -Config $config
        Ensure-ProjectGroups -Config $config -ProjectsByKey $maps.ProjectsByKey

        $assignments = Build-RoleAssignments -Config $config -Users $loaded.Users -ProjectMemberships $loaded.ProjectMemberships -ProjectsByKey $maps.ProjectsByKey -ProjectsByPath $maps.ProjectsByPath
        Sync-AdGroupMembership -Config $config -Assignments $assignments
    }
    else {
        Write-Log "Skipping AD OU/group creation and membership sync (SkipAdOperations set)." 'INFO'
    }
    Sync-AdoGroupMappings -Config $config -ProjectsByKey $maps.ProjectsByKey

    Write-Host "" 
    Write-Host "==== Summary ====" -ForegroundColor Green
    Write-Host ("DryRun: {0}" -f $script:DryRunEffective)
    Write-Host ""
    Write-Host "Active Directory:" -ForegroundColor Cyan
    Write-Host ("  OUs created: {0}" -f ($script:Report.CreatedOUs.Count))
    Write-Host ("  AD groups created: {0}" -f ($script:Report.CreatedGroups.Count))
    Write-Host ("  Users added to AD groups: {0}" -f ($script:Report.UsersAdded.Count))
    Write-Host ("  Missing AD users: {0}" -f ($script:Report.MissingUsers.Count))
    Write-Host ""
    Write-Host "Azure DevOps Group Mapping (3-Step Process):" -ForegroundColor Cyan
    Write-Host ("  Step 1 - Custom ADO groups created: {0}" -f ($script:Report.CreatedAdoGroups.Count))
    Write-Host ("  Step 2 - AD groups mapped to custom ADO groups: {0}" -f ($script:Report.AdGroupMappings.Count))
    Write-Host ("  Step 3 - Custom ADO groups added to built-in groups: {0}" -f ($script:Report.CustomToBuiltInMappings.Count))
    if ($script:Report.Warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        $script:Report.Warnings | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
}

function Initialize-GitLabIdentityImport {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,
        [switch]$DryRun
    )
    Invoke-GitLabIdentityToAdoImport @PSBoundParameters
}

Export-ModuleMember -Function Invoke-GitLabIdentityToAdoImport, Initialize-GitLabIdentityImport
