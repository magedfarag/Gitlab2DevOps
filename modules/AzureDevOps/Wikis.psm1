<#
.SYNOPSIS
    Wiki creation and page management

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Measure-Adoprojectwiki {
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

#>
function Set-AdoWikiPage {
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
    $projEnc = [uri]::EscapeDataString($Project)
    
    # Azure DevOps Wiki API behavior:
    # - PUT: Create new page (fails if page exists)
    # - PATCH: Update existing page (fails if page doesn't exist with 405)
    # Strategy: Try PUT first, if it fails with "already exists", use PATCH
    
    try {
        # Try PUT first to create new page
        Write-Verbose "[Wikis] Creating wiki page: $Path"
        Invoke-AdoRest PUT "/$projEnc/_apis/wiki/wikis/$WikiId/pages?path=$enc" -Body @{
            content = $Markdown
        } | Out-Null
        Write-Verbose "[Wikis] Successfully created wiki page: $Path"
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        # If page already exists, try to update it with PATCH
        if ($errorMsg -match 'WikiPageAlreadyExistsException|already exists|409') {
            Write-Verbose "[Wikis] Page $Path already exists, updating..."
            try {
                # Get existing page to retrieve eTag
                $existing = Invoke-AdoRest GET "/$projEnc/_apis/wiki/wikis/$WikiId/pages?path=$enc"
                
                # Build PATCH body with eTag if available
                $patchBody = @{ content = $Markdown }
                if ($existing.PSObject.Properties['eTag'] -and $existing.eTag) {
                    $patchBody.eTag = $existing.eTag
                }
                
                Invoke-AdoRest PATCH "/$projEnc/_apis/wiki/wikis/$WikiId/pages?path=$enc" -Body $patchBody | Out-Null
                Write-Verbose "[Wikis] Successfully updated wiki page: $Path"
            }
            catch {
                # If PATCH also fails, log warning but don't fail (page might be locked)
                Write-Warning "[Wikis] Could not update page $Path : $_"
            }
        }
        else {
            # Unexpected error - rethrow
            throw
        }
    }
}

#>
function New-AdoQAGuidelinesWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating QA wiki pages..." -ForegroundColor Cyan
    
    # Create parent QA folder
    $qaParentContent = @"
# Quality Assurance

This section contains QA guidelines, testing strategies, and quality management practices.

## Contents
- QA Guidelines & Testing Standards
- Test Strategy & Planning
- Test Data Management
- Automation Framework & Best Practices
- Bug Lifecycle & Quality Metrics

Use the subpages navigation to explore each topic.
"@
    
    try {
        Set-AdoWikiPage $Project $WikiId "/QA" $qaParentContent
        Write-Host "  ✅ QA (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create QA parent page: $_"
    }
    
    # Define all QA wiki pages
    $pages = @(
        @{ path = '/QA/Guidelines'; template = 'QA/QAGuidelines.md'; title = 'QA Guidelines' },
        @{ path = '/QA/Test-Strategy'; template = 'QA/TestStrategy.md'; title = 'Test Strategy' },
        @{ path = '/QA/Test-Data-Management'; template = 'QA/TestDataManagement.md'; title = 'Test Data Management' },
        @{ path = '/QA/Automation-Framework'; template = 'QA/AutomationFramework.md'; title = 'Automation Framework' },
        @{ path = '/QA/Bug-Lifecycle'; template = 'QA/BugLifecycle.md'; title = 'Bug Lifecycle' }
    )
    
    foreach ($page in $pages) {
        try {
            $content = Get-WikiTemplate $page.template
            Set-AdoWikiPage $Project $WikiId $page.path $content | Out-Null
            Write-Host "  ✅ $($page.title)" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($page.path): $_"
        }
    }
    
    Write-Host ""
    Write-Host "[INFO] QA wiki structure created with 5 comprehensive guides:" -ForegroundColor Cyan
    Write-Host "  📋 QA Guidelines: Testing standards and practices" -ForegroundColor Gray
    Write-Host "  🎯 Test Strategy: Planning and execution frameworks" -ForegroundColor Gray
    Write-Host "  � Test Data: Data management and generation strategies" -ForegroundColor Gray
    Write-Host "  🤖 Automation: Framework architecture and best practices" -ForegroundColor Gray
    Write-Host "  🐛 Bug Lifecycle: Defect management and quality metrics" -ForegroundColor Gray
}

