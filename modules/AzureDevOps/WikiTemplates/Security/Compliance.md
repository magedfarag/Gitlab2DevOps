# Compliance Requirements

Regulatory and compliance obligations for our systems and data.

## Applicable Standards

### GDPR (General Data Protection Regulation)

**Scope**: EU personal data processing

**Key Requirements**:
- **Lawful Basis**: Consent, contract, legal obligation, vital interests, public task, legitimate interests
- **Data Subject Rights**:
  - Right to access
  - Right to rectification
  - Right to erasure ("right to be forgotten")
  - Right to data portability
  - Right to object
  - Right to restrict processing
- **Data Protection Impact Assessment (DPIA)**: Required for high-risk processing
- **Data Breach Notification**: 72 hours to supervisory authority
- **Privacy by Design**: Embed privacy from project start

**Implementation**:
- [ ] Data inventory (what personal data we process)
- [ ] Legal basis documented for each processing activity
- [ ] Consent management (if using consent as basis)
- [ ] Data subject request process
- [ ] Privacy policy published
- [ ] DPIA for high-risk projects

**Penalties**: Up to €20M or 4% of annual global turnover

### SOC 2 (Service Organization Control)

**Scope**: Service providers handling customer data

**Trust Service Criteria**:
- **Security**: Protection against unauthorized access
- **Availability**: System available for operation as committed
- **Processing Integrity**: System achieves purpose accurately/completely
- **Confidentiality**: Confidential information protected
- **Privacy**: Personal information collected/used/retained/disclosed per commitments

**SOC 2 Type II Requirements**:
- **Policies and Procedures**: Documented security program
- **Risk Assessment**: Annual threat assessment
- **Logical Access Controls**: Authentication, authorization, audit
- **Change Management**: Controlled deployment process
- **Monitoring**: Continuous security monitoring
- **Incident Response**: Documented IR procedures
- **Vendor Management**: Third-party risk assessment

**Evidence Required**:
- Configuration screenshots
- Policy documents
- Access reviews
- Penetration test reports
- Incident logs
- Training records

**Audit Frequency**: Annual

### ISO 27001 (Information Security Management)

**Scope**: Information security management system (ISMS)

**Key Domains** (Annex A):
1. **Information Security Policies**
2. **Organization of Information Security**
3. **Human Resource Security**
4. **Asset Management**
5. **Access Control**
6. **Cryptography**
7. **Physical and Environmental Security**
8. **Operations Security**
9. **Communications Security**
10. **System Acquisition, Development, and Maintenance**
11. **Supplier Relationships**
12. **Information Security Incident Management**
13. **Business Continuity Management**
14. **Compliance**

**Implementation**:
- [ ] Statement of Applicability (SoA)
- [ ] Risk assessment and treatment
- [ ] Documented policies and procedures
- [ ] Internal audits
- [ ] Management review
- [ ] Continual improvement

**Certification**: External audit by accredited body

### PCI DSS (Payment Card Industry Data Security Standard)

**Scope**: Systems handling credit card data

**12 Requirements**:
1. **Install and maintain firewall**
2. **Don't use vendor defaults** (passwords, security parameters)
3. **Protect stored cardholder data** (encrypt)
4. **Encrypt transmission** (TLS 1.2+)
5. **Use anti-virus**
6. **Develop secure systems** (secure coding)
7. **Restrict access by business need-to-know**
8. **Assign unique ID** (no shared accounts)
9. **Restrict physical access**
10. **Track and monitor network access** (logging)
11. **Test security systems** (quarterly scans, annual pentest)
12. **Maintain security policy**

**Merchant Levels**:
- **Level 1**: >6M transactions/year (annual onsite audit)
- **Level 2**: 1-6M transactions/year (annual SAQ)
- **Level 3**: 20K-1M e-commerce transactions/year (annual SAQ)
- **Level 4**: <20K e-commerce transactions/year (annual SAQ)

**Best Practice**: Use payment processor (tokenization) to reduce scope

### HIPAA (Health Insurance Portability and Accountability Act)

**Scope**: Protected Health Information (PHI)

**Key Rules**:
- **Privacy Rule**: Protects PHI from disclosure
- **Security Rule**: Administrative, physical, technical safeguards
- **Breach Notification Rule**: Notification within 60 days

**Technical Safeguards**:
- Access control (unique user IDs)
- Audit controls (logging)
- Integrity controls (protect from alteration)
- Transmission security (encryption)

**Administrative Safeguards**:
- Risk analysis
- Workforce training
- Business associate agreements
- Contingency plan

**Physical Safeguards**:
- Facility access controls
- Workstation security
- Device and media controls

**Penalties**: Up to $$1.5M per year per violation category

### Azure Compliance

**Built-In Compliance**:
- **GDPR**: Data residency, DPAs available
- **SOC 1/2/3**: Certified
- **ISO 27001/27018/27701**: Certified
- **HIPAA/HITECH**: BAA available
- **PCI DSS Level 1**: Service provider certified

**Shared Responsibility**:
- **Microsoft**: Physical security, network, hypervisor
- **Us**: Application, data, access control, configuration

**Compliance Manager**: Azure portal compliance assessment tool

## Compliance Implementation

### Data Classification

| Classification | Examples | Encryption | Access | Retention |
|----------------|----------|------------|--------|-----------|
| **Public** | Marketing materials | Optional | Anyone | As needed |
| **Internal** | Policies, roadmaps | At rest | Employees | 7 years |
| **Confidential** | Customer data, financials | At rest + transit | Need-to-know | Per regulation |
| **Restricted** | PII, PHI, PCI | At rest + transit + use | Role-based | Per regulation |

