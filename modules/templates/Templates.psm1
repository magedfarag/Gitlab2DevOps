<#
.SYNOPSIS
    Template loading utilities for GitLab to Azure DevOps migration.

.DESCRIPTION
    Centralized template management for WIQL queries, wiki content,
    HTML reports, and other template-based content. Supports fallback
    from external files to embedded content.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Loads a WIQL query template with parameter substitution.

.DESCRIPTION
    Loads WIQL query from template file with support for parameter placeholders.
    Falls back to embedded queries if template file not found.

.PARAMETER QueryName
    Name of the WIQL query template (without .wiql extension).

.PARAMETER Parameters
    Hashtable of parameters to substitute in the query.

.OUTPUTS
    WIQL query string with parameters substituted.

.EXAMPLE
    Get-WiqlTemplate -QueryName "my-active-work" -Parameters @{ project = "MyProject" }
#>
function Get-WiqlTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$QueryName,
        
        [hashtable]$Parameters = @{}
    )
    
    # Try to load from template file
    $templatePath = Join-Path $PSScriptRoot "templates\wiql\$QueryName.wiql"
    $wiql = $null
    
    if (Test-Path $templatePath) {
        try {
            $wiql = Get-Content -Path $templatePath -Raw
            Write-Verbose "[Get-WiqlTemplate] Loaded from file: $templatePath"
        }
        catch {
            Write-Warning "[Get-WiqlTemplate] Failed to load template file '$templatePath': $_"
        }
    }
    
    # Fallback to embedded templates
    if (-not $wiql) {
        $embeddedTemplates = @{
            'my-active-work' = @"
SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo], [Microsoft.VSTS.Scheduling.StoryPoints]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.AssignedTo] = @Me
  AND [System.State] <> 'Closed'
  AND [System.State] <> 'Removed'
ORDER BY [System.ChangedDate] DESC
"@
            'team-backlog' = @"
SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.AssignedTo], [Microsoft.VSTS.Scheduling.StoryPoints]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] IN ('User Story', 'Bug', 'Task', 'Feature')
  AND [System.State] IN ('New', 'Active', 'Approved')
ORDER BY [Microsoft.VSTS.Common.BacklogPriority] ASC
"@
            'active-bugs' = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.CreatedDate], [Microsoft.VSTS.Common.Priority], [Microsoft.VSTS.Common.Severity]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.WorkItemType] = 'Bug'
  AND [System.State] IN ('New', 'Active', 'Approved')
ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.CreatedDate] DESC
"@
            'ready-for-review' = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.CreatedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.Tags] CONTAINS 'needs-review'
  AND [System.State] IN ('Active', 'Resolved')
ORDER BY [System.CreatedDate] ASC
"@
            'blocked-items' = @"
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo], [System.CreatedDate]
FROM WorkItems
WHERE [System.TeamProject] = @project
  AND [System.Tags] CONTAINS 'blocked'
  AND [System.State] IN ('New', 'Active')
ORDER BY [System.CreatedDate] ASC
"@
        }
        
        if ($embeddedTemplates.ContainsKey($QueryName)) {
            $wiql = $embeddedTemplates[$QueryName]
            Write-Verbose "[Get-WiqlTemplate] Using embedded template for: $QueryName"
        } else {
            Write-Warning "[Get-WiqlTemplate] Template '$QueryName' not found in files or embedded templates"
            return $null
        }
    }
    
    # Substitute parameters
    if ($Parameters.Count -gt 0) {
        foreach ($key in $Parameters.Keys) {
            $placeholder = "@$key"
            $wiql = $wiql -replace [regex]::Escape($placeholder), $Parameters[$key]
        }
    }
    
    return $wiql
}

<#
.SYNOPSIS
    Loads a wiki template with parameter substitution.

.DESCRIPTION
    Loads wiki content from markdown template file with support for 
    parameter placeholders and fallback to embedded content.

.PARAMETER TemplateName
    Name of the wiki template (with or without .md extension).

.PARAMETER Parameters
    Hashtable of parameters to substitute in the template.

.PARAMETER CustomDirectory
    Optional custom directory to search for templates.

.OUTPUTS
    Wiki content string with parameters substituted.

.EXAMPLE
    Get-WikiTemplate -TemplateName "welcome-page" -Parameters @{ PROJECT_NAME = "MyProject" }
