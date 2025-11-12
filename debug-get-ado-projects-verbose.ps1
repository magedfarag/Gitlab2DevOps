<#
.SYNOPSIS
    Verbose diagnostic script to list Azure DevOps projects and show full diagnostics.

.DESCRIPTION
    This script attempts to reproduce the logic used by the interactive menu option that
    lists Azure DevOps projects. It prints every variable, request, response, timing and
    network diagnostic (DNS/TCP/TLS). It is intentionally verbose and intended for debugging
    connectivity/auth issues.

    Usage: run in PowerShell from repository root:
      pwsh -NoProfile -ExecutionPolicy Bypass .\scripts\debug-get-ado-projects-verbose.ps1

    The script will read configuration from environment variables (preferred) or from
    a local .env file if present in the repository root. The following variables are used:
      ADO_COLLECTION_URL, ADO_PAT, ADO_API_VERSION (optional, default 7.1), SKIP_CERTIFICATE_CHECK

    Security note: the script masks the PAT when printing values. Do NOT paste the full
    PAT in public places.
#>

Set-StrictMode -Version Latest

function Read-DotEnv {
    param(
        [string]$Path = (Join-Path (Get-Location) '.env')
    )

    if (-not (Test-Path $Path)) { return @{} }
    $pairs = @{}
    Get-Content $Path | ForEach-Object {
        $_ = $_.Trim()
        if ($_.StartsWith('#') -or $_ -eq '') { return }
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            $k = $parts[0].Trim()
            $v = $parts[1].Trim()
            # unquote
            if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
            $pairs[$k] = $v
        }
    }
    return $pairs
}

function Mask-Token {
    param([string]$token)
    if (-not $token) { return '' }
    if ($token.Length -le 8) { return ('*' * $token.Length) }
    $start = $token.Substring(0,4)
    $end = $token.Substring($token.Length - 4, 4)
    return "$start`****`$end"
}

function Build-AdoUri {
    param(
        [Parameter(Mandatory)] [string]$BaseUrl,
        [Parameter(Mandatory)] [string]$Path,
        [string]$ApiVersion = '7.1'
    )
    $baseUrl = $BaseUrl.TrimEnd('/')
    if ($Path -match '\?') { return "{0}/{1}&api-version={2}" -f $baseUrl, $Path.TrimStart('/'), $ApiVersion }
    return "{0}/{1}?api-version={2}" -f $baseUrl, $Path.TrimStart('/'), $ApiVersion
}

function Do-DnsTcpCheck {
    param([string]$HostName, [int]$Port = 443, [int]$TcpTimeoutMs = 5000)
    # Use HostName param to avoid colliding with automatic $Host variable
    $out = [pscustomobject]@{ Host = $HostName; Dns = @(); Tcp = $null }
    try {
        $addrs = [System.Net.Dns]::GetHostAddresses($HostName)
        $out.Dns = $addrs | ForEach-Object { $_.IPAddressToString }
    }
    catch {
        $out.Dns = @(); $out.DnsError = $_.Exception.Message
    }

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect($HostName, $Port, $null, $null)
        $wait = $iar.AsyncWaitHandle.WaitOne($TcpTimeoutMs)
        if (-not $wait) { $out.Tcp = 'TimedOut' }
        else { $tcp.EndConnect($iar); $out.Tcp = 'Success' }
        $tcp.Close()
    }
    catch {
        $out.Tcp = "Failed: $($_.Exception.Message)"
    }
    return $out
}

