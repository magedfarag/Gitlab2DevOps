# Move-PS1Files.ps1
# Temporary script to reorganize .ps1 files from root to appropriate folders
# and update all references across the codebase

param(
    [switch]$WhatIf,
    [switch]$Force
)

# Configuration
$RootPath = $PSScriptRoot
$MainEntryPoint = "Gitlab2DevOps.ps1"  # Don't move this one
$ExcludeFiles = @("Move-PS1Files.ps1")  # Don't move this script itself

# Define folder mappings based on file content analysis
$FolderMappings = @{
    "check-modules" = "modules/dev"  # Development/utility scripts
    "create-sample-excel" = "examples"  # Example/sample creation scripts
    "Prepare-MigrationsFromConfig" = "modules/Migration"  # Migration-related scripts
    "Export-GitLabIdentity" = "examples"  # Example export scripts
    "Import-GitLabIdentityToAdo" = "examples"  # Example import scripts
    "test-progress" = "examples"  # Test/example scripts
}

function Get-FilePurpose {
    param([string]$FilePath)

    $content = Get-Content $FilePath -Raw

    # Analyze content to determine purpose
    if ($content -match "Import-Excel|Export-Excel|work.?item|Excel") {
        return "examples"  # Excel/work item related
    }
    elseif ($content -match "module|Module|Import-Module|function|Function") {
        return "modules/dev"  # Module/utility related
    }
    elseif ($content -match "migration|Migration|config|Config") {
        return "modules/Migration"  # Migration related
    }
    else {
        return "scripts"  # Generic scripts folder
    }
}

function Update-References {
    param(
        [string]$OldPath,
        [string]$NewPath,
        [switch]$WhatIf
    )

    Write-Host "Updating references from '$OldPath' to '$NewPath'..." -ForegroundColor Yellow

    # Get all files that might contain references
    $filesToCheck = Get-ChildItem -Path $RootPath -Recurse -File |
        Where-Object { $_.Extension -ne ".git" -and $_.FullName -notlike "*\.git*" } |
        Select-Object -ExpandProperty FullName

    $updatedFiles = @()

    foreach ($file in $filesToCheck) {
        try {
            $content = Get-Content $file -Raw

            # Look for various reference patterns
            $oldRelativePath = [System.IO.Path]::GetFileName($OldPath)
            $newRelativePath = $NewPath.Replace("$RootPath\", "").Replace("\", "/")

            # Patterns to replace:
            # 1. Dot sourcing: . .\filename.ps1 or . ".\filename.ps1"
            $patterns = @(
                # Dot sourcing: . .\filename.ps1 or . ".\filename.ps1"
                "\.\s*\\?`"$oldRelativePath`"",
                "\.\s*\\?$oldRelativePath",

                # Import-Module with relative path
                "Import-Module\s+.*\\?$oldRelativePath",

                # Direct path references
                "\\$oldRelativePath",
                "/$oldRelativePath"
            )

            $modified = $false
            foreach ($pattern in $patterns) {
                if ($content -match $pattern) {
                    $newContent = $content -replace $pattern, $newRelativePath
                    if ($newContent -ne $content) {
                        if ($WhatIf) {
                            Write-Host "Would update: $file" -ForegroundColor Cyan
                        } else {
                            $newContent | Set-Content $file -Encoding UTF8
                            $modified = $true
                        }
                    }
                }
            }

            if ($modified) {
                $updatedFiles += $file
            }

        } catch {
            Write-Warning "Could not process file: $file ($($_.Exception.Message))"
        }
    }

    if (-not $WhatIf -and $updatedFiles.Count -gt 0) {
        Write-Host "Updated $($updatedFiles.Count) files:" -ForegroundColor Green
        $updatedFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    }

    return $updatedFiles.Count
}

function Move-PS1File {
    param(
        [string]$FileName,
        [string]$TargetFolder,
        [switch]$WhatIf
    )

    $sourcePath = Join-Path $RootPath $FileName
    $targetFolderPath = Join-Path $RootPath $TargetFolder

    # Ensure target folder exists
    if (-not (Test-Path $targetFolderPath)) {
        if ($WhatIf) {
            Write-Host "Would create directory: $targetFolderPath" -ForegroundColor Cyan
        } else {
            New-Item -ItemType Directory -Path $targetFolderPath -Force | Out-Null
            Write-Host "Created directory: $targetFolderPath" -ForegroundColor Green
        }
    }

    $targetPath = Join-Path $targetFolderPath $FileName

    if ($WhatIf) {
        Write-Host "Would move: $sourcePath -> $targetPath" -ForegroundColor Cyan
    } else {
        Move-Item -Path $sourcePath -Destination $targetPath -Force
        Write-Host "Moved: $sourcePath -> $targetPath" -ForegroundColor Green
    }

    return $targetPath
}

# Main execution
Write-Host "=== PS1 File Reorganization Script ===" -ForegroundColor Cyan
Write-Host "Root Path: $RootPath" -ForegroundColor Gray
Write-Host "WhatIf Mode: $($WhatIf.ToString())" -ForegroundColor Gray
Write-Host ""

# Find all .ps1 files in root (excluding main entry point and excluded files)
$ps1Files = Get-ChildItem -Path $RootPath -Filter "*.ps1" -File |
    Where-Object { $_.Name -ne $MainEntryPoint -and $_.Name -notin $ExcludeFiles }

if ($ps1Files.Count -eq 0) {
    Write-Host "No .ps1 files found in root directory (excluding $MainEntryPoint)" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($ps1Files.Count) .ps1 files to process:" -ForegroundColor Yellow
$ps1Files | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
Write-Host ""

$movedFiles = @()
$totalUpdatedReferences = 0

foreach ($file in $ps1Files) {
    $fileName = $file.Name
    $baseName = $file.BaseName

    # Determine target folder
    $targetFolder = if ($FolderMappings.ContainsKey($baseName)) {
        $FolderMappings[$baseName]
    } else {
        Get-FilePurpose -FilePath $file.FullName
    }

    Write-Host "Processing: $fileName -> $targetFolder" -ForegroundColor White

    # Move the file
    $newPath = Move-PS1File -FileName $fileName -TargetFolder $targetFolder -WhatIf:$WhatIf

    if (-not $WhatIf) {
        $movedFiles += @{
            OldPath = $file.FullName
            NewPath = $newPath
            FileName = $fileName
        }
    }
}

Write-Host ""
Write-Host "=== Updating References ===" -ForegroundColor Cyan

# Update references for moved files
foreach ($movedFile in $movedFiles) {
    $updatedCount = Update-References -OldPath $movedFile.OldPath -NewPath $movedFile.NewPath -WhatIf:$WhatIf
    $totalUpdatedReferences += $updatedCount
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Files moved: $($movedFiles.Count)" -ForegroundColor Green
Write-Host "References updated: $totalUpdatedReferences" -ForegroundColor Green

if ($WhatIf) {
    Write-Host ""
    Write-Host "This was a WhatIf run. No actual changes were made." -ForegroundColor Yellow
    Write-Host "Run with -Force to apply changes." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "Reorganization complete!" -ForegroundColor Green
    Write-Host "Please test the moved scripts to ensure they work correctly." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Moved files:" -ForegroundColor White
$movedFiles | ForEach-Object {
    Write-Host "  $($_.FileName): $($_.OldPath) -> $($_.NewPath)" -ForegroundColor Gray
}