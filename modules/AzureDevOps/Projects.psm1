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

# Ensure Core REST dependencies are available when module is imported standalone
$moduleRoot = Split-Path $PSScriptRoot -Parent
$coreRestModule = Join-Path $moduleRoot 'core\Core.Rest.psm1'
if (-not (Get-Module -Name 'Core.Rest') -and (Test-Path $coreRestModule)) {
    Import-Module $coreRestModule -Force -ErrorAction Stop
}

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
        
        # Check if result is valid
        if (-not $result) {
            Write-Warning "[Get-AdoProjectList] Invoke-AdoRest returned null result"
            # Return cached data if available, even if stale
            if ($script:ProjectListCache) {
                Write-Warning "[Get-AdoProjectList] Returning stale cached data"
                return $script:ProjectListCache
            }
            return @()
        }
        
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


function Measure-Adoproject {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$ProcessTemplate = "Agile" # Default to Agile template
    )
    
    Write-Verbose "[Measure-Adoproject] Checking if project '$Name' exists..."
    
    # Force refresh cache to ensure we have latest project list
    # This prevents attempting to create projects that already exist
    $projects = Get-AdoProjectList -RefreshCache
    $p = $projects | Where-Object { $_.name -eq $Name }
    
    if ($p) {
        Write-Verbose "[Measure-Adoproject] Project '$Name' already exists (ID: $($p.id))"
        Write-Host "[INFO] Project '$Name' already exists - no changes needed" -ForegroundColor Green
        return $p
    }
    
    if ($PSCmdlet.ShouldProcess($Name, "Create Azure DevOps project")) {
        # Resolve process template name to GUID by querying available processes
        $processTemplateId = $ProcessTemplate
        
        # If not a GUID, look up by name
        if ($ProcessTemplate -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            Write-Verbose "[Measure-Adoproject] Resolving process template name '$ProcessTemplate' to GUID..."
            try {
                $processes = Invoke-AdoRest GET "/_apis/process/processes"
                $matchedProcess = $processes.value | Where-Object { $_.name -eq $ProcessTemplate }
                
                if ($matchedProcess) {
                    $processTemplateId = $matchedProcess.id
                    Write-Verbose "[Measure-Adoproject] Resolved '$ProcessTemplate' to GUID: $processTemplateId"
                } else {
                    Write-Warning "[Measure-Adoproject] Process template '$ProcessTemplate' not found. Using default."
                    $defaultProcess = $processes.value | Where-Object { $_.isDefault -eq $true }
                    if ($defaultProcess) {
                        $processTemplateId = $defaultProcess.id
                        Write-Verbose "[Measure-Adoproject] Using default process: $($defaultProcess.name) ($processTemplateId)"
                    } else {
                        throw "No default process template found on server"
                    }
                }
            }
            catch {
                Write-Warning "[Measure-Adoproject] Failed to query process templates: $_"
                # If we couldn't query process templates, don't blindly pass a process name as a GUID
                if ($ProcessTemplate -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                    Write-Error "[Measure-Adoproject] Could not resolve process template name '$ProcessTemplate' to a GUID. Server query failed and no GUID was provided. Aborting project creation to avoid sending an invalid template ID."
                    throw "Failed to resolve process template '$ProcessTemplate' to GUID. Query '/_apis/process/processes' failed. Please retry or provide a process template GUID."
                }
                else {
                    # If the caller already provided a GUID string, accept it
                    $processTemplateId = $ProcessTemplate
                    Write-Verbose "[Measure-Adoproject] Using provided GUID for process template: $processTemplateId"
                }
            }
        }
        
        Write-Host "[INFO] Creating project '$Name' with $ProcessTemplate process template..." -ForegroundColor Cyan
        Write-Verbose "[Measure-Adoproject] Process Template ID: $processTemplateId"
        
        $body = @{
            name         = $Name
            description  = "Provisioned by GitLab to Azure DevOps migration"
            capabilities = @{
                versioncontrol  = @{ sourceControlType = "Git" }
                processTemplate = @{ templateTypeId = $processTemplateId }
            }
        }
        
        Write-Verbose "[Measure-Adoproject] Sending POST request to create project..."
        Write-Verbose "[Measure-Adoproject] Request body: $($body | ConvertTo-Json -Depth 5)"
        $resp = Invoke-AdoRest POST "/_apis/projects" -Body $body
        
        Write-Verbose "[Measure-Adoproject] Project creation initiated, operation ID: $($resp.id)"
        Write-Host "[INFO] Project creation operation started (ID: $($resp.id))" -ForegroundColor Cyan
        Write-Host "[INFO] Waiting for operation to complete..." -ForegroundColor Cyan
        
        $final = Wait-AdoOperation $resp.id
        
        if ($final.status -ne 'succeeded') {
            Write-Error "[Measure-Adoproject] Project creation failed with status: $($final.status)"
            throw "Project creation failed with status: $($final.status)"
        }
        
        Write-Verbose "[Measure-Adoproject] Project creation completed successfully"
        
        # Invalidate project cache after creating new project
        Write-Verbose "[Measure-Adoproject] Invalidating project cache after creation"
        Get-AdoProjectList -RefreshCache | Out-Null
        
        Write-Host "[SUCCESS] Project '$Name' created successfully" -ForegroundColor Green
        
        Write-Verbose "[Measure-Adoproject] Fetching project details..."
        return Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Name))"
    }
}


