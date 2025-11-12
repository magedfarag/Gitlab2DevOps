<#
.SYNOPSIS
    Work items, queries, and test plans

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Module-level initialization: ensure the script-scoped relationships tracker and
# workItemTypesCache always exist. Use Set-Variable to avoid StrictMode TerminatingErrors
# when modules/functions reference these variables before they've been assigned.
try {
    Set-Variable -Name 'script:relationshipsCreated' -Scope Script -Value (@{}) -Force -ErrorAction Stop
}
catch {
    # Fallback: if Set-Variable fails for some reason, ensure the plain assignment exists
    if (-not (Test-Path variable:script:relationshipsCreated)) { $script:relationshipsCreated = @{} }
}

try {
    Set-Variable -Name 'script:workItemTypesCache' -Scope Script -Value (@{}) -Force -ErrorAction Stop
}
catch {
    if (-not (Test-Path variable:script:workItemTypesCache)) { $script:workItemTypesCache = @{} }
}

# Helper: ensure the module-level workItemTypesCache exists and optionally prepopulate for a project
function Ensure-WorkItemTypesCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Project,
        [Parameter(Mandatory=$false)][object[]]$Types
    )

    # Ensure the module-level cache exists
    if (-not (Test-Path variable:script:workItemTypesCache)) { $script:workItemTypesCache = @{} }

    if ($Project) {
        try {
            if ($Types) {
                # Normalize incoming types to simple string array and log for diagnostics
                try {
                    $normalized = @()
                    foreach ($t in $Types) { if ($t -ne $null) { $normalized += [string]$t } }
                    if ($normalized.Count -eq 0) { $normalized = $Types }
                }
                catch {
                    $normalized = $Types
                }

                Write-LogLevelVerbose "[Ensure-WorkItemTypesCache] Seeding cache for project '$Project' with types: $($normalized -join ', ')"
                $script:workItemTypesCache[$Project] = $normalized
            }
            elseif (-not ($script:workItemTypesCache -and $script:workItemTypesCache.ContainsKey($Project))) {
                try {
                    $types = @(Get-AdoWorkItemTypes -Project $Project)
                }
                catch {
                    $types = @()
                }

                if (-not $types -or $types.Count -eq 0) {
                    # Seed with static Agile defaults when detection fails
                    $types = Get-StaticAgileWorkItemTypes
                }

                Write-LogLevelVerbose "[Ensure-WorkItemTypesCache] Detected types for project '$Project': $($types -join ', ')"
                $script:workItemTypesCache[$Project] = $types
            }
        }
        catch {
            # On unexpected errors, seed with Agile defaults to allow operations to continue
            Write-LogLevelVerbose "[Ensure-WorkItemTypesCache] Error while ensuring cache for '$Project': $_"
            $script:workItemTypesCache[$Project] = Get-StaticAgileWorkItemTypes
        }
    }
}

# Return the cached work item types for a project (for diagnostics)
function Get-WorkItemTypesCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$Project
    )
    try {
        if ($Project) {
            $val = $script:workItemTypesCache[$Project]
            Write-LogLevelVerbose "[Get-WorkItemTypesCache] Returning cached types for '$Project': $($val -join ', ')"
            return $val
        }
        Write-LogLevelVerbose "[Get-WorkItemTypesCache] Returning full cache keys: $($script:workItemTypesCache.Keys -join ', ')"
        return $script:workItemTypesCache
    }
    catch {
        return $null
    }
}
# Static Agile WITs for seeding the cache when detection fails (safe, small set)
function Get-StaticAgileWorkItemTypes {
    # Return simple name list (strings) - other code expects string arrays
    return @('User Story','Task','Bug','Epic','Feature','Test Case')
}

#>
function New-AdoQueryFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    # Parse the path to get folder hierarchy (e.g., "Shared Queries/Development" -> ["Shared Queries", "Development"])
    $pathParts = $Path -split '/'
    $currentPath = ""
    
    foreach ($part in $pathParts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        
        if ($currentPath) {
            $currentPath += "/$part"
        }
        else {
            $currentPath = $part
        }
        
        # Check if folder exists
        $encoded = [uri]::EscapeDataString($currentPath)
        $projEnc = [uri]::EscapeDataString($Project)
        
        try {
            $existing = Invoke-AdoRest GET "/$projEnc/_apis/wit/queries/$encoded" -ReturnNullOnNotFound
            if ($existing -and $existing.isFolder) {
                Write-LogLevelVerbose "[WorkItems] Query folder '$currentPath' already exists"
                continue
            }
        }
        catch {
            # Folder doesn't exist, create it
            Write-LogLevelVerbose "[WorkItems] Creating query folder: $currentPath"
        }
        
        # Determine parent folder
        $parentPath = ""
        if ($currentPath.Contains('/')) {
            $parentPath = $currentPath.Substring(0, $currentPath.LastIndexOf('/'))
        }
        
        # Create the folder
        try {
            $parentEnc = if ($parentPath) { [uri]::EscapeDataString($parentPath) } else { "My%20Queries" }
            
            $folderBody = @{
                name     = $part
                isFolder = $true
            }
            
            Invoke-AdoRest POST "/$projEnc/_apis/wit/queries/$parentEnc" -Body $folderBody | Out-Null
            Write-LogLevelVerbose "[WorkItems] Successfully created query folder: $currentPath"
        }
        catch {
            if ($_ -notmatch 'already exists|409') {
                Write-Warning "[WorkItems] Failed to create query folder '$currentPath': $_"
            }
        }
    }
}

# Map/resolve incoming Excel WorkItemType values to project-available ADO work item types.
function Resolve-AdoWorkItemType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Project,
        [Parameter(Mandatory=$true)][string]$ExcelType
    )

    if (-not $ExcelType) { return $null }
    $inputNorm = $ExcelType.Trim()
         $available = @('User Story','Task','Bug','Epic','Feature','Test Case') 

    # Cache work item types per project to avoid repeated API calls
    # Access the module-level script-scoped cache defensively to avoid StrictMode
    # TerminatingErrors when the variable hasn't been created in some run contexts.
    try {
        if (-not (Test-Path variable:script:workItemTypesCache)) {
            Set-Variable -Name 'script:workItemTypesCache' -Scope Script -Value @{} -Force -ErrorAction Stop
        }
    }
    catch {
        # Best-effort fallback
        if (-not (Test-Path variable:script:workItemTypesCache)) { $script:workItemTypesCache = @{} }
    }

    # Ensure the cache exists and retrieve the project's entry defensively
    # Ensure module cache exists and access it directly
    if (-not (Test-Path variable:script:workItemTypesCache)) { $script:workItemTypesCache = @{} }

    if (-not $script:workItemTypesCache.ContainsKey($Project)) {
        Write-LogLevelVerbose "[Resolve-AdoWorkItemType] Caching work item types for project: $Project"
        try {
            $script:workItemTypesCache[$Project] = @(Get-AdoWorkItemTypes -Project $Project)
        }
        catch {
            $script:workItemTypesCache[$Project] = @()
        }
    }

    try { $available = $script:workItemTypesCache[$Project] } catch { $available = @() }

    Write-LogLevelVerbose "[Resolve-AdoWorkItemType] Available types for project '$Project': $($available -join ', ')"

    # If detection failed (empty), fall back to process-template defaults to improve chances of mapping
    if (-not $available -or $available.Count -eq 0) {
        Write-LogLevelVerbose "[Resolve-AdoWorkItemType] No work item types detected, falling back to process template defaults"
        try {
            $proc = Get-AdoProjectProcessTemplate -ProjectId $Project
            switch ($proc) {
                'Agile'    { $available = @('User Story','Task','Bug','Epic','Feature','Test Case') }
                'Scrum'    { $available = @('Product Backlog Item','Task','Bug','Epic','Feature','Test Case','Impediment') }
                'CMMI'     { $available = @('Requirement','Task','Bug','Epic','Feature','Test Case','Issue','Risk','Review','Change Request') }
                'Basic'    { $available = @('Issue','Task','Epic') }
                default    { $available = @('User Story','Product Backlog Item','Task','Bug','Epic','Feature','Test Case','Issue','Requirement') }
            }
            Write-LogLevelVerbose "[Resolve-AdoWorkItemType] Fallback available types: $($available -join ', ')"
        }
        catch {
            Write-LogLevelVerbose "[Resolve-AdoWorkItemType] Fallback to defaults failed: $_"
            $available = @()
        }
    }

    $availableLower = @{}
    foreach ($t in $available) { $availableLower[$t.ToLower()] = $t }

    # Normalization map of common Excel synonyms -> canonical ADO names
    $synonyms = @{
        'story' = 'User Story'
        'user story' = 'User Story'
        'userstory' = 'User Story'
        'stories' = 'User Story'
        'epic' = 'Epic'
        'epics' = 'Epic'
        'feature' = 'Feature'
        'features' = 'Feature'
        'pbi' = 'Product Backlog Item'
        'product backlog item' = 'Product Backlog Item'
        'test case' = 'Test Case'
        'testcase' = 'Test Case'
        'tc' = 'Test Case'
        'test cases' = 'Test Case'
        'task' = 'Task'
        'tasks' = 'Task'
        'bug' = 'Bug'
        'bugs' = 'Bug'
        'issue' = 'Issue'
        'issues' = 'Issue'
        'requirement' = 'Requirement'
        'requirements' = 'Requirement'
        'story points' = 'User Story'
        'req' = 'Requirement'
        'backlog' = 'Product Backlog Item'
    }

    $lower = $inputNorm.ToLower()

    # 1) Exact match against available types
    if ($availableLower.ContainsKey($lower)) { return $availableLower[$lower] }

    # 2) Try synonyms map
    if ($synonyms.ContainsKey($lower)) {
        $cand = $synonyms[$lower]
        if ($available -contains $cand) { return $cand }
    }

    # 3) Fuzzy containment: find any available type that contains the input or vice-versa
    foreach ($t in $available) {
        if ($t.ToLower().Contains($lower) -or $lower.Contains($t.ToLower())) { return $t }
    }

    # 4) Last-resort heuristics: map short forms
    foreach ($k in $synonyms.Keys) {
        if ($lower -like "*$k*") {
            $cand = $synonyms[$k]
            if ($available -contains $cand) { return $cand }
        }
    }

    # Unknown type
    Write-Warning "Unknown or unsupported WorkItemType from Excel: '$ExcelType' - will be skipped. Available types: $($available -join ', ')"
    return $null
}

