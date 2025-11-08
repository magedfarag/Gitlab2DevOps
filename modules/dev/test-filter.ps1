$users = @(
    @{ id = $null; username = 'test1' }
    @{ id = 1; username = 'test2' }
)

Write-Host "Original count: $($users.Count)"
$valid = @($users | Where-Object { $null -ne $_.id })
Write-Host "Filtered count: $($valid.Count)"
$valid | ForEach-Object { Write-Host "  id=$($_.id), username=$($_.username)" }

Write-Host "`nTest empty username:"
$users2 = @(
    @{ id = 1; username = '' }
    @{ id = 2; username = 'test' }
)
$valid2 = @($users2 | Where-Object { -not [string]::IsNullOrWhiteSpace($_.username) })
Write-Host "Filtered count: $($valid2.Count)"
$valid2 | ForEach-Object { Write-Host "  id=$($_.id), username=$($_.username)" }