#>
function Measure-Adobestpracticeswiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating Best Practices wiki pages..." -ForegroundColor Cyan
    
    # Create parent Best Practices folder
    $bestPracticesParentContent = @"
# Best Practices

This section contains Azure DevOps best practices, coding standards, and development guidelines.

## Contents
- Azure DevOps Best Practices
- Performance Optimization
- Error Handling & Resilience
- Logging Standards
- Testing Strategies
- Documentation Guidelines

Use the subpages navigation to explore each topic.
"@
    
    try {
        Set-AdoWikiPage $Project $WikiId "/Best-Practices" $bestPracticesParentContent
        Write-Host "  ✅ Best Practices (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Best Practices parent page: $_"
    }
    
    # Define all Best Practices wiki pages
    $pages = @(
        @{ path = '/Best-Practices/Overview'; template = 'BestPractices/BestPractices'; title = 'Best Practices Overview' },
        @{ path = '/Best-Practices/Performance-Optimization'; template = 'BestPractices/PerformanceOptimization'; title = 'Performance Optimization' },
        @{ path = '/Best-Practices/Error-Handling'; template = 'BestPractices/ErrorHandling'; title = 'Error Handling' },
        @{ path = '/Best-Practices/Logging-Standards'; template = 'BestPractices/LoggingStandards'; title = 'Logging Standards' },
        @{ path = '/Best-Practices/Testing-Strategies'; template = 'BestPractices/TestingStrategies'; title = 'Testing Strategies' },
        @{ path = '/Best-Practices/Documentation-Guidelines'; template = 'BestPractices/DocumentationGuidelines'; title = 'Documentation Guidelines' }
    )
    
    foreach ($page in $pages) {
        try {
            $content = Get-WikiTemplate $page.template
            Set-AdoWikiPage $Project $WikiId $page.path $content | Out-Null
            Write-Host "  ✅ $($page.title)" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($page.path): $_"
        }
    }
    
    Write-Host ""
    Write-Host "[INFO] Best Practices wiki structure created with 6 comprehensive guides:" -ForegroundColor Cyan
    Write-Host "  💎 Best Practices: Work items, boards, and team productivity" -ForegroundColor Gray
    Write-Host "  🚀 Performance: Optimization strategies for frontend and backend" -ForegroundColor Gray
    Write-Host "  🛡️ Error Handling: Resilience patterns and error management" -ForegroundColor Gray
    Write-Host "  📝 Logging: Structured logging and monitoring best practices" -ForegroundColor Gray
    Write-Host "  🧪 Testing: Comprehensive testing strategies and patterns" -ForegroundColor Gray
    Write-Host "  📚 Documentation: Guidelines for effective technical documentation" -ForegroundColor Gray
}

#>
function Measure-Adobusinesswiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Project,
        [Parameter(Mandatory)] [string]$WikiId
    )
    Write-Host "[INFO] Creating business wiki pages..." -ForegroundColor Cyan

    # Create parent Business folder
    $businessParentContent = @"
# Business & Migration

This section contains business-focused documentation, decision logs, and migration artifacts.

## Contents
- Business Welcome & Overview
- Decision Log
- Risks & Issues
- Glossary
- Ways of Working
- KPIs and Success Metrics
- Training & Quick Start
- Communication Templates
- Cutover Timeline
- Post-Cutover Summary

