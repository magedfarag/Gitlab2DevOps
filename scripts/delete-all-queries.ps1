<#
.SYNOPSIS
    Delete all queries from all Azure DevOps projects (My Queries and Shared Queries).

.DESCRIPTION
    This script uses the Azure DevOps Work Item Tracking REST API to enumerate all query
    folders and queries under the "My Queries" and "Shared Queries" roots for all projects
    in the organization and deletes them. It leaves the root containers themselves intact,
    so the Queries hub remains usable but empty.

    Parameters can be provided via command line or read from .env file.

    WARNING: Deleting queries is destructive. Although query items can be undeleted
    via the REST API (isDeleted flag) or future features, permission changes on the
    deleted items are not recoverable. Run with -WhatIf first.

.PARAMETER OrganizationUrl
    Base organization URL, for example:
      https://dev.azure.com/your-org
      https://devops.your-domain.local/tfs/DefaultCollection
    If not provided, reads from ADO_COLLECTION_URL environment variable.

.PARAMETER PersonalAccessToken
    PAT with at least "Work Items (read and write)" scope.
    If not provided, reads from ADO_PAT environment variable.

.PARAMETER EnvPath
    Path to .env file to load configuration from. Default is "..\.env".

.PARAMETER WhatIf
    If specified, the script only prints what would be deleted without performing deletions.

.EXAMPLE
    .\delete-all-queries.ps1 -WhatIf

.EXAMPLE
    .\delete-all-queries.ps1 -OrganizationUrl "https://dev.azure.com/contoso" -PersonalAccessToken "xxxxx"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OrganizationUrl,

    [Parameter(Mandatory = $false)]
    [string]$PersonalAccessToken,

    [Parameter(Mandatory = $false)]
    [string]$EnvPath = "..\.env",

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Load environment variables from .env file
if (Test-Path $EnvPath) {
    $envContent = Get-Content $EnvPath | Where-Object { $_ -notmatch '^#' -and $_ -notmatch '^\s*$' }
    foreach ($line in $envContent) {
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($value -match '^"(.*)"$') { $value = $matches[1] }
            elseif ($value -match "^'(.*)'$") { $value = $matches[1] }
            [Environment]::SetEnvironmentVariable($key, $value)
        }
    }
}

# Read parameters from environment if not provided
if (-not $OrganizationUrl) {
    $OrganizationUrl = $env:ADO_COLLECTION_URL
}

if (-not $PersonalAccessToken) {
    $PersonalAccessToken = $env:ADO_PAT
}

# Validate required parameters
if (-not $OrganizationUrl) {
    throw "OrganizationUrl is required. Provide it as parameter or set ADO_COLLECTION_URL in .env file."
}

if (-not $PersonalAccessToken) {
    throw "PersonalAccessToken is required. Provide it as parameter or set ADO_PAT in .env file."
}

$apiVersion = '7.1'

# Expose WhatIf inside helper functions
$script:DoWhatIf = $WhatIf.IsPresent

$trimmedOrg = $OrganizationUrl.TrimEnd('/')

function New-AdoAuthHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pat
    )

    $token = ':' + $Pat
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($token)
    $base64 = [System.Convert]::ToBase64String($bytes)

    return @{
        Authorization = "Basic $base64"
    }
}

$headers = New-AdoAuthHeader -Pat $PersonalAccessToken

function Invoke-AdoGet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    Write-Verbose "GET  $Url"
    return Invoke-RestMethod -Method Get -Uri $Url -Headers $headers
}

function Invoke-AdoDelete {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$ItemDescription
    )

    if ($script:DoWhatIf) {
        Write-Host "[WhatIf] DELETE $ItemDescription"
        Write-Host "         $Url"
        return
    }

    Write-Host "DELETE $ItemDescription"
    Write-Verbose "DELETE $Url"

    Invoke-RestMethod -Method Delete -Uri $Url -Headers $headers | Out-Null
}

