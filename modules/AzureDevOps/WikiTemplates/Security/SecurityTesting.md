# Security Testing Checklist

Comprehensive checklist for security testing throughout SDLC.

## Testing Types

### SAST (Static Application Security Testing)

**Purpose**: Analyze source code for vulnerabilities before runtime.

**Tools**:
- **SonarQube**: Code quality + security
- **Checkmarx**: Enterprise SAST
- **Semgrep**: Open source, customizable rules
- **GitHub Advanced Security**: Code scanning

**When to Run**:
- Every commit (PR validation)
- Before merging to main
- Scheduled scans (daily)

**Common Findings**:
- SQL injection vulnerabilities
- XSS (Cross-Site Scripting)
- Hardcoded secrets
- Insecure randomness
- Path traversal

**Pass Criteria**:
- Zero high/critical issues
- All medium issues reviewed
- Technical debt documented

### DAST (Dynamic Application Security Testing)

**Purpose**: Test running application for vulnerabilities.

**Tools**:
- **OWASP ZAP**: Open source, automated scanning
- **Burp Suite**: Manual + automated testing
- **Acunetix**: Web vulnerability scanner
- **Netsparker**: Automated DAST

**When to Run**:
- After deployment to QA/staging
- Before production release
- Monthly in production

**Common Findings**:
- Authentication bypass
- Authorization flaws
- Session management issues
- Security misconfigurations
- Sensitive data exposure

**Pass Criteria**:
- Zero high/critical vulnerabilities
- All medium issues have mitigation plan
- Signed off by security team

### Dependency Scanning

**Purpose**: Identify vulnerabilities in third-party libraries.

**Tools**:
- **Dependabot**: GitHub-native, automated PRs
- **Snyk**: Comprehensive dependency + container scanning
- **WhiteSource**: Enterprise license + vulnerability management
- **npm audit** / **dotnet list package --vulnerable**

**When to Run**:
- Every build
- Daily scheduled scans
- Before adding new dependency

**Pass Criteria**:
- No critical vulnerabilities
- High vulnerabilities: Fix within 7 days
- Medium vulnerabilities: Fix within 30 days

### Container Scanning

**Purpose**: Find vulnerabilities in container images.

**Tools**:
- **Trivy**: Fast, accurate, easy to use
- **Clair**: Open source, CoreOS project
- **Anchore**: Policy-based scanning
- **Azure Container Registry scanning**

**When to Run**:
- Every image build
- Before pushing to registry
- Daily scans of registry

**Pass Criteria**:
- No critical OS vulnerabilities
- Base image updated within 30 days
- No malware detected

### Infrastructure as Code (IaC) Scanning

**Purpose**: Find misconfigurations in infrastructure code.

**Tools**:
- **Checkov**: Multi-cloud, Terraform/CloudFormation/Kubernetes
- **tfsec**: Terraform-specific
- **Terrascan**: Policy-as-code
- **Azure Security Center recommendations**

**When to Run**:
- Every commit
- Before infrastructure deployment
- Scheduled audit (weekly)

**Common Findings**:
- Public storage buckets
- Unencrypted resources
- Missing network restrictions
- Overly permissive IAM roles

**Pass Criteria**:
- Zero high-severity issues
- All resources encrypted
- Network segmentation validated

### Penetration Testing

**Purpose**: Simulate real-world attacks to find exploitable vulnerabilities.

**Types**:
- **Black Box**: No internal knowledge
- **Gray Box**: Limited knowledge (typical)
- **White Box**: Full access to code/architecture

**When to Run**:
- Before major release
- After significant architecture change
- Annually (compliance requirement)

**Scope**:
- Web applications
- APIs
- Mobile apps
- Network infrastructure

**Deliverables**:
- Executive summary
- Detailed findings with PoC
- Remediation recommendations
- Retest report

**Pass Criteria**:
- All critical findings remediated
- Retest confirms fixes
- CISO sign-off

## Security Testing in CI/CD

### Build Phase

````````````yaml
# Example: Azure Pipelines
stages:
  - stage: Build
    jobs:
      - job: Security_Scan
        steps:
          # SAST
          - task: SonarQubePrepare@4
          - task: DotNetCoreCLI@2
            inputs:
              command: 'build'
          - task: SonarQubeAnalyze@4
          
          # Dependency scan
          - script: |
              dotnet list package --vulnerable --include-transitive
            displayName: 'Check for vulnerable dependencies'
          
          # Secret scanning
          - task: CredScan@3
````````````

### Deploy Phase

````````````yaml
  - stage: Deploy_QA
    jobs:
      - job: Security_Tests
        steps:
          # DAST
          - task: OwaspZap@1
            inputs:
              target: 'https://qa.example.com'
          
          # Container scan
          - script: |
              trivy image myapp:${{BUILD_ID}}
            displayName: 'Scan container image'
