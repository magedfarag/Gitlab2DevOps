<#
.SYNOPSIS
    Azure DevOps project and repository management functions.

.DESCRIPTION
    This module handles all Azure DevOps operations including project creation,
    repository management, wiki setup, branch policies, RBAC configuration,
    and security controls. It has no knowledge of GitLab.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Requires: Core.Rest module
    Version: 2.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Policy type IDs (Microsoft documented - stable GUIDs)
$script:POLICY_REQUIRED_REVIEWERS = 'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd'
$script:POLICY_BUILD_VALIDATION   = '0609b952-1397-4640-95ec-e00a01b2f659'
$script:POLICY_COMMENT_RESOLUTION = 'c6a1889d-b943-48DE-8ECA-6E5AC81B08B6'
$script:POLICY_WORK_ITEM_LINK     = 'fd2167ab-b0be-447a-8ec8-39368250830e'
$script:POLICY_STATUS_CHECK       = 'caae6c6e-4c53-40e6-94f0-6d7410830a9b'

# Git security namespace and permission bits
$script:NS_GIT = '2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87'
$script:GIT_BITS = @{
    GenericContribute      = 4
    ForcePush              = 8
    PullRequestContribute  = 262144
}

<#
.SYNOPSIS
    Loads a wiki template from an external markdown file.

.DESCRIPTION
    Helper function to load wiki page content from markdown template files
    stored in the WikiTemplates subdirectory. This separates content from logic.

.PARAMETER TemplateName
    Name of the template file relative to WikiTemplates directory.
    Example: "Dev/DevSetup" loads "WikiTemplates/Dev/DevSetup.md"

.OUTPUTS
    String content of the template file.

.EXAMPLE
    $content = Get-WikiTemplate "Security/SecurityPolicies"

.NOTES
    Templates are stored in modules/AzureDevOps/WikiTemplates/
    Uses UTF-8 encoding and -Raw to preserve formatting.
#>
function Get-WikiTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TemplateName
    )
    
    $templatePath = Join-Path $PSScriptRoot "WikiTemplates\$TemplateName.md"
    
    if (-not (Test-Path $templatePath)) {
        throw "[Get-WikiTemplate] Template not found: $templatePath"
    }
    
    Write-Verbose "[Get-WikiTemplate] Loading template: $TemplateName"
    return (Get-Content -Path $templatePath -Raw -Encoding UTF8)
}

<#
.SYNOPSIS
    Gets the list of Azure DevOps projects with caching.

.DESCRIPTION
    Retrieves all projects from Azure DevOps with optional in-memory caching
    to reduce API calls during bulk operations. Cache is stored in Core.Rest module.

.PARAMETER UseCache
    If true, returns cached results if available. Default is true.

.PARAMETER RefreshCache
    If true, forces a refresh of the cached project list.

.OUTPUTS
    Array of project objects.

.EXAMPLE
    $projects = Get-AdoProjectList
    
.EXAMPLE
    $projects = Get-AdoProjectList -RefreshCache
#>
function Get-AdoProjectList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [switch]$UseCache = $true,
        [switch]$RefreshCache
    )
    
    # Get cache from Core.Rest module
    $cache = Get-Variable -Name ProjectCache -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if (-not $cache) {
        Write-Verbose "[Get-AdoProjectList] Cache not initialized, creating new cache"
        $cache = @{}
        Set-Variable -Name ProjectCache -Scope Script -Value $cache
    }
    
    $cacheKey = 'ado_projects'
    $cacheExpiry = 'ado_projects_expiry'
    $cacheDurationMinutes = 15
    
    # Check cache validity
    $now = Get-Date
    $cacheValid = $false
    
    if ($UseCache -and -not $RefreshCache -and $cache.ContainsKey($cacheKey)) {
        if ($cache.ContainsKey($cacheExpiry)) {
            $expiry = $cache[$cacheExpiry]
            if ($now -lt $expiry) {
                $cacheValid = $true
                Write-Verbose "[Get-AdoProjectList] Using cached project list (expires: $expiry)"
            }
            else {
                Write-Verbose "[Get-AdoProjectList] Cache expired, refreshing"
            }
        }
    }
    
    if ($cacheValid) {
        return $cache[$cacheKey]
    }
    
    # Fetch fresh data from API
    Write-Verbose "[Get-AdoProjectList] Fetching project list from Azure DevOps API..."
    $list = Invoke-AdoRest GET "/_apis/projects?``$top=5000"
    $projects = $list.value
    
    # Update cache
    $cache[$cacheKey] = $projects
    $cache[$cacheExpiry] = $now.AddMinutes($cacheDurationMinutes)
    
    Write-Verbose "[Get-AdoProjectList] Cached $($projects.Count) projects (expires: $($cache[$cacheExpiry]))"
    
    return $projects
}

<#
.SYNOPSIS
    Tests if an Azure DevOps project exists.

.DESCRIPTION
    Checks if the specified project exists in Azure DevOps.

.PARAMETER ProjectName
    Name of the Azure DevOps project to check.

.OUTPUTS
    Boolean indicating if project exists.

.EXAMPLE
    Test-AdoProjectExists -ProjectName "MyProject"
#>
function Test-AdoProjectExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
    
    try {
        $projects = Get-AdoProjectList
        $project = $projects | Where-Object { $_.name -eq $ProjectName }
        return $null -ne $project
    }
    catch {
        Write-Verbose "[Test-AdoProjectExists] Error checking project: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets repositories in an Azure DevOps project.

.DESCRIPTION
    Returns all repositories in the specified Azure DevOps project.

.PARAMETER ProjectName
    Name of the Azure DevOps project.

.OUTPUTS
    Array of repository objects.

.EXAMPLE
    Get-AdoProjectRepositories -ProjectName "MyProject"
#>
function Get-AdoProjectRepositories {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
    
    try {
        $result = Invoke-AdoRest GET "/$ProjectName/_apis/git/repositories"
        return $result.value
    }
    catch {
        Write-Verbose "[Get-AdoProjectRepositories] Error getting repositories: $_"
        return @()
    }
}

<#
.SYNOPSIS
    Waits for an Azure DevOps asynchronous operation to complete.

.DESCRIPTION
    Polls operation status until succeeded, failed, or cancelled. Used for
    long-running operations like project creation.

.PARAMETER Id
    Operation ID returned from async API call.

.OUTPUTS
    Final operation status object.

.EXAMPLE
    Wait-AdoOperation -Id "abc-123-def"
#>
function Wait-AdoOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )
    
    Write-Verbose "[Wait-AdoOperation] Waiting for operation $Id to complete..."
    
    for ($i = 0; $i -lt 60; $i++) {
        try {
            Write-Verbose "[Wait-AdoOperation] Polling attempt $($i + 1)/60"
            $op = Invoke-AdoRest GET "/_apis/operations/$Id"
            
            Write-Verbose "[Wait-AdoOperation] Operation status: $($op.status)"
            
            if ($op.status -in 'succeeded', 'failed', 'cancelled') {
                Write-Verbose "[Wait-AdoOperation] Operation completed with status: $($op.status)"
                return $op
            }
            
            Write-Verbose "[Wait-AdoOperation] Operation still in progress, waiting 3 seconds..."
            Start-Sleep 3
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Verbose "[Wait-AdoOperation] Poll failed (attempt $($i + 1)): $errorMsg"
            
            # If operation doesn't exist (404), it may have already completed or never existed
            # This can happen if project already existed and Azure DevOps returned success without creating operation
            if ($errorMsg -match "404|Not Found|does not exist") {
                Write-Warning "[Wait-AdoOperation] Operation $Id not found (may have completed or project already existed)"
                # Return a synthetic success status
                return @{ 
                    id = $Id
                    status = 'succeeded'
                    _message = 'Operation not found - assuming completion'
                }
            }
            
            # If it's a connection error, retry with shorter delay
            if ($errorMsg -match "connection was forcibly closed|Unable to read data|SSL|certificate") {
                if ($i -lt 59) {
                    Write-Verbose "[Wait-AdoOperation] Connection error, retrying in 2 seconds..."
                    Start-Sleep 2
                }
                else {
                    Write-Warning "[Wait-AdoOperation] Exhausted all retry attempts due to connection errors"
                    throw
                }
            }
            else {
                # For other errors, throw immediately
                throw
            }
        }
    }
    
    throw "Timeout waiting for operation $Id after 60 attempts"
}

<#
.SYNOPSIS
    Ensures an Azure DevOps project exists, creating if necessary.

.DESCRIPTION
    Checks if project exists; creates with default Agile template if missing.
    Idempotent - safe to call multiple times. Supports -WhatIf and -Confirm.

.PARAMETER Name
    Project name.

.PARAMETER ProcessTemplate
    Process template name ('Agile', 'Scrum', 'CMMI', 'Basic') or GUID. Default: 'Agile'.

.OUTPUTS
    Azure DevOps project object.

.EXAMPLE
    Ensure-AdoProject "MyProject"

.EXAMPLE
    Ensure-AdoProject "MyProject" -ProcessTemplate "Scrum"

.EXAMPLE
    Ensure-AdoProject "MyProject" -WhatIf
#>
function Ensure-AdoProject {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$ProcessTemplate = "Agile" # Default to Agile template
    )
    
    Write-Verbose "[Ensure-AdoProject] Checking if project '$Name' exists..."
    
    # Force refresh cache to ensure we have latest project list
    # This prevents attempting to create projects that already exist
    $projects = Get-AdoProjectList -RefreshCache
    $p = $projects | Where-Object { $_.name -eq $Name }
    
    if ($p) {
        Write-Verbose "[Ensure-AdoProject] Project '$Name' already exists (ID: $($p.id))"
        Write-Host "[INFO] Project '$Name' already exists - no changes needed" -ForegroundColor Green
        return $p
    }
    
    if ($PSCmdlet.ShouldProcess($Name, "Create Azure DevOps project")) {
        # Resolve process template name to GUID by querying available processes
        $processTemplateId = $ProcessTemplate
        
        # If not a GUID, look up by name
        if ($ProcessTemplate -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            Write-Verbose "[Ensure-AdoProject] Resolving process template name '$ProcessTemplate' to GUID..."
            try {
                $processes = Invoke-AdoRest GET "/_apis/process/processes"
                $matchedProcess = $processes.value | Where-Object { $_.name -eq $ProcessTemplate }
                
                if ($matchedProcess) {
                    $processTemplateId = $matchedProcess.id
                    Write-Verbose "[Ensure-AdoProject] Resolved '$ProcessTemplate' to GUID: $processTemplateId"
                } else {
                    Write-Warning "[Ensure-AdoProject] Process template '$ProcessTemplate' not found. Using default."
                    $defaultProcess = $processes.value | Where-Object { $_.isDefault -eq $true }
                    if ($defaultProcess) {
                        $processTemplateId = $defaultProcess.id
                        Write-Verbose "[Ensure-AdoProject] Using default process: $($defaultProcess.name) ($processTemplateId)"
                    } else {
                        throw "No default process template found on server"
                    }
                }
            }
            catch {
                Write-Warning "[Ensure-AdoProject] Failed to query process templates: $_"
                Write-Warning "[Ensure-AdoProject] Using provided value as-is: $ProcessTemplate"
                $processTemplateId = $ProcessTemplate
            }
        }
        
        Write-Host "[INFO] Creating project '$Name' with $ProcessTemplate process template..." -ForegroundColor Cyan
        Write-Verbose "[Ensure-AdoProject] Process Template ID: $processTemplateId"
        
        $body = @{
            name         = $Name
            description  = "Provisioned by GitLab to Azure DevOps migration"
            capabilities = @{
                versioncontrol  = @{ sourceControlType = "Git" }
                processTemplate = @{ templateTypeId = $processTemplateId }
            }
        }
        
        Write-Verbose "[Ensure-AdoProject] Sending POST request to create project..."
        Write-Verbose "[Ensure-AdoProject] Request body: $($body | ConvertTo-Json -Depth 5)"
        $resp = Invoke-AdoRest POST "/_apis/projects" -Body $body
        
        Write-Verbose "[Ensure-AdoProject] Project creation initiated, operation ID: $($resp.id)"
        Write-Host "[INFO] Project creation operation started (ID: $($resp.id))" -ForegroundColor Cyan
        Write-Host "[INFO] Waiting for operation to complete..." -ForegroundColor Cyan
        
        $final = Wait-AdoOperation $resp.id
        
        if ($final.status -ne 'succeeded') {
            Write-Error "[Ensure-AdoProject] Project creation failed with status: $($final.status)"
            throw "Project creation failed with status: $($final.status)"
        }
        
        Write-Verbose "[Ensure-AdoProject] Project creation completed successfully"
        
        # Invalidate project cache after creating new project
        Write-Verbose "[Ensure-AdoProject] Invalidating project cache after creation"
        Get-AdoProjectList -RefreshCache | Out-Null
        
        Write-Host "[SUCCESS] Project '$Name' created successfully" -ForegroundColor Green
        
        Write-Verbose "[Ensure-AdoProject] Fetching project details..."
        return Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Name))"
    }
}

<#
.SYNOPSIS
    Gets the graph descriptor for a project.

.DESCRIPTION
    Retrieves the unique descriptor used for security and group operations.

.PARAMETER ProjectId
    Azure DevOps project ID.

.OUTPUTS
    Project descriptor string.

.EXAMPLE
    Get-AdoProjectDescriptor "abc-123"
#>
function Get-AdoProjectDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId
    )
    
    try {
        # Suppress 404 errors since Graph API may not be available
        $ErrorActionPreference = 'Stop'
        $result = Invoke-AdoRest GET "/_apis/graph/descriptors/$ProjectId"
        Write-Verbose "[Get-AdoProjectDescriptor] Successfully retrieved descriptor for project $ProjectId"
        return $result.value
    }
    catch {
        # Graph API may not be available (404) or may require different permissions
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        if ($statusCode -eq 404) {
            Write-Verbose "[Get-AdoProjectDescriptor] Graph API not available (HTTP 404) - this is normal for some on-premise installations"
            Write-Warning "Graph API not accessible. Some features (RBAC groups, security) may not work."
        }
        else {
            Write-Verbose "[Get-AdoProjectDescriptor] Graph API error for project $ProjectId : $_"
            Write-Warning "Graph API error (HTTP $statusCode). Some features (RBAC groups, security) may not work."
        }
        
        return $null
    }
}

<#
.SYNOPSIS
    Gets built-in group descriptor by name.

.DESCRIPTION
    Retrieves descriptor for default groups like "Contributors",
    "Project Administrators", etc.

.PARAMETER ProjDesc
    Project descriptor.

.PARAMETER GroupName
    Built-in group name (e.g., "Contributors").

.OUTPUTS
    Group descriptor string.

.EXAMPLE
    Get-AdoBuiltInGroupDescriptor $projDesc "Contributors"
#>
function Get-AdoBuiltInGroupDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjDesc,
        
        [Parameter(Mandatory)]
        [string]$GroupName
    )
    
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&``$top=200"
    ($groups.value | Where-Object { $_.principalName -like "*\[$GroupName]" }).descriptor
}

<#
.SYNOPSIS
    Ensures a custom group exists in the project.

.DESCRIPTION
    Creates group if missing. Idempotent.

.PARAMETER ProjDesc
    Project descriptor.

.PARAMETER DisplayName
    Group display name.

.OUTPUTS
    Group object.

.EXAMPLE
    Ensure-AdoGroup $projDesc "Dev"
#>
function Ensure-AdoGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjDesc,
        
        [Parameter(Mandatory)]
        [string]$DisplayName
    )
    
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&``$top=200"
    $existing = $groups.value | Where-Object { $_.displayName -eq $DisplayName }
    
    if ($existing) {
        Write-Verbose "[AzureDevOps] Group '$DisplayName' already exists"
        return $existing
    }
    
    Write-Host "[INFO] Creating group '$DisplayName'"
    Invoke-AdoRest POST "/_apis/graph/groups" -Body @{
        displayName     = $DisplayName
        description     = "Auto-provisioned group: $DisplayName"
        scopeDescriptor = $ProjDesc
    }
}

<#
.SYNOPSIS
    Ensures group membership exists.

.DESCRIPTION
    Adds member to container group if not already present.
    Handles 409 Conflict gracefully.

.PARAMETER Container
    Container group descriptor.

.PARAMETER Member
    Member descriptor.

.EXAMPLE
    Ensure-AdoMembership $containerDesc $memberDesc
#>
function Ensure-AdoMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Container,
        
        [Parameter(Mandatory)]
        [string]$Member
    )
    
    try {
        Invoke-AdoRest PUT "/_apis/graph/memberships/$Member/$Container"
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 409) {
            Write-Verbose "[AzureDevOps] Membership already exists"
        }
        else {
            throw
        }
    }
}

<#
.SYNOPSIS
    Ensures a work item area exists.

.DESCRIPTION
    Creates area path if missing. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Area
    Area name.

.EXAMPLE
    Ensure-AdoArea "MyProject" "Backend"
#>
function Ensure-AdoArea {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$Area
    )
    
    try {
        $area = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas/$([uri]::EscapeDataString($Area))"
        Write-Host "[INFO] Area '$Area' already exists" -ForegroundColor Gray
        return $area
    }
    catch {
        # 404 is expected for new areas - don't treat as error
        Write-Host "[INFO] Creating area '$Area'" -ForegroundColor Cyan
        Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas" -Body @{ name = $Area }
    }
}

<#
.SYNOPSIS
    Ensures project wiki exists.

.DESCRIPTION
    Creates default project wiki if missing. Idempotent.

.PARAMETER ProjId
    Project ID.

.PARAMETER Project
    Project name.

.OUTPUTS
    Wiki object.

.EXAMPLE
    Ensure-AdoProjectWiki $projId "MyProject"
#>
function Ensure-AdoProjectWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjId,
        
        [Parameter(Mandatory)]
        [string]$Project
    )
    
    $w = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis"
    $projWiki = $w.value | Where-Object { $_.type -eq 'projectWiki' }
    
    if ($projWiki) {
        Write-Verbose "[AzureDevOps] Project wiki already exists"
        return $projWiki
    }
    
    Write-Host "[INFO] Creating project wiki"
    Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis" -Body @{
        name      = "$Project.wiki"
        type      = "projectWiki"
        projectId = $ProjId
    }
}

<#
.SYNOPSIS
    Creates or updates a wiki page.

.DESCRIPTION
    Upserts wiki page content.

.PARAMETER Project
    Project name.

.PARAMETER WikiId
    Wiki ID.

.PARAMETER Path
    Page path (e.g., "/Home").

.PARAMETER Markdown
    Page content in Markdown format.

.EXAMPLE
    Upsert-AdoWikiPage "MyProject" "wiki123" "/Home" "# Welcome"
#>
function Upsert-AdoWikiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId,
        
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Markdown
    )
    
    $enc = [uri]::EscapeDataString($Path)
    Invoke-AdoRest PUT "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?path=$enc" -Body @{
        content = $Markdown
    } | Out-Null
}

<#
.SYNOPSIS
    Gets the process template name for a project.

.DESCRIPTION
    Queries the project's capabilities to determine which process template it uses.

.PARAMETER ProjectId
    Project ID.

.OUTPUTS
    Process template name ('Agile', 'Scrum', 'CMMI', 'Basic', or 'Unknown').

.EXAMPLE
    Get-AdoProjectProcessTemplate "abc-123"
#>
function Get-AdoProjectProcessTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId
    )
    
    try {
        # Get project capabilities
        $project = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($ProjectId))?includeCapabilities=true"
        $templateId = $project.capabilities.processTemplate.templateTypeId
        
        # Query available processes to get the name for this ID
        # This handles servers where GUIDs may differ from cloud defaults
        try {
            $processes = Invoke-AdoRest GET "/_apis/process/processes"
            $matchedProcess = $processes.value | Where-Object { $_.id -eq $templateId }
            
            if ($matchedProcess) {
                Write-Host "[INFO] Project uses $($matchedProcess.name) process template (ID: $templateId)" -ForegroundColor Cyan
                return $matchedProcess.name
            }
        }
        catch {
            Write-Verbose "[Get-AdoProjectProcessTemplate] Could not query process list: $_"
        }
        
        # Fallback: Try standard cloud GUIDs (for backward compatibility)
        $standardTemplateMap = @{
            '6b724908-ef14-45cf-84f8-768b5384da45' = 'Agile'      # Standard cloud GUID
            'adcc42ab-9882-485e-a3ed-7678f01f66bc' = 'Scrum'      # Standard cloud GUID
            '27450541-8e31-4150-9947-dc59f998fc01' = 'CMMI'
            'b8a3a935-7e91-48b8-a94c-606d37c3e9f2' = 'Basic'
        }
        
        $templateName = $standardTemplateMap[$templateId]
        if ($templateName) {
            Write-Host "[INFO] Project uses $templateName process template (ID: $templateId)" -ForegroundColor Cyan
            return $templateName
        } else {
            Write-Warning "[Get-AdoProjectProcessTemplate] Unknown process template ID: $templateId"
            return 'Unknown'
        }
    }
    catch {
        Write-Warning "[Get-AdoProjectProcessTemplate] Failed to detect process template: $_"
        return 'Unknown'
    }
}

<#
.SYNOPSIS
    Gets available work item types for a project.

.DESCRIPTION
    Queries the work item types available in the project's process template.

.PARAMETER Project
    Project name.

.OUTPUTS
    Array of work item type names.

.EXAMPLE
    Get-AdoWorkItemTypes "MyProject"
#>
function Get-AdoWorkItemTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )
    
    try {
        $projEscaped = [uri]::EscapeDataString($Project)
        $types = Invoke-AdoRest GET "/$projEscaped/_apis/wit/workitemtypes"
        
        # Handle different response formats
        $typeNames = @()
        
        if ($types -is [array]) {
            # Direct array response
            Write-Verbose "[Get-AdoWorkItemTypes] Response is direct array with $($types.Count) items"
            $typeNames = $types | ForEach-Object { 
                if ($_.PSObject.Properties['name']) { $_.name }
                elseif ($_.PSObject.Properties['referenceName']) { $_.referenceName }
            }
        } 
        elseif ($types.PSObject.Properties['value']) {
            # Wrapped in 'value' property
            Write-Verbose "[Get-AdoWorkItemTypes] Response wrapped in 'value' property with $($types.value.Count) items"
            $typeNames = $types.value | ForEach-Object { 
                if ($_.PSObject.Properties['name']) { $_.name }
                elseif ($_.PSObject.Properties['referenceName']) { $_.referenceName }
            }
        } 
        elseif ($types.PSObject.Properties['count']) {
            # Wrapped in 'count' property
            Write-Verbose "[Get-AdoWorkItemTypes] Response wrapped in 'count' property"
            $typeNames = $types.count | ForEach-Object { 
                if ($_.PSObject.Properties['name']) { $_.name }
                elseif ($_.PSObject.Properties['referenceName']) { $_.referenceName }
            }
        } 
        else {
            # Fallback: try direct properties
            Write-Verbose "[Get-AdoWorkItemTypes] Response format unknown, attempting direct enumeration"
            Write-Verbose "[Get-AdoWorkItemTypes] Response type: $($types.GetType().FullName)"
            Write-Verbose "[Get-AdoWorkItemTypes] Properties: $($types.PSObject.Properties.Name -join ', ')"
            
            $typeNames = @($types) | ForEach-Object { 
                if ($_.PSObject.Properties['name']) { $_.name }
                elseif ($_.PSObject.Properties['referenceName']) { $_.referenceName }
            }
        }
        
        # Filter out nulls and empty strings
        $typeNames = @($typeNames | Where-Object { $_ })
        
        if ($typeNames.Count -gt 0) {
            Write-Host "[INFO] Available work item types in project '$Project': $($typeNames -join ', ')" -ForegroundColor Cyan
            return $typeNames
        } else {
            throw "No work item types found in response"
        }
    }
    catch {
        Write-Warning "[Get-AdoWorkItemTypes] Failed to get work item types: $_"
        Write-Verbose "[Get-AdoWorkItemTypes] Error details: $($_.Exception.Message)"
        # Return empty array - let caller decide defaults based on process template
        Write-Host "[WARN] Could not detect work item types automatically" -ForegroundColor Yellow
        return @()
    }
}

<#
.SYNOPSIS
    Ensures work item templates exist for a team.

.DESCRIPTION
    Creates standard work item templates with DoR/DoD.
    Automatically detects available work item types and creates appropriate templates.

.PARAMETER Project
    Project name.

.PARAMETER Team
    Team name.

.EXAMPLE
    Ensure-AdoTeamTemplates "MyProject" "MyProject Team"
#>
function Ensure-AdoTeamTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$Team
    )
    
    # Wait longer for project to fully initialize work item types after creation
    Write-Host "[INFO] Waiting 10 seconds for project work item types to initialize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Get project details to determine process template
    Write-Host "[INFO] Detecting process template for project '$Project'..." -ForegroundColor Cyan
    $projDetails = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))?includeCapabilities=true"
    $processTemplate = Get-AdoProjectProcessTemplate -ProjectId $projDetails.id
    
    # Determine work item types based on process template
    $availableTypes = switch ($processTemplate) {
        'Agile' {
            @('User Story', 'Task', 'Bug', 'Epic', 'Feature', 'Test Case')
        }
        'Scrum' {
            @('Product Backlog Item', 'Task', 'Bug', 'Epic', 'Feature', 'Test Case', 'Impediment')
        }
        'CMMI' {
            @('Requirement', 'Task', 'Bug', 'Epic', 'Feature', 'Test Case', 'Issue', 'Risk', 'Review', 'Change Request')
        }
        'Basic' {
            @('Issue', 'Task', 'Epic')
        }
        default {
            # Unknown - try detection, fallback to common types
            Write-Host "[INFO] Unknown process template, attempting work item type detection..." -ForegroundColor Yellow
            $detected = Get-AdoWorkItemTypes -Project $Project
            if ($detected -and $detected.Count -gt 0) {
                $detected
            } else {
                # Last resort: include all common types
                @('User Story', 'Product Backlog Item', 'Task', 'Bug', 'Epic', 'Feature', 'Test Case', 'Issue', 'Requirement')
            }
        }
    }
    
    Write-Host "[INFO] Using work item types for $processTemplate template: $($availableTypes -join ', ')" -ForegroundColor Green
    
    # Determine which story type to use based on process template
    $storyType = switch ($processTemplate) {
        'Agile' { 'User Story' }
        'Scrum' { 'Product Backlog Item' }
        'CMMI' { 'Requirement' }
        'Basic' { 'Issue' }
        default {
            # Fallback: try to find any story-like type
            if ($availableTypes -contains 'User Story') {
                'User Story'
            } elseif ($availableTypes -contains 'Product Backlog Item') {
                'Product Backlog Item'
            } elseif ($availableTypes -contains 'Requirement') {
                'Requirement'
            } elseif ($availableTypes -contains 'Issue') {
                'Issue'
            } else {
                $null
            }
        }
    }
    
    $base = "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/wit/templates"
    
    try {
        $existing = Invoke-AdoRest GET $base
        $byName = @{}
        $existing.value | ForEach-Object { $byName[$_.name] = $_ }
    }
    catch {
        Write-Warning "Unable to retrieve existing templates: $_"
        $byName = @{}
    }
    
    # Define comprehensive work item templates for all Agile types
    $templateDefinitions = @{
        'User Story' = @{
            name = 'User Story – DoR/DoD'
            description = 'User Story template with acceptance criteria and DoR/DoD checklists'
            fields = @{
                'System.Title' = 'As a <role>, I want <capability> so that <outcome>'
                'System.Description' = @"
<h2>User Story Context</h2>
<p><strong>Business Value:</strong> Why is this story important?</p>
<p><strong>Assumptions:</strong> What assumptions are we making?</p>

<h2>Definition of Ready</h2>
<ul>
<li>☐ Story is well-defined and understood</li>
<li>☐ Acceptance criteria are clear and testable</li>
<li>☐ Dependencies identified and resolved</li>
<li>☐ Story is appropriately sized (fits in one sprint)</li>
<li>☐ UI/UX designs available (if applicable)</li>
</ul>

<h2>Definition of Done</h2>
<ul>
<li>☐ Code is complete and peer reviewed</li>
<li>☐ Unit tests written and passing</li>
<li>☐ Integration tests passing</li>
<li>☐ Documentation updated</li>
<li>☐ Deployed to test environment</li>
<li>☐ Acceptance criteria verified</li>
<li>☐ Product Owner acceptance</li>
</ul>
"@
                'Microsoft.VSTS.Common.AcceptanceCriteria' = @"
<p><strong>Scenario 1:</strong> Happy path</p>
<ul>
<li><strong>Given</strong> I am a &lt;user type&gt;</li>
<li><strong>When</strong> I &lt;action&gt;</li>
<li><strong>Then</strong> I should &lt;expected result&gt;</li>
</ul>

<p><strong>Scenario 2:</strong> Edge case</p>
<ul>
<li><strong>Given</strong> &lt;precondition&gt;</li>
<li><strong>When</strong> &lt;action&gt;</li>
<li><strong>Then</strong> &lt;expected result&gt;</li>
</ul>
"@
                'Microsoft.VSTS.Common.Priority' = 2
                'Microsoft.VSTS.Scheduling.StoryPoints' = 3
                'System.Tags' = 'template;user-story;team-standard'
            }
        }
        
        'Task' = @{
            name = 'Task – Implementation'
            description = 'Development task template with implementation checklist'
            fields = @{
                'System.Title' = '[TASK] <brief description of work>'
                'System.Description' = @"
<h2>Task Description</h2>
<p><strong>Objective:</strong> What needs to be accomplished?</p>
<p><strong>Technical Approach:</strong> Brief overview of implementation approach</p>

<h2>Implementation Checklist</h2>
<ul>
<li>☐ Design approach reviewed</li>
<li>☐ Implementation completed</li>
<li>☐ Code follows team standards</li>
<li>☐ Unit tests written and passing</li>
<li>☐ Code reviewed and approved</li>
<li>☐ Documentation updated</li>
<li>☐ Integration testing completed</li>
</ul>

<h2>Dependencies</h2>
<ul>
<li><strong>Depends on:</strong> &lt;list any blocking work items&gt;</li>
<li><strong>Blocks:</strong> &lt;list any work items waiting on this&gt;</li>
</ul>

<h2>Acceptance Criteria</h2>
<ul>
<li>☐ &lt;specific deliverable 1&gt;</li>
<li>☐ &lt;specific deliverable 2&gt;</li>
<li>☐ &lt;specific deliverable 3&gt;</li>
</ul>
"@
                'Microsoft.VSTS.Common.Priority' = 2
                'Microsoft.VSTS.Scheduling.RemainingWork' = 8
                'System.Tags' = 'template;task;implementation'
            }
        }
        
        'Bug' = @{
            name = 'Bug – Triaging & Resolution'
            description = 'Bug template with structured reproduction steps and triage information'
            fields = @{
                'System.Title' = '[BUG] <brief description of the issue>'
                'Microsoft.VSTS.TCM.ReproSteps' = @"
<h2>Environment</h2>
<ul>
<li><strong>Browser/OS:</strong> </li>
<li><strong>Application Version:</strong> </li>
<li><strong>User Role:</strong> </li>
</ul>

<h2>Steps to Reproduce</h2>
<ol>
<li>Navigate to &lt;URL or screen&gt;</li>
<li>Click on &lt;element&gt;</li>
<li>Enter &lt;data&gt;</li>
<li>Observe the result</li>
</ol>

<h2>Expected Behavior</h2>
<p>Describe what should happen</p>

<h2>Actual Behavior</h2>
<p>Describe what actually happens</p>

<h2>Additional Information</h2>
<ul>
<li><strong>Frequency:</strong> Always / Sometimes / Rarely</li>
<li><strong>Impact:</strong> &lt;business impact description&gt;</li>
<li><strong>Workaround:</strong> &lt;any known workarounds&gt;</li>
</ul>
"@
                'Microsoft.VSTS.Common.Severity' = '3 - Medium'
                'Microsoft.VSTS.Common.Priority' = 2
                'System.Tags' = 'template;bug;triage-needed'
            }
        }
        
        'Epic' = @{
            name = 'Epic – Strategic Initiative'
            description = 'Epic template for large strategic initiatives with success metrics'
            fields = @{
                'System.Title' = '[EPIC] <strategic initiative name>'
                'System.Description' = @"
<h2>Epic Overview</h2>
<p><strong>Business Objective:</strong> High-level business goal this epic addresses</p>

<p><strong>Success Metrics:</strong> How will we measure success?</p>
<ul>
<li>Metric 1: &lt;measurable outcome&gt;</li>
<li>Metric 2: &lt;measurable outcome&gt;</li>
</ul>

<h2>Scope &amp; Features</h2>
<h3>In Scope</h3>
<ul>
<li>Feature 1: &lt;description&gt;</li>
<li>Feature 2: &lt;description&gt;</li>
</ul>

<h3>Out of Scope</h3>
<ul>
<li>&lt;what's explicitly not included&gt;</li>
</ul>

<h2>Dependencies &amp; Risks</h2>
<h3>Dependencies</h3>
<ul>
<li>External dependency 1</li>
<li>Internal dependency 2</li>
</ul>

<h3>Risks</h3>
<ul>
<li>Risk 1: &lt;description and mitigation&gt;</li>
<li>Risk 2: &lt;description and mitigation&gt;</li>
</ul>

<h2>Timeline &amp; Milestones</h2>
<ul>
<li><strong>Phase 1:</strong> &lt;milestone&gt; - &lt;target date&gt;</li>
<li><strong>Phase 2:</strong> &lt;milestone&gt; - &lt;target date&gt;</li>
<li><strong>Go Live:</strong> &lt;target date&gt;</li>
</ul>
"@
                'Microsoft.VSTS.Common.Priority' = 1
                'Microsoft.VSTS.Scheduling.Effort' = 20
                'System.Tags' = 'template;epic;strategic;roadmap'
            }
        }
        
        'Feature' = @{
            name = 'Feature – Product Capability'
            description = 'Feature template for product capabilities with user value'
            fields = @{
                'System.Title' = '[FEATURE] <feature name>'
                'System.Description' = @"
<h2>Feature Summary</h2>
<p><strong>User Value:</strong> What value does this feature provide to users?</p>
<p><strong>Target Users:</strong> Who will use this feature?</p>

<h2>Functional Requirements</h2>
<h3>Core Capabilities</h3>
<ul>
<li>Capability 1: &lt;description&gt;</li>
<li>Capability 2: &lt;description&gt;</li>
</ul>

<h3>User Experience</h3>
<ul>
<li>&lt;key UX considerations&gt;</li>
</ul>

<h2>Technical Requirements</h2>
<h3>Performance</h3>
<ul>
<li>Response time: &lt;requirement&gt;</li>
<li>Capacity: &lt;requirement&gt;</li>
</ul>

<h3>Security</h3>
<ul>
<li>Authentication: &lt;requirements&gt;</li>
<li>Authorization: &lt;requirements&gt;</li>
</ul>

<h2>Success Criteria</h2>
<ul>
<li>☐ Feature delivers intended user value</li>
<li>☐ Performance requirements met</li>
<li>☐ Security requirements satisfied</li>
<li>☐ User acceptance testing passed</li>
</ul>

<h2>Child Stories</h2>
<p>Link related User Stories here</p>
"@
                'Microsoft.VSTS.Common.Priority' = 2
                'Microsoft.VSTS.Scheduling.Effort' = 13
                'System.Tags' = 'template;feature;product;capability'
            }
        }
        
        'Test Case' = @{
            name = 'Test Case – Quality Validation'
            description = 'Test case template with structured test steps and validation criteria'
            fields = @{
                'System.Title' = '[TEST] <test scenario name>'
                'System.Description' = @"
<h2>Test Objective</h2>
<p><strong>Purpose:</strong> What are we validating with this test?</p>
<p><strong>Test Type:</strong> Unit / Integration / System / User Acceptance</p>

<h2>Prerequisites</h2>
<ul>
<li>Precondition 1</li>
<li>Precondition 2</li>
</ul>

<h2>Test Data Requirements</h2>
<ul>
<li>Data set 1: &lt;description&gt;</li>
<li>Data set 2: &lt;description&gt;</li>
</ul>

<h2>Expected Results</h2>
<p><strong>Success Criteria:</strong></p>
<ul>
<li>Result 1: &lt;expected outcome&gt;</li>
<li>Result 2: &lt;expected outcome&gt;</li>
</ul>

<h2>Test Environment</h2>
<ul>
<li>Environment: &lt;Dev/Test/Staging&gt;</li>
<li>Configuration: &lt;any special setup&gt;</li>
</ul>
"@
                'Microsoft.VSTS.TCM.Steps' = @"
<steps id="0" last="2">
  <step id="2" type="ValidateStep">
    <parameterizedString isformatted="true">
      <DIV><P>1. &lt;action description&gt;</P></DIV>
    </parameterizedString>
    <parameterizedString isformatted="true">
      <DIV><P>&lt;expected result&gt;</P></DIV>
    </parameterizedString>
    <description/>
  </step>
</steps>
"@
                'Microsoft.VSTS.Common.Priority' = 2
                'System.Tags' = 'template;test-case;quality'
            }
        }
    }
    
    # Create templates for all available work item types
    $createdCount = 0
    $skippedCount = 0
    
    Write-Host "[INFO] Creating work item templates for $processTemplate process..." -ForegroundColor Cyan
    Write-Verbose "[Ensure-AdoTeamTemplates] Available types in project: $($availableTypes -join ', ')"
    Write-Verbose "[Ensure-AdoTeamTemplates] Template API endpoint: $base"
    
    foreach ($workItemType in $availableTypes) {
        if ($templateDefinitions.ContainsKey($workItemType)) {
            $template = $templateDefinitions[$workItemType]
            
            # Check if template already exists
            if (-not $byName.ContainsKey($template.name)) {
                Write-Host "[INFO] Creating $workItemType template..." -ForegroundColor Cyan
                
                try {
                    $templateBody = @{
                        name = $template.name
                        description = $template.description
                        workItemTypeName = $workItemType
                        fields = $template.fields
                    }
                    
                    Write-Verbose "[Ensure-AdoTeamTemplates] Creating template: $($template.name)"
                    Write-Verbose "[Ensure-AdoTeamTemplates] Template body: $($templateBody | ConvertTo-Json -Depth 5)"
                    
                    Invoke-AdoRest POST $base -Body $templateBody | Out-Null
                    Write-Host "[SUCCESS] Created $workItemType template: $($template.name)" -ForegroundColor Green
                    $createdCount++
                }
                catch {
                    Write-Warning "Failed to create $workItemType template: $_"
                    Write-Verbose "[AzureDevOps] Error details: $($_.Exception.Message)"
                    if ($_.Exception.Response) {
                        Write-Verbose "[AzureDevOps] HTTP Status: $($_.Exception.Response.StatusCode)"
                    }
                }
            }
            else {
                Write-Host "[INFO] $workItemType template already exists: $($template.name)" -ForegroundColor Gray
                $skippedCount++
            }
        }
        else {
            Write-Host "[INFO] No template defined for work item type: $workItemType" -ForegroundColor Yellow
        }
    }
    
    # Note: Setting templates as defaults via API is not supported
    # Templates can be set as default manually through Azure DevOps UI
    # The templates are still created and usable - they just won't auto-populate
    Write-Verbose "[Ensure-AdoTeamTemplates] Templates created successfully"
    Write-Verbose "[Ensure-AdoTeamTemplates] Note: Setting templates as default requires manual configuration in Azure DevOps UI"
    
    # Summary with actionable guidance
    Write-Host ""
    Write-Host "[INFO] Work item template configuration summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount templates" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount templates (already exist)" -ForegroundColor Yellow
    }
    Write-Host "  📋 Available work item types: $($availableTypes -join ', ')" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] ✨ Templates are ready to use!" -ForegroundColor Green
    Write-Host ""
    Write-Host "[NEXT STEPS] To make templates auto-populate when creating work items:" -ForegroundColor Cyan
    Write-Host "  1. Navigate to: $script:AdoBaseUrl/$([uri]::EscapeDataString($Project))/_settings/work-items" -ForegroundColor White
    Write-Host "  2. Select the work item type (e.g., 'User Story', 'Task', 'Bug')" -ForegroundColor White
    Write-Host "  3. Find the template in the list" -ForegroundColor White
    Write-Host "  4. Click the ⋮ (actions menu) → 'Set as default'" -ForegroundColor White
    Write-Host "  5. Repeat for each work item type" -ForegroundColor White
    Write-Host ""
    Write-Host "[NOTE] Setting templates as default is not available via API - manual configuration required" -ForegroundColor Yellow
    Write-Host "[TIP] Set defaults for most-used types first: User Story, Task, Bug" -ForegroundColor Gray
}

