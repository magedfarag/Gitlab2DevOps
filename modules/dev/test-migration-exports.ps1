Import-Module -WarningAction SilentlyContinue '.\modules\Migration.psm1' -Force

Write-Host "`n=== Loaded Modules ===" -ForegroundColor Cyan
Get-Module | Where-Object { $_.Name -match 'Core|Menu|Project|Team|Single|Bulk|Migration' } | 
    Select-Object Name, Path | Format-Table -AutoSize

Write-Host "`n=== Migration Module Exports ===" -ForegroundColor Cyan
$migrationModule = Get-Module Migration
if ($migrationModule) {
    $exports = $migrationModule.ExportedFunctions.Keys | Sort-Object
    Write-Host "Export count: $($exports.Count)"
    $exports | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "Migration module not found!" -ForegroundColor Red
}

Write-Host "`n=== TeamPacks Module Exports ===" -ForegroundColor Cyan
$teamPacksModule = Get-Module TeamPacks
if ($teamPacksModule) {
    $teamPacksModule.ExportedFunctions.Keys | Sort-Object | ForEach-Object { Write-Host "  - $_" }
} else {
    Write-Host "TeamPacks module not found!" -ForegroundColor Yellow
}
