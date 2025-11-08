try {
    Import-Module .\modules\core\Logging.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Logging.psm1 loaded successfully" -ForegroundColor Green
    Import-Module .\modules\GitLab\GitLab.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] GitLab.psm1 loaded successfully" -ForegroundColor Green
    Import-Module .\modules\Migration\Workflows\SingleMigration.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] SingleMigration.psm1 loaded successfully" -ForegroundColor Green
    Write-Host "[SUCCESS] All modules loaded!" -ForegroundColor Cyan
} catch {
    Write-Host "[ERROR] Module load failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    exit 1
}
