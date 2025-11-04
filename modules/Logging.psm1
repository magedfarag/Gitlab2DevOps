<#
.SYNOPSIS
    Logging and path management functions for migrations.

.DESCRIPTION
    This module provides consistent logging, reporting, and file path management
    for migration operations. Ensures all logs and reports follow standard
    directory structure.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.0.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Gets the base migrations directory path.

.DESCRIPTION
    Returns standardized migrations directory path. Creates if missing.

.OUTPUTS
    Absolute path to migrations directory.

.EXAMPLE
    Get-MigrationsDirectory
#>
function Get-MigrationsDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    $migrationsDir = Join-Path (Get-Location) "migrations"
    
    if (-not (Test-Path $migrationsDir)) {
        New-Item -ItemType Directory -Path $migrationsDir -Force | Out-Null
        Write-Verbose "[Logging] Created migrations directory: $migrationsDir"
    }
    
    return $migrationsDir
}

<#
.SYNOPSIS
    Gets the project-specific directory path.

.DESCRIPTION
    Returns path to project folder within migrations directory.
    Creates directory structure if missing.

.PARAMETER ProjectName
    Project name (used as folder name).

.OUTPUTS
    Hashtable with projectDir, reportsDir, logsDir, repositoryDir paths.

.EXAMPLE
    Get-ProjectPaths "my-project"
#>
function Get-ProjectPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
    
    $migrationsDir = Get-MigrationsDirectory
    $projectDir = Join-Path $migrationsDir $ProjectName
    $reportsDir = Join-Path $projectDir "reports"
    $logsDir = Join-Path $projectDir "logs"
    $repositoryDir = Join-Path $projectDir "repository"
    
    # Create directories if missing
    @($projectDir, $reportsDir, $logsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Verbose "[Logging] Created directory: $_"
        }
    }
    
    return @{
        projectDir    = $projectDir
        reportsDir    = $reportsDir
        logsDir       = $logsDir
        repositoryDir = $repositoryDir
    }
}

<#
.SYNOPSIS
    Writes timestamped log entry to file.

.DESCRIPTION
    Appends log message with timestamp to specified log file.
    Creates parent directories if needed.

.PARAMETER LogFile
    Path to log file.

.PARAMETER Message
    Log message (can be array of strings).

.PARAMETER Level
    Log level (INFO, WARN, ERROR, SUCCESS).

.EXAMPLE
    Write-MigrationLog $logFile "Migration started" -Level INFO
#>
function Write-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogFile,
        
        [Parameter(Mandatory)]
        [object]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    # Ensure parent directory exists
    $parentDir = Split-Path -Parent $LogFile
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    # Handle array of messages
    if ($Message -is [array]) {
        foreach ($line in $Message) {
            "[$timestamp] [$Level] $line" | Out-File -FilePath $LogFile -Append -Encoding utf8
        }
    }
    else {
        "[$timestamp] [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    }
    
    Write-Verbose "[Logging] Wrote $Level message to $LogFile"
}

<#
.SYNOPSIS
    Writes JSON report to file.

.DESCRIPTION
    Converts object to JSON and writes to file with proper encoding.
    Creates parent directories if needed.

.PARAMETER ReportFile
    Path to report file.

.PARAMETER Data
    Object to serialize to JSON.

.PARAMETER Depth
    JSON serialization depth (default: 10).

.EXAMPLE
    Write-MigrationReport $reportFile $reportData
#>
function Write-MigrationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ReportFile,
        
        [Parameter(Mandatory)]
        [object]$Data,
        
        [int]$Depth = 10
    )
    
    # Ensure parent directory exists
    $parentDir = Split-Path -Parent $ReportFile
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    $Data | ConvertTo-Json -Depth $Depth | Out-File -FilePath $ReportFile -Encoding utf8
    Write-Verbose "[Logging] Wrote report to $ReportFile"
}

<#
.SYNOPSIS
    Creates a timestamped log file path.

.DESCRIPTION
    Generates log file name with timestamp and optional prefix.

.PARAMETER LogsDir
    Directory for log files.

.PARAMETER Prefix
    Log file prefix (default: "log").

.OUTPUTS
    Full path to log file.

.EXAMPLE
    New-LogFilePath $logsDir "migration"
#>
function New-LogFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$LogsDir,
        
        [string]$Prefix = "log"
    )
    
    if (-not (Test-Path $LogsDir)) {
        New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Join-Path $LogsDir "$Prefix-$timestamp.log"
}

<#
.SYNOPSIS
    Creates a timestamped report file path.

.DESCRIPTION
    Generates report file name with timestamp and optional prefix.

.PARAMETER ReportsDir
    Directory for report files.

.PARAMETER Prefix
    Report file prefix (default: "report").

.PARAMETER Extension
    File extension (default: "json").

