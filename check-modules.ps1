Import-Module -WarningAction SilentlyContinue 'c:\Projects\devops\Gitlab2DevOps\modules\AzureDevOps\AzureDevOps.psm1' -Force
$modules = Get-Module | Where-Object { $_.Name -like '*Azure*' -or $_.Name -like '*Core*' -or $_.Name -like '*Wiki*' -or $_.Name -like '*Dash*' -or $_.Name -like '*Work*' -or $_.Name -like '*Repo*' }
$modules | Select-Object Name, Path | Format-Table -AutoSize
Write-Host "`nTest-AdoProjectExists available: $(Get-Command Test-AdoProjectExists -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)"