function Upsert-AdoQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Project,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Wiql
    )

    # Path expected as 'Shared Queries/Folder Name/Query Name' or 'Shared Queries/Query Name'
    $projEnc = [uri]::EscapeDataString($Project)

    $name = $Path
    $parent = "Shared Queries"
    if ($Path.Contains('/')) {
        $idx = $Path.LastIndexOf('/')
        $parent = $Path.Substring(0, $idx)
        $name = $Path.Substring($idx + 1)
    }

    # Try to retrieve existing query by full path
    $encodedFull = [uri]::EscapeDataString($Path)
    try {
    $existing = Invoke-AdoRest GET "/$projEnc/_apis/wit/queries/$encodedFull" -ReturnNullOnNotFound
    }
    catch {
        $existing = $null
    }

    if ($existing -and $existing.id) {
        # Update existing query if WIQL differs
        try {
            $currentWiql = if ($existing.PSObject.Properties['wiql']) { $existing.wiql } else { $null }
            if ($currentWiql -and ($currentWiql -ne $Wiql)) {
                Write-LogLevelVerbose "[Upsert-AdoQuery] Updating query '$Path' wiql"
                $patchBody = @{ wiql = $Wiql }
                Invoke-AdoRest PATCH "/$projEnc/_apis/wit/queries/$($existing.id)" -Body $patchBody | Out-Null
            }
            else {
                Write-LogLevelVerbose "[Upsert-AdoQuery] Query '$Path' already exists and wiql unchanged"
            }
            return $existing
        }
        catch {
            Write-Warning "[Upsert-AdoQuery] Failed to update query '$Path': $_"
            return $null
        }
    }

    # Create parent folder if missing
    try {
        New-AdoQueryFolder -Project $Project -Path $parent
    }
    catch {
        Write-LogLevelVerbose "[Upsert-AdoQuery] Could not ensure parent folder '$parent': $_"
    }

    # Create new query under parent
    try {
        $parentEnc = [uri]::EscapeDataString($parent)
        $body = @{ name = $name; wiql = $Wiql }
        $created = Invoke-AdoRest POST "/$projEnc/_apis/wit/queries/$parentEnc" -Body $body
        Write-LogLevelVerbose "[Upsert-AdoQuery] Created query '$Path'"
        return $created
    }
    catch {
        Write-Warning "[Upsert-AdoQuery] Failed to create query '$Path': $_"
        return $null
    }
}

