# 05. Platform Engineering / Software Factory Team Guide: Working in the Security-First Software Factory

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

As part of the Platform Engineering / Software Factory team, you own the internal developer platform that enables 
all product teams to build, test, scan, and release software safely and consistently on‑premises.

You are expected to:

- Design, operate, and continuously improve the Azure DevOps Server ecosystem (Boards, Repos, Pipelines, Artifacts, Test Plans).
- Integrate OpenText Fortify and the existing security stack into standard pipelines.
- Provide golden pipeline and infrastructure templates that encode security and compliance controls.
- Offer self‑service capabilities for teams while maintaining strong governance and traceability.
- Deliver reliable environments (Dev, Test, Pre‑Prod, Prod) and observability foundations.

## 3. How your day‑to‑day work changes

You move from building one‑off CI/CD scripts for individual projects to running the platform as a product used by many teams:

- You work from a backlog of platform features and improvements.
- You measure platform adoption, reliability, and developer experience.
- You collaborate closely with Security, Infra, and Ops to embed guardrails as code.
- You provide clear documentation and onboarding journeys for teams.

## 4. Practices to adopt

1. **Platform as a product.** Treat internal teams as customers; understand their needs and measure satisfaction.
2. **Golden paths.** Provide a small number of well‑supported templates that cover most use cases.
3. **Secure defaults.** Make the easiest way the safest way by embedding SSDF and OWASP DevSecOps controls into templates.
4. **Observability by default.** Ensure pipelines and environments emit useful metrics and logs.
5. **Change safely.** Use the platform itself to test and roll out platform changes with minimal disruption.

## 5. How you collaborate with other teams

- With Product and Dev teams: gather requirements, prioritise platform features, and support onboarding.
- With Security and SOC: integrate tools, define policies, and provide evidence for audits.
- With Infra and Ops: ensure the platform is reliable, scalable, and aligned with capacity plans.

## 6. Metrics that matter for you

- Number of teams and services onboarded to standard pipelines.
- Pipeline reliability and average time to complete.
- Mean time to resolve platform incidents.
- Percentage of releases using golden templates vs. custom pipelines.

## 7. Your first 90 days

- Weeks 1–3: Stabilise core Azure DevOps Server and Fortify integrations; document current capabilities.
- Weeks 4–8: Publish and refine first set of golden pipelines and environment templates.
- Weeks 9–12: Onboard a first wave of pilot teams and adjust based on their feedback and platform metrics.


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
