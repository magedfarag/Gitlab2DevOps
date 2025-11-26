# 01. QA and Test Engineers Guide: Working in the Security-First Software Factory

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

As a QA or test engineer, your focus shifts from gatekeeping at the end of the cycle to building quality in from 
the start. You are responsible for the test strategy, the quality of automated tests, and the effectiveness of 
exploratory testing in the context of fast, frequent releases.

You are expected to:

- Collaborate with developers and product owners to define clear acceptance criteria and testable behaviour.
- Design and maintain automated tests that run reliably in CI pipelines (unit, API, UI, and performance tests where needed).
- Use risk‑based thinking to decide what must be automated and what should be explored manually.
- Integrate security and negative testing patterns based on OWASP guidance.
- Use observability data to refine tests and detect regressions earlier.

## 3. How your day‑to‑day work changes

Instead of long manual test cycles before big releases, you now:

- Contribute test cases as code that run on every change.
- Pair with developers on test design and data management.
- Use shared, production‑like test environments provisioned via infrastructure‑as‑code.
- Focus manual effort on exploratory testing of new risk areas.
- Help define quality gates in pipelines (for example, minimum test coverage and no critical test failures).

## 4. Practices to adopt

1. **Shift testing left.** Participate in story refinement and design sessions and clarify how we will test each change.
2. **Automate regression, explore the unknown.** Use automation to cover stable flows; use exploratory sessions on new, 
   complex, or high‑risk areas.
3. **Use test data responsibly.** Work with Platform and Security to manage synthetic or anonymised data in non‑production 
   environments.
4. **Include non‑functional tests.** Where appropriate, add performance, reliability, and resilience checks into the pipeline.
5. **Use metrics.** Track defect leakage, flaky tests, and coverage trends; use them to prioritise improvements.

## 5. How you collaborate with other teams

- With Developers: define acceptance criteria, pairing on tests, and triaging failures quickly.
- With Platform: influence test stages in pipeline templates and request stable, reproducible environments.
- With Security: include security abuse cases and regression tests based on past vulnerabilities.
- With Ops and Support: review production incidents and turn them into new test cases.

## 6. Metrics that matter for you

- Defect leakage to production.
- Percentage of tests automated by layer (unit, API, UI).
- Test flakiness rate.
- Time from defect discovery to fix in production.
- Coverage of critical user journeys by automated tests.

## 7. Your first 90 days

- Weeks 1–3: Map existing test assets and stabilise critical automated tests in the new pipelines.
- Weeks 4–8: Increase automation coverage for core journeys and add tests for recent high‑impact defects.
- Weeks 9–12: Introduce a regular exploratory testing cadence and partner with Security on adding abuse‑case tests.


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
