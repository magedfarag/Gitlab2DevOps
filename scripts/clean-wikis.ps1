param(
    [Parameter(Mandatory)]
    [string]$BaseUrl,

    [Parameter(Mandatory)]
    [string]$Pat,

    [Parameter()]
    [string]$ApiVersion = "7.1",

    [Parameter()]
    [bool]$DryRun,

    [Parameter()]
    [string[]]$KeepWikisinProjects = @(),

    [Parameter()]
    [string[]]$KeepWikiIds = @(),

    [Parameter()]
    [object[]]$KeepProjectAndWikiNames = @()
)


# ========================= AUTH HEADERS ==========================

$pair = ":" + $Pat
$encodedPat = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$Headers = @{
    Authorization = "Basic $encodedPat"
}

# ========================= HELPER FUNCTION =======================

function Test-IsKeptWiki {
    param(
        [string]$ProjectName,
        [object]$Wiki
    )

    # 1) Check by ID
    if ($KeepWikiIds -contains $Wiki.id) {
        return $true
    }

    # 2) Check by (Project, WikiName)
    foreach ($rule in $KeepProjectAndWikiNames) {
        if ($rule.Project -eq $ProjectName -and $rule.WikiName -eq $Wiki.name) {
            return $true
        }
    }

    return $false
}

# ========================= GET ALL PROJECTS ======================

Write-Host "Listing projects from $BaseUrl ..." -ForegroundColor Cyan

$projectsUrl = "$BaseUrl/_apis/projects?stateFilter=All&`$top=20000&api-version=$ApiVersion"
try {
    $projectsResponse = Invoke-RestMethod -Uri $projectsUrl -Headers $Headers -Method Get
} catch {
    Write-Error "Failed to list projects. $_"
    break
}

$projects = $projectsResponse.value
Write-Host "Found $($projects.Count) projects." -ForegroundColor Cyan

#remove projects that are required to keep
$projects = $projects | Where-Object { $KeepWikisinProjects -notcontains $_.name }

# ========================= PROCESS EACH PROJECT ==================

foreach ($project in $projects) {

    $projectName = $project.name
    Write-Host "=== Project: $projectName ===" -ForegroundColor Magenta

    # List wikis in this project
    $wikisUrl = "$BaseUrl/$projectName/_apis/wiki/wikis?api-version=$ApiVersion"
    try {
        $wikisResponse = Invoke-RestMethod -Uri $wikisUrl -Headers $Headers -Method Get
    } catch {
        Write-Warning "  Failed to list wikis for project '$projectName'. $_"
        continue
    }

    if (-not $wikisResponse.value -or $wikisResponse.value.Count -eq 0) {
        Write-Host "  (No wikis)" -ForegroundColor DarkGray
        continue
    }

    foreach ($wiki in $wikisResponse.value) {

        $wikiName = $wiki.name
        $wikiId   = $wiki.id
        $wikiType = $wiki.type
        $repoId   = $wiki.repositoryId

        if (Test-IsKeptWiki -ProjectName $projectName -Wiki $wiki) {
            Write-Host "  [KEEP]   $wikiName  ($wikiId)  type=$wikiType" -ForegroundColor Green
            continue
        }

        Write-Host "  [DELETE] $wikiName  ($wikiId)  type=$wikiType" -ForegroundColor Yellow

        if ($DryRun) {
            # Only log in DryRun mode
            continue
        }

        # Decide deletion URL based on wiki type
        $deleteUrl = $null

        if ($wikiType -eq "codeWiki") {
            # code wiki -> use Wiki Delete API
            $deleteUrl = "$($BaseUrl)/$($projectName)/_apis/wiki/wikis/$($wikiId)?api-version=$ApiVersion"
        }
        elseif ($wikiType -eq "projectWiki") {
            # project wiki -> delete backing Git repository
            if (-not $repoId) {
                Write-Warning "    projectWiki has no repositoryId, skipping."
                continue
            }
            $deleteUrl = "$($BaseUrl)/$($projectName)/_apis/git/repositories/$($repoId)?api-version=$ApiVersion"
        }
        else {
            Write-Warning "    Unknown wiki type '$wikiType', skipping."
            continue
        }

        try {
            Invoke-RestMethod -Uri $deleteUrl -Headers $Headers -Method Delete
            Write-Host "    --> Deleted." -ForegroundColor Red
        } catch {
            Write-Warning "    Delete failed: $_"
        }
    }
}