<#
.SYNOPSIS
    Creates sprint iterations for a team.

.DESCRIPTION
    Auto-creates a specified number of 2-week sprint iterations starting from today.
    Configures proper start/finish dates and assigns to team. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Team
    Team name (optional, defaults to "<Project> Team").

.PARAMETER SprintCount
    Number of sprints to create (default: 6).

.PARAMETER SprintDurationDays
    Duration of each sprint in days (default: 14).

.PARAMETER StartDate
    Start date for first sprint (default: next Monday).

.OUTPUTS
    Array of created iteration objects.

.EXAMPLE
    Ensure-AdoIterations "MyProject"

.EXAMPLE
    Ensure-AdoIterations "MyProject" -SprintCount 8 -SprintDurationDays 10
#>
function Ensure-AdoIterations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team",
        
        [int]$SprintCount = 6,
        
        [int]$SprintDurationDays = 14,
        
        [DateTime]$StartDate
    )
    
    Write-Host "[INFO] Setting up sprint iterations..." -ForegroundColor Cyan
    
    # Calculate start date: next Monday if not specified
    if (-not $StartDate) {
        $StartDate = Get-Date
        $daysUntilMonday = (8 - [int]$StartDate.DayOfWeek) % 7
        if ($daysUntilMonday -eq 0 -and $StartDate.DayOfWeek -ne [DayOfWeek]::Monday) {
            $daysUntilMonday = 7
        }
        $StartDate = $StartDate.AddDays($daysUntilMonday).Date
    }
    
    # Get existing iterations
    $existingIterations = @()
    try {
        $response = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/work/teamsettings/iterations?``$timeframe=current"
        if ($response -and $response.value) {
            $existingIterations = $response.value.name
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoIterations] Could not retrieve existing iterations: $_"
    }
    
    $createdCount = 0
    $skippedCount = 0
    $iterations = @()
    
    for ($i = 1; $i -le $SprintCount; $i++) {
        $sprintName = "Sprint $i"
        $sprintStart = $StartDate.AddDays(($i - 1) * $SprintDurationDays)
        $sprintEnd = $sprintStart.AddDays($SprintDurationDays - 1).AddHours(23).AddMinutes(59).AddSeconds(59)
        
        # Check if iteration already exists
        if ($existingIterations -contains $sprintName) {
            Write-Host "[INFO] Sprint '$sprintName' already exists" -ForegroundColor Gray
            $skippedCount++
            continue
        }
        
        try {
            # Create iteration at project level
            $iterationBody = @{
                name = $sprintName
                attributes = @{
                    startDate = $sprintStart.ToString("yyyy-MM-ddTHH:mm:ssZ")
                    finishDate = $sprintEnd.ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
            }
            
            Write-Verbose "[Ensure-AdoIterations] Creating iteration: $sprintName ($($sprintStart.ToString('yyyy-MM-dd')) to $($sprintEnd.ToString('yyyy-MM-dd')))"
            $iteration = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations" -Body $iterationBody
            
            # Assign iteration to team
            try {
                $teamIterationBody = @{
                    id = $iteration.identifier
                }
                Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings/iterations" -Body $teamIterationBody | Out-Null
                Write-Host "[SUCCESS] Created '$sprintName' ($($sprintStart.ToString('MMM dd')) - $($sprintEnd.ToString('MMM dd, yyyy')))" -ForegroundColor Green
            }
            catch {
                Write-Warning "Created iteration but failed to assign to team: $_"
                Write-Host "[SUCCESS] Created '$sprintName' (not assigned to team)" -ForegroundColor Yellow
            }
            
            $iterations += $iteration
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create iteration '$sprintName': $_"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Sprint iteration summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount sprints" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount sprints (already exist)" -ForegroundColor Yellow
    }
    Write-Host "  📅 Sprint duration: $SprintDurationDays days" -ForegroundColor Gray
    Write-Host "  📆 First sprint starts: $($StartDate.ToString('MMM dd, yyyy'))" -ForegroundColor Gray
    
    return $iterations
}

<#
.SYNOPSIS
    Creates shared work item queries for common scenarios.

.DESCRIPTION
    Creates 5 essential queries: My Active Work, Team Backlog, Active Bugs,
    Ready for Review, Blocked Items. Places them in "Shared Queries" folder. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Team
    Team name (optional, defaults to "<Project> Team").

.OUTPUTS
    Array of created query objects.

.EXAMPLE
    Ensure-AdoSharedQueries "MyProject"
#>
function Ensure-AdoSharedQueries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Creating shared work item queries..." -ForegroundColor Cyan
    
    # Get project details to get team ID
    $projDetails = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))"
    $projectId = $projDetails.id
    
    # Define queries
    $queries = @(
        @{
            name = "My Active Work"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo], [System.Tags] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.AssignedTo] = @Me AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [System.ChangedDate] DESC"
        },
        @{
            name = "Team Backlog"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.CreatedDate] DESC"
        },
        @{
            name = "Active Bugs"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Common.Severity], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Common.Severity] ASC, [Microsoft.VSTS.Common.Priority] ASC"
        },
        @{
            name = "Ready for Review"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND ([System.State] = 'Ready for Review' OR [System.State] = 'Resolved' OR [System.Tags] CONTAINS 'needs-review') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            name = "Blocked Items"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo], [System.Tags] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND ([System.Tags] CONTAINS 'blocked' OR [System.Tags] CONTAINS 'impediment') AND [System.State] <> 'Closed' ORDER BY [System.CreatedDate] DESC"
        }
    )
    
    # Check existing queries
    $existingQueries = @{}
    try {
        $response = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?``$depth=1"
        if ($response -and $response.children) {
            $response.children | ForEach-Object { $existingQueries[$_.name] = $_ }
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoSharedQueries] Could not retrieve existing queries: $_"
    }
    
    $createdCount = 0
    $skippedCount = 0
    $createdQueries = @()
    
    foreach ($queryDef in $queries) {
        if ($existingQueries.ContainsKey($queryDef.name)) {
            Write-Host "[INFO] Query '$($queryDef.name)' already exists" -ForegroundColor Gray
            $skippedCount++
            continue
        }
        
        try {
            $queryBody = @{
                name = $queryDef.name
                wiql = $queryDef.wiql
            }
            
            Write-Verbose "[Ensure-AdoSharedQueries] Creating query: $($queryDef.name)"
            $query = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" -Body $queryBody
            Write-Host "[SUCCESS] Created query: $($queryDef.name)" -ForegroundColor Green
            $createdQueries += $query
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create query '$($queryDef.name)': $_"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Shared queries summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount queries" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount queries (already exist)" -ForegroundColor Yellow
    }
    Write-Host "  📂 Location: Shared Queries folder" -ForegroundColor Gray
    
    return $createdQueries
}

<#
.SYNOPSIS
    Creates a test plan with test suites for QA team.

.DESCRIPTION
    Creates a test plan with 4 standard test suites: Regression, Smoke, Integration, and UAT.
    Links to current sprint iteration. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Name
    Test plan name (optional, defaults to "<Project> - Test Plan").

.PARAMETER Iteration
    Iteration path (optional, defaults to current sprint).

.OUTPUTS
    Test plan object with created suites.

.EXAMPLE
    Ensure-AdoTestPlan "MyProject"

.EXAMPLE
    Ensure-AdoTestPlan "MyProject" -Name "Sprint 1 Testing" -Iteration "MyProject\Sprint 1"
