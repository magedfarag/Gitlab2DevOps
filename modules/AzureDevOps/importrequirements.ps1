<#
.SYNOPSIS
Import hierarchical requirements (Epic -> Feature -> User Story -> Test Case)
from an Excel sheet into Azure DevOps Server on-prem (Agile process).

.DESCRIPTION
⚠️ DEPRECATED: This standalone script has been integrated into the main toolkit.

Use the new integrated function instead:
  Import-AdoWorkItemsFromExcel -Project "MyProject" -ExcelPath "C:\requirements.xlsx"

Or use during project initialization:
  Initialize-AdoProject -DestProject "MyProject" -RepoName "repo" -ExcelRequirementsPath "C:\requirements.xlsx"

Or via interactive menu:
  .\Gitlab2DevOps.ps1 → Option 3 → Answer 'y' to "Import work items from Excel?"

See: examples\requirements-template.md for Excel format documentation

Requires: ImportExcel PowerShell module to read .xlsx
https://www.powershellgallery.com/packages/ImportExcel/
#>

param(
    [string]$CollectionUri = "https://ado.yourdomain.local/tfs/DefaultCollection",
    [string]$Project       = "MyProject",
    [string]$ExcelPath     = "C:\temp\requirements.xlsx",
    [string]$Pat           = "PUT_YOUR_PAT_HERE"
)

# pick the API version your server supports
# 2022 / 2022.1 / 2022.2 -> 7.0 or 7.1
# 2020 -> 6.0
# https://learn.microsoft.com/.../rest-api-versioning
$apiVersion = "7.0"   # change to 6.0 for Azure DevOps Server 2020 :contentReference[oaicite:5]{index=5}

# PAT auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))

# you can replace this with any other XLSX reader if you don't want ImportExcel
Import-Module ImportExcel -ErrorAction Stop
$rows = Import-Excel -Path $ExcelPath -WorksheetName 'Requirements'

# Azure DevOps wants parents created before children
$hierarchyOrder = @{
    "Epic"      = 1
    "Feature"   = 2
    "User Story"= 3
    "Test Case" = 4
}

$orderedRows = $rows | Sort-Object { $hierarchyOrder[$_.WorkItemType] }

# map LocalId (Excel) -> ADO Id (server)
$localToAdo = @{}

Add-Type -AssemblyName System.Web

function Convert-ToTestStepsXml {
    param([string]$text)

    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $steps = $text -split ';;'
    $last  = $steps.Count
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<steps id=`"0`" last=`"$last`">")
    $id = 1
    foreach ($s in $steps) {
        $parts = $s -split '\|', 2
        $action   = [System.Web.HttpUtility]::HtmlEncode($parts[0].Trim())
        $expected = if ($parts.Count -gt 1) { [System.Web.HttpUtility]::HtmlEncode($parts[1].Trim()) } else { "" }
        [void]$sb.Append("<step id=`"$id`" type=`"ValidateStep`"><parameterizedString isformatted=`"true`">$action</parameterizedString><parameterizedString isformatted=`"true`">$expected</parameterizedString><description /></step>")
        $id++
    }
    [void]$sb.Append("</steps>")
    return $sb.ToString()
}

foreach ($row in $orderedRows) {

    $wit = $row.WorkItemType
    if (-not $wit) { continue }

    $ops = @()

    # required
    $ops += @{
        op    = "add"
        path  = "/fields/System.Title"
        value = $row.Title
    }

    if ($row.AreaPath) {
        $ops += @{ op="add"; path="/fields/System.AreaPath"; value=$row.AreaPath }
    }
    if ($row.IterationPath) {
        $ops += @{ op="add"; path="/fields/System.IterationPath"; value=$row.IterationPath }
    }
    if ($row.State) {
        $ops += @{ op="add"; path="/fields/System.State"; value=$row.State }
    }
    if ($row.Description) {
        $ops += @{ op="add"; path="/fields/System.Description"; value=$row.Description }
    }
    if ($row.Priority) {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Common.Priority"; value=[int]$row.Priority }
    }
    if ($row.StoryPoints -and $wit -eq "User Story") {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StoryPoints"; value=[double]$row.StoryPoints }
    }
    if ($row.BusinessValue) {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Common.BusinessValue"; value=[int]$row.BusinessValue }
    }
    if ($row.ValueArea) {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Common.ValueArea"; value=$row.ValueArea }
    }
    if ($row.Risk) {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Common.Risk"; value=$row.Risk }
    }

    # scheduling / effort
    if ($row.StartDate)    { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StartDate";  value=[datetime]$row.StartDate } }
    if ($row.FinishDate)   { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.FinishDate"; value=[datetime]$row.FinishDate } }
    if ($row.TargetDate)   { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.TargetDate"; value=[datetime]$row.TargetDate } }
    if ($row.DueDate)      { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.DueDate";    value=[datetime]$row.DueDate } }

    if ($row.OriginalEstimate) { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.OriginalEstimate"; value=[double]$row.OriginalEstimate } }
    if ($row.RemainingWork)    { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.RemainingWork";    value=[double]$row.RemainingWork } }
    if ($row.CompletedWork)    { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.CompletedWork";    value=[double]$row.CompletedWork } }

    # test case special field
    if ($wit -eq "Test Case" -and $row.TestSteps) {
        $xml = Convert-ToTestStepsXml -text $row.TestSteps
        if ($xml) {
            $ops += @{
                op   = "add"
                path = "/fields/Microsoft.VSTS.TCM.Steps"
                value = $xml
            }
        }
    }

    if ($row.Tags) {
        $ops += @{ op="add"; path="/fields/System.Tags"; value=$row.Tags }
    }

    # parent link (we can add it during creation if the parent is already created)
    if ($row.ParentLocalId) {
        $parentAdoId = $localToAdo[[int]$row.ParentLocalId]
        if ($parentAdoId) {
            $ops += @{
                op   = "add"
                path = "/relations/-"
                value = @{
                    rel  = "System.LinkTypes.Hierarchy-Reverse"  # child -> parent
                    url  = "$CollectionUri/$Project/_apis/wit/workItems/$parentAdoId"
                    attributes = @{ comment = "imported from Excel" }
                }
            }
        }
    }

    $json = $ops | ConvertTo-Json -Depth 20

    $url = "$CollectionUri/$Project/_apis/wit/workitems/`$$([uri]::EscapeDataString($wit))?api-version=$apiVersion"

    $wi = Invoke-RestMethod -Uri $url `
                            -Method POST `
                            -Headers @{Authorization = "Basic $base64AuthInfo"} `
                            -ContentType "application/json-patch+json" `
                            -Body $json

    # remember ADO id
    if ($row.LocalId) {
        $localToAdo[[int]$row.LocalId] = $wi.id
    }
}

Write-Host "Imported $($localToAdo.Count) work items."