#>
function Initialize-AdoTeamTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$Team
    )
 $available = @('User Story','Task','Bug','Epic','Feature','Test Case') 

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
            # Unknown - try detection, fallback to common types (excluding Issue for Agile-like projects)
            Write-Host "[INFO] Unknown process template, attempting work item type detection..." -ForegroundColor Yellow
            
            # Cache work item types to avoid repeated API calls when multiple team packs are initialized
            try {
                if (-not (Test-Path variable:script:workItemTypesCache)) {
                    Set-Variable -Name 'script:workItemTypesCache' -Scope Script -Value @{} -Force -ErrorAction Stop
                }
            }
            catch {
                if (-not (Test-Path variable:script:workItemTypesCache)) { $script:workItemTypesCache = @{} }
            }

            try {
                if (-not ($script:workItemTypesCache -and $script:workItemTypesCache.ContainsKey($Project))) {
                    $script:workItemTypesCache[$Project] = Get-AdoWorkItemTypes -Project $Project
                }
            }
            catch { $script:workItemTypesCache[$Project] = @() }

            try { $detected = $script:workItemTypesCache[$Project] } catch { $detected = @() }
            
            if ($detected -and $detected.Count -gt 0) {
                $detected
            } else {
                # Last resort: include common types but exclude Issue (not part of Agile)
                @('User Story', 'Product Backlog Item', 'Task', 'Bug', 'Epic', 'Feature', 'Test Case', 'Requirement')
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
    
    # Define comprehensive work item templates for all Agile types - load from JSON
    $templateJsonPath = Join-Path $PSScriptRoot "..\templates\WorkItemTemplates.json"
    if (-not (Test-Path $templateJsonPath)) {
        Write-Error "[Initialize-AdoTeamTemplates] Template JSON file not found: $templateJsonPath"
        return
    }
    $templateDefinitions = Get-Content -Path $templateJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable

    # Create templates for all available work item types
    $createdCount = 0
    $skippedCount = 0
    
    Write-Host "[INFO] Creating work item templates for $processTemplate process..." -ForegroundColor Cyan
    Write-LogLevelVerbose "[Initialize-AdoTeamTemplates] Available types in project: $($availableTypes -join ', ')"
    Write-LogLevelVerbose "[Initialize-AdoTeamTemplates] Template API endpoint: $base"
    
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
                    
                    Write-LogLevelVerbose "[Initialize-AdoTeamTemplates] Creating template: $($template.name)"
                    Write-LogLevelVerbose "[Initialize-AdoTeamTemplates] Template body: $($templateBody | ConvertTo-Json -Depth 5)"
                    
                    Invoke-AdoRest POST $base -Body $templateBody | Out-Null
                    Write-Host "[SUCCESS] Created $workItemType template: $($template.name)" -ForegroundColor Green
                    $createdCount++
                }
                catch {
                    Write-Warning "Failed to create $workItemType template: $_"
                    Write-LogLevelVerbose "[AzureDevOps] Error details: $($_.Exception.Message)"
                    if ($_.Exception.Response) {
                        Write-LogLevelVerbose "[AzureDevOps] HTTP Status: $($_.Exception.Response.StatusCode)"
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
    Write-Host "⚠️  [ACTION REQUIRED] Templates must be set as default manually:" -ForegroundColor Yellow
    Write-Host "    (Azure DevOps API does not support setting templates as default)" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "[NEXT STEPS] To make templates auto-populate when creating work items:" -ForegroundColor Cyan
    try {
        $baseUrl = Get-AdoBaseUrl
        Write-Host "  1. Navigate to: $baseUrl/$([uri]::EscapeDataString($Project))/_settings/work-items" -ForegroundColor White
    }
    catch {
        Write-Host "  1. Navigate to your Azure DevOps project settings → Work items" -ForegroundColor White
    }
    Write-Host "  2. Select the work item type (e.g., 'User Story', 'Task', 'Bug')" -ForegroundColor White
    Write-Host "  3. Find the template in the list" -ForegroundColor White
    Write-Host "  4. Click the ⋮ (actions menu) → 'Set as default'" -ForegroundColor White
    Write-Host "  5. Repeat for each work item type" -ForegroundColor White
    Write-Host ""
    Write-Host "[NOTE] Setting templates as default is not available via API - manual configuration required" -ForegroundColor Yellow
    Write-Host "[TIP] Set defaults for most-used types first: User Story, Task, Bug" -ForegroundColor Gray
}

#>
function New-AdoSharedQueries {
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
    
    # Create team-specific folder under Shared Queries to avoid permission issues
    $teamFolderPath = "Shared Queries/$Team"
    $teamFolderId = $null
    
    try {
        # Check if team folder already exists
    $sharedQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=2" -ReturnNullOnNotFound
        
        if ($sharedQueries -and $sharedQueries.PSObject.Properties['children'] -and $sharedQueries.children) {
            $teamFolder = $sharedQueries.children | Where-Object { $_.name -eq $Team -and $_.isFolder -eq $true }
            if ($teamFolder) {
                $teamFolderId = $teamFolder.id
                Write-Host "[INFO] Team folder '$Team' already exists" -ForegroundColor Gray
            }
        }
        
        # Create team folder if it doesn't exist
        if (-not $teamFolderId) {
            Write-Host "[INFO] Creating team folder '$Team' under Shared Queries..." -ForegroundColor Cyan
            $folderBody = @{
                name = $Team
                isFolder = $true
            }
            $teamFolder = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" -Body $folderBody
            $teamFolderId = $teamFolder.id
            Write-Host "[SUCCESS] Created team folder '$Team'" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to create/access team folder: $_"
        # Fall back to Shared Queries root (may fail due to permissions)
        $teamFolderId = $null
    }
    
    # Check existing queries in team folder
    $existingQueries = @{}
    try {
        if ($teamFolderId) {
            $folderQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$teamFolderId?`$depth=1" -ReturnNullOnNotFound
            # Handle both response structures: direct children or wrapped in value
            $children = $null
            if ($folderQueries -and $folderQueries.PSObject.Properties['children'] -and $folderQueries.children) {
                $children = $folderQueries.children
            }
            elseif ($folderQueries -and $folderQueries.PSObject.Properties['value'] -and $folderQueries.value.PSObject.Properties['children'] -and $folderQueries.value.children) {
                $children = $folderQueries.value.children
            }

            if ($children) {
                $children | ForEach-Object { $existingQueries[$_.name] = $_ }
            }
        }
    }
    catch {
        Write-LogLevelVerbose "[New-AdoSharedQueries] Could not retrieve existing queries: $_"
    }
    
    $createdCount = 0
    $skippedCount = 0
    $createdQueries = @()
    
    # Determine base endpoint for query creation
    $baseEndpoint = if ($teamFolderId) {
        "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$teamFolderId"
    } else {
        "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries"
    }
    
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
            
            Write-LogLevelVerbose "[New-AdoSharedQueries] Creating query: $($queryDef.name)"
            $query = Invoke-AdoRest POST $baseEndpoint -Body $queryBody
            Write-Host "[SUCCESS] Created query: $($queryDef.name)" -ForegroundColor Green
            $createdQueries += $query
            $createdCount++
        }
        catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -match "TF401256.*Write permissions.*query" -or $errorMessage -match "403.*Forbidden") {
                Write-Warning "Query '$($queryDef.name)' creation failed due to insufficient permissions. Contributors cannot create queries in the root Shared Queries folder. Consider creating team-specific query folders or granting appropriate permissions."
                $skippedCount++
            }
            else {
                Write-Warning "Failed to create query '$($queryDef.name)': $errorMessage"
                $skippedCount++
            }
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Shared queries summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount queries" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount queries (already exist or permission denied)" -ForegroundColor Yellow
    }
    $location = if ($teamFolderId) { "Shared Queries/$Team folder" } else { "Shared Queries folder" }
    Write-Host "  📂 Location: $location" -ForegroundColor Gray
    
    return $createdQueries
}

#>
function New-AdoTestPlan {
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
                Write-LogLevelVerbose "[New-AdoTestPlan] Using current iteration: $Iteration"
            } else {
                # Fallback to project root iteration
                $Iteration = $Project
                Write-LogLevelVerbose "[New-AdoTestPlan] No current iteration found, using project root: $Iteration"
            }
        }
        catch {
            $Iteration = $Project
            Write-LogLevelVerbose "[New-AdoTestPlan] Error getting current iteration, using project root: $Iteration"
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
        Write-LogLevelVerbose "[New-AdoTestPlan] Could not retrieve existing test plans: $_"
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
            
            Write-LogLevelVerbose "[New-AdoTestPlan] Creating test plan with body: $($testPlanBody | ConvertTo-Json -Depth 5)"
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
        Write-LogLevelVerbose "[New-AdoTestPlan] Could not retrieve existing test suites: $_"
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
            
            Write-LogLevelVerbose "[New-AdoTestPlan] Creating suite: $($suiteDef.name)"
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

#>
function New-AdoQAQueries {
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
    $sharedQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=2" -ReturnNullOnNotFound
        
        if ($sharedQueries -and $sharedQueries.PSObject.Properties['children'] -and $sharedQueries.children) {
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
            $folderQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$qaFolderId?`$depth=1" -ReturnNullOnNotFound
            # Handle both response structures: direct children or wrapped in value
            $children = $null
            if ($folderQueries -and $folderQueries.PSObject.Properties['children'] -and $folderQueries.children) {
                $children = $folderQueries.children
            }
            elseif ($folderQueries -and $folderQueries.PSObject.Properties['value'] -and $folderQueries.value.PSObject.Properties['children']) {
                $children = $folderQueries.value.children
            }

            if ($children) {
                $children | ForEach-Object { $existingQueries[$_.name] = $_ }
            }
        }
    }
    catch {
        Write-LogLevelVerbose "[New-AdoQAQueries] Could not retrieve existing queries: $_"
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

#>
function New-AdoTestConfigurations {
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
            Write-LogLevelVerbose "[New-AdoTestConfigurations] Could not retrieve existing variables: $_"
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
                        Write-LogLevelVerbose "[New-AdoTestConfigurations] Failed to update variable '$($varDef.Name)': $_"
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
            Write-LogLevelVerbose "[New-AdoTestConfigurations] Could not retrieve existing configurations: $_"
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
                    # Normalize allowed values to their string representation + IDs
                    $allowedEntries = @()
                    if ($variable.PSObject.Properties['values']) {
                        foreach ($valueEntry in $variable.values) {
                            if ($valueEntry -is [string]) {
                                $allowedEntries += [pscustomobject]@{ name = $valueEntry; id = $null }
                            }
                            elseif ($valueEntry.PSObject.Properties['value']) {
                                $allowedEntries += [pscustomobject]@{
                                    name = $valueEntry.value
                                    id   = if ($valueEntry.PSObject.Properties['id']) { $valueEntry.id } else { $null }
                                }
                            }
                        }
                    }

                    $allowedNames = $allowedEntries | ForEach-Object { $_.name }
                    if ($allowedNames -and ($varValue -notin $allowedNames)) {
                        Write-LogLevelVerbose "[New-AdoTestConfigurations] Skipping value '$varValue' for variable '$varName' (not in allowed values)"
                        continue
                    }

                    $matchingEntry = $allowedEntries | Where-Object { $_.name -eq $varValue } | Select-Object -First 1

                    $configEntry = @{
                        name = $varName
                        value = $varValue
                    }

                    $configValues += $configEntry
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
        Write-LogLevelVerbose "[New-AdoTestConfigurations] Error details: $($_.Exception.Message)"
        return @{
            variables = @()
            configurations = @()
        }
    }
}

#>
function Measure-Adocommontags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId,
        
        [string]$CollectionUrl,
        [string]$AdoPat,
        [string]$AdoApiVersion
    )
    
    Write-Host "[INFO] Creating tag guidelines wiki page..." -ForegroundColor Cyan
    
    # Load tag guidelines template with fallback
    $tagGuidelinesContent = $null
    $templatePath = Join-Path $PSScriptRoot "..\templates\TagGuidelines.md"
    
    if (Test-Path $templatePath) {
        try {
            $tagGuidelinesTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8
            $tagGuidelinesContent = $tagGuidelinesTemplate -replace '{{CURRENT_DATE}}', (Get-Date -Format 'yyyy-MM-dd')
            Write-LogLevelVerbose "[Measure-Adocommontags] Loaded template from: $templatePath"
        }
        catch {
            Write-Warning "Failed to load template from '$templatePath': $_"
        }
    }
    
    # Fallback to embedded template if file not found or failed to load
    if (-not $tagGuidelinesContent) {
        Write-LogLevelVerbose "[Measure-Adocommontags] Using embedded fallback template"
        $currentDate = Get-Date -Format 'yyyy-MM-dd'
        $tagGuidelinesContent = @"
# Tag Guidelines

Generated: $currentDate

## Standard Tags

Use these tags to categorize work items effectively:

### Status Tags
- **blocked**: Work is blocked by external dependencies
- **urgent**: Requires immediate attention
- **breaking-change**: Changes that break backward compatibility
- **needs-review**: Ready for code/design review
- **needs-testing**: Requires QA validation

### Technical Tags
- **frontend**: UI/UX changes
- **backend**: Server-side logic
- **database**: Database schema or queries
- **api**: REST/GraphQL API changes
- **infrastructure**: DevOps, CI/CD, deployment

### Quality Tags
- **technical-debt**: Code that needs refactoring
- **performance**: Performance optimization needed
- **security**: Security-related changes

## Best Practices

1. **Consistency**: Use standard tags across all work items
2. **Clarity**: Choose tags that clearly describe the work
3. **Review**: Update tags during sprint planning and retrospectives
4. **Search**: Leverage tags for filtering and reporting

## Usage Examples

- User Story with tags: 'frontend', 'needs-review'
- Bug with tags: 'backend', 'urgent', 'security'
- Task with tags: 'infrastructure', 'technical-debt'
"@
    }

    try {
        # Attempt to create/update the page directly via Set-AdoWikiPage which already performs PUT→PATCH.
        # This avoids an initial GET that can produce expected 404 TerminatingErrors in transcripts.
        Write-LogLevelVerbose "[Measure-Adocommontags] Upserting Tag Guidelines page via Set-AdoWikiPage"
        $page = Set-AdoWikiPage $Project $WikiId "/Tag-Guidelines" $tagGuidelinesContent
        Write-Host "[SUCCESS] Tag Guidelines wiki page created or updated" -ForegroundColor Green
        Write-Host ""
        Write-Host "[INFO] Common tags documented:" -ForegroundColor Cyan
        Write-Host "  🚫 Status: blocked, urgent, breaking-change, needs-review, needs-testing" -ForegroundColor Gray
        Write-Host "  💻 Technical: frontend, backend, database, api, infrastructure" -ForegroundColor Gray
        Write-Host "  🏗️ Quality: technical-debt, performance, security" -ForegroundColor Gray
        Write-Host "  📂 Location: Project Wiki → Tag-Guidelines" -ForegroundColor Gray
        return $page
    }
    catch {
        Write-Warning "Failed to upsert Tag Guidelines page: $_"
        return $null
    }
}

#>
function Measure-Adobusinessqueries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Project
    )

    Write-Host "[INFO] Creating business shared queries..." -ForegroundColor Cyan

    $queries = @(
        @{ name = 'Current Sprint Commitment'; wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.IterationPath] UNDER @CurrentIteration('$Project\\$Project Team') ORDER BY [System.WorkItemType] ASC, [System.State] ASC, [System.ChangedDate] DESC" },
        @{ name = 'Unestimated Stories'; wiql = "SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [Microsoft.VSTS.Scheduling.StoryPoints] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] IN ('User Story','Product Backlog Item','Requirement','Issue') AND ([Microsoft.VSTS.Scheduling.StoryPoints] = '' OR [Microsoft.VSTS.Scheduling.StoryPoints] = 0) AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [System.CreatedDate] DESC" },
        @{ name = 'Epics by Target Date'; wiql = "SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Scheduling.TargetDate] FROM WorkItems WHERE [System.TeamProject] = '$Project' AND [System.WorkItemType] = 'Epic' AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' ORDER BY [Microsoft.VSTS.Scheduling.TargetDate] ASC, [System.CreatedDate] DESC" }
    )

    # Read existing queries under Shared Queries
    $existing = @{}
    try {
    $resp = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=1" -ReturnNullOnNotFound
    if ($resp -and $resp.PSObject.Properties['children'] -and $resp.children) { $resp.children | ForEach-Object { $existing[$_.name] = $_ } }
    }
    catch {
        Write-LogLevelVerbose "[Measure-Adobusinessqueries] Could not retrieve existing queries: $_"
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

#>
function Search-Adodevqueries {
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
        Write-LogLevelVerbose "[Search-Adodevqueries] Created Development queries folder"
    }
    catch {
        # Folder might already exist
        Write-LogLevelVerbose "[Search-Adodevqueries] Development folder exists or creation skipped"
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
  AND [System.State] = 'Active'
ORDER BY [System.CreatedDate] ASC
"@
        },
        @{
            name = "Technical Debt"
            wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Scheduling.StoryPoints]
FROM WorkItems
WHERE [System.TeamProject] = '$Project'
  AND [System.WorkItemType] IN ('User Story', 'Task', 'Bug')
  AND [System.Tags] CONTAINS 'tech-debt'
  AND [System.State] <> 'Closed'
ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [Microsoft.VSTS.Scheduling.StoryPoints] DESC
"@
        },
        @{
            name = "Recently Completed"
            wiql = @"
SELECT [System.Id], [System.Title], [System.WorkItemType], [System.AssignedTo], [System.ChangedDate]
FROM WorkItems
WHERE [System.TeamProject] = '$Project'
  AND [System.WorkItemType] IN ('User Story', 'Task', 'Bug')
  AND [System.State] = 'Closed'
ORDER BY [System.ChangedDate] DESC
"@
        },
        @{
            name = "Code Review Feedback"
            wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.ChangedDate]
