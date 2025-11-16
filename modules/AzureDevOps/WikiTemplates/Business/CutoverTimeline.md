# Cutover & Rollback Plan (Overview)

1) Freeze window → Final verification → Go/No-Go
2) Cutover execution → Validation
3) Rollback path documented (if needed)

---

## 📚 References

- [Release Management Best Practices](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/)
- [Cutover Planning Guide](https://www.pmi.org/)
- [Go-Live Checklist](https://www.atlassian.com/software/jira/guides/release-management/best-practices)
- [Azure Migration Guide](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/migrate/)

### Technical validation examples

- Build pipeline succeeded for the release version in Azure Pipelines.
- All automated tests in the release pipeline are green.
- Monitoring, logging, and alerts are enabled for the new version.
- Rollback steps are tested and documented in the release pipeline.
