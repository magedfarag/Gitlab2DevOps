# Example: Using Custom Configuration Files
# This script demonstrates how to use custom configuration files for project initialization

# Import the ConfigLoader module
Import-Module .\modules\core\ConfigLoader.psm1

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Custom Configuration Example                            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Example 1: Load default configurations
Write-Host "Example 1: Loading Default Configurations" -ForegroundColor Yellow
Write-Host "==========================================`n" -ForegroundColor Yellow

$projectSettings = Get-ProjectSettings
$branchPolicies = Get-BranchPolicySettings

Write-Host "Project Areas:" -ForegroundColor Cyan
$projectSettings.areas | ForEach-Object {
    Write-Host "  • $($_.name): $($_.description)" -ForegroundColor White
}

Write-Host "`nSprint Configuration:" -ForegroundColor Cyan
Write-Host "  • Count: $($projectSettings.iterations.sprintCount)" -ForegroundColor White
Write-Host "  • Duration: $($projectSettings.iterations.sprintDurationDays) days" -ForegroundColor White
Write-Host "  • Process: $($projectSettings.processTemplate)" -ForegroundColor White

Write-Host "`nBranch Policy Configuration:" -ForegroundColor Cyan
Write-Host "  • Min Reviewers: $($branchPolicies.branchPolicies.requiredReviewers.minimumApproverCount)" -ForegroundColor White
Write-Host "  • Work Item Linking: $($branchPolicies.branchPolicies.workItemLinking.enabled)" -ForegroundColor White
Write-Host "  • Comment Resolution: $($branchPolicies.branchPolicies.commentResolution.enabled)" -ForegroundColor White

# Example 2: Create a custom configuration
Write-Host "`n`nExample 2: Creating Custom Configuration" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Yellow

# Get default settings
$customSettings = Get-DefaultProjectSettings

# Modify areas for a mobile-focused project
$customSettings.areas = @(
    @{ name = "iOS"; description = "iOS mobile application" },
    @{ name = "Android"; description = "Android mobile application" },
    @{ name = "Backend"; description = "API and services" },
    @{ name = "DevOps"; description = "CI/CD and infrastructure" }
)

# Change to Scrum process
$customSettings.processTemplate = "Scrum"

# Shorter sprints
$customSettings.iterations.sprintCount = 8
$customSettings.iterations.sprintDurationDays = 10

Write-Host "Custom Configuration Created:" -ForegroundColor Cyan
Write-Host "  • Process: $($customSettings.processTemplate)" -ForegroundColor White
Write-Host "  • Areas: $($customSettings.areas.Count)" -ForegroundColor White
foreach ($area in $customSettings.areas) {
    Write-Host "    - $($area.name)" -ForegroundColor Gray
}

# Export to file
Export-ProjectSettings -Settings $customSettings -OutputPath "examples\mobile-project-settings.json"

# Example 3: Relaxed branch policies for small team
Write-Host "`n`nExample 3: Relaxed Branch Policies (Small Team)" -ForegroundColor Yellow
Write-Host "===============================================`n" -ForegroundColor Yellow

$relaxedPolicies = Get-DefaultBranchPolicySettings

# Only require 1 reviewer
$relaxedPolicies.branchPolicies.requiredReviewers.minimumApproverCount = 1

# Make work item linking non-blocking (warning only)
$relaxedPolicies.branchPolicies.workItemLinking.isBlocking = $false

# Disable comment resolution requirement
$relaxedPolicies.branchPolicies.commentResolution.enabled = $false

Write-Host "Relaxed Policy Configuration:" -ForegroundColor Cyan
Write-Host "  • Min Reviewers: $($relaxedPolicies.branchPolicies.requiredReviewers.minimumApproverCount)" -ForegroundColor White
Write-Host "  • Work Item Linking: $($relaxedPolicies.branchPolicies.workItemLinking.enabled) (blocking: $($relaxedPolicies.branchPolicies.workItemLinking.isBlocking))" -ForegroundColor White
Write-Host "  • Comment Resolution: $($relaxedPolicies.branchPolicies.commentResolution.enabled)" -ForegroundColor White

Export-BranchPolicySettings -Settings $relaxedPolicies -OutputPath "examples\relaxed-policies.json"

# Example 4: Enterprise-grade strict policies
Write-Host "`n`nExample 4: Strict Enterprise Policies" -ForegroundColor Yellow
Write-Host "=====================================`n" -ForegroundColor Yellow

$strictPolicies = Get-DefaultBranchPolicySettings

# Require 3 reviewers
$strictPolicies.branchPolicies.requiredReviewers.minimumApproverCount = 3

# Reset approvals on push
$strictPolicies.branchPolicies.requiredReviewers.resetOnSourcePush = $true

# Enable build validation (assumes build ID 42 exists)
$strictPolicies.branchPolicies.buildValidation.enabled = $true
$strictPolicies.branchPolicies.buildValidation.buildDefinitionId = 42

# Enable SonarQube status check
$strictPolicies.branchPolicies.statusCheck.enabled = $true
$strictPolicies.branchPolicies.statusCheck.isBlocking = $true
$strictPolicies.branchPolicies.statusCheck.statusName = "SonarQube/quality-gate"

Write-Host "Strict Enterprise Configuration:" -ForegroundColor Cyan
Write-Host "  • Min Reviewers: $($strictPolicies.branchPolicies.requiredReviewers.minimumApproverCount)" -ForegroundColor White
Write-Host "  • Reset on Push: $($strictPolicies.branchPolicies.requiredReviewers.resetOnSourcePush)" -ForegroundColor White
Write-Host "  • Build Validation: $($strictPolicies.branchPolicies.buildValidation.enabled) (Build ID: $($strictPolicies.branchPolicies.buildValidation.buildDefinitionId))" -ForegroundColor White
Write-Host "  • Status Check: $($strictPolicies.branchPolicies.statusCheck.enabled) ($($strictPolicies.branchPolicies.statusCheck.statusName))" -ForegroundColor White

Export-BranchPolicySettings -Settings $strictPolicies -OutputPath "examples\strict-policies.json"

Write-Host "`n✅ Examples completed! Check the examples/ folder for generated files.`n" -ForegroundColor Green

# Usage in migration (future feature)
Write-Host "Future Usage:" -ForegroundColor Yellow
Write-Host "  .\Gitlab2DevOps.ps1 -Mode CreateProject ``" -ForegroundColor Cyan
Write-Host "    -Project 'MyProject' ``" -ForegroundColor Cyan
Write-Host "    -ProjectSettingsFile 'examples\mobile-project-settings.json' ``" -ForegroundColor Cyan
Write-Host "    -BranchPoliciesFile 'examples\strict-policies.json'`n" -ForegroundColor Cyan
