<#
.SYNOPSIS
    Logging and path management functions for migrations.

.DESCRIPTION
    This module provides consistent logging, reporting, and file path management
    for migration operations. Ensures all logs and reports follow standard
    directory structure.

.NOTES
    Part of Gitlab2DevOps migration toolkit.
    Version: 2.1.0
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
    Gets the project-specific directory paths for single project migrations.

.DESCRIPTION
    Returns paths for single project migration folder structure.
    Supports both new (v2.1.0+) and legacy structures.
    Creates directory structure if missing.

.PARAMETER ProjectName
    Legacy: Project name (used as folder name).
    New: Azure DevOps project name (container/parent folder).

.PARAMETER AdoProject
    Azure DevOps project name (container folder) - NEW in v2.1.0.

.PARAMETER GitLabProject
    GitLab project name (subfolder) - NEW in v2.1.0.

.OUTPUTS
    Hashtable with projectDir, reportsDir, logsDir, repositoryDir, configFile paths.
    New structure also includes gitlabDir.

.EXAMPLE
    # Legacy structure (deprecated)
    Get-ProjectPaths -ProjectName "my-project"
    
.EXAMPLE
    # New self-contained structure (v2.1.0+)
    Get-ProjectPaths -AdoProject "MyDevOpsProject" -GitLabProject "my-project"
#>
function Get-ProjectPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ParameterSetName='Legacy')]
        [string]$ProjectName,
        
        [Parameter(Mandatory, ParameterSetName='New')]
        [string]$AdoProject,
        
        [Parameter(Mandatory, ParameterSetName='New')]
        [string]$GitLabProject
    )
    
    $migrationsDir = Get-MigrationsDirectory
    
    if ($PSCmdlet.ParameterSetName -eq 'New') {
        # New self-contained structure (v2.1.0+)
        $containerDir = Join-Path $migrationsDir $AdoProject
        $gitlabDir = Join-Path $containerDir $GitLabProject
        $reportsDir = Join-Path $containerDir "reports"
        $logsDir = Join-Path $containerDir "logs"
        $repositoryDir = Join-Path $gitlabDir "repository"
        $configFile = Join-Path $containerDir "migration-config.json"
        
        # Create directories if missing
        @($containerDir, $reportsDir, $logsDir, $gitlabDir) | ForEach-Object {
            if (-not (Test-Path $_)) {
                New-Item -ItemType Directory -Path $_ -Force | Out-Null
                Write-Verbose "[Logging] Created directory: $_"
            }
        }
        
        return @{
            projectDir    = $containerDir
            gitlabDir     = $gitlabDir
            reportsDir    = $reportsDir
            logsDir       = $logsDir
            repositoryDir = $repositoryDir
            configFile    = $configFile
        }
    }
    else {
        # Legacy flat structure (deprecated)
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
}

<#
.SYNOPSIS
    Gets bulk migration project paths.

.DESCRIPTION
    Returns paths for bulk migration self-contained folder structure.
    Creates directory structure if missing.

.PARAMETER AdoProject
    Azure DevOps project name (container/parent folder).

.PARAMETER GitLabProject
    GitLab project name (subfolder for cloned repository).
    Optional - if not provided, returns only parent paths.

.OUTPUTS
    Hashtable with containerDir, reportsDir, logsDir, configFile paths.
    If GitLabProject specified, also includes gitlabDir and repositoryDir.

.EXAMPLE
    Get-BulkProjectPaths -AdoProject "ConsolidatedProject"
    Get-BulkProjectPaths -AdoProject "ConsolidatedProject" -GitLabProject "frontend-app"
