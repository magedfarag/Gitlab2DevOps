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
    $list = Invoke-AdoRest GET "/_apis/projects?`$top=5000"
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
    
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&`$top=200"
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
    
    $groups = Invoke-AdoRest GET "/_apis/graph/groups?scopeDescriptor=$ProjDesc&`$top=200"
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
    
    # Set templates as team defaults
    Write-Host ""
    Write-Host "[INFO] Setting templates as team defaults..." -ForegroundColor Cyan
    
    $setDefaultCount = 0
    foreach ($workItemType in $availableTypes) {
        if ($templateDefinitions.ContainsKey($workItemType)) {
            $template = $templateDefinitions[$workItemType]
            
            try {
                # Get the template ID
                $templateToSet = $byName[$template.name]
                if (-not $templateToSet) {
                    # Try to get updated list of templates
                    $existing = Invoke-AdoRest GET $base
                    $byName = @{}
                    $existing.value | ForEach-Object { $byName[$_.name] = $_ }
                    $templateToSet = $byName[$template.name]
                }
                
                if ($templateToSet) {
                    Write-Verbose "[Ensure-AdoTeamTemplates] Setting template as default: $($template.name) (ID: $($templateToSet.id))"
                    
                    # Set as team default using PATCH request
                    $patchBody = @{
                        id = $templateToSet.id
                        name = $templateToSet.name
                        workItemTypeName = $workItemType
                        isDefault = $true
                    }
                    
                    Invoke-AdoRest PATCH "$base/$($templateToSet.id)" -Body $patchBody | Out-Null
                    Write-Host "[SUCCESS] Set $workItemType template as team default" -ForegroundColor Green
                    $setDefaultCount++
                }
            }
            catch {
                Write-Warning "Failed to set $workItemType template as default: $_"
                Write-Verbose "[AzureDevOps] This is usually not critical - templates can still be used manually"
            }
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Work item template configuration summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount templates" -ForegroundColor Green
    Write-Host "  ⏭️ Skipped: $skippedCount templates (already exist)" -ForegroundColor Yellow
    Write-Host "  🎯 Set as default: $setDefaultCount templates" -ForegroundColor Green
    Write-Host "  📋 Available work item types: $($availableTypes -join ', ')" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] Templates will auto-populate when creating new work items!" -ForegroundColor Cyan
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
        $response = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/work/teamsettings/iterations?`$timeframe=current"
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
        $response = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=1"
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
        $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/commits?`$top=1"
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
\`\`\`bash
# Clone the repository
git clone <repository-url>

# Install dependencies
# Add installation commands here
\`\`\`

### Running Locally
\`\`\`bash
# Add commands to run the application locally
\`\`\`

## Development Workflow

1. Create a feature branch from \`main\`
   \`\`\`bash
   git checkout -b feature/your-feature-name
   \`\`\`

2. Make your changes and commit
   \`\`\`bash
   git add .
   git commit -m "Description of changes"
   \`\`\`

3. Push and create a pull request
   \`\`\`bash
   git push origin feature/your-feature-name
   \`\`\`

4. Link your work items in the PR description
5. Request code review
6. Merge after approval

## Project Structure
\`\`\`
/src        - Source code
/docs       - Documentation
/tests      - Test files
/scripts    - Build and deployment scripts
\`\`\`

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
   - Example: \`frontend, needs-review, breaking-change\`

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
- **Blocked Work**: \`Tags Contains 'blocked'\`
- **Technical Debt**: \`Tags Contains 'technical-debt'\`
- **Needs Review**: \`Tags Contains 'needs-review'\`
- **Breaking Changes**: \`Tags Contains 'breaking-change'\`

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
            $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($existing.id)/commits?`$top=1"
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
    'Ensure-AdoCommonTags',
    'Ensure-AdoRepository',
    'Get-AdoRepoDefaultBranch',
    'Ensure-AdoBranchPolicies',
    'Ensure-AdoRepoDeny'
)
