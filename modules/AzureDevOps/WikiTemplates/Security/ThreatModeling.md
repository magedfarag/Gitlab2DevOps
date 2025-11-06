# Threat Modeling Guide

Systematic approach to identifying and mitigating security threats.

## What is Threat Modeling?

Threat modeling is a structured process to:
1. **Identify** potential security threats
2. **Analyze** likelihood and impact
3. **Prioritize** risks
4. **Mitigate** through design changes or controls

**When to Threat Model**:
- New features or systems
- Architecture changes
- Before security-sensitive code
- After security incidents (lessons learned)

## STRIDE Methodology

STRIDE is a mnemonic for six threat categories:

### S - Spoofing Identity

**Definition**: Attacker pretends to be someone/something else.

**Examples**:
- Stolen credentials
- Forged authentication tokens
- Man-in-the-middle attacks

**Mitigations**:
- Strong authentication (MFA)
- Mutual TLS
- Digital signatures
- Certificate pinning

### T - Tampering with Data

**Definition**: Unauthorized modification of data.

**Examples**:
- SQL injection
- Parameter tampering
- Message replay attacks

**Mitigations**:
- Input validation
- Parameterized queries
- Digital signatures
- Integrity checks (hashes)
- Immutable logs

### R - Repudiation

**Definition**: User denies performing an action.

**Examples**:
- No audit trail
- Unsigned transactions
- Lack of logging

**Mitigations**:
- Comprehensive logging
- Digital signatures
- Audit trails
- Non-repudiation mechanisms

### I - Information Disclosure

**Definition**: Exposure of confidential information.

**Examples**:
- Verbose error messages
- Unencrypted data transmission
- SQL injection revealing data
- Directory traversal

**Mitigations**:
- Encryption (at rest and in transit)
- Generic error messages
- Proper access controls
- Data masking/redaction

### D - Denial of Service

**Definition**: Making system unavailable to legitimate users.

**Examples**:
- Resource exhaustion
- DDoS attacks
- Algorithmic complexity attacks

**Mitigations**:
- Rate limiting
- Input size limits
- Timeout configurations
- Load balancing
- DDoS protection (Cloudflare, Azure DDoS)

### E - Elevation of Privilege

**Definition**: Gaining higher privileges than authorized.

**Examples**:
- Buffer overflow
- SQL injection to admin
- Privilege escalation bugs

**Mitigations**:
- Principle of least privilege
- Input validation
- Regular security patching
- Secure coding practices

## Threat Modeling Process

### Step 1: Define Scope

**Questions**:
- What are we building?
- What assets are we protecting?
- Who are the users?
- What are trust boundaries?

**Deliverable**: System context diagram

### Step 2: Identify Assets

**Data Assets**:
- User credentials
- Personal information (PII)
- Financial data
- Intellectual property
- Configuration data

**System Assets**:
- Authentication service
- Payment processor
- Database servers
- API endpoints

**Criticality Rating**:
- **High**: Data breach = severe impact
- **Medium**: Degraded functionality
- **Low**: Minimal impact

### Step 3: Create Architecture Diagram

**Components to Include**:
- External entities (users, systems)
- Processes (application components)
- Data stores (databases, caches)
- Data flows (APIs, messages)
- Trust boundaries (network, privilege)

**Example Symbols**:
````````````
[User] --HTTPS--> [Web App] --SQL--> [Database]
         (TLS)                 (Encrypted)
````````````

### Step 4: Identify Threats (STRIDE)

For each data flow and component, apply STRIDE:

| Component | STRIDE Category | Threat | Likelihood | Impact |
|-----------|----------------|--------|------------|--------|
| Login API | Spoofing | Brute force | High | High |
| Login API | Tampering | Parameter manipulation | Medium | High |
| Database | Information Disclosure | SQL injection | Medium | Critical |

### Step 5: Rate Threats (DREAD)

