$path = 'C:\Projects\devops\Gitlab2DevOps\modules\Migration\TeamPacks\TeamPacks.psm1'
$content = Get-Content -Raw -Path $path
$errors = @()
[System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$errors) | Out-Null
if ($errors.Count -eq 0) {
    Write-Host "No parse errors"
} else {
    foreach ($e in $errors) {
        Write-Host "Error: $($e.Message) at $($e.Extent.StartLineNumber):$($e.Extent.StartColumn)"
    }
}
