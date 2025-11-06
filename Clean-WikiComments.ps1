<#
.SYNOPSIS
    Safely removes commented wiki content from AzureDevOps.psm1 while preserving function structure.
#>

param(
    [string]$FilePath = ".\modules\AzureDevOps.psm1"
)

Write-Host "[INFO] Safely removing commented wiki content from $FilePath..." -ForegroundColor Cyan

$content = Get-Content $FilePath -Raw
$originalLength = $content.Length

# Define specific comment blocks to remove (with very specific patterns)
$patterns = @(
    # QA Guidelines wiki (lines 2368-2806)
    '(?s)(\$qaGuidelinesContent = Get-WikiTemplate -TemplateName "QA/QAGuidelines"\r?\n\r?\n)    <# OLD INLINE CONTENT - REPLACED WITH TEMPLATE\r?\n    \$qaGuidelinesContent = @".*?"\@\r?\n    #>\r?\n',
    
    # Best Practices wiki (lines 3585-4109)
    '(?s)(\$bestPracticesContent = Get-WikiTemplate -TemplateName "BestPractices/BestPractices"\r?\n\r?\n)    <# OLD INLINE CONTENT - REPLACED WITH TEMPLATE\r?\n    \$bestPracticesContent = @".*?"\@\r?\n    #>\r?\n',
    
    # Business Wiki (lines 4176-4279)
    '(?s)(\$pages = @\([^)]+\)\r?\n)    \r?\n    <# OLD INLINE CONTENT - REPLACED WITH TEMPLATES\r?\n    \$pages = @\(.*?"\@ \}\r?\n    \)\r?\n    #>\r?\n',
    
    # Dev Wiki (lines 4788-6766)
    '(?s)(\$dependenciesContent = Get-WikiTemplate -TemplateName "Dev/Dependencies"\r?\n\r?\n)    <# OLD INLINE CONTENT - REPLACED WITH TEMPLATES\r?\n    # Architecture Decision Records\r?\n    \$adrContent = @".*?"\@\r?\n    #>\r?\n',
    
    # Security Wiki (lines 7155-9640) - This one is special, it's already just a comment marker
    '(?s)    <# \$securityPoliciesContent = @".*?"\@\r?\n    #>\r?\n'
)

$removed = 0
$savedBytes = 0

foreach ($pattern in $patterns) {
    if ($content -match $pattern) {
        $match = $matches[0]
        $savedBytes += $match.Length
        $content = $content -replace $pattern, '$1'
        $removed++
        Write-Host "  ✅ Removed comment block ($($match.Length) chars)" -ForegroundColor Green
    }
}

# Write cleaned content back
$content | Out-File -FilePath $FilePath -Encoding UTF8 -NoNewline

$newLength = $content.Length
$reduction = [math]::Round((($originalLength - $newLength) / $originalLength) * 100, 1)

Write-Host ""
Write-Host "[SUCCESS] Cleanup complete!" -ForegroundColor Green
Write-Host "  Removed: $removed comment blocks" -ForegroundColor Gray
Write-Host "  Saved: $([math]::Round($savedBytes / 1KB, 1)) KB" -ForegroundColor Gray
Write-Host "  Reduction: $reduction%" -ForegroundColor Gray

# Verify syntax
Write-Host ""
Write-Host "[INFO] Verifying PowerShell syntax..." -ForegroundColor Cyan
$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $FilePath -Raw), [ref]$errors)
if ($errors) {
    Write-Host "[ERROR] Syntax errors found:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red }
    Write-Host "[ERROR] Reverting changes..." -ForegroundColor Red
    git checkout HEAD -- $FilePath
} else {
    Write-Host "[SUCCESS] No syntax errors detected!" -ForegroundColor Green
    
    # Show line count
    $lines = (Get-Content $FilePath).Count
    Write-Host "[INFO] Current line count: $lines" -ForegroundColor Cyan
}
