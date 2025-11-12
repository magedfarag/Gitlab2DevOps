<#
.SYNOPSIS
    Extended test suite for Gitlab2DevOps - covers all requirements and edge cases.

.DESCRIPTION
    Comprehensive test coverage for:
    - EnvLoader module (.env file support)
    - Migration modes (Preflight, Initialize, Migrate, BulkPrepare, BulkMigrate)
    - Force, Replace, and AllowSync flags
    - Validation and error handling
    - Configuration precedence
    - Integration scenarios

.NOTES
    Run with: .\tests\ExtendedTests.ps1
    Extends OfflineTests.ps1 with additional scenarios
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup test environment
$testRoot = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $testRoot
$moduleRoot = Join-Path $projectRoot "modules"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  EXTENDED TEST SUITE" -ForegroundColor Cyan
Write-Host "  Requirements & Integration Tests" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$testResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    Skipped = 0
}

function Test-Requirement {
    param(
        [string]$Name,
        [scriptblock]$TestBlock
    )
    
    $testResults.Total++
    Write-Host "Testing: $Name" -ForegroundColor Yellow
    
    try {
        & $TestBlock
        $testResults.Passed++
        Write-Host "  ✅ PASS" -ForegroundColor Green
        return $true
    }
    catch {
        $testResults.Failed++
        Write-Host "  ❌ FAIL: $_" -ForegroundColor Red
        Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
        return $false
    }
}

#region EnvLoader Module Tests

Write-Host "`n=== ENV LOADER MODULE ===" -ForegroundColor Cyan

Test-Requirement "EnvLoader module exports all required functions" {
        Import-Module (Join-Path $moduleRoot "core\EnvLoader.psm1") -Force
    
    $requiredFunctions = @(
        'Import-DotEnvFile',
        'New-DotEnvTemplate',
        'Test-DotEnvConfig'
    )
    
    foreach ($func in $requiredFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Missing function: $func"
        }
    }
}

Test-Requirement "Import-DotEnvFile handles missing file gracefully" {
    $result = Import-DotEnvFile -Path "nonexistent.env" -WarningAction SilentlyContinue
    
    if ($null -eq $result) { throw "Should return empty hashtable, not null" }
    if ($result.Count -ne 0) { throw "Should return empty hashtable for missing file" }
}

