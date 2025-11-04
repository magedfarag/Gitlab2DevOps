# Pre-Publication Verification Script
# Run this before publishing to GitHub to ensure everything is ready

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Pre-Publication Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$issues = @()
$warnings = @()
$checks = 0
$passed = 0

function Test-FileExists {
    param($Path, $Description)
    $checks++
    if (Test-Path $Path) {
        Write-Host "✅ $Description" -ForegroundColor Green
        $script:passed++
        return $true
    } else {
        Write-Host "❌ $Description - MISSING" -ForegroundColor Red
        $script:issues += "$Description missing at: $Path"
        return $false
    }
}

function Test-FileContent {
    param($Path, $Pattern, $Description)
    $checks++
    if (Test-Path $Path) {
        $content = Get-Content $Path -Raw
        if ($content -match $Pattern) {
            Write-Host "✅ $Description" -ForegroundColor Green
            $script:passed++
            return $true
        } else {
            Write-Host "⚠️ $Description - Pattern not found" -ForegroundColor Yellow
            $script:warnings += "$Description - Pattern '$Pattern' not found in $Path"
            return $false
        }
    } else {
        Write-Host "❌ $Description - File missing" -ForegroundColor Red
        $script:issues += "File missing: $Path"
        return $false
    }
}

Write-Host "Checking Core Files..." -ForegroundColor Cyan
Write-Host "----------------------" -ForegroundColor Cyan
Test-FileExists "devops.ps1" "Main script (devops.ps1)"
Test-FileExists "LICENSE" "License file"
Test-FileExists ".gitignore" "Git ignore file"
Test-FileExists ".gitattributes" "Git attributes file"
Write-Host ""

Write-Host "Checking Documentation..." -ForegroundColor Cyan
Write-Host "-------------------------" -ForegroundColor Cyan
Test-FileExists "README.md" "Main README"
Test-FileExists "CHANGELOG.md" "Changelog"
Test-FileExists "CONTRIBUTING.md" "Contributing guidelines"
Test-FileExists "PROJECT_SUMMARY.md" "Project summary"
Test-FileExists "QUICK_REFERENCE.md" "Quick reference guide"
Test-FileExists "BULK_MIGRATION_CONFIG.md" "Bulk migration config docs"
Test-FileExists "SYNC_MODE_GUIDE.md" "Sync mode guide (NEW)"
Write-Host ""

Write-Host "Checking Templates..." -ForegroundColor Cyan
Write-Host "---------------------" -ForegroundColor Cyan
Test-FileExists "bulk-migration-config.template.json" "Bulk migration config template"
Test-FileExists "setup-env.template.ps1" "Environment setup template"
Write-Host ""

Write-Host "Checking GitHub Templates..." -ForegroundColor Cyan
Write-Host "----------------------------" -ForegroundColor Cyan
Test-FileExists ".github/ISSUE_TEMPLATE/bug_report.md" "Bug report template"
Test-FileExists ".github/ISSUE_TEMPLATE/feature_request.md" "Feature request template"
Test-FileExists ".github/ISSUE_TEMPLATE/question.md" "Question template"
Test-FileExists ".github/PULL_REQUEST_TEMPLATE.md" "Pull request template"
Write-Host ""

Write-Host "Checking Publication Files..." -ForegroundColor Cyan
Write-Host "-----------------------------" -ForegroundColor Cyan
Test-FileExists "COMMIT_MESSAGE.md" "Commit message template"
Test-FileExists "GITHUB_RELEASE_NOTES.md" "GitHub release notes"
Test-FileExists "PUBLISHING_GUIDE.md" "Publishing guide"
Test-FileExists "SYNC_IMPLEMENTATION_SUMMARY.md" "Implementation summary"
Write-Host ""

Write-Host "Checking Content..." -ForegroundColor Cyan
Write-Host "-------------------" -ForegroundColor Cyan
Test-FileContent "devops.ps1" "-AllowSync" "devops.ps1 contains -AllowSync parameter"
Test-FileContent "README.md" "Re-running Migrations" "README contains sync mode section"
Test-FileContent "README.md" "SYNC_MODE_GUIDE\.md" "README links to sync guide"
Test-FileContent "QUICK_REFERENCE.md" "-AllowSync" "Quick reference contains sync examples"
Test-FileContent "CHANGELOG.md" "Sync/Re-run Capability" "Changelog documents sync feature"
Test-FileContent "SYNC_MODE_GUIDE.md" "Migration History Tracking" "Sync guide is complete"
Write-Host ""

Write-Host "Checking Git Configuration..." -ForegroundColor Cyan
Write-Host "-----------------------------" -ForegroundColor Cyan
$checks++
if (Test-Path ".git") {
    Write-Host "✅ Git repository initialized" -ForegroundColor Green
    $passed++
    
    # Check if migrations folder is gitignored
    $checks++
    $gitignore = Get-Content ".gitignore" -Raw
    if ($gitignore -match "migrations/") {
        Write-Host "✅ migrations/ folder is gitignored" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "❌ migrations/ folder NOT gitignored" -ForegroundColor Red
        $issues += "migrations/ folder must be in .gitignore"
    }
    
    # Check current branch
    $checks++
    $branch = git branch --show-current
    if ($branch -eq "main" -or $branch -eq "master") {
        Write-Host "✅ On main/master branch: $branch" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "⚠️ Not on main branch: $branch" -ForegroundColor Yellow
        $warnings += "Currently on branch '$branch', consider switching to 'main' for publication"
    }
    
} else {
    Write-Host "❌ Not a Git repository" -ForegroundColor Red
    $issues += "Directory is not a Git repository. Run: git init"
}
Write-Host ""