.OUTPUTS
    Full path to report file.

.EXAMPLE
    New-ReportFilePath $reportsDir "migration-summary"
#>
function New-ReportFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ReportsDir,
        
        [string]$Prefix = "report",
        
        [string]$Extension = "json"
    )
    
    if (-not (Test-Path $ReportsDir)) {
        New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Join-Path $ReportsDir "$Prefix-$timestamp.$Extension"
}

<#
.SYNOPSIS
    Writes formatted console output with color.

.DESCRIPTION
    Standardized console output with severity-based coloring.

.PARAMETER Message
    Message to display.

.PARAMETER Level
    Message level (INFO, WARN, ERROR, SUCCESS).

.EXAMPLE
    Write-MigrationMessage "Operation complete" -Level SUCCESS
#>
function Write-MigrationMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $color = switch ($Level) {
        'INFO' { 'White' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    
    $prefix = switch ($Level) {
        'INFO' { '[INFO]' }
        'WARN' { '[WARN]' }
        'ERROR' { '[ERROR]' }
        'SUCCESS' { '[OK]' }
        'DEBUG' { '[DEBUG]' }
        default { '[INFO]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}

<#
.SYNOPSIS
    Creates a run manifest for tracking migration execution.

.DESCRIPTION
    Generates a manifest file in migrations/ root with metadata about the migration run.
    Useful for auditing, debugging, and tracking automation history.

.PARAMETER RunId
    Unique run identifier (default: generated GUID).

.PARAMETER Mode
    Migration mode (Preflight, Initialize, Migrate, BulkPrepare, BulkMigrate).

.PARAMETER Source
    Source GitLab project path.

.PARAMETER Project
    Target Azure DevOps project.

.PARAMETER Parameters
    Hashtable of parameters used for the run.

.OUTPUTS
    Run manifest object.

.EXAMPLE
    New-RunManifest -Mode "Migrate" -Source "group/app" -Project "MyApp"
#>
function New-RunManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$RunId = [guid]::NewGuid().ToString(),
        
        [Parameter(Mandatory)]
        [ValidateSet('Preflight', 'Initialize', 'Migrate', 'BulkPrepare', 'BulkMigrate', 'Interactive')]
        [string]$Mode,
        
        [string]$Source = "",
        
        [string]$Project = "",
        
        [hashtable]$Parameters = @{}
    )
    
    $manifest = [pscustomobject]@{
        run_id            = $RunId
        timestamp         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        timestamp_utc     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
        mode              = $Mode
        source            = $Source
        project           = $Project
        parameters        = $Parameters
        environment       = @{
            powershell_version = "$($PSVersionTable.PSVersion)"
            os                 = [System.Environment]::OSVersion.VersionString
            machine_name       = $env:COMPUTERNAME
            user               = $env:USERNAME
        }
        tool_version      = "2.0.0"
        status            = "RUNNING"
        start_time        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        end_time          = $null
        duration_seconds  = $null
        errors            = @()
        warnings          = @()
    }
    
    # Write manifest to migrations root
    $migrationsDir = Get-MigrationsDirectory
    $manifestFile = Join-Path $migrationsDir "run-manifest-$RunId.json"
    
    Write-MigrationReport -ReportFile $manifestFile -Data $manifest
    
    Write-Verbose "[Logging] Created run manifest: $manifestFile"
    
    return $manifest
}

<#
.SYNOPSIS
    Updates an existing run manifest.

.DESCRIPTION
    Updates manifest file with final status, timing, and messages.

.PARAMETER RunId
    Run identifier from New-RunManifest.

.PARAMETER Status
    Final status (SUCCESS, FAILED, PARTIAL).

.PARAMETER EndTime
    End time of the run.

.PARAMETER Errors
    Array of error messages.

.PARAMETER Warnings
    Array of warning messages.

.EXAMPLE
    Update-RunManifest -RunId $runId -Status "SUCCESS" -EndTime (Get-Date)
#>
function Update-RunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunId,
        
        [Parameter(Mandatory)]
        [ValidateSet('SUCCESS', 'FAILED', 'PARTIAL')]
        [string]$Status,
        
        [Parameter(Mandatory)]
        [datetime]$EndTime,
        
        [array]$Errors = @(),
        
        [array]$Warnings = @()
    )
    
    $migrationsDir = Get-MigrationsDirectory
    $manifestFile = Join-Path $migrationsDir "run-manifest-$RunId.json"
    
    if (-not (Test-Path $manifestFile)) {
        Write-Warning "[Logging] Run manifest not found: $manifestFile"
        return
    }
    
    # Read existing manifest
    $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
    
    # Calculate duration
    $startTime = [datetime]::ParseExact($manifest.start_time, 'yyyy-MM-dd HH:mm:ss', $null)
    $duration = $EndTime - $startTime
    
    # Update fields
    $manifest.status = $Status
    $manifest.end_time = $EndTime.ToString('yyyy-MM-dd HH:mm:ss')
    $manifest.duration_seconds = [math]::Round($duration.TotalSeconds, 2)
    $manifest.errors = $Errors
    $manifest.warnings = $Warnings
    
    # Write updated manifest
    Write-MigrationReport -ReportFile $manifestFile -Data $manifest
    
    Write-Verbose "[Logging] Updated run manifest: $manifestFile (Status: $Status)"
}

