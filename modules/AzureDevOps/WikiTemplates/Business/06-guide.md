# 06. Business Analysts Guide: Working in the Security-First Software Factory

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

As a business analyst, you translate business goals into clear, testable requirements and user stories that fit a 
product‑centric, continuous delivery environment. You help ensure that what we build is valuable, feasible, and 
aligned with regulatory and security constraints.

You are expected to:

- Capture business needs as user journeys, value streams, and well‑structured backlogs.
- Make requirements testable, including acceptance and security‑relevant criteria.
- Help prioritise work based on business value, risk reduction, and learning.
- Ensure regulatory and data‑protection constraints are visible and traceable down to specific features.
- Work with Product, Security, and Architecture to keep scope realistic and incremental.

## 3. How your day‑to‑day work changes

Instead of large requirement documents handed off at the start of a project, you now:

- Maintain a living backlog of stories and epics.
- Collaborate continuously with Product, Dev, QA, Security, and Operations.
- Think in small increments that can be delivered and validated in weeks, not months.
- Help link DORA and security metrics back to business outcomes (for example, faster feature lead time, fewer customer‑visible incidents).

## 4. Practices to adopt

1. **Value‑stream thinking.** Map how ideas flow from concept to production and identify bottlenecks.
2. **Testable stories.** Always express behaviour in terms that can be checked by automated or manual tests.
3. **Explicit risk and compliance notes.** Capture regulatory or security constraints in the story description so they can be 
   implemented and evidenced.
4. **Small, independent changes.** Slice work into pieces that can be released without waiting for a “big bang”.
5. **Feedback loops.** Use production data, incident reports, and user feedback to refine requirements.

## 5. How you collaborate with other teams

- With Product Owners: manage the backlog and ensure alignment with strategy and KPIs.
- With Developers and QA: clarify behaviour, edge cases, and acceptance criteria.
- With Security and Compliance: translate regulatory obligations into concrete requirements and controls.
- With Ops and Support: understand operational pain points and include them in the backlog.

## 6. Metrics that matter for you

- Lead time from idea to production for key features.
- Percentage of stories with clear acceptance and security criteria.
- Number of production incidents that trace back to unclear or missing requirements.
- Alignment between released features and business outcomes (where measurable).

## 7. Your first 90 days

- Weeks 1–3: Review the current product backlogs and value‑stream maps; identify obvious requirement gaps.
- Weeks 4–8: Standardise story templates to include acceptance and security notes.
- Weeks 9–12: Work with Product and Security to ensure that high‑risk regulatory and data‑protection requirements are fully 
  represented in the backlog and linked to implementation and tests.


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
