<#
.SYNOPSIS
    Reset Active Directory user passwords and send email notifications.

.DESCRIPTION
    Reads exported users from JSON, generates random passwords, resets AD accounts,
    and sends email notifications using a customizable email template.

.NOTES
    Module: Reset-UserPasswords
    Version: 1.0.0
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve repository root
$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[$ts][$Level]"
    switch ($Level) {
        'ERROR'   { Write-Host "$prefix $Message" -ForegroundColor Red }
        'WARN'    { Write-Host "$prefix $Message" -ForegroundColor Yellow }
        'DEBUG'   { Write-Host "$prefix $Message" -ForegroundColor Gray }
        'SUCCESS' { Write-Host "$prefix $Message" -ForegroundColor Green }
        default   { Write-Host "$prefix $Message" -ForegroundColor Cyan }
    }
}

function New-RandomPassword {
    [CmdletBinding()]
    param(
        [int]$Length = 16,
        [int]$MinUpperCase = 2,
        [int]$MinLowerCase = 2,
        [int]$MinDigits = 2,
        [int]$MinSpecialChars = 2
    )

    # Define character sets
    $upperCase = 'ABCDEFGHJKLMNPQRSTUVWXYZ'  # Excluded I, O
    $lowerCase = 'abcdefghijkmnopqrstuvwxyz' # Excluded l, o
    $digits = '23456789'                     # Excluded 0, 1
    $specialChars = '!@#$%^&*-_=+'           # Common safe special chars

    # Build password with minimum requirements
    $password = New-Object System.Collections.ArrayList
    
    # Add minimum required characters
    for ($i = 0; $i -lt $MinUpperCase; $i++) {
        $password.Add($upperCase[(Get-Random -Maximum $upperCase.Length)]) | Out-Null
    }
    for ($i = 0; $i -lt $MinLowerCase; $i++) {
        $password.Add($lowerCase[(Get-Random -Maximum $lowerCase.Length)]) | Out-Null
    }
    for ($i = 0; $i -lt $MinDigits; $i++) {
        $password.Add($digits[(Get-Random -Maximum $digits.Length)]) | Out-Null
    }
    for ($i = 0; $i -lt $MinSpecialChars; $i++) {
        $password.Add($specialChars[(Get-Random -Maximum $specialChars.Length)]) | Out-Null
    }

    # Fill remaining length with random characters from all sets
    $allChars = $upperCase + $lowerCase + $digits + $specialChars
    $remaining = $Length - $password.Count
    for ($i = 0; $i -lt $remaining; $i++) {
        $password.Add($allChars[(Get-Random -Maximum $allChars.Length)]) | Out-Null
    }

    # Shuffle the password characters
    $shuffled = $password | Get-Random -Count $password.Count
    return -join $shuffled
}

function Get-EmailTemplate {
    [CmdletBinding()]
    param(
        [string]$TemplatePath
    )

    if (-not $TemplatePath) {
        $TemplatePath = Join-Path $script:RepoRoot 'templates\password-reset-email.template.txt'
    }

    if (-not (Test-Path $TemplatePath)) {
        Write-Log "Email template not found at: $TemplatePath" 'WARN'
        Write-Log "Creating default template..." 'INFO'
        
        # Create default template
        $defaultTemplate = @'
Subject: Your Account Password Has Been Reset

Dear {{UserDisplayName}},

Your Active Directory account password has been reset as part of the migration to Azure DevOps.

Account Details:
- Username: {{UserName}}
- Email: {{UserEmail}}
- Display Name: {{UserDisplayName}}

New Password: {{NewPassword}}

IMPORTANT:
- Please change this password immediately after your first login
- Keep this password secure and do not share it with anyone
- If you did not request this password reset, please contact IT support immediately

To access Azure DevOps:
1. Navigate to: {{AdoCollectionUrl}}
2. Log in with your domain credentials: {{DomainNetBios}}\{{UserSamAccountName}}
3. Change your password when prompted

For assistance, please contact your IT support team.

Best regards,
IT Support Team

---
This is an automated message. Please do not reply to this email.
Generated on: {{Timestamp}}
'@
        
        $templateDir = Split-Path $TemplatePath -Parent
        if (-not (Test-Path $templateDir)) {
            New-Item -Path $templateDir -ItemType Directory -Force | Out-Null
        }
        
        Set-Content -Path $TemplatePath -Value $defaultTemplate -Encoding UTF8
        Write-Log "Default template created at: $TemplatePath" 'SUCCESS'
    }

    return Get-Content -Path $TemplatePath -Raw
}

