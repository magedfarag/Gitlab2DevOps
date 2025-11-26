# 03. Developers – Practical Playbook

## 1. What this playbook gives you

This playbook explains how developers can work day to day inside our on-prem, security-first software factory.
It focuses on concrete actions, collaboration points, and anti-patterns to avoid. The model assumes Azure DevOps Server
for source control, planning, and pipelines, OpenText Fortify for SAST/DAST/SCA, and reuse of the existing security and
monitoring stack.

You can read it end to end once, then keep it nearby as a reference when you plan work, join ceremonies, or handle
incidents.

## 2. Typical concerns for your role

In the factory, the questions that usually matter most for you are:

- Quality and security of code that flows through Azure DevOps Server pipelines.
- Speed of feedback from unit tests, SAST and SCA scans, and code review.
- Ability to diagnose issues quickly in lower and production environments.

These concerns are normal. The goal is to address them with standard ways of working rather than one-off workarounds.

## 3. Your daily workflow in the software factory

A typical day in the factory should look more like a steady flow of small, well-shaped changes than a long wait
followed by a stressful release. A realistic sequence for you might be:

1. **Start of day – orient.** Look at your team board in Azure DevOps Server. Confirm priorities with the product owner
   and check pipeline health for the services you care about.
2. **Mid-morning – deep work.** Focus on the work items planned for the current sprint. Keep batch sizes small so that
   pipeline feedback is fast and risk stays low.
3. **Before lunch – peer collaboration.** Join or schedule short working sessions with the people you depend on most
   (for example, developers and QA, QA and platform, security and architects). Use these sessions to clarify designs,
   tests, and acceptance criteria rather than exchanging long documents.
4. **Afternoon – respond to feedback.** Review pipeline runs, Fortify findings, and any incidents or support tickets
   that involve your area. Turn important signals into backlog items, not side conversations.
5. **End of day – tidy up.** Make sure work in progress is visible and documented. Avoid hiding unfinished work in
   private notes or local machines; use the shared tools.

This pattern looks slightly different for each role, but the core principles stay the same: small batches, clear flow,
and fast feedback that you act on deliberately.

## 4. Key artefacts you touch or own

In this model, tools are not optional. They carry evidence for audits, support collaboration across teams, and reduce
hand-offs. For your role, the main artefacts you either create or maintain are:

- Feature branches or trunk commits
- Pull requests and code reviews
- Automated test suites
- Pipeline run reports
- Application logs and metrics dashboards

When these artefacts live in Azure DevOps Server repos, Boards, Wikis, and integrated tools, they become part of the
permanent record we can show to auditors, regulators, and internal risk committees.

## 5. Collaboration and hand-off rules of thumb

To avoid confusion and rework, use the following rules in day-to-day work:

- **Make work visible.** If a conversation changes scope, decisions, or risk, capture the outcome on the team board or
  in a short note in the appropriate wiki space.
- **Agree on entry and exit criteria.** For any major activity (design review, test cycle, security review, change
  approval), agree in advance what “ready” and “done” mean and how the factory tools will show this.
- **Prefer working sessions to long email threads.** Use short, focused calls or whiteboarding sessions, then record the
  outcome in a durable place.
- **Document decisions once.** Architecture decisions, security decisions, and change approvals should have a single
  source of truth that links to code, tests, and pipeline runs.

If you are not sure where to record something, ask your product owner or platform engineer. Do not keep critical
decisions only in chat applications.

## 6. Anti-patterns to avoid

Across organisations that moved to DevSecOps, the same failure modes repeat. For your role, the most harmful patterns
usually include some of these:

- Treating the software factory as “extra admin work” rather than the main path to production.
- Bypassing standard pipelines with manual scripts or side channels when deadlines get tight.
- Ignoring security or quality findings because “the tool is noisy” instead of working with Security and Platform to
  tune rules and thresholds.
- Recreating local spreadsheets, documents, or tracking systems that duplicate data from Azure DevOps or the CMDB.
- Letting work items grow huge and vague, then discovering late that they hide big risks or unknown dependencies.

If you catch yourself or your team falling into any of these habits, raise it early. Most of the time there is already
a better pattern defined in the factory, or we can agree on one together.

## 7. Example scenario: contributing to a safe, fast release

Imagine your team needs to deliver a meaningful change within two weeks. In the factory, a good pattern looks like this:

1. **Shape the work.** Split the change into small slices that each add value and can move through analysis, build,
   test, and deployment independently.
2. **Align on risks.** Identify where the change might affect security, reliability, or regulatory obligations. Bring in
   Security or Architecture early if needed.
3. **Use the platform as designed.** Rely on the standard pipeline templates, environment promotions, and Fortify
   integration. If they are missing a capability you need, raise a platform request instead of forking the pipeline.
4. **Watch the data.** Track DORA-style metrics for your product and use them to decide when to cut scope or invest in
   hardening instead of adding more features.
5. **Close the loop.** After the release, review incidents, support tickets, and user feedback. Turn what you learn into
   backlog items or updates to patterns and templates.

This is the same story our regulators expect to hear, backed by concrete evidence in tools and logs.

## 8. Personal checklist for this role

You can use this list in one-to-ones, retrospectives, or performance reviews. Adapt it to your reality, but keep it
short and brutal:

- Do I know which DORA and security metrics matter most for the products I touch?
- Do I make my work and decisions visible where others can find them?
- Do I understand how security controls (SSDF and OWASP) show up in our pipelines and environments?
- Have I built at least one habit in the last quarter that removes manual work or duplicated effort?
- When there is an incident or major change, do I know exactly what my contribution should be?

Review this checklist every month. Pick one item to improve and make the change explicit with your team.


## References and further reading

- NIST Secure Software Development Framework (SSDF) v1.1: https://doi.org/10.6028/NIST.SP.800-218
- NIST SSDF project overview: https://csrc.nist.gov/projects/ssdf
- OWASP Software Assurance Maturity Model (SAMM): https://owaspsamm.org
- OWASP DevSecOps Maturity Model (DSOMM): https://owasp.org/www-project-devsecops-maturity-model/
- OWASP DevSecOps guideline: https://devsecops.owasp.org/
- DORA four key metrics overview: https://waydev.co/dora-metrics/
- Thoughtworks summary of Accelerate and DORA metrics: 
  https://www.thoughtworks.com/insights/articles/improving-your-bottom-line-with-four-key-metrics
- U.S. DoD DevSecOps Enterprise Reference Design (software factory example): 
  https://dodcio.defense.gov/Library/ (look for DevSecOps Reference Design)
- DoD Platform One software factory information: https://p1.dso.mil