#>
function Get-WikiTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,
        
        [hashtable]$Parameters = @{},
        
        [string]$CustomDirectory = $null
    )
    
    # Ensure .md extension
    if (-not $TemplateName.EndsWith('.md')) {
        $TemplateName += '.md'
    }
    
    $content = $null
    
    # Try custom directory first
    if ($CustomDirectory -and (Test-Path $CustomDirectory)) {
        $customPath = Join-Path $CustomDirectory $TemplateName
        if (Test-Path $customPath) {
            try {
                $content = Get-Content -Path $customPath -Raw -Encoding UTF8
                Write-Verbose "[Get-WikiTemplate] Loaded from custom directory: $customPath"
            }
            catch {
                Write-Warning "[Get-WikiTemplate] Failed to load custom template '$customPath': $_"
            }
        }
    }
    
    # Try default templates directory
    if (-not $content) {
        $defaultPath = Join-Path $PSScriptRoot "templates\$TemplateName"
        if (Test-Path $defaultPath) {
            try {
                $content = Get-Content -Path $defaultPath -Raw -Encoding UTF8
                Write-Verbose "[Get-WikiTemplate] Loaded from default directory: $defaultPath"
            }
            catch {
                Write-Warning "[Get-WikiTemplate] Failed to load default template '$defaultPath': $_"
            }
        }
    }
    
    # Fallback to embedded templates
    if (-not $content) {
        $embeddedTemplates = @{
            'welcome-page.md' = @"
# Welcome to {{PROJECT_NAME}}

This project was migrated from GitLab using automated tooling.

## Project Structure

- **Frontend**: Web UI components
- **Backend**: API and services  
- **Infrastructure**: DevOps and deployment
- **Documentation**: Technical docs and guides

## Getting Started

1. Clone the repository
2. Review branch policies
3. Check work item templates
4. Explore the wiki for team guidelines

## Quick Links

- [Team Dashboard]({{DASHBOARD_URL}})
- [Work Items]({{WORKITEMS_URL}})
- [Repository]({{REPOSITORY_URL}})
- [Build Pipelines]({{PIPELINES_URL}})
"@
            'tag-guidelines.md' = @"
# Tag Guidelines

## Standard Tags

Use these tags to categorize work items consistently:

### Priority Tags
- **P0**: Critical/Blocking
- **P1**: High Priority  
- **P2**: Medium Priority
- **P3**: Low Priority

### Status Tags
- **needs-review**: Ready for code review
- **blocked**: Cannot proceed
- **in-progress**: Actively being worked on

### Type Tags
- **feature**: New functionality
- **bug**: Defect or issue
- **techdebt**: Technical debt
- **refactor**: Code improvement

## Best Practices

- Use consistent tag naming (lowercase, hyphen-separated)
- Review and update tags during sprint planning
- Remove obsolete tags when work is completed
- Use tags for filtering and reporting
"@
        }
        
        if ($embeddedTemplates.ContainsKey($TemplateName)) {
            $content = $embeddedTemplates[$TemplateName]
            Write-Verbose "[Get-WikiTemplate] Using embedded template for: $TemplateName"
        } else {
            Write-Warning "[Get-WikiTemplate] Template '$TemplateName' not found in files or embedded templates"
            return "# $TemplateName`n`nTemplate not available."
        }
    }
    
    # Substitute parameters
    if ($content -and $Parameters.Count -gt 0) {
        foreach ($key in $Parameters.Keys) {
            $placeholder = "{{$key}}"
            $content = $content -replace [regex]::Escape($placeholder), $Parameters[$key]
        }
    }
    
    return $content
}

<#
.SYNOPSIS
    Loads an HTML template with parameter substitution.

.DESCRIPTION
    Loads HTML template from file with support for parameter placeholders.
    Used for generating migration status reports and dashboards.

.PARAMETER TemplateName
    Name of the HTML template (with or without .html extension).

.PARAMETER Parameters
    Hashtable of parameters to substitute in the template.

.OUTPUTS
    HTML content string with parameters substituted.

.EXAMPLE
    Get-HtmlTemplate -TemplateName "migration-status" -Parameters @{ REPORT_TITLE = "Migration Status" }
#>
function Get-HtmlTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,
        
        [hashtable]$Parameters = @{}
    )
    
    # Ensure .html extension
    if (-not $TemplateName.EndsWith('.html')) {
        $TemplateName += '.html'
    }
    
    # Try to load from template file
    $templatePath = Join-Path $PSScriptRoot "templates\$TemplateName"
    
    if (-not (Test-Path $templatePath)) {
        Write-Warning "[Get-HtmlTemplate] Template not found: $templatePath"
        return $null
    }
    
    try {
        $content = Get-Content -Path $templatePath -Raw -Encoding UTF8
        Write-Verbose "[Get-HtmlTemplate] Loaded HTML template: $templatePath"
    }
    catch {
        Write-Warning "[Get-HtmlTemplate] Failed to load HTML template '$templatePath': $_"
        return $null
    }
    
    # Substitute parameters
    if ($Parameters.Count -gt 0) {
        foreach ($key in $Parameters.Keys) {
            $placeholder = "{{$key}}"
            $content = $content -replace [regex]::Escape($placeholder), $Parameters[$key]
        }
    }
    
    return $content
}

Export-ModuleMember -Function @(
    'Get-WiqlTemplate',
    'Get-WikiTemplate', 
    'Get-HtmlTemplate'
)