<#
.SYNOPSIS
    Logs REST API call details for debugging.

.DESCRIPTION
    Logs REST method, URL, status code, and response time for observability.
    Useful for troubleshooting API issues and performance analysis.

.PARAMETER Method
    HTTP method (GET, POST, PUT, DELETE, PATCH).

.PARAMETER Url
    Full or relative URL.

.PARAMETER StatusCode
    HTTP status code (200, 404, 500, etc.).

.PARAMETER DurationMs
    Request duration in milliseconds.

.PARAMETER Side
    API side ('ado' or 'gitlab').

.PARAMETER LogFile
    Optional log file path. If not provided, writes to verbose stream.

.EXAMPLE
    Write-RestCallLog -Method "GET" -Url "/_apis/projects" -StatusCode 200 -DurationMs 456 -Side "ado"
#>
function Write-RestCallLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Url,
        
        [int]$StatusCode = 0,
        
        [int]$DurationMs = 0,
        
        [Parameter(Mandatory)]
        [ValidateSet('ado', 'gitlab')]
        [string]$Side,
        
        [string]$LogFile = ""
    )
    
    $sideLabel = $Side.ToUpper()
    $statusLabel = if ($StatusCode -ge 200 -and $StatusCode -lt 300) { "✓" } elseif ($StatusCode -ge 400) { "✗" } else { "○" }
    
    $message = "[$sideLabel] $statusLabel $Method $Url → $StatusCode ($DurationMs ms)"
    
    if ($LogFile -and (Test-Path (Split-Path -Parent $LogFile))) {
        Write-MigrationLog -LogFile $LogFile -Message $message -Level 'DEBUG'
    }
    else {
        Write-Verbose $message
    }
}

<#
.SYNOPSIS
    Creates a migration summary object.

.DESCRIPTION
    Generates standardized migration summary structure.

.PARAMETER GitLabPath
    Source GitLab project path.

.PARAMETER AdoProject
    Target Azure DevOps project.

.PARAMETER AdoRepo
    Target repository name.

.PARAMETER Status
    Migration status (SUCCESS, FAILED, PARTIAL).

.PARAMETER StartTime
    Migration start time.

.PARAMETER EndTime
    Migration end time.

.PARAMETER AdditionalData
    Optional hashtable of additional data.

.OUTPUTS
    Migration summary object.

.EXAMPLE
    New-MigrationSummary -GitLabPath "group/project" -AdoProject "MyProject" -AdoRepo "my-repo" -Status "SUCCESS" -StartTime $start -EndTime $end
#>
function New-MigrationSummary {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$GitLabPath,
        
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [Parameter(Mandatory)]
        [string]$AdoRepo,
        
        [Parameter(Mandatory)]
        [ValidateSet('SUCCESS', 'FAILED', 'PARTIAL')]
        [string]$Status,
        
        [Parameter(Mandatory)]
        [datetime]$StartTime,
        
        [Parameter(Mandatory)]
        [datetime]$EndTime,
        
        [hashtable]$AdditionalData = @{}
    )
    
    $duration = $EndTime - $StartTime
    
    $summary = [pscustomobject]@{
        timestamp         = $StartTime.ToString('yyyy-MM-dd HH:mm:ss')
        gitlab_path       = $GitLabPath
        ado_project       = $AdoProject
        ado_repository    = $AdoRepo
        status            = $Status
        duration_seconds  = [math]::Round($duration.TotalSeconds, 2)
        duration_minutes  = [math]::Round($duration.TotalMinutes, 2)
        start_time        = $StartTime.ToString('yyyy-MM-dd HH:mm:ss')
        end_time          = $EndTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    
    # Add additional data
    foreach ($key in $AdditionalData.Keys) {
        $summary | Add-Member -NotePropertyName $key -NotePropertyValue $AdditionalData[$key]
    }
    
    return $summary
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-MigrationsDirectory',
    'Get-ProjectPaths',
    'Write-MigrationLog',
    'Write-MigrationReport',
    'New-LogFilePath',
    'New-ReportFilePath',
    'Write-MigrationMessage',
    'New-MigrationSummary',
    'New-RunManifest',
    'Update-RunManifest',
    'Write-RestCallLog'
)
