# 12. Communication Templates

**Context.** Use these templates when you communicate software releases, platform changes, and Azure DevOps cutovers. You can reuse the examples by editing project-specific details.

---

## Release / Cutover Announcement Email

**Purpose.** Inform stakeholders about the upcoming cutover, what changes, when it happens, and where to find more information.

**Subject:** Order Processing – Cutover to Azure DevOps on 2025-12-01

**Body:**

Dear colleagues,

On **2025-12-01**, we will cut over the **Order Processing** development work from **GitLab** to **Azure DevOps Server**.

**What is changing**

- Source control will move to Azure Repos.
- Work tracking will move to Azure Boards (stories, bugs, tasks).
- CI/CD pipelines will run in Azure Pipelines.

**When**

- Freeze window: **2025-11-30 18:00** to **2025-12-01 06:00** (local time).
- Expected completion: **2025-12-01 08:00**.
- During the freeze, do not create new branches or merge requests in GitLab.

**What you need to do**

- Review the quick start guide on the wiki.
- Log in to the new project: https://ado.example.com/tfs/DefaultCollection/SoftwareFactory/_home.
- Report any issues in the **#ado-support** channel or by opening a support ticket.

If you have questions, contact **the cutover lead** or ask in **#ado-support**.

Best regards,  
The Azure DevOps migration team

---

## Freeze Window Notice

**Purpose.** Confirm the exact freeze window and allowed exceptions.

**Subject:** Order Processing – Change Freeze Window for Cutover on 2025-12-01

**Body:**

Dear colleagues,

To support a safe cutover for the **Order Processing** platform, a **change freeze** will be in place:

- **Start:** 2025-11-30 18:00 (local time)
- **End:** 2025-12-01 06:00 (local time)

**Scope**

- No production deployments unless they are pre-approved critical fixes.
- No changes to Git repositories that are in scope for the migration.
- No changes to build or release definitions without cutover lead approval.

**Exceptions**

- Security or availability incidents.
- Regulator-mandated changes.

Exception requests must be approved by the cutover lead and the change manager before execution.

Thank you for your support in keeping the cutover stable.

Best regards,  
The Azure DevOps migration team

---

## Go/No-Go Meeting Invite and Checklist

**Purpose.** Provide a clear structure for the go/no-go decision.

**Subject:** Order Processing – Go/No-Go Review for Cutover on 2025-12-01

**Body:**

Attendees: sponsor, product owner, cutover lead, operations, security, support.

**Agenda (30–45 minutes)**

1. Status of technical readiness (builds, tests, monitoring).
2. Status of business readiness (training, communications).
3. Open risks and issues.
4. Recommended decision: Go or No-Go.

**Checklist (example)**

- ✅ Latest build passed in Azure Pipelines for the release version.
- ✅ Automated test suite is green and reviewed.
- ✅ Monitoring and alerting configured for the new environment.
- ✅ Rollback steps documented and tested.
- ✅ Support team briefed and on-call schedule confirmed.
- ✅ Key risks reviewed and accepted by the sponsor.

Decisions and rationale should be recorded in the **Decision Log** and, when appropriate, an Architecture Decision Record (ADR).

---

## Post-Cutover Survey

**Purpose.** Collect feedback about the cutover and early use of Azure DevOps.

You can send this as a short form (3–5 questions).

**Subject:** Order Processing – Post-Cutover Feedback (2 minutes)

**Questions (example)**

1. How clear was the communication before and during cutover?
   - 1 (very unclear) to 5 (very clear)
2. How well did the new Azure DevOps project meet your expectations in the first week?
   - 1 (very poor) to 5 (excellent)
3. What worked well during the cutover?
   - Free text
4. What should we improve for the next cutover?
   - Free text
5. Would you recommend this cutover approach for future projects?
   - Yes/No + comments

Summarize results in the retrospective or lessons-learned session and capture improvement actions in your backlog.

---

## 📚 References

- [Effective Communication in Agile](https://www.agilealliance.org/glossary/information-radiator)
- [Stakeholder Communication Best Practices](https://www.pmi.org/learning/library/effective-stakeholder-communication-8507)
- [Sprint Review Tips](https://www.scrum.org/resources/what-is-a-sprint-review)
- [Status Report Templates](https://www.projectmanagementdocs.com/template-categories/project-reporting.html)