#>
function Ensure-AdoTestPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Name,
        
        [string]$Iteration
    )
    
    Write-Host "[INFO] Setting up test plan and test suites..." -ForegroundColor Cyan
    
    # Get project details
    $projDetails = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))?includeCapabilities=true"
    $projectId = $projDetails.id
    $areaPath = $Project
    
    # Default test plan name if not provided
    if (-not $Name) {
        $Name = "$Project - Test Plan"
    }
    
    # Get current iteration if not specified
    if (-not $Iteration) {
        try {
            $teamName = "$Project Team"
            $teamIterations = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($teamName))/_apis/work/teamsettings/iterations?``$timeframe=current"
            if ($teamIterations -and $teamIterations.value -and $teamIterations.value.Count -gt 0) {
                $Iteration = $teamIterations.value[0].path
                Write-Verbose "[Ensure-AdoTestPlan] Using current iteration: $Iteration"
            } else {
                # Fallback to project root iteration
                $Iteration = $Project
                Write-Verbose "[Ensure-AdoTestPlan] No current iteration found, using project root: $Iteration"
            }
        }
        catch {
            $Iteration = $Project
            Write-Verbose "[Ensure-AdoTestPlan] Error getting current iteration, using project root: $Iteration"
        }
    }
    
    # Check if test plan already exists
    $existingPlans = @()
    try {
        $plansResponse = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/testplan/plans"
        if ($plansResponse -and $plansResponse.value) {
            $existingPlans = $plansResponse.value | Where-Object { $_.name -eq $Name }
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoTestPlan] Could not retrieve existing test plans: $_"
    }
    
    $testPlan = $null
    if ($existingPlans -and $existingPlans.Count -gt 0) {
        $testPlan = $existingPlans[0]
        Write-Host "[INFO] Test plan '$Name' already exists (ID: $($testPlan.id))" -ForegroundColor Gray
    }
    else {
        # Create test plan
        Write-Host "[INFO] Creating test plan '$Name'..." -ForegroundColor Cyan
        
        try {
            $testPlanBody = @{
                name = $Name
                areaPath = $areaPath
                iteration = $Iteration
                state = "Active"
            }
            
            Write-Verbose "[Ensure-AdoTestPlan] Creating test plan with body: $($testPlanBody | ConvertTo-Json -Depth 5)"
            $testPlan = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/testplan/plans" -Body $testPlanBody
            Write-Host "[SUCCESS] Created test plan '$Name' (ID: $($testPlan.id))" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to create test plan: $_"
            throw
        }
    }
    
    # Define test suites to create
    $suiteDefinitions = @(
        @{
            name = "Regression Testing"
            description = "Comprehensive regression test suite to ensure existing functionality remains intact"
        },
        @{
            name = "Smoke Testing"
            description = "Critical path smoke tests to verify basic functionality"
        },
        @{
            name = "Integration Testing"
            description = "End-to-end integration tests across system components"
        },
        @{
            name = "User Acceptance Testing (UAT)"
            description = "User acceptance tests to validate business requirements"
        }
    )
    
    # Get existing test suites for this plan
    $existingSuites = @{}
    try {
        $suitesResponse = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/testplan/plans/$($testPlan.id)/suites"
        if ($suitesResponse -and $suitesResponse.value) {
            $suitesResponse.value | ForEach-Object { $existingSuites[$_.name] = $_ }
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoTestPlan] Could not retrieve existing test suites: $_"
    }
    
    $createdCount = 0
    $skippedCount = 0
    $createdSuites = @()
    
    # Create test suites under root suite
    $rootSuiteId = $testPlan.rootSuite.id
    
    foreach ($suiteDef in $suiteDefinitions) {
        if ($existingSuites.ContainsKey($suiteDef.name)) {
            Write-Host "[INFO] Test suite '$($suiteDef.name)' already exists" -ForegroundColor Gray
            $skippedCount++
            $createdSuites += $existingSuites[$suiteDef.name]
            continue
        }
        
        try {
            Write-Host "[INFO] Creating test suite '$($suiteDef.name)'..." -ForegroundColor Cyan
            
            $suiteBody = @{
                suiteType = "staticTestSuite"
                name = $suiteDef.name
                parentSuite = @{ id = $rootSuiteId }
                inheritDefaultConfigurations = $true
            }
            
            Write-Verbose "[Ensure-AdoTestPlan] Creating suite: $($suiteDef.name)"
            $suite = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/testplan/plans/$($testPlan.id)/suites" -Body $suiteBody
            Write-Host "[SUCCESS] Created test suite '$($suiteDef.name)' (ID: $($suite.id))" -ForegroundColor Green
            $createdSuites += $suite
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create test suite '$($suiteDef.name)': $_"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Test plan configuration summary:" -ForegroundColor Cyan
    Write-Host "  📋 Test Plan: $Name (ID: $($testPlan.id))" -ForegroundColor White
    Write-Host "  📍 Iteration: $Iteration" -ForegroundColor Gray
    Write-Host "  ✅ Created: $createdCount test suites" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount test suites (already exist)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "[INFO] Test suites available:" -ForegroundColor Cyan
    foreach ($suite in $createdSuites) {
        Write-Host "  • $($suite.name)" -ForegroundColor Gray
    }
    
    return @{
        plan = $testPlan
        suites = $createdSuites
    }
}

<#
.SYNOPSIS
    Creates QA-specific work item queries.

.DESCRIPTION
    Creates 8 QA-focused queries: Test Execution Status, Bugs by Severity, Bugs by Priority,
    Test Coverage, Failed Test Cases, Regression Candidates, Bug Triage, Reopened Bugs.
    Places them in "Shared Queries/QA" folder. Idempotent.

.PARAMETER Project
    Project name.

.OUTPUTS
    Array of created query objects.

.EXAMPLE
    Ensure-AdoQAQueries "MyProject"
#>
function Ensure-AdoQAQueries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )
    
    Write-Host "[INFO] Creating QA-specific work item queries..." -ForegroundColor Cyan
    
    # Define QA queries
    $qaQueries = @(
        @{
            name = "Test Execution Status"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Test Case' ORDER BY [System.State] ASC, [Microsoft.VSTS.Common.Priority] ASC"
        },
        @{
            name = "Bugs by Severity"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Common.Severity], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Common.Severity] ASC, [Microsoft.VSTS.Common.Priority] ASC, [System.CreatedDate] DESC"
        },
        @{
            name = "Bugs by Priority"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Bug' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [Microsoft.VSTS.Common.Severity] ASC, [System.CreatedDate] DESC"
        },
        @{
            name = "Test Coverage"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] IN ('User Story', 'Product Backlog Item', 'Requirement') AND [System.State] <> 'Removed' ORDER BY [System.State] ASC, [System.CreatedDate] DESC"
        },
        @{
            name = "Failed Test Cases"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Test Case' AND [System.State] = 'Failed' ORDER BY [Microsoft.VSTS.Common.Priority] ASC"
        },
        @{
            name = "Regression Candidates"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.ChangedDate] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND ([System.WorkItemType] = 'Bug' AND [System.State] = 'Resolved') OR ([System.Tags] CONTAINS 'regression') ORDER BY [System.ChangedDate] DESC"
        },
        @{
            name = "Bug Triage Queue"
            wiql = "SELECT [System.Id], [System.Title], [System.CreatedDate], [Microsoft.VSTS.Common.Severity], [Microsoft.VSTS.Common.Priority] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Bug' AND [System.State] = 'New' ORDER BY [Microsoft.VSTS.Common.Severity] ASC, [System.CreatedDate] DESC"
        },
        @{
            name = "Reopened Bugs"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Common.Severity], [System.ChangedDate] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Bug' AND [System.State] = 'Active' AND [System.Reason] = 'Regression' ORDER BY [Microsoft.VSTS.Common.Severity] ASC, [System.ChangedDate] DESC"
        }
    )
    
    # Ensure QA folder exists under Shared Queries
    $qaFolderPath = "Shared Queries/QA"
    $qaFolderId = $null
    
    try {
        # Check if QA folder already exists
        $sharedQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?``$depth=2"
        
        if ($sharedQueries -and $sharedQueries.children) {
            $qaFolder = $sharedQueries.children | Where-Object { $_.name -eq "QA" -and $_.isFolder -eq $true }
            if ($qaFolder) {
                $qaFolderId = $qaFolder.id
                Write-Host "[INFO] QA folder already exists" -ForegroundColor Gray
            }
        }
        
        # Create QA folder if it doesn't exist
        if (-not $qaFolderId) {
            Write-Host "[INFO] Creating QA folder under Shared Queries..." -ForegroundColor Cyan
            $folderBody = @{
                name = "QA"
                isFolder = $true
            }
            $qaFolder = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" -Body $folderBody
            $qaFolderId = $qaFolder.id
            Write-Host "[SUCCESS] Created QA folder" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to create/access QA folder: $_"
        # Fall back to Shared Queries root
        $qaFolderId = $null
    }
    
    # Get existing queries in QA folder
    $existingQueries = @{}
    try {
        if ($qaFolderId) {
            $folderQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$qaFolderId?``$depth=1"
            if ($folderQueries -and $folderQueries.children) {
                $folderQueries.children | ForEach-Object { $existingQueries[$_.name] = $_ }
            }
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoQAQueries] Could not retrieve existing queries: $_"
    }
    
    $createdCount = 0
    $skippedCount = 0
    $createdQueries = @()
    
    # Create queries
    $baseEndpoint = if ($qaFolderId) {
        "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$qaFolderId"
    } else {
        "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries"
    }
    
    foreach ($queryDef in $qaQueries) {
        if ($existingQueries.ContainsKey($queryDef.name)) {
            Write-Host "[INFO] Query '$($queryDef.name)' already exists" -ForegroundColor Gray
            $skippedCount++
            $createdQueries += $existingQueries[$queryDef.name]
            continue
        }
        
        try {
            Write-Host "[INFO] Creating query '$($queryDef.name)'..." -ForegroundColor Cyan
            
            $queryBody = @{
                name = $queryDef.name
                wiql = $queryDef.wiql
            }
            
            $query = Invoke-AdoRest POST $baseEndpoint -Body $queryBody
            Write-Host "[SUCCESS] Created query '$($queryDef.name)'" -ForegroundColor Green
            $createdQueries += $query
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create query '$($queryDef.name)': $_"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] QA queries summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount queries" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount queries (already exist)" -ForegroundColor Yellow
    }
    Write-Host "  📂 Location: $qaFolderPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] QA queries available:" -ForegroundColor Cyan
    foreach ($query in $createdQueries) {
        Write-Host "  • $($query.name)" -ForegroundColor Gray
    }
    
    return $createdQueries
}

<#
.SYNOPSIS
    Creates a QA-focused dashboard with test and quality metrics.

.DESCRIPTION
    Creates a comprehensive QA dashboard with test execution metrics, bug tracking,
    test coverage, and quality indicators. Uses query tiles and charts from the
    QA queries created by Ensure-AdoQAQueries. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Team
    Team name (optional, defaults to "<Project> Team").

.OUTPUTS
    Dashboard object with QA widgets.

.EXAMPLE
    Ensure-AdoQADashboard "MyProject"

.EXAMPLE
    Ensure-AdoQADashboard "MyProject" -Team "QA Team"
#>
function Ensure-AdoQADashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Creating QA dashboard..." -ForegroundColor Cyan
    
    # Get team context (optional for fallback)
    $teamId = $null
    try {
        $teamContext = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))/teams/$([uri]::EscapeDataString($Team))"
        $teamId = $teamContext.id
    }
    catch {
        Write-Verbose "[Ensure-AdoQADashboard] Team context not available; will attempt project-level dashboards as fallback. Error: $_"
    }
    
    # Check if QA dashboard already exists
    $dashboardName = "$Team - QA Metrics"
    try {
        $existingDashboards = $null
        if ($teamId) {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Preview
        }
        else {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Preview
        }
        $existing = $existingDashboards.dashboardEntries | Where-Object { $_.name -eq $dashboardName }

        if ($existing) {
            Write-Host "[INFO] QA dashboard '$dashboardName' already exists" -ForegroundColor Gray
            return $existing
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoQADashboard] Could not check existing dashboards: $_"
    }
    
    # Create QA dashboard with test and quality widgets
    try {
        Write-Verbose "[Ensure-AdoQADashboard] Creating QA dashboard: $dashboardName"
        
        $dashboardBody = @{
            name = $dashboardName
            description = "QA metrics dashboard with test execution, bug tracking, and quality indicators"
            widgets = @(
                # Row 1: Test Execution Status (2x2) + Bugs by Severity (2x2)
                @{
                    name = "Test Execution Status"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Test Execution Status","chartType":"pie"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Bugs by Severity"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Bugs by Severity","chartType":"stackBar"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                
                # Row 2: Test Coverage (2x2) + Bugs by Priority (2x2)
                @{
                    name = "Test Coverage"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Test Coverage","chartType":"pie"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Bugs by Priority"
                    position = @{ row = 3; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryName":"QA/Bugs by Priority","chartType":"pivot"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                
                # Row 3: Query Tiles (1x1 each) - Quick metrics
                @{
                    name = "Failed Test Cases"
                    position = @{ row = 5; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Failed Test Cases"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Regression Candidates"
                    position = @{ row = 5; column = 2 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Regression Candidates"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Bug Triage Queue"
                    position = @{ row = 5; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Bug Triage Queue"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Reopened Bugs"
                    position = @{ row = 5; column = 4 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryName":"QA/Reopened Bugs"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                }
            )
            _links = $null
        }
        
        $dashboard = $null
        if ($teamId) {
            try {
                $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
            }
            catch {
                Write-Verbose "[Ensure-AdoQADashboard] Team dashboards API failed, attempting project-level fallback: $_"
            }
        }
        if (-not $dashboard) {
            $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
        }
        
        Write-Host "[SUCCESS] Created QA dashboard: $dashboardName" -ForegroundColor Green
        Write-Host ""
        Write-Host "[INFO] QA dashboard widgets:" -ForegroundColor Cyan
        Write-Host "  🧪 Test Execution Status - Test case states (pie chart)" -ForegroundColor Gray
        Write-Host "  🐛 Bugs by Severity - Critical/High/Medium/Low distribution (stacked bar)" -ForegroundColor Gray
        Write-Host "  📊 Test Coverage - Requirements with test tracking (pie chart)" -ForegroundColor Gray
        Write-Host "  📈 Bugs by Priority - Priority-based bug distribution (pivot table)" -ForegroundColor Gray
        Write-Host "  ❌ Failed Test Cases - Count of failed tests (query tile)" -ForegroundColor Gray
        Write-Host "  🔄 Regression Candidates - Resolved bugs with regression tags (query tile)" -ForegroundColor Gray
        Write-Host "  🎯 Bug Triage Queue - New bugs awaiting triage (query tile)" -ForegroundColor Gray
        Write-Host "  🔁 Reopened Bugs - Regressed/reopened bug count (query tile)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  📍 Location: Dashboards → $dashboardName" -ForegroundColor Gray
        Write-Host "  💡 TIP: Configure chart colors in each widget's settings for better visibility" -ForegroundColor Yellow
        
        return $dashboard
    }
    catch {
        Write-Warning "Failed to create QA dashboard: $_"
        Write-Verbose "[Ensure-AdoQADashboard] Error details: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Creates test configuration variables and configurations for cross-platform testing.

.DESCRIPTION
    Creates test configuration variables (Browser, Operating System, Environment) and
    test configurations combining these variables for comprehensive test coverage.
    Supports browsers (Chrome, Firefox, Safari, Edge), operating systems (Windows, macOS, 
    Linux, iOS, Android), and environments (Dev, Test, Staging, Production).
    Idempotent - checks for existing variables and configurations before creating.

.PARAMETER Project
    Project name.

.OUTPUTS
    Hashtable with two keys:
    - variables: Array of created test variable objects
    - configurations: Array of created test configuration objects

.EXAMPLE
    Ensure-AdoTestConfigurations "MyProject"
    Creates test variables and configurations for the project.
#>
function Ensure-AdoTestConfigurations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )
    
    Write-Host "``n========================================" -ForegroundColor Cyan
    Write-Host "CREATING TEST CONFIGURATIONS" -ForegroundColor Cyan
    Write-Host "========================================``n" -ForegroundColor Cyan
    
    try {
        # Define test variables and their values
        $testVariableDefs = @(
            @{
                Name = "Browser"
                Description = "Web browser for testing"
                Values = @("Chrome", "Firefox", "Safari", "Edge")
            },
            @{
                Name = "Operating System"
                Description = "Operating system platform"
                Values = @("Windows", "macOS", "Linux", "iOS", "Android")
            },
            @{
                Name = "Environment"
                Description = "Deployment environment"
                Values = @("Dev", "Test", "Staging", "Production")
            }
        )
        
        # Get existing test variables
        Write-Host "[INFO] Checking existing test variables..." -ForegroundColor Cyan
        $existingVariables = @{}
        try {
            $variables = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/testplan/variables?api-version=7.1"
            foreach ($var in $variables.value) {
                $existingVariables[$var.name] = $var
            }
            Write-Host "✓ Found $($existingVariables.Count) existing test variable(s)" -ForegroundColor Green
        }
        catch {
            Write-Verbose "[Ensure-AdoTestConfigurations] Could not retrieve existing variables: $_"
        }
        
        # Create test variables
        $createdVariables = @()
        foreach ($varDef in $testVariableDefs) {
            if ($existingVariables.ContainsKey($varDef.Name)) {
                Write-Host "  • Test variable '$($varDef.Name)' already exists" -ForegroundColor DarkGray
                $existingVar = $existingVariables[$varDef.Name]

                # Ensure required values exist (merge and update if needed)
                $currentValues = @()
                if ($existingVar.PSObject.Properties['values']) { $currentValues = @($existingVar.values) }
                $missing = @($varDef.Values | Where-Object { $_ -notin $currentValues })
                if ($missing.Count -gt 0) {
                    Write-Host "    ↻ Updating variable '$($varDef.Name)' to add missing values: $($missing -join ', ')" -ForegroundColor Yellow
                    $newValues = @($currentValues + $missing | Select-Object -Unique)
                    $updateBody = @{ name = $existingVar.name; description = $existingVar.description; values = $newValues } | ConvertTo-Json -Depth 10
                    try {
                        $updated = Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/_apis/testplan/variables/$($existingVar.id)?api-version=7.1" -Body $updateBody
                        $existingVar = $updated
                    }
                    catch {
                        Write-Verbose "[Ensure-AdoTestConfigurations] Failed to update variable '$($varDef.Name)': $_"
                    }
                }

                $createdVariables += $existingVar
                continue
            }
            
            Write-Host "  • Creating test variable: $($varDef.Name)..." -ForegroundColor Cyan
            
            $variableBody = @{
                name = $varDef.Name
                description = $varDef.Description
                values = $varDef.Values
            } | ConvertTo-Json -Depth 10
            
            $variable = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/testplan/variables?api-version=7.1" -Body $variableBody
            $createdVariables += $variable
            Write-Host "    ✓ Created with $($varDef.Values.Count) value(s)" -ForegroundColor Green
        }
        
        Write-Host "``n[SUCCESS] Test variables: $($createdVariables.Count) variable(s) configured" -ForegroundColor Green
        
        # Define test configurations (combinations of variables)
        $configurationDefs = @(
            @{ Name = "Chrome on Windows"; Values = @{ Browser = "Chrome"; "Operating System" = "Windows"; Environment = "Test" } },
            @{ Name = "Chrome on macOS"; Values = @{ Browser = "Chrome"; "Operating System" = "macOS"; Environment = "Test" } },
            @{ Name = "Chrome on Linux"; Values = @{ Browser = "Chrome"; "Operating System" = "Linux"; Environment = "Test" } },
            @{ Name = "Firefox on Windows"; Values = @{ Browser = "Firefox"; "Operating System" = "Windows"; Environment = "Test" } },
            @{ Name = "Firefox on macOS"; Values = @{ Browser = "Firefox"; "Operating System" = "macOS"; Environment = "Test" } },
            @{ Name = "Firefox on Linux"; Values = @{ Browser = "Firefox"; "Operating System" = "Linux"; Environment = "Test" } },
            @{ Name = "Safari on macOS"; Values = @{ Browser = "Safari"; "Operating System" = "macOS"; Environment = "Test" } },
            @{ Name = "Safari on iOS"; Values = @{ Browser = "Safari"; "Operating System" = "iOS"; Environment = "Test" } },
            @{ Name = "Edge on Windows"; Values = @{ Browser = "Edge"; "Operating System" = "Windows"; Environment = "Test" } },
            @{ Name = "Chrome on Android"; Values = @{ Browser = "Chrome"; "Operating System" = "Android"; Environment = "Test" } },
            @{ Name = "Dev Environment"; Values = @{ Browser = "Chrome"; "Operating System" = "Windows"; Environment = "Dev" } },
            @{ Name = "Staging Environment"; Values = @{ Browser = "Chrome"; "Operating System" = "Windows"; Environment = "Staging" } },
            @{ Name = "Production Environment"; Values = @{ Browser = "Chrome"; "Operating System" = "Windows"; Environment = "Production" } }
        )
        
        # Get existing test configurations
        Write-Host "``n[INFO] Checking existing test configurations..." -ForegroundColor Cyan
        $existingConfigurations = @{}
        try {
            $configurations = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/testplan/configurations?api-version=7.1"
            foreach ($config in $configurations.value) {
                $existingConfigurations[$config.name] = $config
            }
            Write-Host "✓ Found $($existingConfigurations.Count) existing test configuration(s)" -ForegroundColor Green
        }
        catch {
            Write-Verbose "[Ensure-AdoTestConfigurations] Could not retrieve existing configurations: $_"
        }
        
        # Create test configurations
        $createdConfigurations = @()
        foreach ($configDef in $configurationDefs) {
            if ($existingConfigurations.ContainsKey($configDef.Name)) {
                Write-Host "  • Test configuration '$($configDef.Name)' already exists" -ForegroundColor DarkGray
                $createdConfigurations += $existingConfigurations[$configDef.Name]
                continue
            }
            
            Write-Host "  • Creating test configuration: $($configDef.Name)..." -ForegroundColor Cyan
            
            # Build configuration values array
            $configValues = @()
            foreach ($varName in $configDef.Values.Keys) {
                $varValue = $configDef.Values[$varName]

                # Find the variable ID from created variables
                $variable = $createdVariables | Where-Object { $_.name -eq $varName } | Select-Object -First 1
                if ($variable) {
                    # Validate that the chosen value exists in variable.values; if not, skip this variable for the config
                    $allowed = @()
                    if ($variable.PSObject.Properties['values']) { $allowed = @($variable.values) }
                    if ($allowed -and ($varValue -notin $allowed)) {
                        Write-Verbose "[Ensure-AdoTestConfigurations] Skipping value '$varValue' for variable '$varName' (not in allowed values)"
                        continue
                    }

                    $configValues += @{
                        variable = @{
                            id = $variable.id
                            name = $variable.name
                        }
                        value = $varValue
                    }
                }
            }
            
            $configBody = @{
                name = $configDef.Name
                description = "Test configuration for $($configDef.Name)"
                values = $configValues
                state = "Active"
            } | ConvertTo-Json -Depth 10
            
            $config = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/testplan/configurations?api-version=7.1" -Body $configBody
            $createdConfigurations += $config
            Write-Host "    ✓ Created successfully" -ForegroundColor Green
        }
        
        Write-Host "``n[SUCCESS] Test configurations: $($createdConfigurations.Count) configuration(s) configured" -ForegroundColor Green
        
        # Summary
        Write-Host "``n========================================" -ForegroundColor Green
        Write-Host "TEST CONFIGURATIONS SUMMARY" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✓ Test Variables: $($createdVariables.Count)" -ForegroundColor Green
        Write-Host "  • Browser: Chrome, Firefox, Safari, Edge" -ForegroundColor White
        Write-Host "  • Operating System: Windows, macOS, Linux, iOS, Android" -ForegroundColor White
        Write-Host "  • Environment: Dev, Test, Staging, Production" -ForegroundColor White
        Write-Host "``n✓ Test Configurations: $($createdConfigurations.Count)" -ForegroundColor Green
        Write-Host "  • Browser/OS combinations: 10 configurations" -ForegroundColor White
        Write-Host "  • Environment-specific: 3 configurations" -ForegroundColor White
        Write-Host "========================================``n" -ForegroundColor Green
        
        return @{
            variables = $createdVariables
            configurations = $createdConfigurations
        }
    }
    catch {
        Write-Warning "Failed to create test configurations: $_"
        Write-Verbose "[Ensure-AdoTestConfigurations] Error details: $($_.Exception.Message)"
        return @{
            variables = @()
            configurations = @()
        }
    }
}

<#
.SYNOPSIS
    Creates comprehensive QA guidelines wiki page.

.DESCRIPTION
    Creates a "QA Guidelines" wiki page covering testing standards, QA processes,
    test configuration usage, test plan structure, bug reporting, and quality metrics.
    Includes guidance on using test configurations, dashboards, and queries created by
    Ensure-AdoTestConfigurations, Ensure-AdoTestPlan, Ensure-AdoQAQueries, and Ensure-AdoQADashboard.
    Idempotent - checks if page exists before creating.

.PARAMETER Project
    Project name.

.PARAMETER WikiId
    Wiki ID.

.OUTPUTS
    Wiki page object.

.EXAMPLE
    Ensure-AdoQAGuidelinesWiki "MyProject" "wiki-id-123"
#>
function Ensure-AdoQAGuidelinesWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating QA guidelines wiki page..." -ForegroundColor Cyan
    
    $qaGuidelinesContent = @"
# QA Guidelines & Testing Standards

This guide provides comprehensive testing standards and QA practices for ensuring high-quality software delivery.

---

## 📋 Table of Contents

1. [Testing Strategy](#testing-strategy)
2. [Test Configurations](#test-configurations)
3. [Test Plan Structure](#test-plan-structure)
4. [Writing Test Cases](#writing-test-cases)
5. [Bug Reporting](#bug-reporting)
6. [QA Queries & Dashboards](#qa-queries--dashboards)
7. [Testing Checklist](#testing-checklist)

---

## 🎯 Testing Strategy

### Testing Pyramid

Our testing strategy follows the testing pyramid principle:

**Unit Tests** (70%)
- Fast, isolated tests for individual functions/methods
- Run on every commit
- Owned by developers

**Integration Tests** (20%)
- Test component interactions
- API contract testing
- Database integration
- Run before deployment

**System/UI Tests** (10%)
- End-to-end user scenarios
- Cross-browser testing
- Manual exploratory testing
- Run before release

### Test Types

#### 🔄 Regression Testing
- **Purpose**: Verify existing functionality still works after changes
- **Frequency**: Every sprint
- **Suite**: Test Plans → Regression Suite
- **Priority**: High severity, high usage features

#### 💨 Smoke Testing
- **Purpose**: Validate critical paths work in deployed environment
- **Frequency**: After every deployment
- **Suite**: Test Plans → Smoke Suite
- **Duration**: < 30 minutes

#### 🔗 Integration Testing
- **Purpose**: Verify system components work together
- **Frequency**: Daily (automated), weekly (manual)
- **Suite**: Test Plans → Integration Suite
- **Focus**: API contracts, data flow, service communication

#### ✅ User Acceptance Testing (UAT)
- **Purpose**: Validate business requirements with stakeholders
- **Frequency**: End of sprint
- **Suite**: Test Plans → UAT Suite
- **Participants**: Product Owner, Business Users

---

## 🖥️ Test Configurations

Our project uses **13 predefined test configurations** for comprehensive coverage:

### Browser/OS Combinations (10 configs)

#### Desktop Browsers
- **Chrome on Windows** - Primary configuration (80% users)
- **Chrome on macOS** - Mac users
- **Chrome on Linux** - Developer workstations
- **Firefox on Windows** - Secondary browser
- **Firefox on macOS** - Mac Firefox users
- **Firefox on Linux** - Linux Firefox users
- **Edge on Windows** - Windows native browser
- **Safari on macOS** - Mac native browser

#### Mobile Browsers
- **Safari on iOS** - iPhone/iPad testing
- **Chrome on Android** - Android device testing

### Environment Configurations (3 configs)

- **Dev Environment** - Early integration testing
- **Staging Environment** - Pre-production validation
- **Production Environment** - Production smoke tests

### Using Test Configurations

**Assign configurations to test suites**:
1. Navigate to Test Plans → Your Test Plan
2. Select a test suite
3. Right-click → Assign Configuration
4. Choose appropriate configurations

**Best Practices**:
- ✅ Assign browser configs to UI test suites
- ✅ Assign environment configs to integration/smoke suites
- ✅ Use multiple configs for critical test cases
- ❌ Don't assign all configs to every test (test what matters)

---

## 📚 Test Plan Structure

### Test Plan: \``$Project - Test Plan\``

Our test plan is organized into **4 test suites**:

#### 1. Regression Suite
- **Purpose**: Verify existing functionality
- **Test Cases**: High-priority, stable features
- **Run Frequency**: Every sprint
- **Configurations**: All major browsers (Chrome, Firefox, Edge, Safari)

#### 2. Smoke Suite
- **Purpose**: Critical path validation
- **Test Cases**: Login, core workflows, data access
- **Run Frequency**: After every deployment
- **Configurations**: Chrome on Windows + Production Environment
- **Time Limit**: 30 minutes maximum

#### 3. Integration Suite
- **Purpose**: Component interaction testing
- **Test Cases**: API testing, data flow, service communication
- **Run Frequency**: Daily (automated), weekly (manual)
- **Configurations**: All environments (Dev, Staging, Production)

#### 4. UAT Suite
- **Purpose**: Business acceptance testing
- **Test Cases**: Business scenarios, user workflows
- **Run Frequency**: End of sprint
- **Configurations**: Chrome on Windows + Staging Environment
- **Participants**: Product Owner, Business Users

### Organizing Test Cases

**Naming Convention**:
````````````
[Module] - [Action] - [Expected Result]
Example: [Login] - Valid credentials - User logged in successfully
````````````

**Tags for Test Cases**:
- \``regression\`` - Include in regression suite
- \``smoke\`` - Critical path test
- \``automated\`` - Automated test exists
- \``manual-only\`` - Cannot be automated
- \``blocked\`` - Test is currently blocked

---

## ✍️ Writing Test Cases

### Test Case Template

Use the **Test Case - Quality Validation** template:

**Title Format**: \``[TEST] <scenario name>\``
- ✅ Good: "[TEST] Login with valid credentials"
- ❌ Bad: "test login"

### Test Case Sections

#### 1. Test Objective
- **Purpose**: What are we validating?
- **Test Type**: Unit / Integration / System / UAT

#### 2. Prerequisites
- Environment state before test
- Required data setup
- User permissions needed

#### 3. Test Steps
Write clear, numbered steps:
````````````
1. Navigate to login page
2. Enter username: 'testuser@example.com'
3. Enter password: 'Test123!'
4. Click 'Sign In' button
5. Verify user dashboard displays
````````````

#### 4. Expected Results
- Define success criteria for each step
- Be specific and measurable
- Include screenshots/examples if helpful

#### 5. Test Data
- List required test data
- Include valid and invalid scenarios
- Document edge cases

### Test Case Best Practices

✅ **DO**:
- Write atomic tests (one scenario per test case)
- Use clear, action-oriented language
- Include expected results for each step
- Add screenshots for UI elements
- Link to User Stories (Tested By relationship)
- Assign appropriate configurations

❌ **DON'T**:
- Write vague steps ("Check if it works")
- Skip expected results
- Combine multiple unrelated scenarios
- Assume prior knowledge
- Forget to update tests when features change

---

## 🐛 Bug Reporting

### Bug Template

Use the **Bug - Triaging &amp; Resolution** template:

**Title Format**: \``[BUG] <brief description>\``
- ✅ Good: "[BUG] Login fails with special characters in password"
- ❌ Bad: "login broken"

### Required Bug Information

#### 1. Environment
````````````
Browser/OS: Chrome 118 on Windows 11
Application Version: 2.5.3
User Role: Standard User
````````````

#### 2. Steps to Reproduce
````````````
1. Navigate to https://app.example.com/login
2. Enter username: 'test@example.com'
3. Enter password containing special chars: 'P@ssw0rd!'
4. Click 'Sign In'
5. Observe error message
````````````

#### 3. Expected vs Actual Behavior
- **Expected**: User successfully logs in
- **Actual**: Error message: "Invalid credentials"

#### 4. Additional Information
- **Frequency**: Always reproducible
- **Impact**: Users cannot log in (critical)
- **Workaround**: Use password without special characters
- **Attachments**: Screenshots, logs, network traces

### Bug Severity Guidelines

**Critical (P0)** - Fix immediately
- Complete system/feature failure
- Data loss or corruption
- Security vulnerability
- No workaround available

**High (P1)** - Fix in current sprint
- Major feature broken
- Significant functionality impaired
- Workaround exists but difficult
- Affects many users

**Medium (P2)** - Fix in next sprint
- Minor feature issue
- Cosmetic problems affecting usability
- Easy workaround available
- Affects some users

**Low (P3)** - Fix when time permits
- Cosmetic issues
- Rare edge cases
- Enhancement requests
- Minimal user impact

### Bug Lifecycle

1. **New** → Triage needed
2. **Active** → Assigned to developer
3. **Resolved** → Fixed, ready for QA verification
4. **Closed** → QA verified fix
5. **Reopened** → Issue persists (back to Active)

**Triaging Tags**:
- \``triage-needed\`` - Needs severity/priority assignment
- \``needs-repro\`` - Cannot reproduce, needs more info
- \``regression\`` - Previously working feature broke
- \``known-issue\`` - Documented limitation

---

## 📊 QA Queries &amp; Dashboards

### Available QA Queries

Navigate to **Queries → Shared Queries → QA** folder:

#### 1. Test Execution Status
- Shows test case execution progress
- Groups by outcome (Passed, Failed, Blocked, Not Run)
- Use for sprint QA status reporting

#### 2. Bugs by Severity
- Lists active bugs grouped by severity
- Use for triaging and prioritization
- Critical bugs should be addressed first

#### 3. Bugs by Priority
- Lists active bugs grouped by priority
- Use for sprint planning
- P0/P1 bugs block release

#### 4. Test Coverage
- Shows User Stories with/without test cases
- Use to identify gaps in test coverage
- Goal: 80%+ stories have test cases

#### 5. Failed Test Cases
- Lists all failed test cases
- Use for daily QA standup
- Requires immediate investigation

#### 6. Regression Candidates
- Test cases not run in last 30 days
- Use to plan regression testing
- Update stale test cases

#### 7. Bug Triage Queue
- New/unassigned bugs needing triage
- Use in bug triage meetings
- Assign severity, priority, owner

#### 8. Reopened Bugs
- Bugs that failed verification
- Use to track quality issues
- Requires root cause analysis

### QA Dashboard

Navigate to **Dashboards → <Team> - QA Metrics**:

**Row 1: Test Execution Overview**
- **Test Execution Status** (Pie Chart) - Pass/Fail distribution
- **Bugs by Severity** (Stacked Bar) - Bug severity trends

**Row 2: Bug Analysis**
- **Test Coverage** (Pie Chart) - Coverage percentage
- **Bugs by Priority** (Pivot Table) - Priority distribution

**Row 3: Action Items** (Tiles)
- **Failed Test Cases** - Count requiring investigation
- **Regression Candidates** - Count needing execution
- **Bug Triage Queue** - Count needing assignment
- **Reopened Bugs** - Count needing analysis

**Dashboard Best Practices**:
- Review daily during standup
- Track trends over sprints
- Set goals (e.g., <5% test failure rate)
- Address anomalies immediately

---

## ✅ Testing Checklist

### Before Starting Testing

- [ ] Review User Story acceptance criteria
- [ ] Verify test environment is available
- [ ] Prepare test data
- [ ] Check test configurations assigned
- [ ] Review related test cases

### During Testing

- [ ] Execute test steps sequentially
- [ ] Document actual results for each step
- [ ] Capture screenshots for failures
- [ ] Mark step outcomes (Pass/Fail)
- [ ] Log defects immediately
- [ ] Link bugs to test cases

### After Testing

- [ ] Update test case results
- [ ] Verify all test steps executed
- [ ] Update QA queries/dashboard
- [ ] Report status to team
- [ ] Identify blocked tests
- [ ] Plan next testing iteration

### Before Release

- [ ] All smoke tests passed
- [ ] No open P0/P1 bugs
- [ ] Regression suite executed
- [ ] UAT sign-off received
- [ ] Test results documented
- [ ] Known issues documented in release notes

---

## 🎓 QA Resources

### Training Materials

- **Azure Test Plans Documentation**: [Learn Test Plans](https://learn.microsoft.com/en-us/azure/devops/test/)
- **Test Configuration Guide**: Test Plans → Configurations
- **Work Item Query Language (WIQL)**: [WIQL Reference](https://learn.microsoft.com/en-us/azure/devops/boards/queries/wiql-syntax)

### Team Contacts

- **QA Lead**: <Assign QA Lead>
- **Test Automation**: <Assign Automation Lead>
- **Product Owner**: <Assign PO>

### Support

- **Questions**: Use team chat or email QA Lead
- **Tool Issues**: Create Bug work item with tag \``qa-tooling\``
- **Process Improvements**: Discuss in retrospectives

---

*Last Updated: $(Get-Date -Format 'yyyy-MM-dd')*
*Version: 1.0*
"@

    try {
        # Check if page exists
        try {
            $existingPage = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?path=/QA-Guidelines"
            Write-Host "[INFO] QA Guidelines page already exists" -ForegroundColor Gray
            return $existingPage
        }
        catch {
            # Page doesn't exist, create it
            Write-Verbose "[Ensure-AdoQAGuidelinesWiki] Creating QA Guidelines page"
            $page = Upsert-AdoWikiPage $Project $WikiId "/QA-Guidelines" $qaGuidelinesContent
            Write-Host "[SUCCESS] Created QA Guidelines wiki page" -ForegroundColor Green
            Write-Host ""
            Write-Host "[INFO] QA Guidelines documented:" -ForegroundColor Cyan
            Write-Host "  📋 Testing Strategy: Unit, Integration, System/UI testing" -ForegroundColor Gray
            Write-Host "  🖥️ Test Configurations: 13 browser/OS/environment configs" -ForegroundColor Gray
            Write-Host "  📚 Test Plan Structure: 4 suites (Regression, Smoke, Integration, UAT)" -ForegroundColor Gray
            Write-Host "  ✍️ Writing Test Cases: Templates and best practices" -ForegroundColor Gray
            Write-Host "  🐛 Bug Reporting: Severity guidelines and lifecycle" -ForegroundColor Gray
            Write-Host "  📊 QA Queries & Dashboards: 8 queries and metrics dashboard" -ForegroundColor Gray
            Write-Host "  ✅ Testing Checklist: Pre/during/post testing activities" -ForegroundColor Gray
            Write-Host "  📂 Location: Project Wiki → QA-Guidelines" -ForegroundColor Gray
            
            return $page
        }
    }
    catch {
        Write-Warning "Failed to create QA Guidelines page: $_"
        Write-Verbose "[Ensure-AdoQAGuidelinesWiki] Error details: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Creates repository template files (README.md and PR template).

.DESCRIPTION
    Adds starter README.md and .azuredevops/pull_request_template.md to repository.
    Handles existing files gracefully. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER RepoId
    Repository ID.

.PARAMETER RepoName
    Repository name (used in README).

.OUTPUTS
    Array of created file objects.

.EXAMPLE
    Ensure-AdoRepositoryTemplates "MyProject" "abc-123" "my-repo"
#>
function Ensure-AdoRepositoryTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$RepoName
    )
    
    Write-Host "[INFO] Adding repository template files..." -ForegroundColor Cyan
    
    # Check if repository has any commits (needed to add files)
    $hasCommits = $false
    try {
        $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/commits?``$top=1"
        $hasCommits = $commits.count -gt 0
    }
    catch {
        Write-Verbose "[Ensure-AdoRepositoryTemplates] Could not check commits: $_"
    }
    
    if (-not $hasCommits) {
        Write-Host "[INFO] Repository is empty - templates will be added on first push" -ForegroundColor Yellow
        Write-Host "[INFO] Skipping template files (repository needs at least one commit)" -ForegroundColor Yellow
        return @()
    }
    
    # Get default branch
    $defaultBranch = Get-AdoRepoDefaultBranch $Project $RepoId
    if (-not $defaultBranch) {
        Write-Host "[INFO] No default branch found - skipping template files" -ForegroundColor Yellow
        return @()
    }
    
    # Extract branch name from refs/heads/main
    $branchName = $defaultBranch -replace '^refs/heads/', ''
    
    # Define template files
    $readmeContent = @"
# $RepoName

## Overview
Brief description of the project and its purpose.

## Getting Started

### Prerequisites
- List any prerequisites here
- Development tools required
- Dependencies needed

### Installation
````````````bash
# Clone the repository
git clone <repository-url>

# Install dependencies
# Add installation commands here
````````````

### Running Locally
````````````bash
# Add commands to run the application locally
````````````

## Development Workflow

1. Create a feature branch from \``main\``
   ````````````bash
   git checkout -b feature/your-feature-name
   ````````````

2. Make your changes and commit
   ````````````bash
   git add .
   git commit -m "Description of changes"
   ````````````

3. Push and create a pull request
   ````````````bash
   git push origin feature/your-feature-name
   ````````````

4. Link your work items in the PR description
5. Request code review
6. Merge after approval

## Project Structure
````````````
/src        - Source code
/docs       - Documentation
/tests      - Test files
/scripts    - Build and deployment scripts
````````````

## Contributing
- Follow the team's coding standards
- Write tests for new features
- Update documentation as needed
- Link work items to pull requests

## Support
For questions or issues, contact the team or create a work item.
"@

    $prTemplateContent = @"
## Description
<!-- Provide a brief description of the changes in this PR -->

## Related Work Items
<!-- Link work items using #<work-item-id> -->
- Fixes #
- Related to #

## Type of Change
<!-- Check the relevant options -->
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Refactoring (no functional changes)

## Testing Done
<!-- Describe the testing you've performed -->
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] All tests passing

## Checklist
- [ ] Code follows team coding standards
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated (if needed)
- [ ] No new warnings generated
- [ ] Work items linked above

## Screenshots (if applicable)
<!-- Add screenshots for UI changes -->

## Additional Notes
<!-- Any additional information reviewers should know -->
"@

    $filesCreated = @()
    $createdCount = 0
    $skippedCount = 0
    
    # Check and create README.md
    try {
        $existingReadme = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/README.md"
        if ($existingReadme) {
            Write-Host "[INFO] README.md already exists" -ForegroundColor Gray
            $skippedCount++
        }
    }
    catch {
        # File doesn't exist, create it
        try {
            Write-Verbose "[Ensure-AdoRepositoryTemplates] Creating README.md"
            $pushBody = @{
                refUpdates = @(
                    @{
                        name = $defaultBranch
                        oldObjectId = (Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$branchName").value[0].objectId
                    }
                )
                commits = @(
                    @{
                        comment = "Add README.md template"
                        changes = @(
                            @{
                                changeType = "add"
                                item = @{ path = "/README.md" }
                                newContent = @{
                                    content = $readmeContent
                                    contentType = "rawtext"
                                }
                            }
                        )
                    }
                )
            }
            
            $result = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushBody
            Write-Host "[SUCCESS] Created README.md" -ForegroundColor Green
            $filesCreated += "README.md"
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create README.md: $_"
        }
    }
    
    # Check and create PR template
    try {
        $existingPR = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.azuredevops/pull_request_template.md"
        if ($existingPR) {
            Write-Host "[INFO] PR template already exists" -ForegroundColor Gray
            $skippedCount++
        }
    }
    catch {
        # File doesn't exist, create it
        try {
            Write-Verbose "[Ensure-AdoRepositoryTemplates] Creating .azuredevops/pull_request_template.md"
            $pushBody = @{
                refUpdates = @(
                    @{
                        name = $defaultBranch
                        oldObjectId = (Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$branchName").value[0].objectId
                    }
                )
                commits = @(
                    @{
                        comment = "Add pull request template"
                        changes = @(
                            @{
                                changeType = "add"
                                item = @{ path = "/.azuredevops/pull_request_template.md" }
                                newContent = @{
                                    content = $prTemplateContent
                                    contentType = "rawtext"
                                }
                            }
                        )
                    }
                )
            }
            
            $result = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushBody
            Write-Host "[SUCCESS] Created .azuredevops/pull_request_template.md" -ForegroundColor Green
            $filesCreated += ".azuredevops/pull_request_template.md"
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create PR template: $_"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Repository templates summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount files" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount files (already exist)" -ForegroundColor Yellow
    }
    
    return $filesCreated
}

<#
.SYNOPSIS
    Configures team settings for optimal workflow.

.DESCRIPTION
    Sets default iteration, configures backlog levels, working days (Mon-Fri),
    and bugs on backlog visibility. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Team
    Team name (optional, defaults to "<Project> Team").

.OUTPUTS
    Team settings object.

.EXAMPLE
    Ensure-AdoTeamSettings "MyProject"
#>
function Ensure-AdoTeamSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Configuring team settings..." -ForegroundColor Cyan
    
    $settingsConfigured = 0
    
    # Configure backlog levels (show Epics and Features)
    try {
        Write-Verbose "[Ensure-AdoTeamSettings] Configuring backlog visibility"
        $backlogBody = @{
            backlogVisibilities = @{
                "Microsoft.EpicCategory" = $true
                "Microsoft.FeatureCategory" = $true
                "Microsoft.RequirementCategory" = $true
            }
            bugsBehavior = "asRequirements"  # Show bugs on backlog
        }
        
        Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings" -Body $backlogBody | Out-Null
        Write-Host "[SUCCESS] Configured backlog levels and bugs visibility" -ForegroundColor Green
        $settingsConfigured++
    }
    catch {
        Write-Warning "Failed to configure backlog settings: $_"
    }
    
    # Configure working days (Monday-Friday)
    try {
        Write-Verbose "[Ensure-AdoTeamSettings] Configuring working days"
        $workingDaysBody = @{
            workingDays = @("monday", "tuesday", "wednesday", "thursday", "friday")
        }
        
        Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings" -Body $workingDaysBody | Out-Null
        Write-Host "[SUCCESS] Set working days to Mon-Fri" -ForegroundColor Green
        $settingsConfigured++
    }
    catch {
        Write-Warning "Failed to configure working days: $_"
    }
    
    # Set default iteration to current sprint (if iterations exist)
    try {
        $iterations = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings/iterations"
        if ($iterations -and $iterations.value -and $iterations.value.Count -gt 0) {
            $firstSprint = $iterations.value[0]
            
            Write-Verbose "[Ensure-AdoTeamSettings] Setting default iteration to: $($firstSprint.name)"
            $defaultIterationBody = @{
                backlogIteration = $firstSprint.id
                defaultIteration = $firstSprint.id
            }
            
            Invoke-AdoRest PATCH "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings" -Body $defaultIterationBody | Out-Null
            Write-Host "[SUCCESS] Set default iteration to: $($firstSprint.name)" -ForegroundColor Green
            $settingsConfigured++
        }
        else {
            Write-Host "[INFO] No iterations found - skipping default iteration setup" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoTeamSettings] Could not set default iteration: $_"
        Write-Host "[INFO] Default iteration not set (will use current date)" -ForegroundColor Yellow
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Team settings summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Configured: $settingsConfigured settings" -ForegroundColor Green
    Write-Host "  📊 Backlog levels: Epics → Features → Stories → Tasks" -ForegroundColor Gray
    Write-Host "  🐛 Bugs: Shown on backlog" -ForegroundColor Gray
    Write-Host "  📅 Working days: Mon-Fri" -ForegroundColor Gray
    
    return $settingsConfigured
}

<#
.SYNOPSIS
    Creates a world-class team dashboard with essential widgets.

.DESCRIPTION
    Creates a comprehensive team dashboard with Sprint Burndown, Velocity Chart,
    Work Item Charts, Query Tiles, and Test Results. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER Team
    Team name (optional, defaults to "<Project> Team").

.OUTPUTS
    Dashboard object.

.EXAMPLE
    Ensure-AdoDashboard "MyProject"
#>
function Ensure-AdoDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [string]$Team = "$Project Team"
    )
    
    Write-Host "[INFO] Creating team dashboard..." -ForegroundColor Cyan
    
    # Get team context (optional for fallback)
    $teamId = $null
    try {
        $teamContext = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))/teams/$([uri]::EscapeDataString($Team))"
        $teamId = $teamContext.id
    }
    catch {
        Write-Verbose "[Ensure-AdoDashboard] Team context not available; will attempt project-level dashboards as fallback. Error: $_"
    }
    
    # Check if dashboard already exists
    $dashboardName = "$Team - Overview"
    try {
        $existingDashboards = $null
        if ($teamId) {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Preview
        }
        else {
            $existingDashboards = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Preview
        }
        $existing = $existingDashboards.dashboardEntries | Where-Object { $_.name -eq $dashboardName }

        if ($existing) {
            Write-Host "[INFO] Dashboard '$dashboardName' already exists" -ForegroundColor Gray
            return $existing
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoDashboard] Could not check existing dashboards: $_"
    }
    
    # Create dashboard
    try {
        Write-Verbose "[Ensure-AdoDashboard] Creating dashboard: $dashboardName"
        
        $dashboardBody = @{
            name = $dashboardName
            description = "Auto-generated team overview dashboard with key metrics and insights"
            widgets = @(
                # Row 1: Sprint Burndown + Velocity
                @{
                    name = "Sprint Burndown"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-work-web.microsoft-teams-sprint-burndown"
                },
                @{
                    name = "Velocity"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-work-web.microsoft-teams-velocity"
                },
                
                # Row 2: Work Items by State + Work Items by Assignment
                @{
                    name = "Work Items by State"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryId":"","chartType":"pie"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Work Items by Assigned To"
                    position = @{ row = 3; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = '{"queryId":"","chartType":"stackBar"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                
                # Row 3: Query Tiles
                @{
                    name = "My Active Work"
                    position = @{ row = 5; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"My Active Work"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Active Bugs"
                    position = @{ row = 5; column = 2 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"Active Bugs"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Blocked Items"
                    position = @{ row = 5; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"Blocked Items"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                },
                @{
                    name = "Ready for Review"
                    position = @{ row = 5; column = 4 }
                    size = @{ rowSpan = 1; columnSpan = 1 }
                    settings = '{"queryId":"","queryName":"Ready for Review"}'
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget"
                }
            )
            _links = $null
        }
        
        $dashboard = $null
        if ($teamId) {
            try {
                $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
            }
            catch {
                # Fallback to project-level dashboards (some servers don't support team route)
                Write-Verbose "[Ensure-AdoDashboard] Team dashboards API failed, attempting project-level fallback: $_"
            }
        }
        if (-not $dashboard) {
            $dashboard = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/dashboard/dashboards" -Body $dashboardBody -Preview
        }
        
        Write-Host "[SUCCESS] Created team dashboard: $dashboardName" -ForegroundColor Green
        Write-Host ""
        Write-Host "[INFO] Dashboard widgets:" -ForegroundColor Cyan
        Write-Host "  📊 Sprint Burndown - Track sprint progress" -ForegroundColor Gray
        Write-Host "  📈 Velocity Chart - Team capacity over time" -ForegroundColor Gray
        Write-Host "  🥧 Work Items by State - Current work distribution" -ForegroundColor Gray
        Write-Host "  👥 Work Items by Assignment - Team workload balance" -ForegroundColor Gray
        Write-Host "  🎯 Query Tiles - Quick metrics (My Work, Bugs, Blocked, Review)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  📍 Location: Dashboards → $dashboardName" -ForegroundColor Gray
        
        return $dashboard
    }
    catch {
        Write-Warning "Failed to create dashboard: $_"
        Write-Verbose "[Ensure-AdoDashboard] Error details: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Creates a wiki page documenting common tags taxonomy.

.DESCRIPTION
    Creates a "Tag Guidelines" wiki page with recommended tags for work items.
    Tags help with filtering, reporting, and organization. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER WikiId
    Wiki ID.

.OUTPUTS
    Wiki page object.

.EXAMPLE
    Ensure-AdoCommonTags "MyProject" "wiki-id-123"
#>
function Ensure-AdoCommonTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating tag guidelines wiki page..." -ForegroundColor Cyan
    
    $tagGuidelinesContent = @"
# Work Item Tag Guidelines

This page documents the standard tags used across the project for consistent work item organization.

## Status & Workflow Tags

### 🚫 Blockers & Issues
- **blocked** - Work is blocked by external dependencies
- **impediment** - Team-level impediment requiring resolution
- **urgent** - Requires immediate attention
- **breaking-change** - Changes that break backward compatibility

### 📋 Review & Validation
- **needs-review** - Ready for code/design review
- **needs-testing** - Requires QA validation
- **needs-documentation** - Documentation updates needed
- **tech-review** - Requires technical architect review

## Technical Area Tags

### 💻 Component Tags
- **frontend** - UI/UX related work
- **backend** - Server-side logic and APIs
- **database** - Database schema or queries
- **api** - API design or changes
- **infrastructure** - DevOps, deployment, infrastructure

### 🏗️ Technical Classification
- **technical-debt** - Code that needs refactoring
- **performance** - Performance optimization work
- **security** - Security-related changes
- **accessibility** - Accessibility improvements

## Work Type Tags

### 🔧 Development Categories
- **feature** - New feature development
- **bugfix** - Bug resolution
- **refactoring** - Code improvement without functional changes
- **tooling** - Development tools and automation
- **investigation** - Research or spike work

### 📚 Documentation & Quality
- **documentation** - Documentation work
- **testing** - Test creation or improvement
- **automation** - Test or process automation

## Usage Guidelines

### How to Use Tags

1. **Apply Multiple Tags**: Work items can have multiple tags
   - Example: \``frontend, needs-review, breaking-change\``

2. **Use in Queries**: Filter work items by tags
   - Queries → "Contains" operator for tag searches

3. **Board Filtering**: Use tag pills on boards for quick filtering

4. **Consistency**: Use exact tag names (lowercase with hyphens)

### Best Practices

✅ **DO**:
- Use consistent, predefined tags
- Apply tags during work item creation
- Update tags as work progresses
- Use tags in work item templates

❌ **DON'T**:
- Create ad-hoc tags without team discussion
- Use spaces in tag names (use hyphens)
- Mix capitalization styles
- Overuse tags (3-5 tags per item is ideal)

## Creating New Tags

Before creating a new tag:
1. Check if an existing tag fits your need
2. Discuss with the team if creating a new category
3. Document the new tag here
4. Update work item templates if needed

## Tag Queries

Use these queries to find tagged work items:
- **Blocked Work**: \``Tags Contains 'blocked'\``
- **Technical Debt**: \``Tags Contains 'technical-debt'\``
- **Needs Review**: \``Tags Contains 'needs-review'\``
- **Breaking Changes**: \``Tags Contains 'breaking-change'\``

---

*Last Updated: $(Get-Date -Format 'yyyy-MM-dd')*
"@

    try {
        # Check if page exists
        try {
            $existingPage = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?path=/Tag-Guidelines"
            Write-Host "[INFO] Tag Guidelines page already exists" -ForegroundColor Gray
            return $existingPage
        }
        catch {
            # Page doesn't exist, create it
            Write-Verbose "[Ensure-AdoCommonTags] Creating Tag Guidelines page"
            $page = Upsert-AdoWikiPage $Project $WikiId "/Tag-Guidelines" $tagGuidelinesContent
            Write-Host "[SUCCESS] Created Tag Guidelines wiki page" -ForegroundColor Green
            Write-Host ""
            Write-Host "[INFO] Common tags documented:" -ForegroundColor Cyan
            Write-Host "  🚫 Status: blocked, urgent, breaking-change, needs-review, needs-testing" -ForegroundColor Gray
            Write-Host "  💻 Technical: frontend, backend, database, api, infrastructure" -ForegroundColor Gray
            Write-Host "  🏗️ Quality: technical-debt, performance, security" -ForegroundColor Gray
            Write-Host "  📂 Location: Project Wiki → Tag-Guidelines" -ForegroundColor Gray
            
            return $page
        }
    }
    catch {
        Write-Warning "Failed to create Tag Guidelines page: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Creates a comprehensive Azure DevOps best practices wiki page.

.DESCRIPTION
    Creates a "Best Practices" wiki page covering work item management, sprint planning,
    code review, branching strategies, dashboard usage, and team productivity guidelines.
    Idempotent - checks if page exists before creating.

.PARAMETER Project
    Project name.

.PARAMETER WikiId
    Wiki ID.

.OUTPUTS
    Wiki page object.

.EXAMPLE
    Ensure-AdoBestPracticesWiki "MyProject" "wiki-id-123"
#>
function Ensure-AdoBestPracticesWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating Azure DevOps best practices wiki page..." -ForegroundColor Cyan
    
    $bestPracticesContent = @"
# Azure DevOps Best Practices & Team Productivity Guide

This guide provides comprehensive best practices for using Azure DevOps effectively and maximizing team productivity.

---

## 📋 Work Item Management

### Creating Quality Work Items

#### ✅ DO
- **Write clear titles**: Use action verbs (Add, Fix, Update, Remove)
  - ✅ Good: "Add user authentication API endpoint"
  - ❌ Bad: "Auth stuff"
  
- **Include acceptance criteria**: Define what "done" means
  - Use checklists for clarity
  - Make criteria measurable and testable
  
- **Add relevant tags**: 3-5 tags maximum
  - Use predefined tags (see [Tag Guidelines](/Tag-Guidelines))
  - Example: \``backend, api, needs-review\``
  
- **Link related items**: 
  - Parent-child for hierarchy (Epic → Feature → User Story → Task)
  - Related for dependencies
  - Tested By for test cases
  
- **Estimate work**: Use story points or hours consistently
  - 1 point = ~2-4 hours ideal
  - Break down anything >8 points

#### ❌ DON'T
- Create work items without descriptions
- Skip acceptance criteria on User Stories
- Over-assign (1-2 work items per person max)
- Leave work items unassigned for >24 hours

### Work Item States

**Optimize your workflow**:

1. **New** → Ready for planning
2. **Active** → Currently being worked (limit WIP!)
3. **Resolved** → Ready for review/testing
4. **Closed** → Fully complete

**Rule**: Max 2-3 Active items per person (Work-In-Progress limit)

---

## 🏃 Sprint Planning Best Practices

### Before Sprint Planning

✅ **Preparation (48 hours before)**:
- Groom backlog (refine top 20 items)
- Ensure User Stories have acceptance criteria
- Split large items (>8 points)
- Remove blockers from top items

### During Sprint Planning

**1. Review Velocity** (15 minutes)
- Check last 3 sprints average
- Adjust for team capacity changes (vacations, holidays)
- Plan 80% of capacity (leave buffer)

**2. Commit to Work** (30 minutes)
- Pull from top of refined backlog
- Verify acceptance criteria clarity
- Assign owners (no unassigned items)
- Break User Stories into Tasks

**3. Set Sprint Goal** (15 minutes)
- One clear sentence defining success
- Shared by entire team
- Example: "Complete user authentication and enable login"

### Sprint Commitment Formula

````````````
Commitment = (Average Velocity × 0.8) + Buffer for bugs/tech debt
````````````

**Example**:
- Last 3 sprints: 25, 28, 24 points = 25.67 avg
- Capacity: 25.67 × 0.8 = **~21 points planned work**
- Reserve: ~4 points for unplanned work

---

## 📊 Dashboard Best Practices

### Daily Dashboard Review (5 minutes)

**Morning Standup Routine**:
1. Open **Team Dashboard** (Dashboards → [Team Name] - Overview)
2. Check **Sprint Burndown**: Are we on track?
3. Review **Blocked Items**: What needs unblocking?
4. Scan **Ready for Review**: Any PRs waiting?
5. View **Work Distribution**: Anyone overloaded?

### Key Metrics to Watch

| Metric | Healthy | Warning | Action Needed |
|--------|---------|---------|---------------|
| **Sprint Burndown** | On/ahead of trend | Slightly behind | Significantly behind - adjust scope |
| **Blocked Items** | 0-1 | 2-3 | 4+ - escalate blockers |
| **Ready for Review** | 0-2 | 3-5 | 6+ - prioritize code reviews |
| **Active Bugs** | 0-5 | 6-15 | 16+ - bug bash needed |

### Dashboard KPIs

**Velocity Stability**: ±20% variance acceptable
- 25 → 23 → 28 = **Stable** ✅
- 25 → 15 → 35 = **Unstable** ❌ (investigate)

**Lead Time**: New → Closed average
- Target: <5 days for Stories
- >10 days = bottleneck investigation needed

**Cycle Time**: Active → Closed average
- Target: <3 days
- Measure actual work time (excludes waiting)

---

## 🔀 Branching Strategy

### Recommended: GitHub Flow (Simplified)

````````````
main (protected)
  ↓
feature/add-login ──→ PR ──→ merge to main
feature/fix-bug-123 ──→ PR ──→ merge to main
````````````

### Branch Naming Conventions

**Pattern**: ````<type>/<ticket-number>-<brief-description>````

**Examples**:
- ````feature/123-add-user-authentication````
- ````bugfix/456-fix-login-crash````
- ````hotfix/789-security-patch````
- ````refactor/321-cleanup-api-layer````

### Branch Protection Rules (Applied Automatically)

✅ **Require PR reviews**: Minimum 1 reviewer
✅ **Require linked work items**: Traceability
✅ **Require successful builds**: CI must pass
✅ **No direct commits to main**: Force PR workflow

### Best Practices

- **Branch early**: Create branch as soon as you start work
- **Commit often**: Small, atomic commits with clear messages
- **Pull frequently**: ````git pull origin main```` daily to avoid conflicts
- **Delete after merge**: Keep repository clean

---

## 🔍 Code Review Excellence

### For Authors

**Before Creating PR**:
1. ✅ Self-review code (read your own diff)
2. ✅ Run tests locally (all passing)
3. ✅ Update documentation if needed
4. ✅ Write clear PR description using template
5. ✅ Link work item (required by policy)
6. ✅ Add relevant reviewers (2-3 people max)

**PR Description Template** (created automatically):
- **What**: What changes were made?
- **Why**: Why were these changes needed?
- **Testing**: How was this tested?
- **Checklist**: ☐ Tests added, ☐ Docs updated

### For Reviewers

**Review SLA**: Within 24 hours (4 hours for hotfixes)

**What to Look For**:
1. **Correctness**: Does it work as intended?
2. **Tests**: Are there tests? Do they cover edge cases?
3. **Readability**: Can others understand this code?
4. **Performance**: Any obvious performance issues?
5. **Security**: Any security concerns?

**Feedback Guidelines**:
- 🟢 **Praise good patterns**: "Nice abstraction here!"
- 🟡 **Suggest improvements**: "Consider using X for clarity"
- 🔴 **Block on critical issues**: "Security: SQL injection risk"

**Review Levels**:
- **Approve**: Ready to merge ✅
- **Approve with comments**: Minor suggestions, merge OK
- **Wait for author**: Non-blocking feedback
- **Request changes**: Must fix before merge 🚫

---

## 🏷️ Tagging Strategy

### Essential Tags (Use These)

**Status Tags** (update as work progresses):
- ````blocked```` - External dependency blocking progress
- ````needs-review```` - Code ready for review
- ````needs-testing```` - Requires QA validation
- ````urgent```` - High priority, immediate attention

**Technical Tags** (classify work type):
- ````frontend````, ````backend````, ````database````, ````api````
- ````technical-debt```` - Refactoring needed
- ````breaking-change```` - API/contract changes
- ````performance```` - Optimization work

**See full list**: [Tag Guidelines](/Tag-Guidelines)

### Tagging Rules

✅ **DO**:
- Apply tags during creation
- Update tags as status changes
- Use 3-5 tags per item
- Use shared queries to find tagged items

❌ **DON'T**:
- Create custom tags without team agreement
- Use spaces (use hyphens: \``needs-review\``)
- Over-tag (>7 tags = noise)

---

## 📈 Queries & Reporting

### Use Shared Queries (Created Automatically)

Navigate to: **Boards → Queries → Shared Queries**

1. **My Active Work**
   - Your currently assigned work items
   - Use daily to see personal workload

2. **Team Backlog - Ready to Work**
   - Refined, unassigned work ready for pickup
   - Use during sprint planning

3. **Active Bugs**
   - All open bugs across project
   - Use for bug triage meetings

4. **Ready for Review**
   - Items awaiting code review
   - Check 2-3 times daily

5. **Blocked Items**
   - Work blocked by dependencies
   - Review in daily standup

### Creating Custom Queries

**Query Editor Tips**:
- Use **WIQL** for complex queries
- Save personal queries under "My Queries"
- Share useful queries with team
- Add to dashboard as query tiles

**Example Query**: High Priority Bugs
````````````
Work Item Type = Bug
AND State <> Closed
AND Priority <= 2
ORDER BY Priority ASC
````````````

---

## 👥 Team Collaboration

### Daily Standup Format (15 minutes max)

**Use Dashboard During Standup**:

1. **Review Sprint Burndown** (2 min)
   - On track? Ahead? Behind?

2. **Check Blocked Items** (3 min)
   - What's blocking progress?
   - Who can help remove blockers?

3. **Quick Round Robin** (10 min per person)
   - What did you complete yesterday?
   - What are you working on today?
   - Any blockers? (already visible on dashboard)

**No storytelling** - keep it factual and brief!

### Sprint Review Checklist

✅ **Prepare Demo** (owner prepares 5 min demo per Story)
✅ **Show Live Features** (not slides/mockups)
✅ **Show Metrics** (velocity chart, sprint burndown)
✅ **Collect Feedback** (create work items for feedback)
✅ **Update Stakeholders** (email summary after meeting)

### Retrospective Best Practices

**Format: Start-Stop-Continue**

1. **Start**: What should we start doing?
2. **Stop**: What should we stop doing?
3. **Continue**: What's working well?

**Create Action Items**:
- Assign owners to action items
- Track in next sprint
- Review at next retro (close the loop)

---

## 📚 Documentation Standards

### Wiki Organization

````````````
/Home
/Getting-Started
  /Development-Setup
  /Deployment-Guide
/Architecture
  /System-Design
  /API-Documentation
/Processes
  /Best-Practices (this page)
  /Tag-Guidelines
  /Release-Process
````````````

### When to Document

**Document When**:
- ✅ Setting up development environment
- ✅ Architectural decisions (ADRs)
- ✅ API contracts and schemas
- ✅ Deployment procedures
- ✅ Troubleshooting common issues

**Don't Document**:
- ❌ Obvious code (use comments instead)
- ❌ Temporary workarounds
- ❌ Personal notes (use work item comments)

### README Best Practices

Every repository needs:
1. **What**: Project description
2. **Why**: Purpose and goals
3. **How**: Setup instructions
4. **Prerequisites**: Required tools/versions
5. **Quick Start**: Get running in <5 minutes
6. **Contributing**: How to contribute

(README template created automatically)

---

## 🚀 Continuous Integration Best Practices

### Build Pipeline Configuration

**Every pipeline should**:
- ✅ Run on every PR (gate quality)
- ✅ Run all tests (unit, integration)
- ✅ Enforce code coverage (70%+ recommended)
- ✅ Run linting/static analysis
- ✅ Fail fast (don't waste CI time)
- ✅ Complete in <10 minutes

### Test Pyramid

````````````
       /\\
      /  \\  E2E Tests (5%)
     /----\\
    / UI Tests (15%)
   /----------\\
  / Integration (30%)
 /----------------\\
/__________________\\
   Unit Tests (50%)
````````````

**Golden Rule**: More unit tests, fewer E2E tests

---

## 🎯 Definition of Ready (DoR)

**Before moving User Story to sprint**:

- [ ] Clear, testable acceptance criteria
- [ ] Estimated (story points assigned)
- [ ] Dependencies identified
- [ ] Designs approved (if applicable)
- [ ] No blockers
- [ ] Team understands requirements

**If not ready** → Keep in backlog for refinement

---

## ✅ Definition of Done (DoD)

**Before closing work item**:

- [ ] Code complete and reviewed
- [ ] Tests written and passing
- [ ] Documentation updated
- [ ] PR merged to main
- [ ] Deployed to test environment
- [ ] Acceptance criteria met
- [ ] No new bugs introduced

**If not done** → Move back to Active or Resolved

---

## 📊 Metrics & KPIs

### Team Health Metrics

| Metric | Target | Formula |
|--------|--------|---------|
| **Velocity Stability** | ±20% | Std deviation of last 6 sprints |
| **Sprint Commitment %** | 85-100% | Points completed / Points committed |
| **Escaped Defects** | <5% | Bugs found in prod / Total stories |
| **PR Cycle Time** | <24 hours | Time from PR creation to merge |
| **Lead Time** | <5 days | New → Closed for User Stories |
| **Code Review Coverage** | 100% | PRs reviewed / Total PRs |

### Individual Metrics (Private)

**For self-improvement only** (not for performance reviews):
- Work items completed per sprint
- PR review turnaround time
- Bug introduction rate
- Code review quality (feedback given)

---

## 🛠️ Tooling & Automation

### Recommended VS Code Extensions

- **Azure Boards** - View work items in VS Code
- **GitLens** - Git superpowers
- **Azure Pipelines** - Monitor builds
- **Prettier/ESLint** - Code formatting

### Automation Opportunities

**Automate These**:
- ✅ Work item state transitions (PR merged → Close work item)
- ✅ Build/test on every commit
- ✅ Deployment to test environment
- ✅ Release notes generation
- ✅ Code quality checks (linting, coverage)

**Don't Automate**:
- ❌ Production deployments (require approval)
- ❌ Database migrations (manual review)
- ❌ Critical security changes

---

## 🎓 Learning Resources

### Azure DevOps Documentation
- [Work Item Guidance](https://docs.microsoft.com/azure-devops/boards/)
- [Git Branching Strategies](https://docs.microsoft.com/azure-devops/repos/git/git-branching-guidance)
- [Pipeline Best Practices](https://docs.microsoft.com/azure-devops/pipelines/library/)

### Agile/Scrum Resources
- Scrum Guide: [scrumguides.org](https://scrumguides.org)
- Agile Manifesto: [agilemanifesto.org](https://agilemanifesto.org)

---

## 🆘 Getting Help

**Stuck? Try These**:
1. 🔍 Search this wiki
2. 💬 Ask in team chat
3. 📋 Check [Tag Guidelines](/Tag-Guidelines)
4. 📊 Review dashboard metrics
5. 👥 Pair with teammate

**Remember**: No question is too small!

---

## 🔄 Continuous Improvement

**This document is living**:
- Review quarterly
- Update based on retrospective action items
- Add team-specific practices
- Remove outdated guidance

**Suggest Changes**:
- Create work item tagged \``documentation\``
- Propose changes in retrospectives
- Edit this wiki page directly (with team agreement)

---

*Last Updated: $(Get-Date -Format 'yyyy-MM-dd')*

*This page is maintained by the team. Questions? Create a work item tagged 'documentation'.*
"@

    try {
        # Check if page exists
        try {
            $existingPage = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?path=/Best-Practices"
            Write-Host "[INFO] Best Practices page already exists" -ForegroundColor Gray
            return $existingPage
        }
        catch {
            # Page doesn't exist, create it
            Write-Verbose "[Ensure-AdoBestPracticesWiki] Creating Best Practices page"
            $page = Upsert-AdoWikiPage $Project $WikiId "/Best-Practices" $bestPracticesContent
            Write-Host "[SUCCESS] Created Best Practices wiki page" -ForegroundColor Green
            return $page
        }
    }
    catch {
        Write-Warning "Failed to create Best Practices page: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Provisions business-facing wiki pages (idempotent).

.DESCRIPTION
    Creates or updates a set of business-oriented wiki pages to help non-technical
    stakeholders understand the migration, how to work in ADO, and where to get help.

.PARAMETER Project
    Project name.

.PARAMETER WikiId
    Wiki ID.

.EXAMPLE
    Ensure-AdoBusinessWiki -Project "MyProject" -WikiId "wiki-id-123"
#>
function Ensure-AdoBusinessWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Project,
        [Parameter(Mandatory)] [string]$WikiId
    )
    Write-Host "[INFO] Creating business wiki pages..." -ForegroundColor Cyan

    $pages = @(
        @{ path = '/Business-Welcome'; content = @"
# Welcome – Business Overview

This project is now hosted on Azure DevOps Server. Here’s what you need to know to get started.

## What’s happening
- We migrated source code from GitLab to Azure DevOps.
- Work tracking uses the Agile process (stories, tasks, bugs, epics, features).

## How to access
- Project URL: [$Project](/Home)
- If you need access, contact the Project Admins.

## How we track work
- Boards → Backlog and Sprints
- Shared Queries provide curated views (My Work, Ready for Review, Blocked Items)

## Cutover timeline
See [Cutover & Rollback](/Cutover-Timeline).

## Support
- Teams/Slack: #ado-support
- Office hours: Tue/Thu 14:00–15:00
"@ },
    @{ path = '/Decision-Log'; content = @"
# Decision Log

Record key decisions succinctly.

| Date | Decision | Owner | Impact |
|------|----------|-------|--------|
| yyyy-mm-dd | Short statement | Name | Short impact |
"@ },
    @{ path = '/Risks-Issues'; content = @"
# Risks & Issues

Track business-visible risks and issues.

| Type | Title | Owner | Mitigation | Due |
|------|-------|-------|------------|-----|
| Risk | | | | |
| Issue | | | | |
"@ },
    @{ path = '/Glossary'; content = @"
# Glossary – GitLab → Azure DevOps

- Merge Request → Pull Request
- Issue → Work Item (Story/Task/Bug/etc.)
- Labels → Tags
"@ },
    @{ path = '/Ways-of-Working'; content = @"
# Ways of Working

## Definition of Ready (DoR)
- Clear user value
- Acceptance criteria present
- Dependencies identified

## Definition of Done (DoD)
- Code reviewed, tests passing, docs updated, accepted by PO
"@ },
    @{ path = '/KPIs-and-Success'; content = @"
# KPIs & Success Criteria

- Enablement: % trained, active users
- Flow: Lead time, Cycle time (baseline then trend)
- Quality: Bugs by severity trend
- Migration readiness: Preflight checks passed, SSL/TLS status
"@ },
    @{ path = '/Training-Quick-Start'; content = @"
# Training – Quick Start (30–45 min)

Agenda:
1) Navigation (Boards, Repos, Queries, Dashboards)
2) Create/Update work items; use tags; link PRs
3) Review dashboards; stand-up checklist

Cheat sheets:
- Top 10 daily tasks
- GitLab vs Azure DevOps differences
"@ },
    @{ path = '/Communication-Templates'; content = @"
# Communication Templates

## Announcement (Draft)
Why: Value, timeline, what changes. Links to wiki and support.

## Freeze Window Notice (Draft)
Scope, start/end, exceptions, rollback criteria.

## Go/No-Go Checklist (Draft)
Preconditions, sign-offs, owner list.

## Post-Cutover Survey (Draft)
3–5 quick questions to capture satisfaction and gaps.
"@ },
    @{ path = '/Cutover-Timeline'; content = @"
# Cutover & Rollback Plan (Overview)

1) Freeze window → Final verification → Go/No-Go
2) Cutover execution → Validation
3) Rollback path documented (if needed)
"@ },
    @{ path = '/Post-Cutover-Summary'; content = @"
# Post-Cutover Summary

To be updated after code push:
- Default branch name
- Branch policies applied
- Branches/tags counts
"@ }
    )

    foreach ($p in $pages) {
        try {
            Upsert-AdoWikiPage -Project $Project -WikiId $WikiId -Path $p.path -Markdown $p.content | Out-Null
            Write-Host "[SUCCESS] Wiki page ensured: $($p.path)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to upsert page $($p.path): $_"
        }
    }
}

<#
.SYNOPSIS
    Creates additional business-friendly shared queries.

.DESCRIPTION
    Adds curated queries commonly requested by business stakeholders: current sprint commitment,
    unestimated stories, and epics by target date. Idempotent creation under Shared Queries.

.PARAMETER Project
    Project name.

.EXAMPLE
    Ensure-AdoBusinessQueries -Project "MyProject"
#>
function Ensure-AdoBusinessQueries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Project
    )

    Write-Host "[INFO] Creating business shared queries..." -ForegroundColor Cyan

    $queries = @(
        @{ name = 'Current Sprint: Commitment'; wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.IterationPath] UNDER @CurrentIteration('$Project') ORDER BY [System.WorkItemType] ASC, [System.State] ASC, [System.ChangedDate] DESC" },
        @{ name = 'Unestimated Stories'; wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [Microsoft.VSTS.Scheduling.StoryPoints] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] IN ('User Story','Product Backlog Item','Requirement','Issue') AND ([Microsoft.VSTS.Scheduling.StoryPoints] = '' OR [Microsoft.VSTS.Scheduling.StoryPoints] = 0) AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [System.CreatedDate] DESC" },
        @{ name = 'Epics by Target Date'; wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Scheduling.TargetDate] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Epic' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Scheduling.TargetDate] ASC, [System.CreatedDate] DESC" }
    )

    # Read existing queries under Shared Queries
    $existing = @{}
    try {
        $resp = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?``$depth=1"
        if ($resp -and $resp.children) { $resp.children | ForEach-Object { $existing[$_.name] = $_ } }
    }
    catch {
        Write-Verbose "[Ensure-AdoBusinessQueries] Could not retrieve existing queries: $_"
    }

    $created = 0; $skipped = 0
    foreach ($q in $queries) {
        if ($existing.ContainsKey($q.name)) {
            Write-Host "[INFO] Query '$($q.name)' already exists" -ForegroundColor Gray
            $skipped++
            continue
        }
        try {
            $body = @{ name = $q.name; wiql = $q.wiql }
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" -Body $body | Out-Null
            Write-Host "[SUCCESS] Created query: $($q.name)" -ForegroundColor Green
            $created++
        }
        catch {
            Write-Warning "Failed to create query '$($q.name)': $_"
        }
    }

    Write-Host "[INFO] Business queries summary: Created=$created, Skipped=$skipped" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Ensures a repository exists in the project.

.DESCRIPTION
    Creates repository if missing. Supports AllowExisting for sync scenarios.

.PARAMETER Project
    Project name.

.PARAMETER ProjId
    Project ID.

.PARAMETER RepoName
    Repository name.

.PARAMETER AllowExisting
    If true, returns existing repo without error.

.OUTPUTS
    Repository object.

.EXAMPLE
    Ensure-AdoRepository "MyProject" $projId "my-repo" -AllowExisting
#>
function Ensure-AdoRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$ProjId,
        
        [Parameter(Mandatory)]
        [string]$RepoName,
        
        [switch]$AllowExisting,
        
        [switch]$Replace
    )
    
    Write-Verbose "[Ensure-AdoRepository] Checking if repository '$RepoName' exists..."
    
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories"
    $existing = $repos.value | Where-Object { $_.name -eq $RepoName }
    
    if ($existing) {
        Write-Verbose "[Ensure-AdoRepository] Repository '$RepoName' exists (ID: $($existing.id))"
        
        # Check if repository has commits
        try {
            $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($existing.id)/commits?``$top=1"
            $hasCommits = $commits.count -gt 0
        }
        catch {
            $hasCommits = $false
        }
        
        if ($hasCommits) {
            Write-Verbose "[Ensure-AdoRepository] Repository has $($commits.count) commit(s)"
            
            if ($Replace) {
                if ($PSCmdlet.ShouldProcess($RepoName, "DELETE and recreate repository (has existing commits)")) {
                    Write-Warning "Repository '$RepoName' has commits. Deleting and recreating due to -Replace flag..."
                    
                    # Delete existing repository
                    Invoke-AdoRest DELETE "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($existing.id)"
                    Start-Sleep -Seconds 2
                    
                    # Create new repository
                    Write-Host "[INFO] Creating new repository: $RepoName" -ForegroundColor Cyan
                    return Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -Body @{
                        name    = $RepoName
                        project = @{ id = $ProjId }
                    }
                }
            }
            else {
                $msg = "Repository '$RepoName' already exists with $($commits.count) commit(s). "
                $msg += "Use -Replace to delete and recreate, or -AllowExisting to sync content."
                throw $msg
            }
        }
        
        if ($AllowExisting) {
            Write-Host "[INFO] Repository '$RepoName' already exists. Will sync/update content." -ForegroundColor Green
            return $existing
        }
        else {
            Write-Host "[INFO] Repository '$RepoName' already exists (empty) - no changes needed" -ForegroundColor Green
            return $existing
        }
    }
    
    # Repository does not exist - create it
    if ($PSCmdlet.ShouldProcess($RepoName, "Create new repository")) {
        Write-Host "[INFO] Creating new repository: $RepoName" -ForegroundColor Cyan
        $newRepo = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -Body @{
            name    = $RepoName
            project = @{ id = $ProjId }
        }
        Write-Host "[SUCCESS] Repository '$RepoName' created successfully" -ForegroundColor Green
        return $newRepo
    }
    else {
        Write-Warning "Repository creation was cancelled by the user"
        return $null
    }
}

<#
.SYNOPSIS
    Gets the default branch for a repository.

.DESCRIPTION
    Returns refs/heads/{branch} format. Defaults to 'refs/heads/main' if not set.

.PARAMETER Project
    Project name.

.PARAMETER RepoId
    Repository ID.

.OUTPUTS
    Branch reference string.

.EXAMPLE
    Get-AdoRepoDefaultBranch "MyProject" "repo123"
#>
function Get-AdoRepoDefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId
    )
    
    try {
        $r = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId"
        if ($r.PSObject.Properties['defaultBranch'] -and $r.defaultBranch) {
            Write-Verbose "[Get-AdoRepoDefaultBranch] Found default branch: $($r.defaultBranch)"
            return $r.defaultBranch
        }
        else {
            Write-Warning "Repository has no default branch yet (empty repository). Branch policies will be skipped."
            return $null
        }
    }
    catch {
        Write-Warning "Failed to get default branch: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Ensures branch policies are configured.

.DESCRIPTION
    Creates required reviewers, work item linking, comment resolution,
    build validation, and status check policies. Idempotent.

.PARAMETER Project
    Project name.

.PARAMETER RepoId
    Repository ID.

.PARAMETER Ref
    Branch reference (e.g., "refs/heads/main").

.PARAMETER Min
    Minimum approvers (default: 2).

.PARAMETER BuildId
    Build definition ID for build validation policy.

.PARAMETER StatusContext
    Status check context name (e.g., "SonarQube").

.EXAMPLE
    Ensure-AdoBranchPolicies "MyProject" $repoId "refs/heads/main" -Min 2 -BuildId 10 -StatusContext "SonarQube"
#>
function Ensure-AdoBranchPolicies {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$Ref,
        
        [int]$Min = 2,
        
        [int]$BuildId = 0,
        
        [string]$StatusContext = ""
    )
    
    Write-Verbose "[Ensure-AdoBranchPolicies] Checking existing policies for ref '$Ref'..."
    
    $cfgs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations"
    $scope = @{ repositoryId = $RepoId; refName = $Ref; matchKind = "exact" }
    
    function Test-PolicyExists([string]$id) {
        $cfgs.value | Where-Object { $_.type.id -eq $id -and $_.settings.scope[0].refName -eq $Ref }
    }
    
    # Required reviewers policy
    $existing = Test-PolicyExists $script:POLICY_REQUIRED_REVIEWERS
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($Ref, "Create required reviewers policy (min: $Min)")) {
            Write-Host "[INFO] Creating required reviewers policy" -ForegroundColor Cyan
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:POLICY_REQUIRED_REVIEWERS }
                settings   = @{
                    minimumApproverCount = [Math]::Max(1, $Min)
                    creatorVoteCounts    = $false
                    allowDownvotes       = $true
                    resetOnSourcePush    = $false
                    scope                = @($scope)
                }
            } | Out-Null
        }
    }
    else {
        Write-Verbose "[Ensure-AdoBranchPolicies] Required reviewers policy already exists"
    }
    
    # Work item link policy
    $existing = Test-PolicyExists $script:POLICY_WORK_ITEM_LINK
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($Ref, "Create work item link policy")) {
            Write-Host "[INFO] Creating work item link policy" -ForegroundColor Cyan
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:POLICY_WORK_ITEM_LINK }
                settings   = @{ scope = @($scope) }
            } | Out-Null
        }
    }
    else {
        Write-Verbose "[Ensure-AdoBranchPolicies] Work item link policy already exists"
    }
    
    # Comment resolution policy
    $existing = Test-PolicyExists $script:POLICY_COMMENT_RESOLUTION
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($Ref, "Create comment resolution policy")) {
            Write-Host "[INFO] Creating comment resolution policy" -ForegroundColor Cyan
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:POLICY_COMMENT_RESOLUTION }
                settings   = @{ scope = @($scope) }
            } | Out-Null
        }
    }
    else {
        Write-Verbose "[Ensure-AdoBranchPolicies] Comment resolution policy already exists"
    }
    
    # Build validation policy
    if ($BuildId -gt 0) {
        $existing = Test-PolicyExists $script:POLICY_BUILD_VALIDATION
        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($Ref, "Create build validation policy (Build ID: $BuildId)")) {
                Write-Host "[INFO] Creating build validation policy" -ForegroundColor Cyan
                Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                    isEnabled  = $true
                    isBlocking = $true
                    type       = @{ id = $script:POLICY_BUILD_VALIDATION }
                    settings   = @{
                        displayName             = "CI validation"
                        validDuration           = 0
                        queueOnSourceUpdateOnly = $false
                        buildDefinitionId       = $BuildId
                        scope                   = @($scope)
                    }
                } | Out-Null
            }
        }
        else {
            Write-Verbose "[Ensure-AdoBranchPolicies] Build validation policy already exists"
        }
    }
    
    # Status check policy
    if ($StatusContext -and -not (Test-PolicyExists $script:POLICY_STATUS_CHECK)) {
        Write-Host "[INFO] Creating status check policy"
        Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
            isEnabled  = $true
            isBlocking = $true
            type       = @{ id = $script:POLICY_STATUS_CHECK }
            settings   = @{
                statusName               = $StatusContext
                invalidateOnSourceUpdate = $true
                scope                    = @($scope)
            }
        } | Out-Null
    }
}

<#
.SYNOPSIS
    Applies deny permissions to a group on a repository.

.DESCRIPTION
    Restricts group permissions using Git security namespace.
    Used to prevent direct pushes for certain groups.

.PARAMETER ProjectId
    Project ID.

.PARAMETER RepoId
    Repository ID.

.PARAMETER GroupDescriptor
    Group descriptor.

.PARAMETER DenyBits
    Bitwise OR of permissions to deny.

.EXAMPLE
    Ensure-AdoRepoDeny $projId $repoId $groupDesc 268  # Deny GenericContribute + ForcePush
#>
function Ensure-AdoRepoDeny {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$GroupDescriptor,
        
        [Parameter(Mandatory)]
        [int]$DenyBits
    )
    
    $token = "repoV2/$ProjectId/$RepoId"
    
    # Verify current permissions
    try {
        $currentAcl = Invoke-AdoRest GET "/_apis/securitynamespaces/$script:NS_GIT/accesscontrolentries?token=$([uri]::EscapeDataString($token))&descriptors=$([uri]::EscapeDataString($GroupDescriptor))"
        Write-Verbose "[AzureDevOps] Current ACL for group $GroupDescriptor"
        if ($currentAcl.value.Count -gt 0) {
            Write-Verbose "[AzureDevOps] Current permissions - Allow: $($currentAcl.value[0].allow), Deny: $($currentAcl.value[0].deny)"
        }
        else {
            Write-Verbose "[AzureDevOps] No existing permissions found for this group"
        }
    }
    catch {
        Write-Host "[WARN] Could not retrieve current ACL: $_" -ForegroundColor Yellow
    }
    
    # Apply deny permissions
    Write-Host "[INFO] Applying deny permissions (bits: $DenyBits) to group"
    Invoke-AdoRest POST "/_apis/securitynamespaces/$script:NS_GIT/accesscontrolentries" -Body @{
        token                = $token
        merge                = $true
        accessControlEntries = @(@{
                descriptor = $GroupDescriptor
                allow      = 0
                deny       = $DenyBits
            })
    } | Out-Null
    Write-Host "[INFO] Deny permissions successfully applied" -ForegroundColor Green
}

<#
.SYNOPSIS
    Creates development-focused wiki pages for technical team enablement.

.DESCRIPTION
    Provisions comprehensive wiki structure for development teams including:
    - Architecture Decision Records (ADR) template
    - Development environment setup guide
    - API documentation structure
    - Git workflow and branching strategy
    - Code review checklist
    - Troubleshooting guide
    - Dependencies and third-party libraries documentation

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER WikiId
    Wiki identifier.

.EXAMPLE
    Ensure-AdoDevWiki -Project "MyProject" -WikiId "wiki-id-123"
#>
function Ensure-AdoDevWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating development wiki pages..." -ForegroundColor Cyan
    
    # Architecture Decision Records
    $adrContent = @"
# Architecture Decision Records (ADRs)

Architecture Decision Records document significant architectural decisions made during the project lifecycle.

## What is an ADR?

An ADR is a document that captures an important architectural decision made along with its context and consequences.

## When to Create an ADR

Create an ADR when you make a decision that:
- Affects the structure, non-functional characteristics, dependencies, interfaces, or construction techniques
- Is difficult or expensive to reverse
- Has significant impact on team productivity or system quality
- Introduces new technologies, frameworks, or patterns

## ADR Template

Use this template for new ADRs:

````````````markdown
# ADR-001: [Short Title of Decision]

**Status**: Proposed | Accepted | Superseded | Deprecated  
**Date**: YYYY-MM-DD  
**Deciders**: [List of people involved]  
**Technical Story**: [Link to work item or ticket]

## Context

[Describe the forces at play: technical, business, political, social. 
What is the problem we're trying to solve?]

## Decision

[Describe the decision we made. Use active voice: "We will..."]

## Consequences

### Positive
- [Benefit 1]
- [Benefit 2]

### Negative
- [Drawback 1]
- [Drawback 2]

### Neutral
- [Impact 1]

## Alternatives Considered

### Option A: [Name]
- **Pros**: ...
- **Cons**: ...
- **Why Not Chosen**: ...

### Option B: [Name]
- **Pros**: ...
- **Cons**: ...
- **Why Not Chosen**: ...

## Implementation Notes

[Any specific guidance for implementation]

## References

- [Link to design doc]
- [Link to spike/POC]
- [External resources]
````````````

## Example ADRs

### ADR-001: Use REST API instead of GraphQL

**Status**: Accepted  
**Date**: 2024-01-15  
**Deciders**: Tech Lead, Backend Team  

**Context**: Need to choose API architecture for new service.

**Decision**: We will use REST API with OpenAPI specification.

**Consequences**:
- ✅ Team already familiar with REST
- ✅ Better tooling support
- ❌ More endpoints to maintain

## ADR Index

| Number | Title | Status | Date |
|--------|-------|--------|------|
| ADR-001 | Example decision | Accepted | 2024-01-15 |

---

**Next Steps**: Create a new page under /Development/ADRs for each decision.
"@

    # Development Setup
    $devSetupContent = @"
# Development Environment Setup

Complete guide for setting up your local development environment.

## Prerequisites

### Required Software

- **Git**: Version 2.30+
  - Download: https://git-scm.com/
  - Verify: \``git --version\``

- **IDE/Editor**:
  - Visual Studio Code (recommended)
  - Visual Studio 2022
  - JetBrains Rider/IntelliJ

- **Runtime/SDK**:
  - .NET 8.0 SDK (for .NET projects)
  - Node.js 18+ LTS (for Node projects)
  - Python 3.11+ (for Python projects)
  - Docker Desktop (for containerized development)

### Optional Tools

- **Postman** or **Insomnia** (API testing)
- **Azure Data Studio** or **SQL Server Management Studio** (database)
- **Redis Desktop Manager** (cache debugging)

## Repository Setup

### 1. Clone the Repository

````````````bash
# Clone with HTTPS
git clone https://dev.azure.com/your-org/$Project/_git/$Project

# Or with SSH
git clone git@ssh.dev.azure.com:v3/your-org/$Project/$Project

cd $Project
````````````

### 2. Install Dependencies

#### For .NET Projects
````````````bash
dotnet restore
dotnet build
````````````

#### For Node.js Projects
````````````bash
npm install
# or
yarn install
````````````

#### For Python Projects
````````````bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
````````````

### 3. Configure Local Settings

````````````bash
# Copy configuration template
cp appsettings.Development.json.template appsettings.Development.json
# or
cp .env.example .env

# Edit with your local settings
code appsettings.Development.json
````````````

### 4. Database Setup

````````````bash
# Run migrations
dotnet ef database update
# or
npm run migrate
````````````

### 5. Run the Application

````````````bash
# .NET
dotnet run --project src/MyApp.Api

# Node.js
npm run dev

# Python
python manage.py runserver
````````````

## Verification

### Health Check

After starting the application, verify it's running:

````````````bash
curl http://localhost:5000/health
# Should return: {"status": "healthy"}
````````````

### Run Tests

````````````bash
# .NET
dotnet test

# Node.js
npm test

# Python
pytest
````````````

## Common Issues

### Issue: Port Already in Use

**Solution**: Change port in configuration or kill existing process
````````````bash
# Windows
netstat -ano | findstr :5000
taskkill /PID <PID> /F

# Linux/Mac
lsof -i :5000
kill -9 <PID>
````````````

### Issue: Database Connection Failed

**Solution**: Verify connection string and ensure database server is running

### Issue: SSL Certificate Errors

**Solution**: Trust development certificate
````````````bash
dotnet dev-certs https --trust
````````````

## IDE Configuration

### Visual Studio Code

**Recommended Extensions**:
- C# (for .NET)
- ESLint (for JavaScript)
- Python
- Docker
- GitLens
- Azure Repos

**Settings** (\``.vscode/settings.json\``):
````````````json
{
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  }
}
````````````

### Launch Configuration (\``.vscode/launch.json\``)

Configuration for debugging will be project-specific. See repository for examples.

## Getting Help

- **Wiki**: Check [Troubleshooting](/Development/Troubleshooting)
- **Team**: Ask in team chat or daily standup
- **Documentation**: See [API Documentation](/Development/API-Documentation)

---

**Next Steps**: After setup, review [Git Workflow](/Development/Git-Workflow) and [Code Review Checklist](/Development/Code-Review-Checklist).
"@

    # API Documentation
    $apiDocsContent = @"
# API Documentation

Comprehensive guide to the project's APIs and integration contracts.

## API Overview

### Base URLs

| Environment | URL |
|-------------|-----|
| **Development** | http://localhost:5000 |
| **Staging** | https://staging-api.example.com |
| **Production** | https://api.example.com |

### Authentication

**Type**: Bearer Token (JWT)

````````````http
Authorization: Bearer <your-jwt-token>
````````````

### Common Headers

````````````http
Content-Type: application/json
Accept: application/json
X-API-Version: 1.0
````````````

## API Endpoints

### User Management

#### GET /api/users

Get list of users.

**Request**:
````````````http
GET /api/users?page=1&size=20
Authorization: Bearer <token>
````````````

**Response** (200 OK):
````````````json
{
  "data": [
    {
      "id": "123",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "developer"
    }
  ],
  "pagination": {
    "page": 1,
    "size": 20,
    "total": 100
  }
}
````````````

#### POST /api/users

Create new user.

**Request**:
````````````json
{
  "name": "Jane Smith",
  "email": "jane@example.com",
  "role": "developer"
}
````````````

**Response** (201 Created):
````````````json
{
  "id": "124",
  "name": "Jane Smith",
  "email": "jane@example.com",
  "role": "developer",
  "createdAt": "2024-01-15T10:30:00Z"
}
````````````

## Error Handling

### Standard Error Response

````````````json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input data",
    "details": [
      {
        "field": "email",
        "message": "Email format is invalid"
      }
    ]
  }
}
````````````

### HTTP Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Successful GET request |
| 201 | Created | Successful POST (resource created) |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid input data |
| 401 | Unauthorized | Missing or invalid token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Resource already exists |
| 500 | Internal Server Error | Server error |

## Rate Limiting

- **Rate**: 1000 requests per hour per user
- **Header**: \``X-RateLimit-Remaining\``
- **Reset**: \``X-RateLimit-Reset\`` (Unix timestamp)

## Webhooks

### Subscribing to Events

````````````http
POST /api/webhooks
Content-Type: application/json

{
  "url": "https://your-app.com/webhook",
  "events": ["user.created", "user.updated"],
  "secret": "your-webhook-secret"
}
````````````

### Webhook Payload

````````````json
{
  "event": "user.created",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "id": "124",
    "name": "Jane Smith"
  }
}
````````````

## OpenAPI Specification

Full OpenAPI (Swagger) specification available at:
- **Development**: http://localhost:5000/swagger
- **Staging**: https://staging-api.example.com/swagger

## Testing APIs

### Using cURL

````````````bash
curl -X GET "http://localhost:5000/api/users" \
  -H "Authorization: Bearer <token>" \
  -H "Accept: application/json"
````````````

### Using Postman

1. Import collection: \``docs/postman/collection.json\``
2. Set environment variables
3. Run requests

### Using REST Client (VS Code)

Create \``.http\`` files:

````````````http
### Get Users
GET http://localhost:5000/api/users
Authorization: Bearer {{token}}

### Create User
POST http://localhost:5000/api/users
Content-Type: application/json

{
  "name": "Test User",
  "email": "test@example.com"
}
````````````

## Integration Patterns

### Pagination

All list endpoints support pagination:
- \``page\``: Page number (1-based)
- \``size\``: Items per page (max 100)

### Filtering

Use query parameters:
````````````
GET /api/users?role=developer&status=active
````````````

### Sorting

Use \``sort\`` parameter:
````````````
GET /api/users?sort=name:asc,createdAt:desc
````````````

## Versioning Strategy

- **URL Versioning**: \``/api/v1/users\``
- **Header Versioning**: \``X-API-Version: 1.0\``
- **Deprecation Notice**: 6 months before removal

---

**Next Steps**: Update this page as APIs evolve. Link API changes to ADRs.
"@

    # Git Workflow
    $gitWorkflowContent = @"
# Git Workflow & Branching Strategy

Comprehensive guide to Git workflow, branching conventions, and commit best practices.

## Branching Strategy

We use **GitHub Flow** (simplified Git Flow) with protected main branch.

````````````
main (protected) ──────────────────────────────────────→
       ↓                          ↓
    feature/123-add-auth    bugfix/456-fix-crash
       ↓                          ↓
      [commits]                [commits]
       ↓                          ↓
      [PR + Review]           [PR + Review]
       ↓                          ↓
      merge →                 merge →
````````````

## Branch Naming Conventions

**Pattern**: \``<type>/<ticket-number>-<brief-description>\``

### Branch Types

| Type | Usage | Example |
|------|-------|---------|
| \``feature/\`` | New features | \``feature/123-add-user-authentication\`` |
| \``bugfix/\`` | Bug fixes | \``bugfix/456-fix-login-crash\`` |
| \``hotfix/\`` | Urgent production fixes | \``hotfix/789-security-patch\`` |
| \``refactor/\`` | Code refactoring | \``refactor/321-cleanup-api-layer\`` |
| \``docs/\`` | Documentation only | \``docs/234-update-api-guide\`` |
| \``test/\`` | Test improvements | \``test/567-add-integration-tests\`` |

### Rules

✅ **DO**:
- Always include ticket number: \``feature/123-...\``
- Use kebab-case: \``add-user-auth\`` not \``addUserAuth\``
- Be descriptive but concise (max 50 chars)
- Delete branch after merge

❌ **DON'T**:
- Use generic names: \``fix\``, \``update\``, \``temp\``
- Skip ticket number: \``feature/new-feature\``
- Use spaces or special characters

## Commit Message Conventions

### Format

````````````
<type>(<scope>): <subject>

[optional body]

[optional footer]
````````````

### Types

- \``feat\``: New feature
- \``fix\``: Bug fix
- \``docs\``: Documentation changes
- \``style\``: Code style changes (formatting, no logic change)
- \``refactor\``: Code refactoring
- \``test\``: Adding or updating tests
- \``chore\``: Build process, tooling, dependencies

### Examples

**Good**:
````````````
feat(auth): add JWT token validation

Implement JWT token validation middleware with expiry check.
Includes unit tests and error handling.

Closes #123
````````````

**Bad**:
````````````
updated code
````````````

### Rules

✅ **DO**:
- Use imperative mood: "add" not "added"
- Capitalize first letter
- No period at end of subject
- Link to work item: "Closes #123" or "Refs #456"
- Keep subject under 72 characters
- Explain "why" in body, not "what" (code shows "what")

❌ **DON'T**:
- Write vague messages: "fix bug", "update"
- Commit unrelated changes together
- Skip linking work items

## Daily Workflow

### 1. Start New Work

````````````bash
# Update main branch
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/123-add-user-auth

# Verify branch
git branch --show-current
````````````

### 2. Make Changes

````````````bash
# Make changes to files
code src/Auth/AuthService.cs

# Check status
git status

# Review changes
git diff

# Stage changes
git add src/Auth/AuthService.cs
# or stage all
git add .
````````````

### 3. Commit Changes

````````````bash
# Commit with message
git commit -m "feat(auth): add JWT validation middleware"

# Or open editor for detailed message
git commit
````````````

### 4. Push to Remote

````````````bash
# First push (set upstream)
git push -u origin feature/123-add-user-auth

# Subsequent pushes
git push
````````````

### 5. Keep Branch Updated

````````````bash
# Fetch latest main
git checkout main
git pull origin main

# Rebase your branch
git checkout feature/123-add-user-auth
git rebase main

# Or merge (if rebase causes issues)
git merge main

# Push updated branch (may need force-push after rebase)
git push --force-with-lease
````````````

### 6. Create Pull Request

1. Push your branch
2. Go to Azure Repos → Pull Requests
3. Click "New Pull Request"
4. Select: \``feature/123-add-user-auth\`` → \``main\``
5. Fill PR template
6. Link work item (required)
7. Add reviewers
8. Submit

### 7. Address Review Feedback

````````````bash
# Make requested changes
code src/Auth/AuthService.cs

# Commit changes
git add .
git commit -m "refactor(auth): address PR feedback - improve error handling"

# Push to update PR
git push
````````````

### 8. Merge and Cleanup

After PR approval:

````````````bash
# Merge via Azure DevOps UI (recommended)
# Or locally:
git checkout main
git pull origin main
git merge --no-ff feature/123-add-user-auth
git push origin main

# Delete branch
git branch -d feature/123-add-user-auth
git push origin --delete feature/123-add-user-auth
````````````

## Advanced Git Commands

### Fixing Mistakes

#### Undo Last Commit (keep changes)
````````````bash
git reset --soft HEAD~1
````````````

#### Undo Last Commit (discard changes)
````````````bash
git reset --hard HEAD~1
````````````

#### Amend Last Commit Message
````````````bash
git commit --amend -m "new message"
````````````

#### Undo Changes to File
````````````bash
git checkout -- filename.cs
````````````

### Interactive Rebase (Clean History)

````````````bash
# Rebase last 3 commits
git rebase -i HEAD~3

# Options:
# pick - keep commit
# squash - combine with previous
# edit - modify commit
# drop - remove commit
````````````

### Stash Changes (Temporary Save)

````````````bash
# Save current changes
git stash

# List stashes
git stash list

# Apply latest stash
git stash apply

# Apply and remove stash
git stash pop
````````````

### Cherry-Pick (Copy Commit)

````````````bash
# Copy commit to current branch
git cherry-pick <commit-hash>
````````````

## Conflict Resolution

### When Conflicts Occur

````````````bash
# Attempt merge/rebase
git merge main
# CONFLICT: Fix conflicts then continue

# View conflicted files
git status

# Open conflicted file - look for:
<<<<<<< HEAD
your changes
=======
incoming changes
>>>>>>> main

# Edit to resolve, remove markers

# Mark as resolved
git add filename.cs

# Complete merge
git commit
````````````

### Prevention

- Pull \``main\`` frequently
- Keep branches short-lived (< 3 days)
- Communicate with team about shared files

## Git Configuration

### Recommended Settings

````````````bash
# User identity
git config --global user.name "Your Name"
git config --global user.email "your.email@company.com"

# Default editor
git config --global core.editor "code --wait"

# Default branch name
git config --global init.defaultBranch main

# Auto-fix whitespace
git config --global apply.whitespace fix

# Better diff algorithm
git config --global diff.algorithm histogram

# Reuse recorded resolutions
git config --global rerere.enabled true
````````````

### Useful Aliases

````````````bash
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.last 'log -1 HEAD'
git config --global alias.unstage 'reset HEAD --'
````````````

## Best Practices Summary

1. ✅ **Commit early, commit often** - Small, logical commits
2. ✅ **Write meaningful messages** - Explain "why", not "what"
3. ✅ **One feature per branch** - Keep branches focused
4. ✅ **Keep branches up to date** - Pull main daily
5. ✅ **Review before pushing** - Use \``git diff\`` before commit
6. ✅ **Link work items** - Every commit references ticket
7. ✅ **Delete merged branches** - Keep repository clean
8. ✅ **Never commit secrets** - Use .gitignore and .env

---

**Next Steps**: Practice these workflows and see [Code Review Checklist](/Development/Code-Review-Checklist).
"@

    # Code Review Checklist
    $codeReviewContent = @"
# Code Review Checklist

Comprehensive checklist for both code authors and reviewers to ensure high-quality code reviews.

## For Authors: Before Creating PR

### Code Quality

- [ ] **Self-review completed** - Read your own diff line by line
- [ ] **All tests passing** - Run full test suite locally
- [ ] **No console warnings** - Clean build output
- [ ] **Code follows style guide** - Consistent formatting
- [ ] **No commented-out code** - Remove or explain why kept
- [ ] **No debug statements** - Remove console.log, print, etc.
- [ ] **Variable names are clear** - Self-documenting code

### Testing

- [ ] **Unit tests added** - For new functionality
- [ ] **Unit tests updated** - For modified functionality
- [ ] **Edge cases covered** - Null, empty, boundary values
- [ ] **Integration tests** - If touching multiple components
- [ ] **Manual testing done** - Actually used the feature

### Documentation

- [ ] **XML/JSDoc comments** - For public APIs
- [ ] **README updated** - If setup process changed
- [ ] **API docs updated** - If endpoints changed
- [ ] **Wiki updated** - For architectural changes
- [ ] **CHANGELOG entry** - For user-facing changes

### Security

- [ ] **No secrets in code** - Use configuration/environment variables
- [ ] **Input validation** - All user input validated
- [ ] **SQL injection prevented** - Use parameterized queries
- [ ] **XSS prevented** - Escape output, sanitize input
- [ ] **Authentication checked** - Endpoints require auth
- [ ] **Authorization checked** - Users can only access their data

### Performance

- [ ] **No N+1 queries** - Optimize database calls
- [ ] **Appropriate caching** - Cache expensive operations
- [ ] **Large collections paginated** - Don't load all data
- [ ] **No blocking calls** - Use async where appropriate
- [ ] **Resource cleanup** - Dispose connections, streams

### Work Item

- [ ] **Work item linked** - PR references ticket (required)
- [ ] **Description clear** - What/why/testing explained
- [ ] **Screenshots attached** - For UI changes
- [ ] **Reviewers assigned** - 2-3 appropriate reviewers
- [ ] **Labels added** - Mark as feature/bugfix/etc.

## For Reviewers: Review Checklist

### Code Correctness

- [ ] **Logic is sound** - Code does what it claims
- [ ] **Edge cases handled** - Null checks, empty collections
- [ ] **Error handling present** - Try-catch where appropriate
- [ ] **No obvious bugs** - Race conditions, off-by-one errors
- [ ] **Thread-safe** - Concurrent access handled correctly

### Code Quality

- [ ] **Readable code** - Can understand without asking
- [ ] **Appropriate abstractions** - Not over/under-engineered
- [ ] **DRY principle** - No unnecessary duplication
- [ ] **SOLID principles** - Well-structured OOP
- [ ] **Consistent with codebase** - Matches existing patterns
- [ ] **Appropriate complexity** - Not unnecessarily complex

### Testing

- [ ] **Tests are valuable** - Test behavior, not implementation
- [ ] **Tests are maintainable** - Clear arrange-act-assert
- [ ] **Tests are fast** - No unnecessary delays
- [ ] **Test coverage adequate** - Critical paths covered
- [ ] **Tests will catch regressions** - Actually validate functionality

### Performance

- [ ] **No obvious performance issues** - Check algorithms
- [ ] **Database queries optimized** - Indexes, joins appropriate
- [ ] **Memory usage reasonable** - No memory leaks
- [ ] **Network calls minimized** - Batch where possible

### Security

- [ ] **Authentication enforced** - Login required where needed
- [ ] **Authorization enforced** - Permissions checked
- [ ] **Input validated** - Both client and server side
- [ ] **Output escaped** - Prevent XSS
- [ ] **No hardcoded secrets** - Config files not committed
- [ ] **Dependencies secure** - No known vulnerabilities

### Documentation

- [ ] **Code is self-documenting** - Clear naming
- [ ] **Comments explain "why"** - Not "what"
- [ ] **Public APIs documented** - XML/JSDoc present
- [ ] **Complex logic explained** - Non-obvious code has comments

### Architecture

- [ ] **Follows project architecture** - Layers respected
- [ ] **Dependencies appropriate** - Not introducing circular deps
- [ ] **API design consistent** - Follows REST/naming conventions
- [ ] **Database changes safe** - Migrations backward compatible

## Review Feedback Guidelines

### Effective Feedback Format

**Use Clear Categories**:
- **[CRITICAL]**: Must be fixed (blocks merge)
- **[MAJOR]**: Should be fixed (discuss if not)
- **[MINOR]**: Nice to have (optional)
- **[QUESTION]**: Seeking clarification
- **[PRAISE]**: Positive feedback

**Examples**:

✅ **Good Feedback**:
````````````
[CRITICAL] Security: User input not validated
Line 45: userId comes directly from request without validation.
This could allow SQL injection.
Suggestion: Use parameterized query or validate as integer.
````````````

````````````
[MAJOR] Performance: N+1 query detected
Line 120: Loading users in loop will cause N queries.
Consider using Include() or single query with join.
````````````

````````````
[MINOR] Naming: Variable name could be clearer
Line 78: 'temp' doesn't convey purpose.
Consider 'validatedUsers' or 'activeUsers'.
````````````

````````````
[PRAISE] Nice abstraction!
Love how you extracted this into a reusable service.
Makes testing much easier.
````````````

❌ **Poor Feedback**:
````````````
This is wrong.
```````````` 
(Not specific, not actionable)

````````````
Why did you do it this way?
````````````
(Sounds confrontational, no context)

### Feedback Tone

✅ **DO**:
- Be respectful and constructive
- Assume good intent
- Ask questions, don't accuse
- Praise good patterns
- Explain reasoning
- Suggest alternatives
- Offer to pair program for complex issues

❌ **DON'T**:
- Use absolute statements ("This is bad")
- Be condescending ("Obviously this is wrong")
- Nitpick style if auto-formatter exists
- Request changes without explanation
- Block on personal preferences

### Responding to Feedback

**For Authors**:

✅ **DO**:
- Thank reviewer for feedback
- Ask for clarification if unclear
- Explain decisions if needed
- Push back respectfully if you disagree
- Mark resolved after addressing

❌ **DON'T**:
- Take feedback personally
- Get defensive
- Ignore feedback without discussion
- Mark resolved without addressing

## Review Turnaround Time

| PR Type | Target Review Time |
|---------|-------------------|
| **Hotfix** | 2-4 hours |
| **Small PR** (< 200 lines) | 4-8 hours |
| **Medium PR** (200-500 lines) | 1 business day |
| **Large PR** (> 500 lines) | 2 business days |

**If PR is urgent**: Mark with \``urgent\`` label and notify in chat.

## When to Approve

**Approve when**:
- All CRITICAL and MAJOR issues resolved
- Tests passing
- No security concerns
- Code meets quality bar
- Minor issues documented for follow-up

**Request Changes when**:
- Critical security/performance issues
- Tests failing or missing
- Doesn't meet requirements
- Significant refactoring needed

**Comment (no approval) when**:
- Minor suggestions
- Questions for clarification
- Positive feedback only

## Large PR Guidelines

**For PRs > 500 lines**:

1. **Provide Context**: Extra detailed description
2. **Highlight Changes**: Point to key files/changes
3. **Offer Walkthrough**: Schedule 15-min review session
4. **Break Down**: Consider splitting into multiple PRs

**For Reviewers**:
- Schedule dedicated review time
- Review in multiple sessions if needed
- Focus on architecture first, then details
- Use "Start Review" to batch comments

## Automated Checks

Before human review, these should pass:
- ✅ All tests passing
- ✅ Build successful
- ✅ Code coverage > 80%
- ✅ No linting errors
- ✅ Security scan passed
- ✅ Work item linked

## Review Metrics

**Healthy Team Metrics**:
- PR turnaround time: < 24 hours
- Comments per PR: 5-15 (not too few, not too many)
- Review participation: Everyone reviews, not just seniors
- Approval rate: 80%+ on first submission (indicates clear expectations)

---

**Next Steps**: Start reviewing PRs using this checklist. Give constructive feedback!
"@

    # Troubleshooting Guide
    $troubleshootingContent = @"
# Troubleshooting Guide

Common issues and solutions for development, deployment, and runtime problems.

## Table of Contents

1. [Development Environment](#development-environment)
2. [Build Issues](#build-issues)
3. [Runtime Errors](#runtime-errors)
4. [Database Problems](#database-problems)
5. [Authentication Issues](#authentication-issues)
6. [Performance Problems](#performance-problems)
7. [Git Issues](#git-issues)

---

## Development Environment

### Issue: IDE Not Recognizing Project

**Symptoms**: IntelliSense not working, red squiggles everywhere

**Solutions**:

1. **Reload Project**
   ````````````bash
   # VS Code
   Ctrl+Shift+P → "Developer: Reload Window"
   
   # Visual Studio
   File → Close Solution, then reopen
   ````````````

2. **Clear Cache**
   ````````````bash
   # .NET
   dotnet clean
   dotnet restore
   
   # Node.js
   rm -rf node_modules package-lock.json
   npm install
   ````````````

3. **Check SDK Version**
   ````````````bash
   dotnet --version
   node --version
   ````````````

### Issue: Port Already in Use

**Symptoms**: Cannot start application, "Address already in use"

**Solutions**:

**Windows**:
````````````powershell
# Find process using port 5000
netstat -ano | findstr :5000

# Kill process
taskkill /PID <PID> /F
````````````

**Linux/Mac**:
````````````bash
# Find process
lsof -i :5000

# Kill process
kill -9 <PID>
````````````

**Or Change Port**:
- Edit \``appsettings.Development.json\`` or \``.env\``
- Set different port number

---

## Build Issues

### Issue: Build Failed with Compilation Errors

**Symptoms**: "CS0246: Type or namespace not found"

**Solutions**:

1. **Restore Dependencies**
   ````````````bash
   dotnet restore
   ````````````

2. **Clean and Rebuild**
   ````````````bash
   dotnet clean
   dotnet build
   ````````````

3. **Check NuGet Cache**
   ````````````bash
   dotnet nuget locals all --clear
   ````````````

### Issue: Missing Dependencies

**Symptoms**: Module not found, package missing

**Solutions**:

**For .NET**:
````````````bash
dotnet restore
````````````

**For Node.js**:
````````````bash
npm install
# If issues persist
rm -rf node_modules package-lock.json
npm install
````````````

**For Python**:
````````````bash
pip install -r requirements.txt
````````````

### Issue: Build Succeeds Locally but Fails in CI

**Symptoms**: CI build fails with errors not seen locally

**Common Causes**:
- Different SDK versions
- Missing environment variables
- Case-sensitive file paths (Windows vs Linux)
- Uncommitted files

**Solutions**:

1. **Check CI Logs**: Read full build output
2. **Match SDK Version**: Use same version as CI
3. **Test in Container**: 
   ````````````bash
   docker build -t test .
   ````````````

---

## Runtime Errors

### Issue: Null Reference Exception

**Symptoms**: \``NullReferenceException\`` or \``Cannot read property of undefined\``

**Solutions**:

1. **Add Null Checks**:
   ````````````csharp
   if (user == null)
       throw new ArgumentNullException(nameof(user));
   
   // Or use null-conditional
   var email = user?.Email ?? "unknown";
   ````````````

2. **Check Configuration**: Ensure all required settings exist

3. **Debug**: Add breakpoint before exception, inspect values

### Issue: Timeout Exception

**Symptoms**: Request times out, "Operation timed out"

**Solutions**:

1. **Check Network**: Verify service is reachable
   ````````````bash
   ping <hostname>
   telnet <hostname> <port>
   ````````````

2. **Increase Timeout**:
   ````````````csharp
   httpClient.Timeout = TimeSpan.FromSeconds(60);
   ````````````

3. **Optimize Query**: If database timeout, check query performance

### Issue: Out of Memory

**Symptoms**: \``OutOfMemoryException\``, application crashes

**Solutions**:

1. **Identify Memory Leak**:
   - Use memory profiler (dotMemory, Chrome DevTools)
   - Check for event handlers not unsubscribed
   - Look for large collections kept in memory

2. **Implement Pagination**: Don't load all data at once

3. **Dispose Resources**:
   ````````````csharp
   using (var connection = new SqlConnection(...))
   {
       // Use connection
   } // Automatically disposed
   ````````````

---

## Database Problems

### Issue: Connection String Invalid

**Symptoms**: "Cannot connect to database", authentication failed

**Solutions**:

1. **Verify Connection String**:
   ````````````json
   "ConnectionStrings": {
     "Default": "Server=localhost;Database=MyDb;User Id=sa;Password=YourPassword;TrustServerCertificate=true"
   }
   ````````````

2. **Test Connection**:
   - Use SQL Server Management Studio
   - Or Azure Data Studio
   - Verify server, database, credentials

3. **Check Firewall**: Ensure port 1433 (SQL) is open

### Issue: Migration Failed

**Symptoms**: "Migration ... failed to apply"

**Solutions**:

1. **Check Migration History**:
   ````````````bash
   dotnet ef migrations list
   ````````````

2. **Remove Failed Migration**:
   ````````````bash
   dotnet ef database update <last-good-migration>
   dotnet ef migrations remove
   ````````````

3. **Recreate Migration**:
   ````````````bash
   dotnet ef migrations add <MigrationName>
   dotnet ef database update
   ````````````

### Issue: Slow Query Performance

**Symptoms**: Query takes > 5 seconds, application slow

**Solutions**:

1. **Enable Query Logging**:
   ````````````csharp
   options.UseSqlServer(connectionString)
       .LogTo(Console.WriteLine, LogLevel.Information);
   ````````````

2. **Analyze Query Plan**: Look for table scans

3. **Add Indexes**:
   ````````````sql
   CREATE INDEX IX_Users_Email ON Users(Email);
   ````````````

4. **Use Eager Loading**:
   ````````````csharp
   var users = context.Users
       .Include(u => u.Orders)  // Avoid N+1
       .ToList();
   ````````````

---

## Authentication Issues

### Issue: Token Expired

**Symptoms**: "401 Unauthorized" on API calls

**Solutions**:

1. **Refresh Token**: Implement token refresh flow

2. **Check Token Expiry**:
   ````````````javascript
   const token = jwt_decode(accessToken);
   if (token.exp < Date.now() / 1000) {
       // Token expired, refresh
   }
   ````````````

3. **Verify Token Config**: Ensure expiry time is reasonable

### Issue: CORS Error

**Symptoms**: "Access blocked by CORS policy"

**Solutions**:

1. **Configure CORS** (server-side):
   ````````````csharp
   services.AddCors(options =>
   {
       options.AddPolicy("AllowDevClient",
           builder => builder
               .WithOrigins("http://localhost:3000")
               .AllowAnyHeader()
               .AllowAnyMethod());
   });
   ````````````

2. **Use Proxy** (development):
   ````````````json
   // package.json
   "proxy": "http://localhost:5000"
   ````````````

---

## Performance Problems

### Issue: Application Slow

**Symptoms**: High response times, poor user experience

**Debugging Steps**:

1. **Profile Application**:
   - Use Application Insights
   - Check logs for slow operations
   - Use performance profiler

2. **Check Common Causes**:
   - Database N+1 queries
   - Synchronous I/O on hot path
   - Large JSON serialization
   - Missing caching

3. **Add Logging**:
   ````````````csharp
   var stopwatch = Stopwatch.StartNew();
   // Operation
   stopwatch.Stop();
   _logger.LogInformation("Operation took {Ms}ms", stopwatch.ElapsedMilliseconds);
   ````````````

### Issue: High CPU Usage

**Solutions**:

1. **Profile CPU**: Use profiler to find hot paths

2. **Check for Infinite Loops**

3. **Optimize Algorithms**: O(n²) → O(n log n)

4. **Add Caching**: Cache expensive computations

---

## Git Issues

### Issue: Merge Conflict

**Symptoms**: "CONFLICT: Merge conflict in..."

**Solutions**:

1. **Abort and Start Over**:
   ````````````bash
   git merge --abort
   # or
   git rebase --abort
   ````````````

2. **Resolve Manually**:
   - Open conflicted file
   - Look for \``<<<<<<\``, \``======\``, \``>>>>>>\``
   - Edit to keep desired changes
   - Remove markers
   - \``git add <file>\``
   - \``git commit\`` or \``git rebase --continue\``

3. **Use Merge Tool**:
   ````````````bash
   git mergetool
   ````````````

### Issue: Accidentally Committed Secrets

**Solutions**:

1. **Remove from History** (if not pushed):
   ````````````bash
   git reset --soft HEAD~1
   # Edit files to remove secrets
   git add .
   git commit
   ````````````

2. **If Already Pushed**:
   - ⚠️ **ROTATE SECRETS IMMEDIATELY**
   - Use BFG Repo-Cleaner or git-filter-branch
   - Force push (coordinate with team)

3. **Prevention**: Use \``.gitignore\`` and pre-commit hooks

---

## Getting Help

### Before Asking for Help

1. ✅ **Search Documentation**: Check wiki and README
2. ✅ **Search Previous Issues**: Someone may have solved it
3. ✅ **Try Debugging**: Add logs, breakpoints
4. ✅ **Isolate Problem**: Minimal reproduction case

### When Asking for Help

**Provide**:
- Clear description of problem
- Steps to reproduce
- Expected vs actual behavior
- Error messages (full stack trace)
- Environment (OS, SDK version, etc.)
- What you've tried

**Template**:
````````````
Problem: Application crashes on startup

Environment:
- OS: Windows 11
- .NET SDK: 8.0.100
- IDE: VS Code 1.85

Steps to reproduce:
1. Clone repository
2. Run: dotnet run
3. Application crashes

Error:
System.NullReferenceException at Startup.cs:42

What I've tried:
- Cleared bin/obj folders
- Restored packages
- Checked connection string

Stack trace:
[paste full stack trace]
````````````

### Escalation Path

1. **Team Chat**: Quick questions
2. **Team Member**: Pair programming session
3. **Tech Lead**: Architectural questions
4. **External**: Stack Overflow, GitHub issues

---

**Remember**: Every issue is a learning opportunity! Document solutions you find for others.
"@

    # Dependencies
    $dependenciesContent = @"
# Dependencies & Third-Party Libraries

Comprehensive guide to managing project dependencies and third-party libraries.

## Overview

This project uses several third-party libraries and frameworks. Understanding these dependencies is crucial for development, security, and maintenance.

## Dependency Management

### Package Managers

**For .NET Projects**:
- **NuGet**: Primary package manager
- Config: \``*.csproj\`` files and \``NuGet.config\``
- Restore: \``dotnet restore\``

**For Node.js Projects**:
- **npm** or **yarn**: JavaScript package managers
- Config: \``package.json\`` and \``package-lock.json\``
- Install: \``npm install\`` or \``yarn install\``

**For Python Projects**:
- **pip**: Python package manager
- Config: \``requirements.txt\`` or \``pyproject.toml\``
- Install: \``pip install -r requirements.txt\``

### Version Pinning Strategy

**Semantic Versioning**: \``MAJOR.MINOR.PATCH\``

| Symbol | Meaning | Example | Allows |
|--------|---------|---------|--------|
| \``^\`` | Compatible | \``^1.2.3\`` | 1.2.3 to < 2.0.0 |
| \``~\`` | Patch-level | \``~1.2.3\`` | 1.2.3 to < 1.3.0 |
| None | Exact | \``1.2.3\`` | Exactly 1.2.3 |
| \``*\`` | Any | \``*\`` | Any version (⚠️ not recommended) |

**Our Policy**:
- **Production Dependencies**: Pin exact versions or use \``~\`` for patches
- **Development Dependencies**: Can use \``^\`` for flexibility
- **Security Updates**: Apply immediately after testing

## Core Dependencies

### Runtime Dependencies

#### .NET Projects

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| Microsoft.AspNetCore.App | 8.0.x | Web framework | MIT |
| Microsoft.EntityFrameworkCore | 8.0.x | ORM | MIT |
| Newtonsoft.Json | 13.0.3 | JSON serialization | MIT |
| Serilog.AspNetCore | 8.0.x | Logging | Apache 2.0 |
| AutoMapper | 12.0.x | Object mapping | MIT |

#### Node.js Projects

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| express | ^4.18.0 | Web framework | MIT |
| axios | ^1.6.0 | HTTP client | MIT |
| lodash | ^4.17.21 | Utility functions | MIT |
| dotenv | ^16.3.0 | Environment config | BSD-2-Clause |

#### Python Projects

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| fastapi | ^0.104.0 | Web framework | MIT |
| sqlalchemy | ^2.0.0 | ORM | MIT |
| pydantic | ^2.5.0 | Data validation | MIT |
| requests | ^2.31.0 | HTTP client | Apache 2.0 |

### Development Dependencies

| Package | Purpose |
|---------|---------|
| xunit/jest/pytest | Unit testing |
| Moq/sinon/pytest-mock | Mocking |
| FluentAssertions | Test assertions |
| Faker/bogus | Test data generation |
| ESLint/Ruff | Linting |

## Adding New Dependencies

### Before Adding a Dependency

**Ask**:
1. ✅ **Is it necessary?** - Can we implement it ourselves simply?
2. ✅ **Is it maintained?** - Recent commits, active issues?
3. ✅ **Is it secure?** - Known vulnerabilities?
4. ✅ **Is the license compatible?** - Check license restrictions
5. ✅ **Is it the right tool?** - Better alternatives?
6. ✅ **What's the bundle size?** - For frontend dependencies

### Approval Process

**For New Dependencies**:
1. Create work item describing need
2. Research alternatives (document in ADR)
3. Get approval from tech lead
4. Add dependency
5. Update this documentation
6. Update license compliance doc

### Installation

**.NET**:
````````````bash
dotnet add package PackageName --version 1.2.3
````````````

**Node.js**:
````````````bash
npm install package-name@1.2.3 --save
# or for dev dependency
npm install package-name@1.2.3 --save-dev
````````````

**Python**:
````````````bash
pip install package-name==1.2.3
pip freeze > requirements.txt  # Update requirements
````````````

## Updating Dependencies

### Regular Updates

**Schedule**: Check for updates monthly

**Process**:
1. Check for outdated packages
2. Review changelogs
3. Test in development
4. Update documentation
5. Create PR with updates

### Commands

**.NET**:
````````````bash
# Check outdated
dotnet list package --outdated

# Update package
dotnet add package PackageName
````````````

**Node.js**:
````````````bash
# Check outdated
npm outdated

# Update specific package
npm update package-name

# Interactive updater (recommended)
npx npm-check-updates -i
````````````

**Python**:
````````````bash
# Check outdated
pip list --outdated

# Update package
pip install --upgrade package-name
````````````

### Security Updates

**Priority**: Apply within 48 hours for high/critical

**Check for Vulnerabilities**:

**.NET**:
````````````bash
dotnet list package --vulnerable
````````````

**Node.js**:
````````````bash
npm audit
npm audit fix
````````````

**Python**:
````````````bash
pip-audit
# or
safety check
````````````

### Breaking Changes

**When Major Version Updates**:
1. Read migration guide
2. Create feature branch
3. Update code for breaking changes
4. Run full test suite
5. Test manually
6. Document changes in commit message

## Dependency Security

### Best Practices

✅ **DO**:
- Keep dependencies updated
- Review security advisories
- Use dependency scanning tools
- Lock versions in production
- Audit new dependencies before adding
- Remove unused dependencies

❌ **DON'T**:
- Use dependencies with known vulnerabilities
- Add dependencies without review
- Use wildcards in production (\``*\``)
- Install packages globally that should be project-local

### Security Scanning

**Automated Scans**:
- GitHub Dependabot
- Snyk
- npm audit / dotnet list package --vulnerable
- OWASP Dependency-Check

**Manual Review**:
- Check CVE databases
- Review library GitHub issues
- Search for "CVE-YYYY-NNNNN" + package name

## License Compliance

### Allowed Licenses

✅ **Permissive** (generally okay):
- MIT
- Apache 2.0
- BSD (2-clause, 3-clause)
- ISC

⚠️ **Copyleft** (requires review):
- GPL (v2, v3)
- LGPL
- AGPL

❌ **Restricted** (not allowed):
- Proprietary without license
- "All Rights Reserved"

### Checking Licenses

**.NET**:
````````````bash
dotnet list package --include-transitive
# Check PackageProjectUrl for license
````````````

**Node.js**:
````````````bash
npx license-checker --summary
````````````

**Python**:
````````````bash
pip-licenses
````````````

## Common Dependencies Explained

### Logging: Serilog/Winston/Python logging

**Purpose**: Structured logging  
**Why**: Better than console.log, searchable, filterable  
**Usage**:
````````````csharp
_logger.LogInformation("User {UserId} logged in", userId);
````````````

### ORM: Entity Framework Core/TypeORM/SQLAlchemy

**Purpose**: Database abstraction  
**Why**: Type-safe queries, migrations, prevents SQL injection  
**Usage**:
````````````csharp
var users = await context.Users
    .Where(u => u.IsActive)
    .ToListAsync();
````````````

### Testing: xUnit/Jest/pytest

**Purpose**: Unit testing framework  
**Why**: Automated testing, regression prevention  
**Usage**:
````````````csharp
[Fact]
public void Should_Return_User_When_Valid_Id()
{
    // Arrange, Act, Assert
}
````````````

### HTTP Client: HttpClient/Axios/Requests

**Purpose**: Make HTTP requests  
**Why**: Interact with external APIs  
**Usage**:
````````````javascript
const response = await axios.get('/api/users');
````````````

## Troubleshooting Dependency Issues

### Issue: Package Not Found

**Solution**:
1. Check package name spelling
2. Clear package cache
3. Check package source/registry
4. Verify network connectivity

### Issue: Version Conflict

**Solution**:
````````````bash
# .NET
dotnet restore --force

# Node.js
rm package-lock.json
npm install

# Python
pip install --force-reinstall package-name
````````````

### Issue: Transitive Dependency Vulnerability

**Solution**:
- Update parent package
- Use dependency override/resolution
- Contact maintainer if not fixed

## Resources

- **NuGet Gallery**: https://www.nuget.org/
- **npm Registry**: https://www.npmjs.com/
- **PyPI**: https://pypi.org/
- **Snyk Vulnerability DB**: https://snyk.io/vuln
- **Common Vulnerabilities**: https://cve.mitre.org/

---

**Next Steps**: Keep dependencies updated monthly and check security advisories weekly.
"@

    # Create all wiki pages
    try {
        Upsert-AdoWikiPage $Project $WikiId "/Development/Architecture-Decision-Records" $adrContent
        Write-Host "  ✅ Architecture Decision Records" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Development-Setup" $devSetupContent
        Write-Host "  ✅ Development Setup" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/API-Documentation" $apiDocsContent
        Write-Host "  ✅ API Documentation" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Git-Workflow" $gitWorkflowContent
        Write-Host "  ✅ Git Workflow" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Code-Review-Checklist" $codeReviewContent
        Write-Host "  ✅ Code Review Checklist" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Troubleshooting" $troubleshootingContent
        Write-Host "  ✅ Troubleshooting" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Dependencies" $dependenciesContent
        Write-Host "  ✅ Dependencies" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] Development wiki pages created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create some development wiki pages: $_"
    }
}

<#
.SYNOPSIS
    Creates a development dashboard with PR and code quality metrics.

.DESCRIPTION
    Provisions a dashboard for development teams with widgets tracking:
    - Pull Request turnaround time
    - Code review velocity
    - Active PR count
    - Build success rate
    - Work item burndown
    - Test pass rate

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER WikiId
    Wiki identifier for creating component tags page.

.EXAMPLE
    Ensure-AdoDevDashboard -Project "MyProject" -WikiId "wiki-guid"
#>
function Ensure-AdoDevDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating development dashboard..." -ForegroundColor Cyan
    
    try {
        # Check if dashboard already exists
        $dashboards = Invoke-AdoRest GET "/$Project/_apis/dashboard/dashboards?api-version=7.1-preview.3"
        $devDashboard = $dashboards.dashboardEntries | Where-Object { $_.name -eq "Development Metrics" }
        
        if ($devDashboard) {
            Write-Host "  ℹ️ Development dashboard already exists" -ForegroundColor DarkYellow
            return
        }
        
        # Create dashboard
        $dashboardConfig = @{
            name = "Development Metrics"
            description = "Track PR velocity, code quality, and team productivity"
            widgets = @(
                # Pull Request Overview
                @{
                    name = "Active Pull Requests"
                    position = @{ row = 1; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.PullRequestWidget"
                }
                # Build Success Rate
                @{
                    name = "Build Success Rate"
                    position = @{ row = 1; column = 3 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.BuildHistogramWidget"
                }
                # Work in Progress
                @{
                    name = "Work in Progress"
                    position = @{ row = 2; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-work-web.Microsoft.VisualStudioOnline.MyWork.WorkWidget"
                }
                # Sprint Burndown
                @{
                    name = "Sprint Burndown"
                    position = @{ row = 2; column = 3 }
                    size = @{ rowSpan = 2; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.SprintBurndownWidget"
                }
                # Test Results Trend
                @{
                    name = "Test Pass Rate"
                    position = @{ row = 3; column = 1 }
                    size = @{ rowSpan = 1; columnSpan = 2 }
                    settings = $null
                    contributionId = "ms.vss-test-web.test-results-trending-widget"
                }
            )
        }
        
        $dashboard = Invoke-AdoRest POST "/$Project/_apis/dashboard/dashboards?api-version=7.1-preview.3" -Body $dashboardConfig
        Write-Host "  ✅ Development Metrics dashboard created" -ForegroundColor Gray
        
        # Create component tags wiki page
        $componentTagsContent = @"
# Component Tags & Categorization

This page documents the tagging conventions used to categorize work items, PRs, and code components.

## Technical Components

Use these tags to identify which technical area a work item affects:

- ````api```` - Backend API/REST services
- ````ui```` - Frontend/User Interface
- ````database```` - Database schema/queries
- ````cache```` - Caching layer (Redis, in-memory)
- ````messaging```` - Message queues/event bus
- ````auth```` - Authentication/Authorization
- ````integration```` - Third-party integrations
- ````infrastructure```` - DevOps/Cloud infrastructure
- ````testing```` - Test frameworks/infrastructure
- ````docs```` - Documentation

## Environment Tags

- ````dev```` - Development environment
- ````staging```` - Staging/QA environment
- ````prod```` - Production environment
- ````local```` - Local development only

## Technical Categories

- ````tech-debt```` - Technical debt requiring refactoring
- ````refactor```` - Code refactoring (no behavior change)
- ````performance```` - Performance optimization
- ````security```` - Security improvements/fixes
- ````accessibility```` - Accessibility (a11y) improvements
- ````monitoring```` - Logging/monitoring/observability
- ````scalability```` - Scalability improvements

## Priority Tags

- ````urgent```` - Needs immediate attention
- ````blocked```` - Work is blocked by dependency
- ````needs-review```` - Requires code/design review
- ````breaking-change```` - Contains breaking changes

## Quality Tags

- ````bug```` - Bug fix
- ````hotfix```` - Urgent production fix
- ````regression```` - Previously working feature broke
- ````known-issue```` - Documented limitation

## Usage Guidelines

### Work Items

**Add tags** when creating or updating work items:
1. At least one **component tag** (what area)
2. One **environment tag** if environment-specific
3. One **category tag** if applicable
4. **Priority tags** as needed

**Example**: A performance issue in the API affecting production:
- Tags: ````api````, ````performance````, ````prod````

### Pull Requests

**Link work items** to PRs to inherit tags automatically.

**Add PR labels** that mirror tags:
- ````component:api````
- ````type:performance````
- ````priority:urgent````

### Queries

**Filter by tags** in WIQL queries:

````````````sql
SELECT [System.Id], [System.Title]
FROM WorkItems
WHERE [System.Tags] CONTAINS 'api'
  AND [System.Tags] CONTAINS 'performance'
  AND [System.State] = 'Active'
````````````

### Dashboards

**Create tag-based widgets**:
- Active tech debt items: ````Tags CONTAINS 'tech-debt'````
- Production issues: ````Tags CONTAINS 'prod' AND Type = 'Bug'````
- Blocked work: ````Tags CONTAINS 'blocked'````

## Tag Best Practices

✅ **DO**:
- Use lowercase tags
- Use hyphens for multi-word tags (````tech-debt````, not ````techdebt````)
- Be consistent with existing tags
- Add tags early in work item lifecycle
- Review and clean up obsolete tags

❌ **DON'T**:
- Create duplicate tags with different spelling
- Use spaces in tags (use hyphens)
- Over-tag (more than 5 tags per item)
- Use ambiguous tags (be specific)

## Tag Management

### Finding Tag Usage

**Query all work items** with specific tag:

````````````powershell
# Azure DevOps CLI
az boards query --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.Tags] CONTAINS 'api'"
````````````

**Dashboard widget** for tag distribution.

### Cleaning Up Tags

**Remove obsolete tags**:
1. Identify rarely-used tags
2. Decide: merge, rename, or delete
3. Bulk-update work items
4. Document changes in this wiki

**Merge similar tags**:
- ````performance```` + ````perf```` → ````performance````
- ````ui```` + ````frontend```` → ````ui````

### Adding New Tags

**Before creating a new tag**:
1. Check if similar tag exists
2. Discuss with team if unsure
3. Document in this wiki
4. Announce in team channel

## Component Ownership

| Component | Team/Owner | Slack Channel |
|-----------|-----------|---------------|
| ````api```` | Backend Team | #team-backend |
| ````ui```` | Frontend Team | #team-frontend |
| ````database```` | Data Team | #team-data |
| ````infrastructure```` | DevOps Team | #team-devops |
| ````auth```` | Security Team | #team-security |

## Reporting

### Monthly Tag Report

**Metrics to track**:
- Most-used component tags
- Tech debt backlog size
- Blocked work items
- Environment-specific issues

**Review quarterly** to optimize tagging strategy.

### Tag Hygiene Checklist

**Weekly**:
- [ ] Remove typo/duplicate tags
- [ ] Verify new tags are documented

**Monthly**:
- [ ] Review tag usage metrics
- [ ] Clean up obsolete tags
- [ ] Update tag documentation

**Quarterly**:
- [ ] Assess tag effectiveness
- [ ] Consider new tags for emerging needs
- [ ] Archive unused tags

---

**Questions?** Ask in #team-devops or update this wiki page.
"@
        
        Upsert-AdoWikiPage $Project $WikiId "/Development/Component-Tags" $componentTagsContent
        Write-Host "  ✅ Component Tags wiki page created" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] Development dashboard created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create development dashboard: $_"
        Write-Host "[INFO] Note: Dashboard creation requires appropriate permissions" -ForegroundColor DarkYellow
    }
}

<#
.SYNOPSIS
    Creates security-focused wiki pages for DevSecOps team enablement.

.DESCRIPTION
    Provisions comprehensive wiki structure for security teams including:
    - Security Policies (authentication, authorization, data protection)
    - Threat Modeling Guide (STRIDE methodology)
    - Security Testing Checklist (SAST, DAST, dependency scanning)
    - Incident Response Plan
    - Compliance Requirements (GDPR, SOC2)
    - Secret Management practices
    - Security Champions Program

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER WikiId
    Wiki identifier.

.EXAMPLE
    Ensure-AdoSecurityWiki -Project "MyProject" -WikiId "wiki-id-123"
#>
function Ensure-AdoSecurityWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating security wiki pages..." -ForegroundColor Cyan
    
    # Security Policies
    $securityPoliciesContent = @"
# Security Policies

This page documents the security policies and standards for the project.

## Authentication & Authorization

### Authentication Requirements

**Multi-Factor Authentication (MFA)**:
- ✅ **Required** for all production systems
- ✅ **Required** for administrators and privileged users
- ✅ **Recommended** for all users

**Password Policy**:
- Minimum 12 characters
- Must include: uppercase, lowercase, numbers, special characters
- No common passwords or dictionary words
- Rotate every 90 days for privileged accounts
- No password reuse (last 10 passwords)

**Service Accounts**:
- Use managed identities where possible
- Store credentials in Azure Key Vault
- Rotate credentials every 90 days
- Principle of least privilege
- Document all service accounts in wiki

### Authorization Model

**Role-Based Access Control (RBAC)**:
- Assign minimum necessary permissions
- Regular access reviews (quarterly)
- Disable accounts within 24 hours of termination
- Use groups for permission assignment

**Privilege Levels**:
- **Read**: View-only access to non-sensitive resources
- **Contribute**: Create and modify resources
- **Admin**: Full control (requires approval)
- **Owner**: Complete administrative rights (C-level only)

## Data Protection

### Data Classification

| Level | Description | Examples | Protection |
|-------|-------------|----------|------------|
| **Public** | No harm if disclosed | Marketing materials | Standard controls |
| **Internal** | Limited distribution | Internal docs | Access controls |
| **Confidential** | Sensitive business data | Financial reports | Encryption + MFA |
| **Restricted** | Highly sensitive | PII, PHI, PCI | Encryption + Audit + DLP |

### Encryption Standards

**Data at Rest**:
- AES-256 encryption for databases
- Encrypted storage accounts
- Encrypted backups
- Key management via Azure Key Vault

**Data in Transit**:
- TLS 1.2 or higher only
- Strong cipher suites
- Certificate validation
- No self-signed certificates in production

**Personal Identifiable Information (PII)**:
- Encrypt in database (column-level)
- Mask in logs and error messages
- Pseudonymization where possible
- Data retention policies enforced

### Data Handling

**Development & Testing**:
- ❌ No production data in non-production environments
- ✅ Use synthetic or anonymized data
- ✅ Scrub PII from test datasets
- ✅ Document data lineage

**Data Retention**:
- Logs: 90 days (operational), 1 year (security)
- Backups: 30 days (hot), 7 years (compliance)
- User data: Per GDPR/privacy policy
- Delete data securely (shredding, crypto-erasure)

## Network Security

### Network Segmentation

**DMZ (Demilitarized Zone)**:
- Public-facing services only
- No direct access to internal network
- WAF (Web Application Firewall) required

**Application Tier**:
- Application servers
- API gateways
- No direct internet access

**Data Tier**:
- Databases
- Data warehouses
- Private subnet only
- No internet access

### Firewall Rules

**Principles**:
- Default deny all
- Whitelist only required ports/protocols
- Document business justification
- Review quarterly

**Common Ports**:
- HTTP: 80 (redirect to HTTPS)
- HTTPS: 443
- SSH: 22 (key-based only, VPN required)
- RDP: 3389 (disabled or VPN only)

## Application Security

### Secure Coding Standards

**Input Validation**:
- Validate all input (whitelist approach)
- Sanitize before processing
- Use parameterized queries (prevent SQL injection)
- Encode output (prevent XSS)

**Error Handling**:
- No sensitive data in error messages
- Generic errors to users
- Detailed logs server-side
- Centralized logging

**Session Management**:
- Secure session tokens (HTTPOnly, Secure flags)
- Session timeout: 15 minutes inactivity
- Logout invalidates session
- CSRF protection on state-changing operations

### Third-Party Dependencies

**Before Adding Dependency**:
1. Check for known vulnerabilities
2. Review license compatibility
3. Verify active maintenance
4. Document in dependency catalog
5. Get security approval for critical dependencies

**Ongoing Management**:
- Automated dependency scanning
- Monthly vulnerability checks
- Update within 30 days (high/critical)
- Document exceptions

## Cloud Security

### Azure Security Baseline

**Identity**:
- Azure AD for authentication
- Conditional access policies
- Privileged Identity Management (PIM)

**Network**:
- Virtual network isolation
- Network Security Groups (NSGs)
- Azure Firewall or third-party NVA

**Data**:
- Azure Storage encryption
- Transparent Data Encryption (TDE) for SQL
- Customer-managed keys where required

**Monitoring**:
- Azure Security Center enabled
- Log Analytics workspace
- Security alerts configured

## Incident Response

See [Incident Response Plan](/Security/Incident-Response-Plan) for detailed procedures.

**Severity Levels**:
- **Critical**: Data breach, ransomware, system compromise
- **High**: Attempted breach, malware detected, DDoS
- **Medium**: Policy violation, suspicious activity
- **Low**: Failed login attempts, minor policy issues

**Response Time**:
- Critical: 15 minutes
- High: 1 hour
- Medium: 4 hours
- Low: 24 hours

## Compliance

See [Compliance Requirements](/Security/Compliance-Requirements) for detailed regulations.

**Applicable Standards**:
- GDPR (if EU data)
- SOC 2 Type II
- ISO 27001
- Industry-specific (HIPAA, PCI DSS, etc.)

**Audit Trail**:
- All privileged actions logged
- Logs immutable and tamper-proof
- 1-year retention minimum
- Regular compliance audits

## Security Training

**Required Training**:
- Security awareness (annual, all staff)
- Secure coding (annual, developers)
- Incident response (semi-annual, security team)
- Compliance training (as needed)

**Security Champions**:
- One per team/squad
- Monthly security meetings
- Security advocacy
- First point of contact for security questions

## Policy Exceptions

**Exception Process**:
1. Document risk and business justification
2. Propose compensating controls
3. Get security team approval
4. CISO sign-off for high-risk exceptions
5. Review every 6 months

**Temporary Exceptions**:
- Maximum 90 days
- Documented remediation plan
- Progress tracking required

---

**Policy Owner**: CISO  
**Last Review**: [Date]  
**Next Review**: [Date + 1 year]  
**Questions**: #security or security@company.com
"@

    # Threat Modeling Guide
    $threatModelingContent = @"
# Threat Modeling Guide

Systematic approach to identifying and mitigating security threats.

## What is Threat Modeling?

Threat modeling is a structured process to:
1. **Identify** potential security threats
2. **Analyze** likelihood and impact
3. **Prioritize** risks
4. **Mitigate** through design changes or controls

**When to Threat Model**:
- New features or systems
- Architecture changes
- Before security-sensitive code
- After security incidents (lessons learned)

## STRIDE Methodology

STRIDE is a mnemonic for six threat categories:

### S - Spoofing Identity

**Definition**: Attacker pretends to be someone/something else.

**Examples**:
- Stolen credentials
- Forged authentication tokens
- Man-in-the-middle attacks

**Mitigations**:
- Strong authentication (MFA)
- Mutual TLS
- Digital signatures
- Certificate pinning

### T - Tampering with Data

**Definition**: Unauthorized modification of data.

**Examples**:
- SQL injection
- Parameter tampering
- Message replay attacks

**Mitigations**:
- Input validation
- Parameterized queries
- Digital signatures
- Integrity checks (hashes)
- Immutable logs

### R - Repudiation

**Definition**: User denies performing an action.

**Examples**:
- No audit trail
- Unsigned transactions
- Lack of logging

**Mitigations**:
- Comprehensive logging
- Digital signatures
- Audit trails
- Non-repudiation mechanisms

### I - Information Disclosure

**Definition**: Exposure of confidential information.

**Examples**:
- Verbose error messages
- Unencrypted data transmission
- SQL injection revealing data
- Directory traversal

**Mitigations**:
- Encryption (at rest and in transit)
- Generic error messages
- Proper access controls
- Data masking/redaction

### D - Denial of Service

**Definition**: Making system unavailable to legitimate users.

**Examples**:
- Resource exhaustion
- DDoS attacks
- Algorithmic complexity attacks

**Mitigations**:
- Rate limiting
- Input size limits
- Timeout configurations
- Load balancing
- DDoS protection (Cloudflare, Azure DDoS)

### E - Elevation of Privilege

**Definition**: Gaining higher privileges than authorized.

**Examples**:
- Buffer overflow
- SQL injection to admin
- Privilege escalation bugs

**Mitigations**:
- Principle of least privilege
- Input validation
- Regular security patching
- Secure coding practices

## Threat Modeling Process

### Step 1: Define Scope

**Questions**:
- What are we building?
- What assets are we protecting?
- Who are the users?
- What are trust boundaries?

**Deliverable**: System context diagram

### Step 2: Identify Assets

**Data Assets**:
- User credentials
- Personal information (PII)
- Financial data
- Intellectual property
- Configuration data

**System Assets**:
- Authentication service
- Payment processor
- Database servers
- API endpoints

**Criticality Rating**:
- **High**: Data breach = severe impact
- **Medium**: Degraded functionality
- **Low**: Minimal impact

### Step 3: Create Architecture Diagram

**Components to Include**:
- External entities (users, systems)
- Processes (application components)
- Data stores (databases, caches)
- Data flows (APIs, messages)
- Trust boundaries (network, privilege)

**Example Symbols**:
````````````
[User] --HTTPS--> [Web App] --SQL--> [Database]
         (TLS)                 (Encrypted)
````````````

### Step 4: Identify Threats (STRIDE)

For each data flow and component, apply STRIDE:

| Component | STRIDE Category | Threat | Likelihood | Impact |
|-----------|----------------|--------|------------|--------|
| Login API | Spoofing | Brute force | High | High |
| Login API | Tampering | Parameter manipulation | Medium | High |
| Database | Information Disclosure | SQL injection | Medium | Critical |

### Step 5: Rate Threats (DREAD)

**DREAD Scoring** (1-10 scale):
- **D**amage: How bad if exploited?
- **R**eproducibility: How easy to reproduce?
- **E**xploitability: How easy to exploit?
- **A**ffected Users: How many users impacted?
- **D**iscoverability: How easy to find?

**Risk Score** = (D + R + E + A + D) / 5

| Score | Risk Level | Action |
|-------|-----------|--------|
| 8-10 | Critical | Fix immediately |
| 6-7.9 | High | Fix before release |
| 4-5.9 | Medium | Fix in next sprint |
| 1-3.9 | Low | Document, consider fix |

### Step 6: Mitigate Threats

**Mitigation Strategies**:
1. **Redesign**: Change architecture to eliminate threat
2. **Security Control**: Add authentication, encryption, etc.
3. **Accept Risk**: Document why risk is acceptable
4. **Transfer Risk**: Insurance, third-party service

**Document**:
- Threat ID
- Mitigation approach
- Owner
- Target completion date

### Step 7: Validate Mitigations

**Validation Methods**:
- Security testing (SAST, DAST, penetration testing)
- Code review
- Threat model review (security team)
- Red team exercises

## Attack Surface Analysis

**Attack Vectors**:
- Web interfaces (XSS, CSRF, injection)
- APIs (broken authentication, excessive data exposure)
- Network (DDoS, eavesdropping)
- Physical (device theft, social engineering)
- Supply chain (compromised dependencies)

**Reducing Attack Surface**:
- Minimize exposed endpoints
- Disable unused features
- Principle of least privilege
- Input validation everywhere
- Regular security patching

## Common Threat Scenarios

### Scenario 1: E-commerce Checkout

**Assets**: Payment info, user data, inventory

**Threats**:
- Payment data interception (Information Disclosure)
- Price manipulation (Tampering)
- Fake orders (Spoofing)
- Inventory exhaustion (Denial of Service)

**Mitigations**:
- PCI DSS compliance
- TLS 1.2+
- Server-side price validation
- Rate limiting

### Scenario 2: API Authentication

**Assets**: User credentials, API tokens

**Threats**:
- Credential stuffing (Spoofing)
- Token theft (Spoofing)
- API abuse (Denial of Service)

**Mitigations**:
- OAuth 2.0 / OpenID Connect
- Short-lived tokens
- Refresh token rotation
- Rate limiting per user

### Scenario 3: File Upload

**Assets**: Server filesystem, user data

**Threats**:
- Malware upload (Tampering)
- Path traversal (Elevation of Privilege)
- Resource exhaustion (Denial of Service)

**Mitigations**:
- File type validation (whitelist)
- Antivirus scanning
- Size limits
- Store outside webroot
- Randomized filenames

## Threat Modeling Tools

**Recommended Tools**:
- **Microsoft Threat Modeling Tool**: Free, STRIDE-based
- **OWASP Threat Dragon**: Open source, diagramming
- **IriusRisk**: Commercial, automated threat detection
- **Draw.io**: Manual diagramming

## Documentation Template

````````````markdown
# Threat Model: [Feature Name]

## Scope
- Feature: [Description]
- Assets: [List]
- Trust Boundaries: [Diagram]

## Threats Identified

| ID | Component | STRIDE | Threat | Risk Score | Mitigation | Owner | Status |
|----|-----------|--------|--------|------------|------------|-------|--------|
| T-001 | Login API | S | Brute force | 8.5 | Rate limiting | @security | Done |
| T-002 | Database | I | SQL injection | 9.0 | Parameterized queries | @dev | In Progress |

## Accepted Risks

| ID | Threat | Justification | Compensating Controls |
|----|--------|---------------|----------------------|
| R-001 | [Threat] | [Business reason] | [Alternative controls] |
````````````

---

**Next Steps**:
1. Schedule threat modeling session
2. Invite: Architects, Developers, Security team
3. Use template above
4. Create work items for mitigations
5. Track in [Security Review Required query](/Security/Queries)

**Questions?** #security or security@company.com
"@

    # Security Testing Checklist
    $securityTestingContent = @"
# Security Testing Checklist

Comprehensive checklist for security testing throughout SDLC.

## Testing Types

### SAST (Static Application Security Testing)

**Purpose**: Analyze source code for vulnerabilities before runtime.

**Tools**:
- **SonarQube**: Code quality + security
- **Checkmarx**: Enterprise SAST
- **Semgrep**: Open source, customizable rules
- **GitHub Advanced Security**: Code scanning

**When to Run**:
- Every commit (PR validation)
- Before merging to main
- Scheduled scans (daily)

**Common Findings**:
- SQL injection vulnerabilities
- XSS (Cross-Site Scripting)
- Hardcoded secrets
- Insecure randomness
- Path traversal

**Pass Criteria**:
- Zero high/critical issues
- All medium issues reviewed
- Technical debt documented

### DAST (Dynamic Application Security Testing)

**Purpose**: Test running application for vulnerabilities.

**Tools**:
- **OWASP ZAP**: Open source, automated scanning
- **Burp Suite**: Manual + automated testing
- **Acunetix**: Web vulnerability scanner
- **Netsparker**: Automated DAST

**When to Run**:
- After deployment to QA/staging
- Before production release
- Monthly in production

**Common Findings**:
- Authentication bypass
- Authorization flaws
- Session management issues
- Security misconfigurations
- Sensitive data exposure

**Pass Criteria**:
- Zero high/critical vulnerabilities
- All medium issues have mitigation plan
- Signed off by security team

### Dependency Scanning

**Purpose**: Identify vulnerabilities in third-party libraries.

**Tools**:
- **Dependabot**: GitHub-native, automated PRs
- **Snyk**: Comprehensive dependency + container scanning
- **WhiteSource**: Enterprise license + vulnerability management
- **npm audit** / **dotnet list package --vulnerable**

**When to Run**:
- Every build
- Daily scheduled scans
- Before adding new dependency

**Pass Criteria**:
- No critical vulnerabilities
- High vulnerabilities: Fix within 7 days
- Medium vulnerabilities: Fix within 30 days

### Container Scanning

**Purpose**: Find vulnerabilities in container images.

**Tools**:
- **Trivy**: Fast, accurate, easy to use
- **Clair**: Open source, CoreOS project
- **Anchore**: Policy-based scanning
- **Azure Container Registry scanning**

**When to Run**:
- Every image build
- Before pushing to registry
- Daily scans of registry

**Pass Criteria**:
- No critical OS vulnerabilities
- Base image updated within 30 days
- No malware detected

### Infrastructure as Code (IaC) Scanning

**Purpose**: Find misconfigurations in infrastructure code.

**Tools**:
- **Checkov**: Multi-cloud, Terraform/CloudFormation/Kubernetes
- **tfsec**: Terraform-specific
- **Terrascan**: Policy-as-code
- **Azure Security Center recommendations**

**When to Run**:
- Every commit
- Before infrastructure deployment
- Scheduled audit (weekly)

**Common Findings**:
- Public storage buckets
- Unencrypted resources
- Missing network restrictions
- Overly permissive IAM roles

**Pass Criteria**:
- Zero high-severity issues
- All resources encrypted
- Network segmentation validated

### Penetration Testing

**Purpose**: Simulate real-world attacks to find exploitable vulnerabilities.

**Types**:
- **Black Box**: No internal knowledge
- **Gray Box**: Limited knowledge (typical)
- **White Box**: Full access to code/architecture

**When to Run**:
- Before major release
- After significant architecture change
- Annually (compliance requirement)

**Scope**:
- Web applications
- APIs
- Mobile apps
- Network infrastructure

**Deliverables**:
- Executive summary
- Detailed findings with PoC
- Remediation recommendations
- Retest report

**Pass Criteria**:
- All critical findings remediated
- Retest confirms fixes
- CISO sign-off

## Security Testing in CI/CD

### Build Phase

````````````yaml
# Example: Azure Pipelines
stages:
  - stage: Build
    jobs:
      - job: Security_Scan
        steps:
          # SAST
          - task: SonarQubePrepare@4
          - task: DotNetCoreCLI@2
            inputs:
              command: 'build'
          - task: SonarQubeAnalyze@4
          
          # Dependency scan
          - script: |
              dotnet list package --vulnerable --include-transitive
            displayName: 'Check for vulnerable dependencies'
          
          # Secret scanning
          - task: CredScan@3
````````````

### Deploy Phase

````````````yaml
  - stage: Deploy_QA
    jobs:
      - job: Security_Tests
        steps:
          # DAST
          - task: OwaspZap@1
            inputs:
              target: 'https://qa.example.com'
          
          # Container scan
          - script: |
              trivy image myapp:`${{BUILD_ID}}
            displayName: 'Scan container image'
````````````

## Manual Security Testing

### Authentication Testing

**Checklist**:
- [ ] Test with invalid credentials
- [ ] Test account lockout (brute force protection)
- [ ] Test password reset flow
- [ ] Verify MFA enforcement
- [ ] Test session timeout
- [ ] Test concurrent sessions
- [ ] Test remember me functionality
- [ ] Test logout (session invalidation)

**Tools**: Burp Suite, OWASP ZAP

### Authorization Testing

**Checklist**:
- [ ] Test vertical privilege escalation (user → admin)
- [ ] Test horizontal privilege escalation (user A → user B)
- [ ] Test direct object reference (manipulate IDs)
- [ ] Test API authorization (missing token, expired token)
- [ ] Test role-based access (each role's permissions)
- [ ] Test default permissions (least privilege)

**Tools**: Burp Suite, Postman

### Input Validation Testing

**Checklist**:
- [ ] Test SQL injection (all input fields)
- [ ] Test XSS (reflected, stored, DOM-based)
- [ ] Test command injection
- [ ] Test path traversal
- [ ] Test XML injection / XXE
- [ ] Test LDAP injection
- [ ] Test file upload (malicious files, size limits)
- [ ] Test special characters

**Payloads**: OWASP Testing Guide, PayloadsAllTheThings

### Session Management Testing

**Checklist**:
- [ ] Verify HTTPOnly flag on cookies
- [ ] Verify Secure flag on cookies
- [ ] Test session fixation
- [ ] Test session hijacking
- [ ] Test CSRF protection
- [ ] Test session invalidation on logout
- [ ] Test concurrent session handling

**Tools**: Browser DevTools, Burp Suite

### API Security Testing

**Checklist**:
- [ ] Test broken authentication (missing/weak tokens)
- [ ] Test excessive data exposure (API returns too much)
- [ ] Test rate limiting
- [ ] Test mass assignment (binding attack)
- [ ] Test security misconfiguration
- [ ] Test injection flaws
- [ ] Test improper asset management (old/vulnerable endpoints)

**Reference**: OWASP API Security Top 10

## Security Testing Metrics

### Coverage Metrics

- **SAST Coverage**: % of codebase scanned
- **DAST Coverage**: % of endpoints tested
- **Dependency Coverage**: % of libraries scanned
- **Code Review Coverage**: % of security-relevant code reviewed

### Quality Metrics

- **Mean Time to Detect (MTTD)**: Time from vulnerability introduction to detection
- **Mean Time to Remediate (MTTR)**: Time from detection to fix deployed
- **False Positive Rate**: % of findings that are false positives
- **Escape Rate**: % of vulnerabilities found in production

### Compliance Metrics

- **Critical Findings**: Must be zero before release
- **High Findings**: Must have mitigation plan
- **SLA Compliance**: % of vulnerabilities fixed within SLA
- **Retest Rate**: % of findings requiring retest

## Bug Bounty Program

**Scope**:
- ✅ In-scope: Web app, API, mobile app
- ❌ Out-of-scope: Social engineering, physical security, DDoS

**Rewards**:
- Critical: $$5,000 - $$10,000
- High: $$2,000 - $$5,000
- Medium: $$500 - $$2,000
- Low: $$100 - $$500

**Rules**:
- Do not access other users' data
- Do not perform destructive testing
- Report responsibly (don't disclose publicly)
- One report per vulnerability

**Platform**: HackerOne, Bugcrowd, or internal program

## Security Testing Checklist (Release)

Before production deployment, verify:

- [ ] **SAST**: Clean scan (zero high/critical)
- [ ] **DAST**: Clean scan (zero high/critical)
- [ ] **Dependency Scan**: No critical vulnerabilities
- [ ] **Container Scan**: Base image up-to-date
- [ ] **Manual Testing**: Critical paths tested
- [ ] **Threat Model**: Reviewed and up-to-date
- [ ] **Security Review**: Approved by security team
- [ ] **Penetration Test**: Completed (if required)
- [ ] **Compliance**: All requirements met

---

**Security Testing Schedule**:
- **Daily**: SAST, dependency scanning
- **Per PR**: SAST, secret scanning
- **Per Release**: DAST, full security review
- **Monthly**: Infrastructure scan, third-party audit
- **Annually**: Penetration test, compliance audit

**Questions?** #security or security@company.com
"@

    # Incident Response Plan
    $incidentResponseContent = @"
# Incident Response Plan

Procedures for detecting, responding to, and recovering from security incidents.

## Incident Severity Levels

| Severity | Definition | Examples | Response Time |
|----------|-----------|----------|---------------|
| **Critical** | Data breach, ransomware, full system compromise | Customer data leaked, production down | 15 minutes |
| **High** | Attempted breach, malware detected, DDoS | Failed intrusion attempt, malware quarantined | 1 hour |
| **Medium** | Policy violation, suspicious activity | Unusual login, unpatched vulnerability | 4 hours |
| **Low** | Minor policy issues, false positives | Failed login attempts, scanning activity | 24 hours |

## Incident Response Team

### Roles & Responsibilities

**Incident Commander** (CISO or designate):
- Overall response coordination
- Communication with executives
- Final decision authority
- Post-incident review

**Technical Lead** (Security Engineer):
- Technical investigation
- Containment and eradication
- Evidence collection
- Recovery coordination

**Communications Lead** (PR/Legal):
- Internal communication
- External communication (if required)
- Regulatory notification
- Media relations

**IT Operations**:
- System isolation
- Log collection
- System restoration
- Monitoring

**Legal Counsel**:
- Regulatory compliance
- Contractual obligations
- Litigation holds
- Privilege assessment

**Business Owner**:
- Business impact assessment
- Stakeholder communication
- Business continuity decisions

## Incident Response Process

### Phase 1: Preparation

**Before an Incident**:
- [ ] Incident response plan documented
- [ ] Team roles assigned
- [ ] Contact list up-to-date
- [ ] Monitoring and alerting configured
- [ ] Backup and recovery tested
- [ ] Tabletop exercises conducted (quarterly)
- [ ] Forensics tools ready

**Contact List**:
- Security Team: security@company.com, #security-incidents
- CISO: [Name], [Phone], [Email]
- IT Operations: [24/7 number]
- Legal: [Name], [Phone]
- PR: [Name], [Phone]
- External: IR firm, law firm, cyber insurance

### Phase 2: Detection & Analysis

**Detection Methods**:
- Security monitoring alerts (SIEM)
- User reports
- Third-party notification
- Anomaly detection
- Threat intelligence

**Initial Assessment**:
1. **Verify**: Is this a real incident?
2. **Classify**: What type of incident?
3. **Severity**: What is the impact?
4. **Scope**: What systems are affected?
5. **Notify**: Alert appropriate team members

**Evidence Collection**:
- Preserve logs (write-protect)
- Take system snapshots
- Document timeline
- Screenshot suspicious activity
- Chain of custody for evidence

**Analysis Questions**:
- What happened?
- When did it happen?
- How did it happen?
- What systems are affected?
- What data is at risk?
- Is the threat still active?

### Phase 3: Containment

**Short-Term Containment**:
- Isolate affected systems (network segmentation)
- Disable compromised accounts
- Block malicious IPs/domains
- Reset credentials
- Increase monitoring

**Long-Term Containment**:
- Apply temporary patches
- Implement compensating controls
- Prepare clean system images
- Document containment actions

**Containment Checklist**:
- [ ] Affected systems identified
- [ ] Network isolation applied
- [ ] Credentials rotated
- [ ] Backups secured
- [ ] Evidence preserved
- [ ] Stakeholders notified

### Phase 4: Eradication

**Remove Threat**:
- Delete malware
- Close vulnerabilities
- Remove unauthorized access
- Patch systems
- Rebuild compromised systems

**Root Cause Analysis**:
- How did attacker gain access?
- What vulnerabilities were exploited?
- What controls failed?
- What could have prevented this?

**Validation**:
- Verify threat removed
- Scan for persistence mechanisms
- Check for backdoors
- Review all access points

### Phase 5: Recovery

**Restore Operations**:
- Restore from clean backups (if needed)
- Rebuild systems from known-good images
- Gradually restore services
- Monitor for re-infection
- Verify system integrity

**Verification**:
- [ ] Systems restored
- [ ] Monitoring enhanced
- [ ] Backups validated
- [ ] Access controls verified
- [ ] Business operations resumed

**Return to Normal Operations**:
- Gradual restoration (phased approach)
- Continuous monitoring (24-48 hours)
- User communication
- Document lessons learned

### Phase 6: Post-Incident Activity

**Lessons Learned Meeting** (within 7 days):
- What happened (timeline)
- What went well
- What needs improvement
- Action items with owners

**Report Generation**:
- Executive summary
- Technical details
- Impact assessment
- Cost analysis
- Recommendations

**Follow-Up Actions**:
- Update incident response plan
- Implement improvements
- Security awareness training
- Policy updates
- Technology improvements

## Communication Plan

### Internal Communication

**Immediate Notification** (Critical/High):
- Security team
- CISO
- CIO/CTO
- Legal
- Affected business units

**Regular Updates**:
- Every 2 hours (Critical)
- Every 4 hours (High)
- Daily (Medium/Low)
- Use #security-incidents channel

**Communication Template**:
````````````
[INCIDENT UPDATE - Severity]
Time: [timestamp]
Status: Detection/Containment/Recovery
Impact: [business impact]
Actions Taken: [summary]
Next Steps: [planned actions]
ETA to Resolution: [estimate]
````````````

### External Communication

**Regulatory Notification**:
- **GDPR**: 72 hours to notify authority
- **HIPAA**: 60 days (if PHI breach)
- **State Laws**: Varies by jurisdiction
- **Payment Card**: PCI DSS notification

**Customer Notification**:
- Notify if customer data affected
- Clear, honest communication
- Remediation steps offered
- Support resources provided

**Media Relations**:
- Single spokesperson (PR lead)
- Prepared statements
- No speculation
- Focus on response actions

**Law Enforcement**:
- Notify if required (ransomware, fraud)
- Evidence preservation
- Cooperation with investigation

## Specific Incident Types

### Ransomware

**Immediate Actions**:
1. Isolate affected systems (disconnect network)
2. Identify ransomware variant
3. Check backups (are they encrypted?)
4. Do NOT pay ransom (consult legal/CISO)
5. Report to law enforcement

**Recovery**:
- Restore from clean backups
- Rebuild systems from scratch
- Patch vulnerabilities
- Reset all credentials

### Data Breach

**Immediate Actions**:
1. Stop data exfiltration
2. Identify compromised data
3. Assess scope (how many records?)
4. Check regulatory requirements
5. Notify legal immediately

**Notification Timeline**:
- Internal: Immediate
- Regulatory: Per regulation (72 hours for GDPR)
- Customers: As soon as feasible
- Law enforcement: If criminal activity

### Phishing Attack

**Immediate Actions**:
1. Block malicious email/domain
2. Identify victims (who clicked?)
3. Reset compromised credentials
4. Scan for malware
5. User awareness reminder

**Indicators**:
- Credential harvesting page
- Malware download
- Financial fraud attempt
- Business email compromise (BEC)

### Insider Threat

**Immediate Actions**:
1. Disable user access
2. Preserve evidence
3. Involve HR/Legal
4. Review access logs
5. Interview if appropriate

**Investigation**:
- Motive, means, opportunity
- Data accessed/exfiltrated
- Timeline of activities
- Accomplices

### DDoS Attack

**Immediate Actions**:
1. Activate DDoS mitigation (Cloudflare, Azure DDoS)
2. Identify attack vector
3. Filter malicious traffic
4. Scale infrastructure (if possible)
5. Notify ISP

**Mitigation**:
- Rate limiting
- Geographic filtering
- Challenge-response (CAPTCHA)
- WAF rules

## Compliance & Legal Considerations

**Evidence Preservation**:
- Chain of custody
- Write-protect logs
- System snapshots
- Attorney-client privilege

**Regulatory Notification**:
- Know your obligations
- Consult legal before notification
- Document notification sent
- Keep acknowledgment records

**Cyber Insurance**:
- Notify insurer immediately
- Follow policy requirements
- Document all costs
- Retain approved vendors

## Tools & Resources

**Incident Response Tools**:
- **SIEM**: Splunk, Azure Sentinel, ELK
- **EDR**: CrowdStrike, Carbon Black
- **Forensics**: EnCase, FTK, Volatility
- **Threat Intelligence**: MISP, ThreatConnect

**Playbooks**:
- Ransomware response
- Data breach response
- Phishing response
- DDoS response
- Insider threat response

**External Resources**:
- Incident response firm (on retainer)
- Forensics specialists
- Law firm (cyber practice)
- Cyber insurance carrier

---

**Test Your Plan**:
- **Tabletop Exercise**: Quarterly
- **Full Simulation**: Annually
- **Update Plan**: After each incident or annually

**Questions?** #security-incidents or security@company.com
"@

    try {
        Upsert-AdoWikiPage $Project $WikiId "/Security/Security-Policies" $securityPoliciesContent
        Write-Host "  ✅ Security Policies" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Security/Threat-Modeling-Guide" $threatModelingContent
        Write-Host "  ✅ Threat Modeling Guide" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Security/Security-Testing-Checklist" $securityTestingContent
        Write-Host "  ✅ Security Testing Checklist" -ForegroundColor Gray
        
        Upsert-AdoWikiPage $Project $WikiId "/Security/Incident-Response-Plan" $incidentResponseContent
        Write-Host "  ✅ Incident Response Plan" -ForegroundColor Gray
        
        # Compliance Requirements
        $complianceContent = @"
# Compliance Requirements

Regulatory and compliance obligations for our systems and data.

## Applicable Standards

### GDPR (General Data Protection Regulation)

**Scope**: EU personal data processing

**Key Requirements**:
- **Lawful Basis**: Consent, contract, legal obligation, vital interests, public task, legitimate interests
- **Data Subject Rights**:
  - Right to access
  - Right to rectification
  - Right to erasure ("right to be forgotten")
  - Right to data portability
  - Right to object
  - Right to restrict processing
- **Data Protection Impact Assessment (DPIA)**: Required for high-risk processing
- **Data Breach Notification**: 72 hours to supervisory authority
- **Privacy by Design**: Embed privacy from project start

**Implementation**:
- [ ] Data inventory (what personal data we process)
- [ ] Legal basis documented for each processing activity
- [ ] Consent management (if using consent as basis)
- [ ] Data subject request process
- [ ] Privacy policy published
- [ ] DPIA for high-risk projects

**Penalties**: Up to €20M or 4% of annual global turnover

### SOC 2 (Service Organization Control)

**Scope**: Service providers handling customer data

**Trust Service Criteria**:
- **Security**: Protection against unauthorized access
- **Availability**: System available for operation as committed
- **Processing Integrity**: System achieves purpose accurately/completely
- **Confidentiality**: Confidential information protected
- **Privacy**: Personal information collected/used/retained/disclosed per commitments

**SOC 2 Type II Requirements**:
- **Policies and Procedures**: Documented security program
- **Risk Assessment**: Annual threat assessment
- **Logical Access Controls**: Authentication, authorization, audit
- **Change Management**: Controlled deployment process
- **Monitoring**: Continuous security monitoring
- **Incident Response**: Documented IR procedures
- **Vendor Management**: Third-party risk assessment

**Evidence Required**:
- Configuration screenshots
- Policy documents
- Access reviews
- Penetration test reports
- Incident logs
- Training records

**Audit Frequency**: Annual

### ISO 27001 (Information Security Management)

**Scope**: Information security management system (ISMS)

**Key Domains** (Annex A):
1. **Information Security Policies**
2. **Organization of Information Security**
3. **Human Resource Security**
4. **Asset Management**
5. **Access Control**
6. **Cryptography**
7. **Physical and Environmental Security**
8. **Operations Security**
9. **Communications Security**
10. **System Acquisition, Development, and Maintenance**
11. **Supplier Relationships**
12. **Information Security Incident Management**
13. **Business Continuity Management**
14. **Compliance**

**Implementation**:
- [ ] Statement of Applicability (SoA)
- [ ] Risk assessment and treatment
- [ ] Documented policies and procedures
- [ ] Internal audits
- [ ] Management review
- [ ] Continual improvement

**Certification**: External audit by accredited body

### PCI DSS (Payment Card Industry Data Security Standard)

**Scope**: Systems handling credit card data

**12 Requirements**:
1. **Install and maintain firewall**
2. **Don't use vendor defaults** (passwords, security parameters)
3. **Protect stored cardholder data** (encrypt)
4. **Encrypt transmission** (TLS 1.2+)
5. **Use anti-virus**
6. **Develop secure systems** (secure coding)
7. **Restrict access by business need-to-know**
8. **Assign unique ID** (no shared accounts)
9. **Restrict physical access**
10. **Track and monitor network access** (logging)
11. **Test security systems** (quarterly scans, annual pentest)
12. **Maintain security policy**

**Merchant Levels**:
- **Level 1**: >6M transactions/year (annual onsite audit)
- **Level 2**: 1-6M transactions/year (annual SAQ)
- **Level 3**: 20K-1M e-commerce transactions/year (annual SAQ)
- **Level 4**: <20K e-commerce transactions/year (annual SAQ)

**Best Practice**: Use payment processor (tokenization) to reduce scope

### HIPAA (Health Insurance Portability and Accountability Act)

**Scope**: Protected Health Information (PHI)

**Key Rules**:
- **Privacy Rule**: Protects PHI from disclosure
- **Security Rule**: Administrative, physical, technical safeguards
- **Breach Notification Rule**: Notification within 60 days

**Technical Safeguards**:
- Access control (unique user IDs)
- Audit controls (logging)
- Integrity controls (protect from alteration)
- Transmission security (encryption)

**Administrative Safeguards**:
- Risk analysis
- Workforce training
- Business associate agreements
- Contingency plan

**Physical Safeguards**:
- Facility access controls
- Workstation security
- Device and media controls

**Penalties**: Up to $$1.5M per year per violation category

### Azure Compliance

**Built-In Compliance**:
- **GDPR**: Data residency, DPAs available
- **SOC 1/2/3**: Certified
- **ISO 27001/27018/27701**: Certified
- **HIPAA/HITECH**: BAA available
- **PCI DSS Level 1**: Service provider certified

**Shared Responsibility**:
- **Microsoft**: Physical security, network, hypervisor
- **Us**: Application, data, access control, configuration

**Compliance Manager**: Azure portal compliance assessment tool

## Compliance Implementation

### Data Classification

| Classification | Examples | Encryption | Access | Retention |
|----------------|----------|------------|--------|-----------|
| **Public** | Marketing materials | Optional | Anyone | As needed |
| **Internal** | Policies, roadmaps | At rest | Employees | 7 years |
| **Confidential** | Customer data, financials | At rest + transit | Need-to-know | Per regulation |
| **Restricted** | PII, PHI, PCI | At rest + transit + use | Role-based | Per regulation |

**PII Examples**: Name, email, address, phone, SSN, IP address, biometric data

**Implementation**:
- [ ] Data classification policy
- [ ] Data discovery and labeling
- [ ] Encryption based on classification
- [ ] Access controls based on classification
- [ ] DLP (Data Loss Prevention) policies

### Data Retention

| Data Type | Retention Period | Legal Hold | Disposal Method |
|-----------|-----------------|------------|-----------------|
| **Customer PII** | Duration of relationship + 90 days | Yes | Secure deletion |
| **Audit Logs** | 7 years | Yes | Archive then delete |
| **Financial Records** | 7 years | Yes | Archive then delete |
| **Email** | 7 years | Yes | Archive then delete |
| **Source Code** | Indefinite | No | Keep in Git |
| **Backups** | 90 days | No | Overwrite |

**Legal Hold**: Suspend deletion if litigation/investigation

**Implementation**:
- [ ] Retention policy documented
- [ ] Automated retention enforcement
- [ ] Legal hold process
- [ ] Secure deletion procedures

### Data Subject Rights (GDPR)

**Right to Access**:
- Process: Submit request via privacy@company.com
- Response time: 30 days
- Format: Portable format (JSON, CSV)

**Right to Erasure**:
- Process: Submit request via privacy@company.com
- Response time: 30 days
- Exceptions: Legal obligation, litigation

**Right to Portability**:
- Process: Submit request via privacy@company.com
- Response time: 30 days
- Format: Machine-readable (JSON, CSV)

**Implementation**:
- [ ] Data subject request portal
- [ ] Identity verification process
- [ ] Request tracking system
- [ ] 30-day SLA

### Third-Party Risk Management

**Vendor Assessment**:
- [ ] Security questionnaire (SIG Lite)
- [ ] SOC 2 report review
- [ ] Privacy policy review
- [ ] Data Processing Agreement (DPA)
- [ ] Business Associate Agreement (BAA) if HIPAA

**Approved Vendors**:
- **Cloud**: Azure, AWS, GCP (with appropriate config)
- **SaaS**: GitHub, Azure DevOps, Slack, Office 365
- **Payment**: Stripe, PayPal (PCI DSS Level 1)
- **Analytics**: Azure App Insights, Google Analytics (anonymized)

**Vendor Review Frequency**: Annual

### Privacy by Design

**7 Foundational Principles**:
1. **Proactive not Reactive**: Anticipate and prevent privacy issues
2. **Privacy as Default**: Maximum privacy by default
3. **Privacy Embedded**: Into design of systems
4. **Full Functionality**: Positive-sum, not zero-sum
5. **End-to-End Security**: Lifecycle protection
6. **Visibility and Transparency**: Open and verifiable
7. **Respect for User Privacy**: User-centric

**Implementation Checklist**:
- [ ] Privacy impact assessment before project start
- [ ] Minimize data collection (only what's needed)
- [ ] Pseudonymization/anonymization where possible
- [ ] Encryption by default
- [ ] User consent management
- [ ] Privacy-preserving analytics
- [ ] Secure by default configuration

## Audit & Compliance Evidence

### Evidence Collection

**Automated Evidence**:
- Access logs (Azure AD sign-ins)
- Security alerts (Azure Sentinel)
- Change logs (Git commits, Azure DevOps)
- Configuration snapshots (Azure Policy)
- Vulnerability scans (Defender for Cloud)

**Manual Evidence**:
- Policy documents
- Training records
- Risk assessments
- Penetration test reports
- Vendor assessments
- Incident reports

**Storage**:
- **Location**: Secure SharePoint with restricted access
- **Retention**: Per compliance requirement (typically 7 years)
- **Organization**: By control domain (e.g., Access Control, Encryption)

### Audit Preparation

**Before Audit**:
- [ ] Evidence collected and organized
- [ ] Gaps identified and remediated
- [ ] Stakeholders briefed
- [ ] Conference room/tools prepared
- [ ] Point of contact assigned

**During Audit**:
- [ ] Daily debrief with team
- [ ] Track auditor requests
- [ ] Provide evidence promptly
- [ ] Clarify questions
- [ ] Document audit findings

**After Audit**:
- [ ] Remediation plan for findings
- [ ] Assign owners and due dates
- [ ] Track to closure
- [ ] Management review
- [ ] Update controls for next audit

### Continuous Compliance

**Monthly**:
- [ ] Review access permissions
- [ ] Review security alerts
- [ ] Review failed authentication attempts
- [ ] Vendor risk assessment for new vendors

**Quarterly**:
- [ ] Vulnerability scan
- [ ] Compliance dashboard review
- [ ] Policy updates (if needed)
- [ ] Training completion check

**Annually**:
- [ ] Risk assessment
- [ ] Penetration test
- [ ] Disaster recovery test
- [ ] Compliance audit (SOC 2, ISO 27001)
- [ ] Policy review and approval
- [ ] Vendor risk re-assessment

## Compliance Metrics

**KPIs**:
- **Audit Findings**: Target: 0 high, <5 medium
- **Data Breaches**: Target: 0
- **Training Compliance**: Target: 100% completion within 30 days of hire
- **Vulnerability Remediation**: Target: <7 days for critical, <30 days for high
- **Access Review**: Target: 100% quarterly
- **Data Subject Requests**: Target: 100% within 30 days

**Dashboard**: Power BI compliance dashboard (link in wiki)

---

**Compliance Contact**: compliance@company.com or #compliance

**Questions?** Reach out to Legal or Security teams.
"@

        Upsert-AdoWikiPage $Project $WikiId "/Security/Compliance-Requirements" $complianceContent
        Write-Host "  ✅ Compliance Requirements" -ForegroundColor Gray
        
        # Secret Management
        $secretManagementContent = @"
# Secret Management

Best practices for storing, accessing, and rotating secrets (passwords, API keys, certificates).

## What Are Secrets?

**Secrets** are sensitive credentials that grant access to systems or data:
- **API Keys**: Third-party services (Stripe, SendGrid)
- **Database Passwords**: Connection strings
- **Certificates**: TLS/SSL certificates, code signing
- **SSH Keys**: Server access, Git operations
- **Tokens**: Personal Access Tokens (PAT), OAuth tokens
- **Encryption Keys**: Data encryption keys

**Never**:
- ❌ Hardcode secrets in source code
- ❌ Commit secrets to Git (even in private repos)
- ❌ Store secrets in plaintext files
- ❌ Share secrets via email/chat
- ❌ Use same secret across environments

## Secret Storage Solutions

### Azure Key Vault (Primary)

**Use For**:
- Database connection strings
- API keys
- Certificates
- Encryption keys

**Features**:
- Encryption at rest (FIPS 140-2 Level 2 HSMs)
- Access policies with Azure AD integration
- Audit logging (who accessed what, when)
- Secret versioning
- Automatic rotation (for supported services)
- Soft delete and purge protection

**Access Patterns**:

````````````csharp
// C# example
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

var client = new SecretClient(
    new Uri("https://myvault.vault.azure.net/"),
    new DefaultAzureCredential()
);

KeyVaultSecret secret = await client.GetSecretAsync("database-password");
string password = secret.Value;
````````````

````````````powershell
# PowerShell example
$secret = Get-AzKeyVaultSecret -VaultName "myvault" -Name "database-password"
$password = $secret.SecretValueText
````````````

**Best Practices**:
- Use Managed Identities (no credentials in code)
- Restrict access to Key Vault (RBAC)
- Enable audit logging
- Use separate Key Vaults per environment (dev, staging, prod)
- Enable soft delete and purge protection

### Azure DevOps Variable Groups

**Use For**:
- Pipeline secrets (build/deploy)
- Environment-specific variables

**Features**:
- Encrypted at rest
- Link to Azure Key Vault
- Scoped to pipelines or stages
- Approval gates

**Configuration**:

````````````yaml
# azure-pipelines.yml
variables:
  - group: production-secrets  # Variable group

steps:
  - script: |
      echo "Deploying with API key"
      curl -H "X-API-Key: $(API_KEY)" https://api.example.com
    env:
      API_KEY: $(API_KEY)  # Secret variable from variable group
````````````

**Best Practices**:
- Mark as "secret" (obfuscated in logs)
- Link to Azure Key Vault for production
- Use separate variable groups per environment
- Restrict access to variable groups

### Environment Variables (Runtime)

**Use For**:
- Application runtime secrets
- Container secrets

**Configuration**:

````````````yaml
# docker-compose.yml
services:
  web:
    image: myapp:latest
    environment:
      - DATABASE_PASSWORD=$${DATABASE_PASSWORD}
````````````

````````````yaml
# Kubernetes Secret
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # Base64 encoded
````````````

**Best Practices**:
- Never log environment variables
- Use Kubernetes Secrets (not ConfigMaps) for sensitive data
- Rotate regularly
- Inject at runtime (not baked into images)

### Git-Ignored .env Files (Development Only)

**Use For**:
- Local development (never production)

**Setup**:

````````````bash
# .env file (gitignored)
DATABASE_PASSWORD=local_dev_password
API_KEY=dev_key_12345
````````````

````````````bash
# .gitignore
.env
.env.local
````````````

**Best Practices**:
- Provide `.env.template` with dummy values
- Document in README.md
- Never commit actual `.env` file
- Use weak/fake secrets for local dev

## Secret Rotation

### Why Rotate?

- Reduce impact of credential compromise
- Compliance requirements (PCI DSS, SOC 2)
- Limit exposure window
- Detect misuse (old credentials stop working)

### Rotation Frequency

| Secret Type | Rotation Frequency | Why |
|-------------|-------------------|-----|
| **Database Passwords** | 90 days | Compliance, reduce risk |
| **API Keys** | 180 days | Balance security vs. disruption |
| **Certificates** | Before expiry (90 days) | Avoid downtime |
| **SSH Keys** | 1 year | Infrequent change due to disruption |
| **Personal Access Tokens** | 90 days | User-specific, high privilege |
| **Service Account Passwords** | 90 days | High privilege |

### Rotation Process

**Automated Rotation** (Preferred):

````````````powershell
# Example: Azure Key Vault + Azure Function
function Rotate-Secret {
    param($SecretName)
    
    # Generate new secret
    $newPassword = New-RandomPassword -Length 32
    
    # Update application (e.g., database user password)
    Update-DatabasePassword -Username "appuser" -NewPassword $newPassword
    
    # Update Key Vault
    Set-AzKeyVaultSecret -VaultName "myvault" -Name $SecretName -SecretValue (ConvertTo-SecureString $newPassword -AsPlainText -Force)
    
    # Verify application still works
    Test-Application
}
````````````

**Manual Rotation** (If required):
1. Generate new secret
2. Update secret in Key Vault (new version)
3. Deploy application (picks up new secret)
4. Verify application works
5. Delete old secret version (after grace period)

**Zero-Downtime Rotation**:
- Use dual-write pattern (accept both old and new secrets during transition)
- Example: API key rotation with versioned keys

### Certificate Rotation

**Automatic Renewal** (Let's Encrypt, Azure App Service):
- Certificates auto-renew 30 days before expiry
- No manual intervention required

**Manual Renewal**:
1. Generate new certificate (30 days before expiry)
2. Upload to Azure Key Vault
3. Update application configuration
4. Verify HTTPS works
5. Remove old certificate

**Monitoring**:
- Alert 30 days before expiry
- Weekly check for expiring certificates

## Secret Scanning

### Pre-Commit Scanning

**Tools**:
- **git-secrets**: AWS credential scanner
- **truffleHog**: Scans Git history for secrets
- **detect-secrets**: Yelp's secret scanner

**Setup** (git-secrets):

````````````bash
# Install
brew install git-secrets  # macOS
choco install git-secrets  # Windows

# Configure
git secrets --install
git secrets --register-aws  # AWS patterns
git secrets --add 'password\s*=\s*.+'  # Custom patterns
````````````

### CI/CD Scanning

**Azure Pipelines** (CredScan):

````````````yaml
steps:
  - task: CredScan@3
    inputs:
      suppressionsFile: '.credscan/suppressions.json'
  
  - task: PostAnalysis@2
    inputs:
      CredScan: true
````````````

**GitHub** (Secret Scanning):
- Automatically scans for secrets
- Alerts on detected secrets
- Partner patterns (Stripe, AWS, Azure)

**Custom Patterns**:

````````````regex
# Example patterns
api[_-]?key\s*[:=]\s*['"][a-zA-Z0-9]{32}['"]
password\s*[:=]\s*['"][^'"]{8,}['"]
BEGIN\s+(RSA|DSA|EC|OPENSSH)\s+PRIVATE\s+KEY
````````````

### Post-Commit Scanning

**git-secrets** (scan history):

````````````bash
git secrets --scan-history
````````````

**TruffleHog** (deep scan):

````````````bash
trufflehog git https://github.com/myorg/myrepo --only-verified
````````````

### Remediation

**If Secret Committed**:
1. **Rotate Immediately**: Assume secret is compromised
2. **Remove from Git History**: Use `git filter-branch` or BFG Repo-Cleaner
3. **Force Push**: After history rewrite
4. **Notify Team**: All clones need to be reset
5. **Audit**: Check if secret was used maliciously

**BFG Repo-Cleaner** (faster than git filter-branch):

````````````bash
# Replace all passwords in history
bfg --replace-text passwords.txt myrepo.git

# Remove files
bfg --delete-files secrets.json myrepo.git

# Cleanup
cd myrepo.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
````````````

## Access Control

### Principle of Least Privilege

**Grant Minimum Access**:
- Developers: Read-only access to Key Vault (via Managed Identity)
- CI/CD: Read-only access to secrets needed for deployment
- Admins: Full access (create, update, delete secrets)
- Applications: Read-only access to specific secrets

**Azure Key Vault Access Policies**:

````````````powershell
# Grant app read-only access to specific secret
Set-AzKeyVaultAccessPolicy -VaultName "myvault" `
    -ObjectId $appManagedIdentityId `
    -PermissionsToSecrets Get,List `
    -SecretName "database-password"
````````````

### Managed Identities (Preferred)

**Why?**
- No credentials in code
- Automatic credential rotation
- Azure AD integration

**Types**:
- **System-Assigned**: Tied to resource lifecycle (VM, App Service)
- **User-Assigned**: Shared across resources

**Example** (App Service):

````````````csharp
// No credentials needed - uses Managed Identity
var client = new SecretClient(
    new Uri("https://myvault.vault.azure.net/"),
    new DefaultAzureCredential()  // Automatically uses Managed Identity
);
````````````

### Service Principals (If Managed Identity Not Available)

**Use For**:
- Third-party CI/CD (GitHub Actions, CircleCI)
- On-premise servers

**Permissions**:
- Grant only necessary permissions
- Use short-lived tokens (if possible)
- Rotate credentials regularly

## Monitoring & Auditing

### Key Vault Audit Logs

**Enable Diagnostic Logs**:

````````````powershell
Set-AzDiagnosticSetting -ResourceId $keyVaultId `
    -Name "KeyVaultAudit" `
    -WorkspaceId $logAnalyticsWorkspaceId `
    -Enabled $true `
    -Category AuditEvent
````````````

**Monitor For**:
- Failed access attempts (unauthorized access)
- Secret retrieved by unexpected identity
- Secret deleted (should be rare)
- High volume of secret retrievals (potential scraping)

**Alerts**:
- Alert on failed Key Vault access
- Alert on secret deletion
- Alert on access from unexpected IP

### Azure DevOps Audit Logs

**Track**:
- Variable group access
- Pipeline runs (which secrets used)
- Variable group changes

**Audit Query**:

````````````kusto
AzureDevOpsAuditLogs
| where OperationName == "VariableGroup.SecretAccessed"
| project TimeGenerated, UserPrincipalName, ResourceName
````````````

## Secrets in Code Review

**Checklist**:
- [ ] No hardcoded secrets
- [ ] No secrets in comments
- [ ] No secrets in test files
- [ ] Connection strings use Key Vault
- [ ] API keys come from environment variables
- [ ] Certificates loaded from Key Vault
- [ ] No secrets in logs

**Red Flags**:
- String literals that look like passwords: `"P@ssw0rd123"`
- Long alphanumeric strings: `"ak_live_51H..."`
- Base64-encoded strings (potential secret)
- Comments like "// TODO: remove hardcoded password"

## Common Pitfalls

### Logging Secrets

❌ **Bad**:
````````````csharp
logger.LogInformation($$"Connecting with password: {password}");
````````````

✅ **Good**:
````````````csharp
logger.LogInformation("Connecting to database");
````````````

### Exception Messages

❌ **Bad**:
````````````csharp
throw new Exception($$"Failed to connect with connection string: {connectionString}");
````````````

✅ **Good**:
````````````csharp
throw new Exception("Failed to connect to database");
````````````

### URL Parameters

❌ **Bad**:
````````````
https://api.example.com/data?api_key=12345
````````````

✅ **Good**:
````````````
https://api.example.com/data
Authorization: Bearer 12345
````````````

### Git Commits

❌ **Bad**:
````````````bash
git commit -m "Add API key: sk_live_12345"
````````````

✅ **Good**:
````````````bash
git commit -m "Add API key from Key Vault"
````````````

## Emergency Procedures

### Compromised Secret

1. **Rotate Immediately**: Generate new secret
2. **Revoke Old Secret**: Disable/delete compromised credential
3. **Audit Usage**: Check logs for unauthorized usage
4. **Notify Stakeholders**: Security team, affected service owners
5. **Post-Mortem**: How was it compromised? How to prevent?

### Lost Access to Key Vault

**Recovery**:
- Use break-glass admin account (stored in secure physical location)
- Or recover via Azure subscription owner

**Prevention**:
- Multiple Key Vault admins
- Break-glass procedure documented
- Periodic access verification

---

**Secret Management Checklist**:
- [ ] All secrets stored in Azure Key Vault (production)
- [ ] Managed Identities used (where possible)
- [ ] Secret scanning in CI/CD
- [ ] Secrets rotated per schedule
- [ ] Audit logging enabled
- [ ] No secrets in source code
- [ ] Developers trained on secret management

**Questions?** #security or security@company.com
"@

        Upsert-AdoWikiPage $Project $WikiId "/Security/Secret-Management" $secretManagementContent
        Write-Host "  ✅ Secret Management" -ForegroundColor Gray
        
        # Security Champions Program
        $securityChampionsContent = @"
# Security Champions Program

Empower developers to become security advocates within their teams.

## What Is a Security Champion?

A **Security Champion** is a developer who:
- Acts as security liaison between dev team and security team
- Promotes security best practices
- Participates in threat modeling sessions
- Reviews security findings and coordinates remediation
- Stays current on security trends and vulnerabilities
- Mentors team members on secure coding

**Not a replacement for security team** - Champions extend security culture into engineering teams.

## Program Goals

1. **Shift Left Security**: Embed security early in development
2. **Scale Security**: Extend security team's reach
3. **Build Security Culture**: Make security everyone's responsibility
4. **Faster Remediation**: Security issues fixed at the source
5. **Knowledge Sharing**: Spread security expertise across org

## Roles & Responsibilities

### Security Champions

**Responsibilities**:
- [ ] Attend monthly Security Champion meetings
- [ ] Review security findings for your team (SAST, DAST, dependency scans)
- [ ] Participate in threat modeling (new features)
- [ ] Conduct security-focused code reviews
- [ ] Promote security awareness within your team
- [ ] Coordinate vulnerability remediation
- [ ] Contribute to security documentation
- [ ] Complete security training (annually)

**Time Commitment**: 2-4 hours per week

**Recognition**:
- Security Champion badge on profile
- Certificate of completion (annual)
- Public recognition in all-hands meetings
- Priority access to security training
- Invitation to security conferences

### Security Team

**Responsibilities**:
- [ ] Provide training and resources
- [ ] Facilitate monthly Champion meetings
- [ ] Support Champions with security questions
- [ ] Triage and assign security findings
- [ ] Conduct threat modeling workshops
- [ ] Recognize Champion contributions

**Support Channels**:
- #security-champions (Slack/Teams)
- security-champions@company.com
- Monthly office hours

### Engineering Managers

**Responsibilities**:
- [ ] Nominate Security Champions
- [ ] Allocate time for Champion activities
- [ ] Support Champion initiatives
- [ ] Recognize Champion contributions in reviews
- [ ] Attend quarterly security reviews

## How to Become a Security Champion

### Eligibility

**Requirements**:
- Software engineer (any level)
- Good understanding of application architecture
- Interest in security (no prior security experience required)
- Manager approval

**Nice-to-Have**:
- Experience with threat modeling
- Security certifications (CISSP, CEH, OSCP)
- Contributions to security tools/projects

### Application Process

1. **Nominate Yourself**: Fill out nomination form (link below)
2. **Manager Approval**: Manager confirms time allocation
3. **Security Team Review**: Security team reviews nomination
4. **Onboarding**: Complete Security Champion onboarding (2-week program)
5. **Assignment**: Assigned to your team

**Nomination Form**: [Link to form]

### Onboarding Program (2 Weeks)

**Week 1: Foundations**
- Day 1-2: Security fundamentals (OWASP Top 10, STRIDE)
- Day 3-4: Threat modeling workshop
- Day 5: Secure coding practices

**Week 2: Tools & Processes**
- Day 1-2: Security tools (SAST, DAST, dependency scanning)
- Day 3: Incident response procedures
- Day 4: Security code review techniques
- Day 5: Capstone project (threat model a real feature)

**Completion**: Security Champion certificate + badge

## Champion Activities

### Monthly Security Champion Meeting

**Format**: 1 hour, all Champions + security team

**Agenda**:
- Security news and trends
- Recent vulnerabilities and lessons learned
- New tools and techniques
- Q&A with security team
- Recognition of Champion contributions

**Schedule**: First Thursday of each month, 2pm PT

### Threat Modeling Sessions

**When**: For new features or significant changes

**Process**:
1. Champion coordinates with security team
2. Whiteboard session (1-2 hours)
3. Identify threats using STRIDE
4. Document mitigations
5. Update threat model in wiki

**Champion Role**:
- Schedule session
- Invite stakeholders (PM, architects, security)
- Document threat model
- Track mitigation implementation

**Threat Model Template**: [Link to template in Security/Threat-Modeling-Guide]

### Security Code Review

**Champion Review Checklist**:

**Authentication & Authorization**:
- [ ] Authentication required for sensitive endpoints?
- [ ] Authorization checks on all protected resources?
- [ ] No privilege escalation vulnerabilities?

**Input Validation**:
- [ ] All user input validated?
- [ ] Parameterized queries (no SQL injection)?
- [ ] Output encoding (no XSS)?
- [ ] File upload restrictions (type, size)?

**Data Protection**:
- [ ] Sensitive data encrypted at rest?
- [ ] TLS used for data in transit?
- [ ] No secrets in code?
- [ ] PII handling per privacy policy?

**Error Handling**:
- [ ] Errors logged but not exposed to user?
- [ ] No stack traces in production?
- [ ] Sensitive data redacted from logs?

**Dependencies**:
- [ ] No vulnerable dependencies?
- [ ] Dependencies from trusted sources?
- [ ] Dependency versions pinned?

### Vulnerability Triage

**Champion Process**:
1. Review security findings (SAST, DAST, dependency scan)
2. Validate findings (eliminate false positives)
3. Prioritize (critical → high → medium → low)
4. Assign to team members
5. Track to completion
6. Verify fixes

**SLA by Severity**:
- Critical: 7 days
- High: 30 days
- Medium: 90 days
- Low: Best effort

**Escalation**: If SLA at risk, escalate to security team

### Security Training

**Champion-Led Training** (quarterly):
- Secure coding workshop (2 hours)
- OWASP Top 10 deep dive
- Hands-on labs (vulnerable apps)
- Capture The Flag (CTF) competition

**External Training**:
- Security conferences (BSides, OWASP AppSec)
- Online courses (SANS, Pluralsight)
- Certifications (company-sponsored)

## Champion Resources

### Documentation

- **OWASP Top 10**: https://owasp.org/Top10/
- **OWASP Cheat Sheets**: https://cheatsheetseries.owasp.org/
- **Security Policies**: [Link to Security/Security-Policies]
- **Threat Modeling Guide**: [Link to Security/Threat-Modeling-Guide]
- **Incident Response Plan**: [Link to Security/Incident-Response-Plan]
- **Secret Management**: [Link to Security/Secret-Management]

### Tools

**SAST**:
- SonarQube: [Link]
- Semgrep: https://semgrep.dev/

**DAST**:
- OWASP ZAP: https://www.zaproxy.org/
- Burp Suite Community: https://portswigger.net/burp/communitydownload

**Dependency Scanning**:
- Snyk: [Link]
- Dependabot: Built into GitHub

**Threat Modeling**:
- Microsoft Threat Modeling Tool: https://aka.ms/threatmodelingtool
- OWASP Threat Dragon: https://owasp.org/www-project-threat-dragon/

**Learning**:
- OWASP WebGoat (vulnerable app): https://owasp.org/www-project-webgoat/
- Damn Vulnerable Web Application (DVWA): http://www.dvwa.co.uk/
- HackTheBox: https://www.hackthebox.com/

### Communication

**Slack Channels**:
- #security-champions (primary channel)
- #security (general security discussions)
- #security-incidents (incident response)

**Email**: security-champions@company.com

**Office Hours**: Every Wednesday, 2-3pm PT (optional)

## Success Metrics

### Individual Champion Metrics

- Security findings reviewed (target: 100% within 7 days)
- Threat models facilitated (target: ≥1 per quarter)
- Security training attended (target: ≥4 hours per quarter)
- Code reviews with security focus (target: ≥5 per month)
- Security improvements contributed (documented)

### Program Metrics

- Number of active Champions (target: ≥1 per team)
- Vulnerability remediation time (target: 30% reduction)
- Security findings per 1000 LOC (target: downward trend)
- Champion satisfaction (target: ≥4.0/5.0)
- Security culture survey score (target: ≥4.0/5.0)

**Dashboard**: [Link to Power BI dashboard]

## Recognition & Rewards

### Quarterly Recognition

**Security Champion of the Quarter**:
- Criteria: Most impactful contribution
- Reward: $500 bonus, public recognition, plaque

**Nomination Process**: Self-nomination or peer nomination

### Annual Recognition

**Security Champion of the Year**:
- Criteria: Consistent contributions, mentorship, innovation
- Reward: $2000 bonus, conference attendance, trophy

### Continuous Recognition

- Shout-outs in #security-champions channel
- Monthly summary email highlighting contributions
- Profile badge and certificate
- Career development support

## Champion Advancement

### Levels

**Level 1: Security Champion** (0-1 year):
- Learning phase
- Focus on your team
- Complete core training

**Level 2: Senior Security Champion** (1-2 years):
- Mentor new Champions
- Lead threat modeling sessions
- Contribute to security tools/processes

**Level 3: Lead Security Champion** (2+ years):
- Program leadership
- Define security strategy
- Cross-team security initiatives
- May transition to security team

### Career Path

**Paths**:
1. **Stay in Engineering**: Security-focused senior engineer, security architect
2. **Transition to Security**: Security engineer, application security engineer
3. **Security Leadership**: Security manager, CISO

**Support**:
- Career development conversations (quarterly)
- Training budget for certifications
- Internal mobility support

## Program Evolution

### Feedback

**Channels**:
- Monthly Champion survey (pulse check)
- Quarterly program retrospective
- Annual program review

**Act On Feedback**:
- Adjust meeting frequency/format
- Update training content
- Improve tools and processes

### Continuous Improvement

**Quarterly Goals**:
- Q1: Onboard 10 new Champions
- Q2: Reduce vulnerability remediation time by 30%
- Q3: Launch security training platform
- Q4: Achieve 100% Champion satisfaction

---

**Join the Security Champions Program!**

**Why Become a Champion?**
- Build valuable security skills
- Make a real impact on product security
- Career growth opportunities
- Recognition and rewards
- Join a community of security-minded engineers

**Ready to Apply?** [Link to nomination form]

**Questions?** Reach out to security-champions@company.com or #security-champions

---

*Security is everyone's responsibility. Security Champions make it everyone's capability.*
"@

        Upsert-AdoWikiPage $Project $WikiId "/Security/Security-Champions-Program" $securityChampionsContent
        Write-Host "  ✅ Security Champions Program" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] All 7 security wiki pages created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create some security wiki pages: $_"
    }
}

<#
.SYNOPSIS
    Creates security-focused queries for vulnerability tracking and compliance monitoring.

.DESCRIPTION
    Creates a "Security" query folder with 5 pre-configured queries:
    1. Security Bugs (Priority 0-1) - Critical security vulnerabilities
    2. Vulnerability Backlog - All open security items
    3. Security Review Required - Work items pending security review
    4. Compliance Items - Compliance-related work items
    5. Security Debt - Security technical debt tracking

.PARAMETER Project
    The name of the Azure DevOps project.

.EXAMPLE
    Ensure-AdoSecurityQueries -Project "MyProject"
#>
function Ensure-AdoSecurityQueries {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )

    Write-Host "[INFO] Setting up security queries..." -ForegroundColor Cyan

    # Security Bugs (Priority 0-1)
    $securityBugsQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.Priority], [Microsoft.VSTS.Common.Severity], [System.AssignedTo], [System.CreatedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] = 'Bug'
  AND [System.Tags] CONTAINS 'security'
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
  AND [System.Priority] <= 1
ORDER BY [System.Priority], [Microsoft.VSTS.Common.Severity] DESC, [System.CreatedDate]
"@

    # Vulnerability Backlog
    $vulnerabilityBacklogQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.Tags], [System.AssignedTo], [System.CreatedDate], [Microsoft.VSTS.Scheduling.TargetDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND (
    [System.Tags] CONTAINS 'security' OR
    [System.Tags] CONTAINS 'vulnerability' OR
    [System.Tags] CONTAINS 'cve' OR
    [System.Tags] CONTAINS 'sast' OR
    [System.Tags] CONTAINS 'dast' OR
    [System.Tags] CONTAINS 'dependency-scan'
  )
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [System.Priority], [System.CreatedDate]
"@

    # Security Review Required
    $securityReviewQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo], [System.CreatedDate], [Microsoft.VSTS.Scheduling.TargetDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND (
    [System.Tags] CONTAINS 'security-review-required' OR
    [System.Tags] CONTAINS 'threat-model-required' OR
    [System.Tags] CONTAINS 'pentest-required'
  )
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Scheduling.TargetDate], [System.CreatedDate]
"@

    # Compliance Items
    $complianceItemsQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.Tags], [System.AssignedTo], [System.CreatedDate], [Microsoft.VSTS.Scheduling.TargetDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND (
    [System.Tags] CONTAINS 'compliance' OR
    [System.Tags] CONTAINS 'gdpr' OR
    [System.Tags] CONTAINS 'soc2' OR
    [System.Tags] CONTAINS 'iso27001' OR
    [System.Tags] CONTAINS 'pci-dss' OR
    [System.Tags] CONTAINS 'hipaa' OR
    [System.Tags] CONTAINS 'audit'
  )
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Scheduling.TargetDate], [System.Priority], [System.CreatedDate]
"@

    # Security Debt
    $securityDebtQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [Microsoft.VSTS.Common.Priority], [System.AssignedTo], [System.CreatedDate], [Microsoft.VSTS.Scheduling.TargetDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND (
    [System.Tags] CONTAINS 'security-debt' OR
    [System.Tags] CONTAINS 'security-refactor' OR
    [System.Tags] CONTAINS 'security-upgrade'
  )
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Common.Priority], [System.CreatedDate]
"@

    try {
        # Ensure "Security" folder exists
        $folderPath = "Shared Queries/Security"
        Ensure-AdoQueryFolder -Project $Project -Path $folderPath

        # Create queries
        Upsert-AdoQuery -Project $Project -Path "$folderPath/Security Bugs (Priority 0-1)" -Wiql $securityBugsQuery
        Write-Host "  ✅ Security Bugs (Priority 0-1)" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Vulnerability Backlog" -Wiql $vulnerabilityBacklogQuery
        Write-Host "  ✅ Vulnerability Backlog" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Security Review Required" -Wiql $securityReviewQuery
        Write-Host "  ✅ Security Review Required" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Compliance Items" -Wiql $complianceItemsQuery
        Write-Host "  ✅ Compliance Items" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Security Debt" -Wiql $securityDebtQuery
        Write-Host "  ✅ Security Debt" -ForegroundColor Gray

        Write-Host "[SUCCESS] All 5 security queries created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create some security queries: $_"
    }
}

<#
.SYNOPSIS
    Creates development-focused queries for PR tracking and technical debt.

.DESCRIPTION
    Provisions queries for development team workflow:
    - My PRs Awaiting Review
    - PRs I Need to Review
    - Technical Debt items
    - Recently Completed work
    - Code Review Feedback items

.PARAMETER Project
    Azure DevOps project name.

.EXAMPLE
    Ensure-AdoDevQueries -Project "MyProject"
#>
function Ensure-AdoDevQueries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )
    
    Write-Host "[INFO] Creating development-focused queries..." -ForegroundColor Cyan
    
    $folderPath = "Shared Queries/Development"
    
    # Create Development folder
    try {
        $folderPayload = @{
            name   = "Development"
            isFolder = $true
        }
        Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" -Body $folderPayload | Out-Null
        Write-Verbose "[Ensure-AdoDevQueries] Created Development queries folder"
    }
    catch {
        # Folder might already exist
        Write-Verbose "[Ensure-AdoDevQueries] Development folder exists or creation skipped"
    }
    
    # Define queries
    $queries = @(
        @{
            name = "My PRs Awaiting Review"
            wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.CreatedDate]
FROM WorkItems
WHERE [System.WorkItemType] = 'Task'
  AND [System.Tags] CONTAINS 'needs-review'
  AND [System.CreatedBy] = @Me
  AND [System.State] <> 'Closed'
ORDER BY [System.CreatedDate] DESC
"@
        },
        @{
            name = "PRs I Need to Review"
            wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.CreatedDate]
FROM WorkItems
WHERE [System.WorkItemType] = 'Task'
  AND [System.Tags] CONTAINS 'needs-review'
  AND [System.AssignedTo] = @Me
  AND [System.State] = 'Active'
ORDER BY [System.CreatedDate] ASC
"@
        },
        @{
            name = "Technical Debt"
            wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Scheduling.StoryPoints]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] IN ('User Story', 'Task', 'Bug')
  AND [System.Tags] CONTAINS 'tech-debt'
  AND [System.State] <> 'Closed'
ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [Microsoft.VSTS.Scheduling.StoryPoints] DESC
"@
        },
        @{
            name = "Recently Completed"
            wiql = @"
SELECT [System.Id], [System.Title], [System.WorkItemType], [System.AssignedTo], [Microsoft.VSTS.Common.ClosedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] IN ('User Story', 'Task', 'Bug')
  AND [System.State] = 'Closed'
  AND [Microsoft.VSTS.Common.ClosedDate] >= @Today - 14
ORDER BY [Microsoft.VSTS.Common.ClosedDate] DESC
"@
        },
        @{
            name = "Code Review Feedback"
            wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.ChangedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] IN ('User Story', 'Task')
  AND [System.Tags] CONTAINS 'review-feedback'
  AND [System.State] = 'Active'
ORDER BY [System.ChangedDate] DESC
"@
        }
    )
    
    # Create each query
    foreach ($q in $queries) {
        try {
            $queryPayload = @{
                name  = $q.name
                wiql  = $q.wiql
            }
            
            $encodedPath = [uri]::EscapeDataString("Shared Queries/Development/$($q.name)")
            try {
                # Try to get existing query
                $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$encodedPath"
                Write-Host "  ✓ Query exists: $($q.name)" -ForegroundColor Gray
            }
            catch {
                # Create new query
                $encodedFolder = [uri]::EscapeDataString("Shared Queries/Development")
                Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$encodedFolder" -Body $queryPayload | Out-Null
                Write-Host "  ✅ Created query: $($q.name)" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Failed to create query '$($q.name)': $_"
        }
    }
    
    Write-Host "[SUCCESS] Development queries created" -ForegroundColor Green
}

