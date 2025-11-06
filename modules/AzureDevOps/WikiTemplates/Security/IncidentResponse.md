# Incident Response Plan

Procedures for detecting, responding to, and recovering from security incidents.

## Incident Severity Levels

| Severity | Definition | Examples | Response Time |
|----------|-----------|----------|---------------|
| **Critical** | Data breach, ransomware, full system compromise | Customer data leaked, production down | 15 minutes |
| **High** | Attempted breach, malware detected, DDoS | Failed intrusion attempt, malware quarantined | 1 hour |
| **Medium** | Policy violation, suspicious activity | Unusual login, unpatched vulnerability | 4 hours |
| **Low** | Minor policy issues, false positives | Failed login attempts, scanning activity | 24 hours |

## Incident Response Team

### Roles & Responsibilities

**Incident Commander** (CISO or designate):
- Overall response coordination
- Communication with executives
- Final decision authority
- Post-incident review

**Technical Lead** (Security Engineer):
- Technical investigation
- Containment and eradication
- Evidence collection
- Recovery coordination

**Communications Lead** (PR/Legal):
- Internal communication
- External communication (if required)
- Regulatory notification
- Media relations

**IT Operations**:
- System isolation
- Log collection
- System restoration
- Monitoring

**Legal Counsel**:
- Regulatory compliance
- Contractual obligations
- Litigation holds
- Privilege assessment

**Business Owner**:
- Business impact assessment
- Stakeholder communication
- Business continuity decisions

## Incident Response Process

### Phase 1: Preparation

**Before an Incident**:
- [ ] Incident response plan documented
- [ ] Team roles assigned
- [ ] Contact list up-to-date
- [ ] Monitoring and alerting configured
- [ ] Backup and recovery tested
- [ ] Tabletop exercises conducted (quarterly)
- [ ] Forensics tools ready

**Contact List**:
- Security Team: security@company.com, #security-incidents
- CISO: [Name], [Phone], [Email]
- IT Operations: [24/7 number]
- Legal: [Name], [Phone]
- PR: [Name], [Phone]
- External: IR firm, law firm, cyber insurance

### Phase 2: Detection & Analysis

**Detection Methods**:
- Security monitoring alerts (SIEM)
- User reports
- Third-party notification
- Anomaly detection
- Threat intelligence

**Initial Assessment**:
1. **Verify**: Is this a real incident?
2. **Classify**: What type of incident?
3. **Severity**: What is the impact?
4. **Scope**: What systems are affected?
5. **Notify**: Alert appropriate team members

**Evidence Collection**:
- Preserve logs (write-protect)
- Take system snapshots
- Document timeline
- Screenshot suspicious activity
- Chain of custody for evidence

**Analysis Questions**:
- What happened?
- When did it happen?
- How did it happen?
- What systems are affected?
- What data is at risk?
- Is the threat still active?

### Phase 3: Containment

**Short-Term Containment**:
- Isolate affected systems (network segmentation)
- Disable compromised accounts
- Block malicious IPs/domains
- Reset credentials
- Increase monitoring

**Long-Term Containment**:
- Apply temporary patches
- Implement compensating controls
- Prepare clean system images
- Document containment actions

**Containment Checklist**:
- [ ] Affected systems identified
- [ ] Network isolation applied
- [ ] Credentials rotated
- [ ] Backups secured
- [ ] Evidence preserved
- [ ] Stakeholders notified

### Phase 4: Eradication

**Remove Threat**:
- Delete malware
- Close vulnerabilities
- Remove unauthorized access
- Patch systems
- Rebuild compromised systems

**Root Cause Analysis**:
- How did attacker gain access?
- What vulnerabilities were exploited?
- What controls failed?
- What could have prevented this?

**Validation**:
- Verify threat removed
- Scan for persistence mechanisms
- Check for backdoors
- Review all access points

### Phase 5: Recovery

**Restore Operations**:
- Restore from clean backups (if needed)
- Rebuild systems from known-good images
- Gradually restore services
- Monitor for re-infection
- Verify system integrity

**Verification**:
- [ ] Systems restored
- [ ] Monitoring enhanced
- [ ] Backups validated
- [ ] Access controls verified
- [ ] Business operations resumed

**Return to Normal Operations**:
- Gradual restoration (phased approach)
- Continuous monitoring (24-48 hours)
- User communication
- Document lessons learned

### Phase 6: Post-Incident Activity

**Lessons Learned Meeting** (within 7 days):
- What happened (timeline)
- What went well
- What needs improvement
- Action items with owners

**Report Generation**:
- Executive summary
- Technical details
- Impact assessment
- Cost analysis
- Recommendations

