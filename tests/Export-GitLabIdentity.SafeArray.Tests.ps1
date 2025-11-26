Import-Module "$PSScriptRoot/../modules/GitLab/GitLab.psm1" -Force -ErrorAction SilentlyContinue
Describe "Export-GitLabIdentity safe array handling" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../modules/Migration/Export-GitLabIdentity.ps1'
    }

    It "Handles single-object responses without .Count error" {
        Mock Invoke-GitLabRest {
            param($Method, $Endpoint, $Query)
            if ($Endpoint -match '/users') {
                return [pscustomobject]@{ Data = [pscustomobject]@{ id = 1; username = 'unit'; created_at = (Get-Date -Format o) }; Headers = @{ 'X-Total' = '1' } }
            }
            if ($Endpoint -match '/groups') {
                return [pscustomobject]@{ Data = [pscustomobject]@{ id = 2; full_path = 'group/path' }; Headers = @{ 'X-Total' = '1' } }
            }
            if ($Endpoint -match '/projects') {
                return [pscustomobject]@{ Data = @() ; Headers = @{ 'X-Total' = '0' } }
            }

            return [pscustomobject]@{ Data = @(); Headers = @{} }
        }

        { & $scriptPath -OutDirectory "$PSScriptRoot\temp-exports" -Profile Complete } | Should -Not -Throw
    }
}

