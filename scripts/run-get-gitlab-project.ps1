param(
    [string]$Path = 'test19873/code-spa'
)

Import-Module "$PSScriptRoot\..\modules\core\Core.Rest.psm1" -Force
#Initialize-CoreRest
Import-Module "$PSScriptRoot\..\modules\GitLab\GitLab.psm1" -Force

try {
    $proj = Get-GitLabProject $Path
    Write-Host "SUCCESS: Project fetched"
    $proj | ConvertTo-Json -Depth 6 | Out-Host
}
catch {
    Write-Host "FAILED: $_"
}
