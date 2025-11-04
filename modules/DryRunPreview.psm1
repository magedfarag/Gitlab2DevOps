<#
.SYNOPSIS
    Enhanced dry-run and preview module.

.DESCRIPTION
    Provides comprehensive preview capabilities for migration operations with
    detailed reports, HTML visualization, and -WhatIf support for all operations.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Generates a comprehensive migration preview report.

.DESCRIPTION
    Creates detailed preview of what will happen during migration including:
    - Projects to create
    - Repositories to migrate
    - Policies to apply
    - Size estimates
    - Duration estimates

.PARAMETER GitLabProjects
    Array of GitLab project paths to preview.

.PARAMETER DestinationProject
    Target Azure DevOps project name.

.PARAMETER OutputFormat
    Output format: JSON, HTML, or Console. Default is Console.

.PARAMETER OutputPath
    Optional output file path for JSON/HTML formats.

.OUTPUTS
    Preview report object.

.EXAMPLE
    New-MigrationPreview -GitLabProjects @("group/proj1", "group/proj2") -DestinationProject "MyProject"

.EXAMPLE
    New-MigrationPreview -GitLabProjects @("group/proj1") -DestinationProject "Test" -OutputFormat HTML -OutputPath "preview.html"
#>
function New-MigrationPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$GitLabProjects,
        
        [Parameter(Mandatory)]
        [string]$DestinationProject,
        
        [ValidateSet("Console", "JSON", "HTML")]
        [string]$OutputFormat = "Console",
        
        [string]$OutputPath
    )
    
    Write-Host ""
    Write-Host "=== MIGRATION PREVIEW REPORT ===" -ForegroundColor Cyan
    Write-Host "Analyzing $($GitLabProjects.Count) project(s) for migration..." -ForegroundColor Cyan
    Write-Host ""
    
    $preview = @{
        Timestamp           = Get-Date
        DestinationProject  = $DestinationProject
        SourceProjects      = @()
        TotalSize           = 0
        TotalLfsSize        = 0
        EstimatedDuration   = 0
        Prerequisites       = @()
        Warnings            = @()
        Operations          = @()
    }
    
    # Analyze each project
    foreach ($projectPath in $GitLabProjects) {
        Write-Host "Analyzing: $projectPath" -ForegroundColor Yellow
        
        try {
            # Fetch GitLab project details
            $glProject = Get-GitLabProject -PathWithNamespace $projectPath
            
            $projectPreview = @{
                GitLabPath      = $projectPath
                RepoName        = $glProject.path
                SizeMB          = [math]::Round(($glProject.statistics.repository_size / 1MB), 2)
                LfsSizeMB       = [math]::Round(($glProject.statistics.lfs_objects_size / 1MB), 2)
                DefaultBranch   = $glProject.default_branch
                BranchCount     = 0  # Would need additional API call
                TagCount        = 0  # Would need additional API call
                LfsEnabled      = $glProject.lfs_enabled
                Visibility      = $glProject.visibility
                Operations      = @()
            }
            
            # Estimate duration based on size
            $estimatedMinutes = switch ($projectPreview.SizeMB) {
                { $_ -lt 10 }    { 2 }
                { $_ -lt 50 }    { 5 }
                { $_ -lt 100 }   { 10 }
                { $_ -lt 500 }   { 30 }
                { $_ -lt 1000 }  { 60 }
                default          { 120 }
            }
            
            $projectPreview.EstimatedDurationMinutes = $estimatedMinutes
            
            # Add LFS time if enabled
            if ($projectPreview.LfsEnabled -and $projectPreview.LfsSizeMB -gt 0) {
                $projectPreview.EstimatedDurationMinutes += [math]::Ceiling($projectPreview.LfsSizeMB / 10)
            }
            
            # Define operations
            $projectPreview.Operations = @(
                "Create repository: $($projectPreview.RepoName)",
                "Clone from GitLab: $projectPath",
                "Push to Azure DevOps: $DestinationProject/$($projectPreview.RepoName)",
                "Apply branch policies to: $($projectPreview.DefaultBranch)"
            )
            
            # Add warnings
            if ($projectPreview.SizeMB -gt 500) {
                $preview.Warnings += "⚠️  Large repository: $projectPath ($($projectPreview.SizeMB) MB) - migration may take longer"
            }
            
            if ($projectPreview.LfsEnabled -and $projectPreview.LfsSizeMB -gt 0) {
                $lfsWarning = "ℹ️  Git LFS required for $projectPath (LFS: $($projectPreview.LfsSizeMB) MB)"
                $preview.Warnings += $lfsWarning
                
                if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
                    $preview.Warnings += "❌ Git LFS not installed - required for $projectPath"
                    $preview.Prerequisites += "Install Git LFS: https://git-lfs.github.com/"
                }
            }
            
            $preview.SourceProjects += $projectPreview
            $preview.TotalSize += $projectPreview.SizeMB
            $preview.TotalLfsSize += $projectPreview.LfsSizeMB
            $preview.EstimatedDuration += $projectPreview.EstimatedDurationMinutes
            
            Write-Host "  ✅ $projectPath ($($projectPreview.SizeMB) MB, ~$estimatedMinutes min)" -ForegroundColor Green
        }
        catch {
            Write-Host "  ❌ Failed to analyze: $projectPath" -ForegroundColor Red
            Write-Host "     Error: $_" -ForegroundColor Red
            
            $preview.Warnings += "❌ Cannot access: $projectPath - $_"
        }
    }
    
    # Check Azure DevOps prerequisites
    Write-Host ""
    Write-Host "Checking Azure DevOps prerequisites..." -ForegroundColor Yellow
    
    try {
        $adoProjects = Get-AdoProjectList -UseCache
        $adoProject = $adoProjects | Where-Object { $_.name -eq $DestinationProject }
        
        if ($adoProject) {
            Write-Host "  ✅ Project exists: $DestinationProject" -ForegroundColor Green
            $preview.Operations += "✅ Use existing project: $DestinationProject"
        }
        else {
            Write-Host "  ⚠️  Project does not exist: $DestinationProject" -ForegroundColor Yellow
            $preview.Operations += "⚠️  CREATE project: $DestinationProject"
            $preview.Prerequisites += "Project '$DestinationProject' will be created during migration"
        }
        
        # Check for repository conflicts
        if ($adoProject) {
            $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($DestinationProject))/_apis/git/repositories"
            foreach ($srcProj in $preview.SourceProjects) {
                $existingRepo = $repos.value | Where-Object { $_.name -eq $srcProj.RepoName }
                if ($existingRepo) {
                    $preview.Warnings += "⚠️  Repository already exists: $($srcProj.RepoName) (use -AllowSync to update)"
                }
            }
        }
    }
    catch {
        Write-Host "  ❌ Failed to check Azure DevOps: $_" -ForegroundColor Red
        $preview.Warnings += "❌ Cannot verify Azure DevOps project status"
    }
    
    # Add high-level operations
    $preview.Operations += "Total repositories to migrate: $($preview.SourceProjects.Count)"
    $preview.Operations += "Total data transfer: $($preview.TotalSize) MB"
    if ($preview.TotalLfsSize -gt 0) {
        $preview.Operations += "Total LFS data: $($preview.TotalLfsSize) MB"
    }
    $preview.Operations += "Estimated duration: $($preview.EstimatedDuration) minutes ($([math]::Round($preview.EstimatedDuration / 60, 1)) hours)"
    
    # Output based on format
    switch ($OutputFormat) {
        "Console" {
            Write-MigrationPreviewConsole -Preview $preview
        }
        "JSON" {
            if (-not $OutputPath) {
                $OutputPath = "migration-preview-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            }
            $preview | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host ""
            Write-Host "Preview saved to: $OutputPath" -ForegroundColor Green
        }
        "HTML" {
            if (-not $OutputPath) {
                $OutputPath = "migration-preview-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
            }
            Write-MigrationPreviewHtml -Preview $preview -OutputPath $OutputPath
            Write-Host ""
            Write-Host "HTML preview saved to: $OutputPath" -ForegroundColor Green
            Write-Host "Open in browser to view detailed report" -ForegroundColor Cyan
        }
    }
    
    return $preview
}