function Test-AdoProjectExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
    
    Write-Verbose "[Test-AdoProjectExists] Checking if project '$ProjectName' exists..."
    
    try {
        # Use cached project list for efficiency (same pattern as Measure-Adoproject)
        $projects = Get-AdoProjectList -UseCache
        $project = $projects | Where-Object { $_.name -eq $ProjectName }
        
        $exists = $null -ne $project
        Write-Verbose "[Test-AdoProjectExists] Project '$ProjectName' exists: $exists"
        return $exists
    }
    catch {
        Write-Warning "[Test-AdoProjectExists] Failed to check project existence: $_"
        return $false
    }
}


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


function Get-AdoWorkItemTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )

    try {
        $projEscaped = [uri]::EscapeDataString($Project)
        $types = Invoke-AdoRest GET "/$projEscaped/_apis/wit/workitemtypes"

        # Normalize string payloads (some wrappers may return raw JSON)
        if ($types -is [string]) {
            try {
                # Try -AsHashTable first as it's more robust for edge cases
                Write-Verbose "[Get-AdoWorkItemTypes] Attempting JSON parsing with -AsHashTable"
                $types = $types | ConvertFrom-Json -AsHashTable -ErrorAction Stop
                Write-Verbose "[Get-AdoWorkItemTypes] Successfully parsed JSON string response to hashtable"
            }
            catch {
                Write-Verbose "[Get-AdoWorkItemTypes] -AsHashTable failed, trying regular parsing: $_"
                try {
                    $types = $types | ConvertFrom-Json -ErrorAction Stop
                    Write-Verbose "[Get-AdoWorkItemTypes] Successfully parsed JSON string response to object"
                }
                catch {
                    Write-Verbose "[Get-AdoWorkItemTypes] Response was string but failed to parse JSON: $_"
                    # If JSON parsing fails completely, log the raw response for debugging
                    Write-Verbose "[Get-AdoWorkItemTypes] Raw response (first 500 chars): $($types.Substring(0, [Math]::Min(500, $types.Length)))"
                    # Return empty array to avoid breaking the caller
                    return @()
                }
            }
        }

        # Handle different response formats more defensively
        $typeNames = @()

        if ($types -is [array]) {
            Write-Verbose "[Get-AdoWorkItemTypes] Response is direct array with $($types.Count) items"
            $typeNames = $types | ForEach-Object {
                if ($_.PSObject.Properties['name']) {
                    $_.name
                } elseif ($_.PSObject.Properties['referenceName']) {
                    $_.referenceName
                } else {
                    $null
                }
            }
        }
        elseif ($types -and $types.PSObject.Properties['value']) {
            Write-Verbose "[Get-AdoWorkItemTypes] Response wrapped in 'value' property with $($types.value.Count) items"
            $typeNames = $types.value | ForEach-Object {
                if ($_.PSObject.Properties['name']) {
                    $_.name
                } elseif ($_.PSObject.Properties['referenceName']) {
                    $_.referenceName
                } else {
                    $null
                }
            }
        }
        elseif ($types -and $types.PSObject.Properties['workItemTypes']) {
            Write-Verbose "[Get-AdoWorkItemTypes] Response contains 'workItemTypes' property with $($types.workItemTypes.Count) items"
            $typeNames = $types.workItemTypes | ForEach-Object {
                if ($_.PSObject.Properties['name']) {
                    $_.name
                } elseif ($_.PSObject.Properties['referenceName']) {
                    $_.referenceName
                } else {
                    $null
                }
            }
        }
        elseif ($types -is [hashtable] -and $types.ContainsKey('value')) {
            Write-Verbose "[Get-AdoWorkItemTypes] Response is hashtable wrapped in 'value' property with $($types.value.Count) items"
            $typeNames = $types.value | ForEach-Object {
                if ($_ -is [hashtable] -and $_.ContainsKey('name')) {
                    $_.name
                } elseif ($_.PSObject.Properties['name']) {
                    $_.name
                } elseif ($_.PSObject.Properties['referenceName']) {
                    $_.referenceName
                } else {
                    $null
                }
            }
        }
        else {
            # Try to enumerate any objects that look like work item type descriptors
            Write-Verbose "[Get-AdoWorkItemTypes] Response format unknown, attempting to enumerate for items with 'name' property"
            Write-Verbose "[Get-AdoWorkItemTypes] Response type: $($types.GetType().FullName)"
            Write-Verbose "[Get-AdoWorkItemTypes] Properties: $($types.PSObject.Properties.Name -join ', ')"

            $candidates = @()
            try {
                $candidates = @($types) | Where-Object { $_ -and $_.PSObject.Properties['name'] }
            }
            catch {
                $candidates = @()
            }

            if ($candidates -and $candidates.Count -gt 0) {
                $typeNames = $candidates | ForEach-Object { $_.name }
            }
        }

        # Filter out nulls and empty strings
        $typeNames = @($typeNames | Where-Object { $_ })

        if ($typeNames.Count -gt 0) {
            Write-Host "[INFO] Available work item types in project '$Project': $($typeNames -join ', ')" -ForegroundColor Cyan
            return $typeNames
        }

        # If nothing found, return empty array (caller may fall back to process-template defaults)
        Write-Verbose "[Get-AdoWorkItemTypes] No explicit work item types detected in response"
        return @()
    }
    catch {
        Write-Warning "[Get-AdoWorkItemTypes] Failed to get work item types: $_"
        Write-Verbose "[Get-AdoWorkItemTypes] Error details: $($_.Exception.Message)"
        # Return empty array - let caller decide defaults based on process template
        Write-Host "[WARN] Could not detect work item types automatically" -ForegroundColor Yellow
        return @()
    }
}


