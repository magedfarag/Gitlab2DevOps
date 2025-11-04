<#
.SYNOPSIS
    Telemetry and metrics collection module (opt-in).

.DESCRIPTION
    Provides optional telemetry collection for migration analytics including
    duration metrics, error frequency, API response times, and repository sizes.
    Exports data to CSV/JSON for analysis. Includes privacy controls and opt-out.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.0.0
    Privacy: All telemetry is opt-in and stored locally only
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Module-level telemetry context
$script:TelemetryEnabled = $false
$script:TelemetrySession = $null

<#
.SYNOPSIS
    Initializes telemetry collection for the current session.

.DESCRIPTION
    Starts a new telemetry session with optional user consent.
    Data is stored locally and never transmitted externally.

.PARAMETER SessionName
    Optional session name for tracking.

.PARAMETER Enabled
    If true, enables telemetry collection. Default is false (opt-in).

.OUTPUTS
    Telemetry session object.

.EXAMPLE
    Initialize-Telemetry -Enabled -SessionName "Migration-2024-11-04"
#>
function Initialize-Telemetry {
    [CmdletBinding()]
    param(
        [string]$SessionName = "Session-$(Get-Date -Format 'yyyyMMdd-HHmmss')",
        
        [switch]$Enabled
    )
    
    if (-not $Enabled) {
        Write-Verbose "[Telemetry] Telemetry disabled (opt-in required)"
        $script:TelemetryEnabled = $false
        return $null
    }
    
    $script:TelemetryEnabled = $true
    $script:TelemetrySession = @{
        SessionId     = [guid]::NewGuid().ToString()
        SessionName   = $SessionName
        StartTime     = Get-Date
        Events        = @()
        Metrics       = @()
        Errors        = @()
        ApiCalls      = @()
    }
    
    Write-Host "[Telemetry] Session started: $SessionName (ID: $($script:TelemetrySession.SessionId))" -ForegroundColor Cyan
    Write-Host "[Telemetry] Data will be saved locally for analysis" -ForegroundColor Cyan
    
    return $script:TelemetrySession
}

<#
.SYNOPSIS
    Records a migration event for telemetry.

.DESCRIPTION
    Captures migration events with timestamps and metadata.

.PARAMETER EventType
    Type of event (e.g., "MigrationStart", "MigrationComplete", "ProjectCreated").

.PARAMETER Project
    Project name or path.

.PARAMETER Data
    Additional event data as hashtable.

.EXAMPLE
    Record-TelemetryEvent -EventType "MigrationStart" -Project "my-project" -Data @{ SizeMB = 150 }
#>
function Record-TelemetryEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventType,
        
        [string]$Project,
        
        [hashtable]$Data = @{}
    )
    
    if (-not $script:TelemetryEnabled -or -not $script:TelemetrySession) {
        return
    }
    
    $event = @{
        Timestamp = Get-Date
        EventType = $EventType
        Project   = $Project
        Data      = $Data
    }
    
    $script:TelemetrySession.Events += $event
    Write-Verbose "[Telemetry] Event recorded: $EventType for $Project"
}

<#
.SYNOPSIS
    Records a metric value for telemetry.

.DESCRIPTION
    Captures numeric metrics like duration, size, count, etc.

.PARAMETER MetricName
    Metric name (e.g., "MigrationDurationSeconds", "RepositorySizeMB").

.PARAMETER Value
    Metric value.

.PARAMETER Unit
    Optional unit of measurement.

.PARAMETER Tags
    Optional tags for categorization.

.EXAMPLE
    Record-TelemetryMetric -MetricName "MigrationDurationSeconds" -Value 125.5 -Unit "seconds" -Tags @{ Project = "my-project" }
