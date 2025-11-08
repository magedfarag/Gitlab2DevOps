$since = [datetime]'2024-01-01'
$user1 = @{ id = 1; username = 'old'; created_at = '2023-06-01T00:00:00Z' }
$user2 = @{ id = 2; username = 'new'; created_at = '2024-06-01T00:00:00Z' }

Write-Host "Testing date filter..."
Write-Host "Input array count: $((@($user1, $user2)).Count)"

$filtered = @($user1, $user2) | Where-Object { 
    if (-not $_.created_at) {
        Write-Host "  No created_at for $($_.username)"
        return $false
    }
    $createdDate = [datetime]::Parse($_.created_at)
    $result = ($createdDate -ge $since)
    Write-Host "  $($_.username): $($_.created_at) >= $since = $result"
    return $result
}

Write-Host "`nFiltered count: $($filtered.Count)"
Write-Host "Filtered is array: $($filtered -is [array])"
Write-Host "Filtered type: $($filtered.GetType().FullName)"
$filtered | ForEach-Object { 
    Write-Host "  - Item type: $($_.GetType().FullName), username: $($_.username)" 
}
