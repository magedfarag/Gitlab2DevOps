<#
.SYNOPSIS
    Extracts wiki content from AzureDevOps.psm1 into separate template files.

.DESCRIPTION
    This script parses the AzureDevOps.psm1 file, extracts all wiki content
    from here-strings, and saves them as separate .md template files.
#>

param(
    [string]$ModuleFile = ".\modules\AzureDevOps.psm1",
    [string]$OutputDir = ".\modules\AzureDevOps\WikiTemplates"
)

Write-Host "[INFO] Extracting wiki templates from $ModuleFile..." -ForegroundColor Cyan

# Read the module file
$content = Get-Content $ModuleFile -Raw

# Define extraction patterns for each wiki section
$extractions = @(
    # Dev Wiki Templates
    @{
        Pattern = '(?s)\$adrContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\ADR.md"
        Name = "Dev - ADR"
    },
    @{
        Pattern = '(?s)\$devSetupContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\DevSetup.md"
        Name = "Dev - Setup"
    },
    @{
        Pattern = '(?s)\$apiDocsContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\APIDocs.md"
        Name = "Dev - API Docs"
    },
    @{
        Pattern = '(?s)\$gitWorkflowContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\GitWorkflow.md"
        Name = "Dev - Git Workflow"
    },
    @{
        Pattern = '(?s)\$codeReviewContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\CodeReview.md"
        Name = "Dev - Code Review"
    },
    @{
        Pattern = '(?s)\$troubleshootingContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\Troubleshooting.md"
        Name = "Dev - Troubleshooting"
    },
    @{
        Pattern = '(?s)\$dependenciesContent = @"(.+?)"@'
        Output = "$OutputDir\Dev\Dependencies.md"
        Name = "Dev - Dependencies"
    },
    
    # Security Wiki Templates (already extracted, but included for completeness)
    @{
        Pattern = '(?s)\$securityPoliciesContent = @"(.+?)"@'
        Output = "$OutputDir\Security\SecurityPolicies.md"
        Name = "Security - Policies"
    },
    @{
        Pattern = '(?s)\$threatModelingContent = @"(.+?)"@'
        Output = "$OutputDir\Security\ThreatModeling.md"
        Name = "Security - Threat Modeling"
    },
    @{
        Pattern = '(?s)\$securityTestingContent = @"(.+?)"@'
        Output = "$OutputDir\Security\SecurityTesting.md"
        Name = "Security - Testing"
    },
    @{
        Pattern = '(?s)\$incidentResponseContent = @"(.+?)"@'
        Output = "$OutputDir\Security\IncidentResponse.md"
        Name = "Security - Incident Response"
    },
    @{
        Pattern = '(?s)\$complianceContent = @"(.+?)"@'
        Output = "$OutputDir\Security\Compliance.md"
        Name = "Security - Compliance"
    },
    @{
        Pattern = '(?s)\$secretManagementContent = @"(.+?)"@'
        Output = "$OutputDir\Security\SecretManagement.md"
        Name = "Security - Secret Management"
    },
    @{
        Pattern = '(?s)\$securityChampionsContent = @"(.+?)"@'
        Output = "$OutputDir\Security\SecurityChampions.md"
        Name = "Security - Champions"
    },
    
    # Best Practices Wiki Template (single content variable)
    @{
        Pattern = '(?s)\$bestPracticesContent = @"(.+?)"@'
        Output = "$OutputDir\BestPractices\BestPractices.md"
        Name = "Best Practices"
    },
    
    # QA Wiki Template (single content variable)
    @{
        Pattern = '(?s)\$qaGuidelinesContent = @"(.+?)"@'
        Output = "$OutputDir\QA\QAGuidelines.md"
        Name = "QA Guidelines"
    },
    
    # Business Wiki Templates (embedded in $pages array)
    @{
        Pattern = '(?s)@\{ path = ''/Business-Welcome''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\BusinessWelcome.md"
        Name = "Business - Welcome"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Decision-Log''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\DecisionLog.md"
        Name = "Business - Decision Log"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Risks-Issues''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\RisksIssues.md"
        Name = "Business - Risks & Issues"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Glossary''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\Glossary.md"
        Name = "Business - Glossary"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Ways-of-Working''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\WaysOfWorking.md"
        Name = "Business - Ways of Working"
    },
    @{
        Pattern = '(?s)@\{ path = ''/KPIs-and-Success''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\KPIsAndSuccess.md"
        Name = "Business - KPIs & Success"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Training-Quick-Start''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\TrainingQuickStart.md"
        Name = "Business - Training"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Communication-Templates''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\CommunicationTemplates.md"
        Name = "Business - Communication Templates"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Cutover-Timeline''; content = @"(.+?)"@ \},'
        Output = "$OutputDir\Business\CutoverTimeline.md"
        Name = "Business - Cutover Timeline"
    },
    @{
        Pattern = '(?s)@\{ path = ''/Post-Cutover-Summary''; content = @"(.+?)"@ \}'
        Output = "$OutputDir\Business\PostCutoverSummary.md"
        Name = "Business - Post-Cutover Summary"
    }
)

$extracted = 0
$failed = 0

foreach ($item in $extractions) {
    Write-Host "  Processing: $($item.Name)..." -ForegroundColor Gray
    
    if ($content -match $item.Pattern) {
        $templateContent = $matches[1].Trim()
        
        # Ensure output directory exists
        $outputPath = $item.Output
        $outputDir = Split-Path $outputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        
        # Write template file
        $templateContent | Out-File -FilePath $outputPath -Encoding UTF8 -NoNewline
        
        Write-Host "    ✅ Created: $outputPath" -ForegroundColor Green
        $extracted++
    }
    else {
        Write-Warning "    ❌ Pattern not found for: $($item.Name)"
        $failed++
    }
}

Write-Host ""
Write-Host "[SUCCESS] Extraction complete!" -ForegroundColor Green
Write-Host "  Extracted: $extracted templates" -ForegroundColor Gray
if ($failed -gt 0) {
    Write-Host "  Failed: $failed templates" -ForegroundColor Yellow
}
