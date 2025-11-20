# Non-Functional Testing

## Purpose

Non-functional testing checks how well a system behaves under real conditions. It focuses on qualities such as performance, scalability, reliability, security, and usability rather than specific functional outcomes.

Skipping non-functional testing moves risk directly into production.

## Scope of Non-Functional Testing

Typical areas:

- **Performance and load**: response times, throughput, and resource usage under expected and peak loads.
- **Stress and resilience**: behaviour under extreme conditions and failure of dependencies.
- **Scalability**: ability to handle growth in users, data, or transactions.
- **Reliability and availability**: stability over time and ability to operate for long periods.
- **Security**: resistance to attacks and misuse (for example penetration tests and security scans).
- **Usability and accessibility**: ease of use and support for accessibility needs.

Not every release requires every type of non-functional test, but every product needs a clear strategy.

## When to Run Non-Functional Tests

We integrate non-functional tests into the lifecycle.

- **During design**: define non-functional requirements with measurable targets.
- **During development**: run lightweight checks and performance smoke tests in CI where practical.
- **Before major releases**: run deeper performance, security, and resilience tests for high-risk changes.
- **After incidents**: add targeted non-functional tests that reproduce observed failures.

Non-functional testing is not a single hardening phase at the end.

## Ownership and Collaboration

- Product owners define non-functional requirements and business impact.
- Architects and technical leads design to meet those requirements.
- Developers and QA engineers implement and automate tests.
- Security and SRE teams support specialised tests, such as penetration tests and chaos experiments.

## Example: Performance Testing Strategy

For a critical API:

- Define targets (for example 95th percentile latency and maximum error rate at expected peak load).
- Build repeatable load test scenarios with realistic data and usage patterns.
- Integrate a small subset of tests into CI for regression detection.
- Run extended tests before major events or campaigns.
- Monitor in production and adjust tests to reflect real traffic.

## References

- ISO/IEC (2011) *ISO/IEC 25010: Systems and Software Quality Requirements and Evaluation (SQuaRE)*.
- TestRail (2024) *Non-Functional Testing: A Complete Guide*.
- BrowserStack (2024) *Functional vs Non-Functional Testing*.
