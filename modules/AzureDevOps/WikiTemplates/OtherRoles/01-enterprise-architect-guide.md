# 01. Enterprise Architects Guide: Working in the Security-First Software Factory

## 1. Why this Software Factory exists

Our organisation is moving from project-by-project delivery and manual releases to a software factory model. 
A software factory standardises how we build, test, secure, and release software, using automated pipelines, 
shared platforms, and product‑centric teams.

This move is not cosmetic. Research on thousands of technology organisations shows that teams that deploy more 
often, with shorter lead times, lower change failure rates, and faster recovery from incidents, also achieve 
better business outcomes such as profitability, market share, and customer satisfaction 
(see summaries of the DORA research and the book “Accelerate” by Forsgren, Humble, and Kim at 
https://waydev.co/dora-metrics/ and https://thoughtworks.com/insights/articles/improving-your-bottom-line-with-four-key-metrics).

At the same time, regulators and customers expect secure‑by‑design software and traceable development practices. 
The NIST Secure Software Development Framework (SSDF) at https://doi.org/10.6028/NIST.SP.800-218 defines four 
groups of practices we must embed into our way of working:

- Prepare the organization (policies, training, governance).
- Protect the software (secure repos, access control, hardened build and runtime environments).
- Produce well‑secured software (secure design, coding, and testing).
- Respond to vulnerabilities (monitoring, triage, and remediation).

The OWASP Software Assurance Maturity Model (SAMM) at https://owaspsamm.org and OWASP DevSecOps guidance at 
https://owasp.org/projects/ together give us a roadmap for maturing our security practices and pipelines. 
Defence and government programmes such as the U.S. DoD DevSecOps “Platform One” software factory show that a 
centrally managed, security‑first platform with hardened components can dramatically shorten authority‑to‑operate 
timelines and improve reuse (see the DoD DevSecOps Reference Design at 
https://dodcio.defense.gov/Library/ and Platform One information at https://p1.dso.mil).

Our Security‑First Software Factory plan brings these ideas into a single, on‑premises, Azure DevOps Server and 
OpenText Fortify‑based platform, reusing the existing security stack and integrating with our change, monitoring, 
and incident processes.


## 2. What your role is expected to own

As an enterprise architect, you define guardrails and reference architectures that allow teams to move fast without 
creating chaos. In the factory, you focus less on detailed design approvals and more on enabling standardised, 
secure patterns.

You are expected to:

- Provide a small set of approved reference architectures that align with security, data, and infrastructure standards.
- Define and maintain architecture decision records for cross‑cutting choices.
- Work with Platform and Security to ensure the software factory supports the target architectures.
- Help resolve cross‑team dependencies and integration concerns.
- Participate in threat modelling and risk decisions for complex or high‑risk systems.

## 3. How your day‑to‑day work changes

Instead of long architecture documents and infrequent review boards, you now:

- Engage frequently with product and platform teams through short, focused design sessions.
- Maintain living architecture documentation and reusable patterns.
- Use evidence from metrics (for example, incident patterns, performance data) to refine architectures.
- Support incremental modernisation of legacy systems into more modular designs.

## 4. Practices to adopt

1. **Publish opinionated reference architectures.** Make the “paved roads” easy to follow by providing ready‑to‑use patterns and templates.
2. **Use architecture decision records (ADRs).** Capture key decisions, context, and consequences in a lightweight format.
3. **Integrate with security frameworks.** Align reference architectures explicitly with SSDF, OWASP SAMM, and DevSecOps guidance.
4. **Encourage evolutionary architecture.** Support teams in making regular, small improvements rather than rare big redesigns.
5. **Measure architecture quality through outcomes.** Look at reliability, change frequency, and incident data rather than subjective opinions.

## 5. How you collaborate with other teams

- With Platform: ensure the platform supports the reference architectures and required non‑functional properties.
- With Security: embed controls into patterns so that using the pattern automatically satisfies key requirements.
- With Product and Dev teams: review significant design changes early and provide guidance, not just approvals.
- With Infra and Ops: ensure architectures are operable, observable, and aligned with capacity and resilience strategies.

## 6. Metrics that matter for you

- Adoption rate of reference architectures and patterns.
- Number of incidents linked to architectural issues.
- Time and effort required to onboard a new product onto the standard platform.
- Degree of duplication in technologies and patterns across the estate.

## 7. Your first 90 days

- Weeks 1–3: Identify the most common architectures in use and map them to a small set of reference patterns.
- Weeks 4–8: Publish initial reference architectures and work with Platform and Security to ensure they are supported by the factory.
- Weeks 9–12: Pilot the patterns with 1–2 product teams and adjust based on real feedback and metrics.


## References and further reading

- NIST Secure Software Development Framework (SSDF) v1.1: https://doi.org/10.6028/NIST.SP.800-218
- OWASP Software Assurance Maturity Model (SAMM): https://owaspsamm.org
- OWASP DevSecOps Guideline: https://devguide.owasp.org/en/09-operations/01-devsecops/
- OWASP DevSecOps Maturity Model (DSOMM): https://devsecops.owasp.org/
- DORA / “Accelerate” summaries and four key metrics: 
  - https://waydev.co/dora-metrics/
  - https://thoughtworks.com/insights/articles/improving-your-bottom-line-with-four-key-metrics
- DoD Enterprise DevSecOps Reference Design and Platform One software factory:
  - https://dodcio.defense.gov/Library/
  - https://p1.dso.mil
- OWASP Developer Guide (DevSecOps section): https://devguide.owasp.org
- Internal Security‑First Software Factory Plan (Figma): 
  https://www.figma.com/make/3ZYUKLC9POQjmCruUGvamN/Security-First-Software-Factory-Plan


## Additional notes

This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. This section will be extended with more role-specific examples and scenarios based on real incidents and delivery experience. 
