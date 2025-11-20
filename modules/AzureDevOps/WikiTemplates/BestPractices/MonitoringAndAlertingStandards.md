# Monitoring and Alerting Standards

## Purpose

Monitoring and alerting protect users and the business from surprises. They provide early signals, shorten incident duration, and support learning.

This standard defines the minimum bar for metrics, logs, traces, dashboards, and alerts for production systems.

## Observability Model

We use three types of telemetry:

- Metrics: numeric time series that show health and trends.
- Logs: discrete events with context.
- Traces: end-to-end views of requests across services.

We monitor the four “golden signals” from site reliability engineering practice:

- Latency.
- Traffic.
- Errors.
- Saturation.

## Minimum Standard for Any Service

Each production service must have:

1. **Service level indicators (SLIs) and objectives (SLOs)**
   - At least one SLI for availability or success rate.
   - At least one SLI for latency of key operations.
   - SLOs expressed as percentages over time (for example 99.5 per cent over 30 days).

2. **Dashboards**
   - A main dashboard that shows the golden signals.
   - Views for product metrics where relevant.

3. **Alerts**
   - Alerts on SLO burn and error budget risk.
   - Alerts on critical technical conditions (for example high error rate or severe latency spikes).
   - Routing to the correct on-call group with runbook links.

4. **Logging**
   - Structured logs with timestamp, service name, severity, correlation ID, and key identifiers where allowed.
   - No secrets or sensitive personal data in logs.
   - Retention long enough for troubleshooting and legal needs.

5. **Tracing where practical**
   - Distributed tracing for user-facing and inter-service calls.
   - Propagation of correlation IDs and trace context.

## Alert Design Principles

Follow these principles:

- Every alert must be actionable.
- Every alert must have a clear owner.
- Use severity levels and avoid paging for low-severity issues.
- Tune thresholds and rules to reduce noise.

If the team never acts on a signal, remove or redesign the alert.

## SLOs, Error Budgets, and Governance

We use SLOs and error budgets to link monitoring to decisions.

- SLOs describe target reliability.
- SLIs measure actual performance.
- The error budget represents allowed unreliability over a period.

When a service exhausts its error budget:

- The team prioritises stability work over new features.
- Change velocity may slow until reliability returns to target.
- We document causes and improvements.

## Runbooks

For each critical alert or scenario, provide a runbook that includes:

- Symptoms and triggers.
- Likely causes and quick checks.
- Safe mitigation steps and known pitfalls.
- Links to deeper documentation and dashboards.

A runbook should allow a new engineer to handle an incident without guesswork.

## References

- Beyer, B. et al. (2016) *Site Reliability Engineering: How Google Runs Production Systems*. O'Reilly.
- Google SRE (2016) ‘Monitoring Distributed Systems’ in *Site Reliability Engineering*.
- Datadog (2020) *Service Level Objectives (SLOs) Overview*.
