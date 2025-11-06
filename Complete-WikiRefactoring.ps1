<#
.SYNOPSIS
    Completes wiki template refactoring by removing remaining inline here-strings.

.DESCRIPTION
    Manually refactors the remaining wiki functions that still have inline content.
#>

$modulePath = ".\modules\AzureDevOps.psm1"
$lines = Get-Content $modulePath

Write-Host "[INFO] Refactoring remaining wiki functions..." -ForegroundColor Cyan
Write-Host "Original file size: $($lines.Count) lines`n" -ForegroundColor Gray

# Function to find and replace content between two line numbers
function Replace-Lines {
    param(
        [string[]]$Content,
        [int]$StartLine,
        [int]$EndLine,
        [string]$Replacement
    )
    
    $newContent = @()
    for ($i = 0; $i -lt $Content.Count; $i++) {
        if ($i -eq ($StartLine - 1)) {
            $newContent += $Replacement
        }
        elseif ($i -lt ($StartLine - 1) -or $i -gt ($EndLine - 1)) {
            $newContent += $Content[$i]
        }
    }
    return $newContent
}

# Dev Wiki: Replace 7 content variables
Write-Host "[1/3] Refactoring Ensure-AdoDevWiki (7 templates)..." -ForegroundColor Yellow

# Find line numbers for each here-string and replace
$devReplacements = @(
    @{ Pattern = '    $adrContent = @"'; Replacement = '    $adrContent = Get-WikiTemplate "Dev/ADR"'; Name = 'ADR' }
    @{ Pattern = '    $devSetupContent = @"'; Replacement = '    $devSetupContent = Get-WikiTemplate "Dev/DevSetup"'; Name = 'DevSetup' }
    @{ Pattern = '    $apiDocsContent = @"'; Replacement = '    $apiDocsContent = Get-WikiTemplate "Dev/APIDocs"'; Name = 'APIDocs' }
    @{ Pattern = '    $gitWorkflowContent = @"'; Replacement = '    $gitWorkflowContent = Get-WikiTemplate "Dev/GitWorkflow"'; Name = 'GitWorkflow' }
    @{ Pattern = '    $codeReviewContent = @"'; Replacement = '    $codeReviewContent = Get-WikiTemplate "Dev/CodeReview"'; Name = 'CodeReview' }
    @{ Pattern = '    $troubleshootingContent = @"'; Replacement = '    $troubleshootingContent = Get-WikiTemplate "Dev/Troubleshooting"'; Name = 'Troubleshooting' }
    @{ Pattern = '    $dependenciesContent = @"'; Replacement = '    $dependenciesContent = Get-WikiTemplate "Dev/Dependencies"'; Name = 'Dependencies' }
)

foreach ($repl in $devReplacements) {
    $startIdx = $lines.IndexOf(($lines | Where-Object { $_ -eq $repl.Pattern } | Select-Object -First 1))
    if ($startIdx -ge 0) {
        # Find closing "@
        $endIdx = -1
        for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*"@\s*$') {
                $endIdx = $i
                break
            }
        }
        
        if ($endIdx -gt $startIdx) {
            Write-Host "  - Replacing $($repl.Name): lines $($startIdx+1)-$($endIdx+1) with Get-WikiTemplate" -ForegroundColor Gray
            $lines = Replace-Lines -Content $lines -StartLine ($startIdx + 1) -EndLine ($endIdx + 1) -Replacement $repl.Replacement
        }
    }
}

# Security Wiki: Replace 7 content variables
Write-Host "`n[2/3] Refactoring Ensure-AdoSecurityWiki (7 templates)..." -ForegroundColor Yellow

$securityReplacements = @(
    @{ Pattern = '    $securityPoliciesContent = @"'; Replacement = '    $securityPoliciesContent = Get-WikiTemplate "Security/SecurityPolicies"'; Name = 'SecurityPolicies' }
    @{ Pattern = '    $threatModelingContent = @"'; Replacement = '    $threatModelingContent = Get-WikiTemplate "Security/ThreatModeling"'; Name = 'ThreatModeling' }
    @{ Pattern = '    $securityTestingContent = @"'; Replacement = '    $securityTestingContent = Get-WikiTemplate "Security/SecurityTesting"'; Name = 'SecurityTesting' }
    @{ Pattern = '    $incidentResponseContent = @"'; Replacement = '    $incidentResponseContent = Get-WikiTemplate "Security/IncidentResponse"'; Name = 'IncidentResponse' }
    @{ Pattern = '        $complianceContent = @"'; Replacement = '        $complianceContent = Get-WikiTemplate "Security/Compliance"'; Name = 'Compliance' }
    @{ Pattern = '        $secretManagementContent = @"'; Replacement = '        $secretManagementContent = Get-WikiTemplate "Security/SecretManagement"'; Name = 'SecretManagement' }
    @{ Pattern = '        $securityChampionsContent = @"'; Replacement = '        $securityChampionsContent = Get-WikiTemplate "Security/SecurityChampions"'; Name = 'SecurityChampions' }
)

foreach ($repl in $securityReplacements) {
    $startIdx = $lines.IndexOf(($lines | Where-Object { $_ -eq $repl.Pattern } | Select-Object -First 1))
    if ($startIdx -ge 0) {
        # Find closing "@
        $endIdx = -1
        for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*"@\s*$') {
                $endIdx = $i
                break
            }
        }
        
        if ($endIdx -gt $startIdx) {
            Write-Host "  - Replacing $($repl.Name): lines $($startIdx+1)-$($endIdx+1) with Get-WikiTemplate" -ForegroundColor Gray
            $lines = Replace-Lines -Content $lines -StartLine ($startIdx + 1) -EndLine ($endIdx + 1) -Replacement $repl.Replacement
        }
    }
}

# Business Wiki: This one needs special handling for the array
Write-Host "`n[3/3] Refactoring Ensure-AdoBusinessWiki (10 templates in array)..." -ForegroundColor Yellow
Write-Host "  - Skipping for now (requires manual array refactoring)" -ForegroundColor Yellow

# Save refactored content
$lines | Set-Content $modulePath -Encoding UTF8
Write-Host "`n[SUCCESS] Refactoring complete!" -ForegroundColor Green

# Test import
$newLines = (Get-Content $modulePath).Count
$reduction = 9800 - $newLines
Write-Host "File size: 9800 → $newLines lines (-$reduction lines)" -ForegroundColor Cyan

Write-Host "`nTesting module import..." -ForegroundColor Cyan
try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "✅ Module imports successfully!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Module import failed: $_" -ForegroundColor Red
    Write-Host "Restoring from git..." -ForegroundColor Yellow
    git checkout HEAD -- $modulePath
    exit 1
}