function Send-PasswordResetEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ToAddress,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$SmtpServer,
        [int]$SmtpPort = 25,
        [string]$FromAddress = 'noreply@company.com',
        [PSCredential]$Credential,
        [switch]$UseSSL,
        [switch]$DryRun
    )

    if ($DryRun) {
        Write-Log "[DryRun] Would send email to: $ToAddress" 'INFO'
        Write-Log "[DryRun] Subject: $Subject" 'DEBUG'
        return $true
    }

    try {
        $mailParams = @{
            To         = $ToAddress
            From       = $FromAddress
            Subject    = $Subject
            Body       = $Body
            SmtpServer = $SmtpServer
            Port       = $SmtpPort
            ErrorAction = 'Stop'
        }

        if ($Credential) {
            $mailParams['Credential'] = $Credential
        }

        if ($UseSSL) {
            $mailParams['UseSsl'] = $true
        }

        Send-MailMessage @mailParams
        Write-Log "Email sent successfully to: $ToAddress" 'SUCCESS'
        return $true
    }
    catch {
        Write-Log "Failed to send email to ${ToAddress}: $_" 'ERROR'
        return $false
    }
}

function Invoke-UserPasswordReset {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$UsersJsonPath,
        [string]$EmailTemplatePath,
        [string]$SmtpServer,
        [int]$SmtpPort = 25,
        [string]$FromAddress = 'noreply@company.com',
        [PSCredential]$SmtpCredential,
        [switch]$UseSSL,
        [switch]$DryRun,
        [switch]$SkipEmailNotification,
        [string]$OutputCsvPath,
        [string]$AdoCollectionUrl,
        [int]$PasswordLength = 16
    )

    # Validate environment
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module is not available. Install RSAT-AD-PowerShell."
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    if (-not $cs.PartOfDomain) {
        throw "Host is not domain-joined. Join the domain before running."
    }

    # Load users from JSON
    if (-not (Test-Path $UsersJsonPath)) {
        throw "Users JSON file not found: $UsersJsonPath"
    }

    Write-Log "Loading users from: $UsersJsonPath" 'INFO'
    $users = Get-Content -Raw $UsersJsonPath | ConvertFrom-Json
    if (-not $users) { $users = @() }
    if ($users -isnot [array]) { $users = @($users) }

    Write-Log "Found $($users.Count) users in export file" 'INFO'

    # Load email template
    $emailTemplate = Get-EmailTemplate -TemplatePath $EmailTemplatePath

    # Get domain NetBIOS name
    $domain = $env:USERDOMAIN
    if (-not $domain) {
        $domain = (Get-ADDomain).NetBIOSName
    }

    # Initialize results tracking
    $results = New-Object System.Collections.ArrayList
    $successCount = 0
    $failureCount = 0
    $emailSuccessCount = 0
    $emailFailureCount = 0

    Write-Log "Starting password reset process..." 'INFO'
    if ($DryRun) {
        Write-Log "DRY RUN MODE: No changes will be made" 'WARN'
    }

    foreach ($user in $users) {
        $username = $user.username
        $email = if ($user.email) { $user.email } elseif ($user.public_email) { $user.public_email } else { $null }
        $name = if ($user.name) { $user.name } else { $username }

        Write-Log "" 'INFO'
        Write-Log "Processing user: $username" 'INFO'

        # Try to find AD user by username (assuming username matches samAccountName or userPrincipalName)
        $adUser = $null
        try {
            # Try samAccountName first
            $adUser = Get-ADUser -Filter "samAccountName -eq '$username'" -Properties EmailAddress, DisplayName -ErrorAction SilentlyContinue
            
            if (-not $adUser -and $email) {
                # Try userPrincipalName
                $adUser = Get-ADUser -Filter "userPrincipalName -eq '$email'" -Properties EmailAddress, DisplayName -ErrorAction SilentlyContinue
            }

            if (-not $adUser -and $email) {
                # Try email address
                $adUser = Get-ADUser -Filter "EmailAddress -eq '$email'" -Properties EmailAddress, DisplayName -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log "Error searching for user ${username}: $_" 'ERROR'
        }

        if (-not $adUser) {
            Write-Log "AD user not found for: $username (email: $email)" 'WARN'
            $failureCount++
            $results.Add([PSCustomObject]@{
                GitLabUsername = $username
                GitLabEmail = $email
                ADUserFound = $false
                ADSamAccountName = $null
                PasswordReset = $false
                EmailSent = $false
                Status = 'AD User Not Found'
                ErrorMessage = 'Could not locate AD account'
            }) | Out-Null
            continue
        }

        Write-Log "Found AD user: $($adUser.SamAccountName) ($($adUser.DisplayName))" 'SUCCESS'

        # Generate new password
        $newPassword = New-RandomPassword -Length $PasswordLength
        $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force

        # Reset password
        $passwordResetSuccess = $false
        try {
            if ($DryRun) {
                Write-Log "[DryRun] Would reset password for: $($adUser.SamAccountName)" 'INFO'
                $passwordResetSuccess = $true
            }
            elseif ($PSCmdlet.ShouldProcess($adUser.SamAccountName, 'Reset AD Password')) {
                Set-ADAccountPassword -Identity $adUser -NewPassword $securePassword -Reset -ErrorAction Stop
                Write-Log "Password reset successful for: $($adUser.SamAccountName)" 'SUCCESS'
                $passwordResetSuccess = $true
                $successCount++
            }
        }
        catch {
            Write-Log "Failed to reset password for ${username}: $_" 'ERROR'
            $failureCount++
            $results.Add([PSCustomObject]@{
                GitLabUsername = $username
                GitLabEmail = $email
                ADUserFound = $true
                ADSamAccountName = $adUser.SamAccountName
                PasswordReset = $false
                EmailSent = $false
                Status = 'Password Reset Failed'
                ErrorMessage = $_.Exception.Message
            }) | Out-Null
            continue
        }

        # Send email notification
        $emailSent = $false
        if ($passwordResetSuccess -and -not $SkipEmailNotification) {
            $targetEmail = if ($adUser.EmailAddress) { $adUser.EmailAddress } else { $email }
            
            if (-not $targetEmail) {
                Write-Log "No email address available for: $($adUser.SamAccountName)" 'WARN'
            }
            else {
                # Populate email template
                $emailBody = $emailTemplate `
                    -replace '{{UserDisplayName}}', $adUser.DisplayName `
                    -replace '{{UserName}}', $username `
                    -replace '{{UserEmail}}', $targetEmail `
                    -replace '{{UserSamAccountName}}', $adUser.SamAccountName `
                    -replace '{{NewPassword}}', $newPassword `
                    -replace '{{DomainNetBios}}', $domain `
                    -replace '{{AdoCollectionUrl}}', $AdoCollectionUrl `
                    -replace '{{Timestamp}}', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

                # Extract subject from template (first line starting with "Subject:")
                $subject = "Your Account Password Has Been Reset"
                if ($emailBody -match '(?m)^Subject:\s*(.+)$') {
                    $subject = $matches[1].Trim()
                    $emailBody = $emailBody -replace '(?m)^Subject:\s*.+\r?\n', ''
                }

                if ($SmtpServer) {
                    $emailSent = Send-PasswordResetEmail `
                        -ToAddress $targetEmail `
                        -Subject $subject `
                        -Body $emailBody `
                        -SmtpServer $SmtpServer `
                        -SmtpPort $SmtpPort `
                        -FromAddress $FromAddress `
                        -Credential $SmtpCredential `
                        -UseSSL:$UseSSL `
                        -DryRun:$DryRun

                    if ($emailSent) {
                        $emailSuccessCount++
                    } else {
                        $emailFailureCount++
                    }
                }
                else {
                    Write-Log "SMTP server not configured. Skipping email notification." 'WARN'
                }
            }
        }

        # Record result
        $results.Add([PSCustomObject]@{
            GitLabUsername = $username
            GitLabEmail = $email
            ADUserFound = $true
            ADSamAccountName = $adUser.SamAccountName
            ADDisplayName = $adUser.DisplayName
            ADEmail = $adUser.EmailAddress
            PasswordReset = $passwordResetSuccess
            NewPassword = if ($DryRun) { "[DryRun]" } else { $newPassword }
            EmailSent = $emailSent
            Status = if ($passwordResetSuccess) { 'Success' } else { 'Failed' }
            ErrorMessage = $null
        }) | Out-Null
    }

    # Export results to CSV if requested
    if ($OutputCsvPath -and $results.Count -gt 0) {
        try {
            $results | Export-Csv -Path $OutputCsvPath -NoTypeInformation -Encoding UTF8
            Write-Log "" 'INFO'
            Write-Log "Results exported to: $OutputCsvPath" 'SUCCESS'
            Write-Log "IMPORTANT: Store this file securely - it contains temporary passwords!" 'WARN'
        }
        catch {
            Write-Log "Failed to export results to CSV: $_" 'ERROR'
        }
    }

    # Summary
    Write-Log "" 'INFO'
    Write-Log "========== PASSWORD RESET SUMMARY ==========" 'INFO'
    Write-Log "Total users processed: $($users.Count)" 'INFO'
    Write-Log "Passwords reset successfully: $successCount" 'SUCCESS'
    Write-Log "Password reset failures: $failureCount" 'ERROR'
    if (-not $SkipEmailNotification -and $SmtpServer) {
        Write-Log "Emails sent successfully: $emailSuccessCount" 'SUCCESS'
        Write-Log "Email send failures: $emailFailureCount" 'ERROR'
    }
    Write-Log "===========================================" 'INFO'

    return $results
}

Export-ModuleMember -Function Invoke-UserPasswordReset, New-RandomPassword, Get-EmailTemplate
