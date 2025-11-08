$file='c:\Projects\devops\Gitlab2DevOps\modules\adapters\AzureDevOps\Wikis.psm1'
$lines=Get-Content $file
for ($i=189; $i -le 219; $i++){
    Write-Output ("{0}: {1}" -f $i, $lines[$i-1])
}