function Get-AdoRootQueryFolders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectUrl
    )

    <#
        Returns the root query folders for the project, typically:
          - My Queries
          - Shared Queries
    #>
    $url = ("{0}/_apis/wit/queries?`$depth=1&api-version={1}" -f $ProjectUrl, $apiVersion)
    $result = Invoke-AdoGet -Url $url

    if ($null -ne $result.value) {
        return $result.value
    }

    # Some servers return a single QueryHierarchyItem instead of a wrapper
    return @($result)
}

function Remove-AdoQueriesUnderFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectUrl,

        [Parameter(Mandatory = $true)]
        [string]$FolderId
    )

    # Request folder with its children
    $url = ("{0}/_apis/wit/queries/{1}?`$depth=2&api-version={2}" -f $ProjectUrl, $FolderId, $apiVersion)
    $folder = Invoke-AdoGet -Url $url

    $children = @()
    if ($null -ne $folder.children) {
        $children = $folder.children
    } elseif ($null -ne $folder.value) {
        $children = $folder.value
    }

    foreach ($child in $children) {
        if ($child.isFolder -eq $true) {
            # Recurse into sub-folder first
            Remove-AdoQueriesUnderFolder -ProjectUrl $ProjectUrl -FolderId $child.id

            # Then delete the folder itself
            $deleteUrl = ("{0}/_apis/wit/queries/{1}?api-version={2}" -f $ProjectUrl, $child.id, $apiVersion)
            $desc = "folder '{0}' ({1})" -f $child.name, $child.id
            Invoke-AdoDelete -Url $deleteUrl -ItemDescription $desc
        }
        else {
            # Delete individual query
            $deleteUrl = ("{0}/_apis/wit/queries/{1}?api-version={2}" -f $ProjectUrl, $child.id, $apiVersion)
            $desc = "query '{0}' ({1})" -f $child.name, $child.id
            Invoke-AdoDelete -Url $deleteUrl -ItemDescription $desc
        }
    }
}

Write-Host "Azure DevOps organization: $trimmedOrg"
Write-Host "API version              : $apiVersion"
Write-Host "WhatIf mode              : $($script:DoWhatIf)"
Write-Host "Env file                 : $EnvPath"

# Get all projects
$projectsUrl = "$trimmedOrg/_apis/projects?`$top=1000&api-version=$apiVersion"
$projectsResponse = Invoke-AdoGet -Url $projectsUrl

if (-not $projectsResponse -or -not $projectsResponse.value) {
    throw "Failed to get projects from $projectsUrl"
}

$projects = $projectsResponse.value
Write-Host "Found $($projects.Count) projects to process."

foreach ($project in $projects) {
    Write-Host ""
    Write-Host "Processing project: $($project.name) ($($project.id))"

    $projectUrl = "$trimmedOrg/$($project.name)"

    $rootFolders = Get-AdoRootQueryFolders -ProjectUrl $projectUrl

    if (-not $rootFolders) {
        Write-Warning "No root query folders returned for project $($project.name). Skipping."
        continue
    }

    $targets = $rootFolders | Where-Object {
        $_.name -eq 'Shared Queries' -or $_.name -eq 'My Queries'
    }

    if (-not $targets) {
        Write-Warning "Could not find 'Shared Queries' or 'My Queries' roots for project $($project.name). Skipping."
        continue
    }

    foreach ($root in $targets) {
        Write-Host "  Processing root folder: $($root.name) ($($root.id))"
        Remove-AdoQueriesUnderFolder -ProjectUrl $projectUrl -FolderId $root.id
    }
}

Write-Host ""
if ($script:DoWhatIf) {
    Write-Host "Completed in WhatIf mode. No queries were actually deleted."
} else {
    Write-Host "Completed. All queries and sub-folders under 'Shared Queries' and 'My Queries' have been deleted from all projects."
}
