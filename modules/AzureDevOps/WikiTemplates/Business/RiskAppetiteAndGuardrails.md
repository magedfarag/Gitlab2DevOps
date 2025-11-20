# Risk Appetite and Guardrails

## Purpose

Risk appetite answers how much risk the organisation will accept to achieve its goals. Guardrails turn that answer into daily decisions in engineering and operations.

This page links abstract risk appetite to concrete mechanisms such as SLOs, error budgets, DORA metrics, and pipeline policies.

## Risk Appetite and Risk Tolerance

- Risk appetite is the general level and type of risk the organisation accepts.
- Risk tolerance is the specific threshold for a particular system or process.

Example:

- Appetite: “We accept moderate risk for internal tools and low risk for payment and identity systems.”
- Tolerance: “The payment API has an availability SLO of 99.9 per cent per month with an error budget of about 43 minutes.”

If we never use the error budget, we may over-invest in reliability. If we always exceed it, we accept too much risk.

## Quantitative Signals

We express appetite and tolerance through measurable indicators:

- SLOs and error budgets.
- DORA metrics (deployment frequency, lead time, change failure rate, time to restore).
- Security thresholds (patching cadence, maximum open critical vulnerabilities, baseline controls).

We review these indicators at least quarterly and adjust when priorities change.

## Guardrail Types

Guardrails constrain unsafe freedom without blocking healthy delivery. Examples:

- **CI/CD**: quality and security gates, required tests, policy checks.
- **Change management**: rules for standard, normal, and emergency changes.
- **Security**: minimum encryption standards, secret management requirements, vulnerability SLAs.
- **Architecture**: banned patterns and required patterns.

We prefer guardrails that tools enforce and that make the safe path the easiest path.

## Example: Balancing Speed and Safety

For a customer-facing web service with a 99.9 per cent availability SLO and weekly deployments:

- Increasing deployment frequency without better testing increases change failure rate and burns the error budget.
- Heavy manual approvals protect reliability but reduce speed and learning.

The right balance uses SLOs, DORA metrics, and incident data, not personal preference alone.

## Adjusting Guardrails

Tighten guardrails when you see:

- Frequent incidents from similar causes.
- Repeated SLO or security SLA violations.
- Evidence that teams ignore existing checks.

Loosen or simplify guardrails when:

- Controls add delay but no measurable safety.
- Automation can replace manual approval.
- Teams hit the same bureaucratic friction repeatedly.

Ask whether a control reduces meaningful risk or only provides the appearance of control.

## Roles and Responsibilities

- Executive leadership: sets overall risk appetite.
- Risk, security, and compliance: translate appetite into policies and guardrails.
- Engineering leadership: designs guardrails that fit delivery workflows.
- Teams: operate within guardrails and provide feedback from real incidents and delivery work.

## References

- Forsgren, N., Humble, J. and Kim, G. (2018) *Accelerate: The Science of Lean Software and DevOps*. IT Revolution.
- NIST (2022) *Secure Software Development Framework (SSDF) Version 1.1*. NIST Special Publication 800-218.
- Google SRE (2018) *Site Reliability Engineering Workbook: Error Budget Policy*.