<#
.SYNOPSIS
    Creates enhanced repository files for development workflow.

.DESCRIPTION
    Adds enhanced repository files:
    - .gitignore (multi-language support)
    - .editorconfig (consistent formatting)
    - CONTRIBUTING.md (contribution guidelines)
    - CODEOWNERS (auto-assign reviewers)

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER RepoId
    Repository ID.

.PARAMETER RepoName
    Repository name.

.PARAMETER ProjectType
    Project type for .gitignore template (dotnet, node, python, java).

.EXAMPLE
    Ensure-AdoRepoFiles -Project "MyProject" -RepoId "repo-123" -RepoName "my-repo" -ProjectType "dotnet"
#>
function Ensure-AdoRepoFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$RepoName,
        
        [ValidateSet('dotnet', 'node', 'python', 'java', 'all')]
        [string]$ProjectType = 'all'
    )
    
    Write-Host "[INFO] Creating enhanced repository files..." -ForegroundColor Cyan
    
    # Get default branch
    try {
        $repo = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId"
        $defaultBranch = $repo.defaultBranch -replace '^refs/heads/', ''
    }
    catch {
        Write-Warning "Could not determine default branch, using 'main'"
        $defaultBranch = 'main'
    }
    
    # .gitignore content
    $gitignoreContent = @"