function Measure-Adoarea {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$Area,
        
        [string]$CollectionUrl,
        [string]$AdoPat,
        [string]$AdoApiVersion
    )
    
    # Respect environment override to disable automatic area creation
    $disableAreaCreation = $false
    if ($env:GITLAB2DEVOPS_DISABLE_AREA_CREATION) {
        if ($env:GITLAB2DEVOPS_DISABLE_AREA_CREATION -match '^(1|true)$') { $disableAreaCreation = $true }
    }

    try {
        $area = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas/$([uri]::EscapeDataString($Area))"
        Write-Host "[INFO] Area '$Area' already exists" -ForegroundColor Gray
        return $area
    }
    catch {
        # 404 is expected for new areas - don't treat as error
        if ($disableAreaCreation) {
            Write-Host "[INFO] Area creation disabled; skipping creation of area '$Area'" -ForegroundColor Yellow
            # Return a placeholder object so callers can continue
            return [PSCustomObject]@{ name = $Area }
        }
        Write-Host "[INFO] Creating area '$Area'" -ForegroundColor Cyan
        Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas" -Body @{ name = $Area }
    }
}


function Measure-Adoiterations {
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
    
    # Get existing iterations from project classification nodes (safer - returns all iterations)
    $existingIterations = @()
    try {
        $respNodes = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations?`$depth=5"
        # Flatten tree to collect names
        function Get-IterationNamesFromNode($node) {
            $names = @()
            if ($node.name) { $names += $node.name }
            if ($node.PSObject.Properties['children'] -and $node.children) {
                foreach ($c in $node.children) { $names += Get-IterationNamesFromNode $c }
            }
            return $names
        }
        if ($respNodes -and $respNodes.value) {
            foreach ($root in $respNodes.value) {
                $existingIterations += Get-IterationNamesFromNode $root
            }
        }
        elseif ($respNodes -and $respNodes.name) {
            $existingIterations += Get-IterationNamesFromNode $respNodes
        }
        $existingIterations = $existingIterations | Select-Object -Unique
    }
    catch {
        Write-Verbose "[Measure-Adoiterations] Could not retrieve classification nodes for iterations: $_"
        # Fallback to teamsettings current iterations
        try {
            $response = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings/iterations?`$timeframe=current"
            if ($response -and $response.value) { $existingIterations += $response.value | ForEach-Object { $_.name } }
            $existingIterations = $existingIterations | Select-Object -Unique
        }
        catch {
            Write-Verbose "[Measure-Adoiterations] Could not retrieve existing iterations (fallback): $_"
        }
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
            
            Write-Verbose "[Measure-Adoiterations] Creating iteration: $sprintName ($($sprintStart.ToString('yyyy-MM-dd')) to $($sprintEnd.ToString('yyyy-MM-dd')))"
            $res = Ensure-AdoIteration -Project $Project -Name $sprintName -StartDate $sprintStart -FinishDate $sprintEnd -Team $Team
            if ($res -and $res.Node) {
                $iterations += $res.Node
                if ($res.Created) {
                    Write-Host "[SUCCESS] Created '$sprintName' ($($sprintStart.ToString('MMM dd')) - $($sprintEnd.ToString('MMM dd, yyyy')))" -ForegroundColor Green
                    $createdCount++
                }
                else {
                    Write-Host "[INFO] Found existing iteration '$sprintName'" -ForegroundColor Gray
                    $skippedCount++
                }
            }
            else {
                Write-Warning "Failed to ensure iteration '$sprintName'"
            }
        }
        catch {
            # Handle duplicate name race conditions gracefully: if server reports ClassificationNodeDuplicateNameException
            $errMsg = $_.Exception.Message
            if ($errMsg -and ($errMsg -match 'ClassificationNodeDuplicateNameException' -or $errMsg -match 'ClassificationNodeDuplicateName')) {
                Write-Verbose "[Measure-Adoiterations] Iteration '$sprintName' already created by another process - fetching existing node"
                try {
                    $existingIteration = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations/$([uri]::EscapeDataString($sprintName))"
                    if ($existingIteration) {
                        $iterations += $existingIteration
                        Write-Host "[INFO] Found existing iteration '$sprintName' after duplicate error" -ForegroundColor Gray
                        $skippedCount++
                        continue
                    }
                }
                catch {
                    Write-Warning "Iteration reported duplicate but failed to fetch existing node for '$sprintName': $_"
                    continue
                }
            }

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

# Idempotent iteration ensure helper
function Ensure-AdoIteration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Project,
        [Parameter(Mandatory=$true)] [string]$Name,
        [DateTime]$StartDate,
        [DateTime]$FinishDate,
        [string]$Team
    )

    $projEnc = [uri]::EscapeDataString($Project)
    $nameEnc = [uri]::EscapeDataString($Name)

    # Try to get existing node first
    try {
        $existing = Invoke-AdoRest GET "/$projEnc/_apis/wit/classificationnodes/iterations/$nameEnc" -ReturnNullOnNotFound
        if ($existing) {
            Write-Verbose "[Ensure-AdoIteration] Iteration '$Name' already exists in project '$Project'"
            try { Add-InitMetric -Category 'iterations' -Action 'skipped' } catch { }
            return @{ Name = $Name; Created = $false; Node = $existing }
        }
    }
    catch {
        Write-Verbose "[Ensure-AdoIteration] Could not GET existing iteration '$Name' (will attempt create): $_"
    }

    # Build body and attempt to create
    $body = @{ name = $Name }
    if ($PSBoundParameters.ContainsKey('StartDate') -and $PSBoundParameters.ContainsKey('FinishDate')) {
        $body.attributes = @{ startDate = $StartDate.ToString('yyyy-MM-ddTHH:mm:ssZ'); finishDate = $FinishDate.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }

    try {
        Write-Verbose "[Ensure-AdoIteration] Creating iteration '$Name' in project '$Project'"
        $iteration = Invoke-AdoRest POST "/$projEnc/_apis/wit/classificationnodes/iterations" -Body $body

        if ($Team -and $iteration -and $iteration.identifier) {
            try {
                $teamIterationBody = @{ id = $iteration.identifier }
                Invoke-AdoRest POST "/$projEnc/$([uri]::EscapeDataString($Team))/_apis/work/teamsettings/iterations" -Body $teamIterationBody | Out-Null
            }
            catch {
                Write-Warning "Created iteration but failed to assign to team '$Team': $_"
            }
        }

        try { Add-InitMetric -Category 'iterations' -Action 'created' } catch { }
        return @{ Name = $Name; Created = $true; Node = $iteration }
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -and ($errMsg -match 'ClassificationNodeDuplicateNameException' -or $errMsg -match 'TF237018' -or $errMsg -match 'ClassificationNodeDuplicateName')) {
            Write-Verbose "[Ensure-AdoIteration] Duplicate-name detected when creating '$Name' - fetching existing node"
            try {
                $existing2 = Invoke-AdoRest GET "/$projEnc/_apis/wit/classificationnodes/iterations/$nameEnc"
                if ($existing2) { try { Add-InitMetric -Category 'iterations' -Action 'skipped' } catch { }; return @{ Name = $Name; Created = $false; Node = $existing2 } }
            }
            catch {
                Write-Warning "Iteration reported duplicate but failed to fetch existing node for '$Name': $_"
                try { Add-InitMetric -Category 'iterations' -Action 'failed' } catch { }
                return @{ Name = $Name; Created = $false; Node = $null; Error = $_ }
            }
        }

        Write-Warning "Failed to create iteration '$Name': $_"
        try { Add-InitMetric -Category 'iterations' -Action 'failed' } catch { }
        return @{ Name = $Name; Created = $false; Node = $null; Error = $_ }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-AdoProjectList',
    'Get-AdoProjectRepositories',
    'Measure-Adoproject',
    'Test-AdoProjectExists',
    'Get-AdoProjectProcessTemplate',
    'Get-AdoWorkItemTypes',
    'Measure-Adoarea',
    'Measure-Adoiterations',
    'Ensure-AdoIteration'
)