<#
.SYNOPSIS
    Writes migration preview to console with formatting.

.DESCRIPTION
    Internal helper to display preview in formatted console output.

.PARAMETER Preview
    Preview object from New-MigrationPreview.

.EXAMPLE
    Write-MigrationPreviewConsole -Preview $preview
#>
function Write-MigrationPreviewConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Preview
    )
    
    Write-Host ""
    Write-Host "=== MIGRATION PREVIEW ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Destination: $($Preview.DestinationProject)" -ForegroundColor White
    Write-Host "Projects: $($Preview.SourceProjects.Count)" -ForegroundColor White
    Write-Host "Total Size: $($Preview.TotalSize) MB" -ForegroundColor White
    if ($Preview.TotalLfsSize -gt 0) {
        Write-Host "LFS Data: $($Preview.TotalLfsSize) MB" -ForegroundColor White
    }
    Write-Host "Estimated Duration: $($Preview.EstimatedDuration) minutes" -ForegroundColor White
    Write-Host ""
    
    if ($Preview.Prerequisites.Count -gt 0) {
        Write-Host "📋 Prerequisites:" -ForegroundColor Yellow
        foreach ($prereq in $Preview.Prerequisites) {
            Write-Host "   $prereq" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    if ($Preview.Warnings.Count -gt 0) {
        Write-Host "⚠️  Warnings:" -ForegroundColor Yellow
        foreach ($warning in $Preview.Warnings) {
            Write-Host "   $warning" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    
    Write-Host "📦 Projects to Migrate:" -ForegroundColor Cyan
    foreach ($proj in $Preview.SourceProjects) {
        Write-Host ""
        Write-Host "  $($proj.GitLabPath) → $($proj.RepoName)" -ForegroundColor White
        Write-Host "    Size: $($proj.SizeMB) MB" -ForegroundColor Gray
        if ($proj.LfsSizeMB -gt 0) {
            Write-Host "    LFS: $($proj.LfsSizeMB) MB" -ForegroundColor Gray
        }
        Write-Host "    Branch: $($proj.DefaultBranch)" -ForegroundColor Gray
        Write-Host "    Estimated: ~$($proj.EstimatedDurationMinutes) minutes" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "=== Operations Summary ===" -ForegroundColor Cyan
    foreach ($op in $Preview.Operations) {
        Write-Host "  $op"
    }
    Write-Host ""
}

<#
.SYNOPSIS
    Generates HTML migration preview report.

.DESCRIPTION
    Creates a detailed HTML report with styling and visualizations.

.PARAMETER Preview
    Preview object from New-MigrationPreview.

.PARAMETER OutputPath
    Output HTML file path.

.EXAMPLE
    Write-MigrationPreviewHtml -Preview $preview -OutputPath "report.html"
#>
function Write-MigrationPreviewHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Preview,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    $timestamp = $Preview.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
    
    # Generate project rows
    $projectRows = $Preview.SourceProjects | ForEach-Object {
        $statusClass = if ($_.SizeMB -gt 500) { "warning" } else { "success" }
        $lfsDisplay = if ($_.LfsSizeMB -gt 0) { "$($_.LfsSizeMB) MB" } else { "None" }
        
        @"
        <tr class="$statusClass">
            <td>$($_.GitLabPath)</td>
            <td>$($_.RepoName)</td>
            <td>$($_.SizeMB) MB</td>
            <td>$lfsDisplay</td>
            <td>$($_.DefaultBranch)</td>
            <td>~$($_.EstimatedDurationMinutes) min</td>
        </tr>
"@
    } | Join-String -Separator "`n"
    
    # Generate warnings
    $warningsHtml = if ($Preview.Warnings.Count -gt 0) {
        $warningItems = $Preview.Warnings | ForEach-Object { "<li>$_</li>" } | Join-String -Separator "`n"
        @"
        <div class="warnings">
            <h3>⚠️ Warnings</h3>
            <ul>
                $warningItems
            </ul>
        </div>
"@
    } else {
        "<p class='success'>✅ No warnings</p>"
    }
    
    # Generate prerequisites
    $prereqHtml = if ($Preview.Prerequisites.Count -gt 0) {
        $prereqItems = $Preview.Prerequisites | ForEach-Object { "<li>$_</li>" } | Join-String -Separator "`n"
        @"
        <div class="prerequisites">
            <h3>📋 Prerequisites</h3>
            <ul>
                $prereqItems
            </ul>
        </div>
"@
    } else {
        ""
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Migration Preview - $($Preview.DestinationProject)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; margin-bottom: 20px; }
        h2 { color: #323130; margin-top: 30px; margin-bottom: 15px; }
        h3 { color: #605e5c; margin-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background: #f3f2f1; padding: 20px; border-radius: 4px; border-left: 4px solid #0078d4; }
        .summary-card h3 { color: #0078d4; font-size: 14px; margin-bottom: 5px; }
        .summary-card p { font-size: 24px; font-weight: bold; color: #323130; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 12px; border-bottom: 1px solid #e1dfdd; }
        tr:hover { background: #f3f2f1; }
        tr.warning { background: #fff4ce; }
        tr.success { background: #dff6dd; }
        .warnings { background: #fff4ce; border-left: 4px solid #ffaa44; padding: 15px; margin: 20px 0; border-radius: 4px; }
        .prerequisites { background: #e1f5fe; border-left: 4px solid #039be5; padding: 15px; margin: 20px 0; border-radius: 4px; }
        .success { color: #107c10; }
        .warning { color: #d83b01; }
        ul { margin-left: 20px; }
        li { margin: 5px 0; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #e1dfdd; color: #605e5c; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Migration Preview Report</h1>
        <p><strong>Generated:</strong> $timestamp</p>
        <p><strong>Destination Project:</strong> $($Preview.DestinationProject)</p>
        
        <h2>Summary</h2>
        <div class="summary">
            <div class="summary-card">
                <h3>Projects</h3>
                <p>$($Preview.SourceProjects.Count)</p>
            </div>
            <div class="summary-card">
                <h3>Total Size</h3>
                <p>$($Preview.TotalSize) MB</p>
            </div>
            <div class="summary-card">
                <h3>LFS Data</h3>
                <p>$($Preview.TotalLfsSize) MB</p>
            </div>
            <div class="summary-card">
                <h3>Estimated Duration</h3>
                <p>$($Preview.EstimatedDuration) min</p>
            </div>
        </div>
        
        $prereqHtml
        $warningsHtml
        
        <h2>Projects to Migrate</h2>
        <table>
            <thead>
                <tr>
                    <th>GitLab Path</th>
                    <th>Repository Name</th>
                    <th>Size</th>
                    <th>LFS</th>
                    <th>Default Branch</th>
                    <th>Est. Duration</th>
                </tr>
            </thead>
            <tbody>
                $projectRows
            </tbody>
        </table>
        
        <div class="footer">
            <p><strong>GitLab to Azure DevOps Migration Tool</strong> v2.0.0</p>
            <p>This is a preview report. Actual migration times may vary based on network conditions and repository complexity.</p>
        </div>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $OutputPath -Encoding UTF8
}

Export-ModuleMember -Function @(
    'New-MigrationPreview'
)