**PII Examples**: Name, email, address, phone, SSN, IP address, biometric data

**Implementation**:
- [ ] Data classification policy
- [ ] Data discovery and labeling
- [ ] Encryption based on classification
- [ ] Access controls based on classification
- [ ] DLP (Data Loss Prevention) policies

### Data Retention

| Data Type | Retention Period | Legal Hold | Disposal Method |
|-----------|-----------------|------------|-----------------|
| **Customer PII** | Duration of relationship + 90 days | Yes | Secure deletion |
| **Audit Logs** | 7 years | Yes | Archive then delete |
| **Financial Records** | 7 years | Yes | Archive then delete |
| **Email** | 7 years | Yes | Archive then delete |
| **Source Code** | Indefinite | No | Keep in Git |
| **Backups** | 90 days | No | Overwrite |

**Legal Hold**: Suspend deletion if litigation/investigation

**Implementation**:
- [ ] Retention policy documented
- [ ] Automated retention enforcement
- [ ] Legal hold process
- [ ] Secure deletion procedures

### Data Subject Rights (GDPR)

**Right to Access**:
- Process: Submit request via privacy@company.com
- Response time: 30 days
- Format: Portable format (JSON, CSV)

**Right to Erasure**:
- Process: Submit request via privacy@company.com
- Response time: 30 days
- Exceptions: Legal obligation, litigation

**Right to Portability**:
- Process: Submit request via privacy@company.com
- Response time: 30 days
- Format: Machine-readable (JSON, CSV)

**Implementation**:
- [ ] Data subject request portal
- [ ] Identity verification process
- [ ] Request tracking system
- [ ] 30-day SLA

### Third-Party Risk Management

**Vendor Assessment**:
- [ ] Security questionnaire (SIG Lite)
- [ ] SOC 2 report review
- [ ] Privacy policy review
- [ ] Data Processing Agreement (DPA)
- [ ] Business Associate Agreement (BAA) if HIPAA

**Approved Vendors**:
- **Cloud**: Azure, AWS, GCP (with appropriate config)
- **SaaS**: GitHub, Azure DevOps, Slack, Office 365
- **Payment**: Stripe, PayPal (PCI DSS Level 1)
- **Analytics**: Azure App Insights, Google Analytics (anonymized)

**Vendor Review Frequency**: Annual

### Privacy by Design

**7 Foundational Principles**:
1. **Proactive not Reactive**: Anticipate and prevent privacy issues
2. **Privacy as Default**: Maximum privacy by default
3. **Privacy Embedded**: Into design of systems
4. **Full Functionality**: Positive-sum, not zero-sum
5. **End-to-End Security**: Lifecycle protection
6. **Visibility and Transparency**: Open and verifiable
7. **Respect for User Privacy**: User-centric

**Implementation Checklist**:
- [ ] Privacy impact assessment before project start
- [ ] Minimize data collection (only what's needed)
- [ ] Pseudonymization/anonymization where possible
- [ ] Encryption by default
- [ ] User consent management
- [ ] Privacy-preserving analytics
- [ ] Secure by default configuration

## Audit & Compliance Evidence

### Evidence Collection

**Automated Evidence**:
- Access logs (Azure AD sign-ins)
- Security alerts (Azure Sentinel)
- Change logs (Git commits, Azure DevOps)
- Configuration snapshots (Azure Policy)
- Vulnerability scans (Defender for Cloud)

**Manual Evidence**:
- Policy documents
- Training records
- Risk assessments
- Penetration test reports
- Vendor assessments
- Incident reports

**Storage**:
- **Location**: Secure SharePoint with restricted access
- **Retention**: Per compliance requirement (typically 7 years)
- **Organization**: By control domain (e.g., Access Control, Encryption)

### Audit Preparation

**Before Audit**:
- [ ] Evidence collected and organized
- [ ] Gaps identified and remediated
- [ ] Stakeholders briefed
- [ ] Conference room/tools prepared
- [ ] Point of contact assigned

**During Audit**:
- [ ] Daily debrief with team
- [ ] Track auditor requests
- [ ] Provide evidence promptly
- [ ] Clarify questions
- [ ] Document audit findings

**After Audit**:
- [ ] Remediation plan for findings
- [ ] Assign owners and due dates
- [ ] Track to closure
- [ ] Management review
- [ ] Update controls for next audit

### Continuous Compliance

**Monthly**:
- [ ] Review access permissions
- [ ] Review security alerts
- [ ] Review failed authentication attempts
- [ ] Vendor risk assessment for new vendors

**Quarterly**:
- [ ] Vulnerability scan
- [ ] Compliance dashboard review
- [ ] Policy updates (if needed)
- [ ] Training completion check

**Annually**:
- [ ] Risk assessment
- [ ] Penetration test
- [ ] Disaster recovery test
- [ ] Compliance audit (SOC 2, ISO 27001)
- [ ] Policy review and approval
- [ ] Vendor risk re-assessment

## Compliance Metrics

**KPIs**:
- **Audit Findings**: Target: 0 high, <5 medium
- **Data Breaches**: Target: 0
- **Training Compliance**: Target: 100% completion within 30 days of hire
- **Vulnerability Remediation**: Target: <7 days for critical, <30 days for high
- **Access Review**: Target: 100% quarterly
- **Data Subject Requests**: Target: 100% within 30 days

**Dashboard**: Power BI compliance dashboard (link in wiki)

---

**Compliance Contact**: compliance@company.com or #compliance

**Questions?** Reach out to Legal or Security teams.