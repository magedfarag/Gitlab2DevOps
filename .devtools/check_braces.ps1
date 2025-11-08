$file='c:\Projects\devops\Gitlab2DevOps\modules\adapters\AzureDevOps\Wikis.psm1'
$lines = Get-Content $file
$open=0
$max=0
$maxLine=0
for ($i=0;$i -lt $lines.Count;$i++){
    $line=$lines[$i]
    $open += ([regex]::Matches($line,'\\{').Count)
    $open -= ([regex]::Matches($line,'\\}').Count)
    if ($open -lt 0) { Write-Output "NEGATIVE at line $($i+1): $line"; break }
    if ($open -gt $max) { $max=$open; $maxLine=$i+1 }
}
Write-Output "Final brace balance: $open"
Write-Output "Max open braces $max at line $maxLine"
