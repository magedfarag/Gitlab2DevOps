Set-Location 'c:\Projects\devops\Gitlab2DevOps'
$null = Import-Module -WarningAction SilentlyContinue .\modules\core\Core.Rest.psm1 -Force -ErrorAction SilentlyContinue
$null = Import-Module -WarningAction SilentlyContinue .\modules\core\Logging.psm1 -Force -ErrorAction SilentlyContinue
$null = Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\WorkItems.psm1 -Force
$script:relationshipsCreated = 0
# Ensure the work item types cache exists and populate with common types for simulation
# Populate the module cache explicitly with common ADO types for the simulated project
try {
    if (Get-Command -Name Ensure-WorkItemTypesCache -ErrorAction SilentlyContinue) {
        $simTypes = @('User Story','Task','Bug','Issue','Feature','Epic','Test Case')
        Ensure-WorkItemTypesCache -Project 'edamah' -Types $simTypes
    }
}
catch { }
try {
    if (Get-Command -Name Get-WorkItemTypesCache -ErrorAction SilentlyContinue) {
        Write-Host "[DEBUG] Cached work item types for 'edamah':" -ForegroundColor Yellow
        $cache = Get-WorkItemTypesCache -Project 'edamah'
        if ($cache) { $cache | ForEach-Object { Write-Host " - $_" } } else { Write-Host " - <empty>" }
    }
}
catch { }
function Invoke-AdoRest {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body,
        $Preview,
        $ApiVersion,
        [string]$ContentType
    )

    if ($Method -eq 'POST' -and $Path -like '*workitems*') {
        try {
            $operations = $Body | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($operations) {
                $relationOps = @($operations) | Where-Object { $_.path -eq '/relations/-' }
                if ($relationOps) { $script:relationshipsCreated += @($relationOps).Count }
            }
        } catch { }
        return @{ id = Get-Random -Minimum 1000 -Maximum 9999 }
    }
    elseif ($Method -eq 'GET') {
        return @{ value = @() }
    }
    else {
        return @{ }
    }
}

Write-Host 'Running simulated import (no network)'
$res = Import-AdoWorkItemsFromExcel -Project 'edamah' -ExcelPath 'c:\Projects\devops\Gitlab2DevOps\migrations\edamah\requirements.xlsx' -CollectionUrl 'https://dev.azure.com/test' -TeamName 'edamah Team'
Write-Host 'Result:'
$res | ConvertTo-Json -Depth 5
Write-Host 'relationshipsCreated:' $script:relationshipsCreated
