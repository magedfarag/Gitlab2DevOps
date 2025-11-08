$file = 'c:\Projects\devops\Gitlab2DevOps\modules\adapters\AzureDevOps\Wikis.psm1'
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors) {
    foreach ($e in $errors) {
        Write-Output "--- ERROR ---"
        Write-Output "Message: $($e.Message)"
        Write-Output "Line: $($e.Extent.StartLineNumber) Column: $($e.Extent.StartColumn)"
        Write-Output "Text: $($e.Extent.Text.Trim())"
        # show context lines
        $start = [Math]::Max(1, $e.Extent.StartLineNumber - 3)
        $end = [Math]::Min($lines.Count, $e.Extent.EndLineNumber + 3)
    Write-Output ("Context lines {0}..{1}:" -f $start, $end)
    for ($i = $start; $i -le $end; $i++) { Write-Output ("{0}: {1}" -f $i, $lines[$i-1]) }
    }
    exit 1
}
Write-Output 'PARSE OK'
