Set-StrictMode -Version Latest
$errors = @()
Get-ChildItem -Path "$PSScriptRoot\..\modules" -Filter *.psm1 -Recurse | ForEach-Object {
    $path = $_.FullName
    try {
        [System.Management.Automation.ScriptBlock]::Create((Get-Content -Raw -Path $path)) > $null
        Write-Host "PARSE OK: $path" -ForegroundColor Green
    }
    catch {
        Write-Host "PARSE FAIL: $path -- $($_.Exception.Message)" -ForegroundColor Red
        $errors += $path
    }
}
if ($errors.Count -gt 0) {
    Write-Error "Syntax errors detected in $($errors.Count) files"
    exit 2
}
else {
    Write-Host "All module files parsed successfully" -ForegroundColor Green
    exit 0
}