#>
function Record-TelemetryMetric {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MetricName,
        
        [Parameter(Mandatory)]
        [double]$Value,
        
        [string]$Unit = "",
        
        [hashtable]$Tags = @{}
    )
    
    if (-not $script:TelemetryEnabled -or -not $script:TelemetrySession) {
        return
    }
    
    $metric = @{
        Timestamp  = Get-Date
        MetricName = $MetricName
        Value      = $Value
        Unit       = $Unit
        Tags       = $Tags
    }
    
    $script:TelemetrySession.Metrics += $metric
    Write-Verbose "[Telemetry] Metric recorded: $MetricName = $Value $Unit"
}

<#
.SYNOPSIS
    Records an error for telemetry.

.DESCRIPTION
    Captures error details for analysis and troubleshooting.

.PARAMETER ErrorMessage
    Error message.

.PARAMETER ErrorType
    Type of error (e.g., "GitError", "ApiError", "ValidationError").

.PARAMETER Context
    Additional context as hashtable.

.EXAMPLE
    Record-TelemetryError -ErrorMessage "Git clone failed" -ErrorType "GitError" -Context @{ Project = "my-project" }
#>
function Record-TelemetryError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ErrorMessage,
        
        [string]$ErrorType = "General",
        
        [hashtable]$Context = @{}
    )
    
    if (-not $script:TelemetryEnabled -or -not $script:TelemetrySession) {
        return
    }
    
    $error = @{
        Timestamp    = Get-Date
        ErrorMessage = $ErrorMessage
        ErrorType    = $ErrorType
        Context      = $Context
    }
    
    $script:TelemetrySession.Errors += $error
    Write-Verbose "[Telemetry] Error recorded: $ErrorType - $ErrorMessage"
}

<#
.SYNOPSIS
    Records an API call for telemetry.

.DESCRIPTION
    Captures API call details including method, endpoint, duration, and status.

.PARAMETER Method
    HTTP method (GET, POST, PUT, etc.).

.PARAMETER Endpoint
    API endpoint path.

.PARAMETER DurationMs
    Duration in milliseconds.

.PARAMETER StatusCode
    HTTP status code.

.PARAMETER Success
    If true, indicates successful call.

.EXAMPLE
    Record-TelemetryApiCall -Method "GET" -Endpoint "/_apis/projects" -DurationMs 250 -StatusCode 200 -Success
#>
function Record-TelemetryApiCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter(Mandatory)]
        [int]$DurationMs,
        
        [int]$StatusCode = 0,
        
        [switch]$Success
    )
    
    if (-not $script:TelemetryEnabled -or -not $script:TelemetrySession) {
        return
    }
    
    $apiCall = @{
        Timestamp   = Get-Date
        Method      = $Method
        Endpoint    = $Endpoint
        DurationMs  = $DurationMs
        StatusCode  = $StatusCode
        Success     = $Success.IsPresent
    }
    
    $script:TelemetrySession.ApiCalls += $apiCall
    Write-Verbose "[Telemetry] API call recorded: $Method $Endpoint ($DurationMs ms)"
}

<#
.SYNOPSIS
    Exports telemetry data to file.

.DESCRIPTION
    Exports collected telemetry to JSON or CSV format for analysis.

.PARAMETER OutputPath
    Output file path.

.PARAMETER Format
    Export format: JSON or CSV. Default is JSON.

.EXAMPLE
    Export-TelemetryData -OutputPath "C:\telemetry\session.json"

.EXAMPLE
    Export-TelemetryData -OutputPath "C:\telemetry\metrics.csv" -Format CSV
