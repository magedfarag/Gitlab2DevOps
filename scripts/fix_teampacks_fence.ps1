$path = 'c:\Projects\devops\Gitlab2DevOps\modules\Migration\TeamPacks\TeamPacks.psm1'
Write-Host "Fixing fences in $path"
$content = Get-Content -LiteralPath $path -ErrorAction Stop
$filtered = $content | Where-Object { $_.Trim() -ne '```powershell' -and $_.Trim() -ne '```' }
Set-Content -LiteralPath $path -Value $filtered -Encoding UTF8
Write-Host "Done"