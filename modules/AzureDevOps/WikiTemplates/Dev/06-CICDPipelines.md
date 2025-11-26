# 06. CI/CD Pipelines

## Purpose

Continuous integration and continuous delivery or deployment (CI/CD) turn source code into running software in a repeatable, observable, and secure way. They remove manual steps, lower deployment risk, and shorten feedback loops.

Our goal is small, frequent, low-risk changes with strong automated checks.

## Principles

- Define pipelines and environments as code.
- Provide fast feedback on code quality, security, and integration.
- Protect build and deployment infrastructure.
- Use shared templates to avoid drift.
- Separate build, test, and deploy stages clearly.

## Standard Pipeline Stages

Most services should follow this logical structure:

1. Validate.
2. Build.
3. Unit tests.
4. Integration and contract tests.
5. Security and quality gates.
6. Deploy to non-production.
7. Pre-production checks where needed.
8. Deploy to production.
9. Post-deployment verification.

Names can differ, but the intent stays the same.

### Validate

- Run formatters, linters, and basic static analysis.
- Perform quick dependency checks.

### Build

- Compile code and produce artifacts or container images.
- Generate a software bill of materials where possible.
- Store outputs in a trusted artifact repository.

### Unit tests

- Run on every change.
- Keep runtime short to maintain fast feedback.

### Integration and contract tests

- Verify key interactions between components.
- Use test doubles for external dependencies where necessary.

### Security and quality gates

- Run SAST, SCA, and configuration scans.
- Enforce thresholds and fail pipelines on critical or high findings unless a risk owner explicitly accepts them.

### Deploy to non-production

- Deploy automatically to test or staging.
- Run smoke tests and basic non-functional checks.

### Pre-production checks

- Run performance or load tests where justified.
- Run extra security tests or manual reviews for high-risk changes.

### Deploy to production

- Deploy through the pipeline, not by hand.
- Prefer progressive release strategies such as blue-green, canary, or feature flags.

### Post-deployment verification

- Run health checks and business smoke tests.
- Enable automatic rollback where feasible.

## Security of the Pipeline

We treat the pipeline as critical infrastructure.

- Protect build agents and runners with strong authentication and network isolation.
- Limit who can change pipeline definitions and shared templates.
- Use secrets management tools and short-lived tokens.
- Scan container images and base images regularly.
- Sign and verify artifacts where the platform supports it.

A compromised pipeline can compromise every environment.

## Environments and Promotion

We promote artifacts rather than rebuilding them in each environment. This ensures:

- The same binary runs in test and production.
- We can trace incidents back to a specific build.

Promotion decisions rely on:

- Automated test and security results.
- SLO and error budget status.
- Risk assessment of the change.

## Observability of Pipelines

We observe pipelines themselves:

- Metrics: duration, success and failure rates, queue times, flaky tests.
- Logs: structured logs for each stage and step.
- Correlations between deployments and production incidents.

We use this data to improve speed, stability, and developer experience.

## References

- NIST (2022) *Secure Software Development Framework (SSDF) Version 1.1*. NIST Special Publication 800-218.
- GitLab (2025) *DORA Metrics*.
- Microsoft (2025) *Azure DevOps Pipelines Documentation*.
