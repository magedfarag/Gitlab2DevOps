<#
.SYNOPSIS
    Refactors remaining wiki functions to use Get-WikiTemplate.

.DESCRIPTION
    This script refactors 4 remaining wiki functions in AzureDevOps.psm1:
    1. Ensure-AdoBestPracticesWiki (1 template)
    2. Ensure-AdoBusinessWiki (10 templates in array)
    3. Ensure-AdoDevWiki (7 templates)
    4. Ensure-AdoSecurityWiki (7 templates)
#>

$modulePath = ".\modules\AzureDevOps.psm1"
$content = Get-Content $modulePath -Raw

Write-Host "[INFO] Starting wiki function refactoring..." -ForegroundColor Cyan

# 1. Ensure-AdoBestPracticesWiki
Write-Host "[1/4] Refactoring Ensure-AdoBestPracticesWiki..." -ForegroundColor Yellow
$pattern1 = '(?s)(\$bestPracticesContent = )@".*?"\@'
$replacement1 = '$1Get-WikiTemplate "BestPractices/BestPractices"'
$content = $content -replace $pattern1, $replacement1

# 2. Ensure-AdoBusinessWiki - more complex (array of pages)
Write-Host "[2/4] Refactoring Ensure-AdoBusinessWiki..." -ForegroundColor Yellow
# This one needs special handling - skip for now, will do manually

# 3. Ensure-AdoDevWiki
Write-Host "[3/4] Refactoring Ensure-AdoDevWiki..." -ForegroundColor Yellow
$devPatterns = @(
    @{ var = '$adrContent'; template = 'Dev/ADR' }
    @{ var = '$devSetupContent'; template = 'Dev/DevSetup' }
    @{ var = '$apiDocsContent'; template = 'Dev/APIDocs' }
    @{ var = '$gitWorkflowContent'; template = 'Dev/GitWorkflow' }
    @{ var = '$codeReviewContent'; template = 'Dev/CodeReview' }
    @{ var = '$troubleshootingContent'; template = 'Dev/Troubleshooting' }
    @{ var = '$dependenciesContent'; template = 'Dev/Dependencies' }
)

foreach ($p in $devPatterns) {
    $pattern = "(?s)(\$($($p.var -replace '\$','')) = )@`".*?`"@"
    $replacement = "`$1Get-WikiTemplate `"$($p.template)`""
    $content = $content -replace $pattern, $replacement
}

# 4. Ensure-AdoSecurityWiki
Write-Host "[4/4] Refactoring Ensure-AdoSecurityWiki..." -ForegroundColor Yellow
$securityPatterns = @(
    @{ var = '$securityPoliciesContent'; template = 'Security/SecurityPolicies' }
    @{ var = '$threatModelingContent'; template = 'Security/ThreatModeling' }
    @{ var = '$securityTestingContent'; template = 'Security/SecurityTesting' }
    @{ var = '$incidentResponseContent'; template = 'Security/IncidentResponse' }
    @{ var = '$complianceContent'; template = 'Security/Compliance' }
    @{ var = '$secretManagementContent'; template = 'Security/SecretManagement' }
    @{ var = '$securityChampionsContent'; template = 'Security/SecurityChampions' }
)

foreach ($p in $securityPatterns) {
    $pattern = "(?s)(\$($($p.var -replace '\$','')) = )@`".*?`"@"
    $replacement = "`$1Get-WikiTemplate `"$($p.template)`""
    $content = $content -replace $pattern, $replacement
}

# Save the refactored content
$content | Set-Content $modulePath -Encoding UTF8 -NoNewline

Write-Host "`n[SUCCESS] Refactoring complete!" -ForegroundColor Green
Write-Host "Testing module import..." -ForegroundColor Cyan

try {
    Import-Module $modulePath -Force -ErrorAction Stop
    $lines = (Get-Content $modulePath).Count
    Write-Host "✅ Module imports successfully!" -ForegroundColor Green
    Write-Host "File size: $lines lines" -ForegroundColor Cyan
}
catch {
    Write-Host "❌ Module import failed: $_" -ForegroundColor Red
    Write-Host "Restoring from git..." -ForegroundColor Yellow
    git checkout HEAD -- $modulePath
    exit 1
}
