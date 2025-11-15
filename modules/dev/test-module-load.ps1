try {
    Import-Module -WarningAction SilentlyContinue .\modules\core\Logging.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Logging.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\core\Core.Rest.psm1 -Force -DisableNameChecking -ErrorAction Stop
    Write-Host "[SUCCESS] Core.Rest.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\GitLab\GitLab.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] GitLab.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\AzureDevOps.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\Core.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Core.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\Security.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Security.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\Projects.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Projects.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\Repositories.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Repositories.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\Wikis.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Wikis.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\WorkItems.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\WorkItems.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\Dashboards.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Dashboards.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Migration\Core\Core.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Core\Core.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Migration\Menu\Menu.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Menu\Menu.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Migration\Initialization\Initialization.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Initialization\Initialization.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Migration\TeamPacks\TeamPacks.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\TeamPacks\TeamPacks.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Migration\Workflows\SingleMigration.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Workflows\SingleMigration.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Migration.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\DryRunPreview.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] DryRunPreview.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\ProgressTracking.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] ProgressTracking.psm1 loaded successfully" -ForegroundColor Green

    Import-Module -WarningAction SilentlyContinue .\modules\Telemetry.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Telemetry.psm1 loaded successfully" -ForegroundColor Green

    Write-Host "[SUCCESS] All modules loaded!" -ForegroundColor Cyan
}
 catch {
    Write-Host "[ERROR] Module load failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    exit 1
}
