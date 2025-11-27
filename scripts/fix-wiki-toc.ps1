param(
    [string]$PagePath = "Security-First Software Factory – On-Prem Overview"
)

Import-Module -Name "$PSScriptRoot\..\modules\core\EnvLoader.psm1" -ErrorAction Stop
Import-DotEnvFile -Path "$PSScriptRoot\..\ .env" -ErrorAction SilentlyContinue
Import-Module -Name "$PSScriptRoot\..\modules\AzureDevOps\AzureDevOps.psm1" -ErrorAction Stop

function Convert-TocLinks {
    param([string]$Content)
    $pattern = '\[(?<text>[^\]]+)\]\((?<target>[^)#\s]+)\)'
    return [regex]::Replace($Content, $pattern, {
        param($m)
        $text = $m.Groups['text'].Value
        $target = $m.Groups['target'].Value
        if ($target -match '^(https?://|mailto:|#|/)') { return $m.Value }
        $segments = $target -split '/'
        $encoded = $segments | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { $_ } else { [uri]::EscapeDataString($_).Replace('-', '%2D') }
        }
        $newTarget = '/' + ($encoded -join '/')
        return "[{0}]({1})" -f $text, $newTarget
    })
}

$projects = Get-AdoProjectList -RefreshCache
foreach ($proj in $projects) {
    $projName = $proj.name
    Write-Host "[INFO] Processing project '$projName'..." -ForegroundColor Cyan
    try {
        $projEnc = [uri]::EscapeDataString($projName)
        $wikis = Invoke-AdoRest GET "/$projEnc/_apis/wiki/wikis" -ReturnNullOnNotFound
        $wikiId = $null
        if ($wikis) {
            if ($wikis.PSObject.Properties['value'] -and $wikis.value.Count -gt 0) { $wikiId = $wikis.value[0].id }
            elseif ($wikis.PSObject.Properties['id']) { $wikiId = $wikis.id }
        }
        if (-not $wikiId) {
            Write-Host "  [SKIP] No wiki found for '$projName'." -ForegroundColor Yellow
            continue
        }

        $pageEnc = [uri]::EscapeDataString($PagePath.Trim())
        $page = Invoke-AdoRest GET "/$projEnc/_apis/wiki/wikis/$wikiId/pages?path=$pageEnc&includeContent=true" -ReturnNullOnNotFound
        if (-not $page -or -not $page.content) {
            Write-Host "  [SKIP] Page '$PagePath' not found in '$projName' wiki." -ForegroundColor Yellow
            continue
        }

        $updated = Convert-TocLinks -Content $page.content
        if ($updated -eq $page.content) {
            Write-Host "  [INFO] No TOC link changes needed for '$projName'." -ForegroundColor Gray
            continue
        }

        Set-AdoWikiPage -Project $projName -WikiId $wikiId -Path $PagePath -Markdown $updated
        Write-Host "  [SUCCESS] TOC links updated for '$projName'." -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Failed to update '$projName': $($_.Exception.Message)" -ForegroundColor Red
    }
}
