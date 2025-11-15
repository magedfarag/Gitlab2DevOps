$errors = $null
$tokens = $null
$path = 'C:\Projects\devops\Gitlab2DevOps\modules\Migration\Workflows\BulkMigration.psm1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors) {
    foreach ($e in $errors) {
        Write-Host "ERROR: $($e.Message) at $($e.Extent.StartLineNumber):$($e.Extent.StartColumn)"
    }
    exit 1
}
else {
    Write-Host 'BulkMigration parse OK'
}
