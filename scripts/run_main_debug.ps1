try {
    . "c:\Projects\devops\Gitlab2DevOps\Gitlab2DevOps.ps1" -Verbose
}
catch {
    Write-Host "ERROR DETAILS:" -ForegroundColor Red
    $_ | Format-List * -Force
    if ($_.Exception) { Write-Host "Exception:"; $_.Exception | Format-List * -Force }
    if ($_.InvocationInfo) { Write-Host "InvocationInfo:"; $_.InvocationInfo | Format-List * -Force }
    exit 1
}