function Send-HttpClientGet {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string]$Pat,
        [switch]$SkipCertificateCheck
    )
    $res = [pscustomobject]@{
        Uri = $Uri
        StatusCode = $null
        Headers = $null
        Content = $null
        DurationMs = $null
        Exception = $null
    }

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Choose handler
        if ($SkipCertificateCheck) {
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.ServerCertificateCustomValidationCallback = { $true }
            # honor system proxy automatically
            try { $sys = [System.Net.WebRequest]::GetSystemWebProxy(); if ($sys) { $handler.UseProxy = $true; $handler.Proxy = $sys } } catch {}
        }
        else {
            try { $handler = [System.Net.Http.SocketsHttpHandler]::new(); $handler.SslOptions.EnabledSslProtocols = [System.Security.Authentication.SslProtocols]::Tls12; $handler.AllowAutoRedirect = $true } catch { $handler = New-Object System.Net.Http.HttpClientHandler }
            try { $sys = [System.Net.WebRequest]::GetSystemWebProxy(); if ($sys) { $handler.UseProxy = $true; $handler.Proxy = $sys } } catch {}
        }

        $client = [System.Net.Http.HttpClient]::new($handler)
        try { $client.Timeout = [System.TimeSpan]::FromSeconds(60) } catch {}

        $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
        if ($Pat) {
            $b = [Text.Encoding]::ASCII.GetBytes(":" + $Pat)
            $auth = [Convert]::ToBase64String($b)
            $req.Headers.TryAddWithoutValidation('Authorization', "Basic $auth") | Out-Null
        }

        try {
            $resp = $client.SendAsync($req).GetAwaiter().GetResult()
            $sw.Stop()
            $res.DurationMs = $sw.ElapsedMilliseconds
            $res.StatusCode = $resp.StatusCode.Value__
            $res.Headers = @{}
            foreach ($h in $resp.Headers) { $res.Headers[$h.Key] = ($h.Value -join ', ') }
            foreach ($h in $resp.Content.Headers) { $res.Headers[$h.Key] = ($h.Value -join ', ') }
            try { $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult(); $res.Content = $body } catch { $res.Content = "(body read error: $($_.Exception.Message))" }
        }
        catch {
            $sw.Stop()
            $res.DurationMs = $sw.ElapsedMilliseconds
            $ex = $_.Exception
            $res.Exception = "$($ex.GetType().FullName): $($ex.Message)"
            if ($ex.InnerException) { $res.Exception += " | Inner: $($ex.InnerException.GetType().FullName): $($ex.InnerException.Message)" }
        }
        finally { $client.Dispose(); if ($req) { $req.Dispose() } }
    }
    catch {
        $res.Exception = $_.Exception.Message
    }
    return $res
}

function Try-CurlVerbose {
    param([string]$Uri, [switch]$Insecure)
    $out = [pscustomobject]@{ Present = $false; Output = $null; ExitCode = $null }
    $curlCmd = Get-Command curl -ErrorAction SilentlyContinue
    if (-not $curlCmd) { return $out }
    $out.Present = $true
    try {
        # Run curl directly and capture combined stdout+stderr
        $cmd = $curlCmd.Source
        $argList = @('-v')
        if ($Insecure) { $argList += '--insecure' }
        $argList += $Uri
        # Execute and capture output
        $raw = & $cmd @argList 2>&1
        if ($raw -is [array]) { $out.Output = ($raw -join "`n") } else { $out.Output = [string]$raw }
        $out.ExitCode = $LASTEXITCODE
    }
    catch {
        $out.Output = "Failed to run curl: $($_.Exception.Message)"
    }
    return $out
}

