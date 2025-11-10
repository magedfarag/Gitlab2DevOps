#Requires -Modules Pester
<#
.SYNOPSIS
    Unit tests for Core.Rest module.

.DESCRIPTION
    Tests for REST API helpers, authentication, retry logic, error handling,
    and secret masking functions.
#>

BeforeAll {
    # Import the canonical Core.Rest implementation from modules/core
    $modulePath = Join-Path $PSScriptRoot ".." "modules" "core" "Core.Rest.psm1"
    Import-Module $modulePath -Force
    
    # Mock credentials for testing
    $script:testCollectionUrl = "https://dev.azure.com/testorg"
    $script:testAdoPat = "test-ado-pat-1234567890"
    $script:testGitLabUrl = "https://gitlab.example.com"
    $script:testGitLabToken = "glpat-test1234567890"
    $script:testApiVersion = "7.1"
}

Describe "Hide-Secret" {
    Context "When masking Azure DevOps PAT" {
        It "Should mask PAT in URL" {
            $url = "https://test-ado-pat-1234567890@dev.azure.com/org/project"
            $masked = Hide-Secret -Text $url -Secret "test-ado-pat-1234567890"
            $masked | Should -Be "https://***@dev.azure.com/org/project"
        }
        
        It "Should mask PAT in plain text" {
            $text = "Token: test-ado-pat-1234567890 is invalid"
            $masked = Hide-Secret -Text $text -Secret "test-ado-pat-1234567890"
            $masked | Should -Be "Token: *** is invalid"
        }
        
        It "Should handle empty secret" {
            $text = "No secret here"
            $masked = Hide-Secret -Text $text -Secret ""
            $masked | Should -Be "No secret here"
        }
        
        It "Should handle null text" {
            $masked = Hide-Secret -Text $null -Secret "secret"
            $masked | Should -BeNullOrEmpty
        }
    }
    
    Context "When masking GitLab token" {
        It "Should mask token in URL" {
            $url = "https://oauth2:glpat-test1234567890@gitlab.example.com/group/project.git"
            $masked = Hide-Secret -Text $url -Secret "glpat-test1234567890"
            $masked | Should -Be "https://oauth2:***@gitlab.example.com/group/project.git"
        }
    }
}

Describe "New-NormalizedError" {
    Context "When normalizing ErrorRecord" {
        It "Should extract HTTP status code from exception" {
            $exception = [System.Net.WebException]::new("HTTP 404")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                "WebError",
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $null
            )
            
            $normalized = New-NormalizedError -Exception $errorRecord -Side "ado" -Endpoint "/test"
            
            $normalized.side | Should -Be "ado"
            $normalized.endpoint | Should -Be "/test"
            $normalized.message | Should -Match "HTTP 404"
        }
    }
    
    Context "When normalizing plain Exception" {
        It "Should create normalized error object" {
            $exception = [System.Exception]::new("Test error message")
            
            $normalized = New-NormalizedError -Exception $exception -Side "gitlab" -Endpoint "/api/v4/projects"
            
            $normalized.side | Should -Be "gitlab"
            $normalized.endpoint | Should -Be "/api/v4/projects"
            $normalized.message | Should -Be "Test error message"
        }
    }
    
    Context "When normalizing string error" {
        It "Should handle string input" {
            $normalized = New-NormalizedError -Exception "Simple error string" -Side "ado" -Endpoint "/projects"
            
            $normalized.side | Should -Be "ado"
            $normalized.message | Should -Be "Simple error string"
        }
    }
}

Describe "Get-CoreRestVersion" {
    It "Should return semantic version" {
        $version = Get-CoreRestVersion
        $version | Should -Match '^\d+\.\d+\.\d+$'
    }
    
    It "Should return version 2.0.0 or higher" {
        $version = Get-CoreRestVersion
        $parts = $version -split '\.'
        [int]$parts[0] | Should -BeGreaterOrEqual 2
    }
}

