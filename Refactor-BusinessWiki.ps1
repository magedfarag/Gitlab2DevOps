# Refactor-BusinessWiki.ps1
# Specialized script to refactor Ensure-AdoBusinessWiki array structure

$ErrorActionPreference = 'Stop'
$modulePath = ".\modules\AzureDevOps.psm1"

Write-Host "[INFO] Refactoring Ensure-AdoBusinessWiki array..." -ForegroundColor Cyan

# Backup
Copy-Item $modulePath "$modulePath.backup" -Force

try {
    $content = Get-Content $modulePath -Raw
    
    # Template mappings (path -> template name)
    $templateMap = @{
        '/Business-Welcome' = 'Business/BusinessWelcome'
        '/Decision-Log' = 'Business/DecisionLog'
        '/Risks-Issues' = 'Business/RisksIssues'
        '/Glossary' = 'Business/Glossary'
        '/Ways-of-Working' = 'Business/WaysOfWorking'
        '/KPIs-and-Success' = 'Business/KPIsAndSuccess'
        '/Training-Quick-Start' = 'Business/TrainingQuickStart'
        '/Communication-Templates' = 'Business/CommunicationTemplates'
        '/Cutover-Timeline' = 'Business/CutoverTimeline'
        '/Post-Cutover-Summary' = 'Business/PostCutoverSummary'
    }
    
    # Process each template
    foreach ($path in $templateMap.Keys) {
        $templateName = $templateMap[$path]
        Write-Host "  - Processing: $path -> $templateName" -ForegroundColor Yellow
        
        # Pattern: @{ path = '/Path'; content = @"
        # ... content ...
        # "@ }
        $pattern = [regex]::Escape("@{ path = '$path'; content = @`"") + 
                   ".*?" + 
                   [regex]::Escape("`"@ }")
        
        $replacement = "@{ path = '$path'; content = Get-WikiTemplate `"$templateName`" }"
        
        # Use RegexOptions.Singleline to match across newlines
        $content = [regex]::Replace($content, $pattern, $replacement, 
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }
    
    # Write back
    $content | Set-Content $modulePath -NoNewline -Encoding UTF8
    
    # Count lines removed
    $originalLines = (Get-Content "$modulePath.backup").Count
    $newLines = (Get-Content $modulePath).Count
    $reduction = $originalLines - $newLines
    
    Write-Host "[SUCCESS] Refactored Business wiki array!" -ForegroundColor Green
    Write-Host "  File size: $originalLines → $newLines lines (-$reduction lines)" -ForegroundColor Cyan
    
    # Test import
    Write-Host "`nTesting module import..." -ForegroundColor Yellow
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "✅ Module imports successfully!" -ForegroundColor Green
    
    # Remove backup on success
    Remove-Item "$modulePath.backup" -Force
    
    Write-Host "`n[NEXT] Run: git add modules/AzureDevOps.psm1 && git commit -m 'refactor: Complete Business wiki template extraction'" -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] Refactoring failed: $_" -ForegroundColor Red
    Write-Host "Restoring backup..." -ForegroundColor Yellow
    Copy-Item "$modulePath.backup" $modulePath -Force
    Remove-Item "$modulePath.backup" -Force
    throw
}
