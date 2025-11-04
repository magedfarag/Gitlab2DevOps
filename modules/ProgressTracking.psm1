<#
.SYNOPSIS
    Progress tracking module with Write-Progress support.

.DESCRIPTION
    Provides progress tracking utilities for long-running operations like
    git clones, bulk migrations, and policy applications. Improves UX with
    visual progress bars and estimated time remaining.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Starts a progress tracking session for a long-running operation.

.DESCRIPTION
    Initializes progress tracking with total items and operation details.
    Returns a progress context object for updating during the operation.

.PARAMETER Activity
    The main activity description (e.g., "Migrating Projects").

.PARAMETER TotalItems
    Total number of items to process.

.PARAMETER Status
    Initial status message.

.OUTPUTS
    Progress context object with tracking data.

.EXAMPLE
    $progress = Start-MigrationProgress -Activity "Bulk Migration" -TotalItems 10 -Status "Initializing..."
#>
function Start-MigrationProgress {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,
        
        [Parameter(Mandatory)]
        [int]$TotalItems,
        
        [string]$Status = "Starting..."
    )
    
    $context = @{
        Activity      = $Activity
        TotalItems    = $TotalItems
        CurrentItem   = 0
        StartTime     = Get-Date
        Status        = $Status
        Id            = Get-Random -Minimum 1 -Maximum 100
    }
    
    Write-Progress `
        -Id $context.Id `
        -Activity $context.Activity `
        -Status $context.Status `
        -PercentComplete 0
    
    return $context
}

<#
.SYNOPSIS
    Updates progress during a long-running operation.

.DESCRIPTION
    Updates the progress bar with current item, status, and estimated time.
    Calculates percentage and ETA based on elapsed time.

.PARAMETER Context
    Progress context from Start-MigrationProgress.

.PARAMETER CurrentItem
    Current item number being processed.

.PARAMETER Status
    Status message describing current operation.

.PARAMETER CurrentOperation
    Optional detailed operation description.

.EXAMPLE
    Update-MigrationProgress -Context $progress -CurrentItem 5 -Status "Migrating project-5" -CurrentOperation "Pushing to Azure DevOps"
#>
function Update-MigrationProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context,
        
        [Parameter(Mandatory)]
        [int]$CurrentItem,
        
        [Parameter(Mandatory)]
        [string]$Status,
        
        [string]$CurrentOperation
    )
    
    $Context.CurrentItem = $CurrentItem
    $Context.Status = $Status
    
    # Calculate percentage
    $percentComplete = [int](($CurrentItem / $Context.TotalItems) * 100)
    
    # Calculate ETA
    $elapsed = (Get-Date) - $Context.StartTime
    if ($CurrentItem -gt 0) {
        $avgTimePerItem = $elapsed.TotalSeconds / $CurrentItem
        $remainingItems = $Context.TotalItems - $CurrentItem
        $estimatedSeconds = $remainingItems * $avgTimePerItem
        $eta = [TimeSpan]::FromSeconds($estimatedSeconds)
        
        $etaString = if ($eta.TotalMinutes -lt 1) {
            "$([int]$eta.TotalSeconds) seconds remaining"
        } elseif ($eta.TotalHours -lt 1) {
            "$([int]$eta.TotalMinutes) minutes remaining"
        } else {
            "$([int]$eta.TotalHours) hours, $($eta.Minutes) minutes remaining"
        }
        
        $statusMessage = "$Status - $etaString"
    } else {
        $statusMessage = $Status
    }
    
    $progressParams = @{
        Id              = $Context.Id
        Activity        = $Context.Activity
        Status          = $statusMessage
        PercentComplete = $percentComplete
    }
    
    if ($CurrentOperation) {
        $progressParams['CurrentOperation'] = $CurrentOperation
    }
    
    Write-Progress @progressParams
}

<#
.SYNOPSIS
    Completes a progress tracking session.

.DESCRIPTION
    Finalizes progress tracking and clears the progress bar.

.PARAMETER Context
    Progress context from Start-MigrationProgress.

.EXAMPLE
    Complete-MigrationProgress -Context $progress
#>
function Complete-MigrationProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    
    Write-Progress `
        -Id $Context.Id `
        -Activity $Context.Activity `
        -Status "Completed" `
        -PercentComplete 100 `
        -Completed
}

<#
.SYNOPSIS
    Tracks progress for git clone operations.

.DESCRIPTION
    Wraps git clone with progress monitoring. Since git clone doesn't provide
    progress callbacks, this shows elapsed time and activity status.

.PARAMETER Url
    Git repository URL.

.PARAMETER Destination
    Local destination path.

.PARAMETER Mirror
    If true, performs a mirror clone.

.PARAMETER SizeEstimateMB
    Optional size estimate for better ETA calculation.

.EXAMPLE
    Invoke-GitCloneWithProgress -Url "https://gitlab.com/org/repo.git" -Destination "C:\temp\repo" -Mirror
#>
function Invoke-GitCloneWithProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        
        [Parameter(Mandatory)]
        [string]$Destination,
        
        [switch]$Mirror,
        
        [int]$SizeEstimateMB = 0
    )
    
    $activity = "Cloning Repository"
    $status = "Downloading from $Url"
    
    if ($SizeEstimateMB -gt 0) {
        $status += " ($SizeEstimateMB MB)"
    }
    
    Write-Progress -Activity $activity -Status $status -PercentComplete 0
    
    $startTime = Get-Date
    
    try {
        # Build git command
        $gitArgs = @('clone')
        if ($Mirror) {
            $gitArgs += '--mirror'
        }
        $gitArgs += @($Url, $Destination)
        
        # Execute git clone
        & git @gitArgs 2>&1 | ForEach-Object {
            # Git outputs progress to stderr, monitor for completion
            if ($_ -match 'Receiving objects:.*(\d+)%') {
                $percent = [int]$Matches[1]
                Write-Progress -Activity $activity -Status "Receiving objects: $percent%" -PercentComplete $percent
            }
            elseif ($_ -match 'Resolving deltas:.*(\d+)%') {
                $percent = [int]$Matches[1]
                Write-Progress -Activity $activity -Status "Resolving deltas: $percent%" -PercentComplete $percent
            }
            # Pass through output
            $_
        }
        
        $elapsed = (Get-Date) - $startTime
        Write-Progress -Activity $activity -Status "Completed in $([int]$elapsed.TotalSeconds) seconds" -Completed
    }
    catch {
        Write-Progress -Activity $activity -Completed
        throw
    }
}

Export-ModuleMember -Function @(
    'Start-MigrationProgress',
    'Update-MigrationProgress',
    'Complete-MigrationProgress',
    'Invoke-GitCloneWithProgress'
)
