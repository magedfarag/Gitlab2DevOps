$path = 'C:\Projects\devops\Gitlab2DevOps\modules\Migration\TeamPacks\TeamPacks.psm1'
$lines = Get-Content -Path $path
$start = 100
$end = 150
for ($i = $start; $i -le $end; $i++) {
    $line = $lines[$i-1]
    "{0,4}: {1}" -f $i, $line
}
