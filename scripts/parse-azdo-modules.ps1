$dir = Join-Path $PSScriptRoot '..\modules\AzureDevOps'
Get-ChildItem -Path $dir -Filter '*.psm1' | ForEach-Object {
    $file = $_.FullName
    $null1 = $null; $null2 = $null
    try {
        [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null1, [ref]$null2) | Out-Null
        Write-Host "$($_.Name): Parse OK" -ForegroundColor Green
    }
    catch {
        Write-Host "$($_.Name): PARSE ERROR -> $($_.Exception.Message)" -ForegroundColor Red
    }
}
