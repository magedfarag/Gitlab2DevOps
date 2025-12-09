<#
.SYNOPSIS
    Wiki creation and page management

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Import Core.Rest FIRST so all functions are available for parameter validation and runtime usage
$migrationRoot = Split-Path $PSScriptRoot -Parent
$coreRestPath = Join-Path $migrationRoot "core\Core.Rest.psm1"
if (-not (Get-Module -Name 'Core.Rest') -and (Test-Path $coreRestPath)) {
    Import-Module -WarningAction SilentlyContinue $coreRestPath -Force -Global -ErrorAction Stop
}
$loggingPath = Join-Path $migrationRoot "core\Logging.psm1"
if (-not (Get-Module -Name 'Logging') -and (Test-Path $loggingPath)) {
    Import-Module -WarningAction SilentlyContinue $loggingPath -Force -Global -ErrorAction Stop
}
$templatesPath = Join-Path $migrationRoot "Templates\Templates.psm1"
if (-not (Get-Module -Name 'Templates') -and (Test-Path $templatesPath)) {
    Import-Module -WarningAction SilentlyContinue $templatesPath -Force -Global -ErrorAction Stop
}

function Measure-Adoprojectwiki {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ProjId,
        
        [Parameter(Mandatory)]
        [string]$Project
        # Removed unused parameters: CollectionUrl, AdoPat, AdoApiVersion
    )
    
    if (-not $ProjId) {
        try {
            $projInfo = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))?includeCapabilities=false" -MaxAttempts 1 -DelaySeconds 0
            if ($projInfo -and $projInfo.PSObject.Properties['id']) {
                $ProjId = $projInfo.id
            }
        }
        catch {
            Write-Verbose "[AzureDevOps] Failed to resolve project id for $($Project): $_"
        }
    }

    try {
        # Do a fast, non-retried check for existing project wikis to avoid noisy retries
        $w = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis" -MaxAttempts 1 -DelaySeconds 0
    }
    catch {
        # Use format operator to avoid ambiguous "$Var: ..." parsing inside double-quoted strings
        Write-Warning ("[AzureDevOps] Failed to query project wikis for {0}: {1}" -f $Project, $_)
        return $null
    }

    # Defensive handling: API may return $null, an object with .value, or an array
    $projWiki = $null
    if ($w) {
        if ($w.PSObject.Properties['value']) {
            $projWiki = $w.value | Where-Object { $_.type -eq 'projectWiki' }
        }
        elseif ($w -is [System.Array]) {
            $projWiki = $w | Where-Object { $_.type -eq 'projectWiki' }
        }
    }

    if ($projWiki) {
        Write-Verbose "[AzureDevOps] Project wiki already exists"
        return $projWiki
    }
    
    Write-Host "[INFO] Creating project wiki"
        try {
        # Create wiki without core-layer retries to avoid noisy global retry logs
        $newWiki = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis" -Body @{
            name      = "$Project.wiki"
            type      = "projectWiki"
            projectId = $ProjId
        } -MaxAttempts 1 -DelaySeconds 0
        Write-Host "[SUCCESS] Project wiki created successfully" -ForegroundColor Green
        
        # Give the wiki time to initialize before proceeding
        Start-Sleep -Seconds 5
        
        return $newWiki
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "[AzureDevOps] Failed to create project wiki for $Project`: $errorMsg"
        
        # Provide specific guidance based on error type
        if ($errorMsg -match '403|Forbidden') {
            Write-Warning "  → Check PAT permissions: Ensure 'Project and Team (read, write, & manage)' scope"
        }
        elseif ($errorMsg -match '401|Unauthorized') {
            Write-Warning "  → Check PAT validity: Token may be expired or invalid"
        }
        elseif ($errorMsg -match '400|Bad Request') {
            Write-Warning "  → Check project configuration: Project may not support wikis"
        }
        elseif ($errorMsg -match '409|Conflict') {
            Write-Warning "  → Wiki may already exist with different name, check Azure DevOps UI"
        }
        else {
            Write-Warning "  → Check server configuration and network connectivity"
        }
        
        return $null
    }
}


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

    $projEnc = [uri]::EscapeDataString($Project)
    $pathEnc = [uri]::EscapeDataString($Path)
    $relative = "/$projEnc/_apis/wiki/wikis/$WikiId/pages?path=$pathEnc"

    $pageExists = $false
    $etag = $null

    # 1) Check if page exists and capture ETag for updates
    try {
        $resp = Invoke-AdoRest GET $relative -ApiVersion '7.1' -ReturnNullOnNotFound
        if ($resp -and $resp.PSObject.Properties['path']) {
            $pageExists = $true
            # ETag can come from headers; Invoke-AdoRest returns parsed body, so re-fetch raw headers
            try {
                $config = Get-CoreRestConfig
                $authHeader = New-AuthHeader -Pat $config.AdoPat
                $collectionUrl = $config.CollectionUrl.TrimEnd('/')
                $raw = Invoke-WebRequest -Uri ($collectionUrl + $relative + "&api-version=7.1") -Headers $authHeader -Method GET -UseBasicParsing
                if ($raw -and $raw.Headers['ETag']) { $etag = $raw.Headers['ETag'] }
            } catch { }
        }
    }
    catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
        if ($status -eq 404) {
            $pageExists = $false
        }
        else {
            throw
        }
    }

    # 2) Build headers for PUT - use Content-Type and optionally If-Match
    $headers = @{
        'Content-Type' = 'application/json'
    }
    if ($pageExists -and $etag) {
        $headers['If-Match'] = $etag
    }

    $body = @{ content = $Markdown } | ConvertTo-Json -Depth 5

    # 3) Create or update
    try {
        Invoke-AdoRest PUT $relative -ApiVersion '7.1' -Body $body -Headers $headers | Out-Null
        return
    }
    catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
        if ($status -eq 500) {
            # Some on-premises instances return 500 after creating; verify existence and treat as success if present
            try {
                $verify = Invoke-AdoRest GET $relative -ApiVersion '7.1' -ReturnNullOnNotFound
                if ($verify -and $verify.PSObject.Properties['path']) {
                    Write-LogLevelVerbose "[Wikis] PUT returned 500 but page exists; treating as success."
                    return
                }
            } catch { }
        }
        throw
    }
}