function Get-AdoProjectsVerbose {
    Write-Host "=== Azure DevOps verbose projects diagnostic ===" -ForegroundColor Cyan

    # Load config from env or .env
    $envCfg = @{}
    $envCfg.ADO_COLLECTION_URL = $Env:ADO_COLLECTION_URL
    $envCfg.ADO_PAT = $Env:ADO_PAT
    $envCfg.ADO_API_VERSION = $Env:ADO_API_VERSION
    $envCfg.SKIP_CERTIFICATE_CHECK = $Env:SKIP_CERTIFICATE_CHECK

    $dot = Read-DotEnv
    foreach ($k in $dot.Keys) {
        if (-not $envCfg[$k]) { $envCfg[$k] = $dot[$k] }
    }

    # Normalize values
    $collectionUrl = $envCfg.ADO_COLLECTION_URL
    $pat = $envCfg.ADO_PAT
    $apiVer = if ($envCfg.ADO_API_VERSION) { $envCfg.ADO_API_VERSION } else { '7.1' }
    $skipCert = $false
    if ($envCfg.SKIP_CERTIFICATE_CHECK) {
        $skipCert = $envCfg.SKIP_CERTIFICATE_CHECK -in @('1','true','True','TRUE')
    }

    Write-Host "CollectionUrl: $collectionUrl"
    Write-Host "PAT present: $([bool]$pat)" -ForegroundColor Yellow
    Write-Host "PAT mask: $(if ($pat) { Mask-Token -token $pat } else { '(none)' })"
    Write-Host "ApiVersion: $apiVer"
    Write-Host "SkipCertificateCheck: $skipCert"
    Write-Host "Environment HTTPS_PROXY: $($Env:HTTPS_PROXY)"
    Write-Host "Environment HTTP_PROXY: $($Env:HTTP_PROXY)"
    Write-Host "Environment NO_PROXY: $($Env:NO_PROXY)"
    Write-Host "Working dir: $(Get-Location)"
    Write-Host "`n--- Building request URI ---`n"

    if (-not $collectionUrl -or -not $pat) {
        Write-Host "ERROR: ADO_COLLECTION_URL and ADO_PAT must be defined in environment or .env" -ForegroundColor Red
        return
    }

    $path = '_apis/projects?$top=5000'
    $uri = Build-AdoUri -BaseUrl $collectionUrl -Path $path -ApiVersion $apiVer
    Write-Host "Request URI: $uri"

    Write-Host "`n--- DNS & TCP diagnostics ---`n"
    $uriObj = $null
    try { $uriObj = [uri]$uri } catch { Write-Host "Invalid URI: $($_.Exception.Message)" -ForegroundColor Red; return }
    $hostName = $uriObj.Host
    $diag = Do-DnsTcpCheck -HostName $hostName -Port 443 -TcpTimeoutMs 5000
    Write-Host "Host: $($diag.Host)"; Write-Host "DNS: $($diag.Dns -join ', ')"; Write-Host "TCP: $($diag.Tcp)"
    # Safely check for an optional DnsError property (added only on exceptions in Do-DnsTcpCheck)
    if ($diag.PSObject.Properties['DnsError'] -ne $null) {
        $dnsErr = $diag.PSObject.Properties['DnsError'].Value
        Write-Host "DNS error: $dnsErr" -ForegroundColor Red
    }

    Write-Host "`n--- HttpClient request (detailed) ---`n"
    $hc = Send-HttpClientGet -Uri $uri -Pat $pat -SkipCertificateCheck:($skipCert)
    if ($hc.Exception) {
        Write-Host "HTTP request failed after $($hc.DurationMs)ms" -ForegroundColor Red
        Write-Host "Exception: $($hc.Exception)" -ForegroundColor Red
    }
    else {
        Write-Host "HTTP status: $($hc.StatusCode) (in $($hc.DurationMs)ms)" -ForegroundColor Green
    Write-Host "Response headers:" -ForegroundColor Cyan
    foreach ($k in $hc.Headers.Keys) { Write-Host ('  {0}: {1}' -f $k, $hc.Headers[$k]) }
        Write-Host "`nResponse body (first 8k):`n" -ForegroundColor Cyan
        if ($hc.Content) { Write-Host $hc.Content.Substring(0, [Math]::Min(8192, $hc.Content.Length)) } else { Write-Host '(empty)' }
    }

    Write-Host "`n--- curl fallback (verbose) ---`n"
    $curl = Try-CurlVerbose -Uri $uri -Insecure:$skipCert
    if (-not $curl.Present) { Write-Host "curl not available on PATH" -ForegroundColor Yellow }
    else {
    Write-Host "curl exit: $($curl.ExitCode)" -ForegroundColor Cyan
    $curlOut = $curl.Output -ne $null ? $curl.Output : ''
    $curlLen = 0
    try { $curlLen = [Math]::Min(12000, $curlOut.Length) } catch { $curlLen = 0 }
    if ($curlLen -gt 0) { $curlSnippet = $curlOut.Substring(0, $curlLen) } else { $curlSnippet = $curlOut }
    Write-Host "curl output (truncated 12k):`n$curlSnippet"
    }

    Write-Host "`n--- Additional checks: Invoke-WebRequest ---`n"
    try {
        $iw = $null
        $invokeStart = [DateTime]::UtcNow
        $iw = Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $pat)))" } -UseBasicParsing -ErrorAction Stop
        $invokeEnd = [DateTime]::UtcNow
        Write-Host "Invoke-WebRequest status: $($iw.StatusCode) (time: $((($invokeEnd - $invokeStart).TotalMilliseconds) )ms)" -ForegroundColor Green
        Write-Host "Headers:`n$($iw.Headers)`n`nContent (first 4k):`n$($iw.Content.Substring(0, [Math]::Min(4096, $iw.Content.Length)))"
    }
    catch {
        Write-Host "Invoke-WebRequest failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.InnerException) { Write-Host "Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red }
    }

    Write-Host "`n=== End diagnostic ===" -ForegroundColor Cyan
}

# If script is dot-sourced or executed, run the function (no parameters)
if ($MyInvocation.InvocationName -eq (Split-Path -Leaf $PSCommandPath)) {
    Write-Host "Condition met: Running as a script: call main"
    Get-AdoProjectsVerbose
}
else {
    Write-Host "Condition is NOT met: Running as a script: call main"
    Get-AdoProjectsVerbose
}
