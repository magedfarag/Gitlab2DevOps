# Simulate a wiki PUT resulting in HTTP 500 and run the diagnostic logging used by Set-AdoWikiPage
# This script creates a fake exception object with a Response.GetResponseStream() that returns a stream
# containing a sample HTML error body, then runs the same logging logic used in Set-AdoWikiPage to write a timestamped JSON file.

Add-Type -TypeDefinition @'
using System;
using System.IO;
public class FakeWebResponse {
    private byte[] _data;
    public FakeWebResponse(string s) {
        _data = System.Text.Encoding.UTF8.GetBytes(s);
    }
    public Stream GetResponseStream() {
        return new MemoryStream(_data);
    }
}
public class FakeException : Exception {
    public FakeWebResponse Response { get; private set; }
    public FakeException(string message, FakeWebResponse resp) : base(message) {
        this.Response = resp;
    }
}
'@ -Language CSharpVersion3

# Create fake response and exception
$body = "<html><body><h1>500 Internal Server Error</h1><p>Simulated server stack trace or message here</p></body></html>"
$resp = New-Object FakeWebResponse $body
$fakeEx = New-Object FakeException "Simulated 500 from ADO Wiki PUT" $resp

# Simulate the catch block context ($_ will be an ErrorRecord when caught); create an ErrorRecord wrapping the fake exception
$errorRecord = New-Object System.Management.Automation.ErrorRecord ($fakeEx, "Simulated", [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

# Logging logic (adapted from Set-AdoWikiPage)
try {
    throw $errorRecord
}
catch {
    # Use the same normalization logic used in Wikis.psm1 to get the inner exception
    $rawBody = $null
    $actualEx = $null
    if ($_.Exception -and ($_.Exception -is [System.Management.Automation.ErrorRecord])) { $actualEx = $_.Exception.Exception } else { $actualEx = $_.Exception }

    if ($actualEx -and (Get-Member -InputObject $actualEx -Name 'Response' -MemberType Properties -ErrorAction SilentlyContinue)) {
        if ($actualEx.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($actualEx.Response.GetResponseStream())
                $rawBody = $reader.ReadToEnd()
            }
            catch {
                $rawBody = "<failed to read response stream: $_>"
            }
        }
    }

    # Determine repo root and logs dir
    $repoRoot = (Get-Location).Path
    $logsDir = Join-Path $repoRoot "modules\logs"
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safePath = "-simulated-500-" + $timestamp
    $project = "SIMULATED-PROJECT"
    $logFile = Join-Path $logsDir ("wiki-500-" + [uri]::EscapeDataString($project) + $safePath + ".log")

    $payload = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        project   = $project
        wikiPath  = "/Simulated/Path"
        status    = 500
        message   = $_.Exception.Message
        rawBody   = if ($rawBody) { $rawBody } else { '<no body captured>' }
    }

    $payload | ConvertTo-Json -Depth 10 | Out-File -FilePath $logFile -Encoding UTF8 -Force
    Write-Host "Wrote simulated 500 diagnostic to: $logFile" -ForegroundColor Cyan
    Write-Host "Payload (first 200 chars of rawBody):" -ForegroundColor Gray
    $preview = $payload.rawBody
    if ($preview.Length -gt 200) { $preview = $preview.Substring(0,200) + '... (truncated)' }
    Write-Host $preview -ForegroundColor Gray
}

Write-Host "Simulation complete." -ForegroundColor Green