Use the subpages navigation to explore each topic.
"@
    
    try {
        Set-AdoWikiPage $Project $WikiId "/Business" $businessParentContent
        Write-Host "  ✅ Business (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Business parent page: $_"
    }

    $pages = @(
        @{ path = '/Business/Welcome'; content = Get-WikiTemplate "Business/BusinessWelcome.md" },
        @{ path = '/Business/Decision-Log'; content = Get-WikiTemplate "Business/DecisionLog.md" },
        @{ path = '/Business/Risks-Issues'; content = Get-WikiTemplate "Business/RisksIssues.md" },
        @{ path = '/Business/Glossary'; content = Get-WikiTemplate "Business/Glossary.md" },
        @{ path = '/Business/Ways-of-Working'; content = Get-WikiTemplate "Business/WaysOfWorking.md" },
        @{ path = '/Business/KPIs-and-Success'; content = Get-WikiTemplate "Business/KPIsAndSuccess.md" },
        @{ path = '/Business/Training-Quick-Start'; content = Get-WikiTemplate "Business/TrainingQuickStart.md" },
        @{ path = '/Business/Communication-Templates'; content = Get-WikiTemplate "Business/CommunicationTemplates.md" },
        @{ path = '/Business/Cutover-Timeline'; content = Get-WikiTemplate "Business/CutoverTimeline.md" },
        @{ path = '/Business/Post-Cutover-Summary'; content = Get-WikiTemplate "Business/PostCutoverSummary.md" }
    )

    foreach ($p in $pages) {
        try {
            Set-AdoWikiPage -Project $Project -WikiId $WikiId -Path $p.path -Markdown $p.content | Out-Null
            $pageName = ($p.path -split '/')[-1]
            Write-Host "  ✅ $pageName" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to upsert page $($p.path): $_"
        }
    }
}

#>
function Measure-Adodevwiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating development wiki pages..." -ForegroundColor Cyan
    
    # First, create the parent Development page (required for subpages)
    $developmentParentContent = @"
# Development
This section contains development-focused documentation and guidelines.

## Contents
- Architecture Decision Records
- Development Setup
- API Documentation
- Git Workflow
- Code Review Checklist
- Troubleshooting
- Dependencies

Use the subpages navigation to explore each topic.
"@
    
    try {
        Set-AdoWikiPage $Project $WikiId "/Development" $developmentParentContent
        Write-Host "  ✅ Development (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Development parent page: $_"
    }
    
    # Architecture Decision Records
    $adrContent = Get-WikiTemplate "Dev/ADR.md"

    # Development Setup
    $devSetupContent = Get-WikiTemplate "Dev/DevSetup.md"

    # API Documentation
    $apiDocsContent = Get-WikiTemplate "Dev/APIDocs.md"

    # Git Workflow
    $gitWorkflowContent = Get-WikiTemplate "Dev/GitWorkflow.md"

    # Code Review Checklist
    $codeReviewContent = Get-WikiTemplate "Dev/CodeReview.md"

    # Troubleshooting Guide
    $troubleshootingContent = Get-WikiTemplate "Dev/Troubleshooting.md"

    # Dependencies
    $dependenciesContent = Get-WikiTemplate "Dev/Dependencies.md"

    # Create all wiki subpages
    try {
        Set-AdoWikiPage $Project $WikiId "/Development/Architecture-Decision-Records" $adrContent
        Write-Host "  ✅ Architecture Decision Records" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Development/Development-Setup" $devSetupContent
        Write-Host "  ✅ Development Setup" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Development/API-Documentation" $apiDocsContent
        Write-Host "  ✅ API Documentation" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Development/Git-Workflow" $gitWorkflowContent
        Write-Host "  ✅ Git Workflow" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Development/Code-Review-Checklist" $codeReviewContent
        Write-Host "  ✅ Code Review Checklist" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Development/Troubleshooting" $troubleshootingContent
        Write-Host "  ✅ Troubleshooting" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Development/Dependencies" $dependenciesContent
        Write-Host "  ✅ Dependencies" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] Development wiki pages created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create some development wiki pages: $_"
    }
}

#>
function New-AdoSecurityWiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating security wiki pages..." -ForegroundColor Cyan
    
    # First, create the parent Security page (required for subpages)
    $securityParentContent = @"
# Security
This section contains security policies, guidelines, and procedures.

## Contents
- Security Policies
- Threat Modeling Guide
- Security Testing Checklist
- Incident Response Plan
- Compliance Requirements
- Secret Management
- Security Champions Program

