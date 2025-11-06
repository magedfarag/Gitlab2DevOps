# Azure DevOps Best Practices & Team Productivity Guide

This guide provides comprehensive best practices for using Azure DevOps effectively and maximizing team productivity.

---

## 📋 Work Item Management

### Creating Quality Work Items

#### ✅ DO
- **Write clear titles**: Use action verbs (Add, Fix, Update, Remove)
  - ✅ Good: "Add user authentication API endpoint"
  - ❌ Bad: "Auth stuff"
  
- **Include acceptance criteria**: Define what "done" means
  - Use checklists for clarity
  - Make criteria measurable and testable
  
- **Add relevant tags**: 3-5 tags maximum
  - Use predefined tags (see [Tag Guidelines](/Tag-Guidelines))
  - Example: \``backend, api, needs-review\``
  
- **Link related items**: 
  - Parent-child for hierarchy (Epic → Feature → User Story → Task)
  - Related for dependencies
  - Tested By for test cases
  
- **Estimate work**: Use story points or hours consistently
  - 1 point = ~2-4 hours ideal
  - Break down anything >8 points

#### ❌ DON'T
- Create work items without descriptions
- Skip acceptance criteria on User Stories
- Over-assign (1-2 work items per person max)
- Leave work items unassigned for >24 hours

### Work Item States

**Optimize your workflow**:

1. **New** → Ready for planning
2. **Active** → Currently being worked (limit WIP!)
3. **Resolved** → Ready for review/testing
4. **Closed** → Fully complete

**Rule**: Max 2-3 Active items per person (Work-In-Progress limit)

---

## 🏃 Sprint Planning Best Practices

### Before Sprint Planning

✅ **Preparation (48 hours before)**:
- Groom backlog (refine top 20 items)
- Ensure User Stories have acceptance criteria
- Split large items (>8 points)
- Remove blockers from top items

### During Sprint Planning

**1. Review Velocity** (15 minutes)
- Check last 3 sprints average
- Adjust for team capacity changes (vacations, holidays)
- Plan 80% of capacity (leave buffer)

**2. Commit to Work** (30 minutes)
- Pull from top of refined backlog
- Verify acceptance criteria clarity
- Assign owners (no unassigned items)
- Break User Stories into Tasks

**3. Set Sprint Goal** (15 minutes)
- One clear sentence defining success
- Shared by entire team
- Example: "Complete user authentication and enable login"

### Sprint Commitment Formula

````````````
Commitment = (Average Velocity × 0.8) + Buffer for bugs/tech debt
````````````

**Example**:
- Last 3 sprints: 25, 28, 24 points = 25.67 avg
- Capacity: 25.67 × 0.8 = **~21 points planned work**
- Reserve: ~4 points for unplanned work

---

## 📊 Dashboard Best Practices

### Daily Dashboard Review (5 minutes)

**Morning Standup Routine**:
1. Open **Team Dashboard** (Dashboards → [Team Name] - Overview)
2. Check **Sprint Burndown**: Are we on track?
3. Review **Blocked Items**: What needs unblocking?
4. Scan **Ready for Review**: Any PRs waiting?
5. View **Work Distribution**: Anyone overloaded?

### Key Metrics to Watch

| Metric | Healthy | Warning | Action Needed |
|--------|---------|---------|---------------|
| **Sprint Burndown** | On/ahead of trend | Slightly behind | Significantly behind - adjust scope |
| **Blocked Items** | 0-1 | 2-3 | 4+ - escalate blockers |
| **Ready for Review** | 0-2 | 3-5 | 6+ - prioritize code reviews |
| **Active Bugs** | 0-5 | 6-15 | 16+ - bug bash needed |

### Dashboard KPIs

**Velocity Stability**: ±20% variance acceptable
- 25 → 23 → 28 = **Stable** ✅
- 25 → 15 → 35 = **Unstable** ❌ (investigate)

**Lead Time**: New → Closed average
- Target: <5 days for Stories
- >10 days = bottleneck investigation needed

**Cycle Time**: Active → Closed average
- Target: <3 days
- Measure actual work time (excludes waiting)

---

## 🔀 Branching Strategy

### Recommended: GitHub Flow (Simplified)

````````````
main (protected)
  ↓
feature/add-login ──→ PR ──→ merge to main
feature/fix-bug-123 ──→ PR ──→ merge to main
````````````

### Branch Naming Conventions

**Pattern**: ````<type>/<ticket-number>-<brief-description>````

**Examples**:
- ````feature/123-add-user-authentication````
- ````bugfix/456-fix-login-crash````
- ````hotfix/789-security-patch````
- ````refactor/321-cleanup-api-layer````

### Branch Protection Rules (Applied Automatically)

✅ **Require PR reviews**: Minimum 1 reviewer
✅ **Require linked work items**: Traceability
✅ **Require successful builds**: CI must pass
✅ **No direct commits to main**: Force PR workflow

### Best Practices

- **Branch early**: Create branch as soon as you start work
- **Commit often**: Small, atomic commits with clear messages
- **Pull frequently**: ````git pull origin main```` daily to avoid conflicts
- **Delete after merge**: Keep repository clean

