# User Password Reset Guide

## Overview

The **User Password Reset** feature (Option 15) automates the process of resetting Active Directory passwords for users exported from GitLab and sending customized email notifications to each user.

## Features

- ✅ **Batch Processing**: Reset passwords for multiple users from exported JSON
- ✅ **Secure Password Generation**: Random passwords with complexity requirements
- ✅ **Email Notifications**: Customizable email templates
- ✅ **CSV Export**: Secure record of temporary passwords
- ✅ **Dry Run Mode**: Test without making changes
- ✅ **Force Password Change**: Users must change password at next login
- ✅ **AD Integration**: Automatic user lookup by username/email

---

## Prerequisites

1. **Active Directory Module**: RSAT-AD-PowerShell must be installed
2. **Domain Membership**: Host must be joined to the domain
3. **AD Permissions**: Account must have permission to reset user passwords
4. **Exported Users**: Users must be exported first (Option 5)
5. **SMTP Access** (Optional): For email notifications

---

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. Export Users (Option 5)                                 │
│     └─> exports/users.json                                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Reset Passwords (Option 15)                             │
│     ├─> Read users.json                                     │
│     ├─> Find AD accounts                                    │
│     ├─> Generate random passwords                           │
│     ├─> Reset AD passwords                                  │
│     ├─> Set "change at next login"                          │
│     ├─> Send email notifications                            │
│     └─> Export results to CSV                               │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Securely Distribute Passwords                           │
│     └─> CSV contains temporary passwords                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Usage

### Interactive Mode

1. Launch the migration tool:
   ```powershell
   .\Gitlab2DevOps.ps1
   ```

2. Select **Option 15** - Reset User Passwords

3. Provide configuration:
   - **Users JSON file**: Path to exported users (default: `exports/users.json`)
   - **Email template**: Custom or default template (default: `templates/password-reset-email.template.txt`)
   - **SMTP server**: Email server address (optional)
   - **SMTP port**: Default 25
   - **From address**: Sender email
   - **Use SSL**: Enable secure connection
   - **Authentication**: SMTP credentials if required
   - **Output CSV**: Results file path
   - **Dry run**: Test mode (recommended first)
   - **Password length**: Default 16 characters

4. Confirm by typing `RESET` (for non-dry-run)

### PowerShell Script Mode

```powershell
# Import the module
Import-Module .\modules\Migration\Reset-UserPasswords.psm1

# Execute password reset
Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -EmailTemplatePath "templates\password-reset-email.template.txt" `
    -SmtpServer "smtp.company.com" `
    -SmtpPort 587 `
    -FromAddress "noreply@company.com" `
    -UseSSL `
    -OutputCsvPath "exports\password-reset-results.csv" `
    -AdoCollectionUrl "https://ado.company.com/tfs/DefaultCollection" `
    -PasswordLength 16 `
    -DryRun
```

### Dry Run (Recommended First)

Always perform a dry run first to verify:
- AD users can be found
- Email template renders correctly
- No unexpected errors

```powershell
Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -OutputCsvPath "exports\test-results.csv" `
    -DryRun `
    -SkipEmailNotification
```

---

## Password Generation

### Default Settings

