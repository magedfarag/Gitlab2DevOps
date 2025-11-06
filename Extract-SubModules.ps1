<#
.SYNOPSIS
    Extracts AzureDevOps.psm1 functions into logical sub-modules.

.DESCRIPTION
    Automates the extraction of functions from the monolithic AzureDevOps.psm1
    into smaller, focused sub-modules organized by functional area.
#>

$sourceFile = ".\modules\AzureDevOps.psm1"
$targetDir = ".\modules\AzureDevOps"

# Ensure target directory exists
New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

# Read entire source file
$content = Get-Content $sourceFile -Raw

# Define module structure with function mappings (line ranges will be calculated)
$modules = @{
    'Security.psm1' = @{
        Description = 'Security groups and permissions management'
        Functions = @(
            'Get-AdoBuiltInGroupDescriptor',
            'Ensure-AdoGroup',
            'Ensure-AdoMembership'
        )
    }
    'Projects.psm1' = @{
        Description = 'Project creation and configuration'
        Functions = @(
            'Get-AdoProjectRepositories',
            'Ensure-AdoProject',
            'Get-AdoProjectDescriptor',
            'Get-AdoProjectProcessTemplate',
            'Get-AdoWorkItemTypes',
            'Ensure-AdoArea',
            'Ensure-AdoIterations'
        )
    }
    'Wikis.psm1' = @{
        Description = 'Wiki creation and page management'
        Functions = @(
            'Ensure-AdoProjectWiki',
            'Upsert-AdoWikiPage',
            'Ensure-AdoQAGuidelinesWiki',
            'Ensure-AdoBestPracticesWiki',
            'Ensure-AdoBusinessWiki',
            'Ensure-AdoDevWiki',
            'Ensure-AdoSecurityWiki'
        )
    }
    'Repositories.psm1' = @{
        Description = 'Repository management and branch policies'
        Functions = @(
            'Ensure-AdoRepositoryTemplates',
            'Ensure-AdoRepository',
            'Get-AdoRepoDefaultBranch',
            'Ensure-AdoBranchPolicies',
            'Ensure-AdoRepoDeny',
            'Ensure-AdoRepoFiles'
        )
    }
    'WorkItems.psm1' = @{
        Description = 'Work items, queries, and test plans'
        Functions = @(
            'Ensure-AdoTeamTemplates',
            'Ensure-AdoSharedQueries',
            'Ensure-AdoTestPlan',
            'Ensure-AdoQAQueries',
            'Ensure-AdoTestConfigurations',
            'Ensure-AdoCommonTags',
            'Ensure-AdoBusinessQueries',
            'Ensure-AdoDevQueries',
            'Ensure-AdoSecurityQueries'
        )
    }
    'Dashboards.psm1' = @{
        Description = 'Dashboard and team settings'
        Functions = @(
            'Ensure-AdoTeamSettings',
            'Ensure-AdoDashboard',
            'Ensure-AdoQADashboard',
            'Ensure-AdoDevDashboard'
        )
    }
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Azure DevOps Module Extraction Tool" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Extract header and constants
$lines = $content -split "`r?`n"
$headerEndLine = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#.*POLICY_|^\s*\$script:POLICY_|^\s*\$script:NS_|^\s*\$script:GIT_') {
        $headerEndLine = $i
    }
    if ($lines[$i] -match '^function Get-WikiTemplate') {
        break
    }
}

$header = $lines[0..$headerEndLine] -join "`n"

Write-Host "[INFO] Extracted header and constants ($headerEndLine lines)" -ForegroundColor Green

# Function to extract a function's complete code
function Extract-Function {
    param(
        [string]$FunctionName,
        [string[]]$Lines
    )
    
    # Find function start
    $startLine = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^function $FunctionName\s*\{") {
            $startLine = $i
            break
        }
    }
    
    if ($startLine -eq -1) {
        Write-Warning "Function $FunctionName not found"
        return $null
    }
    
    # Find function end by counting braces
    $braceCount = 0
    $inFunction = $false
    $endLine = $startLine
    
    for ($i = $startLine; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        
        # Count opening and closing braces
        $openBraces = ([regex]::Matches($line, '\{')).Count
        $closeBraces = ([regex]::Matches($line, '\}')).Count
        
        if ($line -match "^function $FunctionName") {
            $inFunction = $true
        }
        
        if ($inFunction) {
            $braceCount += $openBraces - $closeBraces
            
            if ($braceCount -eq 0 -and $i -gt $startLine) {
                $endLine = $i
                break
            }
        }
    }
    
    # Include comment block before function
    $commentStart = $startLine
    for ($i = $startLine - 1; $i -ge 0; $i--) {
        if ($Lines[$i] -match '^\s*<#|^\s*#|^\s*$') {
            $commentStart = $i
        } else {
            break
        }
    }
    
    $functionCode = $Lines[$commentStart..$endLine] -join "`n"
    return $functionCode
}

# Extract each module
foreach ($moduleName in $modules.Keys) {
    $moduleInfo = $modules[$moduleName]
    $modulePath = Join-Path $targetDir $moduleName
    
    Write-Host ""
    Write-Host "Processing $moduleName..." -ForegroundColor Cyan
    Write-Host "  Description: $($moduleInfo.Description)" -ForegroundColor Gray
    Write-Host "  Functions: $($moduleInfo.Functions.Count)" -ForegroundColor Gray
    
    # Build module content
    $moduleContent = @"
<#
.SYNOPSIS
    $($moduleInfo.Description)

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

"@
    
    $extractedCount = 0
    foreach ($funcName in $moduleInfo.Functions) {
        Write-Host "    Extracting $funcName..." -ForegroundColor Gray
        $funcCode = Extract-Function -FunctionName $funcName -Lines $lines
        
        if ($funcCode) {
            $moduleContent += "`n$funcCode`n"
            $extractedCount++
        }
    }
    
    # Add exports
    $exports = $moduleInfo.Functions -join "',`n    '"
    $moduleContent += @"

# Export functions
Export-ModuleMember -Function @(
    '$exports'
)
"@
    
    # Write module file
    $moduleContent | Set-Content -Path $modulePath -Encoding UTF8
    Write-Host "  [SUCCESS] Created $moduleName with $extractedCount functions" -ForegroundColor Green
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Green
Write-Host "Extraction complete!" -ForegroundColor Green
Write-Host "=" * 80 -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review extracted modules in: $targetDir" -ForegroundColor Gray
Write-Host "  2. Update main AzureDevOps.psm1 to import sub-modules" -ForegroundColor Gray
Write-Host "  3. Test module imports" -ForegroundColor Gray
Write-Host ""
