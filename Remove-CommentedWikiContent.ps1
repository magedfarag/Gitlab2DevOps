# Clean up commented wiki content
$file = ".\modules\AzureDevOps.psm1"
$lines = Get-Content $file

Write-Host "[INFO] Original line count: $($lines.Count)" -ForegroundColor Cyan

# Find and mark ranges to remove
$inComment = $false
$toRemove = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    
    # Start of comment block
    if ($line -match '^\s+<# OLD INLINE CONTENT' -or $line -match '^\s+<# \$securityPoliciesContent') {
        $inComment = $true
        $toRemove += $i
    }
    # End of comment block
    elseif ($inComment -and $line -match '^\s+#>') {
        $toRemove += $i
        $inComment = $false
    }
    # Lines inside comment block
    elseif ($inComment) {
        $toRemove += $i
    }
}

Write-Host "[INFO] Lines to remove: $($toRemove.Count)" -ForegroundColor Gray

# Remove lines (in reverse order to preserve indices)
$newLines = for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -notin $toRemove) {
        $lines[$i]
    }
}

# Write back
$newLines | Out-File -FilePath $file -Encoding UTF8
Write-Host "[SUCCESS] New line count: $($newLines.Count)" -ForegroundColor Green
Write-Host "[SUCCESS] Removed: $($lines.Count - $newLines.Count) lines" -ForegroundColor Green