---

## 🔍 Code Review Excellence

### For Authors

**Before Creating PR**:
1. ✅ Self-review code (read your own diff)
2. ✅ Run tests locally (all passing)
3. ✅ Update documentation if needed
4. ✅ Write clear PR description using template
5. ✅ Link work item (required by policy)
6. ✅ Add relevant reviewers (2-3 people max)

**PR Description Template** (created automatically):
- **What**: What changes were made?
- **Why**: Why were these changes needed?
- **Testing**: How was this tested?
- **Checklist**: ☐ Tests added, ☐ Docs updated

### For Reviewers

**Review SLA**: Within 24 hours (4 hours for hotfixes)

**What to Look For**:
1. **Correctness**: Does it work as intended?
2. **Tests**: Are there tests? Do they cover edge cases?
3. **Readability**: Can others understand this code?
4. **Performance**: Any obvious performance issues?
5. **Security**: Any security concerns?

**Feedback Guidelines**:
- 🟢 **Praise good patterns**: "Nice abstraction here!"
- 🟡 **Suggest improvements**: "Consider using X for clarity"
- 🔴 **Block on critical issues**: "Security: SQL injection risk"

**Review Levels**:
- **Approve**: Ready to merge ✅
- **Approve with comments**: Minor suggestions, merge OK
- **Wait for author**: Non-blocking feedback
- **Request changes**: Must fix before merge 🚫

---

## 🏷️ Tagging Strategy

### Essential Tags (Use These)

**Status Tags** (update as work progresses):
- ````blocked```` - External dependency blocking progress
- ````needs-review```` - Code ready for review
- ````needs-testing```` - Requires QA validation
- ````urgent```` - High priority, immediate attention

**Technical Tags** (classify work type):
- ````frontend````, ````backend````, ````database````, ````api````
- ````technical-debt```` - Refactoring needed
- ````breaking-change```` - API/contract changes
- ````performance```` - Optimization work

**See full list**: [Tag Guidelines](/Tag-Guidelines)

### Tagging Rules

✅ **DO**:
- Apply tags during creation
- Update tags as status changes
- Use 3-5 tags per item
- Use shared queries to find tagged items

❌ **DON'T**:
- Create custom tags without team agreement
- Use spaces (use hyphens: \``needs-review\``)
- Over-tag (>7 tags = noise)

---

## 📈 Queries & Reporting

### Use Shared Queries (Created Automatically)

Navigate to: **Boards → Queries → Shared Queries**

1. **My Active Work**
   - Your currently assigned work items
   - Use daily to see personal workload

2. **Team Backlog - Ready to Work**
   - Refined, unassigned work ready for pickup
   - Use during sprint planning

3. **Active Bugs**
   - All open bugs across project
   - Use for bug triage meetings

4. **Ready for Review**
   - Items awaiting code review
   - Check 2-3 times daily

5. **Blocked Items**
   - Work blocked by dependencies
   - Review in daily standup

### Creating Custom Queries

**Query Editor Tips**:
- Use **WIQL** for complex queries
- Save personal queries under "My Queries"
- Share useful queries with team
- Add to dashboard as query tiles

**Example Query**: High Priority Bugs
````````````
Work Item Type = Bug
AND State <> Closed
AND Priority <= 2
ORDER BY Priority ASC
````````````

---

## 👥 Team Collaboration

### Daily Standup Format (15 minutes max)

**Use Dashboard During Standup**:

1. **Review Sprint Burndown** (2 min)
   - On track? Ahead? Behind?

2. **Check Blocked Items** (3 min)
   - What's blocking progress?
   - Who can help remove blockers?

3. **Quick Round Robin** (10 min per person)
   - What did you complete yesterday?
   - What are you working on today?
   - Any blockers? (already visible on dashboard)

**No storytelling** - keep it factual and brief!

### Sprint Review Checklist

✅ **Prepare Demo** (owner prepares 5 min demo per Story)
✅ **Show Live Features** (not slides/mockups)
✅ **Show Metrics** (velocity chart, sprint burndown)
✅ **Collect Feedback** (create work items for feedback)
✅ **Update Stakeholders** (email summary after meeting)

### Retrospective Best Practices

**Format: Start-Stop-Continue**

1. **Start**: What should we start doing?
2. **Stop**: What should we stop doing?
3. **Continue**: What's working well?

**Create Action Items**:
- Assign owners to action items
- Track in next sprint
- Review at next retro (close the loop)

---

## 📚 Documentation Standards

### Wiki Organization

````````````
/Home
/Getting-Started
  /Development-Setup
  /Deployment-Guide
/Architecture
  /System-Design
  /API-Documentation
/Processes
  /Best-Practices (this page)
  /Tag-Guidelines
  /Release-Process
````````````

### When to Document

**Document When**:
- ✅ Setting up development environment
- ✅ Architectural decisions (ADRs)
- ✅ API contracts and schemas
- ✅ Deployment procedures
- ✅ Troubleshooting common issues