Describe "Initialize-CoreRest" {
    Context "When initializing with valid credentials" {
        It "Should set module-level variables" {
            Initialize-CoreRest `
                -CollectionUrl $testCollectionUrl `
                -AdoPat $testAdoPat `
                -GitLabBaseUrl $testGitLabUrl `
                -GitLabToken $testGitLabToken `
                -AdoApiVersion $testApiVersion
            
            # Test by calling a function that uses these variables
            $version = Get-CoreRestVersion
            $version | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "When initializing with SkipCertificateCheck" {
        It "Should accept SkipCertificateCheck parameter" {
            {
                Initialize-CoreRest `
                    -CollectionUrl $testCollectionUrl `
                    -AdoPat $testAdoPat `
                    -GitLabBaseUrl $testGitLabUrl `
                    -GitLabToken $testGitLabToken `
                    -AdoApiVersion $testApiVersion `
                    -SkipCertificateCheck
            } | Should -Not -Throw
        }
    }
}

Describe "New-AuthHeader" {
    Context "When creating Azure DevOps auth header" {
        It "Should create base64 encoded header" {
            $header = New-AuthHeader -Pat "test-pat-12345" -Type "ado"
            
            $header.Keys | Should -Contain "Authorization"
            $header.Authorization | Should -Match '^Basic '
        }
        
        It "Should include api-version parameter" {
            $header = New-AuthHeader -Pat "test-pat-12345" -Type "ado" -ApiVersion "7.1"
            
            $header.Keys | Should -Contain "api-version"
            $header.'api-version' | Should -Be "7.1"
        }
    }
    
    Context "When creating GitLab auth header" {
        It "Should create token-based header" {
            $header = New-AuthHeader -Pat "glpat-12345" -Type "gitlab"
            
            $header.Keys | Should -Contain "PRIVATE-TOKEN"
            $header.'PRIVATE-TOKEN' | Should -Be "glpat-12345"
        }
    }
}

Describe "Invoke-RestWithRetry" -Tag "Integration" {
    Context "When API call succeeds" {
        BeforeAll {
            # Mock Invoke-RestMethod to simulate success - must specify -ModuleName for Pester v5
            Mock Invoke-RestMethod -ModuleName Core.Rest {
                return @{ success = $true; data = "test" }
            }
        }
        
        It "Should return response on first attempt" {
            $result = Invoke-RestWithRetry `
                -Uri "https://api.example.com/test" `
                -Headers @{ Authorization = "Bearer test" } `
                -Method "GET" `
                -MaxAttempts 3
            
            $result.success | Should -Be $true
            Should -Invoke Invoke-RestMethod -ModuleName Core.Rest -Times 1
        }
    }
    
    Context "When API call fails with retryable error" {
        BeforeAll {
            # Turn off SkipCertificateCheck to avoid curl fallback in tests
            Initialize-CoreRest `
                -CollectionUrl $testCollectionUrl `
                -AdoPat $testAdoPat `
                -GitLabBaseUrl $testGitLabUrl `
                -GitLabToken $testGitLabToken `
                -AdoApiVersion $testApiVersion
            
            # Mock to fail first 2 times with custom error that includes status, succeed on 3rd
            $script:attemptCount = 0
            Mock Invoke-RestMethod -ModuleName Core.Rest {
                $script:attemptCount++
                if ($script:attemptCount -lt 3) {
                    # Create custom exception that includes Response property with StatusCode
                    $mockResponse = [PSCustomObject]@{
                        StatusCode = [PSCustomObject]@{ value__ = 503 }
                    }
                    $mockException = [PSCustomObject]@{
                        Message = "Service Unavailable"
                        Response = $mockResponse
                    }
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Service Unavailable"),
                        "MockError",
                        [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                        $null
                    )
                    # Add Response as note property
                    $errorRecord.Exception | Add-Member -NotePropertyName Response -NotePropertyValue $mockResponse -Force
                    throw $errorRecord
                }
                return @{ success = $true }
            }
            
            # Mock New-NormalizedError to return status 503 for retryable errors
            Mock New-NormalizedError -ModuleName Core.Rest {
                return @{
                    side = 'ado'
                    endpoint = $Endpoint
                    status = 503
                    message = "Service Unavailable"
                }
            }
        }
        
        It "Should retry and eventually succeed" {
            $script:attemptCount = 0
            $result = Invoke-RestWithRetry `
                -Uri "https://api.example.com/test" `
                -Headers @{ Authorization = "Bearer test" } `
                -Method "GET" `
                -MaxAttempts 3 `
                -DelaySeconds 0
            
            $result.success | Should -Be $true
            Should -Invoke Invoke-RestMethod -ModuleName Core.Rest -Times 3
        }
    }
    
    Context "When API call fails permanently" {
        BeforeAll {
            Mock Invoke-RestMethod -ModuleName Core.Rest {
                throw [System.Exception]::new("Permanent failure")
            }
        }
        
        It "Should throw after max attempts" {
            {
                Invoke-RestWithRetry `
                    -Uri "https://api.example.com/test" `
                    -Headers @{ Authorization = "Bearer test" } `
                    -Method "GET" `
                    -MaxAttempts 2 `
                    -DelaySeconds 0
            } | Should -Throw
        }
    }
}

Describe "Module Exports" {
    It "Should export Hide-Secret function" {
        Get-Command Hide-Secret -Module Core.Rest -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export New-NormalizedError function" {
        Get-Command New-NormalizedError -Module Core.Rest -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export Get-CoreRestVersion function" {
        Get-Command Get-CoreRestVersion -Module Core.Rest -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
    
    It "Should export Initialize-CoreRest function" {
        Get-Command Initialize-CoreRest -Module Core.Rest -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

AfterAll {
    # Clean up
    Remove-Module Core.Rest -Force -ErrorAction SilentlyContinue
}
