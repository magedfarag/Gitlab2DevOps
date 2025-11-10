# Compatibility shim
# This file exists so tests that expect modules\Core.Rest.psm1 can import the module.
# It simply loads the real implementation from modules/core/Core.Rest.psm1
$realPath = Join-Path $PSScriptRoot "core\Core.Rest.psm1"
try {
    # If Core.Rest already loaded in this session, do nothing
    $loaded = Get-Module -Name 'Core.Rest' -ErrorAction SilentlyContinue
    if (-not $loaded) {
        if (Test-Path $realPath) {
            # Dot-source the real implementation inside this shim's module scope so that
            # a single module instance (named 'Core.Rest') is created regardless of
            # which path (modules\Core.Rest.psm1 or modules\core\Core.Rest.psm1) is imported.
            . $realPath
        }
        else {
            Write-Error "Core.Rest implementation not found at: $realPath"
        }
    }
}
catch {
    Write-Error "Failed to load Core.Rest shim: $_"
}
