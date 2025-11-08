# Secret Management

Best practices for storing, accessing, and rotating secrets (passwords, API keys, certificates).

## What Are Secrets?

**Secrets** are sensitive credentials that grant access to systems or data:
- **API Keys**: Third-party services (Stripe, SendGrid)
- **Database Passwords**: Connection strings
- **Certificates**: TLS/SSL certificates, code signing
- **SSH Keys**: Server access, Git operations
- **Tokens**: Personal Access Tokens (PAT), OAuth tokens
- **Encryption Keys**: Data encryption keys

**Never**:
- ❌ Hardcode secrets in source code
- ❌ Commit secrets to Git (even in private repos)
- ❌ Store secrets in plaintext files
- ❌ Share secrets via email/chat
- ❌ Use same secret across environments

## Secret Storage Solutions

### Azure Key Vault (Primary)

**Use For**:
- Database connection strings
- API keys
- Certificates
- Encryption keys

**Features**:
- Encryption at rest (FIPS 140-2 Level 2 HSMs)
- Access policies with Azure AD integration
- Audit logging (who accessed what, when)
- Secret versioning
- Automatic rotation (for supported services)
- Soft delete and purge protection

**Access Patterns**:

````````````csharp
// C# example
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

var client = new SecretClient(
    new Uri("https://myvault.vault.azure.net/"),
    new DefaultAzureCredential()
);

KeyVaultSecret secret = await client.GetSecretAsync("database-password");
string password = secret.Value;
````````````

````````````powershell
# PowerShell example
$secret = Get-AzKeyVaultSecret -VaultName "myvault" -Name "database-password"
$password = $secret.SecretValueText
````````````

**Best Practices**:
- Use Managed Identities (no credentials in code)
- Restrict access to Key Vault (RBAC)
- Enable audit logging
- Use separate Key Vaults per environment (dev, staging, prod)
- Enable soft delete and purge protection

### Azure DevOps Variable Groups

**Use For**:
- Pipeline secrets (build/deploy)
- Environment-specific variables

**Features**:
- Encrypted at rest
- Link to Azure Key Vault
- Scoped to pipelines or stages
- Approval gates

**Configuration**:

````````````yaml
# azure-pipelines.yml
variables:
  - group: production-secrets  # Variable group

steps:
  - script: |
      echo "Deploying with API key"
      curl -H "X-API-Key: $(API_KEY)" https://api.example.com
    env:
      API_KEY: $(API_KEY)  # Secret variable from variable group
````````````

**Best Practices**:
- Mark as "secret" (obfuscated in logs)
- Link to Azure Key Vault for production
- Use separate variable groups per environment
- Restrict access to variable groups

### Environment Variables (Runtime)

**Use For**:
- Application runtime secrets
- Container secrets

**Configuration**:

````````````yaml
# docker-compose.yml
services:
  web:
    image: myapp:latest
    environment:
      - DATABASE_PASSWORD=$${DATABASE_PASSWORD}
````````````

````````````yaml
# Kubernetes Secret
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=  # Base64 encoded
````````````

**Best Practices**:
- Never log environment variables
- Use Kubernetes Secrets (not ConfigMaps) for sensitive data
- Rotate regularly
- Inject at runtime (not baked into images)

### Git-Ignored .env Files (Development Only)

**Use For**:
- Local development (never production)

**Setup**:

````````````bash
# .env file (gitignored)
DATABASE_PASSWORD=local_dev_password
API_KEY=dev_key_12345
````````````

````````````bash
# .gitignore
.env
.env.local
````````````

**Best Practices**:
- Provide `.env.template` with dummy values
- Document in README.md
- Never commit actual `.env` file
- Use weak/fake secrets for local dev

## Secret Rotation

### Why Rotate?

- Reduce impact of credential compromise
- Compliance requirements (PCI DSS, SOC 2)
- Limit exposure window
- Detect misuse (old credentials stop working)

### Rotation Frequency

| Secret Type | Rotation Frequency | Why |
|-------------|-------------------|-----|
| **Database Passwords** | 90 days | Compliance, reduce risk |
| **API Keys** | 180 days | Balance security vs. disruption |
| **Certificates** | Before expiry (90 days) | Avoid downtime |
| **SSH Keys** | 1 year | Infrequent change due to disruption |
| **Personal Access Tokens** | 90 days | User-specific, high privilege |
| **Service Account Passwords** | 90 days | High privilege |

