# Architecture and Design Guidelines

## Purpose

Architecture decides most of our long-term cost, risk, and speed. A poor design cannot be rescued by late testing or ad hoc fixes.

These guidelines help architects and engineers design systems that:

- Meet functional needs.
- Deliver non-functional quality (performance, reliability, security, maintainability, usability).
- Fit our DevSecOps, observability, and risk expectations.

## Core Principles

### Clear boundaries and ownership

- Give every service a focused responsibility and defined API.
- Avoid services that collect unrelated responsibilities.
- Assign a single owning team for each service and data store.

### Security by design

- Include security requirements and threat models in early design.
- Apply least privilege to identities, network access, and data access.
- Centralise identity and access control when practical.
- Use defence in depth; do not rely on a single control.

### Loose coupling

- Use APIs and message contracts instead of direct database access across services.
- Design for backward-compatible changes and versioning.
- Keep synchronous dependencies small and well understood.

### Observability as a design concern

- Decide which events, metrics, and traces you need before coding.
- Design correlation IDs and their propagation across calls.
- Budget for logs, metrics, and storage as part of architecture.

### Performance, scalability, and resilience

- Design capacity and scaling strategies explicitly.
- Use patterns such as bulkheads, circuit breakers, and retries with back-off.
- Plan for graceful degradation under load or dependency failure.

### Simplicity and consistency

- Prefer simple, well-understood patterns.
- Reuse platform capabilities (CI/CD, observability, auth) instead of building custom versions.
- Follow agreed reference architectures where they exist.

## Non-Functional Quality Attributes

We align with the ISO/IEC 25010 quality model. Key attributes:

- Reliability.
- Performance efficiency.
- Security.
- Maintainability.
- Usability and accessibility.

Each significant design decision should indicate which attributes it optimises and what trade-offs it accepts.

## Reference Architectures

Where possible, we base designs on stable patterns:

- API-centric services behind a shared gateway with centralised authentication and authorisation.
- Event-driven integrations for decoupling between domains.
- Tiered web architectures for user-facing applications.
- Standard patterns for logging, metrics, and tracing.

If you diverge from a reference architecture, document why and what extra risk and complexity that introduces.

## Threat-Aware Design

As part of design work:

- Identify assets that attackers might target (data, functions, identities).
- Identify trust boundaries (network segments, identity boundaries, tenants).
- Consider common threat categories and known weaknesses in similar systems.

You do not need a heavy model for every feature, but you do need conscious choices about what you protect and how you protect it.

## Design Review Expectations

Design reviews should cover at least:

- Goals, constraints, and non-functional requirements.
- Data flows and trust boundaries.
- Identity, access control, and secrets handling.
- Failure modes and recovery paths.
- Observability plan (logs, metrics, traces, dashboards, alerts).
- Security considerations and mapping to relevant standards.

## References

- ISO/IEC (2011) *ISO/IEC 25010: Systems and Software Quality Requirements and Evaluation (SQuaRE)*.
- NIST (2022) *Secure Software Development Framework (SSDF) Version 1.1*. NIST Special Publication 800-218.
- OWASP (2021) *Application Security Verification Standard (ASVS) Version 4.0.3*.