# Gitlab2DevOps - Enhanced .gitignore
# Generated for project type: $ProjectType

## User-specific files
*.suo
*.user
*.userosscache
*.sln.docstates
.vscode/
.idea/
*.swp
*.swo
*~

## Build results
[Dd]ebug/
[Rr]elease/
x64/
x86/
[Bb]in/
[Oo]bj/
[Ll]og/
[Ll]ogs/
*.log
build/
dist/
out/

## .NET
*.dll
*.exe
*.pdb
*.cache
project.lock.json
project.fragment.lock.json
artifacts/
**/Properties/launchSettings.json
TestResults/
*.VisualState.xml

## Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.npm
.eslintcache
.node_repl_history
*.tgz
.yarn-integrity
.env.local
.env.*.local

## Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
ENV/
.venv
pip-log.txt
pip-delete-this-directory.txt
.pytest_cache/
*.egg-info/
.coverage
htmlcov/

## Java
*.class
*.jar
*.war
*.ear
target/
.gradle/
gradle-app.setting
.gradletasknamecache
hs_err_pid*

## OS
.DS_Store
Thumbs.db
Desktop.ini

## Environment & Secrets (CRITICAL)
.env
.env.local
.env.*.local
appsettings.Development.json
appsettings.Local.json
secrets.json
*.pfx
*.key
*.pem

