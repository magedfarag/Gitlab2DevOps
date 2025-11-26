# 01. Cybersecurity and Application Security Guide: Working in the Security-First Software Factory

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

As part of Cybersecurity or Application Security, you set the security standards for the factory and ensure that 
security risks are identified, prioritised, and managed in a way that supports fast, reliable delivery.

You are expected to:

- Define secure development policies aligned with NIST SSDF and OWASP SAMM.
- Own and configure security tools (SAST, SCA, DAST, secrets management) integrated into the pipelines.
- Run threat modelling and security design reviews for high‑risk systems.
- Define risk acceptance processes and criteria.
- Provide guidance and training to security champions and development teams.

## 3. How your day‑to‑day work changes

Instead of primarily doing manual reviews and late‑stage penetration tests, you now:

- Design controls as code and integrate them into the factory.
- Focus on building scalable patterns and guardrails rather than case‑by‑case exceptions.
- Use vulnerability and incident data to prioritise improvements.
- Work closely with SOC, and Ops to ensure end‑to‑end coverage from code to production.

## 4. Practices to adopt

1. **Security by default.** Encode baseline controls in templates and reference architectures.
2. **Risk‑based gates.** Use severity thresholds, SLAs, and contextual information rather than blocking all issues.
3. **Security champions network.** Build and support champions in each team to multiply your impact.
4. **Continuous education.** Provide regular, role‑based training and share lessons from real incidents.
5. **Evidence‑driven decisions.** Use data from tools and incidents to focus on the highest‑impact risks.

## 5. How you collaborate with other teams

- With Platform: design and maintain security stages in pipelines.
- With Dev and QA: help interpret findings and design secure solutions.
- With SOC and Ops: ensure detection use‑cases and incident playbooks are aligned with application behaviour.
- With Management: present security posture and negotiate risk treatment options.

## 6. Metrics that matter for you

- Number and age of open vulnerabilities by severity.
- Time to remediate critical and high issues.
- Coverage of threat modelling, security testing, and security training.
- Percentage of systems using standard security patterns and pipelines.

## 7. Your first 90 days

- Weeks 1–3: Map existing tools and practices against NIST SSDF and OWASP SAMM.
- Weeks 4–8: Define initial security policies and thresholds in the factory pipelines.
- Weeks 9–12: Establish the first wave of security champions and run targeted training.


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
