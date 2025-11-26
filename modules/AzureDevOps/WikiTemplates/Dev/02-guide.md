# 02. Developers Guide: Working in the Security-First Software Factory

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

As a developer in the software factory, you own the internal quality and security of the code you commit. 
You are no longer “just implementing tickets”. You are responsible for how your code behaves in production, 
how easy it is to observe and debug, and how quickly issues can be fixed.

Concretely, you are expected to:

- Work in trunk‑based Git workflows with small, frequent commits that flow through automated pipelines.
- Design and implement features using secure coding practices aligned with OWASP guidance and internal standards.
- Maintain high levels of automated test coverage for your components (unit, integration, and where appropriate, 
  contract tests).
- Treat SAST, SCA, and DAST findings as part of normal work, not as external “audit tasks”.
- Participate in threat modelling, design discussions, and post‑incident reviews.

## 3. How your day‑to‑day work changes

In the old model, you might have written code in long‑lived branches, handed it to QA, and waited weeks for a 
deployment window approved by a CAB. In the software factory:

- Pipelines run on every commit to the main or integration branch.
- Builds, tests, and security scans are automated using Azure DevOps pipelines and OpenText Fortify integrated with 
  the existing security stack.
- You see feedback from tests and security tools within minutes, not days.
- Deployments follow standardised, versioned release pipelines, so you can focus on code instead of writing ad‑hoc 
  deployment scripts.

You still work with QA, Ops, and Security, but the interaction moves from tickets and escalations to shared pipelines, 
common dashboards, and joint design reviews.

## 4. Practices to adopt

1. **Commit small, testable changes.** Aim for changes that can be understood, reviewed, and rolled back easily. 
   This aligns with DORA’s finding that small batch sizes improve lead time and stability.
2. **Use trunk‑based development.** Avoid long‑lived feature branches that diverge from main. Use short‑lived branches 
   with fast integration.
3. **Write tests first for risky code paths.** Use automated unit and integration tests to lock in expected behaviour. 
   Ensure tests run in the pipeline and fail fast when behaviour changes.
4. **Make security checks part of your definition of done.** A story is not complete if critical SAST/SCA issues remain 
   unresolved without a documented risk decision.
5. **Instrument your code.** Emit structured, correlation‑friendly logs and metrics so incidents can be diagnosed quickly.
6. **Treat build and pipeline failures as first‑class defects.** Broken pipelines are production issues for the factory.

## 5. How you collaborate with other teams

- With QA: co‑own test strategy, pair on adding automated checks, and use exploratory testing sessions to discover gaps.
- With Platform: give feedback on pipeline templates and request changes via backlog items instead of local scripting.
- With Security and SOC: agree on secure coding guidelines, understand common attack patterns, and review real incidents.
- With Ops and Support: ensure you provide clear runbooks, feature flags, and diagnostics to reduce mean time to restore.

## 6. Metrics that matter for you

- Lead time from code commit to production for your services.
- Deployment frequency for your product.
- Change failure rate related to your changes.
- Number and age of open critical and high‑severity vulnerabilities in your code base.
- Automated test coverage and production defect leakage.

These metrics are not for blame. They help you see whether your engineering practices are improving outcomes for 
customers and for the organisation.

## 7. Your first 90 days

- Weeks 1–3: Learn the standard Git branching strategy, pipeline templates, and coding standards. 
  Clean up obvious technical debt and security issues in your area.
- Weeks 4–8: Increase automated test coverage, especially around critical flows. Integrate security findings into 
  your regular backlog.
- Weeks 9–12: Participate in a threat modelling session, contribute to improving a pipeline template, and help the team 
  improve one key DORA metric (for example, reduce lead time by simplifying the deployment process).


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