## Databases
*.db
*.sqlite
*.sqlite3

## Package managers
package-lock.json
yarn.lock
Gemfile.lock
poetry.lock
Pipfile.lock

## IDEs
.vs/
.vscode/settings.json
.idea/
*.iml
*.iws

## Temporary files
*.tmp
*.temp
*.bak
*.swp
*~

## Azure
local.settings.json
.azure/
"@

    # .editorconfig content
    $editorconfigContent = @"
# EditorConfig - Consistent coding styles
# https://editorconfig.org

root = true

# All files
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

# Code files
[*.{cs,csx,vb,vbx,js,ts,jsx,tsx,java,py}]
indent_style = space
indent_size = 4

# JSON, YAML, XML
[*.{json,yml,yaml,xml,csproj,props,targets}]
indent_style = space
indent_size = 2

# Markdown
[*.md]
trim_trailing_whitespace = false
max_line_length = 120

# Shell scripts
[*.{sh,bash,zsh}]
indent_style = space
indent_size = 2
end_of_line = lf

# Batch files
[*.{cmd,bat}]
end_of_line = crlf

# C# specific
[*.cs]
# Organize usings
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false

# this. preferences
dotnet_style_qualification_for_field = false:warning
dotnet_style_qualification_for_property = false:warning
dotnet_style_qualification_for_method = false:warning
dotnet_style_qualification_for_event = false:warning

