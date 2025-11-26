# 07. Product Owners and Product Managers Guide: Working in the Security-First Software Factory

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

As a product owner or product manager, you own the vision and outcomes for your product in the factory. Your role is 
to maximise value delivery while respecting security, reliability, and regulatory constraints.

You are expected to:

- Maintain a clear product vision and roadmap tied to measurable outcomes.
- Prioritise backlog items based on value, risk reduction, and learning.
- Ensure that security, reliability, and operability work is visible in the backlog.
- Use metrics from pipelines, production, and incidents to drive prioritisation.
- Communicate trade‑offs transparently to stakeholders.

## 3. How your day‑to‑day work changes

Instead of planning for rare “big bang” releases, you now:

- Plan for frequent, incremental releases that can be measured and adjusted.
- Work closely with Dev, QA, Ops, and Security to understand constraints and opportunities.
- Use DORA metrics and customer feedback to decide where to invest next.
- Treat technical debt and security risk as part of product health, not as optional extras.

## 4. Practices to adopt

1. **Outcome‑oriented roadmaps.** Express plans in terms of customer and business outcomes rather than only feature lists.
2. **Balanced backlogs.** Allocate capacity for features, technical debt, reliability improvements, and security work.
3. **Data‑informed decisions.** Use metrics and experiments to learn what actually improves outcomes.
4. **Small, safe changes.** Encourage teams to deliver in small increments to reduce risk and increase learning speed.
5. **Transparent trade‑offs.** Make security and compliance implications explicit when negotiating scope and timelines.

## 5. How you collaborate with other teams

- With BA and Dev: shape and refine user stories and acceptance criteria.
- With QA: ensure test strategies cover critical user journeys and risks.
- With Security and Compliance: understand obligations and include necessary work.
- With Management and stakeholders: communicate progress and recalibrate expectations based on evidence.

## 6. Metrics that matter for you

- Product‑level DORA metrics (deployment frequency, lead time, change failure rate, MTTR).
- Customer satisfaction and adoption metrics.
- Incident impact on customers (frequency, severity, time to resolution).
- Ratio of capacity spent on new features vs. risk and debt work.

## 7. Your first 90 days

- Weeks 1–3: Clarify vision, key outcomes, and baseline metrics for your product.
- Weeks 4–8: Reshape the backlog to include explicit reliability and security work.
- Weeks 9–12: Run at least one experiment per quarter and use results to adjust roadmap priorities.


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
