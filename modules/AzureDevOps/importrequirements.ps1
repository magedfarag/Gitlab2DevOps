<#
Import hierarchical requirements (Epic -> Feature -> User Story -> Test Case)
from Excel into Azure DevOps Server on-prem.
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
$apiVersion = "7.0"

# PAT auth header
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))

Import-Module ImportExcel -ErrorAction Stop

# 1) read
$rawRows = Import-Excel -Path $ExcelPath -WorksheetName 'Requirements'

# 2) drop columns with empty headers so later JSON doesn’t contain ""
$rows = foreach ($r in $rawRows) {
    $clean = [pscustomobject]@{}
    foreach ($p in $r.PSObject.Properties) {
        if ([string]::IsNullOrWhiteSpace($p.Name)) { continue }
        $clean | Add-Member -NotePropertyName $p.Name.Trim() -NotePropertyValue $p.Value
    }
    $clean
}

# Azure DevOps wants parents before children
$hierarchyOrder = @{
    "Epic"        = 1
    "Feature"     = 2
    "User Story"  = 3
    "Test Case"   = 4
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

function Add-IntField {
    param(
        [ref]$ops,
        [string]$value,
        [string]$path
    )
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    $n = 0
    if ([int]::TryParse($value, [ref]$n)) {
        $ops.Value += @{ op="add"; path=$path; value=$n }
    }
}

function Add-DoubleField {
    param(
        [ref]$ops,
        [string]$value,
        [string]$path
    )
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    $d = 0.0
    if ([double]::TryParse($value, [ref]$d)) {
        $ops.Value += @{ op="add"; path=$path; value=$d }
    }
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

    # priority / numeric business fields
    Add-IntField    -ops ([ref]$ops) -value $row.Priority      -path "/fields/Microsoft.VSTS.Common.Priority"
    Add-IntField    -ops ([ref]$ops) -value $row.BusinessValue -path "/fields/Microsoft.VSTS.Common.BusinessValue"

    if ($row.StoryPoints -and $wit -eq "User Story") {
        Add-DoubleField -ops ([ref]$ops) -value $row.StoryPoints -path "/fields/Microsoft.VSTS.Scheduling.StoryPoints"
    }

    if ($row.ValueArea) {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Common.ValueArea"; value=$row.ValueArea }
    }
    if ($row.Risk) {
        $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Common.Risk"; value=$row.Risk }
    }

    # dates
    if ($row.StartDate)  { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.StartDate";  value=[datetime]$row.StartDate } }
    if ($row.FinishDate) { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.FinishDate"; value=[datetime]$row.FinishDate } }
    if ($row.TargetDate) { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.TargetDate"; value=[datetime]$row.TargetDate } }
    if ($row.DueDate)    { $ops += @{ op="add"; path="/fields/Microsoft.VSTS.Scheduling.DueDate";    value=[datetime]$row.DueDate } }

    # effort
    Add-DoubleField -ops ([ref]$ops) -value $row.OriginalEstimate -path "/fields/Microsoft.VSTS.Scheduling.OriginalEstimate"
    Add-DoubleField -ops ([ref]$ops) -value $row.RemainingWork    -path "/fields/Microsoft.VSTS.Scheduling.RemainingWork"
    Add-DoubleField -ops ([ref]$ops) -value $row.CompletedWork    -path "/fields/Microsoft.VSTS.Scheduling.CompletedWork"

    # test steps
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

    # parent link
    if ($row.ParentLocalId) {
        $parentAdoId = $localToAdo[[int]$row.ParentLocalId]
        if ($parentAdoId) {
            $ops += @{
                op   = "add"
                path = "/relations/-"
                value = @{
                    rel  = "System.LinkTypes.Hierarchy-Reverse"
                    url  = "$CollectionUri/$Project/_apis/wit/workItems/$parentAdoId"
                    attributes = @{ comment = "imported from Excel" }
                }
            }
        }
    }

    $json = $ops | ConvertTo-Json -Depth 20

    # Build the ADO path for creating a work item of a given type. The endpoint expects a literal
    # dollar sign before the type (e.g. /_apis/wit/workitems/$Bug). Create the literal by prefixing
    # a backtick to the dollar sign and concatenating the escaped work item type.
    $escapedWit = [uri]::EscapeDataString($wit)
    $typeSegment = "`$" + $escapedWit
    $path = "/$Project/_apis/wit/workitems/$typeSegment"

    # Use the central Invoke-AdoRest wrapper so SkipCertificateCheck and curl fallback are applied consistently
    $wi = Invoke-AdoRest -Method POST -Path $path -Body $json -ContentType 'application/json-patch+json'

    if ($row.LocalId) {
        $localToAdo[[int]$row.LocalId] = $wi.id
    }
}

Write-Host "Imported $($localToAdo.Count) work items."