FROM WorkItems
WHERE [System.TeamProject] = '$Project'
  AND [System.WorkItemType] IN ('User Story', 'Task')
  AND [System.State] = 'Active'
ORDER BY [System.ChangedDate] DESC
"@
        }
    )
    
    # Create each query
    try {
        foreach ($q in $queries) {
            try {
                $queryPayload = @{
                    name  = $q.name
                    wiql  = $q.wiql
                }
                $encodedPath = [uri]::EscapeDataString("Shared Queries/Development/$($q.name)")
                try {
                    # Try to get existing query
                    $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$encodedPath" -ReturnNullOnNotFound
                    Write-Host "  ✓ Query exists: $($q.name)" -ForegroundColor Gray
                }
                catch {
                    # Create new query
                    $encodedFolder = [uri]::EscapeDataString("Shared Queries/Development")
                    try {
                        Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$encodedFolder" -Body $queryPayload | Out-Null
                        Write-Host "  ✅ Created query: $($q.name)" -ForegroundColor Gray
                    }
                    catch {
                        Write-Warning "Failed to create query '$($q.name)' (POST): $_"
                        # Temporary debug capture: write exception + context to logs/debug-failing-post-<guid>.json
                        try {
                            $logsDir = Join-Path (Get-Location) 'logs'
                            if (-not (Test-Path $logsDir)) { New-Item -Path $logsDir -ItemType Directory -Force | Out-Null }

                            $payload = [ordered]@{
                                timestamp = (Get-Date).ToString('o')
                                project   = $Project
                                queryName = $q.name
                                endpoint  = "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries"
                                exception = ($_ | Out-String).Trim()
                            }

                            $fname = Join-Path $logsDir ("debug-failing-post-" + [guid]::NewGuid().ToString() + ".json")
                            $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $fname -Encoding UTF8 -Force
                            Write-LogLevelVerbose "[Search-Adodevqueries] Wrote debug failure details to: $fname"
                        }
                        catch {
                            Write-LogLevelVerbose "[Search-Adodevqueries] Failed to write debug file: $_"
                        }

                        continue
                    }
                }
            }
            catch {
                Write-Warning "Failed to create query '$($q.name)': $_"
            }
        }
    }
    catch {
        Write-Warning "[Search-Adodevqueries] Unhandled error during query creation: $_"
    }
    
    Write-Host "[SUCCESS] Development queries created" -ForegroundColor Green
}

#>
function New-AdoSecurityQueries {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )

    Write-Host "[INFO] Setting up security queries..." -ForegroundColor Cyan

    # Security Bugs (Priority 0-1)
    $securityBugsQuery = @"
SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity], [System.AssignedTo], [System.CreatedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] = 'Bug'
  AND [System.Tags] CONTAINS 'security'
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
  AND [Microsoft.VSTS.Common.Priority] <= 1
ORDER BY [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity] DESC, [System.CreatedDate]
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
ORDER BY [Microsoft.VSTS.Common.Priority], [System.CreatedDate]
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
ORDER BY [Microsoft.VSTS.Scheduling.TargetDate], [Microsoft.VSTS.Common.Priority], [System.CreatedDate]
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
        New-AdoQueryFolder -Project $Project -Path $folderPath

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

#>
function Measure-Adomanagementqueries {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Project
    )

    Write-Host "[INFO] Setting up management queries..." -ForegroundColor Cyan

    # Program Status - All active work across the program
    $programStatusQuery = @"
SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [System.AssignedTo], [System.Tags], [Microsoft.VSTS.Scheduling.TargetDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] IN ('Epic', 'Feature', 'User Story', 'Bug', 'Task')
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [System.WorkItemType], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Scheduling.TargetDate]
"@

    # Sprint Progress - Current sprint work items
    $sprintProgressQuery = @"
SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Scheduling.StoryPoints], [System.IterationPath]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.IterationPath] = @currentIteration('[Project]\[Project] Team')
  AND [System.State] <> 'Removed'
ORDER BY [System.State], [System.WorkItemType], [Microsoft.VSTS.Common.Priority]
"@

    # Active Risks - Risk work items or items tagged with risk
    $activeRisksQuery = @"
SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity], [System.AssignedTo], [System.Tags], [System.CreatedDate], [Microsoft.VSTS.Scheduling.TargetDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND (
    [System.WorkItemType] = 'Risk' OR
    [System.WorkItemType] = 'Issue' OR
    [System.Tags] CONTAINS 'risk' OR
    [System.Tags] CONTAINS 'blocker' OR
    [System.Tags] CONTAINS 'critical'
  )
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity] DESC, [System.CreatedDate]
"@

    # Open Issues - All issues requiring attention
    $openIssuesQuery = @"
SELECT [System.Id], [System.Title], [System.State], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity], [System.AssignedTo], [System.Tags], [System.CreatedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] = 'Issue'
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity] DESC, [System.CreatedDate]
"@

    # Cross-Team Dependencies - Items with dependency tags
    $dependenciesQuery = @"
SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo], [System.Tags], [Microsoft.VSTS.Scheduling.TargetDate], [System.AreaPath]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND (
    [System.Tags] CONTAINS 'dependency' OR
    [System.Tags] CONTAINS 'blocked' OR
    [System.Tags] CONTAINS 'waiting' OR
    [System.Tags] CONTAINS 'external-dependency'
  )
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Scheduling.TargetDate], [System.CreatedDate]
"@

    # Milestone Tracker - Epics and Features by target date
    $milestoneTrackerQuery = @"
SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo], [Microsoft.VSTS.Scheduling.TargetDate], [System.Tags], [Microsoft.VSTS.Common.Priority]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] IN ('Epic', 'Feature')
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Scheduling.TargetDate], [System.WorkItemType], [Microsoft.VSTS.Common.Priority]
"@

    try {
        # Ensure "Management" folder exists
        $folderPath = "Shared Queries/Management"
        New-AdoQueryFolder -Project $Project -Path $folderPath

        # Create queries
        Upsert-AdoQuery -Project $Project -Path "$folderPath/Program Status" -Wiql $programStatusQuery
        Write-Host "  ✅ Program Status" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Sprint Progress" -Wiql $sprintProgressQuery
        Write-Host "  ✅ Sprint Progress" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Active Risks" -Wiql $activeRisksQuery
        Write-Host "  ✅ Active Risks" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Open Issues" -Wiql $openIssuesQuery
        Write-Host "  ✅ Open Issues" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Cross-Team Dependencies" -Wiql $dependenciesQuery
        Write-Host "  ✅ Cross-Team Dependencies" -ForegroundColor Gray

        Upsert-AdoQuery -Project $Project -Path "$folderPath/Milestone Tracker" -Wiql $milestoneTrackerQuery
        Write-Host "  ✅ Milestone Tracker" -ForegroundColor Gray

        Write-Host "[SUCCESS] All 6 management queries created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create some management queries: $_"
    }
}

