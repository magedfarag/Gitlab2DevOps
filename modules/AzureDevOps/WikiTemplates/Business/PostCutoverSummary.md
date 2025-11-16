# Post-Cutover Summary

To be updated after code push:
- Default branch name
- Branch policies applied
- Branches/tags counts

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
