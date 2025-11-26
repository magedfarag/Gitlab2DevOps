# 10. KPIs & Success Criteria

**Scope.** These KPIs describe how we measure software delivery on Azure DevOps Boards and Pipelines.

- Enablement: % trained, active users
- Flow: Lead time, Cycle time (baseline then trend)
- Quality: Bugs by severity trend
- Migration readiness: Preflight checks passed, SSL/TLS status

---

## 📚 References

- [Azure DevOps Analytics](https://learn.microsoft.com/en-us/azure/devops/report/dashboards/analytics-extension)
- [DORA Metrics](https://cloud.google.com/blog/products/devops-sre/using-the-four-keys-to-measure-your-devops-performance)
- [OKRs (Objectives and Key Results)](https://www.whatmatters.com/faqs/okr-meaning-definition-example)
- [Agile Metrics Guide](https://www.atlassian.com/agile/project-management/metrics)

### DORA mapping

- **Deployment frequency** – how often we complete successful releases through Azure Pipelines.
- **Lead time for changes** – time from code commit or work item start until the change is running in production.
- **Change failure rate** – percentage of releases that cause incidents or require hotfixes.
- **Mean time to recover (MTTR)** – time from incident detection until service returns to normal.

Use these definitions when you design dashboards and alerts.