# Language keywords vs BCL types
dotnet_style_predefined_type_for_locals_parameters_members = true:warning
dotnet_style_predefined_type_for_member_access = true:warning

# Parentheses preferences
dotnet_style_parentheses_in_arithmetic_binary_operators = always_for_clarity:warning
dotnet_style_parentheses_in_other_binary_operators = always_for_clarity:warning

# Expression preferences
dotnet_style_prefer_auto_properties = true:suggestion
dotnet_style_prefer_inferred_tuple_names = true:suggestion
dotnet_style_prefer_inferred_anonymous_type_member_names = true:suggestion

# Null checking
csharp_style_throw_expression = true:suggestion
csharp_style_conditional_delegate_call = true:suggestion

# var preferences
csharp_style_var_for_built_in_types = true:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = true:suggestion

# Expression-bodied members
csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_constructors = false:suggestion
csharp_style_expression_bodied_operators = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = when_on_single_line:suggestion

# Pattern matching
csharp_style_pattern_matching_over_is_with_cast_check = true:suggestion
csharp_style_pattern_matching_over_as_with_null_check = true:suggestion

# Null checking preferences
csharp_style_inlined_variable_declaration = true:suggestion

# Code block preferences
csharp_prefer_braces = true:warning

# JavaScript/TypeScript
[*.{js,ts,jsx,tsx}]
quote_type = single
indent_style = space
indent_size = 2