**DREAD Scoring** (1-10 scale):
- **D**amage: How bad if exploited?
- **R**eproducibility: How easy to reproduce?
- **E**xploitability: How easy to exploit?
- **A**ffected Users: How many users impacted?
- **D**iscoverability: How easy to find?

**Risk Score** = (D + R + E + A + D) / 5

| Score | Risk Level | Action |
|-------|-----------|--------|
| 8-10 | Critical | Fix immediately |
| 6-7.9 | High | Fix before release |
| 4-5.9 | Medium | Fix in next sprint |
| 1-3.9 | Low | Document, consider fix |

### Step 6: Mitigate Threats

**Mitigation Strategies**:
1. **Redesign**: Change architecture to eliminate threat
2. **Security Control**: Add authentication, encryption, etc.
3. **Accept Risk**: Document why risk is acceptable
4. **Transfer Risk**: Insurance, third-party service

**Document**:
- Threat ID
- Mitigation approach
- Owner
- Target completion date

### Step 7: Validate Mitigations

**Validation Methods**:
- Security testing (SAST, DAST, penetration testing)
- Code review
- Threat model review (security team)
- Red team exercises

## Attack Surface Analysis

**Attack Vectors**:
- Web interfaces (XSS, CSRF, injection)
- APIs (broken authentication, excessive data exposure)
- Network (DDoS, eavesdropping)
- Physical (device theft, social engineering)
- Supply chain (compromised dependencies)

**Reducing Attack Surface**:
- Minimize exposed endpoints
- Disable unused features
- Principle of least privilege
- Input validation everywhere
- Regular security patching

## Common Threat Scenarios

### Scenario 1: E-commerce Checkout

**Assets**: Payment info, user data, inventory

**Threats**:
- Payment data interception (Information Disclosure)
- Price manipulation (Tampering)
- Fake orders (Spoofing)
- Inventory exhaustion (Denial of Service)

**Mitigations**:
- PCI DSS compliance
- TLS 1.2+
- Server-side price validation
- Rate limiting

### Scenario 2: API Authentication

**Assets**: User credentials, API tokens

**Threats**:
- Credential stuffing (Spoofing)
- Token theft (Spoofing)
- API abuse (Denial of Service)

**Mitigations**:
- OAuth 2.0 / OpenID Connect
- Short-lived tokens
- Refresh token rotation
- Rate limiting per user

### Scenario 3: File Upload

**Assets**: Server filesystem, user data

**Threats**:
- Malware upload (Tampering)
- Path traversal (Elevation of Privilege)
- Resource exhaustion (Denial of Service)

**Mitigations**:
- File type validation (whitelist)
- Antivirus scanning
- Size limits
- Store outside webroot
- Randomized filenames

## Threat Modeling Tools

**Recommended Tools**:
- **Microsoft Threat Modeling Tool**: Free, STRIDE-based
- **OWASP Threat Dragon**: Open source, diagramming
- **IriusRisk**: Commercial, automated threat detection
- **Draw.io**: Manual diagramming

## Documentation Template

````````````markdown
# Threat Model: [Feature Name]

## Scope
- Feature: [Description]
- Assets: [List]
- Trust Boundaries: [Diagram]

## Threats Identified

| ID | Component | STRIDE | Threat | Risk Score | Mitigation | Owner | Status |
|----|-----------|--------|--------|------------|------------|-------|--------|
| T-001 | Login API | S | Brute force | 8.5 | Rate limiting | @security | Done |
| T-002 | Database | I | SQL injection | 9.0 | Parameterized queries | @dev | In Progress |

## Accepted Risks

| ID | Threat | Justification | Compensating Controls |
|----|--------|---------------|----------------------|
| R-001 | [Threat] | [Business reason] | [Alternative controls] |
````````````

---

**Next Steps**:
1. Schedule threat modeling session
2. Invite: Architects, Developers, Security team
3. Use template above
4. Create work items for mitigations
5. Track in [Security Review Required query](/Security/Queries)

**Questions?** #security or security@company.com