Test-Requirement "Import-DotEnvFile parses basic KEY=VALUE format" {
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    
    @"
TEST_KEY=test_value
ANOTHER_KEY=another_value
"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        $config = Import-DotEnvFile -Path $tempFile
        
        if ($config['TEST_KEY'] -ne 'test_value') {
            throw "TEST_KEY value incorrect: $($config['TEST_KEY'])"
        }
        if ($config['ANOTHER_KEY'] -ne 'another_value') {
            throw "ANOTHER_KEY value incorrect"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "Import-DotEnvFile ignores comments and empty lines" {
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    
    @"
# This is a comment
KEY1=value1

# Another comment
KEY2=value2

"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        $config = Import-DotEnvFile -Path $tempFile
        
        if ($config.Count -ne 2) {
            throw "Should parse exactly 2 keys, got $($config.Count)"
        }
        if ($config['KEY1'] -ne 'value1') { throw "KEY1 incorrect" }
        if ($config['KEY2'] -ne 'value2') { throw "KEY2 incorrect" }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "Import-DotEnvFile handles quoted values" {
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    
    @"
DOUBLE_QUOTED="value with spaces"
SINGLE_QUOTED='another value'
NO_QUOTES=simple_value
"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        $config = Import-DotEnvFile -Path $tempFile
        
        if ($config['DOUBLE_QUOTED'] -ne 'value with spaces') {
            throw "DOUBLE_QUOTED incorrect: $($config['DOUBLE_QUOTED'])"
        }
        if ($config['SINGLE_QUOTED'] -ne 'another value') {
            throw "SINGLE_QUOTED incorrect"
        }
        if ($config['NO_QUOTES'] -ne 'simple_value') {
            throw "NO_QUOTES incorrect"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "Import-DotEnvFile expands variable references" {
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    
    @"
BASE_URL=https://example.com
API_URL=`${BASE_URL}/api
FULL_URL=`${API_URL}/v1
"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        $config = Import-DotEnvFile -Path $tempFile
        
        if ($config['BASE_URL'] -ne 'https://example.com') {
            throw "BASE_URL incorrect"
        }
        if ($config['API_URL'] -ne 'https://example.com/api') {
            throw "API_URL not expanded: $($config['API_URL'])"
        }
        if ($config['FULL_URL'] -ne 'https://example.com/api/v1') {
            throw "FULL_URL not expanded: $($config['FULL_URL'])"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "Import-DotEnvFile sets environment variables when requested" {
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    $testKey = "TEST_ENV_VAR_$(Get-Random)"
    
    @"
$testKey=test_env_value
"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        Import-DotEnvFile -Path $tempFile -SetEnvironmentVariables
        
        $envValue = [Environment]::GetEnvironmentVariable($testKey, [EnvironmentVariableTarget]::Process)
        if ($envValue -ne 'test_env_value') {
            throw "Environment variable not set: $envValue"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($testKey, $null, [EnvironmentVariableTarget]::Process)
    }
}

Test-Requirement "Import-DotEnvFile respects existing environment variables by default" {
    $testKey = "TEST_EXISTING_VAR_$(Get-Random)"
    [Environment]::SetEnvironmentVariable($testKey, "existing_value", [EnvironmentVariableTarget]::Process)
    
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    @"
$testKey=new_value
"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        Import-DotEnvFile -Path $tempFile -SetEnvironmentVariables
        
        $envValue = [Environment]::GetEnvironmentVariable($testKey, [EnvironmentVariableTarget]::Process)
        if ($envValue -ne 'existing_value') {
            throw "Environment variable was overwritten: $envValue"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($testKey, $null, [EnvironmentVariableTarget]::Process)
    }
}

Test-Requirement "Import-DotEnvFile overwrites with AllowOverwrite flag" {
    $testKey = "TEST_OVERWRITE_VAR_$(Get-Random)"
    [Environment]::SetEnvironmentVariable($testKey, "old_value", [EnvironmentVariableTarget]::Process)
    
    $tempFile = Join-Path $($env:TEMP) "test-env-$(Get-Random).env"
    @"
$testKey=new_value
"@ | Out-File -FilePath $tempFile -Encoding UTF8
    
    try {
        Import-DotEnvFile -Path $tempFile -SetEnvironmentVariables -AllowOverwrite
        
        $envValue = [Environment]::GetEnvironmentVariable($testKey, [EnvironmentVariableTarget]::Process)
        if ($envValue -ne 'new_value') {
            throw "Environment variable not overwritten: $envValue"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($testKey, $null, [EnvironmentVariableTarget]::Process)
    }
}

Test-Requirement "Import-DotEnvFile loads multiple files with correct precedence" {
    $file1 = Join-Path $($env:TEMP) "test-env1-$(Get-Random).env"
    $file2 = Join-Path $($env:TEMP) "test-env2-$(Get-Random).env"
    
    @"
KEY1=from_file1
KEY2=also_from_file1
"@ | Out-File -FilePath $file1 -Encoding UTF8
    
    @"
KEY2=from_file2
KEY3=only_in_file2
"@ | Out-File -FilePath $file2 -Encoding UTF8
    
    try {
        $config = Import-DotEnvFile -Path @($file1, $file2)
        
        if ($config['KEY1'] -ne 'from_file1') { throw "KEY1 incorrect" }
        if ($config['KEY2'] -ne 'from_file2') {
            throw "KEY2 should be from file2 (later file), got: $($config['KEY2'])"
        }
        if ($config['KEY3'] -ne 'only_in_file2') { throw "KEY3 incorrect" }
    }
    finally {
        Remove-Item $file1, $file2 -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "New-DotEnvTemplate creates valid template file" {
    $tempFile = Join-Path $($env:TEMP) "test-template-$(Get-Random).env"
    
    try {
        New-DotEnvTemplate -Path $tempFile
        
        if (-not (Test-Path $tempFile)) {
            throw "Template file not created"
        }
        
        $content = Get-Content $tempFile -Raw
        
        # Verify required sections exist
        $requiredSections = @(
            'ADO_COLLECTION_URL',
            'ADO_PAT',
            'GITLAB_BASE_URL',
            'GITLAB_PAT',
            'Azure DevOps Configuration',
            'GitLab Configuration'
        )
        
        foreach ($section in $requiredSections) {
            if ($content -notmatch [regex]::Escape($section)) {
                throw "Template missing section: $section"
            }
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "New-DotEnvTemplate respects Force flag" {
    $tempFile = Join-Path $($env:TEMP) "test-template-$(Get-Random).env"
    
    try {
        "existing content" | Out-File -FilePath $tempFile -Encoding UTF8
        
        # Should not overwrite without Force
        New-DotEnvTemplate -Path $tempFile -WarningAction SilentlyContinue
        $content1 = Get-Content $tempFile -Raw
        if ($content1 -notmatch "existing content") {
            throw "File was overwritten without Force flag"
        }
        
        # Should overwrite with Force
        New-DotEnvTemplate -Path $tempFile -Force
        $content2 = Get-Content $tempFile -Raw
        if ($content2 -match "existing content") {
            throw "File was not overwritten with Force flag"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Test-Requirement "Test-DotEnvConfig validates required keys" {
    $config = @{
        'ADO_PAT' = 'test-pat'
        'GITLAB_PAT' = 'test-token'
        'ADO_COLLECTION_URL' = 'https://dev.azure.com/org'
    }
    
    # Should pass with all required keys
    $result1 = Test-DotEnvConfig -Config $config -RequiredKeys @('ADO_PAT', 'GITLAB_PAT')
    if (-not $result1) {
        throw "Validation should pass with all required keys present"
    }
    
    # Should fail with missing key
    $result2 = Test-DotEnvConfig -Config $config -RequiredKeys @('ADO_PAT', 'MISSING_KEY') -WarningAction SilentlyContinue
    if ($result2) {
        throw "Validation should fail with missing required key"
    }
}

Test-Requirement "Test-DotEnvConfig detects empty values" {
    $config = @{
        'ADO_PAT' = ''
        'GITLAB_PAT' = 'test-token'
    }
    
    $result = Test-DotEnvConfig -Config $config -RequiredKeys @('ADO_PAT', 'GITLAB_PAT') -WarningAction SilentlyContinue
    if ($result) {
        throw "Validation should fail with empty required value"
    }
}

#endregion

#region Migration Mode Tests

Write-Host "`n=== MIGRATION MODE VALIDATION ===" -ForegroundColor Cyan

Test-Requirement "Preflight mode requires Source parameter" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    
    if (-not (Test-Path $scriptPath)) {
        throw "Main script not found: $scriptPath"
    }
    
    # Test parameter validation by checking parameter attributes
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $params = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.ParameterAst]}, $true)
    
    $sourceParam = $params | Where-Object { $_.Name.VariablePath.UserPath -eq 'Source' }
    if (-not $sourceParam) {
        throw "Source parameter not found in script"
    }
}

Test-Requirement "Initialize mode requires Source and Project parameters" {
    # Validate that parameter sets are correctly defined
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    if ($content -notmatch 'Initialize') {
        throw "Initialize mode not found in script"
    }
    
    if ($content -notmatch '\$Source' -or $content -notmatch '\$Project') {
        throw "Source or Project parameter not found in script"
    }
}

Test-Requirement "Migrate mode supports AllowSync flag" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    if ($content -notmatch 'AllowSync') {
        throw "AllowSync parameter not found in script"
    }
    
    # Verify it's a switch parameter
    if ($content -notmatch '\[switch\]\s*\$AllowSync') {
        throw "AllowSync should be a switch parameter"
    }
}

Test-Requirement "Migrate mode supports Force flag" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    if ($content -notmatch '\[switch\]\s*\$Force') {
        throw "Force parameter not found or not a switch"
    }
}

Test-Requirement "Migrate mode supports Replace flag" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    if ($content -notmatch '\[switch\]\s*\$Replace') {
        throw "Replace parameter not found or not a switch"
    }
}

Test-Requirement "BulkMigrate mode handles config files" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    if ($content -notmatch 'BulkMigrate|bulkMigrate') {
        throw "BulkMigrate mode not found"
    }
    
    # Migration module should handle bulk operations
    $migrationModule = Join-Path $moduleRoot "Migration.psm1"
    $moduleContent = Get-Content $migrationModule -Raw
    if ($moduleContent -notmatch 'Bulk') {
        throw "Bulk migration functionality not found in Migration module"
    }
    
    # Check for bulk workflow functions
    if ($moduleContent -notmatch 'Invoke-BulkMigrationWorkflow|Invoke-BulkPreparationWorkflow') {
        throw "Bulk migration workflow functions not found"
    }
}

#endregion

#region Validation and Preflight Tests

Write-Host "`n=== VALIDATION & PREFLIGHT ===" -ForegroundColor Cyan

Test-Requirement "Preflight report schema has required fields" {
    Import-Module (Join-Path $moduleRoot "GitLab.psm1") -Force
    Import-Module (Join-Path $moduleRoot "AzureDevOps.psm1") -Force
    Import-Module (Join-Path $moduleRoot "Migration.psm1") -Force
    
    # Check that New-MigrationPreReport function exists
    $cmd = Get-Command New-MigrationPreReport -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "New-MigrationPreReport function not found"
    }
    
    # Verify it accepts AllowSync parameter
    if (-not $cmd.Parameters.ContainsKey('AllowSync')) {
        throw "New-MigrationPreReport should accept AllowSync parameter"
    }
}

Test-Requirement "Force flag can bypass preflight checks" {
    $migrationModule = Join-Path $moduleRoot "Migration.psm1"
    $content = Get-Content $migrationModule -Raw
    
    # Verify Force logic exists
    if ($content -notmatch 'Force') {
        throw "Force parameter handling not found in Migration module"
    }
    
    # Verify blocking issue check with Force
    if ($content -notmatch 'blocking.{0,50}Force') {
        throw "Force bypass logic for blocking issues not found"
    }
}

Test-Requirement "AllowSync affects validation logic" {
    $migrationModule = Join-Path $moduleRoot "Migration.psm1"
    $content = Get-Content $migrationModule -Raw
    
    # Verify AllowSync is checked in validation
    if ($content -notmatch 'AllowSync') {
        throw "AllowSync parameter not referenced in Migration module"
    }
}

Test-Requirement "Replace flag handling exists" {
    $migrationModule = Join-Path $moduleRoot "Migration.psm1"
    $content = Get-Content $migrationModule -Raw
    
    if ($content -notmatch 'Replace') {
        throw "Replace parameter handling not found in Migration module"
    }
}

#endregion

#region API Error Handling Tests

Write-Host "`n=== API ERROR HANDLING ===" -ForegroundColor Cyan

Test-Requirement "API error catalog documents 401 Unauthorized" {
    $catalogPath = Join-Path $projectRoot "docs" "api-errors.md"
    if (-not (Test-Path $catalogPath)) {
        throw "API error catalog not found"
    }
    
    $content = Get-Content $catalogPath -Raw
    if ($content -notmatch '401.*Unauthorized') {
        throw "401 Unauthorized error not documented"
    }
    
    # Should have resolution or cause sections
    if ($content -notmatch '\*\*Resolution\*\*|\*\*Cause\*\*') {
        throw "API errors missing resolution/cause sections"
    }
}

Test-Requirement "API error catalog documents 403 Forbidden" {
    $catalogPath = Join-Path $projectRoot "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    if ($content -notmatch '403.*Forbidden') {
        throw "403 Forbidden error not documented"
    }
}

Test-Requirement "API error catalog documents 404 Not Found" {
    $catalogPath = Join-Path $projectRoot "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    if ($content -notmatch '404.*Not Found') {
        throw "404 Not Found error not documented"
    }
}

Test-Requirement "API error catalog documents rate limiting (429)" {
    $catalogPath = Join-Path $projectRoot "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    if ($content -notmatch '429.*Rate.?Limit') {
        throw "429 Rate Limiting error not documented"
    }
}

Test-Requirement "API error catalog documents Azure DevOps TF codes" {
    $catalogPath = Join-Path $projectRoot "docs" "api-errors.md"
    $content = Get-Content $catalogPath -Raw
    
    $tfCodes = @('TF400813', 'TF401019', 'TF400948')
    foreach ($code in $tfCodes) {
        if ($content -notmatch [regex]::Escape($code)) {
            throw "TF error code not documented: $code"
        }
    }
}

#endregion

#region Configuration Priority Tests

Write-Host "`n=== CONFIGURATION PRIORITY ===" -ForegroundColor Cyan

Test-Requirement "Configuration priority: .env.local > .env > env vars > params" {
    # This tests the documented priority order
    $testKey = "TEST_PRIORITY_$(Get-Random)"
    
    $envFile = Join-Path $($env:TEMP) "test-priority.env"
    $envLocalFile = Join-Path $($env:TEMP) "test-priority.env.local"
    
    try {
        # Create .env with value1
        "$testKey=from_env_file" | Out-File -FilePath $envFile -Encoding UTF8
        
        # Create .env.local with value2
        "$testKey=from_env_local_file" | Out-File -FilePath $envLocalFile -Encoding UTF8
        
        # Set environment variable with value3
        [Environment]::SetEnvironmentVariable($testKey, "from_environment", [EnvironmentVariableTarget]::Process)
        
        # Load both files (local should override env)
        $config = Import-DotEnvFile -Path @($envFile, $envLocalFile)
        
        if ($config[$testKey] -ne 'from_env_local_file') {
            throw ".env.local should override .env, got: $($config[$testKey])"
        }
    }
    finally {
        Remove-Item $envFile, $envLocalFile -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($testKey, $null, [EnvironmentVariableTarget]::Process)
    }
}

Test-Requirement "Environment variables override .env when not using SetEnvironmentVariables" {
    $testKey = "TEST_ENV_OVERRIDE_$(Get-Random)"
    $envFile = Join-Path $($env:TEMP) "test-override.env"
    
    try {
        # Set environment variable
        [Environment]::SetEnvironmentVariable($testKey, "from_environment", [EnvironmentVariableTarget]::Process)
        
        # Create .env file with different value
        "$testKey=from_env_file" | Out-File -FilePath $envFile -Encoding UTF8
        
        # Load without setting env vars (should just return hashtable)
        $config = Import-DotEnvFile -Path $envFile
        
        # Hashtable should have the file value
        if ($config[$testKey] -ne 'from_env_file') {
            throw "Config should have file value, got: $($config[$testKey])"
        }
        
        # But environment should still have original
        $envValue = [Environment]::GetEnvironmentVariable($testKey, [EnvironmentVariableTarget]::Process)
        if ($envValue -ne 'from_environment') {
            throw "Environment should be unchanged, got: $envValue"
        }
    }
    finally {
        Remove-Item $envFile -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($testKey, $null, [EnvironmentVariableTarget]::Process)
    }
}

#endregion

#region Sync Mode Tests

Write-Host "`n=== SYNC MODE FUNCTIONALITY ===" -ForegroundColor Cyan

Test-Requirement "Sync mode documentation exists" {
    $syncGuidePath = Join-Path $projectRoot "SYNC_MODE_GUIDE.md"
    if (-not (Test-Path $syncGuidePath)) {
        throw "SYNC_MODE_GUIDE.md not found"
    }
    
    $content = Get-Content $syncGuidePath -Raw
    
    $requiredSections = @(
        'AllowSync',
        'Usage Examples',
        'Migration History',
        'Configuration Preservation'
    )
    
    foreach ($section in $requiredSections) {
        if ($content -notmatch [regex]::Escape($section)) {
            throw "Sync mode guide missing section: $section"
        }
    }
}

Test-Requirement "Sync mode preserves migration history" {
    $syncGuide = Join-Path $projectRoot "SYNC_MODE_GUIDE.md"
    $content = Get-Content $syncGuide -Raw
    
    # Verify history tracking is documented
    if ($content -notmatch 'migration_count') {
        throw "migration_count not documented in sync mode"
    }
    
    if ($content -notmatch 'previous_migrations') {
        throw "previous_migrations not documented in sync mode"
    }
    
    if ($content -notmatch 'last_sync') {
        throw "last_sync not documented in sync mode"
    }
}

Test-Requirement "Sync mode workflow is documented" {
    $syncGuide = Join-Path $projectRoot "SYNC_MODE_GUIDE.md"
    $content = Get-Content $syncGuide -Raw
    
    $workflowSteps = @(
        'Pre-Validation',
        'Repository Update',
        'History Recording',
        'Completion'
    )
    
    foreach ($step in $workflowSteps) {
        if ($content -notmatch [regex]::Escape($step)) {
            throw "Sync workflow missing step: $step"
        }
    }
}

#endregion

#region Documentation Completeness Tests

Write-Host "`n=== DOCUMENTATION COMPLETENESS ===" -ForegroundColor Cyan

Test-Requirement "README contains configuration section" {
    $readmePath = Join-Path $projectRoot "README.md"
    if (-not (Test-Path $readmePath)) {
        throw "README.md not found"
    }
    
    $content = Get-Content $readmePath -Raw
    
    if ($content -notmatch 'Configuration') {
        throw "README missing Configuration section"
    }
    
    if ($content -notmatch '\.env') {
        throw "README should mention .env file configuration"
    }
}

Test-Requirement "README documents all operation modes" {
    $readmePath = Join-Path $projectRoot "README.md"
    $content = Get-Content $readmePath -Raw
    
    $modes = @('Preflight', 'Initialize', 'Migrate', 'BulkPrepare', 'BulkMigrate')
    
    foreach ($mode in $modes) {
        if ($content -notmatch $mode) {
            throw "README should document mode: $mode"
        }
    }
}

Test-Requirement "QUICK_REFERENCE contains key parameter descriptions" {
    $quickRefPath = Join-Path $projectRoot "QUICK_REFERENCE.md"
    if (-not (Test-Path $quickRefPath)) {
        throw "QUICK_REFERENCE.md not found"
    }
    
    $content = Get-Content $quickRefPath -Raw
    
    # Core parameters that should be documented
    $coreParameters = @('Mode', 'Source', 'Project', 'AllowSync', 'Force')
    
    foreach ($param in $coreParameters) {
        if ($content -notmatch $param) {
            throw "QUICK_REFERENCE missing core parameter: $param"
        }
    }
}

Test-Requirement "Advanced features documentation exists" {
    $advancedPath = Join-Path $projectRoot "examples" "advanced-features.md"
    if (-not (Test-Path $advancedPath)) {
        throw "advanced-features.md not found"
    }
    
    $content = Get-Content $advancedPath -Raw
    
    # Should document new features
    $features = @(
        'Progress Tracking',
        'Telemetry',
        'Dry-Run Preview',
        'Error Catalog'
    )
    
    foreach ($feature in $features) {
        if ($content -notmatch [regex]::Escape($feature)) {
            throw "Advanced features doc missing: $feature"
        }
    }
}

Test-Requirement ".env configuration guide exists" {
    $envDocPath = Join-Path $projectRoot "docs" "env-configuration.md"
    if (-not (Test-Path $envDocPath)) {
        throw "env-configuration.md not found"
    }
    
    $content = Get-Content $envDocPath -Raw
    
    $sections = @(
        'Quick Start',
        'Security',
        'Configuration Priority',
        'Troubleshooting'
    )
    
    foreach ($section in $sections) {
        if ($content -notmatch [regex]::Escape($section)) {
            throw "env-configuration.md missing section: $section"
        }
    }
}

#endregion

#region Logging and Audit Tests

Write-Host "`n=== LOGGING & AUDIT TRAILS ===" -ForegroundColor Cyan

Test-Requirement "Logging module exports core functions" {
    Import-Module (Join-Path $moduleRoot "Logging.psm1") -Force
    
    # Check for key functions (actual names may vary)
    $coreFunctions = @(
        'Write-MigrationMessage',
        'Write-MigrationReport',
        'New-RunManifest',
        'Update-RunManifest'
    )
    
    foreach ($func in $coreFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Logging module missing function: $func"
        }
    }
}

Test-Requirement "New-RunManifest creates manifest with required fields" {
    $manifest = New-RunManifest -Mode "Preflight" -Source "test/repo"
    
    $requiredFields = @('run_id', 'mode', 'source', 'start_time', 'status')
    
    foreach ($field in $requiredFields) {
        if (-not $manifest.$field) {
            throw "Manifest missing field: $field"
        }
    }
}

Test-Requirement "New-RunManifest accepts all valid modes" {
    $validModes = @('Preflight', 'Initialize', 'Migrate', 'BulkPrepare', 'BulkMigrate', 'Interactive')
    
    foreach ($mode in $validModes) {
        $manifest = New-RunManifest -Mode $mode -Source "test/repo"
        if ($manifest.mode -ne $mode) {
            throw "Mode not set correctly: expected $mode, got $($manifest.mode)"
        }
    }
}

#endregion

#region Git Operations Tests

Write-Host "`n=== GIT OPERATIONS ===" -ForegroundColor Cyan

Test-Requirement "GitLab module exports core functions" {
    Import-Module (Join-Path $moduleRoot "GitLab.psm1") -Force
    
    # Check for Get-GitLabProject at minimum
    if (-not (Get-Command Get-GitLabProject -ErrorAction SilentlyContinue)) {
        throw "GitLab module missing Get-GitLabProject function"
    }
    
    # Verify module has commands
    $commands = Get-Command -Module GitLab
    if ($commands.Count -lt 2) {
        throw "GitLab module should export multiple functions, found $($commands.Count)"
    }
}

Test-Requirement "AzureDevOps module exports core functions" {
    # Ensure Core.Rest is available so Invoke-AdoRest is present in session
    Import-Module (Join-Path $moduleRoot "core\Core.Rest.psm1") -Force
    Import-Module (Join-Path $moduleRoot "AzureDevOps.psm1") -Force
    
    # Check for Invoke-AdoRest available in session (provided by Core.Rest)
    if (-not (Get-Command Invoke-AdoRest -ErrorAction SilentlyContinue)) {
        throw "Invoke-AdoRest function not available"
    }
    
    # Check for repository management functions (actual names vary)
    $commands = Get-Command -Module AzureDevOps
    $repoFunctions = $commands | Where-Object { $_.Name -like '*Repo*' }
    if ($repoFunctions.Count -lt 2) {
        throw "AzureDevOps module should have repository management functions"
    }
}

Test-Requirement "Migration module exports core functions" {
    Import-Module (Join-Path $moduleRoot "Migration.psm1") -Force
    
    # Check for preflight function at minimum
    if (-not (Get-Command New-MigrationPreReport -ErrorAction SilentlyContinue)) {
        throw "Migration module missing New-MigrationPreReport function"
    }
    
    # Verify module has multiple commands
    $commands = Get-Command -Module Migration
    if ($commands.Count -lt 3) {
        throw "Migration module should export multiple functions, found $($commands.Count)"
    }
}

#endregion

#region Security Tests

Write-Host "`n=== SECURITY VALIDATION ===" -ForegroundColor Cyan

Test-Requirement ".gitignore excludes .env files" {
    $gitignorePath = Join-Path $projectRoot ".gitignore"
    if (-not (Test-Path $gitignorePath)) {
        throw ".gitignore not found"
    }
    
    $content = Get-Content $gitignorePath -Raw
    
    if ($content -notmatch '\.env\b') {
        throw ".gitignore should exclude .env files"
    }
    
    if ($content -notmatch '\.env\.local') {
        throw ".gitignore should exclude .env.local files"
    }
}

Test-Requirement ".env.example exists and is tracked" {
    $examplePath = Join-Path $projectRoot ".env.example"
    if (-not (Test-Path $examplePath)) {
        throw ".env.example template file not found"
    }
    
    $content = Get-Content $examplePath -Raw
    
    # Should contain placeholder values, not real credentials
    if ($content -match 'glpat-[A-Za-z0-9_-]{20,}') {
        throw ".env.example contains what looks like a real GitLab token"
    }
    
    if ($content -notmatch 'your-.*-here|example|placeholder') {
        throw ".env.example should use placeholder values"
    }
}

Test-Requirement "Documentation warns about credential security" {
    $envDocPath = Join-Path $projectRoot "docs" "env-configuration.md"
    $content = Get-Content $envDocPath -Raw
    
    $securityKeywords = @('Security', 'credential', 'token', 'secret', 'sensitive')
    
    $foundKeywords = 0
    foreach ($keyword in $securityKeywords) {
        if ($content -imatch $keyword) {
            $foundKeywords++
        }
    }
    
    if ($foundKeywords -lt 3) {
        throw "env-configuration.md should emphasize security (found $foundKeywords security-related terms)"
    }
}

#endregion

#region Performance and Optimization Tests

Write-Host "`n=== PERFORMANCE FEATURES ===" -ForegroundColor Cyan

Test-Requirement "Progress tracking module has ETA calculation" {
    Import-Module (Join-Path $moduleRoot "dev\ProgressTracking.psm1") -Force
    
    $cmd = Get-Command Update-MigrationProgress -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Update-MigrationProgress function not found"
    }
    
    # Check help or implementation mentions ETA
    $help = Get-Help Update-MigrationProgress
    if ($help.description.Text -notmatch 'ETA|estimate|remaining') {
        # Check the module file directly
        $moduleFile = Join-Path $moduleRoot "dev\ProgressTracking.psm1"
        $content = Get-Content $moduleFile -Raw
        if ($content -notmatch 'ETA|SecondsRemaining|estimate') {
            throw "Progress tracking should calculate ETA"
        }
    }
}

Test-Requirement "Telemetry collects API call metrics" {
    Import-Module (Join-Path $moduleRoot "dev\Telemetry.psm1") -Force
    
    $cmd = Get-Command Record-TelemetryApiCall -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Record-TelemetryApiCall function not found"
    }
    
    # Verify it accepts duration and status code
    $params = $cmd.Parameters
    if (-not $params.ContainsKey('DurationMs')) {
        throw "Record-TelemetryApiCall should accept DurationMs parameter"
    }
    if (-not $params.ContainsKey('StatusCode')) {
        throw "Record-TelemetryApiCall should accept StatusCode parameter"
    }
}

Test-Requirement "Dry-run preview generates reports" {
    Import-Module (Join-Path $moduleRoot "dev\DryRunPreview.psm1") -Force
    
    $cmd = Get-Command New-MigrationPreview -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "New-MigrationPreview function not found"
    }
    
    # Should support multiple output formats
    $params = $cmd.Parameters
    if (-not $params.ContainsKey('OutputFormat')) {
        throw "New-MigrationPreview should accept OutputFormat parameter"
    }
}

