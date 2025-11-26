# 03. Ways of Working

## Definition of Ready (DoR)
- Clear user value
- Acceptance criteria present
- Dependencies identified

## Definition of Done (DoD)
- Code reviewed, tests passing, docs updated, accepted by PO

---

## 📚 References

- [Scrum Guide](https://scrumguides.org/)
- [Kanban Guide](https://kanban.university/)
- [Team Working Agreement Templates](https://www.atlassian.com/team-playbook/plays/working-agreements)
- [Azure DevOps Team Settings](https://learn.microsoft.com/en-us/azure/devops/organizations/settings/about-teams-and-settings)

### Notes on Definition of Ready

Definition of Ready (DoR) is not part of the official Scrum Guide. Many software teams use it as a local working agreement to improve backlog quality.

### Software-focused examples in Definition of Done

When you define "Done" for a backlog item, include concrete engineering checks such as:

- All automated tests in CI are green (unit, integration, and critical end-to-end tests).
- Static analysis, security scans, and license checks have passed for the change.
- Logging, metrics, and feature flags for the change are in place and verified.
- Documentation that developers or operators rely on is updated in the same repository.

These examples keep the Definition of Done anchored in real software delivery work.
