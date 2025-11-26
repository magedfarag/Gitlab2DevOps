# 15. Vendors and Strategic Partners Guide: Working in the Security-First Software Factory

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

As a vendor or strategic partner, you contribute products or services that integrate into our software factory and 
production environments. You share responsibility for security, reliability, and compliance of your components.

You are expected to:

- Demonstrate secure development practices aligned with NIST SSDF and OWASP guidance.
- Integrate with our on‑prem, Azure DevOps‑based pipelines where appropriate.
- Provide SBOMs, vulnerability information, and update plans for your software.
- Support joint testing, integration, and incident response activities.
- Respect our change, risk, and regulatory constraints.

## 3. How your day‑to‑day work changes

Instead of delivering black‑box products on infrequent cycles, you now:

- Provide regular, well‑tested updates that can be automated in our pipelines where feasible.
- Share security and quality evidence proactively.
- Work with our Platform and Security teams to ensure integrations are supportable and auditable.
- Participate in joint retrospectives when issues arise.

## 4. Practices to adopt

1. **Transparent security posture.** Share your secure SDLC practices and relevant certifications or attestations.
2. **Automatable deliveries.** Provide packages, APIs, or container images that fit our deployment model.
3. **Clear release notes and guidance.** Explain risks, dependencies, and rollout recommendations.
4. **Joint incident handling.** Agree on contacts, SLAs, and playbooks for security or reliability issues.
5. **Alignment with our standards.** Where possible, align configurations, logging, and monitoring with our factory patterns.

## 5. How you collaborate with other teams

- With Platform and Infra: design integration points and environment requirements.
- With Security and SOC: provide vulnerability details, patch timelines, and logging formats.
- With Product and Ops: support pilots and production rollouts.
- With Procurement and Legal: align contracts with security and change expectations.

## 6. Metrics that matter for you

- Time to deliver patches for critical vulnerabilities.
- Number of security or reliability incidents linked to your components.
- Effort required to integrate and update your software in our environment.
- Customer satisfaction with support and responsiveness.

## 7. Your first 90 days

- Weeks 1–3: Share your secure SDLC and support model; understand our factory and regulatory context.
- Weeks 4–8: Align release and integration processes with our pipelines and environments.
- Weeks 9–12: Participate in at least one joint test or incident simulation and refine collaboration agreements.


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