**Don't Document**:
- ❌ Obvious code (use comments instead)
- ❌ Temporary workarounds
- ❌ Personal notes (use work item comments)

### README Best Practices

Every repository needs:
1. **What**: Project description
2. **Why**: Purpose and goals
3. **How**: Setup instructions
4. **Prerequisites**: Required tools/versions
5. **Quick Start**: Get running in <5 minutes
6. **Contributing**: How to contribute

(README template created automatically)

---

## 🚀 Continuous Integration Best Practices

### Build Pipeline Configuration

**Every pipeline should**:
- ✅ Run on every PR (gate quality)
- ✅ Run all tests (unit, integration)
- ✅ Enforce code coverage (70%+ recommended)
- ✅ Run linting/static analysis
- ✅ Fail fast (don't waste CI time)
- ✅ Complete in <10 minutes

### Test Pyramid

````````````
       /\\
      /  \\  E2E Tests (5%)
     /----\\
    / UI Tests (15%)
   /----------\\
  / Integration (30%)
 /----------------\\
/__________________\\
   Unit Tests (50%)
````````````

**Golden Rule**: More unit tests, fewer E2E tests

---

## 🎯 Definition of Ready (DoR)

**Before moving User Story to sprint**:

- [ ] Clear, testable acceptance criteria
- [ ] Estimated (story points assigned)
- [ ] Dependencies identified
- [ ] Designs approved (if applicable)
- [ ] No blockers
- [ ] Team understands requirements

**If not ready** → Keep in backlog for refinement

---

## ✅ Definition of Done (DoD)

**Before closing work item**:

- [ ] Code complete and reviewed
- [ ] Tests written and passing
- [ ] Documentation updated
- [ ] PR merged to main
- [ ] Deployed to test environment
- [ ] Acceptance criteria met
- [ ] No new bugs introduced

**If not done** → Move back to Active or Resolved

---

## 📊 Metrics & KPIs

### Team Health Metrics

| Metric | Target | Formula |
|--------|--------|---------|
| **Velocity Stability** | ±20% | Std deviation of last 6 sprints |
| **Sprint Commitment %** | 85-100% | Points completed / Points committed |
| **Escaped Defects** | <5% | Bugs found in prod / Total stories |
| **PR Cycle Time** | <24 hours | Time from PR creation to merge |
| **Lead Time** | <5 days | New → Closed for User Stories |
| **Code Review Coverage** | 100% | PRs reviewed / Total PRs |

### Individual Metrics (Private)

**For self-improvement only** (not for performance reviews):
- Work items completed per sprint
- PR review turnaround time
- Bug introduction rate
- Code review quality (feedback given)

---

## 🛠️ Tooling & Automation

### Recommended VS Code Extensions

- **Azure Boards** - View work items in VS Code
- **GitLens** - Git superpowers
- **Azure Pipelines** - Monitor builds
- **Prettier/ESLint** - Code formatting

### Automation Opportunities

**Automate These**:
- ✅ Work item state transitions (PR merged → Close work item)
- ✅ Build/test on every commit
- ✅ Deployment to test environment
- ✅ Release notes generation
- ✅ Code quality checks (linting, coverage)

**Don't Automate**:
- ❌ Production deployments (require approval)
- ❌ Database migrations (manual review)
- ❌ Critical security changes

---

## 🎓 Learning Resources

### Azure DevOps Documentation
- [Work Item Guidance](https://learn.microsoft.com/azure-devops/boards/)
- [Git Branching Strategies](https://learn.microsoft.com/azure-devops/repos/git/git-branching-guidance)
- [Pipeline Best Practices](https://learn.microsoft.com/azure-devops/pipelines/library/)

### Agile/Scrum Resources
- Scrum Guide: [scrumguides.org](https://scrumguides.org)
- Agile Manifesto: [agilemanifesto.org](https://agilemanifesto.org)

---

## 📚 References

- [Azure DevOps Best Practices](https://learn.microsoft.com/en-us/azure/devops/best-practices/)
- [Microsoft Engineering Playbook](https://microsoft.github.io/code-with-engineering-playbook/)
- [The Twelve-Factor App](https://12factor.net/)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Clean Code by Robert C. Martin](https://www.oreilly.com/library/view/clean-code-a/9780136083238/)
- [Continuous Delivery by Jez Humble](https://continuousdelivery.com/)

---

## 🆘 Getting Help

**Stuck? Try These**:
1. 🔍 Search this wiki
2. 💬 Ask in team chat
3. 📋 Check [Tag Guidelines](/Tag-Guidelines)
4. 📊 Review dashboard metrics
5. 👥 Pair with teammate

**Remember**: No question is too small!

---

## 🔄 Continuous Improvement

**This document is living**:
- Review quarterly
- Update based on retrospective action items
- Add team-specific practices
- Remove outdated guidance

**Suggest Changes**:
- Create work item tagged \``documentation\``
- Propose changes in retrospectives
- Edit this wiki page directly (with team agreement)

---

*Last Updated: $(Get-Date -Format 'yyyy-MM-dd')*

*This page is maintained by the team. Questions? Create a work item tagged 'documentation'.*