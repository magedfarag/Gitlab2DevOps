$root = (Get-Location).Path
$corePath = Join-Path $root 'modules\core\Core.Rest.psm1'
Import-Module $corePath -Force
Initialize-CoreRest
Write-Host "Calling Invoke-GitLabRest..."
try {
    $resp = Invoke-GitLabRest "/api/v4/projects/test19873%2Fcode-spa?statistics=true"
    Write-Host "Success: $($resp.GetType().FullName)"
    $resp | ConvertTo-Json -Depth 6 | Out-Host
}
catch {
    Write-Host "Invoke-GitLabRest failed:"
    $_ | Format-List * -Force | Out-Host
}