#>
function Get-BulkProjectPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$AdoProject,
        
        [Parameter()]
        [string]$GitLabProject
    )
    
    $migrationsDir = Get-MigrationsDirectory
    $containerDir = Join-Path $migrationsDir $AdoProject
    $reportsDir = Join-Path $containerDir "reports"
    $logsDir = Join-Path $containerDir "logs"
    $configFile = Join-Path $containerDir "bulk-migration-config.json"
    
    # Create parent directories
    @($containerDir, $reportsDir, $logsDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Verbose "[Logging] Created directory: $_"
        }
    }
    
    $result = @{
        containerDir = $containerDir
        reportsDir   = $reportsDir
        logsDir      = $logsDir
        configFile   = $configFile
    }
    
    # Add GitLab project specific paths if provided
    if (-not [string]::IsNullOrWhiteSpace($GitLabProject)) {
        $gitlabDir = Join-Path $containerDir $GitLabProject
        $repositoryDir = Join-Path $gitlabDir "repository"
        
        # Create GitLab project directory (but not repository - that's created by git clone)
        if (-not (Test-Path $gitlabDir)) {
            New-Item -ItemType Directory -Path $gitlabDir -Force | Out-Null
            Write-Verbose "[Logging] Created GitLab project directory: $gitlabDir"
        }
        
        $result.gitlabDir = $gitlabDir
        $result.repositoryDir = $repositoryDir
    }
    
    return $result
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
    [CmdletBinding(DefaultParameterSetName='ByDir')]
    [OutputType([string])]
    param(
        # Existing usage: provide logs directory directly
        [Parameter(Mandatory, ParameterSetName='ByDir')]
        [string]$LogsDir,
        
        [Parameter(ParameterSetName='ByDir')]
        [string]$Prefix = "log",
        
        # Compatibility usage (as expected by some tests)
        [Parameter(Mandatory, ParameterSetName='ByProject')]
        [string]$ProjectName,
        
        [Parameter(Mandatory, ParameterSetName='ByProject')]
        [string]$Operation
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'ByProject') {
        $paths = Get-ProjectPaths -ProjectName $ProjectName
        $LogsDir = $paths.logsDir
        $Prefix = $Operation
    }
    
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
    [CmdletBinding(DefaultParameterSetName='ByDir')]
    [OutputType([string])]
    param(
        # Existing usage: provide reports directory directly
        [Parameter(Mandatory, ParameterSetName='ByDir')]
        [string]$ReportsDir,
        
        [Parameter(ParameterSetName='ByDir')]
        [string]$Prefix = "report",
        
        [Parameter(ParameterSetName='ByDir')]
        [string]$Extension = "json",
        
        # Compatibility usage: compute path based on project and report type
        [Parameter(Mandatory, ParameterSetName='ByProject')]
        [string]$ProjectName,
        
        [Parameter(Mandatory, ParameterSetName='ByProject')]
        [ValidateSet('preflight','migration')]
        [string]$ReportType
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'ByProject') {
        $paths = Get-ProjectPaths -ProjectName $ProjectName
        $ReportsDir = $paths.reportsDir
        switch ($ReportType) {
            'preflight' { return (Join-Path $ReportsDir 'preflight-report.json') }
            'migration' { return (Join-Path $ReportsDir 'migration-report.json') }
        }
    }
    
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
    [ValidateSet('Preflight', 'Initialize', 'Migrate', 'BulkPrepare', 'BulkMigrate', 'BusinessInit', 'Interactive')]
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
            ps_version         = "$($PSVersionTable.PSVersion)"  # compatibility alias
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
    [CmdletBinding(DefaultParameterSetName='ByRunId')]
    param(
        # Existing usage: identify manifest by run id
        [Parameter(Mandatory, ParameterSetName='ByRunId')]
        [string]$RunId,
        
        # Compatibility usage: pass manifest file directly
        [Parameter(Mandatory, ParameterSetName='ByFile')]
        [string]$ManifestFile,
        
        [Parameter(Mandatory)]
        [ValidateSet('SUCCESS', 'FAILED', 'PARTIAL')]
        [string]$Status,
        
        [Parameter(ParameterSetName='ByRunId')]
        [Parameter(ParameterSetName='ByFile')]
        [datetime]$EndTime = (Get-Date),
        
        [array]$Errors = @(),
        
        [array]$Warnings = @()
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'ByRunId') {
        $migrationsDir = Get-MigrationsDirectory
        $ManifestFile = Join-Path $migrationsDir "run-manifest-$RunId.json"
    }
    
    if (-not (Test-Path $ManifestFile)) {
        Write-Warning "[Logging] Run manifest not found: $ManifestFile"
        return
    }
    
    # Read existing manifest
    $manifest = Get-Content $ManifestFile -Raw | ConvertFrom-Json
    
    # Calculate duration
    # Be robust to different date formats (ISO 8601 or custom)
    try {
        $startTime = [datetime]::Parse($manifest.start_time, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        $startTime = [datetime]::ParseExact($manifest.start_time, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $duration = $EndTime - $startTime
    
    # Helper to set or add a property on PSCustomObject
    function Set-OrAddProperty([pscustomobject]$obj, [string]$name, $value) {
        $prop = $obj.PSObject.Properties[$name]
        if ($prop) { $obj.$name = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
    }
    
    # Update fields
    Set-OrAddProperty -obj $manifest -name 'status' -value $Status
    Set-OrAddProperty -obj $manifest -name 'end_time' -value ($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Set-OrAddProperty -obj $manifest -name 'duration_seconds' -value ([math]::Round($duration.TotalSeconds, 2))
    Set-OrAddProperty -obj $manifest -name 'errors' -value $Errors
    Set-OrAddProperty -obj $manifest -name 'warnings' -value $Warnings
    
    # Write updated manifest
    Write-MigrationReport -ReportFile $ManifestFile -Data $manifest
    
    Write-Verbose "[Logging] Updated run manifest: $ManifestFile (Status: $Status)"
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
    [CmdletBinding(DefaultParameterSetName='ByExplicit')]
    [OutputType([pscustomobject])]
    param(
        # Existing usage
        [Parameter(Mandatory, ParameterSetName='ByExplicit')]
        [string]$GitLabPath,
        
        [Parameter(Mandatory, ParameterSetName='ByExplicit')]
        [string]$AdoProject,
        
        [Parameter(Mandatory, ParameterSetName='ByExplicit')]
        [string]$AdoRepo,
        
        # Compatibility usage
        [Parameter(Mandatory, ParameterSetName='ByCompat')]
        [string]$SourceProject,
        
        [Parameter(Mandatory, ParameterSetName='ByCompat')]
        [string]$DestProject,
        
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
        gitlab_path       = if ($PSCmdlet.ParameterSetName -eq 'ByCompat') { $SourceProject } else { $GitLabPath }
        ado_project       = if ($PSCmdlet.ParameterSetName -eq 'ByCompat') { $DestProject } else { $AdoProject }
        ado_repository    = if ($PSCmdlet.ParameterSetName -eq 'ByCompat') { '' } else { $AdoRepo }
        status            = $Status
        duration_seconds  = [math]::Round($duration.TotalSeconds, 2)
        duration_minutes  = [math]::Round($duration.TotalMinutes, 2)
        start_time        = $StartTime.ToString('yyyy-MM-dd HH:mm:ss')
        end_time          = $EndTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    
    # Add compatibility aliases expected by some consumers/tests
    $summary | Add-Member -NotePropertyName source_project -NotePropertyValue $summary.gitlab_path
    $summary | Add-Member -NotePropertyName destination_project -NotePropertyValue $summary.ado_project
    
    # Add additional data
    foreach ($key in $AdditionalData.Keys) {
        $summary | Add-Member -NotePropertyName $key -NotePropertyValue $AdditionalData[$key]
    }
    
    return $summary
}

# Export public functions
<#
.SYNOPSIS
    Generates an HTML status report for a single migration project.

.DESCRIPTION
    Creates a visually appealing HTML report showing the current status of a migration project.
    The report includes project details, status, timestamps, and progress indicators.

.PARAMETER ProjectPath
    Path to the project migration folder.

.PARAMETER OutputPath
    Optional custom output path. Defaults to reports/migration-status.html in project folder.

.OUTPUTS
    Path to generated HTML report.

.EXAMPLE
    New-MigrationHtmlReport -ProjectPath "migrations/MyProject/my-repo"
#>
function New-MigrationHtmlReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,
        
        [Parameter()]
        [string]$OutputPath
    )
    
    try {
        # Load template
        $templatePath = Join-Path $PSScriptRoot "templates\migration-status.html"
        if (-not (Test-Path $templatePath)) {
            Write-Warning "[New-MigrationHtmlReport] Template not found: $templatePath"
            return $null
        }
        
        $template = Get-Content -Path $templatePath -Raw
        
        # Load migration config
        $configFile = Join-Path $ProjectPath "migration-config.json"
        if (-not (Test-Path $configFile)) {
            Write-Warning "[New-MigrationHtmlReport] Config not found: $configFile"
            return $null
        }
        
        $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
        
        # Determine output path
        if (-not $OutputPath) {
            $reportsDir = Join-Path $ProjectPath "reports"
            if (-not (Test-Path $reportsDir)) {
                New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
            }
            $OutputPath = Join-Path $reportsDir "migration-status.html"
        }
        
        # Build project card HTML
        $statusClass = $config.status.ToUpper() -replace '[^A-Z_]', '_'
        $projectCard = @"
<div class="project-card">
    <div class="project-header">
        <div class="project-name">$($config.gitlab_project)</div>
        <span class="status-badge $statusClass">$($config.status)</span>
    </div>
    
    <div class="project-details">
        <div class="detail-item">
            <span class="icon">📦</span>
            <div class="content">
                <div class="label">Azure DevOps Project</div>
                <div class="value">$($config.ado_project)</div>
            </div>
        </div>
        <div class="detail-item">
            <span class="icon">🔗</span>
            <div class="content">
                <div class="label">GitLab Repository</div>
                <div class="value">$($config.gitlab_repo_name)</div>
            </div>
        </div>
        <div class="detail-item">
            <span class="icon">📊</span>
            <div class="content">
                <div class="label">Migration Type</div>
                <div class="value">$($config.migration_type)</div>
            </div>
        </div>
    </div>
    
    <div class="timestamps">
        <div class="timestamp">
            <span class="icon">🕒</span>
            Created: $($config.created_date)
        </div>
        <div class="timestamp">
            <span class="icon">🔄</span>
            Updated: $($config.last_updated)
        </div>
    </div>
</div>
"@
        
        # Add back navigation link
        $backNavigation = @'
<div class="refresh-info" style="background: #e3f2fd; border-bottom-color: #2196f3;">
    <a href="../../../index.html" style="color: #1565c0; text-decoration: none; font-weight: 600;">
        ← Back to Migration Overview Dashboard
    </a>
</div>
'@
        
        # Replace template placeholders
        $html = $template `
            -replace '{{REPORT_TITLE}}', "Migration Status: $($config.gitlab_project)" `
            -replace '{{REPORT_SUBTITLE}}', "Azure DevOps Project: $($config.ado_project)" `
            -replace '{{REFRESH_INFO}}', $backNavigation `
            -replace '{{SUMMARY_STATS}}', '' `
            -replace '{{PROJECT_CARDS}}', $projectCard `
            -replace '{{GENERATION_TIME}}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        
        # Write HTML file
        $html | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Verbose "[New-MigrationHtmlReport] Generated report: $OutputPath"
        
        return $OutputPath
    }
    catch {
        Write-Warning "[New-MigrationHtmlReport] Failed to generate HTML report: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Generates a consolidated HTML report for all migrations in the migrations folder.

.DESCRIPTION
    Creates a comprehensive HTML dashboard showing all migration projects with their
    current status, statistics, and details. Auto-refreshes every 30 seconds.

.PARAMETER MigrationsPath
    Optional path to migrations directory. Defaults to ./migrations.

.PARAMETER OutputPath
    Optional custom output path. Defaults to migrations/index.html.

.OUTPUTS
    Path to generated HTML report.

.EXAMPLE
    New-MigrationsOverviewReport
#>
function New-MigrationsOverviewReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$MigrationsPath,
        
        [Parameter()]
        [string]$OutputPath
    )
    
    try {
        # Get migrations directory
        if (-not $MigrationsPath) {
            $MigrationsPath = Get-MigrationsDirectory
        }
        
        # Determine output path
        if (-not $OutputPath) {
            $OutputPath = Join-Path $MigrationsPath "index.html"
        }
        
        # Load template
        $templatePath = Join-Path $PSScriptRoot "templates\migration-status.html"
        if (-not (Test-Path $templatePath)) {
            Write-Warning "[New-MigrationsOverviewReport] Template not found: $templatePath"
            return $null
        }
        
        $template = Get-Content -Path $templatePath -Raw
        
        # Collect all migration projects
        $allProjects = @()
        $stats = @{
            total = 0
            prepared = 0
            migrated = 0
            completed = 0
            failed = 0
        }
        
        # Find all migration-config.json and bulk-migration-config.json files
        $configFiles = Get-ChildItem -Path $MigrationsPath -Recurse -Filter "*migration-config.json" -File
        
        foreach ($configFile in $configFiles) {
            try {
                $config = Get-Content -Path $configFile.FullName -Raw | ConvertFrom-Json
                
                # Handle bulk migration configs
                if ($config.migration_type -eq 'BULK' -and $config.projects) {
                    foreach ($project in $config.projects) {
                        $projectObj = [PSCustomObject]@{
                            ado_project = $config.destination_project
                            gitlab_project = $project.gitlab_path
                            gitlab_repo_name = $project.ado_repo_name
                            status = $project.preparation_status
                            migration_type = 'BULK'
                            created_date = $config.preparation_summary.preparation_time
                            last_updated = $config.preparation_summary.preparation_time
                            repo_size_MB = $project.repo_size_MB
                            lfs_enabled = $project.lfs_enabled
                        }
                        $allProjects += $projectObj
                        $stats.total++
                        if ($project.preparation_status -eq 'SUCCESS') { $stats.prepared++ }
                    }
                }
                # Handle single migration configs
                elseif ($config.ado_project) {
                    $allProjects += $config
                    $stats.total++
                    
                    switch ($config.status) {
                        'PREPARED' { $stats.prepared++ }
                        'MIGRATED' { $stats.migrated++ }
                        'COMPLETED' { $stats.completed++ }
                        'FAILED' { $stats.failed++ }
                    }
                }
            }
            catch {
                Write-Verbose "[New-MigrationsOverviewReport] Failed to parse config: $($configFile.FullName)"
            }
        }
        
        # Build summary stats HTML
        $summaryHtml = @"
<div class="stat-card total">
    <div class="value">$($stats.total)</div>
    <div class="label">Total Projects</div>
</div>
<div class="stat-card prepared">
    <div class="value">$($stats.prepared)</div>
    <div class="label">Prepared</div>
</div>
<div class="stat-card migrated">
    <div class="value">$($stats.migrated)</div>
    <div class="label">Migrated</div>
</div>
<div class="stat-card completed">
    <div class="value">$($stats.completed)</div>
    <div class="label">Completed</div>
</div>
<div class="stat-card failed">
    <div class="value">$($stats.failed)</div>
    <div class="label">Failed</div>
</div>
"@
        
        # Build project cards HTML with links
        $cardsHtml = ""
        foreach ($project in $allProjects) {
            $statusClass = $project.status.ToUpper() -replace '[^A-Z_]', '_'
            $repoSize = if ($project.PSObject.Properties['repo_size_MB'] -and $project.repo_size_MB) { "$($project.repo_size_MB) MB" } else { "N/A" }
            $lfsStatus = if ($project.PSObject.Properties['lfs_enabled'] -and $project.lfs_enabled) { "✓ Enabled" } else { "✗ Disabled" }
            
            # Build relative path to individual project report
            $projectReportPath = ""
            if ($project.ado_project -and $project.gitlab_repo_name) {
                $projectReportPath = "./$($project.ado_project)/$($project.gitlab_repo_name)/reports/migration-status.html"
            }
            
            # Add clickable link if report path exists
            $nameHtml = if ($projectReportPath) {
                "<a href=`"$projectReportPath`" style=`"color: inherit; text-decoration: none;`">$($project.gitlab_project) 🔗</a>"
            } else {
                $project.gitlab_project
            }
            
            $cardsHtml += @"
<div class="project-card" style="cursor: pointer;" onclick="window.location.href='$projectReportPath'">
    <div class="project-header">
        <div class="project-name">$nameHtml</div>
        <span class="status-badge $statusClass">$($project.status)</span>
    </div>
    
    <div class="project-details">
        <div class="detail-item">
            <span class="icon">📦</span>
            <div class="content">
                <div class="label">Azure DevOps Project</div>
                <div class="value">$($project.ado_project)</div>
            </div>
        </div>
        <div class="detail-item">
            <span class="icon">🔗</span>
            <div class="content">
                <div class="label">Repository Name</div>
                <div class="value">$($project.gitlab_repo_name)</div>
            </div>
        </div>
        <div class="detail-item">
            <span class="icon">📊</span>
            <div class="content">
                <div class="label">Migration Type</div>
                <div class="value">$($project.migration_type)</div>
            </div>
        </div>
        <div class="detail-item">
            <span class="icon">💾</span>
            <div class="content">
                <div class="label">Repository Size</div>
                <div class="value">$repoSize</div>
            </div>
        </div>
        <div class="detail-item">
            <span class="icon">📁</span>
            <div class="content">
                <div class="label">Git LFS</div>
                <div class="value">$lfsStatus</div>
            </div>
        </div>
    </div>
    
    <div class="timestamps">
        <div class="timestamp">
            <span class="icon">🕒</span>
            Created: $($project.created_date)
        </div>
        <div class="timestamp">
            <span class="icon">🔄</span>
            Updated: $($project.last_updated)
        </div>
    </div>
</div>

"@
        }
        
        # Add refresh info
        $refreshInfo = @'
<div class="refresh-info">
    ⚡ This page auto-refreshes every 30 seconds to show the latest migration status
</div>
<script>
    setTimeout(function() {
        location.reload();
    }, 30000);
</script>
'@
        
        # Replace template placeholders
        $html = $template `
            -replace '{{REPORT_TITLE}}', "GitLab to Azure DevOps Migration Dashboard" `
            -replace '{{REPORT_SUBTITLE}}', "Overview of all migration projects" `
            -replace '{{REFRESH_INFO}}', $refreshInfo `
            -replace '{{SUMMARY_STATS}}', $summaryHtml `
            -replace '{{PROJECT_CARDS}}', $cardsHtml `
            -replace '{{GENERATION_TIME}}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        
        # Write HTML file
        $html | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "[SUCCESS] Generated migrations overview: $OutputPath" -ForegroundColor Green
        
        return $OutputPath
    }
    catch {
        Write-Warning "[New-MigrationsOverviewReport] Failed to generate overview report: $_"
        return $null
    }
}

Export-ModuleMember -Function @(
    'Get-MigrationsDirectory',
    'Get-ProjectPaths',
    'Get-BulkProjectPaths',
    'Write-MigrationLog',
    'Write-MigrationReport',
    'New-LogFilePath',
    'New-ReportFilePath',
    'Write-MigrationMessage',
    'New-MigrationSummary',
    'New-RunManifest',
    'Update-RunManifest',
    'Write-RestCallLog',
    'New-MigrationHtmlReport',
    'New-MigrationsOverviewReport'
)
