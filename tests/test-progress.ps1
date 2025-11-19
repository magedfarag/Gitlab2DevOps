# Test script to demonstrate stable progress bar
$config = Get-Content 'projects.json' | ConvertFrom-Json

$totalEntries = $config.Count
$currentEntryIndex = 0

Write-Progress -Activity "Bulk Migration Preparation" -Status "Starting preparation of $totalEntries entries..." -PercentComplete 0 -Id 1

foreach ($entry in $config) {
    $currentEntryIndex++
    $adoProject = $entry.adoproject
    $projectPaths = $entry.projects

    $entryProgress = [math]::Round((($currentEntryIndex - 1) / $totalEntries) * 100)
    Write-Progress -Activity "Bulk Migration Preparation" -Status "Processing Azure DevOps project: $adoProject ($currentEntryIndex of $totalEntries)" -PercentComplete $entryProgress -Id 1

    Write-Host "[INFO] Processing $adoProject..."

    # Simulate some work
    Start-Sleep -Milliseconds 500

    # Update overall progress after processing each entry
    $overallProgress = [math]::Round(($currentEntryIndex / $totalEntries) * 100)
    Write-Progress -Activity "Bulk Migration Preparation" -Status "Completed entry $currentEntryIndex of $totalEntries ($adoProject)" -PercentComplete $overallProgress -Id 1
}

Write-Progress -Activity "Bulk Migration Preparation" -Status "All entries processed successfully" -PercentComplete 100 -Id 1
Write-Host "[SUCCESS] Progress bar demonstration complete."