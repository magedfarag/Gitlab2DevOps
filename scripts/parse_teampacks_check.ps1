$path = 'c:\Projects\devops\Gitlab2DevOps\modules\Migration\TeamPacks\TeamPacks.psm1'
$s = Get-Content -LiteralPath $path -Raw
try {
    $dummy = [scriptblock]::Create($s)
    Write-Host 'PARSE_OK'
}
catch {
    Write-Host $_.Exception.ToString()
    exit 2
}