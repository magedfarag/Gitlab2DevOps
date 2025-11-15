$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Projects\devops\Gitlab2DevOps\modules\AzureDevOps\WorkItems.psm1',[ref]$tokens,[ref]$errors)
if ($errors) {
    foreach ($e in $errors) {
        Write-Host "ERROR: $($e.Message) at $($e.Extent.StartLineNumber):$($e.Extent.StartColumn)"
    }
    exit 1
} else {
    Write-Host 'PARSE_OK'
}
