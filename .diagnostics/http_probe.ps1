$u = 'https://dev.azure.com/_apis/projects?api-version=7.1'
Write-Host "URL: $u"
try {
    $c = New-Object System.Net.Http.HttpClient
    $t = $c.GetAsync($u)
    $t.Wait()
    $r = $t.Result
    Write-Host "HTTP status: $($r.StatusCode)"
}
catch {
    Write-Host "HttpClient exception: $($_.Exception.ToString())"
    if ($_.Exception.InnerException) { Write-Host 'Inner:'; Write-Host $_.Exception.InnerException.ToString() }
}
