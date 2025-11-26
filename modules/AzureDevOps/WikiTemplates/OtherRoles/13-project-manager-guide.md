# 13. Project and Delivery Managers Guide: Working in the Security-First Software Factory

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

As a project or delivery manager, you focus on orchestrating delivery across teams and dependencies, while respecting 
the product‑centric, continuous delivery model. You still care about scope, schedule, and budget, but success is 
measured by regular, valuable deliveries and stable services rather than by hitting a single big go‑live date.

You are expected to:

- Plan work around value streams and product roadmaps, not just projects.
- Use incremental milestones tied to working software and measurable outcomes.
- Make constraints and risks visible, especially around security, compliance, and environments.
- Coordinate with Platform, Security, and Ops to avoid bottlenecks and resource conflicts.
- Help teams interpret and act on DORA and quality metrics.

## 3. How your day‑to‑day work changes

Instead of managing large Gantt charts and long change windows, you now:

- Facilitate planning and review events across squads and platforms.
- Track progress using flow‑based metrics (cycle time, throughput, WIP) and outcome metrics, not just task completion.
- Support teams in unblocking dependencies quickly.
- Communicate status in terms of delivered capabilities, risk reduction, and operational impact.

## 4. Practices to adopt

1. **Move from “push” to “pull”.** Encourage teams to pull work based on capacity and WIP limits rather than overloading them.
2. **Use evidence‑based forecasting.** Use historical flow metrics instead of optimistic estimates.
3. **Integrate security and compliance into plans.** Treat security activities as first‑class work items, not as last‑minute add‑ons.
4. **Simplify change processes.** Work with Security to move toward pre‑approved standard changes based on pipeline evidence.
5. **Protect teams from unnecessary noise.** Shield delivery teams from conflicting priorities and non‑essential reporting.

## 5. How you collaborate with other teams

- With Product and BA: align delivery plans with product goals and backlog priorities.
- With Platform: plan onboarding, migrations, and capacity upgrades.
- With Security: coordinate risk assessments and change approvals.
- With Management: communicate realistic expectations and trade‑offs based on data.

## 6. Metrics that matter for you

- Lead time for key deliverables.
- Throughput and flow efficiency across teams.
- Rate of scope changes and their impact.
- Number of blocked work items and average time blocked.
- Predictability of delivery against outcome‑based milestones.

## 7. Your first 90 days

- Weeks 1–3: Map current projects to products and value streams; identify major bottlenecks.
- Weeks 4–8: Introduce flow‑based tracking and align reporting with DORA and quality metrics.
- Weeks 9–12: Partner with Security to streamline standard changes supported by pipeline evidence.


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
