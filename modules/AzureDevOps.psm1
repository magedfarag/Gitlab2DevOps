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
    
    # Load QA guidelines content from external template
    $qaGuidelinesContent = Get-WikiTemplate "QA/QAGuidelines"
    
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
    
    $bestPracticesContent = Get-WikiTemplate "BestPractices/BestPractices"

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
    $adrContent = Get-WikiTemplate "Dev/ADR"

    # Development Setup
    $devSetupContent = Get-WikiTemplate "Dev/DevSetup"

    # API Documentation
    $apiDocsContent = Get-WikiTemplate "Dev/APIDocs"

    # Git Workflow
    $gitWorkflowContent = Get-WikiTemplate "Dev/GitWorkflow"

    # Code Review Checklist
    $codeReviewContent = Get-WikiTemplate "Dev/CodeReview"

    # Troubleshooting Guide
    $troubleshootingContent = Get-WikiTemplate "Dev/Troubleshooting"

    # Dependencies
    $dependenciesContent = Get-WikiTemplate "Dev/Dependencies"

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
    $securityPoliciesContent = Get-WikiTemplate "Security/SecurityPolicies"

    # Threat Modeling Guide
    $threatModelingContent = Get-WikiTemplate "Security/ThreatModeling"

    # Security Testing Checklist
    $securityTestingContent = Get-WikiTemplate "Security/SecurityTesting"

    # Incident Response Plan
    $incidentResponseContent = Get-WikiTemplate "Security/IncidentResponse"

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
        $complianceContent = Get-WikiTemplate "Security/Compliance"

        Upsert-AdoWikiPage $Project $WikiId "/Security/Compliance-Requirements" $complianceContent
        Write-Host "  ✅ Compliance Requirements" -ForegroundColor Gray
        
        # Secret Management
        $secretManagementContent = Get-WikiTemplate "Security/SecretManagement"

        Upsert-AdoWikiPage $Project $WikiId "/Security/Secret-Management" $secretManagementContent
        Write-Host "  ✅ Secret Management" -ForegroundColor Gray
        
        # Security Champions Program
        $securityChampionsContent = Get-WikiTemplate "Security/SecurityChampions"

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
