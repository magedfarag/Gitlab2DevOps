# Test script for documentation extraction functionality
param(
    [string]$TestProject = "TestDocsProject"
)

Write-Host "=== Testing Documentation Extraction Functionality ===" -ForegroundColor Cyan
Write-Host ""

# Import required modules
try {
    Import-Module .\modules\core\Logging.psm1 -Force
    Import-Module .\modules\GitLab\GitLab.psm1 -Force
    Write-Host "[SUCCESS] Modules loaded" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to load modules: $_" -ForegroundColor Red
    exit 1
}

# Create test structure
Write-Host ""
Write-Host "[INFO] Creating test folder structure..." -ForegroundColor Cyan

$migrationsDir = Join-Path (Get-Location) "migrations"
$testContainer = Join-Path $migrationsDir $TestProject

# Clean up if exists
if (Test-Path $testContainer) {
    Write-Host "[INFO] Cleaning up existing test folder..." -ForegroundColor Yellow
    Remove-Item -Path $testContainer -Recurse -Force
}

# Create test repositories with mock documentation files
$repos = @("frontend-app", "backend-api", "documentation")

foreach ($repo in $repos) {
    $repoDir = Join-Path $testContainer "$repo\repository"
    New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
    
    # Create mock documentation files
    if ($repo -eq "documentation") {
        # Documentation repo has lots of docs
        New-Item -ItemType File -Path "$repoDir\UserGuide.docx" -Force | Out-Null
        New-Item -ItemType File -Path "$repoDir\TechnicalSpec.pdf" -Force | Out-Null
        New-Item -ItemType File -Path "$repoDir\ProjectPlan.xlsx" -Force | Out-Null
        New-Item -ItemType File -Path "$repoDir\Presentation.pptx" -Force | Out-Null
        
        # Nested docs
        New-Item -ItemType Directory -Path "$repoDir\guides" -Force | Out-Null
        New-Item -ItemType File -Path "$repoDir\guides\AdminGuide.docx" -Force | Out-Null
        New-Item -ItemType File -Path "$repoDir\guides\DeveloperGuide.pdf" -Force | Out-Null
    }
    elseif ($repo -eq "backend-api") {
        # Backend has some API docs
        New-Item -ItemType File -Path "$repoDir\API-Reference.pdf" -Force | Out-Null
        New-Item -ItemType Directory -Path "$repoDir\docs" -Force | Out-Null
        New-Item -ItemType File -Path "$repoDir\docs\Architecture.docx" -Force | Out-Null
    }
    else {
        # Frontend has one design doc
        New-Item -ItemType File -Path "$repoDir\DesignMockups.pptx" -Force | Out-Null
    }
    
    # Create non-doc files (should not be extracted)
    New-Item -ItemType File -Path "$repoDir\README.md" -Force | Out-Null
    New-Item -ItemType File -Path "$repoDir\config.json" -Force | Out-Null
}

Write-Host "[SUCCESS] Created test structure with mock documentation files" -ForegroundColor Green
Write-Host "  � frontend-app: 1 doc file"
Write-Host "  � backend-api: 2 doc files"
Write-Host "  � documentation: 6 doc files"
Write-Host ""

# Test the extraction function
Write-Host "[INFO] Running Export-GitLabDocumentation..." -ForegroundColor Cyan
Write-Host ""

try {
    $stats = Export-GitLabDocumentation -AdoProject $TestProject
    
    if ($stats) {
        Write-Host ""
        Write-Host "=== TEST RESULTS ===" -ForegroundColor Cyan
        Write-Host "✅ Function executed successfully" -ForegroundColor Green
        Write-Host "✅ Expected 9 files, found $($stats.total_files)" -ForegroundColor $(if ($stats.total_files -eq 9) { 'Green' } else { 'Yellow' })
        Write-Host "✅ Repositories processed: $($stats.repositories_processed)" -ForegroundColor Green
        
        # Check if docs folder was created
        $docsFolder = Join-Path $testContainer "docs"
        if (Test-Path $docsFolder) {
            Write-Host "✅ docs/ folder created at: $docsFolder" -ForegroundColor Green
            
            # Verify structure
            $docFiles = Get-ChildItem -Path $docsFolder -Recurse -File
            Write-Host "✅ Total files in docs/: $($docFiles.Count)" -ForegroundColor Green
            
            Write-Host ""
            Write-Host "Documentation structure:" -ForegroundColor Cyan
            Get-ChildItem -Path $docsFolder -Recurse | ForEach-Object {
                $indent = "  " * (($_.FullName.Substring($docsFolder.Length) -split '\\').Count - 1)
                if ($_.PSIsContainer) {
                    Write-Host "$indent📁 $($_.Name)" -ForegroundColor Yellow
                }
                else {
                    Write-Host "$indent📄 $($_.Name)" -ForegroundColor Gray
                }
            }
        }
        else {
            Write-Host "❌ docs/ folder not created" -ForegroundColor Red
        }
    }
    else {
        Write-Host "❌ Function returned null" -ForegroundColor Red
    }
}
catch {
    Write-Host "[ERROR] Function failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
}

Write-Host ""
Write-Host "Test folder: $testContainer" -ForegroundColor Gray
Write-Host "Note: Test folder NOT automatically cleaned up for manual inspection" -ForegroundColor Yellow
Write-Host ""
