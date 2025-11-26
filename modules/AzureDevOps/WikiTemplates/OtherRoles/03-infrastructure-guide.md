# 03. Infrastructure and Network Engineering Guide: Working in the Security-First Software Factory

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

As an infrastructure or network engineer, you provide the secure, reliable foundation on which the factory runs. 
In an on‑prem, no‑cloud environment, your designs and operations are critical to both performance and compliance.

You are expected to:

- Provide compute, storage, and network services that support the factory’s environments.
- Implement segmentation, firewalls, and access controls that align with security policies.
- Support infrastructure‑as‑code practices for repeatable environment provisioning.
- Work with Platform to ensure pipelines have the access and capacity they need, within guardrails.
- Participate in capacity planning and incident response.

## 3. How your day‑to‑day work changes

Instead of manually provisioning servers and enforcing one‑off firewall rules, you now:

- Manage infrastructure definitions as code and review changes via version control and pipelines.
- Design standard environment patterns for Dev, Test, Pre‑Prod, and Prod.
- Collaborate closely with Platform and Security on connectivity and control points.
- Use monitoring data to adjust capacity and plan upgrades.

## 4. Practices to adopt

1. **Infrastructure as code.** Use version‑controlled templates and automated provisioning to maintain consistency.
2. **Standard environment patterns.** Publish supported patterns for applications and services.
3. **Least privilege and segmentation.** Design network zones and access paths that minimise blast radius.
4. **Automated validation.** Use configuration and compliance scanning tools as part of the pipeline.
5. **Joint planning.** Work with Platform and Ops on capacity models and resilience strategies.

## 5. How you collaborate with other teams

- With Platform: co‑design environment blueprints and connectivity for the factory.
- With Security: implement network controls, monitoring, and hardening requirements.
- With Ops and Support: align operational processes with infrastructure changes and incidents.
- With Product teams: understand specific needs that may require exceptions or new patterns.

## 6. Metrics that matter for you

- Time to provision or change environments.
- Number of environment‑related incidents and their impact.
- Compliance with baseline hardening and configuration standards.
- Capacity utilisation and headroom for key systems.

## 7. Your first 90 days

- Weeks 1–3: Document current environment patterns and key dependencies for the factory.
- Weeks 4–8: Move at least one critical environment type to infrastructure‑as‑code.
- Weeks 9–12: Introduce automated configuration checks and improve documentation of network and access models.


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
