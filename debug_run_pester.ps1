Set-Location 'C:\Projects\devops\Gitlab2DevOps'

try {
    Invoke-Pester -Path tests\DevInit.Idempotency.Tests.ps1 -Output Detailed -PassThru | Out-Null
}
catch {
    Write-Host "Invoke-Pester threw: $_"
}

if ($Error.Count -gt 0) {
    $e = $Error[0]
    $payload = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        error = ($e | Out-String).Trim()
        exception = ($e.Exception | Out-String).Trim()
        response = ''
        responseBody = ''
    }
    try {
        if ($e.Exception -and $e.Exception.Response) { $payload.response = ($e.Exception.Response.StatusCode.ToString()) }
    } catch {}
    try {
        if ($e.Exception -and $e.Exception.Response -and $e.Exception.Response.Content) { $payload.responseBody = ($e.Exception.Response.Content.ReadAsStringAsync().Result) }
    } catch { $payload.responseBody = 'failed-to-read-response-body: ' + ($_ | Out-String) }

    $logsDir = Join-Path (Get-Location) 'logs'
    if (-not (Test-Path $logsDir)) { New-Item -Path $logsDir -ItemType Directory -Force | Out-Null }
    $fname = Join-Path $logsDir ("pester-exception-" + [guid]::NewGuid().ToString() + ".json")
    $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $fname -Encoding UTF8 -Force
    Write-Host "Wrote debug file: $fname"
}
else {
    Write-Host 'No errors captured in $Error after Pester run'
}
