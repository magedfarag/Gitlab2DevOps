# Security Requirements

## Purpose

Security requirements turn abstract risk into concrete, testable expectations. They tell everyone what “secure enough” means for a product or service.

## Scope and Audience

This guideline targets:

- Product owners and business analysts.
- Architects and technical leads.
- Developers and testers.
- Security and platform teams.

We apply it to all software products, internal and external, regardless of technology.

## What Is a Security Requirement?

A security requirement is a clear statement that describes behaviour or a control that protects confidentiality, integrity, availability, or accountability.

Good requirements:

- Reduce ambiguity.
- Support design and implementation decisions.
- Map to tests and monitoring.

Typical categories:

- Access control (authentication, authorisation, session management).
- Data protection (encryption, key management, retention, privacy).
- Input and output handling (validation, encoding, canonicalisation).
- Operational security (logging, monitoring, incident support).
- Supply chain (dependencies, third-party services, licensing).
- Compliance (legal, regulatory, contractual obligations).

## Sources of Security Requirements

We derive security requirements from:

- Laws and regulations (for example data protection and financial rules).
- Corporate policies, standards, and security baselines.
- Threat models and architecture decisions.
- Industry frameworks such as NIST SSDF, OWASP SAMM, and OWASP ASVS.
- Past incidents, bug reports, and penetration test findings.
- Customer contracts and service-level agreements.

When you design a product, ask which of these sources apply and what they imply for this system.

## Lifecycle and Traceability

We manage security requirements across the lifecycle.

1. **Discovery and inception**
   - Capture high-level security goals and constraints.
   - Identify sensitive data, critical transactions, and regulatory scope.

2. **Design**
   - Refine goals into specific, testable requirements.
   - Map each requirement to components, APIs, and data flows.
   - Document trade-offs when you accept risk.

3. **Implementation**
   - Represent requirements as backlog items or acceptance criteria.
   - Link them to user stories, tasks, and technical spikes.
   - Reference relevant standards or patterns.

4. **Verification**
   - Map requirements to tests (unit, integration, non-functional, and security tests).
   - Enforce coverage in CI/CD gates where feasible.

5. **Operations**
   - Confirm that monitoring and alerting support the requirements.
   - Revisit requirements after incidents or significant architecture changes.

Maintain traceability from requirement to design, implementation, tests, and monitoring.

## Working with Security Requirements in Practice

### Minimal checklist for a new service or major feature

For every new service, at least answer:

- How do users authenticate? Which identity provider and MFA model do you use?
- How do you authorise them? Which roles, permissions, or claims do you rely on?
- How do you protect data at rest and in transit?
- What do you log, and how do you protect those logs?
- How do you validate and sanitise inputs and outputs?
- How do you manage third-party services and dependencies?

If you cannot answer one of these questions clearly, you still have security requirements to define.

### Writing good security requirements

Good requirements are:

- Specific: “Encrypt all personal data at rest using approved algorithms”, not “encrypt data”.
- Verifiable: you can test or observe them.
- Bounded: they cover a clear scope and condition.

Useful pattern:

> The system must [control] to mitigate [threat] for [asset] in [context].

Avoid vague words such as “properly”, “securely”, or “appropriately” without measurable criteria.

### Example: API security requirement

> All authenticated API endpoints must:
> - Require tokens issued by the corporate identity provider.
> - Validate scopes or permissions for each operation.
> - Reject requests without a correlation ID header and log the ID for at least 90 days.

You can design, implement, test, and monitor this requirement.

## Roles and Responsibilities

- **Product owner**: ensures security requirements exist and reflect business risk.
- **Architect or technical lead**: translates requirements into design and technical decisions.
- **Developers**: implement controls according to standards and patterns.
- **Testers and QA**: verify that controls work and stay stable.
- **Security and platform teams**: provide baselines, guidance, and shared tooling.

If nobody owns a security requirement, it will not hold under delivery pressure.

## References

- NIST (2022) *Secure Software Development Framework (SSDF) Version 1.1*. NIST Special Publication 800-218.
- OWASP (2021) *Software Assurance Maturity Model (SAMM) Version 2*.
- OWASP (2021) *Application Security Verification Standard (ASVS) Version 4.0.3*.
