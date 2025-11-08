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
    
    # Define all QA wiki pages
    $pages = @(
        @{ path = '/QA-Guidelines'; template = 'QA/QAGuidelines'; title = 'QA Guidelines & Testing Standards' },
        @{ path = '/Test-Strategy'; template = 'QA/TestStrategy'; title = 'Test Strategy & Planning' },
        @{ path = '/Test-Data-Management'; template = 'QA/TestDataManagement'; title = 'Test Data Management' },
        @{ path = '/Automation-Framework'; template = 'QA/AutomationFramework'; title = 'Automation Framework & Best Practices' },
        @{ path = '/Bug-Lifecycle'; template = 'QA/BugLifecycle'; title = 'Bug Lifecycle & Quality Metrics' }
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
    
    # Define all Best Practices wiki pages
    $pages = @(
        @{ path = '/Best-Practices'; template = 'BestPractices/BestPractices'; title = 'Azure DevOps Best Practices' },
        @{ path = '/Performance-Optimization'; template = 'BestPractices/PerformanceOptimization'; title = 'Performance Optimization' },
        @{ path = '/Error-Handling'; template = 'BestPractices/ErrorHandling'; title = 'Error Handling & Resilience' },
        @{ path = '/Logging-Standards'; template = 'BestPractices/LoggingStandards'; title = 'Logging Standards' },
        @{ path = '/Testing-Strategies'; template = 'BestPractices/TestingStrategies'; title = 'Testing Strategies' },
        @{ path = '/Documentation-Guidelines'; template = 'BestPractices/DocumentationGuidelines'; title = 'Documentation Guidelines' }
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

    $pages = @(
        @{ path = '/Business-Welcome'; content = Get-WikiTemplate "Business/BusinessWelcome" },
    @{ path = '/Decision-Log'; content = Get-WikiTemplate "Business/DecisionLog" },
    @{ path = '/Risks-Issues'; content = Get-WikiTemplate "Business/RisksIssues" },
    @{ path = '/Glossary'; content = Get-WikiTemplate "Business/Glossary" },
    @{ path = '/Ways-of-Working'; content = Get-WikiTemplate "Business/WaysOfWorking" },
    @{ path = '/KPIs-and-Success'; content = Get-WikiTemplate "Business/KPIsAndSuccess" },
    @{ path = '/Training-Quick-Start'; content = Get-WikiTemplate "Business/TrainingQuickStart" },
    @{ path = '/Communication-Templates'; content = Get-WikiTemplate "Business/CommunicationTemplates" },
    @{ path = '/Cutover-Timeline'; content = Get-WikiTemplate "Business/CutoverTimeline" },
    @{ path = '/Post-Cutover-Summary'; content = Get-WikiTemplate "Business/PostCutoverSummary" }
    )

    foreach ($p in $pages) {
        try {
            Set-AdoWikiPage -Project $Project -WikiId $WikiId -Path $p.path -Markdown $p.content | Out-Null
            Write-Host "[SUCCESS] Wiki page ensured: $($p.path)" -ForegroundColor Green
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
    
    # Security Policies
    $securityPoliciesContent = Get-WikiTemplate "Security/SecurityPolicies"

    # Threat Modeling Guide
    $threatModelingContent = Get-WikiTemplate "Security/ThreatModeling"

    # Security Testing Checklist
    $securityTestingContent = Get-WikiTemplate "Security/SecurityTesting"

    # Incident Response Plan
    $incidentResponseContent = Get-WikiTemplate "Security/IncidentResponse"

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
        $complianceContent = Get-WikiTemplate "Security/Compliance"

        Set-AdoWikiPage $Project $WikiId "/Security/Compliance-Requirements" $complianceContent
        Write-Host "  ✅ Compliance Requirements" -ForegroundColor Gray
        
        # Secret Management
        $secretManagementContent = Get-WikiTemplate "Security/SecretManagement"

        Set-AdoWikiPage $Project $WikiId "/Security/Secret-Management" $secretManagementContent
        Write-Host "  ✅ Secret Management" -ForegroundColor Gray
        
        # Security Champions Program
        $securityChampionsContent = Get-WikiTemplate "Security/SecurityChampions"

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
    
    # Define all Management wiki pages
    $pages = @(
        @{ path = '/Management/Program-Overview'; template = 'Management/ProgramOverview'; title = 'Program Overview' },
        @{ path = '/Management/Sprint-Planning'; template = 'Management/SprintPlanning'; title = 'Sprint Planning' },
        @{ path = '/Management/Capacity-Planning'; template = 'Management/CapacityPlanning'; title = 'Capacity Planning' },
        @{ path = '/Management/Roadmap'; template = 'Management/Roadmap'; title = 'Product Roadmap' },
        @{ path = '/Management/RAID-Log'; template = 'Management/RAID'; title = 'RAID Log (Risks, Assumptions, Issues, Dependencies)' },
        @{ path = '/Management/Stakeholder-Communications'; template = 'Management/StakeholderComms'; title = 'Stakeholder Communications' },
        @{ path = '/Management/Retrospectives'; template = 'Management/Retrospectives'; title = 'Retrospective Insights' },
        @{ path = '/Management/Metrics-Dashboard'; template = 'Management/MetricsDashboard'; title = 'Metrics Dashboard' }
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
        $adoUrl = $script:coreRestConfig.AdoCollectionUrl

        # repositories
        $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories"
        $repoCount = 0; if ($repos -and $repos.value) { $repoCount = $repos.value.Count }

        # work item types
        $witypes = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/workitemtypes"
        $workItemTypes = '' ; if ($witypes -and $witypes.value) { $workItemTypes = ($witypes.value | Select-Object -ExpandProperty name) -join ', ' }

        # areas and iterations
        $areas = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas?``$depth=2"
        $areaCount = 0; if ($areas -and $areas.children) { $areaCount = $areas.children.Count }
        $iterations = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations?``$depth=2"
        $iterationCount = 0; if ($iterations -and $iterations.children) { $iterationCount = $iterations.children.Count }

        # wiki pages
        $wikiPages = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?recursionLevel=full"
        $wikiPageCount = 0; if ($wikiPages -and $wikiPages.subPages) { $wikiPageCount = $wikiPages.subPages.Count }

        # queries
        $queries = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries?``$depth=2"
        $queryCount = 0; if ($queries -and $queries.children) { $queryCount = $queries.children.Count }

    # dashboards/builds/policies (best-effort)
    try { $dash = Invoke-AdoRest GET "/$projEnc/_apis/dashboard/dashboards" } catch { $dash = $null }
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
                $default = if ($r.defaultBranch) { $r.defaultBranch -replace '^refs/heads/', '' } else { 'none' }
                try {
                    $comm = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($r.id)/commits?``$top=1"
                    $last = if ($comm -and $comm.value -and $comm.value.Count -gt 0) { ([DateTime]$comm.value[0].committer.date).ToString('yyyy-MM-dd HH:mm') } else { 'No commits' }
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
                    $repoPolicyCount = ($pol.value | Where-Object {
                        $_.settings -and $_.settings.scope -and ($_.settings.scope | Where-Object { $_.repositoryId -eq $r.id })
                    }).Count
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
                    $lastBuild = Invoke-AdoRest GET "/$projEnc/_apis/build/builds?definitions=$($def.id)&``$top=1"
                } catch { $lastBuild = $null }
                $status = 'N/A'
                $result = ''
                $link = "$adoUrl/$projEnc/_build?definitionId=$($def.id)"
                $runLink = $link
                $branch = 'n/a'
                $sha = ''
                $duration = ''

                if ($lastBuild -and $lastBuild.value -and $lastBuild.value.Count -gt 0) {
                    $b = $lastBuild.value[0]
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
> **Project ID**: ``$($proj.id)``  
> **Process Template**: $($proj.capabilities.processTemplate.templateName)

---

## Project Overview

| Resource | Count |
|---|---:|
| Repositories | $repoCount |
| Work Item Types | $($witypes.value.Count) |
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