<#
.SYNOPSIS
    Import hierarchical requirements from Excel into Azure DevOps.

.DESCRIPTION
    Imports work items (Epic -> Feature -> User Story -> Test Case) from an Excel spreadsheet
    into Azure DevOps Server. Preserves parent-child relationships and supports all standard
    Agile process fields.

.PARAMETER Project
    Azure DevOps project name.

.PARAMETER ExcelPath
    Path to Excel file (.xlsx) containing requirements.
    
    Expected columns:
    - LocalId: Unique identifier in Excel (for parent linking)
    - WorkItemType: Epic, Feature, User Story, Test Case
    - Title: Work item title (required)
    - ParentLocalId: LocalId of parent work item (for hierarchy)
    - IterationPath, State, Description, Priority (AreaPath is ignored)
    - StoryPoints, BusinessValue, ValueArea, Risk
    - StartDate, FinishDate, TargetDate, DueDate
    - OriginalEstimate, RemainingWork, CompletedWork
    - TestSteps: For Test Cases (format: "step1|expected1;;step2|expected2")
    - Tags: Semicolon-separated tags

.PARAMETER WorksheetName
    Name of the worksheet in Excel file. Default: "Requirements"

.PARAMETER ApiVersion
    Azure DevOps REST API version. Default: "7.0"
    - Use "7.0" or "7.1" for Azure DevOps Server 2022+
    - Use "6.0" for Azure DevOps Server 2020

.EXAMPLE
    Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\requirements.xlsx"

.EXAMPLE
    Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\reqs.xlsx" -WorksheetName "Sprint1" -ApiVersion "6.0"

.NOTES
    Requires ImportExcel module: Install-Module ImportExcel
    Work items are created in hierarchical order (Epic -> Feature -> User Story -> Test Case)
#>
function Convert-ExcelLocalId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalId
    )

    # Trim whitespace and handle empty/null values
    $localId = $LocalId.Trim()
    if ([string]::IsNullOrEmpty($localId)) {
        return $null
    }

    # Extract prefix and number part
    if ($localId -match '^([A-Za-z]+)(\d+)$') {
        $prefix = $matches[1].ToUpper()
        $number = [int]$matches[2]

        switch ($prefix) {
            'E' {
                # Remove prefix, keep number as-is
                return $number
            }
            'F' {
                # Multiply by 10
                return $number * 10
            }
            'US' {
                # Multiply by 100
                return $number * 100
            }
            'TC' {
                # Multiply by 1000
                return $number * 1000
            }
            default {
                # Unknown prefix, return original value as integer if possible
                Write-Warning "Unknown LocalId prefix '$prefix' in '$localId', treating as plain number"
                if ($localId -match '^\d+$') {
                    return [int]$localId
                }
                else {
                    return $localId
                }
            }
        }
    }
    else {
        # No prefix found, treat as plain number if possible
        if ($localId -match '^\d+$') {
            return [int]$localId
        }
        else {
            Write-Warning "LocalId '$localId' does not match expected format (prefix + number), keeping as string"
            return $localId
        }
    }
}

<#
.SYNOPSIS
    Import work items from Excel file into Azure DevOps project.