# Python
[*.py]
indent_style = space
indent_size = 4
max_line_length = 88
"@

    # CONTRIBUTING.md content
    $contributingContent = @"
# Contributing to $RepoName

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to this project.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Workflow](#development-workflow)
4. [Pull Request Process](#pull-request-process)
5. [Coding Standards](#coding-standards)
6. [Testing Requirements](#testing-requirements)
7. [Documentation](#documentation)

## Code of Conduct

### Our Pledge

- Be respectful and inclusive
- Accept constructive criticism gracefully
- Focus on what's best for the project
- Show empathy towards other contributors

### Unacceptable Behavior

- Harassment or discriminatory language
- Trolling or insulting comments
- Personal attacks
- Publishing others' private information

## Getting Started

### Prerequisites

Review the [Development Setup Guide](/Development/Development-Setup) in the project wiki for:
- Required software and tools
- Environment configuration
- Local development setup

### First Contribution

**Good First Issues**: Look for issues tagged with \``good-first-issue\`` label.

**Steps**:
1. Fork the repository (if external) or create a branch
2. Set up local development environment
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Development Workflow

### Branching Strategy

Follow the [Git Workflow](/Development/Git-Workflow) guide:

````````````bash
# Create feature branch
git checkout -b feature/123-your-feature-name

# Make changes and commit
git add .
git commit -m "feat(module): add new feature"

# Push to remote
git push -u origin feature/123-your-feature-name
````````````

### Branch Naming

**Pattern**: \``<type>/<ticket-number>-<description>\``

**Types**:
- \``feature/\`` - New features
- \``bugfix/\`` - Bug fixes
- \``hotfix/\`` - Urgent production fixes
- \``refactor/\`` - Code refactoring
- \``docs/\`` - Documentation only

**Examples**:
- \``feature/123-add-authentication\``
- \``bugfix/456-fix-null-reference\``
- \``docs/789-update-api-guide\``

### Commit Messages

Follow conventional commits:

````````````
<type>(<scope>): <subject>

[optional body]

[optional footer]
````````````

**Types**: \``feat\``, \``fix\``, \``docs\``, \``style\``, \``refactor\``, \``test\``, \``chore\``

**Examples**:
````````````
feat(auth): add JWT token validation

fix(api): handle null response from external service

docs(readme): update installation instructions
````````````

## Pull Request Process

### Before Creating PR

✅ **Checklist**:
- [ ] Code builds successfully
- [ ] All tests pass
- [ ] New tests added for new functionality
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] No merge conflicts with main branch
- [ ] Self-reviewed the changes
- [ ] Work item linked

### PR Title

Follow same format as commit messages:
````````````
feat(auth): add OAuth2 support
````````````

### PR Description

Use the PR template (created automatically):

````````````markdown
## What
Brief description of changes

## Why
Reason for changes (link to work item)

## How
Technical approach and implementation details

## Testing
- [ ] Unit tests added
- [ ] Integration tests added
- [ ] Manual testing performed

## Screenshots (if UI changes)
[Attach screenshots]

## Checklist
- [ ] Code follows style guidelines
- [ ] Tests pass locally
- [ ] Documentation updated
````````````

### Review Process

1. **Automated Checks**: CI build must pass
2. **Code Review**: Minimum 2 approvals required
3. **Address Feedback**: Respond to all comments
4. **Final Approval**: Once approved, PR can be merged

**Response Time**:
- Reviewers: 24 hours
- Authors (feedback): 48 hours

## Coding Standards

### General Principles

- **DRY**: Don't Repeat Yourself
- **KISS**: Keep It Simple, Stupid
- **YAGNI**: You Aren't Gonna Need It
- **SOLID**: Object-oriented design principles

### Code Style

#### .NET / C#
````````````csharp
// Use PascalCase for classes and methods
public class UserService
{
    // Use camelCase for parameters and local variables
    public User GetUser(int userId)
    {
        var user = _repository.FindById(userId);
        return user;
    }
}
````````````

#### JavaScript / TypeScript
````````````javascript
// Use camelCase for variables and functions
function getUserById(userId) {
    const user = repository.findById(userId);
    return user;
}

// Use PascalCase for classes
class UserService {
    getUser(userId) {
        return this.repository.findById(userId);
    }
}
````````````

#### Python
````````````python
# Use snake_case for functions and variables
def get_user_by_id(user_id):
    user = repository.find_by_id(user_id)
    return user

# Use PascalCase for classes
class UserService:
    def get_user(self, user_id):
        return self.repository.find_by_id(user_id)
````````````

### Documentation Comments

#### C#
````````````csharp
/// <summary>
/// Gets user by ID.
/// </summary>
/// <param name="userId">The user identifier.</param>
/// <returns>User object or null if not found.</returns>
public User GetUser(int userId)
````````````

#### JavaScript
````````````javascript
/**
 * Gets user by ID.
 * @param {number} userId - The user identifier
 * @returns {Promise<User>} User object or null
 */
async function getUser(userId)
````````````

## Testing Requirements

### Test Coverage

- **Minimum**: 80% code coverage
- **Target**: 90%+ for critical paths
- **Required**: Tests for all public APIs

### Test Types

1. **Unit Tests**: Test individual components
2. **Integration Tests**: Test component interactions
3. **E2E Tests**: Test full user flows (where applicable)

### Test Structure

````````````csharp
[Fact]
public void GetUser_ValidId_ReturnsUser()
{
    // Arrange
    var userId = 123;
    var expected = new User { Id = userId };
    
    // Act
    var result = _service.GetUser(userId);
    
    // Assert
    Assert.Equal(expected.Id, result.Id);
}
````````````

### Running Tests

````````````bash
# .NET
dotnet test

# Node.js
npm test

# Python
pytest
````````````

## Documentation

### When to Document

**Always Document**:
- Public APIs
- Complex algorithms
- Non-obvious decisions
- Architecture changes

**Wiki Updates**:
- Update [API Documentation](/Development/API-Documentation) for API changes
- Create [ADR](/Development/Architecture-Decision-Records) for architectural decisions
- Update [Dependencies](/Development/Dependencies) when adding/removing packages

### Documentation Standards

- Use clear, concise language
- Include code examples
- Keep documentation up to date with code
- Link to related documentation

## Questions?

- **Technical Questions**: Ask in team chat or daily standup
- **Process Questions**: Contact tech lead
- **Issues**: Create an issue in Azure Boards

---

**Thank you for contributing!** Every contribution, no matter how small, helps improve the project.
"@

    # CODEOWNERS content
    $codeownersContent = @"
# CODEOWNERS - Auto-assign reviewers for PRs
# https://docs.microsoft.com/en-us/azure/devops/repos/git/require-branch-folders

# Default owners for everything
* @$Project-Team

# API / Backend
/src/API/ @backend-team
/src/Services/ @backend-team
/src/Domain/ @backend-team

# Frontend / UI
/src/Web/ @frontend-team
/src/UI/ @frontend-team
/client/ @frontend-team

# Infrastructure / DevOps
/azure-pipelines.yml @devops-team
/Dockerfile @devops-team
/docker-compose.yml @devops-team
/.github/ @devops-team
/terraform/ @devops-team
/k8s/ @devops-team

# Database
/src/Migrations/ @database-team
/database/ @database-team
*.sql @database-team

# Documentation
/docs/ @tech-writers
README.md @tech-writers
CONTRIBUTING.md @tech-writers

# Configuration
appsettings.json @devops-team @backend-team
*.config @devops-team

# Dependencies
package.json @tech-lead
package-lock.json @tech-lead
*.csproj @tech-lead
requirements.txt @tech-lead

# Security-sensitive files
/src/Auth/ @security-team @tech-lead
/src/Security/ @security-team @tech-lead

# Tests
/tests/ @qa-team
*.Tests.cs @qa-team
*.test.js @qa-team
*_test.py @qa-team

# Root configuration files
/.editorconfig @tech-lead
/.gitignore @tech-lead
/CODEOWNERS @tech-lead
"@

    # Create files via Git push API
    $filesCreated = @()
    
    try {
        # Get latest commit
        $refs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$defaultBranch"
        if ($refs.value.Count -eq 0) {
            Write-Warning "Repository has no commits yet. Files will be added after first push."
            return
        }
        
        $latestCommit = $refs.value[0].objectId
        
        # Prepare push with all files
        $changes = @()
        
        # Add .gitignore if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.gitignore"
            Write-Host "  ✓ .gitignore already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/.gitignore" }
                newContent = @{
                    content = $gitignoreContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add .editorconfig if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.editorconfig"
            Write-Host "  ✓ .editorconfig already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/.editorconfig" }
                newContent = @{
                    content = $editorconfigContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add CONTRIBUTING.md if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/CONTRIBUTING.md"
            Write-Host "  ✓ CONTRIBUTING.md already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/CONTRIBUTING.md" }
                newContent = @{
                    content = $contributingContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add CODEOWNERS if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/CODEOWNERS"
            Write-Host "  ✓ CODEOWNERS already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/CODEOWNERS" }
                newContent = @{
                    content = $codeownersContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Push all changes if any
        if ($changes.Count -gt 0) {
            $pushPayload = @{
                refUpdates = @(
                    @{
                        name = "refs/heads/$defaultBranch"
                        oldObjectId = $latestCommit
                    }
                )
                commits = @(
                    @{
                        comment = "Add enhanced repository files (gitignore, editorconfig, CONTRIBUTING, CODEOWNERS)"
                        changes = $changes
                    }
                )
            }
            
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushPayload | Out-Null
            Write-Host "[SUCCESS] Created repository files: $($changes.Count) file(s)" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] All repository files already exist" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Failed to create repository files: $_"
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Wait-AdoOperation',
    'Get-AdoProjectList',
    'Test-AdoProjectExists',
    'Get-AdoProjectRepositories',
    'Ensure-AdoProject',
    'Get-AdoProjectDescriptor',
    'Get-AdoBuiltInGroupDescriptor',
    'Ensure-AdoGroup',
    'Ensure-AdoMembership',
    'Ensure-AdoArea',
    'Ensure-AdoProjectWiki',
    'Upsert-AdoWikiPage',
    'Get-AdoProjectProcessTemplate',
    'Get-AdoWorkItemTypes',
    'Ensure-AdoTeamTemplates',
    'Ensure-AdoIterations',
    'Ensure-AdoSharedQueries',
    'Ensure-AdoRepositoryTemplates',
    'Ensure-AdoTeamSettings',
    'Ensure-AdoDashboard',
    'Ensure-AdoCommonTags',
    'Ensure-AdoBestPracticesWiki',
    'Ensure-AdoBusinessWiki',
    'Ensure-AdoDevWiki',
    'Ensure-AdoDevDashboard',
    'Ensure-AdoDevQueries',
    'Ensure-AdoRepoFiles',
    'Ensure-AdoSecurityWiki',
    'Ensure-AdoSecurityQueries',
    'Ensure-AdoTestPlan',
    'Ensure-AdoQAQueries',
    'Ensure-AdoQADashboard',
    'Ensure-AdoTestConfigurations',
    'Ensure-AdoQAGuidelinesWiki',
    'Ensure-AdoBusinessQueries',
    'Ensure-AdoRepository',
    'Get-AdoRepoDefaultBranch',
    'Ensure-AdoBranchPolicies',
    'Ensure-AdoRepoDeny'
)