Write-Host "Checking for Sensitive Data..." -ForegroundColor Cyan
Write-Host "------------------------------" -ForegroundColor Cyan
$checks++
$gitignore = Get-Content ".gitignore" -Raw
if ($gitignore -match "setup-env\.ps1" -and $gitignore -match "bulk-migration-config\.json") {
    Write-Host "✅ Credential files are gitignored" -ForegroundColor Green
    $passed++
} else {
    Write-Host "⚠️ Check gitignore for credential files" -ForegroundColor Yellow
    $warnings += "Ensure setup-env.ps1 and bulk-migration-config.json are gitignored"
}

$checks++
if (Test-Path "migrations") {
    Write-Host "⚠️ migrations/ folder exists locally (OK if gitignored)" -ForegroundColor Yellow
    $warnings += "migrations/ folder exists - ensure it's not committed to Git"
} else {
    Write-Host "✅ No migrations/ folder to accidentally commit" -ForegroundColor Green
    $passed++
}
Write-Host ""

# Check for potential sensitive content in tracked files
Write-Host "Scanning for potential credentials..." -ForegroundColor Cyan
$checks++
$sensitivePatterns = @(
    "(?i)(password|secret|token|api[_-]?key)\s*[:=]\s*['""][^'""]+['""]",
    "(?i)pat\s*[:=]\s*['""][^'""]+['""]"
)

$trackedFiles = @("devops.ps1", "README.md", "setup-env.template.ps1", "bulk-migration-config.template.json")
$foundSensitive = $false

foreach ($file in $trackedFiles) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw
        foreach ($pattern in $sensitivePatterns) {
            if ($content -match $pattern) {
                # Check if it's in a template or example
                $match = $matches[0]
                if ($match -notmatch "example|template|your-|placeholder|\*\*\*|xxx") {
                    Write-Host "⚠️ Potential credential in $file" -ForegroundColor Yellow
                    $warnings += "Review $file for potential credentials: $($match.Substring(0, [Math]::Min(50, $match.Length)))..."
                    $foundSensitive = $true
                }
            }
        }
    }
}

if (-not $foundSensitive) {
    Write-Host "✅ No obvious credentials found in tracked files" -ForegroundColor Green
    $passed++
}
Write-Host ""

# Check Git status
Write-Host "Checking Git Status..." -ForegroundColor Cyan
Write-Host "----------------------" -ForegroundColor Cyan
if (Test-Path ".git") {
    $checks++
    $gitStatus = git status --porcelain
    if ($gitStatus) {
        Write-Host "⚠️ Uncommitted changes detected:" -ForegroundColor Yellow
        git status --short
        $warnings += "You have uncommitted changes. Commit before publishing."
    } else {
        Write-Host "✅ No uncommitted changes" -ForegroundColor Green
        $passed++
    }
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Checks: $checks" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Issues: $($issues.Count)" -ForegroundColor $(if ($issues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "Warnings: $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "❌ BLOCKING ISSUES:" -ForegroundColor Red
    Write-Host "-------------------" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  • $issue" -ForegroundColor Red
    }
    Write-Host ""
}

if ($warnings.Count -gt 0) {
    Write-Host "⚠️ WARNINGS:" -ForegroundColor Yellow
    Write-Host "------------" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "  • $warning" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "✅ ALL CHECKS PASSED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ready to publish! Follow these steps:" -ForegroundColor Cyan
    Write-Host "1. Review PUBLISHING_GUIDE.md" -ForegroundColor White
    Write-Host "2. Stage changes: git add ." -ForegroundColor White
    Write-Host "3. Commit: git commit -F COMMIT_MESSAGE.md" -ForegroundColor White
    Write-Host "4. Tag: git tag -a v2.0.0 -m 'Version 2.0.0'" -ForegroundColor White
    Write-Host "5. Push: git push origin main && git push origin v2.0.0" -ForegroundColor White
    Write-Host "6. Create GitHub release using GITHUB_RELEASE_NOTES.md" -ForegroundColor White
} elseif ($issues.Count -eq 0) {
    Write-Host "⚠️ WARNINGS ONLY - Ready to publish (review warnings first)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If warnings are acceptable, proceed with:" -ForegroundColor Cyan
    Write-Host "  See PUBLISHING_GUIDE.md for complete steps" -ForegroundColor White
} else {
    Write-Host "❌ PUBLICATION BLOCKED - Fix issues above before publishing" -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix the blocking issues listed above, then run this script again." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "For detailed publishing instructions, see: PUBLISHING_GUIDE.md" -ForegroundColor Cyan
Write-Host ""
