# 10. Observability for Developers

## Purpose

Observability lets you understand what your system does in production without guessing. It turns events in code into signals that you can search, graph, and alert on.

Developers own observability for the code they ship.

## Three Pillars and Golden Signals

We focus on three telemetry types:

- Metrics.
- Logs.
- Traces.

We pay special attention to the four golden signals:

- Latency.
- Traffic.
- Errors.
- Saturation.

If your service exposes these clearly, you make diagnosis and incident response faster.

## Developer Responsibilities

For each feature or service, developers should:

- Define what success looks like in production.
- Identify SLIs and basic SLOs where appropriate.
- Instrument code with metrics, logs, and traces.
- Propagate correlation IDs and trace context.
- Avoid logging secrets or sensitive personal data.
- Test observability in lower environments.

## Logging Guidelines

- Use structured logs rather than free text.
- Include timestamp, severity, service name, correlation ID, and key business identifiers where allowed.
- Use log levels consistently: DEBUG, INFO, WARN, ERROR.
- Avoid logging secrets, credentials, or full personal data.

If many log entries use the highest severity, real problems disappear in the noise.

## Metrics Guidelines

- Use counters for counts (requests, errors).
- Use gauges for current states (queue length, active users).
- Use histograms for latencies and sizes.
- Avoid high-cardinality labels such as raw user IDs.

Metrics should answer questions about volume, performance, errors, and resource usage.

## Tracing Guidelines

- Use a standard tracing library such as OpenTelemetry where available.
- Create spans around meaningful operations (external calls, database queries, heavy computations).
- Propagate trace context across service boundaries.

With good traces, you can answer what happened to a single request without guesswork.

## Learning from Incidents

Use incidents and serious bugs to improve observability:

- During reviews, ask what signal would have detected the issue earlier or simplified debugging.
- Add or refine metrics, logs, and traces based on that insight.
- Keep observability tasks visible in team backlogs.

## References

- Google SRE (2016) ‘Monitoring Distributed Systems’ in *Site Reliability Engineering*.
- Microsoft (2024) *Engineering Fundamentals Playbook: Observability*.
- Cloud Native Computing Foundation (2023) *OpenTelemetry Documentation*.
