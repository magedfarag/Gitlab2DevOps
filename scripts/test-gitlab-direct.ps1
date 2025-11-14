$token = $env:GITLAB_PAT
if (-not $token) { Write-Host 'No token'; exit 2 }
$uri = 'https://gitlab.com/api/v4/projects/test19873%2Fcode-spa?statistics=true'
Write-Host "Calling: $uri"
try {
    $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'PRIVATE-TOKEN' = $token } -SkipCertificateCheck -ErrorAction Stop
    Write-Host "Success"
    $resp | ConvertTo-Json -Depth 5 | Out-File -FilePath .\logs\debug-gitlab-response.json -Encoding utf8
    Write-Host "Saved response"
}
catch {
    Write-Host "Error invoking API"
    if ($_.Exception) { $_.Exception | Format-List * -Force | Out-Host } else { $_ | Format-List * -Force | Out-Host }
}
