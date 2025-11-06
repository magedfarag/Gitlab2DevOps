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

#>
function Ensure-AdoQAGuidelinesWiki {
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
            Upsert-AdoWikiPage $Project $WikiId $page.path $content | Out-Null
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
function Ensure-AdoBestPracticesWiki {
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
            Upsert-AdoWikiPage $Project $WikiId $page.path $content | Out-Null
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
function Ensure-AdoBusinessWiki {
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
            Upsert-AdoWikiPage -Project $Project -WikiId $WikiId -Path $p.path -Markdown $p.content | Out-Null
            Write-Host "[SUCCESS] Wiki page ensured: $($p.path)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to upsert page $($p.path): $_"
        }
    }
}

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

# Export functions
Export-ModuleMember -Function @(
    'Ensure-AdoProjectWiki',
    'Upsert-AdoWikiPage',
    'Ensure-AdoQAGuidelinesWiki',
    'Ensure-AdoBestPracticesWiki',
    'Ensure-AdoBusinessWiki',
    'Ensure-AdoDevWiki',
    'Ensure-AdoSecurityWiki'
)
