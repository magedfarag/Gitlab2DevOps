try {
    Import-Module .\modules\core\Logging.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Logging.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\core\Core.Rest.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Core.Rest.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\GitLab\GitLab.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] GitLab.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\AzureDevOps.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\Core.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Core.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\Security.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Security.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\Projects.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Projects.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\Repositories.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Repositories.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\Wikis.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Wikis.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\WorkItems.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\WorkItems.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\AzureDevOps\Dashboards.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] AzureDevOps\Dashboards.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Migration\Core\Core.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Core\Core.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Migration\Menu\Menu.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Menu\Menu.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Migration\Initialization\Initialization.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Initialization\Initialization.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Migration\TeamPacks\TeamPacks.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\TeamPacks\TeamPacks.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Migration\Workflows\SingleMigration.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration\Workflows\SingleMigration.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Migration.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Migration.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\DryRunPreview.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] DryRunPreview.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\ProgressTracking.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] ProgressTracking.psm1 loaded successfully" -ForegroundColor Green

    Import-Module .\modules\Telemetry.psm1 -Force -ErrorAction Stop
    Write-Host "[SUCCESS] Telemetry.psm1 loaded successfully" -ForegroundColor Green

    Write-Host "[SUCCESS] All modules loaded!" -ForegroundColor Cyan
}
 catch {
    Write-Host "[ERROR] Module load failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host $_.ScriptStackTrace
    exit 1
}
