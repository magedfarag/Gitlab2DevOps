Set-Location 'c:\Projects\devops\Gitlab2DevOps'
Import-Module -WarningAction SilentlyContinue .\modules\core\Core.Rest.psm1 -Force
Import-Module -WarningAction SilentlyContinue .\modules\AzureDevOps\WorkItems.psm1 -Force
# Write-Host '--- Get-CoreRestConfig ---'
# try { (Get-CoreRestConfig) | ConvertTo-Json -Compress } catch { Write-Host 'Get-CoreRestConfig failed:' $_.Exception.Message }
Write-Host '--- script:CollectionUrl ---'
try { if (Get-Variable -Name script:CollectionUrl -Scope Script -ErrorAction SilentlyContinue) { Write-Host $script:CollectionUrl } else { Write-Host '<not set>' } } catch { Write-Host 'variable check failed:' $_.Exception.Message }
Write-Host '--- script:workItemTypesCache ---'
try { if (Get-Variable -Name script:workItemTypesCache -Scope Script -ErrorAction SilentlyContinue) { $script:workItemTypesCache | ConvertTo-Json -Compress } else { Write-Host '<not set>' } } catch { Write-Host 'cache check failed:' $_.Exception.Message }
Write-Host '--- Excel file exists? ---'
Write-Host (Test-Path 'c:\Projects\devops\Gitlab2DevOps\migrations\edamah\requirements.xlsx')