#>
function Import-AdoWorkItemsFromExcel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [ValidateScript({
            if ($_ -notmatch '\.(xlsx|xls)$') {
                throw "File must be Excel format (.xlsx or .xls): $_"
            }
            $true
        })]
        [string]$ExcelPath,
        [string]$WorksheetName = "Requirements",
        [string]$ApiVersion = $null,
        # Optional explicit collection URL - caller should prefer Initialize-CoreRest, but this keeps backwards compatibility
        [string]$CollectionUrl,
        [string]$TeamName = $null
    )

    # Validate Excel file exists early to provide clear error message for callers/tests
    if (-not (Test-Path $ExcelPath)) {
        throw "Excel file not found: $ExcelPath"
    }

    # Ensure we have a CollectionUrl for parent/child relationships
    $effectiveCollectionUrl = $null
    if ($PSBoundParameters.ContainsKey('CollectionUrl') -and $CollectionUrl) {
        # Caller provided explicit collection URL for this import
        $effectiveCollectionUrl = $CollectionUrl
        $script:CollectionUrl = $CollectionUrl  # Also set script variable for compatibility
    }
    elseif ($script:CollectionUrl) {
        # Use existing script variable
        $effectiveCollectionUrl = $script:CollectionUrl
    }
    else {
        try {
            # Try to recover from core rest config if module initialized
            $cfg = Ensure-CoreRestInitialized
            if ($cfg -and $cfg.CollectionUrl) {
                $effectiveCollectionUrl = $cfg.CollectionUrl
                $script:CollectionUrl = $cfg.CollectionUrl  # Set script variable too
            }
            else {
                throw "CollectionUrl is not configured. Call Initialize-CoreRest or pass -CollectionUrl to Import-AdoWorkItemsFromExcel."
            }
        }
        catch {
            throw "CollectionUrl is not configured. Call Initialize-CoreRest or pass -CollectionUrl to Import-AdoWorkItemsFromExcel. Error: $_"
        }
    }

    # Diagnostic: report effective collection URL for easier troubleshooting
    Write-Verbose "[Import-AdoWorkItemsFromExcel] Effective CollectionUrl: $effectiveCollectionUrl"
    Write-Host "[INFO] Using CollectionUrl: $effectiveCollectionUrl" -ForegroundColor Gray

    Write-Host "[INFO] Importing work items from Excel: $ExcelPath" -ForegroundColor Cyan

    # Import Excel data. Do not proactively Import-Module here so that tests can mock Import-Excel freely.
    # Small wrapper to call Import-Excel via an indirection so Pester can mock Import-Excel reliably
    function Invoke-ImportExcel {
        param(
            [Parameter(Mandatory=$true)][string]$Path,
            [string]$WorksheetName
        )
        & Import-Excel -Path $Path -WorksheetName $WorksheetName -ErrorAction Stop
    }

    try {
        Write-LogLevelVerbose "Reading Excel file: $ExcelPath"
        $rows = Invoke-ImportExcel -Path $ExcelPath -WorksheetName $WorksheetName

        # Normalize to array to handle single-row returns from Import-Excel
        $rows = @($rows)

        if (-not $rows -or (@($rows).Count -eq 0)) {
            Write-Warning "No data found in worksheet '$WorksheetName'"
            return
        }

        Write-Host "[INFO] Found $(@($rows).Count) rows in Excel" -ForegroundColor Cyan
    }
    catch {
        Write-Host "[ERROR] Failed to read Excel file: $_" -ForegroundColor Red
        throw
    }

    # Clean Excel data to remove empty column names (resilient to blank columns in Excel)
    $cleanedRows = @()
    foreach ($row in $rows) {
        $clean = @{}
        foreach ($prop in $row.PSObject.Properties) {
            if ([string]::IsNullOrWhiteSpace($prop.Name)) { continue }
            $clean[$prop.Name] = $prop.Value
        }
        $cleanedRows += [pscustomobject]$clean
    }
    $rows = $cleanedRows

    # Parse LocalId and ParentLocalId prefixes according to mapping rules
    foreach ($row in $rows) {
        if ($row.PSObject.Properties['LocalId'] -and $row.LocalId) {
            $parsedLocalId = Convert-ExcelLocalId -LocalId $row.LocalId.ToString()
            $row.LocalId = $parsedLocalId
        }
        if ($row.PSObject.Properties['ParentLocalId'] -and $row.ParentLocalId) {
            $parsedParentLocalId = Convert-ExcelLocalId -LocalId $row.ParentLocalId.ToString()
            $row.ParentLocalId = $parsedParentLocalId
        }
    }
    
    # Resolve and normalize WorkItemType values from Excel to ADO project types.
    $resolvedRows = @()
    $skippedRows = @()
    $importErrors = @()

    # Build a default hierarchy order (will be filtered to resolved types below)
    $hierarchyOrder = @{
        "Epic"       = 1
        "Feature"    = 2
        "User Story" = 3
        "Product Backlog Item" = 3
        "Test Case"  = 4
        "Task"       = 5
        "Bug"        = 6
        "Issue"      = 7
        "Requirement"= 3
    }

    foreach ($r in $rows) {
        $excelType = if ($r.WorkItemType) { $r.WorkItemType.ToString() } else { $null }
        $resolved = Resolve-AdoWorkItemType -Project $Project -ExcelType $excelType
        if ($resolved) {
            # attach resolved type to row for later use
            $r | Add-Member -NotePropertyName ResolvedWorkItemType -NotePropertyValue $resolved -Force
            $resolvedRows += $r
        }
        else {
            $msg = "[SKIP] Row skipped: Title='$($r.Title)', WorkItemType='$excelType' (could not resolve to ADO type)"
            Write-Warning $msg
            $skippedRows += $r
            $importErrors += $msg
        }
    }

    if (@($skippedRows).Count -gt 0) {
        $count = @($skippedRows).Count
        Write-Warning "Skipping $count row(s) due to unknown WorkItemType. See warnings above for details."
        $importErrors += "Skipping $count row(s) due to unknown WorkItemType"
    }

    # Sort by hierarchy to ensure parents are created before children
    # Sort by the configured hierarchy order. Unknown types go to the end.
    $orderedRows = $resolvedRows | Sort-Object {
        if ($null -ne $_.ResolvedWorkItemType -and $hierarchyOrder.ContainsKey($_.ResolvedWorkItemType)) {
            $hierarchyOrder[$_.ResolvedWorkItemType]
        }
        else { 999 }
    }

    Write-Host "[INFO] Processing $(@($orderedRows).Count) work items in hierarchical order" -ForegroundColor Cyan
    
    # Cache field definitions to avoid repeated API calls
    Write-LogLevelVerbose "Initializing field cache for validation..."
    $fieldCache = @{}  # Will store per work item type: $fieldCache["User Story"]["System.State"] = @("New", "Active", ...)
    
    # Helper function to get allowed values for a field on a specific work item type
    function Get-FieldAllowedValues {
        param(
            [string]$WorkItemType,
            [string]$FieldName
        )
        
        $cacheKey = "$WorkItemType|$FieldName"
        if ($fieldCache.ContainsKey($cacheKey)) {
            return $fieldCache[$cacheKey]
        }
        
        try {
            $witEncoded = [uri]::EscapeDataString($WorkItemType)
            $fieldEncoded = [uri]::EscapeDataString($FieldName)
            $fieldInfo = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/workitemtypes/$witEncoded/fields/$fieldEncoded?api-version=7.1"
            if ($fieldInfo -and $fieldInfo.allowedValues) {
                $fieldCache[$cacheKey] = $fieldInfo.allowedValues
                Write-LogLevelVerbose "Cached $($fieldInfo.allowedValues.Count) allowed values for $WorkItemType.$FieldName"
                return $fieldInfo.allowedValues
            } else {
                $fieldCache[$cacheKey] = @()
                Write-LogLevelVerbose "No allowed values found for $WorkItemType.$FieldName"
                return @()
            }
        }
        catch {
            $fieldCache[$cacheKey] = @()
            Write-LogLevelVerbose "Could not cache $WorkItemType.$FieldName`: $_"
            # Also log a warning for state field failures as they are more critical
            if ($FieldName -eq "System.State") {
                Write-LogLevelVerbose "State validation will be skipped for $WorkItemType - API unavailable"
            }
            return @()
        }
    }
    
    # Get current iteration for default assignment
    $currentIterationPath = $null
    try {
        Write-LogLevelVerbose "Getting current iteration for project: $Project"
        if ($TeamName) {
            $currentIterationResponse = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/$([uri]::EscapeDataString($TeamName))/_apis/work/teamsettings/iterations?`$timeframe=current"
            if ($currentIterationResponse -and $currentIterationResponse.value -and $currentIterationResponse.value.Count -gt 0) {
                $currentIterationPath = $currentIterationResponse.value[0].path
                Write-LogLevelVerbose "Current iteration path: $currentIterationPath"
            }
        } else {
            Write-Host "[INFO] No team name provided - skipping current iteration retrieval" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Could not retrieve current iteration, work items may fail if iteration path is required: $_"
    }
    
    # Get first area and first iteration for default assignment to all work items
    $firstAreaPath = $null
    $firstIterationPath = $null
    try {
        Write-LogLevelVerbose "Getting first area and iteration for project: $Project"
        
        # Get first area. Use ReturnNullOnNotFound to avoid noisy TerminatingError when no areas exist yet.
        $areasResponse = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas?`$depth=1" -ReturnNullOnNotFound
        if ($areasResponse -and $areasResponse.value -and $areasResponse.value.Count -gt 0) {
            $firstAreaPath = $areasResponse.value[0].name
            Write-LogLevelVerbose "First area path: $firstAreaPath"
        } elseif ($areasResponse -and $areasResponse.name) {
            $firstAreaPath = $areasResponse.name
            Write-LogLevelVerbose "First area path: $firstAreaPath"
        }
        
        # Get first iteration. Use ReturnNullOnNotFound to avoid noisy TerminatingError when no iterations exist yet.
        $iterationsResponse = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations?`$depth=1" -ReturnNullOnNotFound
        if ($iterationsResponse -and $iterationsResponse.value -and $iterationsResponse.value.Count -gt 0) {
            $firstIterationPath = $iterationsResponse.value[0].name
            Write-LogLevelVerbose "First iteration path: $firstIterationPath"
        } elseif ($iterationsResponse -and $iterationsResponse.name) {
            $firstIterationPath = $iterationsResponse.name
            Write-LogLevelVerbose "First iteration path: $firstIterationPath"
        }
    }
    catch {
        Write-LogLevelVerbose "Could not retrieve classification nodes: $_"
        # If classification nodes are missing, create default area and iteration with the project name so imports have sensible defaults
        try {
            Write-Host "[INFO] Creating default Area and Iteration: $Project" -ForegroundColor Cyan
            $projEnc = [uri]::EscapeDataString($Project)
            # Create root area node named after the project
            Invoke-AdoRest POST "/$projEnc/_apis/wit/classificationnodes/areas?api-version=7.1" -Body @{ name = $Project } -MaxAttempts 1 -DelaySeconds 0 | Out-Null
            # Create root iteration node named after the project
            Invoke-AdoRest POST "/$projEnc/_apis/wit/classificationnodes/iterations?api-version=7.1" -Body @{ name = $Project } -MaxAttempts 1 -DelaySeconds 0 | Out-Null
            
            # Ensure a default Sprint 1 exists under the project for child work items
            try {
                $sprintName = 'Sprint 1'
                # Attempt to create Sprint 1 - if it already exists, API may return 409 and we'll ignore
                Invoke-AdoRest POST "/$projEnc/_apis/wit/classificationnodes/iterations?api-version=7.1" -Body @{ name = $sprintName } -MaxAttempts 1 -DelaySeconds 0 | Out-Null
                $sprintIterationPath = "$Project\\$sprintName"
                Write-Host "[SUCCESS] Default iteration '$sprintIterationPath' ensured" -ForegroundColor Green
            }
            catch {
                # If creation failed, attempt to use fallback path (project\Sprint 1) regardless
                $sprintIterationPath = "$Project\\Sprint 1"
                Write-LogLevelVerbose "Could not create Sprint 1 iteration (may already exist): $_"
            }

            # Assign created values as defaults
            $firstAreaPath = $Project
            $firstIterationPath = $Project
            Write-Host "[SUCCESS] Default area and iteration '$Project' created and will be assigned to imported work items" -ForegroundColor Green
        }
        catch {
            Write-Warning "Could not create default area/iteration automatically: $_"
        }
    }
    
    # Map Excel LocalId to Azure DevOps work item ID (string keys to avoid JSON serialization issues)
    $localToAdoMap = @{}
    $successCount = 0
    $errorCount = 0
    # Initialize relationships tracking to avoid uninitialized variable errors in some code paths/tests
    if (-not (Test-Path variable:script:relationshipsCreated)) {
        $script:relationshipsCreated = @{}
    }
    
    foreach ($row in $orderedRows) {
        # Use resolved work item type (from Resolve-AdoWorkItemType)
        $wit = if ($row.PSObject.Properties['ResolvedWorkItemType']) { $row.ResolvedWorkItemType } else { $row.WorkItemType }
        
        # Skip bugs that are not linked to a parent
        if ($wit -eq "Bug" -and (-not $row.PSObject.Properties['ParentLocalId'] -or [string]::IsNullOrWhiteSpace($row.ParentLocalId))) {
            Write-Warning "Skipping Bug work item '$($row.Title)' - bugs must be linked to a parent work item"
            continue
        }
        
        # Guard against cycles and invalid parent references
        if ($row.PSObject.Properties['ParentLocalId'] -and $row.ParentLocalId) {
            if ($row.LocalId -eq $row.ParentLocalId) {
                Write-Warning "Skipping row with LocalId=$($row.LocalId) due to ParentLocalId=$($row.ParentLocalId) (self-reference cycle)"
                continue
            }
            if ([int]$row.ParentLocalId -ge [int]$row.LocalId) {
                Write-Warning "Skipping row with LocalId=$($row.LocalId) due to ParentLocalId=$($row.ParentLocalId) (forward reference or cycle)"
                continue
            }
        }
    try {
            # Build JSON Patch operations array (use PSCustomObject to ensure ConvertTo-Json serializes cleanly)
            $operations = @()
            
            # Required: Title
            if ([string]::IsNullOrWhiteSpace($row.Title)) {
                Write-Warning "Skipping row with missing title (LocalId: $($row.LocalId))"
                continue
            }
            
            $operations += [pscustomobject]@{
                op    = "add"
                path  = "/fields/System.Title"
                value = $row.Title.ToString()
            }
            
            # Assign first area and iteration to all work items
            if ($firstAreaPath) {
                $operations += [pscustomobject]@{
                    op    = "add"
                    path  = "/fields/System.AreaPath"
                    value = $firstAreaPath
                }
                Write-LogLevelVerbose "Assigned area path '$firstAreaPath' to work item '$($row.Title)'"
            }
            
            # Decide iteration assignment: child work items (User Story, Bug, Test Case, Task, PBI) should go to Project\Sprint 1
            $childTypes = @('User Story','Bug','Test Case','Task','Product Backlog Item')
            $childIterationPath = if ($sprintIterationPath) { $sprintIterationPath } else { "$Project\Sprint 1" }

            if ($firstIterationPath) {
                if ($childTypes -contains $wit) {
                    $operations += [pscustomobject]@{
                        op    = "add"
                        path  = "/fields/System.IterationPath"
                        value = $childIterationPath
                    }
                    Write-LogLevelVerbose "Assigned child iteration path '$childIterationPath' to work item '$($row.Title)' (type: $wit)"
                }
                else {
                    # For parent types (Epic, Feature, etc.) keep the project's first iteration/default
                    $operations += [pscustomobject]@{
                        op    = "add"
                        path  = "/fields/System.IterationPath"
                        value = $firstIterationPath
                    }
                    Write-LogLevelVerbose "Assigned iteration path '$firstIterationPath' to parent work item '$($row.Title)' (type: $wit)"
                }
            }
            
            # IterationPath is intentionally ignored during Excel import to use default project area
            # Skip all iteration path logic to prevent "Invalid tree name" errors
            # if ($row.PSObject.Properties['IterationPath']) {
            #     $iterationPath = $null
            #     if (-not [string]::IsNullOrWhiteSpace($row.IterationPath)) {
            #         # Use the Excel value if it's not empty
            #         $iterationPath = $row.IterationPath.ToString()
            #
            #         # Replace template placeholders with actual project values
            #         $iterationPath = $iterationPath -replace '\{\{ITERATION_ROOT\}\}', $Project
            #         $iterationPath = $iterationPath -replace '\{\{AREA_PATH_ROOT\}\}', $Project
            #     }
            #     elseif ($currentIterationPath) {
            #         # Use current iteration as default if Excel value is empty
            #         $iterationPath = $currentIterationPath
            #         Write-LogLevelVerbose "Using current iteration '$currentIterationPath' for work item '$($row.Title)'"
            #     }
            #
            #     # Only set iteration path if we have a valid path AND current iteration was successfully retrieved
            #     # This prevents failures when iterations haven't been created yet (e.g., bulk initialization)
            #     if ($iterationPath -and $currentIterationPath) {
            #         $operations += [pscustomobject]@{ op="add"; path="/fields/System.IterationPath"; value=$iterationPath }
            #     }
            #     elseif ($iterationPath -and -not $currentIterationPath) {
            #         Write-LogLevelVerbose "Skipping iteration path '$iterationPath' for work item '$($row.Title)' - no iterations available yet"
            #     }
            # }
            if ($row.PSObject.Properties['State'] -and $row.State) {
                $originalStateVal = $row.State.ToString()
                $stateVal = $originalStateVal

                # Special handling for "New" state - map to appropriate initial state based on work item type
                if ($originalStateVal -eq "New") {
                    # Test Cases use "Design" as their initial state, not "New"
                    if ($wit -eq "Test Case") {
                        $stateVal = "Design"
                        Write-LogLevelVerbose "Mapping 'New' state to 'Design' for Test Case work item type"
                    }
                    else {
                        # For other work item types, try to map to first allowed state if "New" not allowed
                        $allowedStates = Get-FieldAllowedValues -WorkItemType $wit -FieldName "System.State"
                        if (-not $allowedStates) { $allowedStates = @() }

                        # Check if "New" is directly allowed
                        $newIsAllowed = $false
                        if ($allowedStates -and $allowedStates.Count -gt 0) {
                            foreach ($av in $allowedStates) {
                                if ($av -ieq "New") {
                                    $newIsAllowed = $true
                                    break
                                }
                            }
                        }

                        if (-not $newIsAllowed -and $allowedStates.Count -gt 0) {
                            # "New" not allowed, use first state in the workflow
                            $stateVal = $allowedStates[0]
                            Write-LogLevelVerbose "Mapping 'New' state to first allowed state: '$stateVal' (allowed: $($allowedStates -join ', '))"
                        }
                    }
                }

                # Validate the final state value
                $allowed = Get-FieldAllowedValues -WorkItemType $wit -FieldName "System.State"
                if (-not $allowed) { $allowed = @() }

                $isAllowed = $false
                if ($allowed -and $allowed.Count -gt 0) {
                    foreach ($av in $allowed) { if ($av -ieq $stateVal) { $isAllowed = $true; break } }
                }

                # If API calls failed (empty allowed values), skip validation and allow the state
                # This prevents false warnings when Azure DevOps API is not available
                if ($allowed.Count -eq 0) {
                    Write-LogLevelVerbose "API unavailable for state validation - allowing state '$stateVal' without validation"
                    $isAllowed = $true
                }

                if ($isAllowed) {
                    $operations += [pscustomobject]@{ op="add"; path="/fields/System.State"; value=$stateVal }
                }
                else {
                    Write-Warning "Skipping setting State='$originalStateVal' (mapped to '$stateVal' but not in allowed values for $wit.System.State - will use default state)"
                }
            }
            if ($row.PSObject.Properties['Description'] -and $row.Description) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/System.Description"; value=$row.Description.ToString() }
            }
            if ($row.PSObject.Properties['Priority'] -and $row.Priority) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Common.Priority"; value=[int]$row.Priority }
            }
            
            # Work item type specific fields
            if ($row.PSObject.Properties['StoryPoints'] -and $row.StoryPoints -and $wit -eq "User Story") {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StoryPoints"; value=[double]$row.StoryPoints }
            }
            if ($row.PSObject.Properties['BusinessValue'] -and $row.BusinessValue) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Common.BusinessValue"; value=[int]$row.BusinessValue }
            }
            if ($row.PSObject.Properties['ValueArea'] -and $row.ValueArea) {
                # Map Excel ValueArea values to Azure DevOps Agile process values
                $valueAreaMapping = @{
                    "Enabler" = "Architectural"  # Map Enabler to Architectural (valid ADO value)
                }

                $originalValueAreaVal = $row.ValueArea.ToString()
                $valueAreaVal = if ($valueAreaMapping.ContainsKey($originalValueAreaVal)) {
                    $valueAreaMapping[$originalValueAreaVal]
                } else {
                    $originalValueAreaVal
                }

                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Common.ValueArea"; value=$valueAreaVal }
            }
            if ($row.PSObject.Properties['Risk'] -and $row.Risk) {
                # Map Excel Risk values to Azure DevOps Agile process values
                $riskMapping = @{
                    "High" = "1 - High"
                    "Medium" = "2 - Medium"
                    "Low" = "3 - Low"
                }

                $originalRiskVal = $row.Risk.ToString()
                $riskVal = if ($riskMapping.ContainsKey($originalRiskVal)) {
                    $riskMapping[$originalRiskVal]
                } else {
                    $originalRiskVal
                }

                # Try to validate Risk allowed values; if not available, add cautiously
                $riskAllowed = Get-FieldAllowedValues -WorkItemType $wit -FieldName "Microsoft.VSTS.Common.Risk"
                if (-not $riskAllowed) { $riskAllowed = @() }

                $riskOk = $false
                if ($riskAllowed -and $riskAllowed.Count -gt 0) {
                    foreach ($rv in $riskAllowed) { if ($rv -ieq $riskVal) { $riskOk = $true; break } }
                }

                # If API calls failed (empty allowed values), skip validation and allow the risk
                if ($riskAllowed.Count -eq 0) {
                    Write-LogLevelVerbose "API unavailable for risk validation - allowing risk '$riskVal' without validation"
                    $riskOk = $true
                }

                if ($riskOk) {
                    $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Common.Risk"; value=$riskVal }
                }
                else {
                    Write-Warning "Skipping setting Risk='$originalRiskVal' (mapped to '$riskVal' but not in allowed values for $wit.Risk)"
                }
            }
            
            # Scheduling fields
            if ($row.PSObject.Properties['StartDate'] -and $row.StartDate) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StartDate"; value=[datetime]$row.StartDate }
            }
            if ($row.PSObject.Properties['FinishDate'] -and $row.FinishDate) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.FinishDate"; value=[datetime]$row.FinishDate }
            }
            if ($row.PSObject.Properties['TargetDate'] -and $row.TargetDate) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.TargetDate"; value=[datetime]$row.TargetDate }
            }
            if ($row.PSObject.Properties['DueDate'] -and $row.DueDate) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.DueDate"; value=[datetime]$row.DueDate }
            }
            
            # Effort tracking
            if ($row.PSObject.Properties['OriginalEstimate'] -and $row.OriginalEstimate) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.OriginalEstimate"; value=[double]$row.OriginalEstimate }
            }
            if ($row.PSObject.Properties['RemainingWork'] -and $row.RemainingWork) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.RemainingWork"; value=[double]$row.RemainingWork }
            }
            if ($row.PSObject.Properties['CompletedWork'] -and $row.CompletedWork) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.CompletedWork"; value=[double]$row.CompletedWork }
            }
            
            # Test Case specific: Test Steps
            if ($wit -eq "Test Case" -and $row.PSObject.Properties['TestSteps'] -and $row.TestSteps) {
                $stepsXml = ConvertTo-AdoTestStepsXml -StepsText $row.TestSteps
                if ($stepsXml) {
                    $operations += [pscustomobject]@{
                        op    = "add"
                        path  = "/fields/Microsoft.VSTS.TCM.Steps"
                        value = $stepsXml
                    }
                }
            }
            
            # Tags
            if ($row.PSObject.Properties['Tags'] -and $row.Tags) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/System.Tags"; value=$row.Tags.ToString() }
            }
            
            # Parent relationship (if parent was already created)
            if ($row.PSObject.Properties['ParentLocalId'] -and $row.ParentLocalId) {
                $parentKey = "$($row.ParentLocalId)"
                $parentAdoId = $null
                if ($localToAdoMap.ContainsKey($parentKey)) { $parentAdoId = $localToAdoMap[$parentKey] }
                if ($parentAdoId) {
                    $projEnc = [uri]::EscapeDataString($Project)
                    $relValue = [pscustomobject]@{
                        rel = "System.LinkTypes.Hierarchy-Reverse"
                        url = "$effectiveCollectionUrl/$projEnc/_apis/wit/workItems/$parentAdoId"
                        attributes = [pscustomobject]@{ comment = "Imported from Excel" }
                    }
                    $operations += [pscustomobject]@{
                        op = "add"
                        path = "/relations/-"
                        value = $relValue
                    }
                }
                else {
                    Write-LogLevelVerbose "Parent LocalId $($row.ParentLocalId) not yet created for work item '$($row.Title)'"
                }
            }
            
            # Create work item via REST API
            $witEncoded = [uri]::EscapeDataString($wit)
            $projEnc = [uri]::EscapeDataString($Project)
            
            # Ensure $operations is JSON-serializable by ConvertTo-Json
            $workItemBody = $operations | ConvertTo-Json -Depth 20
            $workItem = Invoke-AdoRest POST "/$projEnc/_apis/wit/workitems/`$$witEncoded" `
                                      -Body $workItemBody `
                                      -ContentType "application/json-patch+json"
            
            # Store mapping for child relationships
            if ($row.PSObject.Properties['LocalId'] -and $row.LocalId) {
                $localToAdoMap["$($row.LocalId)"] = $workItem.id
            }
            
            Write-Host "  ✅ Created $wit #$($workItem.id): $($row.Title)" -ForegroundColor Gray
            $successCount++
        }
        catch {
            $errMsg = "Failed to create $wit '$($row.Title)': $($_.Exception.Message)"
            Write-Warning $errMsg
            $importErrors += $errMsg
            $errorCount++
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[SUCCESS] Imported $successCount work items successfully" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Host "[WARN] $errorCount work items failed to import" -ForegroundColor Yellow
    }

    # Include errors array in return value for caller diagnostics
    return @{
        SuccessCount = $successCount
        ErrorCount   = $errorCount
        WorkItemMap  = $localToAdoMap
        Errors       = $importErrors
        SkippedRows  = $(@($skippedRows).Count)
    }
}

<#
.SYNOPSIS
    Convert Excel test steps format to Azure DevOps XML format.

.DESCRIPTION
    Converts test steps from Excel format (step|expected;;step|expected) to 
    Azure DevOps TCM XML format for Test Case work items.

.PARAMETER StepsText
    Test steps in format: "step1|expected1;;step2|expected2"
    Use ";;" to separate steps, "|" to separate action from expected result.

.EXAMPLE
    ConvertTo-AdoTestStepsXml -StepsText "Login|User logged in;;Logout|User logged out"
#>
function ConvertTo-AdoTestStepsXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepsText
    )
    
    if ([string]::IsNullOrWhiteSpace($StepsText)) {
        return $null
    }
    
    Add-Type -AssemblyName System.Web
    
    # Split by ;; delimiter
    $steps = $StepsText -split ';;'
    $stepCount = $steps.Count
    
    $xmlBuilder = New-Object System.Text.StringBuilder
    [void]$xmlBuilder.Append("<steps id=`"0`" last=`"$stepCount`">")
    
    $stepId = 1
    foreach ($step in $steps) {
        $parts = $step -split '\|', 2
        $action = [System.Web.HttpUtility]::HtmlEncode($parts[0].Trim())
        $expected = if ($parts.Count -gt 1) { 
            [System.Web.HttpUtility]::HtmlEncode($parts[1].Trim()) 
        } else { 
            "" 
        }
        
        [void]$xmlBuilder.Append("<step id=`"$stepId`" type=`"ValidateStep`">")
        [void]$xmlBuilder.Append("<parameterizedString isformatted=`"true`">$action</parameterizedString>")
        [void]$xmlBuilder.Append("<parameterizedString isformatted=`"true`">$expected</parameterizedString>")
        [void]$xmlBuilder.Append("<description />")
        [void]$xmlBuilder.Append("</step>")
        
        $stepId++
    }
    
    [void]$xmlBuilder.Append("</steps>")
    return $xmlBuilder.ToString()
}

<#
.SYNOPSIS
    Shows the allowed states for a specific work item type in Azure DevOps.

.DESCRIPTION
    Queries Azure DevOps to retrieve the allowed values for the System.State field
    of a specific work item type. This helps understand what states are valid
    when importing work items from Excel.

.PARAMETER Project
    The Azure DevOps project name.

.PARAMETER WorkItemType
    The work item type to query (Epic, Feature, User Story, Task, Bug, Test Case, etc.).

.PARAMETER ApiVersion
    The Azure DevOps API version to use (default: 7.1).

.EXAMPLE
    Show-AdoWorkItemStates -Project "MyProject" -WorkItemType "Feature"
#>
function Show-AdoWorkItemStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [ValidateSet("Epic", "Feature", "User Story", "Task", "Bug", "Test Case", "Issue", "Impediment", "Change Request", "Review", "Risk")]
        [string]$WorkItemType,

        [string]$ApiVersion = "7.1"
    )

    Write-Host "🔍 Querying allowed states for $WorkItemType in project '$Project'..." -ForegroundColor Cyan

    try {
        # Get the allowed values for System.State field
        $witEncoded = [uri]::EscapeDataString($WorkItemType)
        $fieldEncoded = [uri]::EscapeDataString("System.State")
        $projEnc = [uri]::EscapeDataString($Project)

        $fieldInfo = Invoke-AdoRest GET "/$projEnc/_apis/wit/workitemtypes/$witEncoded/fields/$fieldEncoded`?api-version=$ApiVersion"

        if ($fieldInfo -and $fieldInfo.allowedValues) {
            Write-Host ""
            Write-Host "✅ Allowed states for $WorkItemType.System.State:" -ForegroundColor Green
            Write-Host "─" * 50 -ForegroundColor Gray

            foreach ($state in $fieldInfo.allowedValues) {
                Write-Host "  • $state" -ForegroundColor White
            }

            Write-Host ""
            Write-Host "📋 Summary:" -ForegroundColor Cyan
            Write-Host "  Total allowed states: $($fieldInfo.allowedValues.Count)" -ForegroundColor White
            Write-Host "  Field is required: $($fieldInfo.required)" -ForegroundColor White
            Write-Host "  Default value: $($fieldInfo.defaultValue)" -ForegroundColor White

            return @{
                WorkItemType = $WorkItemType
                AllowedStates = $fieldInfo.allowedValues
                IsRequired = $fieldInfo.required
                DefaultValue = $fieldInfo.defaultValue
            }
        } else {
            Write-Warning "No allowed values found for $WorkItemType.System.State"
            return $null
        }
    }
    catch {
        Write-Error "Failed to query allowed states: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Shows the allowed states for all common work item types in Azure DevOps.

.DESCRIPTION
    Queries Azure DevOps to retrieve the allowed values for the System.State field
    for all common work item types (Epic, Feature, User Story, Task, Bug, Test Case).
    This provides a comprehensive view of valid states across the project.

.PARAMETER Project
    The Azure DevOps project name.

.EXAMPLE
    Show-AllWorkItemStates -Project "MyProject"
#>
function Show-AllWorkItemStates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project
    )

    Write-Host "🔍 Querying allowed states for all work item types in project '$Project'..." -ForegroundColor Cyan
    Write-Host ""

    $workItemTypes = @("Epic", "Feature", "User Story", "Task", "Bug", "Test Case")
    $results = @{}

    foreach ($wit in $workItemTypes) {
        try {
            $result = Show-AdoWorkItemStates -Project $Project -WorkItemType $wit
            if ($result) {
                $results[$wit] = $result
            }
        }
        catch {
            Write-Warning "Could not query states for $wit`: $_"
        }
    }

    Write-Host ""
    Write-Host "📊 Summary of all work item type states:" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta

    foreach ($wit in $workItemTypes) {
        if ($results.ContainsKey($wit)) {
            $states = $results[$wit].AllowedStates -join ", "
            Write-Host "$wit`: $states" -ForegroundColor White
        } else {
            Write-Host "$wit`: Could not determine" -ForegroundColor Yellow
        }
    }

    return $results
}

# Export functions
Export-ModuleMember -Function @(
    'Ensure-WorkItemTypesCache',
    'Get-WorkItemTypesCache',
    'Initialize-AdoTeamTemplates',
    'New-AdoSharedQueries',
    'New-AdoTestPlan',
    'New-AdoQAQueries',
    'New-AdoTestConfigurations',
    'New-AdoSecurityQueries',
    'Measure-Adocommontags',
    'Measure-Adobusinessqueries',
    'Search-Adodevqueries',
    'Measure-Adomanagementqueries',
    'Import-AdoWorkItemsFromExcel',
    'Resolve-AdoWorkItemType',
    'ConvertTo-AdoTestStepsXml',
    'Convert-ExcelLocalId',
    'Show-AdoWorkItemStates',
    'Show-AllWorkItemStates'
)

# Note: Upsert-AdoQuery removed from exports - internal helper function only