- **Length**: 16 characters
- **Uppercase**: Minimum 2 (A-Z, excluding I, O)
- **Lowercase**: Minimum 2 (a-z, excluding l, o)
- **Digits**: Minimum 2 (2-9, excluding 0, 1)
- **Special Characters**: Minimum 2 (!@#$%^&*-_=+)

### Example Generated Password

```
A7k$mP9@xR2nW5q#
```

### Customization

```powershell
Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -PasswordLength 20 `
    -OutputCsvPath "exports\results.csv"
```

---

## Email Template

### Template Location

Default: `templates/password-reset-email.template.txt`

### Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `{{UserDisplayName}}` | User's full name from AD | John Smith |
| `{{UserName}}` | GitLab username | jsmith |
| `{{UserEmail}}` | User's email address | john.smith@company.com |
| `{{UserSamAccountName}}` | AD samAccountName | jsmith |
| `{{NewPassword}}` | Generated password | A7k$mP9@xR2nW5q# |
| `{{DomainNetBios}}` | Domain NetBIOS name | CONTOSO |
| `{{AdoCollectionUrl}}` | Azure DevOps URL | https://ado.company.com |
| `{{Timestamp}}` | Generation timestamp | 2025-12-09 14:30:00 |

### Default Template

```text
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
```

### Custom Template

1. Copy the default template:
   ```powershell
   Copy-Item templates\password-reset-email.template.txt templates\custom-password-reset.template.txt
   ```

2. Edit the custom template:
   ```powershell
   notepad templates\custom-password-reset.template.txt
   ```

3. Use the custom template:
   - In interactive mode: Enter custom template path when prompted
   - In script mode: Use `-EmailTemplatePath` parameter

### Template Best Practices

- ✅ Always include `Subject:` line as the first line
- ✅ Include the password: `{{NewPassword}}`
- ✅ Provide login instructions
- ✅ Emphasize security and password change requirement
- ✅ Include support contact information
- ⚠️ Test template rendering in dry-run mode first

---

## SMTP Configuration

### Common SMTP Settings

| Provider | Server | Port | SSL | Authentication |
|----------|--------|------|-----|----------------|
| **Office 365** | smtp.office365.com | 587 | Yes | Required |
| **Gmail** | smtp.gmail.com | 587 | Yes | Required |
| **Internal Exchange** | mail.company.com | 25 | No | Optional |
| **SendGrid** | smtp.sendgrid.net | 587 | Yes | Required |
| **AWS SES** | email-smtp.region.amazonaws.com | 587 | Yes | Required |

### Office 365 Example

```powershell
$smtpCred = Get-Credential # Enter O365 credentials

Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -SmtpServer "smtp.office365.com" `
    -SmtpPort 587 `
    -FromAddress "it-support@company.com" `
    -UseSSL `
    -SmtpCredential $smtpCred `
    -OutputCsvPath "exports\results.csv"
```

### Gmail Example (App Password Required)

```powershell
$gmailPassword = Read-Host "Enter Gmail App Password" -AsSecureString
$smtpCred = New-Object PSCredential("your-email@gmail.com", $gmailPassword)

Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -SmtpServer "smtp.gmail.com" `
    -SmtpPort 587 `
    -FromAddress "your-email@gmail.com" `
    -UseSSL `
    -SmtpCredential $smtpCred `
    -OutputCsvPath "exports\results.csv"
```

### Skip Email Notifications

```powershell
Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -OutputCsvPath "exports\results.csv" `
    -SkipEmailNotification
```

---

## Output CSV Format

### CSV Columns

| Column | Description |
|--------|-------------|
| GitLabUsername | Username from GitLab export |
| GitLabEmail | Email from GitLab export |
| ADUserFound | Boolean - was AD account found |
| ADSamAccountName | Active Directory username |
| ADDisplayName | User's full name from AD |
| ADEmail | Email address from AD |
| PasswordReset | Boolean - was password reset successful |
| NewPassword | Temporary password (⚠️ SENSITIVE) |
| EmailSent | Boolean - was email sent |
| Status | Success/Failed/AD User Not Found |
| ErrorMessage | Error details if failed |

### Example CSV

```csv
GitLabUsername,GitLabEmail,ADUserFound,ADSamAccountName,PasswordReset,NewPassword,EmailSent,Status
jsmith,john.smith@company.com,True,jsmith,True,A7k$mP9@xR2nW5q#,True,Success
mjones,mary.jones@company.com,True,mjones,True,B3x@nQ6$yT8pL4w#,True,Success
unknown,unknown@gmail.com,False,,,False,,False,AD User Not Found
```

### Security Warning

🔒 **IMPORTANT**: The CSV file contains **temporary passwords in plain text**

- Store in a secure location
- Restrict file permissions
- Delete after users have changed passwords
- Never commit to version control
- Never send via unencrypted email

---

## User Matching Logic

The script tries to match GitLab users to AD accounts using the following priority:

1. **samAccountName** match with GitLab username
2. **userPrincipalName** match with GitLab email
3. **EmailAddress** match with GitLab email

### Manual Overrides

If automatic matching fails, you can create a mapping file:

```powershell
# Create user mapping
$mapping = @(
    @{ GitLabUsername = 'jsmith'; ADSamAccountName = 'john.smith' }
    @{ GitLabUsername = 'mjones'; ADSamAccountName = 'mary.jones' }
)

# Manually process with mapping
foreach ($map in $mapping) {
    $adUser = Get-ADUser -Identity $map.ADSamAccountName
    # Reset password logic...
}
```

---

## Troubleshooting

### Issue: AD User Not Found

**Symptoms**: Users marked as "AD User Not Found" in results

**Solutions**:
1. Verify AD user exists: `Get-ADUser -Filter "samAccountName -eq 'username'"`
2. Check username format matches between GitLab and AD
3. Verify email addresses match
4. Review user mapping logic
5. Consider manual mapping for problem users

### Issue: Password Reset Failed

**Symptoms**: "Password Reset Failed" status

**Solutions**:
1. Check AD permissions: `Get-ADUser -Identity username -Properties *`
2. Verify account executing script has "Reset Password" permission
3. Check password policy compliance
4. Review error message in CSV
5. Verify account is not disabled

### Issue: Email Send Failed

**Symptoms**: "EmailSent" = False in results

**Solutions**:
1. Verify SMTP server is reachable: `Test-NetConnection smtp.company.com -Port 587`
2. Check SMTP credentials are correct
3. Verify SSL/TLS settings
4. Check firewall rules
5. Review SMTP server logs
6. Test with simple email:
   ```powershell
   Send-MailMessage -To test@company.com -From noreply@company.com -Subject Test -Body Test -SmtpServer smtp.company.com
   ```

### Issue: Template Variables Not Replaced

**Symptoms**: Email contains literal `{{VariableName}}`

**Solutions**:
1. Verify template file encoding is UTF-8
2. Check variable names match exactly (case-sensitive)
3. Review template file for syntax errors
4. Test with default template first

### Issue: Permission Denied

**Symptoms**: "Access is denied" error

**Solutions**:
1. Run PowerShell as Administrator
2. Verify domain membership: `(Get-WmiObject Win32_ComputerSystem).PartOfDomain`
3. Check AD module is loaded: `Get-Module ActiveDirectory`
4. Verify account has "Reset Password" permission in AD
5. Contact domain administrator

---

## Security Best Practices

### Before Reset

- [ ] Run in dry-run mode first
- [ ] Review list of users to be processed
- [ ] Verify SMTP settings are correct
- [ ] Test with a small subset of users
- [ ] Notify users in advance
- [ ] Schedule during maintenance window

### During Reset

- [ ] Monitor progress and logs
- [ ] Watch for failed resets
- [ ] Verify emails are being sent
- [ ] Keep CSV file secure
- [ ] Document any manual interventions

### After Reset

- [ ] Verify all users received emails
- [ ] Store CSV in secure location with restricted access
- [ ] Follow up with users who failed
- [ ] Monitor for password change compliance
- [ ] Delete CSV after verification period
- [ ] Archive logs for audit trail

### Password Security

- ✅ Use strong password length (16+ characters)
- ✅ Force password change at next login (automatic)
- ✅ Include complexity requirements (automatic)
- ✅ Generate truly random passwords (automatic)
- ✅ Never reuse passwords
- ✅ Never share passwords via insecure channels
- ✅ Delete temporary password records after use

---

## Examples

### Example 1: Basic Dry Run

```powershell
.\Gitlab2DevOps.ps1
# Select Option 15
# Use default users.json
# Use default template
# Skip SMTP configuration (press Enter)
# Use default CSV path
# Choose 'y' for dry run
```

### Example 2: Production Reset with Email

```powershell
.\Gitlab2DevOps.ps1
# Select Option 15
# Users file: exports\users.json
# Template: templates\password-reset-email.template.txt
# SMTP: smtp.office365.com
# Port: 587
# From: it-support@company.com
# SSL: y
# Auth: y
# Username: it-support@company.com
# Password: [secure password]
# CSV: exports\password-reset-20251209.csv
# Dry run: n
# Confirm: RESET
```

### Example 3: Script with Custom Template

```powershell
Import-Module .\modules\Migration\Reset-UserPasswords.psm1

Invoke-UserPasswordReset `
    -UsersJsonPath "C:\exports\users-subset.json" `
    -EmailTemplatePath "C:\templates\custom-email.txt" `
    -SmtpServer "smtp.company.com" `
    -SmtpPort 25 `
    -FromAddress "migration-team@company.com" `
    -OutputCsvPath "C:\exports\reset-results.csv" `
    -AdoCollectionUrl "https://ado.company.com" `
    -PasswordLength 20
```

### Example 4: No Email, Just Reset

```powershell
Invoke-UserPasswordReset `
    -UsersJsonPath "exports\users.json" `
    -OutputCsvPath "exports\results.csv" `
    -SkipEmailNotification
```

---

## Related Documentation

- [User Export/Import Guide](USER_EXPORT_IMPORT.md)
- [Active Directory Structure](AD-Structure-MindMap.md)
- [Security Best Practices](BEST_PRACTICES_ALIGNMENT.md)

---

## Changelog

### Version 1.0.0 (2025-12-09)
- Initial release
- Batch password reset functionality
- Customizable email templates
- CSV export of results
- Dry run mode
- SMTP integration
