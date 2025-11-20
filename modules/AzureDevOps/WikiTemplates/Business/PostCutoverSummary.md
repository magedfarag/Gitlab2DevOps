# Post-Cutover Summary

Use this page to document the state of the project after the cutover and the first weeks of running on Azure DevOps Server. Capture facts that will help future migrations and audits.

## Repository and branch status

Record:

- The default branch name in Azure Repos (for example, `main`).
- Branch policies configured on the default branch (required reviewers, build validation, status checks).
- Approximate counts of active branches and tags after clean-up.

## Operational observations

Summarize:

- Any incidents or near misses related to the cutover.
- Performance or stability changes observed after the switch.
- Feedback from development, operations, and business stakeholders.

---

## 📚 References

- [Project Closure Best Practices](https://www.pmi.org/learning/library/closing-project-lessons-learned-5892)
- [Retrospective Techniques](https://www.atlassian.com/team-playbook/plays/retrospective)
- [Lessons Learned Templates](https://www.projectmanagementdocs.com/template-categories/lessons-learned.html)
- [Azure DevOps Retrospectives](https://marketplace.visualstudio.com/items?itemName=ms-devlabs.team-retrospectives)

### Software quality gates to capture

- Default branch protection and pull request policies, including required reviewers and build validation.
- Required status checks in Azure Pipelines for the main branch.
- Any security scanning or compliance checks that must pass before release.

### Post-cutover performance signals

During the first weeks after cutover, watch the DORA metrics on your dashboards:

- Deployment frequency.
- Lead time for changes.
- Change failure rate.
- Mean time to recover (MTTR).

Adjust the process if these metrics regress.