function Set-AdoWikiPageWithRetry {
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
    
    $maxRetries = 3
    $retryDelay = 2
    
    for ($retryAttempt = 1; $retryAttempt -le $maxRetries; $retryAttempt++) {
        try {
            Set-AdoWikiPage -Project $Project -WikiId $WikiId -Path $Path -Markdown $Markdown
            return  # Success, exit the function
        }
        catch {
            $errorMsg = $_.Exception.Message
            # Check if this is a retryable error
            $isRetryable = $errorMsg -match '404|WikiNotFoundException|Wiki.*not found' -or
                          $errorMsg -match 'Service Unavailable'
            # Note: 500 errors are NOT retried here since Set-AdoWikiPage already handles them with its own retry logic
            if ($isRetryable -and $retryAttempt -lt $maxRetries) {
                Write-Host "[Wikis] Page creation failed for $Path (attempt $retryAttempt/$maxRetries), retrying in ${retryDelay}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2  # Exponential backoff
            }
            elseif ($retryAttempt -eq $maxRetries) {
                Write-Host "[Wikis] All retry attempts failed for $Path — skipping page creation" -ForegroundColor Red
                throw $_
            }
            else {
                # For non-retryable errors, don't retry
                throw $_
            }
        }
    }
}

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
    $qaParentContent = @'
# Quality Assurance

This section contains QA guidelines, testing strategies, and quality management practices.

## Contents
- QA Guidelines & Testing Standards
- Test Strategy & Planning
- Test Data Management
- Automation Framework & Best Practices
- Bug Lifecycle & Quality Metrics
- Non-Functional Testing

Use the subpages navigation to explore each topic.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/QA" $qaParentContent
        Write-Host "  ✅ QA (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create QA parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000
    
    # Define QA wiki pages in reverse order (highest number first) for correct Azure DevOps display
    $qaFiles = @(
        "08-BugLifecycle.md",
        "07-NonFunctionalTesting.md",
        "06-TestDataManagement.md",
        "05-AutomationFramework.md",
        "04-QAGuidelines.md",
        "03-TestStrategy.md",
        "02-playbook.md",
        "01-guide.md"
    )
    foreach ($fileName in $qaFiles) {
        $path = "/QA/$($fileName -replace '\.md$', '')"
        $content = Get-WikiTemplate "QA/$fileName"
        try {
            Set-AdoWikiPageWithRetry $Project $WikiId $path $content | Out-Null
            Write-Host "  ✅ $($fileName -replace '\.md$', '')" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}


function Measure-Adobestpracticeswiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
        # Removed unused parameters: CollectionUrl, AdoPat, AdoApiVersion
    )
    
    Write-Host "[INFO] Creating Best Practices wiki pages..." -ForegroundColor Cyan
    
    # Create parent Best Practices folder
    $bestPracticesParentContent = @'
# Best Practices

This section contains Azure DevOps best practices, coding standards, and development guidelines.

## Contents
- Architecture and Design Guidelines
- Azure DevOps Best Practices
- Performance Optimization
- Error Handling & Resilience
- Logging Standards
- Monitoring and Alerting Standards
- Testing Strategies
- Documentation Guidelines

Use the subpages navigation to explore each topic.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/Best-Practices" $bestPracticesParentContent | Out-Null
        Write-Host "  ✅ Best Practices (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Best Practices parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000
    
    # Define Best Practices wiki pages in reverse order (highest number first) for correct Azure DevOps display
    $bestPracticesFiles = @(
        "08-DocumentationGuidelines.md",
        "07-PerformanceOptimization.md",
        "06-MonitoringAndAlertingStandards.md",
        "05-LoggingStandards.md",
        "04-ErrorHandling.md",
        "03-TestingStrategies.md",
        "02-ArchitectureAndDesignGuidelines.md",
        "01-BestPractices.md"
    )
    foreach ($fileName in $bestPracticesFiles) {
        $path = "/Best-Practices/$($fileName -replace '\.md$', '')"
        $content = Get-WikiTemplate "BestPractices/$fileName"
        try {
            Set-AdoWikiPageWithRetry $Project $WikiId $path $content | Out-Null
            Write-Host "  ✅ $($fileName -replace '\.md$', '')" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}


function Measure-Adobusinesswiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Project,
        [Parameter(Mandatory)] [string]$WikiId
    )
    Write-Host "[INFO] Creating business wiki pages..." -ForegroundColor Cyan

    # Create parent Business folder
    $businessParentContent = @'
# Business & Migration

This section contains business-focused documentation, decision logs, and migration artifacts.

