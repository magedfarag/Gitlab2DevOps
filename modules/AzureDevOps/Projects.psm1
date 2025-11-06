<#
.SYNOPSIS
    Project creation and configuration

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Module-level cache for project list
$script:ProjectListCache = $null
$script:ProjectListCacheTime = $null
$script:ProjectListCacheTTL = 300 # 5 minutes

<#
.SYNOPSIS
    Gets a list of all Azure DevOps projects with caching.

.PARAMETER RefreshCache
    Force refresh the cache.

.PARAMETER UseCache
    Use cached data if available.

.OUTPUTS
    Array of project objects.
#>
function Get-AdoProjectList {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [switch]$RefreshCache,
        [switch]$UseCache
    )
    
    # Check if we should use cache
    if ($UseCache -and $script:ProjectListCache -and $script:ProjectListCacheTime) {
        $age = ((Get-Date) - $script:ProjectListCacheTime).TotalSeconds
        if ($age -lt $script:ProjectListCacheTTL) {
            Write-Verbose "[Get-AdoProjectList] Using cached project list (age: $([int]$age)s)"
            return $script:ProjectListCache
        }
    }
    
    # Fetch project list
    try {
        $result = Invoke-AdoRest GET "/_apis/projects?`$top=5000"
        $projects = $result.value
        
        # Update cache
        $script:ProjectListCache = $projects
        $script:ProjectListCacheTime = Get-Date
        
        Write-Verbose "[Get-AdoProjectList] Fetched $($projects.Count) projects from server"
        return $projects
    }
    catch {
        Write-Warning "[Get-AdoProjectList] Failed to fetch project list: $_"
        # Return cached data if available, even if stale
        if ($script:ProjectListCache) {
            Write-Warning "[Get-AdoProjectList] Returning stale cached data"
            return $script:ProjectListCache
        }
        return @()
    }
}

<#
.SYNOPSIS
    Gets all repositories for a specific Azure DevOps project.

.OUTPUTS
    Array of repository objects.
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

# Export functions
Export-ModuleMember -Function @(
    'Get-AdoProjectRepositories',
    'Ensure-AdoProject',
    'Get-AdoProjectDescriptor',
    'Get-AdoProjectProcessTemplate',
    'Get-AdoWorkItemTypes',
    'Ensure-AdoArea',
    'Ensure-AdoIterations'
)
