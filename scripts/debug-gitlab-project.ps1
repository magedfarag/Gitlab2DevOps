param(
    [string]$ProjectPath = 'test19873/code-spa'
)

$token = $env:GITLAB_PAT
if (-not $token) { Write-Host 'No GITLAB_PAT found in environment'; exit 2 }
Write-Host "Token length: $($token.Length)"
$enc = [uri]::EscapeDataString($ProjectPath)
$uri = "https://gitlab.com/api/v4/projects/$enc?statistics=true"
Write-Host "Calling: $uri"
try {
    $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'PRIVATE-TOKEN' = $token } -SkipCertificateCheck -ErrorAction Stop
    Write-Host "Success: Received response of type $($resp.GetType().FullName)"
    $resp | ConvertTo-Json -Depth 5 | Out-File -FilePath .\logs\debug-gitlab-response.json -Encoding utf8
    Write-Host "Saved response to .\logs\debug-gitlab-response.json"
}
catch {
    Write-Host "ERROR invoking GitLab API"
    if ($_.Exception) {
        Write-Host "Exception.Type: $($_.Exception.GetType().FullName)"
        Write-Host "Exception.Message: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                Write-Host "Response body (truncated 1000 chars):"
                Write-Host ($body.Substring(0, [Math]::Min(1000, $body.Length)))
                $body | Out-File -FilePath .\logs\debug-gitlab-error-body.txt -Encoding utf8
                Write-Host "Saved raw response to .\logs\debug-gitlab-error-body.txt"
            }
            catch {
                Write-Host "Could not read response stream: $_"
            }
        }
        else {
            Write-Host "No Response property on exception. Full error:"; $_ | Format-List * -Force
        }
    }
    else { $_ | Format-List * -Force }
}