#>
function Export-TelemetryData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [ValidateSet("JSON", "CSV")]
        [string]$Format = "JSON"
    )
    
    if (-not $script:TelemetryEnabled -or -not $script:TelemetrySession) {
        Write-Warning "No telemetry data to export (telemetry not enabled or no session)"
        return
    }
    
    # Ensure directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Add session summary
    $endTime = Get-Date
    $duration = $endTime - $script:TelemetrySession.StartTime
    
    $sessionSummary = @{
        SessionId        = $script:TelemetrySession.SessionId
        SessionName      = $script:TelemetrySession.SessionName
        StartTime        = $script:TelemetrySession.StartTime.ToString('yyyy-MM-dd HH:mm:ss')
        EndTime          = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
        DurationMinutes  = [math]::Round($duration.TotalMinutes, 2)
        TotalEvents      = $script:TelemetrySession.Events.Count
        TotalMetrics     = $script:TelemetrySession.Metrics.Count
        TotalErrors      = $script:TelemetrySession.Errors.Count
        TotalApiCalls    = $script:TelemetrySession.ApiCalls.Count
    }
    
    if ($Format -eq "JSON") {
        $exportData = @{
            Summary  = $sessionSummary
            Events   = $script:TelemetrySession.Events
            Metrics  = $script:TelemetrySession.Metrics
            Errors   = $script:TelemetrySession.Errors
            ApiCalls = $script:TelemetrySession.ApiCalls
        }
        
        $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "[Telemetry] Data exported to JSON: $OutputPath" -ForegroundColor Green
    }
    elseif ($Format -eq "CSV") {
        # Export metrics to CSV (most useful for analysis)
        if ($script:TelemetrySession.Metrics.Count -gt 0) {
            $script:TelemetrySession.Metrics | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            Write-Host "[Telemetry] Metrics exported to CSV: $OutputPath" -ForegroundColor Green
        }
        else {
            Write-Warning "No metrics data to export to CSV"
        }
    }
    
    # Display summary
    Write-Host "[Telemetry] Session Summary:" -ForegroundColor Cyan
    Write-Host "  Session: $($sessionSummary.SessionName)"
    Write-Host "  Duration: $($sessionSummary.DurationMinutes) minutes"
    Write-Host "  Events: $($sessionSummary.TotalEvents)"
    Write-Host "  Metrics: $($sessionSummary.TotalMetrics)"
    Write-Host "  Errors: $($sessionSummary.TotalErrors)"
    Write-Host "  API Calls: $($sessionSummary.TotalApiCalls)"
}

<#
.SYNOPSIS
    Gets telemetry statistics for the current session.

.DESCRIPTION
    Returns summary statistics from the current telemetry session.

.OUTPUTS
    Hashtable with telemetry statistics.

.EXAMPLE
    $stats = Get-TelemetryStatistics
#>
function Get-TelemetryStatistics {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    if (-not $script:TelemetryEnabled -or -not $script:TelemetrySession) {
        Write-Warning "No active telemetry session"
        return @{}
    }
    
    $duration = (Get-Date) - $script:TelemetrySession.StartTime
    
    # Calculate API statistics
    $apiStats = @{
        TotalCalls      = $script:TelemetrySession.ApiCalls.Count
        SuccessfulCalls = ($script:TelemetrySession.ApiCalls | Where-Object { $_.Success }).Count
        FailedCalls     = ($script:TelemetrySession.ApiCalls | Where-Object { -not $_.Success }).Count
        AvgDurationMs   = if ($script:TelemetrySession.ApiCalls.Count -gt 0) {
            [math]::Round(($script:TelemetrySession.ApiCalls | Measure-Object -Property DurationMs -Average).Average, 2)
        } else { 0 }
    }
    
    # Calculate error statistics
    $errorStats = @{
        TotalErrors = $script:TelemetrySession.Errors.Count
        ErrorTypes  = ($script:TelemetrySession.Errors | Group-Object -Property ErrorType | 
            ForEach-Object { @{ Type = $_.Name; Count = $_.Count } })
    }
    
    return @{
        SessionId       = $script:TelemetrySession.SessionId
        SessionName     = $script:TelemetrySession.SessionName
        DurationMinutes = [math]::Round($duration.TotalMinutes, 2)
        EventCount      = $script:TelemetrySession.Events.Count
        MetricCount     = $script:TelemetrySession.Metrics.Count
        ApiStatistics   = $apiStats
        ErrorStatistics = $errorStats
    }
}

Export-ModuleMember -Function @(
    'Initialize-Telemetry',
    'Record-TelemetryEvent',
    'Record-TelemetryMetric',
    'Record-TelemetryError',
    'Record-TelemetryApiCall',
    'Export-TelemetryData',
    'Get-TelemetryStatistics'
)