### Rotation Process

**Automated Rotation** (Preferred):

````````````powershell
# Example: Azure Key Vault + Azure Function
function Rotate-Secret {
    param($SecretName)
    
    # Generate new secret
    $newPassword = New-RandomPassword -Length 32
    
    # Update application (e.g., database user password)
    Update-DatabasePassword -Username "appuser" -NewPassword $newPassword
    
    # Update Key Vault
    Set-AzKeyVaultSecret -VaultName "myvault" -Name $SecretName -SecretValue (ConvertTo-SecureString $newPassword -AsPlainText -Force)
    
    # Verify application still works
    Test-Application
}
````````````

**Manual Rotation** (If required):
1. Generate new secret
2. Update secret in Key Vault (new version)
3. Deploy application (picks up new secret)
4. Verify application works
5. Delete old secret version (after grace period)

**Zero-Downtime Rotation**:
- Use dual-write pattern (accept both old and new secrets during transition)
- Example: API key rotation with versioned keys

### Certificate Rotation

**Automatic Renewal** (Let's Encrypt, Azure App Service):
- Certificates auto-renew 30 days before expiry
- No manual intervention required

**Manual Renewal**:
1. Generate new certificate (30 days before expiry)
2. Upload to Azure Key Vault
3. Update application configuration
4. Verify HTTPS works
5. Remove old certificate

**Monitoring**:
- Alert 30 days before expiry
- Weekly check for expiring certificates

## Secret Scanning

### Pre-Commit Scanning

**Tools**:
- **git-secrets**: AWS credential scanner
- **truffleHog**: Scans Git history for secrets
- **detect-secrets**: Yelp's secret scanner

**Setup** (git-secrets):

````````````bash
# Install
brew install git-secrets  # macOS
choco install git-secrets  # Windows

# Configure
git secrets --install
git secrets --register-aws  # AWS patterns
git secrets --add 'password\s*=\s*.+'  # Custom patterns
````````````

### CI/CD Scanning

**Azure Pipelines** (CredScan):

````````````yaml
steps:
  - task: CredScan@3
    inputs:
      suppressionsFile: '.credscan/suppressions.json'
  
  - task: PostAnalysis@2
    inputs:
      CredScan: true
````````````

**GitHub** (Secret Scanning):
- Automatically scans for secrets
- Alerts on detected secrets
- Partner patterns (Stripe, AWS, Azure)

**Custom Patterns**:

````````````regex
# Example patterns
api[_-]?key\s*[:=]\s*['"][a-zA-Z0-9]{32}['"]
password\s*[:=]\s*['"][^'"]{8,}['"]
BEGIN\s+(RSA|DSA|EC|OPENSSH)\s+PRIVATE\s+KEY
````````````

### Post-Commit Scanning

**git-secrets** (scan history):

````````````bash
git secrets --scan-history
````````````

**TruffleHog** (deep scan):

````````````bash
trufflehog git https://github.com/myorg/myrepo --only-verified
````````````

### Remediation

**If Secret Committed**:
1. **Rotate Immediately**: Assume secret is compromised
2. **Remove from Git History**: Use `git filter-branch` or BFG Repo-Cleaner
3. **Force Push**: After history rewrite
4. **Notify Team**: All clones need to be reset
5. **Audit**: Check if secret was used maliciously

**BFG Repo-Cleaner** (faster than git filter-branch):

````````````bash
# Replace all passwords in history
bfg --replace-text passwords.txt myrepo.git

# Remove files
bfg --delete-files secrets.json myrepo.git

# Cleanup
cd myrepo.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
````````````

## Access Control

### Principle of Least Privilege

**Grant Minimum Access**:
- Developers: Read-only access to Key Vault (via Managed Identity)
- CI/CD: Read-only access to secrets needed for deployment
- Admins: Full access (create, update, delete secrets)
- Applications: Read-only access to specific secrets

**Azure Key Vault Access Policies**:

````````````powershell
# Grant app read-only access to specific secret
Set-AzKeyVaultAccessPolicy -VaultName "myvault" `
    -ObjectId $appManagedIdentityId `
    -PermissionsToSecrets Get,List `
    -SecretName "database-password"
````````````

### Managed Identities (Preferred)

**Why?**
- No credentials in code
- Automatic credential rotation
- Azure AD integration

**Types**:
- **System-Assigned**: Tied to resource lifecycle (VM, App Service)
- **User-Assigned**: Shared across resources

**Example** (App Service):

````````````csharp
// No credentials needed - uses Managed Identity
var client = new SecretClient(
    new Uri("https://myvault.vault.azure.net/"),
    new DefaultAzureCredential()  // Automatically uses Managed Identity
);
````````````

### Service Principals (If Managed Identity Not Available)

**Use For**:
- Third-party CI/CD (GitHub Actions, CircleCI)
- On-premise servers

**Permissions**:
- Grant only necessary permissions
- Use short-lived tokens (if possible)
- Rotate credentials regularly

## Monitoring & Auditing

### Key Vault Audit Logs

**Enable Diagnostic Logs**:

````````````powershell
Set-AzDiagnosticSetting -ResourceId $keyVaultId `
    -Name "KeyVaultAudit" `
    -WorkspaceId $logAnalyticsWorkspaceId `
    -Enabled $true `
    -Category AuditEvent
````````````

**Monitor For**:
- Failed access attempts (unauthorized access)
- Secret retrieved by unexpected identity
- Secret deleted (should be rare)
- High volume of secret retrievals (potential scraping)

**Alerts**:
- Alert on failed Key Vault access
- Alert on secret deletion
- Alert on access from unexpected IP

### Azure DevOps Audit Logs

**Track**:
- Variable group access
- Pipeline runs (which secrets used)
- Variable group changes

**Audit Query**:

````````````kusto
AzureDevOpsAuditLogs
| where OperationName == "VariableGroup.SecretAccessed"
| project TimeGenerated, UserPrincipalName, ResourceName
````````````

## Secrets in Code Review

**Checklist**:
- [ ] No hardcoded secrets
- [ ] No secrets in comments
- [ ] No secrets in test files
- [ ] Connection strings use Key Vault
- [ ] API keys come from environment variables
- [ ] Certificates loaded from Key Vault
- [ ] No secrets in logs

**Red Flags**:
- String literals that look like passwords: `"P@ssw0rd123"`
- Long alphanumeric strings: `"ak_live_51H..."`
- Base64-encoded strings (potential secret)
- Comments like "// TODO: remove hardcoded password"

## Common Pitfalls

### Logging Secrets

❌ **Bad**:
````````````csharp
logger.LogInformation($$"Connecting with password: {password}");
````````````

✅ **Good**:
````````````csharp
logger.LogInformation("Connecting to database");
````````````

### Exception Messages

❌ **Bad**:
````````````csharp
throw new Exception($$"Failed to connect with connection string: {connectionString}");
````````````

✅ **Good**:
````````````csharp
throw new Exception("Failed to connect to database");
````````````

### URL Parameters

❌ **Bad**:
````````````
https://api.example.com/data?api_key=12345
````````````

✅ **Good**:
````````````
https://api.example.com/data
Authorization: Bearer 12345
````````````

### Git Commits

❌ **Bad**:
````````````bash
git commit -m "Add API key: sk_live_12345"
````````````

✅ **Good**:
````````````bash
git commit -m "Add API key from Key Vault"
````````````

## Emergency Procedures

### Compromised Secret

1. **Rotate Immediately**: Generate new secret
2. **Revoke Old Secret**: Disable/delete compromised credential
3. **Audit Usage**: Check logs for unauthorized usage
4. **Notify Stakeholders**: Security team, affected service owners
5. **Post-Mortem**: How was it compromised? How to prevent?

### Lost Access to Key Vault

**Recovery**:
- Use break-glass admin account (stored in secure physical location)
- Or recover via Azure subscription owner

**Prevention**:
- Multiple Key Vault admins
- Break-glass procedure documented
- Periodic access verification

---

**Secret Management Checklist**:
- [ ] All secrets stored in Azure Key Vault (production)
- [ ] Managed Identities used (where possible)
- [ ] Secret scanning in CI/CD
- [ ] Secrets rotated per schedule
- [ ] Audit logging enabled
- [ ] No secrets in source code
- [ ] Developers trained on secret management

**Questions?** #security or security@company.com

---

## 📚 References

- [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/)
- [HashiCorp Vault](https://www.vaultproject.io/)
- [OWASP Secrets Management](https://owasp.org/www-community/vulnerabilities/Use_of_hard-coded_password)
- [GitHub Secrets Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [Azure DevOps Variable Groups](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups)