# Refactor-BusinessWiki-v2.ps1
# Complete refactoring of Ensure-AdoBusinessWiki function using line-by-line processing

$ErrorActionPreference = 'Stop'
$modulePath = ".\modules\AzureDevOps.psm1"

Write-Host "[INFO] Refactoring Ensure-AdoBusinessWiki array..." -ForegroundColor Cyan

# Backup
Copy-Item $modulePath "$modulePath.backup" -Force

try {
    $lines = Get-Content $modulePath
    $newLines = [System.Collections.ArrayList]::new()
    
    # Template mappings (variable name fragment -> template name)
    $templateMap = @{
        'Business-Welcome' = 'Business/BusinessWelcome'
        'Decision-Log' = 'Business/DecisionLog'
        'Risks-Issues' = 'Business/RisksIssues'
        'Glossary' = 'Business/Glossary'
        'Ways-of-Working' = 'Business/WaysOfWorking'
        'KPIs-and-Success' = 'Business/KPIsAndSuccess'
        'Training-Quick-Start' = 'Business/TrainingQuickStart'
        'Communication-Templates' = 'Business/CommunicationTemplates'
        'Cutover-Timeline' = 'Business/CutoverTimeline'
        'Post-Cutover-Summary' = 'Business/PostCutoverSummary'
    }
    
    $inBusinessWiki = $false
    $inHereString = $false
    $currentPath = $null
    $skipMode = $false
    $i = 0
    
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        
        # Detect entering Ensure-AdoBusinessWiki
        if ($line -match '^\s*function Ensure-AdoBusinessWiki') {
            $inBusinessWiki = $true
            Write-Host "  - Found Ensure-AdoBusinessWiki at line $($i+1)" -ForegroundColor Yellow
        }
        
        # Exit the function when we hit the next function
        if ($inBusinessWiki -and $line -match '^\s*function ' -and $line -notmatch 'Ensure-AdoBusinessWiki') {
            $inBusinessWiki = $false
        }
        
        # Process Business wiki lines
        if ($inBusinessWiki) {
            # Check if this line starts an array entry with here-string
            if ($line -match '@\{\s*path\s*=\s*''(/[^'']+)''\s*;\s*content\s*=\s*@"') {
                $currentPath = $matches[1]
                $pathKey = $currentPath.TrimStart('/')
                
                if ($templateMap.ContainsKey($pathKey)) {
                    $templateName = $templateMap[$pathKey]
                    Write-Host "  - Replacing $currentPath -> $templateName" -ForegroundColor Green
                    
                    # Replace with Get-WikiTemplate call
                    $indent = $line -replace '^(\s*).*','$1'
                    $newLine = "${indent}@{ path = '$currentPath'; content = Get-WikiTemplate `"$templateName`" }"
                    
                    # Check if this is the last entry (no comma)
                    # Find the closing "@ } and check if there's a comma after
                    $j = $i + 1
                    while ($j -lt $lines.Count -and $lines[$j] -notmatch '"\@\s*\}') {
                        $j++
                    }
                    
                    # Check if the closing line has a comma
                    if ($j -lt $lines.Count) {
                        $closeLine = $lines[$j]
                        if ($closeLine -match '"\@\s*\}\s*,') {
                            $newLine += ","
                        }
                    }
                    
                    [void]$newLines.Add($newLine)
                    
                    # Skip lines until we find the closing "@
                    $inHereString = $true
                    $skipMode = $true
                }
                else {
                    [void]$newLines.Add($line)
                }
            }
            # Skip here-string content
            elseif ($skipMode -and $line -match '"\@\s*\}') {
                $skipMode = $false
                $inHereString = $false
                # Don't add this line, we already added the replacement
            }
            elseif ($skipMode) {
                # Skip content lines
            }
            else {
                # Keep all other lines
                [void]$newLines.Add($line)
            }
        }
        else {
            # Not in BusinessWiki function, keep line as-is
            [void]$newLines.Add($line)
        }
        
        $i++
    }
    
    # Write back
    $newLines | Set-Content $modulePath -Encoding UTF8
    
    # Count lines removed
    $originalLines = (Get-Content "$modulePath.backup").Count
    $finalLines = $newLines.Count
    $reduction = $originalLines - $finalLines
    
    Write-Host "[SUCCESS] Refactored Business wiki array!" -ForegroundColor Green
    Write-Host "  File size: $originalLines → $finalLines lines (-$reduction lines)" -ForegroundColor Cyan
    
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
