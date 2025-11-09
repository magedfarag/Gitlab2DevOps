<#
.SYNOPSIS
    Work items, queries, and test plans

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

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
            $existing = Invoke-AdoRest GET "/$projEnc/_apis/wit/queries/$encoded"
            if ($existing -and $existing.isFolder) {
                Write-Verbose "[WorkItems] Query folder '$currentPath' already exists"
                continue
            }
        }
        catch {
            # Folder doesn't exist, create it
            Write-Verbose "[WorkItems] Creating query folder: $currentPath"
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
            Write-Verbose "[WorkItems] Successfully created query folder: $currentPath"
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

    # Get available types for the project (may return names like 'User Story' or 'Product Backlog Item')
    $available = @()
    try {
        $available = Get-AdoWorkItemTypes -Project $Project
    }
    catch {
        Write-Verbose "[Resolve-AdoWorkItemType] Could not retrieve available work item types: $_"
        $available = @()
    }

    # If detection failed (empty), fall back to process-template defaults to improve chances of mapping
    if (-not $available -or $available.Count -eq 0) {
        Write-Verbose "[Resolve-AdoWorkItemType] No work item types detected, falling back to process template defaults"
        try {
            $proc = Get-AdoProjectProcessTemplate -ProjectId $Project
            switch ($proc) {
                'Agile'    { $available = @('User Story','Task','Bug','Epic','Feature','Test Case') }
                'Scrum'    { $available = @('Product Backlog Item','Task','Bug','Epic','Feature','Test Case','Impediment') }
                'CMMI'     { $available = @('Requirement','Task','Bug','Epic','Feature','Test Case','Issue','Risk','Review','Change Request') }
                'Basic'    { $available = @('Issue','Task','Epic') }
                default    { $available = @('User Story','Product Backlog Item','Task','Bug','Epic','Feature','Test Case','Issue','Requirement') }
            }
            Write-Verbose "[Resolve-AdoWorkItemType] Fallback available types: $($available -join ', ')"
        }
        catch {
            Write-Verbose "[Resolve-AdoWorkItemType] Fallback to defaults failed: $_"
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
        $existing = Invoke-AdoRest GET "/$projEnc/_apis/wit/queries/$encodedFull"
    }
    catch {
        $existing = $null
    }

    if ($existing -and $existing.id) {
        # Update existing query if WIQL differs
        try {
            $currentWiql = if ($existing.PSObject.Properties['wiql']) { $existing.wiql } else { $null }
            if ($currentWiql -and ($currentWiql -ne $Wiql)) {
                Write-Verbose "[Upsert-AdoQuery] Updating query '$Path' wiql"
                $patchBody = @{ wiql = $Wiql }
                Invoke-AdoRest PATCH "/$projEnc/_apis/wit/queries/$($existing.id)" -Body $patchBody | Out-Null
            }
            else {
                Write-Verbose "[Upsert-AdoQuery] Query '$Path' already exists and wiql unchanged"
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
        Write-Verbose "[Upsert-AdoQuery] Could not ensure parent folder '$parent': $_"
    }

    # Create new query under parent
    try {
        $parentEnc = [uri]::EscapeDataString($parent)
        $body = @{ name = $name; wiql = $Wiql }
        $created = Invoke-AdoRest POST "/$projEnc/_apis/wit/queries/$parentEnc" -Body $body
        Write-Verbose "[Upsert-AdoQuery] Created query '$Path'"
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
    Write-Verbose "[Initialize-AdoTeamTemplates] Available types in project: $($availableTypes -join ', ')"
    Write-Verbose "[Initialize-AdoTeamTemplates] Template API endpoint: $base"
    
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
                    
                    Write-Verbose "[Initialize-AdoTeamTemplates] Creating template: $($template.name)"
                    Write-Verbose "[Initialize-AdoTeamTemplates] Template body: $($templateBody | ConvertTo-Json -Depth 5)"
                    
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
    
    # Check existing queries
    $existingQueries = @{}
    try {
        $response = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=1"
        if ($response -and $response.children) {
            $response.children | ForEach-Object { $existingQueries[$_.name] = $_ }
        }
    }
    catch {
        Write-Verbose "[New-AdoSharedQueries] Could not retrieve existing queries: $_"
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
            
            Write-Verbose "[New-AdoSharedQueries] Creating query: $($queryDef.name)"
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
                Write-Verbose "[New-AdoTestPlan] Using current iteration: $Iteration"
            } else {
                # Fallback to project root iteration
                $Iteration = $Project
                Write-Verbose "[New-AdoTestPlan] No current iteration found, using project root: $Iteration"
            }
        }
        catch {
            $Iteration = $Project
            Write-Verbose "[New-AdoTestPlan] Error getting current iteration, using project root: $Iteration"
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
        Write-Verbose "[New-AdoTestPlan] Could not retrieve existing test plans: $_"
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
            
            Write-Verbose "[New-AdoTestPlan] Creating test plan with body: $($testPlanBody | ConvertTo-Json -Depth 5)"
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
        Write-Verbose "[New-AdoTestPlan] Could not retrieve existing test suites: $_"
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
            
            Write-Verbose "[New-AdoTestPlan] Creating suite: $($suiteDef.name)"
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
        $sharedQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=2"
        
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
            $folderQueries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/$qaFolderId?`$depth=1"
            if ($folderQueries -and $folderQueries.children) {
                $folderQueries.children | ForEach-Object { $existingQueries[$_.name] = $_ }
            }
        }
    }
    catch {
        Write-Verbose "[New-AdoQAQueries] Could not retrieve existing queries: $_"
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
            Write-Verbose "[New-AdoTestConfigurations] Could not retrieve existing variables: $_"
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
                        Write-Verbose "[New-AdoTestConfigurations] Failed to update variable '$($varDef.Name)': $_"
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
            Write-Verbose "[New-AdoTestConfigurations] Could not retrieve existing configurations: $_"
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
                        Write-Verbose "[New-AdoTestConfigurations] Skipping value '$varValue' for variable '$varName' (not in allowed values)"
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
        Write-Verbose "[New-AdoTestConfigurations] Error details: $($_.Exception.Message)"
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
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating tag guidelines wiki page..." -ForegroundColor Cyan
    
    # Load tag guidelines template with fallback
    $tagGuidelinesContent = $null
    $templatePath = Join-Path $PSScriptRoot "..\templates\TagGuidelines.md"
    
    if (Test-Path $templatePath) {
        try {
            $tagGuidelinesTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8
            $tagGuidelinesContent = $tagGuidelinesTemplate -replace '{{CURRENT_DATE}}', (Get-Date -Format 'yyyy-MM-dd')
            Write-Verbose "[Measure-Adocommontags] Loaded template from: $templatePath"
        }
        catch {
            Write-Warning "Failed to load template from '$templatePath': $_"
        }
    }
    
    # Fallback to embedded template if file not found or failed to load
    if (-not $tagGuidelinesContent) {
        Write-Verbose "[Measure-Adocommontags] Using embedded fallback template"
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
        # Check if page exists
        try {
            $existingPage = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?path=/Tag-Guidelines"
            Write-Host "[INFO] Tag Guidelines page already exists" -ForegroundColor Gray
            return $existingPage
        }
        catch {
            # Page doesn't exist, create it
            Write-Verbose "[Measure-Adocommontags] Creating Tag Guidelines page"
            $page = Set-AdoWikiPage $Project $WikiId "/Tag-Guidelines" $tagGuidelinesContent
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
        $resp = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?`$depth=1"
        if ($resp -and $resp.children) { $resp.children | ForEach-Object { $existing[$_.name] = $_ } }
    }
    catch {
        Write-Verbose "[Measure-Adobusinessqueries] Could not retrieve existing queries: $_"
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
        Write-Verbose "[Search-Adodevqueries] Created Development queries folder"
    }
    catch {
        # Folder might already exist
        Write-Verbose "[Search-Adodevqueries] Development folder exists or creation skipped"
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
    - AreaPath, IterationPath, State, Description, Priority
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
        [string]$ApiVersion = $null
    )

    # Ensure $script:CollectionUrl is set for parent/child relationships
    if (-not $script:CollectionUrl) {
        $script:CollectionUrl = 'https://dev.azure.com/magedfarag'
    }

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
        Write-Verbose "Reading Excel file: $ExcelPath"
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
    
    # Resolve and normalize WorkItemType values from Excel to ADO project types.
    $resolvedRows = @()
    $skippedRows = @()

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
            Write-Warning "[SKIP] Row skipped: Title='$($r.Title)', WorkItemType='$excelType' (could not resolve to ADO type)"
            $skippedRows += $r
        }
    }

    if (@($skippedRows).Count -gt 0) {
        Write-Warning "Skipping $(@($skippedRows).Count) row(s) due to unknown WorkItemType. See warnings above for details."
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
    
    # Map Excel LocalId to Azure DevOps work item ID (string keys to avoid JSON serialization issues)
    $localToAdoMap = @{}
    $successCount = 0
    $errorCount = 0
    
    foreach ($row in $orderedRows) {
        # Use resolved work item type (from Resolve-AdoWorkItemType)
        $wit = if ($row.PSObject.Properties['ResolvedWorkItemType']) { $row.ResolvedWorkItemType } else { $row.WorkItemType }
        
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
            
            # Optional standard fields - check if property exists first using PSObject.Properties
            if ($row.PSObject.Properties['AreaPath'] -and $row.AreaPath) {
                $operations += [pscustomobject]@{ op="add"; path="/fields/System.AreaPath"; value=$row.AreaPath.ToString() }
            }
            if ($row.PSObject.Properties['IterationPath'] -and $row.IterationPath) {
                $operations += @{ op="add"; path="/fields/System.IterationPath"; value=$row.IterationPath.ToString() }
            }
            if ($row.PSObject.Properties['State'] -and $row.State) {
                # Query allowed values for System.State and only add if allowed (case-insensitive)
                try {
                    $fieldInfo = Invoke-AdoRest GET "/_apis/wit/fields/System.State?api-version=7.1"
                    $allowed = @()
                    if ($fieldInfo -and $fieldInfo.allowedValues) { $allowed = $fieldInfo.allowedValues }
                }
                catch {
                    $allowed = @()
                }

                $stateVal = $row.State.ToString()
                $isAllowed = $false
                if ($allowed -and $allowed.Count -gt 0) {
                    foreach ($av in $allowed) { if ($av -ieq $stateVal) { $isAllowed = $true; break } }
                }

                if ($isAllowed) {
                    $operations += [pscustomobject]@{ op="add"; path="/fields/System.State"; value=$stateVal }
                }
                else {
                    Write-Warning "Skipping setting State='$stateVal' (not in allowed values for System.State)"
                }
            }
            if ($row.PSObject.Properties['Description'] -and $row.Description) {
                $operations += @{ op="add"; path="/fields/System.Description"; value=$row.Description.ToString() }
            }
            if ($row.PSObject.Properties['Priority'] -and $row.Priority) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Common.Priority"; value=[int]$row.Priority }
            }
            
            # Work item type specific fields
            if ($row.PSObject.Properties['StoryPoints'] -and $row.StoryPoints -and $wit -eq "User Story") {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StoryPoints"; value=[double]$row.StoryPoints }
            }
            if ($row.PSObject.Properties['BusinessValue'] -and $row.BusinessValue) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Common.BusinessValue"; value=[int]$row.BusinessValue }
            }
            if ($row.PSObject.Properties['ValueArea'] -and $row.ValueArea) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Common.ValueArea"; value=$row.ValueArea.ToString() }
            }
            if ($row.PSObject.Properties['Risk'] -and $row.Risk) {
                # Try to validate Risk allowed values; if not available, add cautiously
                try {
                    $riskField = Invoke-AdoRest GET "/_apis/wit/fields/Microsoft.VSTS.Common.Risk?api-version=7.1"
                    $riskAllowed = @()
                    if ($riskField -and $riskField.allowedValues) { $riskAllowed = $riskField.allowedValues }
                }
                catch {
                    $riskAllowed = @()
                }

                $riskVal = $row.Risk.ToString()
                $riskOk = $false
                if ($riskAllowed -and $riskAllowed.Count -gt 0) {
                    foreach ($rv in $riskAllowed) { if ($rv -ieq $riskVal) { $riskOk = $true; break } }
                }

                if ($riskOk -or $riskAllowed.Count -eq 0) {
                    $operations += [pscustomobject]@{ op="add"; path="/fields/Microsoft.VSTS.Common.Risk"; value=$riskVal }
                }
                else {
                    Write-Warning "Skipping setting Risk='$riskVal' (not in allowed values for Risk)"
                }
            }
            
            # Scheduling fields
            if ($row.PSObject.Properties['StartDate'] -and $row.StartDate) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StartDate"; value=[datetime]$row.StartDate }
            }
            if ($row.PSObject.Properties['FinishDate'] -and $row.FinishDate) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.FinishDate"; value=[datetime]$row.FinishDate }
            }
            if ($row.PSObject.Properties['TargetDate'] -and $row.TargetDate) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.TargetDate"; value=[datetime]$row.TargetDate }
            }
            if ($row.PSObject.Properties['DueDate'] -and $row.DueDate) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.DueDate"; value=[datetime]$row.DueDate }
            }
            
            # Effort tracking
            if ($row.PSObject.Properties['OriginalEstimate'] -and $row.OriginalEstimate) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.OriginalEstimate"; value=[double]$row.OriginalEstimate }
            }
            if ($row.PSObject.Properties['RemainingWork'] -and $row.RemainingWork) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.RemainingWork"; value=[double]$row.RemainingWork }
            }
            if ($row.PSObject.Properties['CompletedWork'] -and $row.CompletedWork) {
                $operations += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.CompletedWork"; value=[double]$row.CompletedWork }
            }
            
            # Test Case specific: Test Steps
            if ($wit -eq "Test Case" -and $row.PSObject.Properties['TestSteps'] -and $row.TestSteps) {
                $stepsXml = ConvertTo-AdoTestStepsXml -StepsText $row.TestSteps
                if ($stepsXml) {
                    $operations += @{
                        op    = "add"
                        path  = "/fields/Microsoft.VSTS.TCM.Steps"
                        value = $stepsXml
                    }
                }
            }
            
            # Tags
            if ($row.PSObject.Properties['Tags'] -and $row.Tags) {
                $operations += @{ op="add"; path="/fields/System.Tags"; value=$row.Tags.ToString() }
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
                        url = "$script:CollectionUrl/$projEnc/_apis/wit/workItems/$parentAdoId"
                        attributes = [pscustomobject]@{ comment = "Imported from Excel" }
                    }
                    $operations += [pscustomobject]@{
                        op = "add"
                        path = "/relations/-"
                        value = $relValue
                    }
                }
                else {
                    Write-Verbose "Parent LocalId $($row.ParentLocalId) not yet created for work item '$($row.Title)'"
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
            Write-Warning "Failed to create $wit '$($row.Title)': $_"
            $errorCount++
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[SUCCESS] Imported $successCount work items successfully" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Host "[WARN] $errorCount work items failed to import" -ForegroundColor Yellow
    }
    
    return @{
        SuccessCount = $successCount
        ErrorCount   = $errorCount
        WorkItemMap  = $localToAdoMap
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

# Export functions
Export-ModuleMember -Function @(
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
    'ConvertTo-AdoTestStepsXml'
)

# Note: Upsert-AdoQuery removed from exports - internal helper function only