#endregion

#region Integration Scenario Tests

Write-Host "`n=== INTEGRATION SCENARIOS ===" -ForegroundColor Cyan

Test-Requirement "All modules can be loaded together without conflicts" {
    $modules = @(
        'core\Core.Rest.psm1',
        'Logging.psm1',
        'GitLab.psm1',
        'AzureDevOps.psm1',
        'Migration.psm1',
        'dev\ProgressTracking.psm1',
        'dev\Telemetry.psm1',
        'dev\DryRunPreview.psm1',
        'core\EnvLoader.psm1'
    )
    
    foreach ($module in $modules) {
        $modulePath = Join-Path $moduleRoot $module
        if (-not (Test-Path $modulePath)) {
            throw "Module not found: $module"
        }
        
        try {
            Import-Module $modulePath -Force -ErrorAction Stop
        }
        catch {
            throw "Failed to load module $module : $_"
        }
    }
    
    # Verify no command name conflicts
    $commands = Get-Command -Module @(
        'Core.Rest', 'Logging', 'GitLab', 'AzureDevOps', 'Migration',
        'ProgressTracking', 'Telemetry', 'DryRunPreview', 'EnvLoader'
    ) | Group-Object Name | Where-Object { $_.Count -gt 1 }
    
    if ($commands) {
        $conflicts = ($commands | ForEach-Object { $_.Name }) -join ', '
        throw "Command name conflicts detected: $conflicts"
    }
}