````````````

## Manual Security Testing

### Authentication Testing

**Checklist**:
- [ ] Test with invalid credentials
- [ ] Test account lockout (brute force protection)
- [ ] Test password reset flow
- [ ] Verify MFA enforcement
- [ ] Test session timeout
- [ ] Test concurrent sessions
- [ ] Test remember me functionality
- [ ] Test logout (session invalidation)

**Tools**: Burp Suite, OWASP ZAP

### Authorization Testing

**Checklist**:
- [ ] Test vertical privilege escalation (user → admin)
- [ ] Test horizontal privilege escalation (user A → user B)
- [ ] Test direct object reference (manipulate IDs)
- [ ] Test API authorization (missing token, expired token)
- [ ] Test role-based access (each role's permissions)
- [ ] Test default permissions (least privilege)

**Tools**: Burp Suite, Postman

### Input Validation Testing

**Checklist**:
- [ ] Test SQL injection (all input fields)
- [ ] Test XSS (reflected, stored, DOM-based)
- [ ] Test command injection
- [ ] Test path traversal
- [ ] Test XML injection / XXE
- [ ] Test LDAP injection
- [ ] Test file upload (malicious files, size limits)
- [ ] Test special characters

**Payloads**: OWASP Testing Guide, PayloadsAllTheThings

### Session Management Testing

**Checklist**:
- [ ] Verify HTTPOnly flag on cookies
- [ ] Verify Secure flag on cookies
- [ ] Test session fixation
- [ ] Test session hijacking
- [ ] Test CSRF protection
- [ ] Test session invalidation on logout
- [ ] Test concurrent session handling

**Tools**: Browser DevTools, Burp Suite

### API Security Testing

**Checklist**:
- [ ] Test broken authentication (missing/weak tokens)
- [ ] Test excessive data exposure (API returns too much)
- [ ] Test rate limiting
- [ ] Test mass assignment (binding attack)
- [ ] Test security misconfiguration
- [ ] Test injection flaws
- [ ] Test improper asset management (old/vulnerable endpoints)

**Reference**: OWASP API Security Top 10

## Security Testing Metrics

### Coverage Metrics

- **SAST Coverage**: % of codebase scanned
- **DAST Coverage**: % of endpoints tested
- **Dependency Coverage**: % of libraries scanned
- **Code Review Coverage**: % of security-relevant code reviewed

### Quality Metrics

- **Mean Time to Detect (MTTD)**: Time from vulnerability introduction to detection
- **Mean Time to Remediate (MTTR)**: Time from detection to fix deployed
- **False Positive Rate**: % of findings that are false positives
- **Escape Rate**: % of vulnerabilities found in production

### Compliance Metrics

- **Critical Findings**: Must be zero before release
- **High Findings**: Must have mitigation plan
- **SLA Compliance**: % of vulnerabilities fixed within SLA
- **Retest Rate**: % of findings requiring retest

## Bug Bounty Program

**Scope**:
- ✅ In-scope: Web app, API, mobile app
- ❌ Out-of-scope: Social engineering, physical security, DDoS

**Rewards**:
- Critical: $$5,000 - $$10,000
- High: $$2,000 - $$5,000
- Medium: $$500 - $$2,000
- Low: $$100 - $$500

**Rules**:
- Do not access other users' data
- Do not perform destructive testing
- Report responsibly (don't disclose publicly)
- One report per vulnerability

**Platform**: HackerOne, Bugcrowd, or internal program

## Security Testing Checklist (Release)

Before production deployment, verify:

- [ ] **SAST**: Clean scan (zero high/critical)
- [ ] **DAST**: Clean scan (zero high/critical)
- [ ] **Dependency Scan**: No critical vulnerabilities
- [ ] **Container Scan**: Base image up-to-date
- [ ] **Manual Testing**: Critical paths tested
- [ ] **Threat Model**: Reviewed and up-to-date
- [ ] **Security Review**: Approved by security team
- [ ] **Penetration Test**: Completed (if required)
- [ ] **Compliance**: All requirements met

---

**Security Testing Schedule**:
- **Daily**: SAST, dependency scanning
- **Per PR**: SAST, secret scanning
- **Per Release**: DAST, full security review
- **Monthly**: Infrastructure scan, third-party audit
- **Annually**: Penetration test, compliance audit

**Questions?** #security or security@company.com

---

## 📚 References

- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [OWASP ZAP (Zed Attack Proxy)](https://www.zaproxy.org/)
- [Burp Suite](https://portswigger.net/burp)
- [Azure Security Testing](https://learn.microsoft.com/en-us/azure/security/develop/secure-dev-overview)
- [NIST Penetration Testing](https://csrc.nist.gov/glossary/term/penetration_testing)