Use the subpages navigation to explore each topic.
"@
    
    try {
        Set-AdoWikiPage $Project $WikiId "/Security" $securityParentContent
        Write-Host "  ✅ Security (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Security parent page: $_"
    }
    
    # Security Policies
    $securityPoliciesContent = Get-WikiTemplate "Security/SecurityPolicies.md"

    # Threat Modeling Guide
    $threatModelingContent = Get-WikiTemplate "Security/ThreatModeling.md"

    # Security Testing Checklist
    $securityTestingContent = Get-WikiTemplate "Security/SecurityTesting.md"

    # Incident Response Plan
    $incidentResponseContent = Get-WikiTemplate "Security/IncidentResponse.md"

    try {
        Set-AdoWikiPage $Project $WikiId "/Security/Security-Policies" $securityPoliciesContent
        Write-Host "  ✅ Security Policies" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Security/Threat-Modeling-Guide" $threatModelingContent
        Write-Host "  ✅ Threat Modeling Guide" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Security/Security-Testing-Checklist" $securityTestingContent
        Write-Host "  ✅ Security Testing Checklist" -ForegroundColor Gray
        
        Set-AdoWikiPage $Project $WikiId "/Security/Incident-Response-Plan" $incidentResponseContent
        Write-Host "  ✅ Incident Response Plan" -ForegroundColor Gray
        
        # Compliance Requirements
        $complianceContent = Get-WikiTemplate "Security/Compliance.md"

        Set-AdoWikiPage $Project $WikiId "/Security/Compliance-Requirements" $complianceContent
        Write-Host "  ✅ Compliance Requirements" -ForegroundColor Gray
        
        # Secret Management
        $secretManagementContent = Get-WikiTemplate "Security/SecretManagement.md"

        Set-AdoWikiPage $Project $WikiId "/Security/Secret-Management" $secretManagementContent
        Write-Host "  ✅ Secret Management" -ForegroundColor Gray
        
        # Security Champions Program
        $securityChampionsContent = Get-WikiTemplate "Security/SecurityChampions.md"

        Set-AdoWikiPage $Project $WikiId "/Security/Security-Champions-Program" $securityChampionsContent
        Write-Host "  ✅ Security Champions Program" -ForegroundColor Gray
        
        Write-Host "[SUCCESS] All 7 security wiki pages created" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create some security wiki pages: $_"
    }
}

#>
function Measure-Adomanagementwiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating Management wiki pages..." -ForegroundColor Cyan
    
    # First, create the parent Management page (required for subpages)
    $managementParentContent = @"
# Management
This section contains program management and PMO documentation.

## Contents
- Program Overview
- Sprint Planning
- Capacity Planning
- Product Roadmap
- RAID Log
- Stakeholder Communications
- Retrospectives
- Metrics Dashboard

Use the subpages navigation to explore each topic.
"@
    
    try {
        Set-AdoWikiPage $Project $WikiId "/Management" $managementParentContent
        Write-Host "  ✅ Management (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Management parent page: $_"
    }
    
    # Define all Management wiki pages
    $pages = @(
        @{ path = '/Management/Program-Overview'; template = 'Management/ProgramOverview.md'; title = 'Program Overview' },
        @{ path = '/Management/Sprint-Planning'; template = 'Management/SprintPlanning.md'; title = 'Sprint Planning' },
        @{ path = '/Management/Capacity-Planning'; template = 'Management/CapacityPlanning.md'; title = 'Capacity Planning' },
        @{ path = '/Management/Roadmap'; template = 'Management/Roadmap.md'; title = 'Product Roadmap' },
        @{ path = '/Management/RAID-Log'; template = 'Management/RAID.md'; title = 'RAID Log (Risks, Assumptions, Issues, Dependencies)' },
        @{ path = '/Management/Stakeholder-Communications'; template = 'Management/StakeholderComms.md'; title = 'Stakeholder Communications' },
        @{ path = '/Management/Retrospectives'; template = 'Management/Retrospectives.md'; title = 'Retrospective Insights' },
        @{ path = '/Management/Metrics-Dashboard'; template = 'Management/MetricsDashboard.md'; title = 'Metrics Dashboard' }
    )
    
    foreach ($page in $pages) {
        try {
            $content = Get-WikiTemplate $page.template
            Set-AdoWikiPage $Project $WikiId $page.path $content | Out-Null
            Write-Host "[SUCCESS] Created/updated wiki page: $($page.title)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to create page $($page.path): $_"
        }
    }
    
    Write-Host ""
    Write-Host "[INFO] Management wiki structure created with 8 comprehensive guides:" -ForegroundColor Cyan
    Write-Host "  📊 Program Overview: Mission, structure, and governance" -ForegroundColor Gray
    Write-Host "  📅 Sprint Planning: Sprint goals, backlog, and ceremonies" -ForegroundColor Gray
    Write-Host "  👥 Capacity Planning: Team capacity and resource allocation" -ForegroundColor Gray
    Write-Host "  🗺️ Product Roadmap: Vision, strategy, and feature timeline" -ForegroundColor Gray
    Write-Host "  🎯 RAID Log: Risks, assumptions, issues, dependencies tracking" -ForegroundColor Gray
    Write-Host "  📢 Stakeholder Communications: Communication plan and templates" -ForegroundColor Gray
    Write-Host "  🔄 Retrospectives: Sprint insights and continuous improvement" -ForegroundColor Gray
    Write-Host "  📈 Metrics Dashboard: KPIs, health metrics, and performance indicators" -ForegroundColor Gray
}

# Export functions
Export-ModuleMember -Function @(
    'Measure-Adoprojectwiki',
    'Set-AdoWikiPage',
    'New-AdoQAGuidelinesWiki',
    'Measure-Adobestpracticeswiki',
    'Measure-Adobusinesswiki',
    'Measure-Adodevwiki',
    'New-AdoSecurityWiki',
    'Measure-Adomanagementwiki'
)


function New-AdoProjectSummaryWikiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Project,
        [Parameter(Mandatory)] [string]$WikiId
    )

    Write-Host "[INFO] Creating Project Summary wiki page..." -ForegroundColor Cyan

    try {
        $proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))?includeCapabilities=true"
        # Ensure core REST is initialized and get a validated config
        $coreRestConfig = Ensure-CoreRestInitialized
        $adoUrl = $coreRestConfig.CollectionUrl

        # Normalize project id and process template values (response shapes vary)
        $projId = ''
        $processTemplateName = 'Unknown'
        if ($proj) {
            if ($proj.PSObject.Properties['id']) { $projId = $proj.id }
            elseif ($proj.PSObject.Properties['value'] -and $proj.value.Count -gt 0 -and $proj.value[0].PSObject.Properties['id']) { $projId = $proj.value[0].id }

            if ($proj.PSObject.Properties['capabilities'] -and $proj.capabilities.processTemplate -and $proj.capabilities.processTemplate.templateName) { $processTemplateName = $proj.capabilities.processTemplate.templateName }
            elseif ($proj.PSObject.Properties['value'] -and $proj.value.Count -gt 0 -and $proj.value[0].PSObject.Properties['capabilities'] -and $proj.value[0].capabilities.processTemplate.templateName) { $processTemplateName = $proj.value[0].capabilities.processTemplate.templateName }
        }

        # Escaped project name for API paths
        $projEnc = [uri]::EscapeDataString($Project)

        # repositories
        $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories"
        $repoCount = 0
        if ($repos) {
            if ($repos.PSObject.Properties['value']) { $repoCount = $repos.value.Count }
            elseif ($repos -is [System.Array]) { $repoCount = $repos.Count }
        }

        # work item types
        $witypes = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/workitemtypes"
        $workItemTypes = ''
        $witypesCount = 0
        if ($witypes) {
            if ($witypes.PSObject.Properties['value']) {
                $workItemTypes = ($witypes.value | Select-Object -ExpandProperty name) -join ', '
                $witypesCount = $witypes.value.Count
            }
            elseif ($witypes -is [System.Array]) {
                $workItemTypes = ($witypes | Select-Object -ExpandProperty name) -join ', '
                $witypesCount = $witypes.Count
            }
        }

        # areas and iterations
        $areas = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas" + '?$depth=2')
        $areaCount = 0
        if ($areas) {
            if ($areas.PSObject.Properties['children']) { $areaCount = $areas.children.Count }
            elseif ($areas.PSObject.Properties['value']) { $areaCount = ($areas.value | Measure-Object).Count }
            elseif ($areas -is [System.Array]) { $areaCount = $areas.Count }
        }

        $iterations = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations" + '?$depth=2')
        $iterationCount = 0
        if ($iterations) {
            if ($iterations.PSObject.Properties['children']) { $iterationCount = $iterations.children.Count }
            elseif ($iterations.PSObject.Properties['value']) { $iterationCount = ($iterations.value | Measure-Object).Count }
            elseif ($iterations -is [System.Array]) { $iterationCount = $iterations.Count }
        }

        # wiki pages
        $wikiPages = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?recursionLevel=full"
        $wikiPageCount = 0
        if ($wikiPages) {
            if ($wikiPages.PSObject.Properties['subPages']) { $wikiPageCount = $wikiPages.subPages.Count }
            elseif ($wikiPages.PSObject.Properties['value']) { $wikiPageCount = ($wikiPages.value | Measure-Object).Count }
            elseif ($wikiPages -is [System.Array]) { $wikiPageCount = $wikiPages.Count }
        }

        # queries
        $queries = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" + '?$depth=2')
        $queryCount = 0
        if ($queries) {
            if ($queries.PSObject.Properties['children']) { $queryCount = $queries.children.Count }
            elseif ($queries.PSObject.Properties['value']) { $queryCount = ($queries.value | Measure-Object).Count }
            elseif ($queries -is [System.Array]) { $queryCount = $queries.Count }
        }

    # dashboards/builds/policies (best-effort)
    try { $dash = Invoke-AdoRest GET "/$projEnc/_apis/dashboard/dashboards" -Preview } catch { $dash = $null }
    $dashboardCount = 0; if ($dash -and $dash.value) { $dashboardCount = $dash.value.Count }
    try { $builddefs = Invoke-AdoRest GET "/$projEnc/_apis/build/definitions" } catch { $builddefs = $null }
    $buildCount = 0; if ($builddefs -and $builddefs.value) { $buildCount = $builddefs.value.Count }
    try { $pol = Invoke-AdoRest GET "/$projEnc/_apis/policy/configurations" } catch { $pol = $null }
    $policyCount = 0; if ($pol -and $pol.value) { $policyCount = $pol.value.Count }

        $projEnc = [uri]::EscapeDataString($Project)

        # build repository list with default branch and last commit (best-effort)
        $repoLines = @()
        if ($repoCount -gt 0) {
            foreach ($r in $repos.value) {
                $default = if ($r.PSObject.Properties['defaultBranch'] -and $r.defaultBranch) { 
                    $r.defaultBranch -replace '^refs/heads/', '' 
                } else { 
                    'none' 
                }
                try {
                    $comm = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($r.id)/commits" + '?$top=1')
                    $commArray = @($comm.value)
                    $last = if ($comm -and $commArray.Count -gt 0) { 
                        ([DateTime]$commArray[0].committer.date).ToString('yyyy-MM-dd HH:mm') 
                    } else { 
                        'No commits' 
                    }
                } catch { $last = 'Unknown' }
                $repoUrl = "$adoUrl/$([uri]::EscapeDataString($Project))/_git/$([uri]::EscapeDataString($r.name))"
                # badge by recency: green if <30 days, yellow if <90, red otherwise
                $badge = '🔴'
                try {
                    if ($last -ne 'No commits' -and $last -ne 'Unknown') {
                        $dt = [DateTime]::ParseExact($last,'yyyy-MM-dd HH:mm',[System.Globalization.CultureInfo]::InvariantCulture)
                        $age = (Get-Date) - $dt
                        if ($age.TotalDays -le 30) { $badge = '🟢' }
                        elseif ($age.TotalDays -le 90) { $badge = '🟡' }
                    }
                } catch { $badge = '🔴' }

                # count branch policies for this repo (best-effort)
                $repoPolicyCount = 0
                if ($pol -and $pol.value) {
                    $repoPolicies = @($pol.value | Where-Object {
                        $_.settings -and $_.settings.scope -and ($_.settings.scope | Where-Object { $_.repositoryId -eq $r.id })
                    })
                    $repoPolicyCount = $repoPolicies.Count
                }

                $repoLines += "- $badge [$($r.name)]($repoUrl) - Default: ``$default`` - Last commit: ``$last`` - Policies: $repoPolicyCount"
            }
        }
        $repoSection = if ($repoLines.Count -gt 0) { $repoLines -join "`n" } else { 'No repositories have been created yet. Repositories will be added during migration.' }

        # pipeline summary: last run status per definition (best-effort)
        $pipelineLines = @()
        if ($buildCount -gt 0) {
            foreach ($def in $builddefs.value) {
                    try {
                    $lastBuild = Invoke-AdoRest GET ("/$projEnc/_apis/build/builds?definitions=$($def.id)" + '&$top=1')
                } catch { $lastBuild = $null }
                $status = 'N/A'
                $result = ''
                $link = "$adoUrl/$projEnc/_build?definitionId=$($def.id)"
                $runLink = $link
                $branch = 'n/a'
                $sha = ''
                $duration = ''

                if ($lastBuild -and $lastBuild.value) {
                    $buildArray = @($lastBuild.value)
                    if ($buildArray.Count -gt 0) {
                        $b = $buildArray[0]
                    $status = $b.status
                    $result = $b.result
                    $runLink = "$adoUrl/$projEnc/_build/results?buildId=$($b.id)"

                    # Trigger branch and commit SHA (best-effort)
                    if ($b.sourceBranch) { $branch = ($b.sourceBranch -replace '^refs/heads/', '') }
                    if ($b.sourceVersion) { $sha = $b.sourceVersion }

                    # Duration calculation
                    try {
                        if ($b.startTime -and $b.finishTime) {
                            $st = [DateTime]$b.startTime
                            $fn = [DateTime]$b.finishTime
                            $ts = $fn - $st
                            $duration = ([int]$ts.TotalMinutes).ToString() + 'm'
                        }
                        elseif ($b.startTime -and -not $b.finishTime) {
                            $st = [DateTime]$b.startTime
                            $ts = (Get-Date) - $st
                            $duration = ([int]$ts.TotalMinutes).ToString() + 'm (running)'
                        }
                    } catch { $duration = '' }
                    }
                }

                # small badge
                $pBadge = '⚪'
                if ($result -eq 'succeeded') { $pBadge = '🟢' }
                elseif ($result -in @('partiallySucceeded','succeededWithIssues')) { $pBadge = '🟡' }
                elseif ($result -in @('failed','canceled')) { $pBadge = '🔴' }

                $pipelineLines += "- $pBadge [$($def.name)]($link) - Branch: `$branch` - Commit: `$($sha.Substring(0,([Math]::Min(7,$sha.Length)) ) )` - Duration: $duration - Result: $result ([view run]($runLink))"
            }
        }
        $pipelineSection = if ($pipelineLines.Count -gt 0) { $pipelineLines -join "`n" } else { 'No pipeline definitions found.' }

            $summary = @"
# $Project - Project Summary

> **Last Updated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
> **Project ID**: ``$projId``  
> **Process Template**: $processTemplateName

---

## Project Overview

| Resource | Count |
|---|---:|
| Repositories | $repoCount |
| Work Item Types | $witypesCount |
| Areas | $areaCount |
| Iterations | $iterationCount |
| Wiki Pages | $wikiPageCount |
| Shared Queries | $queryCount |
| Dashboards | $dashboardCount |
| Build definitions | $buildCount |
| Branch policies | $policyCount |

---

## Repositories

$repoSection

"@

    $summary += "`n---`n## Pipelines`n`n" + $pipelineSection + "`n"
    $summary += "`n---`n## Dashboards & Links`n`n"
    $summary += "- Dashboards: $dashboardCount ([view dashboards]($adoUrl/$projEnc/_dashboards))`n"
    $summary += "- Pipelines: $buildCount ([view pipelines]($adoUrl/$projEnc/_build))`n"
    $summary += "- Queries: $queryCount ([view queries]($adoUrl/$projEnc/_queries))`n"

        Set-AdoWikiPage -Project $Project -WikiId $WikiId -Path "/Project-Summary" -Markdown $summary
        Write-Host "[SUCCESS] Project Summary wiki page created" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to create Project Summary wiki page: $_"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Measure-Adoprojectwiki',
    'Set-AdoWikiPage',
    'New-AdoQAGuidelinesWiki',
    'Measure-Adobestpracticeswiki',
    'Measure-Adobusinesswiki',
    'Measure-Adodevwiki',
    'New-AdoSecurityWiki',
    'Measure-Adomanagementwiki',
    'New-AdoProjectSummaryWikiPage'
)