## Contents
- Business Welcome & Overview
- Decision Log
- Risks & Issues
- Risk Appetite and Guardrails
- Glossary
- Ways of Working
- KPIs and Success Metrics
- Training & Quick Start
- Communication Templates

Use the subpages navigation to explore each topic.

> Related: See the [Security](../Security) section for policies, threat modeling, testing, and incident response guidance that pairs with business governance.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/Business" $businessParentContent
        Write-Host "  ✅ Business (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Business parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000

    # Dynamically read all .md files from Business folder
    $businessDir = Join-Path $PSScriptRoot "WikiTemplates\Business"
    $mdFiles = Get-ChildItem -Path $businessDir -Filter "*.md" | Sort-Object Name -Descending
    foreach ($file in $mdFiles) {
        $fileName = $file.BaseName
        $path = "/Business/$fileName"
        $content = Get-WikiTemplate "Business/$($file.Name)"
        try {
            Set-AdoWikiPageWithRetry -Project $Project -WikiId $WikiId -Path $path -Markdown $content | Out-Null
            Write-Host "  ✅ $fileName" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to upsert page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}


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
    $developmentParentContent = @'
# Development
This section contains development-focused documentation and guidelines.

## Contents
- Architecture Decision Records
- Development Setup
- API Documentation
- Git Workflow
- CI/CD Pipelines
- Code Review Checklist
- Observability for Developers
- Troubleshooting
- Dependencies

Use the subpages navigation to explore each topic.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/Development" $developmentParentContent
        Write-Host "  ✅ Development (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Development parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000
    
    $devDir = Join-Path $PSScriptRoot "WikiTemplates\Dev"
    $mdFiles = Get-ChildItem -Path $devDir -Filter "*.md" | Sort-Object Name -Descending
    foreach ($file in $mdFiles) {
        $fileName = $file.BaseName
        $path = "/Development/$fileName"
        $content = Get-WikiTemplate "Dev/$($file.Name)"
        try {
            Set-AdoWikiPageWithRetry $Project $WikiId $path $content | Out-Null
            Write-Host "  ✅ $fileName" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}


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
    $securityParentContent = @'
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
- Security Requirements
- Vulnerability Management

Use the subpages navigation to explore each topic.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/Security" $securityParentContent
        Write-Host "  ✅ Security (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Security parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000
    
    # Dynamically read all .md files from Security folder
    $securityDir = Join-Path $PSScriptRoot "WikiTemplates\Security"
    $mdFiles = Get-ChildItem -Path $securityDir -Filter "*.md" | Sort-Object Name -Descending
    foreach ($file in $mdFiles) {
        $fileName = $file.BaseName
        $path = "/Security/$fileName"
        $content = Get-WikiTemplate "Security/$($file.Name)"
        try {
            Set-AdoWikiPageWithRetry $Project $WikiId $path $content | Out-Null
            Write-Host "  ✅ $fileName" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}


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
    $managementParentContent = @'
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
- Change Management and Release Governance
- Metrics Dashboard

Use the subpages navigation to explore each topic.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/Management" $managementParentContent
        Write-Host "  ✅ Management (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Management parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000
    
    # Define Management wiki pages in reverse order (highest number first) for correct Azure DevOps display
    $managementFiles = @(
        "11-RAID.md",
        "10-StakeholderComms.md",
        "09-ChangeManagementAndReleaseGovernance.md",
        "08-Retrospectives.md",
        "07-MetricsDashboard.md",
        "06-SprintPlanning.md",
        "05-CapacityPlanning.md",
        "04-Roadmap.md",
        "03-ProgramOverview.md",
        "02-playbook.md",
        "01-guide.md"
    )
    foreach ($fileName in $managementFiles) {
        $path = "/Management/$($fileName -replace '\.md$', '')"
        $content = Get-WikiTemplate "Management/$fileName"
        try {
            Set-AdoWikiPageWithRetry $Project $WikiId $path $content | Out-Null
            Write-Host "  ✅ $($fileName -replace '\.md$', '')" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}

function Measure-Adootherroleswiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating Other Roles wiki pages..." -ForegroundColor Cyan
    
    # Create parent Other Roles folder
    $otherRolesParentContent = @'
# Other Roles

This section contains guides and playbooks for various roles involved in the project.

## Contents
- Enterprise Architect Guide & Playbook
- Infrastructure Guide & Playbook
- Operations Guide & Playbook
- Platform Guide & Playbook
- Project Manager Guide & Playbook
- SOC Guide & Playbook
- Support Guide & Playbook
- Vendors Guide & Playbook

Use the subpages navigation to explore each role's guide and playbook.
'@
    
    try {
        Set-AdoWikiPageWithRetry $Project $WikiId "/Other-Roles" $otherRolesParentContent
        Write-Host "  ✅ Other Roles (parent page)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Other Roles parent page: $_"
    }
    
    # Add delay after parent page creation
    Start-Sleep -Milliseconds 3000
    
    # Define Other Roles wiki pages in reverse paired order (highest number first) for correct Azure DevOps display
    # Each role has guide-playbook pair, ordered by highest number first
    $otherRolesFiles = @(
        "16-vendors-playbook.md",
        "15-vendors-guide.md",
        "14-project-manager-playbook.md",
        "13-project-manager-guide.md",
        "12-support-playbook.md",
        "11-support-guide.md",
        "10-soc-playbook.md",
        "09-soc-guide.md",
        "08-operations-playbook.md",
        "07-operations-guide.md",
        "06-platform-playbook.md",
        "05-platform-guide.md",
        "04-infrastructure-playbook.md",
        "03-infrastructure-guide.md",
        "02-enterprise-architect-playbook.md",
        "01-enterprise-architect-guide.md"
    )
    foreach ($fileName in $otherRolesFiles) {
        $path = "/Other-Roles/$($fileName -replace '\.md$', '')"
        $content = Get-WikiTemplate "OtherRoles/$fileName"
        try {
            Set-AdoWikiPageWithRetry $Project $WikiId $path $content | Out-Null
            Write-Host "  ✅ $($fileName -replace '\.md$', '')" -ForegroundColor Gray
        }
        catch {
            Write-Warning "Failed to create page $($path): $_"
        }
        # Add small delay between page creations to avoid rate limiting
        Start-Sleep -Milliseconds 2000
    }
}

function Initialize-AdoProjectWikis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$WikiId
    )

    Write-Host "[INFO] Initializing all project wikis for project '$Project'..." -ForegroundColor Cyan

    $results = @()

    $handlers = @(
        @{ Name = 'Root'; Func = { Measure-Adorootwiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'Home'; Func = { New-AdoProjectHomeWikiPage -Project $Project -WikiId $WikiId } },
        @{ Name = 'TagGuidelines'; Func = { New-AdoTagGuidelinesWikiPage -Project $Project -WikiId $WikiId } },
        @{ Name = 'QA'; Func = { New-AdoQAGuidelinesWiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'BestPractices'; Func = { Measure-Adobestpracticeswiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'Business'; Func = { Measure-Adobusinesswiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'Dev'; Func = { Measure-Adodevwiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'Security'; Func = { New-AdoSecurityWiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'Management'; Func = { Measure-Adomanagementwiki -Project $Project -WikiId $WikiId } },
        @{ Name = 'OtherRoles'; Func = { Measure-Adootherroleswiki -Project $Project -WikiId $WikiId } }
    )

    foreach ($h in $handlers) {
        try {
            & $($h.Func)
            $results += [pscustomobject]@{ Wiki = $h.Name; Status = 'Success' }
        }
        catch {
            Write-Warning "Failed to initialize $($h.Name) wiki: $_"
            $results += [pscustomobject]@{ Wiki = $h.Name; Status = 'Failed'; Error = $_.Exception.Message }
        }
    }

    Write-Host "";
    Write-Host "[SUMMARY] Wiki initialization results for project '$Project':" -ForegroundColor Cyan
    foreach ($r in $results) {
        $statusColor = if ($r.Status -eq 'Success') { 'Green' } else { 'Yellow' }
        Write-Host " - $($r.Wiki): $($r.Status)" -ForegroundColor $statusColor
    }

    return $results
}

function Initialize-AdoProjectWikisEfficient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceProject,
        [Parameter(Mandatory)][string[]]$TargetProjects
    )

    Write-Host "[INFO] Creating complete wiki structure for source project '$SourceProject'..." -ForegroundColor Cyan

    # Create the complete wiki structure for the source project
    # Resolve source project id once
    $projInfo = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($SourceProject))?includeCapabilities=false" -MaxAttempts 1 -DelaySeconds 0
    $sourceProjId = $null
    if ($projInfo -and $projInfo.PSObject.Properties['id']) { $sourceProjId = $projInfo.id }

    $sourceWiki = Measure-Adoprojectwiki -Project $SourceProject -ProjId $sourceProjId
    if (-not $sourceWiki) {
        throw "Failed to create wiki for source project '$SourceProject'"
    }

    $sourceWikiId = $sourceWiki.id
    $results = Initialize-AdoProjectWikis -Project $SourceProject -WikiId $sourceWikiId

    Write-Host "[SUCCESS] Complete wiki structure created for source project '$SourceProject'" -ForegroundColor Green

    # Now clone the wiki to all target projects
    foreach ($targetProject in $TargetProjects) {
        try {
            Write-Host "[INFO] Cloning wiki from '$SourceProject' to '$targetProject'..." -ForegroundColor Cyan
            Copy-AdoWikiViaGit -SourceProject $SourceProject -TargetProject $targetProject -WikiId $sourceWikiId
            Write-Host "[SUCCESS] Wiki cloned to '$targetProject'" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to clone wiki to '$targetProject': $_"
        }
    }

    return $results
}

function Invoke-AdoGitClone {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory)]
        [string]$TargetPath,

        [Parameter()]
        [pscustomobject]$Config
    )

    Write-Log "Cloning Git repo '$RepositoryUrl' into '$TargetPath'..." 'INFO'

    $parent = Split-Path -Parent $TargetPath
    if (-not $parent) { $parent = '.' }
    if (-not (Test-Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $patEnv = $null
    if ($Config -and $Config.PSObject.Properties['azureDevOps'] -and $Config.azureDevOps.PSObject.Properties['personalAccessTokenEnvVar']) {
        $patEnv = $Config.azureDevOps.personalAccessTokenEnvVar
    }
    elseif ($Config -and $Config.PSObject.Properties['personalAccessTokenEnvVar']) {
        $patEnv = $Config.personalAccessTokenEnvVar
    }
    if (-not $patEnv) { $patEnv = 'ADO_PAT' }

    $pat = if ($patEnv) { [Environment]::GetEnvironmentVariable($patEnv) } else { $null }

    if (-not $pat) {
        throw "No PAT found in environment variable '$patEnv'. Cannot authenticate git clone."
    }

    $pair     = ":$pat"
    $bytes    = [Text.Encoding]::ASCII.GetBytes($pair)
    $base64   = [Convert]::ToBase64String($bytes)
    # Use canonical header casing; keep the space after the colon for curl/git compatibility
    $authHead = "Authorization: Basic $base64"

    if (Test-Path $TargetPath) {
        $hasGit = Test-Path (Join-Path $TargetPath '.git')
        if ($hasGit) {
            Write-Log "Target path '$TargetPath' already exists and is a git repo; skipping git clone." 'INFO'
            return
        }
        # If the path exists but is not a git repo (e.g., temp folder we just created), remove and recreate
        Remove-Item -Path $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    $gitArgsString = ('-c "http.extraheader={0}" clone "{1}" "{2}"' -f $authHead, $RepositoryUrl, $TargetPath)
    Write-Log ("Running: git {0}" -f $gitArgsString) 'DEBUG'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'git'
    $psi.Arguments              = $gitArgsString
    $psi.EnvironmentVariables['GIT_HTTP_EXTRAHEADER'] = $authHead
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($stdout) { Write-Log $stdout 'DEBUG' }
    if ($stderr) { Write-Log $stderr 'WARN' }

    if ($proc.ExitCode -ne 0) {
        throw "git clone failed for '$RepositoryUrl' (exit $($proc.ExitCode))."
    }

    Write-Log "Successfully cloned '$RepositoryUrl'." 'INFO'
}

function Copy-AdoWikiViaGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceProject,
        [Parameter(Mandatory)][string]$TargetProject,
        [Parameter(Mandatory)][string]$WikiId,
        [pscustomobject]$Config
    )

    # Get the source wiki details
    Write-Warning "[Copy-AdoWikiViaGit] Starting wiki copy from '$SourceProject' to '$TargetProject' (WikiId: $WikiId)..."

    $sourceWikiUrl = "/$([uri]::EscapeDataString($SourceProject))/_apis/wiki/wikis/$WikiId"
    Write-Warning "[Copy-AdoWikiViaGit] Fetching source wiki details from: $sourceWikiUrl"
    $sourceWiki = Invoke-AdoRest GET $sourceWikiUrl

    if (-not $sourceWiki) {
        Write-Warning "[Copy-AdoWikiViaGit] Could not get source wiki details for project '$SourceProject'"
        throw "Could not get source wiki details for project '$SourceProject'"
    }

    $wikiName = $sourceWiki.name
    Write-Warning "[Copy-AdoWikiViaGit] Source wiki name: $wikiName"

    # Derive a usable Git remote URL for cloning.
    # For project wikis, the returned remoteUrl is a UI URL, not a git URL.
    $sourceRemoteUrl = $null
    # Try backing repository first
    if ($sourceWiki.PSObject.Properties['repository']) {
        $repoId = $sourceWiki.repository.id
        Write-Warning "[Copy-AdoWikiViaGit] Source wiki has backing repository (id: $repoId). Fetching repository details..."
        $repoResp = Invoke-AdoRest GET "/_apis/git/repositories/$repoId" -ReturnNullOnNotFound
        if ($repoResp -and $repoResp.remoteUrl) {
            $sourceRemoteUrl = $repoResp.remoteUrl
            Write-Warning "[Copy-AdoWikiViaGit] Found remoteUrl for backing repository: $sourceRemoteUrl"
        } else {
            Write-Warning "[Copy-AdoWikiViaGit] Could not find remoteUrl for backing repository."
        }
    }
    # Fallback: construct git URL from wiki name and project (ensure coreRestConfig is available)
    if (-not $sourceRemoteUrl) {
        Write-Warning "[Copy-AdoWikiViaGit] Backing repository remoteUrl not found. Attempting to construct git URL from wiki name and project."
        $coreRestConfig = Get-CoreRestConfig
        if (-not $coreRestConfig -or -not $coreRestConfig.CollectionUrl) {
            Write-Warning "[Copy-AdoWikiViaGit] Core REST config is not initialized (missing CollectionUrl); cannot construct wiki git URL."
            throw "Core REST config is not initialized (missing CollectionUrl); cannot construct wiki git URL."
        }
        $collectionUrl = ($coreRestConfig.CollectionUrl).TrimEnd('/')
        $projEnc = [uri]::EscapeDataString($SourceProject)
        $repoName = if ($wikiName -like '*.wiki') { $wikiName } else { "$wikiName.wiki" }
        $sourceRemoteUrl = "$collectionUrl/$projEnc/_git/$repoName"
        Write-Warning "[Copy-AdoWikiViaGit] Constructed source remote git URL: $sourceRemoteUrl"
    }

    Write-Warning "[Copy-AdoWikiViaGit] Preparing to clone wiki '$wikiName' from '$SourceProject'..."

    if (-not $Config) {
        Write-Warning "[Copy-AdoWikiViaGit] No config provided. Using default PAT environment variable 'ADO_PAT'."
        $Config = [pscustomobject]@{
            azureDevOps = [pscustomobject]@{
                personalAccessTokenEnvVar = 'ADO_PAT'
            }
        }
    }

    # Create a temporary directory for cloning
    $tempDir = Join-Path $env:TEMP "WikiClone_$([guid]::NewGuid())"
    Write-Warning "[Copy-AdoWikiViaGit] Creating temporary directory for git clone: $tempDir"
    if (Test-Path $tempDir) {
        Write-Warning "[Copy-AdoWikiViaGit] Temporary directory already exists. Removing: $tempDir"
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    $pushed = $false
    try {
        Write-Warning "[Copy-AdoWikiViaGit] Cloning source wiki repository from '$sourceRemoteUrl' into '$tempDir'..."
        Invoke-AdoGitClone -RepositoryUrl $sourceRemoteUrl -TargetPath $tempDir -Config $Config
        Push-Location $tempDir
        $pushed = $true

        # Normalize target repo name to target project wiki
        $targetRepoName = if ($TargetProject -like '*.wiki') { $TargetProject } else { "$TargetProject.wiki" }

        # Resolve target project id for repository creation (avoid project mismatch errors)
        $projInfo = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($TargetProject))?includeCapabilities=false" -ReturnNullOnNotFound
        $targetProjId = $null
        if ($projInfo) {
            if ($projInfo.PSObject.Properties['id']) { $targetProjId = $projInfo.id }
            elseif ($projInfo.PSObject.Properties['value'] -and $projInfo.value.Count -gt 0 -and $projInfo.value[0].PSObject.Properties['id']) { $targetProjId = $projInfo.value[0].id }
        }

        # If a wiki repo already exists on the target, delete it (best effort) or reuse it to avoid conflicts
        $targetRepo = $null
        $targetRemoteUrl = $null
        $existingRepos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($TargetProject))/_apis/git/repositories" -ReturnNullOnNotFound
        $existingList = @()
        if ($existingRepos) {
            if ($existingRepos.PSObject.Properties['value']) {
                $existingList = @($existingRepos.value)
            }
            elseif ($existingRepos -is [System.Array]) {
                $existingList = @($existingRepos)
            }
            elseif ($existingRepos.PSObject.Properties['name']) {
                $existingList = @($existingRepos)
            }
        }

        $existingWikiRepo = $existingList | Where-Object { $_.name -eq $targetRepoName -or $_.name -eq "$targetRepoName.wiki" } | Select-Object -First 1
        if ($existingWikiRepo -and $existingWikiRepo.id) {
            try {
                Write-Warning "[Copy-AdoWikiViaGit] Deleting existing wiki repository '$($existingWikiRepo.name)' in '$TargetProject' before recreation..."
                Invoke-AdoRest DELETE "/_apis/git/repositories/$($existingWikiRepo.id)" | Out-Null
                Start-Sleep -Seconds 2
                # Re-check after delete
                $existingRepos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($TargetProject))/_apis/git/repositories" -ReturnNullOnNotFound
                $existingList = @()
                if ($existingRepos) {
                    if ($existingRepos.PSObject.Properties['value']) { $existingList = @($existingRepos.value) }
                    elseif ($existingRepos -is [System.Array]) { $existingList = @($existingRepos) }
                    elseif ($existingRepos.PSObject.Properties['name']) { $existingList = @($existingRepos) }
                }
                $existingWikiRepo = $existingList | Where-Object { $_.name -eq $targetRepoName -or $_.name -eq "$targetRepoName.wiki" } | Select-Object -First 1
            }
            catch {
                Write-Warning "[Copy-AdoWikiViaGit] Failed to delete existing wiki repository for '$TargetProject': $($_.Exception.Message). Will attempt to reuse the existing repo."
            }
        }

        if ($existingWikiRepo -and $existingWikiRepo.remoteUrl) {
            Write-Warning "[Copy-AdoWikiViaGit] Reusing existing wiki repository '$($existingWikiRepo.name)' for '$TargetProject' (will overwrite with --mirror push)..."
            $targetRepo = $existingWikiRepo
            $targetRemoteUrl = $existingWikiRepo.remoteUrl
        }
        else {
            # Create target git repository
            $repoBody = @{
                name    = $targetRepoName
                project = if ($targetProjId) { @{ id = $targetProjId } } else { @{ name = $TargetProject } }
            } | ConvertTo-Json

            $createRepoUrl = "/$([uri]::EscapeDataString($TargetProject))/_apis/git/repositories"
            Write-Warning "[Copy-AdoWikiViaGit] Creating target git repository for project '$TargetProject' via: $createRepoUrl"
            try {
                $targetRepo = Invoke-AdoRest POST $createRepoUrl -Body $repoBody
            }
            catch {
                Write-Warning "[Copy-AdoWikiViaGit] Repository create returned error: $($_.Exception.Message). Checking for existing repo to reuse..."
                $existingRepos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($TargetProject))/_apis/git/repositories" -ReturnNullOnNotFound
                $existingList = @()
                if ($existingRepos) {
                    if ($existingRepos.PSObject.Properties['value']) { $existingList = @($existingRepos.value) }
                    elseif ($existingRepos -is [System.Array]) { $existingList = @($existingRepos) }
                    elseif ($existingRepos.PSObject.Properties['name']) { $existingList = @($existingRepos) }
                }
                $existingWikiRepo = $existingList | Where-Object { $_.name -eq $targetRepoName -or $_.name -eq "$targetRepoName.wiki" } | Select-Object -First 1

                if ($existingWikiRepo -and $existingWikiRepo.remoteUrl) {
                    Write-Warning "[Copy-AdoWikiViaGit] Repo '$($existingWikiRepo.name)' already exists; reusing it for push instead of creating a new one."
                    $targetRepo = $existingWikiRepo
                    $targetRemoteUrl = $existingWikiRepo.remoteUrl
                }
                else {
                    throw
                }
            }

            if (-not $targetRepo -or -not $targetRepo.remoteUrl) {
                Write-Warning "[Copy-AdoWikiViaGit] Failed to create target repository for project '$TargetProject'"
                throw "Failed to create target repository for project '$TargetProject'"
            }

            $targetRemoteUrl = $targetRepo.remoteUrl
        }
        Write-Warning "[Copy-AdoWikiViaGit] Target repository remote URL: $targetRemoteUrl"

        # Push to target repository
        Write-Warning "[Copy-AdoWikiViaGit] Removing existing 'origin' remote (if any)..."
        & git remote remove origin 2>&1 | Out-Null
        Write-Warning "[Copy-AdoWikiViaGit] Adding new 'origin' remote: $targetRemoteUrl"
        & git remote add origin $targetRemoteUrl 2>&1 | Out-Null
        Write-Warning "[Copy-AdoWikiViaGit] Pushing all refs (--mirror) to target repository..."
        & git push --mirror origin 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "[Copy-AdoWikiViaGit] Failed to push wiki content to target repository '$targetRemoteUrl'"
            throw "Failed to push wiki content to target repository '$targetRemoteUrl'"
        }

        Write-Warning "[Copy-AdoWikiViaGit] Wiki content pushed to target repository successfully."

        # Now create the wiki from the repository (publish code as wiki)
        $wikiBody = @{
            name = "$TargetProject.wiki"
            type = "codeWiki"
            projectId = $targetRepo.project.id
            repositoryId = $targetRepo.id
            mappedPath = "/"
            version = @{
                versionType = "branch"
                version = "main"
            }
        } | ConvertTo-Json

        $createWikiUrl = "/$([uri]::EscapeDataString($TargetProject))/_apis/wiki/wikis"
        Write-Warning "[Copy-AdoWikiViaGit] Creating wiki from repository for project '$TargetProject' via: $createWikiUrl"
        $targetWiki = Invoke-AdoRest POST $createWikiUrl -Body $wikiBody

        if (-not $targetWiki) {
            Write-Warning "[Copy-AdoWikiViaGit] Failed to create wiki from repository for project '$TargetProject'"
            throw "Failed to create wiki from repository for project '$TargetProject'"
        }

        Write-Warning "[Copy-AdoWikiViaGit] Wiki created from repository for project '$TargetProject' successfully."

    }
    catch {
        Write-Warning "[Copy-AdoWikiViaGit] Exception occurred: $($_.Exception.Message)"
        throw
    }
    finally {
        if ($pushed) { 
            Write-Warning "[Copy-AdoWikiViaGit] Restoring previous location after git operations."
            Pop-Location 
        }
        if (Test-Path $tempDir) {
            Write-Warning "[Copy-AdoWikiViaGit] Cleaning up temporary directory: $tempDir"
            Remove-Item $tempDir -Recurse -Force
        }
    }
}


