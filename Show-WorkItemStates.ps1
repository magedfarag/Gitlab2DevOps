# Script to show allowed work item states in Azure DevOps
# This helps understand why certain states are rejected during Excel import
Import-Module .\modules\core\EnvLoader.psm1
Import-Module .\modules\core\Core.Rest.psm1 -Force

param(
    [Parameter(Mandatory)]
    [string]$ProjectName,

    [string]$WorkItemType = "Feature"  # Default to Feature since that's what the user asked about
)

Write-Host "🔍 Azure DevOps Work Item States Diagnostic" -ForegroundColor Magenta
Write-Host "=" * 50 -ForegroundColor Magenta
Write-Host ""

# Import required modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path $scriptDir "modules"

Import-Module (Join-Path $modulesPath "Core.Rest.psm1") -Force
Import-Module (Join-Path $modulesPath "AzureDevOps\WorkItems.psm1") -Force

# Initialize CoreRest (you may need to modify these values for your environment)
# Initialize-CoreRest -CollectionUrl "https://dev.azure.com/your-org" -AdoPat "your-pat"

Write-Host "📋 Checking allowed states for $WorkItemType in project '$ProjectName'..." -ForegroundColor Cyan
Write-Host ""

try {
    # Show states for the specific work item type
    $result = Show-AdoWorkItemStates -Project $ProjectName -WorkItemType $WorkItemType

    if ($result) {
        Write-Host ""
        Write-Host "💡 Why 'New' might be rejected:" -ForegroundColor Yellow
        if ($result.AllowedStates -notcontains "New") {
            Write-Host "  • 'New' is not in the allowed states list for $WorkItemType" -ForegroundColor Red
            Write-Host "  • Valid alternatives: $($result.AllowedStates -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "  • 'New' IS allowed for $WorkItemType - check other validation issues" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "🔧 Excel Import Behavior:" -ForegroundColor Cyan
        Write-Host "  • If 'New' is specified in Excel but not allowed, it gets mapped to: $($result.DefaultValue)" -ForegroundColor White
        Write-Host "  • The warning you saw indicates this automatic mapping occurred" -ForegroundColor White
    }
}
catch {
    Write-Error "Failed to query work item states: $_"
    Write-Host ""
    Write-Host "💡 Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  • Make sure you're connected to Azure DevOps (run Initialize-CoreRest first)" -ForegroundColor White
    Write-Host "  • Verify the project name is correct" -ForegroundColor White
    Write-Host "  • Check that the work item type exists in your project" -ForegroundColor White
}

Write-Host ""
Write-Host "📊 To see ALL work item type states, run:" -ForegroundColor Cyan
Write-Host "  Show-AllWorkItemStates -Project '$ProjectName'" -ForegroundColor White