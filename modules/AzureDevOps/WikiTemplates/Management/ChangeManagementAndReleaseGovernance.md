# Change Management and Release Governance

## Purpose

Change management and release governance reduce harmful surprises while preserving speed. The goal is frequent, safe changes, not rare, risky ones.

This page sets expectations for how we classify, approve, and deploy changes.

## Change Types

We use three main categories:

- **Standard changes**: low risk, repeatable, and pre-approved steps.
- **Normal changes**: medium or uncertain risk; require peer review and appropriate approval.
- **Emergency changes**: high urgency to restore service or fix a critical security issue.

Misclassifying changes creates risk. If most changes appear as “emergency”, the process needs review.

## Principles

- Automate where possible and review where necessary.
- Use risk and data, not hierarchy alone, to decide strictness.
- Embed testing and security checks in the normal flow.
- Learn from incidents and feed lessons back into the process.

## Release Governance Flow for Normal Changes

1. **Proposal**
   - Describe change, impact, risk level, rollback strategy, and test plan.

2. **Review**
   - Peer review of code.
   - Architecture or security review for high-risk work.

3. **Testing**
   - Automated tests and security checks pass in CI.
   - Additional manual or non-functional tests where justified.

4. **Approval**
   - For low-risk systems, peer review and a green pipeline may be enough.
   - For high-risk systems, a delegated approver or a lightweight CAB approves.

5. **Deployment**
   - Use CI/CD pipelines, not manual steps.
   - Prefer progressive rollouts such as canary or blue-green.

6. **Post-deployment**
   - Monitor metrics and logs.
   - Roll back or fix forward if problems appear.

7. **Review**
   - Run a blameless review for failed changes or major incidents.
   - Update tests, guardrails, and documentation.

## Emergency Changes

When a severe incident or critical security issue occurs:

- The on-call engineer and duty manager may trigger an emergency change.
- We still use pipelines and avoid manual edits in production.
- We document what changed, why it was urgent, and which normal steps we skipped.
- We review within a short time and update process, tests, and documentation.

Emergency change is an exception path, not a general shortcut.

## Metrics and Feedback

We track:

- Deployment frequency.
- Change failure rate.
- Time to restore service after failure.
- Lead time from code commit to production.

We use these metrics in governance reviews and adjust process and guardrails accordingly.

## Dependence on Risk Appetite

Change rules depend on risk appetite and system criticality.

- High-risk systems may need stricter checks and approvals.
- Lower-risk internal tools can rely more on automation and lighter approvals.

A single, rigid process for all systems either slows the organisation or exposes it to avoidable risk.

## References

- Forsgren, N., Humble, J. and Kim, G. (2018) *Accelerate: The Science of Lean Software and DevOps*. IT Revolution.
- NIST (2022) *Secure Software Development Framework (SSDF) Version 1.1*. NIST Special Publication 800-218.
- Google SRE (2018) *Site Reliability Engineering Workbook: Error Budget Policy*.