function New-AdoProjectHomeWikiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating project home wiki page..." -ForegroundColor Cyan
    
    try {
        # Load welcome template from Templates module
        $welcomeContent = Get-EmbeddedWikiTemplate -TemplateName "welcome-wiki" -Parameters @{
            PROJECT_NAME = $Project
        }
        
        Set-AdoWikiPage $Project $WikiId "/Home" $welcomeContent
        Write-Host "[SUCCESS] Created project home page" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create project home page: $_"
    }
}

function New-AdoProjectSummaryWikiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$WikiId
    )

    Write-Host "[INFO] Creating Project Summary wiki page..." -ForegroundColor Cyan

    try {
        $proj = Invoke-AdoRest GET "/_apis/projects/$([uri]::EscapeDataString($Project))?includeCapabilities=true"
        # Resolve collection URL for summary links
        $adoUrl = $null
        if (Get-Command -Name Get-AdoBaseUrl -ErrorAction SilentlyContinue) {
            try { $adoUrl = Get-AdoBaseUrl } catch { }
        }
        if (-not $adoUrl) {
            try {
                $coreRestConfig = Get-CoreRestConfig
                if ($coreRestConfig -and $coreRestConfig.CollectionUrl) {
                    $adoUrl = $coreRestConfig.CollectionUrl
                }
            }
            catch { }
        }
        if (-not $adoUrl) {
            Write-Warning "Could not determine Azure DevOps collection URL. Using default https://dev.azure.com."
            $adoUrl = "https://dev.azure.com"
        }

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
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -ReturnNullOnNotFound
        $repoCount = 0
        if ($repos) {
            if ($repos.PSObject.Properties['value']) { $repoCount = $repos.value.Count }
            elseif ($repos -is [System.Array]) { $repoCount = $repos.Count }
        }

    # work item types
    $witypes = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wit/workitemtypes" -ReturnNullOnNotFound
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
    $areas = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/areas" + '?$depth=2') -ReturnNullOnNotFound
        $areaCount = 0
        if ($areas) {
            if ($areas.PSObject.Properties['children'] -and $areas.children) { $areaCount = $areas.children.Count }
            elseif ($areas.PSObject.Properties['value'] -and $areas.value) { $areaCount = ($areas.value | Measure-Object).Count }
            elseif ($areas -is [System.Array]) { $areaCount = $areas.Count }
        }

    $iterations = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/wit/classificationnodes/iterations" + '?$depth=2') -ReturnNullOnNotFound
        $iterationCount = 0
        if ($iterations) {
            if ($iterations.PSObject.Properties['children'] -and $iterations.children) { $iterationCount = $iterations.children.Count }
            elseif ($iterations.PSObject.Properties['value'] -and $iterations.value) { $iterationCount = ($iterations.value | Measure-Object).Count }
            elseif ($iterations -is [System.Array]) { $iterationCount = $iterations.Count }
        }

        # wiki pages
    # Non-retried wiki pages listing to avoid global retry noise for large wiki trees
    $wikiPages = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/wiki/wikis/$WikiId/pages?recursionLevel=full" -ReturnNullOnNotFound -MaxAttempts 1 -DelaySeconds 0
        $wikiPageCount = 0
        if ($wikiPages) {
            if ($wikiPages.PSObject.Properties['subPages'] -and $wikiPages.subPages) { $wikiPageCount = $wikiPages.subPages.Count }
            elseif ($wikiPages.PSObject.Properties['value'] -and $wikiPages.value) { $wikiPageCount = ($wikiPages.value | Measure-Object).Count }
            elseif ($wikiPages -is [System.Array]) { $wikiPageCount = $wikiPages.Count }
        }

    # queries
    $queries = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/wit/queries/Shared%20Queries" + '?$depth=2') -ReturnNullOnNotFound
        $queryCount = 0
        if ($queries) {
            if ($queries.PSObject.Properties['children'] -and $queries.children) { $queryCount = $queries.children.Count }
            elseif ($queries.PSObject.Properties['value'] -and $queries.value) { $queryCount = ($queries.value | Measure-Object).Count }
            elseif ($queries -is [System.Array]) { $queryCount = $queries.Count }
        }

    # dashboards/builds/policies (best-effort)
    try {
        # Prefer team-specific dashboard endpoint when possible to avoid project-level 404s
        $dash = $null
        if (Get-Command -Name Get-AdoDashboardContext -ErrorAction SilentlyContinue) {
            $ctx = Get-AdoDashboardContext -Project $Project -Team "$Project Team"
            if ($ctx -and $ctx.TeamId) {
                $endpoints = Resolve-AdoDashboardEndpoints -Project $Project -Team "$Project Team" -TeamId $ctx.TeamId -ProjectId $ctx.ProjectId
                foreach ($ep in $endpoints) {
                    try { $dash = Invoke-AdoRest GET $ep -Preview -ReturnNullOnNotFound; break } catch { }
                }
            }
        }
        # Fallback to project-level listing if no team context found
        if (-not $dash) { $dash = Invoke-AdoRest GET "/$projEnc/_apis/dashboard/dashboards" -Preview -ReturnNullOnNotFound }
    } catch { $dash = $null }
    $dashboardCount = 0; if ($dash -and $dash.value) { $dashboardCount = $dash.value.Count }
    try { $builddefs = Invoke-AdoRest GET "/$projEnc/_apis/build/definitions" -ReturnNullOnNotFound } catch { $builddefs = $null }
    $buildCount = 0; if ($builddefs -and $builddefs.value) { $buildCount = $builddefs.value.Count }
    try { $pol = Invoke-AdoRest GET "/$projEnc/_apis/policy/configurations" -ReturnNullOnNotFound } catch { $pol = $null }
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
                    $comm = Invoke-AdoRest GET ("/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($r.id)/commits" + '?$top=1') -ReturnNullOnNotFound
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

    # NOTE: Creation of the Project-Summary wiki page has been disabled per configuration.
    # If you want to enable it again, uncomment the Set-AdoWikiPage call below.
    # Set-AdoWikiPage -Project $Project -WikiId $WikiId -Path "/Project-Summary" -Markdown $summary
    Write-Host "[INFO] Skipping creation of Project-Summary wiki page (disabled)" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Warning "Failed to create Project Summary wiki page: $_"
        return $false
    }
}

function New-AdoTagGuidelinesWikiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating tag guidelines wiki page..." -ForegroundColor Cyan
    
    try {
        # Load tag guidelines template from Templates module
        $tagContent = Get-EmbeddedWikiTemplate -TemplateName "TagGuidelines" -Parameters @{
            CURRENT_DATE = (Get-Date -Format 'yyyy-MM-dd')
        }
        
        Set-AdoWikiPage $Project $WikiId "/Tag-Guidelines" $tagContent
        Write-Host "[SUCCESS] Created tag guidelines page" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create tag guidelines page: $_"
    }
}

function Measure-Adorootwiki {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$WikiId
    )
    
    Write-Host "[INFO] Creating root overview wiki page..." -ForegroundColor Cyan
    
    try {
        $content = Get-WikiTemplate "overview.md"
        # Prefix with 00- to keep Overview at the top of the wiki tree
        Set-AdoWikiPageWithRetry $Project $WikiId "/00-Overview" $content | Out-Null
        Write-Host "  ✅ Overview (00-Overview)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to create Overview page: $_"
    }
}

Export-ModuleMember -Function @(
    'Measure-Adoprojectwiki',
    'Set-AdoWikiPage',
    'Set-AdoWikiPageWithRetry',
    'Initialize-AdoProjectWikis',
    'Initialize-AdoProjectWikisEfficient',
    'Invoke-AdoGitClone',
    'Copy-AdoWikiViaGit',
    'New-AdoQAGuidelinesWiki',
    'Measure-Adobestpracticeswiki',
    'Measure-Adobusinesswiki',
    'Measure-Adodevwiki',
    'New-AdoSecurityWiki',
    'Measure-Adomanagementwiki',
    'Measure-Adootherroleswiki',
    'Measure-Adorootwiki',
    'New-AdoProjectHomeWikiPage',
    'New-AdoTagGuidelinesWikiPage',
    'New-AdoProjectSummaryWikiPage'
)