**Follow-Up Actions**:
- Update incident response plan
- Implement improvements
- Security awareness training
- Policy updates
- Technology improvements

## Communication Plan

### Internal Communication

**Immediate Notification** (Critical/High):
- Security team
- CISO
- CIO/CTO
- Legal
- Affected business units

**Regular Updates**:
- Every 2 hours (Critical)
- Every 4 hours (High)
- Daily (Medium/Low)
- Use #security-incidents channel

**Communication Template**:
````````````
[INCIDENT UPDATE - Severity]
Time: [timestamp]
Status: Detection/Containment/Recovery
Impact: [business impact]
Actions Taken: [summary]
Next Steps: [planned actions]
ETA to Resolution: [estimate]
````````````

### External Communication

**Regulatory Notification**:
- **GDPR**: 72 hours to notify authority
- **HIPAA**: 60 days (if PHI breach)
- **State Laws**: Varies by jurisdiction
- **Payment Card**: PCI DSS notification

**Customer Notification**:
- Notify if customer data affected
- Clear, honest communication
- Remediation steps offered
- Support resources provided

**Media Relations**:
- Single spokesperson (PR lead)
- Prepared statements
- No speculation
- Focus on response actions

**Law Enforcement**:
- Notify if required (ransomware, fraud)
- Evidence preservation
- Cooperation with investigation

## Specific Incident Types

### Ransomware

**Immediate Actions**:
1. Isolate affected systems (disconnect network)
2. Identify ransomware variant
3. Check backups (are they encrypted?)
4. Do NOT pay ransom (consult legal/CISO)
5. Report to law enforcement

**Recovery**:
- Restore from clean backups
- Rebuild systems from scratch
- Patch vulnerabilities
- Reset all credentials

### Data Breach

**Immediate Actions**:
1. Stop data exfiltration
2. Identify compromised data
3. Assess scope (how many records?)
4. Check regulatory requirements
5. Notify legal immediately

**Notification Timeline**:
- Internal: Immediate
- Regulatory: Per regulation (72 hours for GDPR)
- Customers: As soon as feasible
- Law enforcement: If criminal activity

### Phishing Attack

**Immediate Actions**:
1. Block malicious email/domain
2. Identify victims (who clicked?)
3. Reset compromised credentials
4. Scan for malware
5. User awareness reminder

**Indicators**:
- Credential harvesting page
- Malware download
- Financial fraud attempt
- Business email compromise (BEC)

### Insider Threat

**Immediate Actions**:
1. Disable user access
2. Preserve evidence
3. Involve HR/Legal
4. Review access logs
5. Interview if appropriate

**Investigation**:
- Motive, means, opportunity
- Data accessed/exfiltrated
- Timeline of activities
- Accomplices

### DDoS Attack

**Immediate Actions**:
1. Activate DDoS mitigation (Cloudflare, Azure DDoS)
2. Identify attack vector
3. Filter malicious traffic
4. Scale infrastructure (if possible)
5. Notify ISP

**Mitigation**:
- Rate limiting
- Geographic filtering
- Challenge-response (CAPTCHA)
- WAF rules

## Compliance & Legal Considerations

**Evidence Preservation**:
- Chain of custody
- Write-protect logs
- System snapshots
- Attorney-client privilege

**Regulatory Notification**:
- Know your obligations
- Consult legal before notification
- Document notification sent
- Keep acknowledgment records

**Cyber Insurance**:
- Notify insurer immediately
- Follow policy requirements
- Document all costs
- Retain approved vendors

## Tools & Resources

**Incident Response Tools**:
- **SIEM**: Splunk, Azure Sentinel, ELK
- **EDR**: CrowdStrike, Carbon Black
- **Forensics**: EnCase, FTK, Volatility
- **Threat Intelligence**: MISP, ThreatConnect

**Playbooks**:
- Ransomware response
- Data breach response
- Phishing response
- DDoS response
- Insider threat response

**External Resources**:
- Incident response firm (on retainer)
- Forensics specialists
- Law firm (cyber practice)
- Cyber insurance carrier

---

**Test Your Plan**:
- **Tabletop Exercise**: Quarterly
- **Full Simulation**: Annually
- **Update Plan**: After each incident or annually

**Questions?** #security-incidents or security@company.com

---

## 📚 References

- [NIST Incident Response Guide](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-61r2.pdf)
- [Azure Security Incident Response](https://learn.microsoft.com/en-us/security/operations/incident-response-overview)
- [SANS Incident Response Steps](https://www.sans.org/white-papers/33901/)
- [CIS Incident Response Best Practices](https://www.cisecurity.org/)