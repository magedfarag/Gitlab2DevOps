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

# Export functions
Export-ModuleMember -Function @(
    'Ensure-AdoTeamTemplates',
    'Ensure-AdoSharedQueries',
    'Ensure-AdoTestPlan',
    'Ensure-AdoQAQueries',
    'Ensure-AdoTestConfigurations',
    'Ensure-AdoCommonTags',
    'Ensure-AdoBusinessQueries',
    'Ensure-AdoDevQueries',
    'Ensure-AdoSecurityQueries'
)