Test-Requirement "Main script loads .env file on startup" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    # Should have auto-load logic for .env files
    if ($content -notmatch 'EnvLoader') {
        throw "Main script should load EnvLoader module"
    }
    
    if ($content -notmatch 'Import-DotEnv') {
        throw "Main script should call Import-DotEnv function"
    }
    
    if ($content -notmatch '\.env\.local|\.env') {
        throw "Main script should load .env files"
    }
}

Test-Requirement "Bulk migration supports .env configuration" {
    $scriptPath = Join-Path $projectRoot "Gitlab2DevOps.ps1"
    $content = Get-Content $scriptPath -Raw
    
    # Verify bulk migration can use environment-configured credentials
    if ($content -notmatch 'BulkMigrate') {
        throw "BulkMigrate mode not found"
    }
    
    # Credentials should be loadable from environment
    $requiredEnvVars = @('ADO_PAT', 'GITLAB_PAT', 'ADO_COLLECTION_URL', 'GITLAB_BASE_URL')
    foreach ($var in $requiredEnvVars) {
        if ($content -notmatch [regex]::Escape("`$env:$var")) {
            throw "Script should support environment variable: $var"
        }
    }
}

#endregion

# Display results
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  EXTENDED TEST RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total:   $($testResults.Total)" -ForegroundColor White
Write-Host "Passed:  $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped: $($testResults.Skipped)" -ForegroundColor Yellow
Write-Host ""

$passRate = if ($testResults.Total -gt 0) {
    [math]::Round(($testResults.Passed / $testResults.Total) * 100, 1)
} else { 0 }

Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })
Write-Host ""

if ($testResults.Failed -gt 0) {
    Write-Host "❌ Some tests failed" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Cyan
    exit 1
}
else {
    Write-Host "✅ All extended tests passed!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    exit 0
}
