# Team Productivity Features Guide

## Overview

This guide documents all the **team productivity features** automatically configured during project initialization. These features are designed to help teams hit the ground running with best practices already in place.

## ✨ What's Configured Automatically

When you initialize a new Azure DevOps project (Option 2 in the menu), the migration tool automatically sets up:

1. ✅ **Sprint Iterations** - 6 upcoming 2-week sprints
2. ✅ **Work Item Templates** - 6 comprehensive templates with DoR/DoD
3. ✅ **Shared Queries** - 5 essential queries for common scenarios
4. ✅ **Team Settings** - Backlog levels, working days, default iteration
5. ✅ **Tag Guidelines** - Documented tag taxonomy in wiki
6. ✅ **Repository Templates** - README.md and PR template
7. ✅ **Areas** - Frontend, Backend, Infrastructure, Documentation
8. ✅ **Wiki** - Welcome page and guidelines

---

## 📅 Sprint Iterations

### What's Created

- **6 sprints** starting from the next Monday
- **2-week duration** (14 days) for each sprint
- Automatically assigned to the default team
- Proper start/finish dates configured

### Sprint Schedule Example

```
Sprint 1: Nov 11, 2025 - Nov 24, 2025
Sprint 2: Nov 25, 2025 - Dec 08, 2025
Sprint 3: Dec 09, 2025 - Dec 22, 2025
Sprint 4: Dec 23, 2025 - Jan 05, 2026
Sprint 5: Jan 06, 2026 - Jan 19, 2026
Sprint 6: Jan 20, 2026 - Feb 02, 2026
```

### How to Use

1. **View Sprints**: Boards → Sprints
2. **Plan Work**: Drag work items to sprint backlog
3. **Track Progress**: Use sprint burndown charts
4. **Sprint Ceremonies**: Use for planning, review, retrospective

### Customization

To modify sprint settings:
- **Duration**: Use `Ensure-AdoIterations -SprintDurationDays 10` for 10-day sprints
- **Count**: Use `Ensure-AdoIterations -SprintCount 8` for 8 sprints
- **Start Date**: Use `Ensure-AdoIterations -StartDate (Get-Date "2025-12-01")`

---

## 📊 Shared Work Item Queries

### Available Queries

All queries are located in **Shared Queries** folder:

#### 1. **My Active Work**
Shows all work items assigned to you that aren't closed.

**Use Case**: Daily standup, personal task tracking

**WIQL**:
```
[System.AssignedTo] = @Me 
AND [System.State] <> 'Closed' 
AND [System.State] <> 'Removed'
ORDER BY [System.ChangedDate] DESC
```

#### 2. **Team Backlog**
Shows all active work items ordered by priority.

**Use Case**: Sprint planning, backlog refinement

**WIQL**:
```
[System.State] <> 'Closed' 
AND [System.State] <> 'Removed'
ORDER BY [Microsoft.VSTS.Common.Priority] ASC
```

#### 3. **Active Bugs**
Shows all open bugs ordered by severity and priority.

**Use Case**: Bug triage, QA dashboard

**WIQL**:
```
[System.WorkItemType] = 'Bug'
AND [System.State] <> 'Closed'
ORDER BY [Microsoft.VSTS.Common.Severity] ASC
```

#### 4. **Ready for Review**
Shows items marked as ready for review or containing 'needs-review' tag.

**Use Case**: Code review dashboard, PR tracking

**WIQL**:
```
[System.State] = 'Ready for Review'
OR [System.State] = 'Resolved'
OR [System.Tags] CONTAINS 'needs-review'
ORDER BY [System.ChangedDate] DESC
```

#### 5. **Blocked Items**
Shows work items tagged with 'blocked' or 'impediment'.

**Use Case**: Impediment tracking, daily standups

**WIQL**:
```
[System.Tags] CONTAINS 'blocked'
OR [System.Tags] CONTAINS 'impediment'
AND [System.State] <> 'Closed'
ORDER BY [System.CreatedDate] DESC
```

### How to Use Queries

1. **Navigate**: Boards → Queries → Shared Queries
2. **Run Query**: Click query name to view results
3. **Save to Favorites**: Star icon to add to favorites
4. **Create Charts**: Right-click → "Create chart" for visualizations
5. **Pin to Dashboard**: Add query results to team dashboard

---

## 📝 Work Item Templates

Comprehensive templates for all work item types with HTML formatting, DoR/DoD checklists, and team standards.

### Templates Created

1. **User Story – DoR/DoD** - With acceptance criteria, DoR, DoD
2. **Task – Implementation** - Implementation checklist, dependencies
3. **Bug – Triaging & Resolution** - Repro steps, environment, triage info
4. **Epic – Strategic Initiative** - Business objectives, metrics, timeline
5. **Feature – Product Capability** - Requirements, success criteria
6. **Test Case – Quality Validation** - Test steps, validation criteria

### Automatic Configuration

✅ Templates are **automatically set as team defaults** - no manual configuration needed!

When you create a new work item, the template fields automatically populate.

**See**: [Work Item Templates Guide](../WORK_ITEM_TEMPLATES.md) for detailed usage.

---

## ⚙️ Team Settings

### Configured Settings

#### 1. **Backlog Visibility**
- ✅ Epics visible
- ✅ Features visible  
- ✅ User Stories / PBIs visible
- ✅ Tasks visible
- ✅ **Bugs shown on backlog** (treated as requirements)

**Benefit**: Complete hierarchy visibility from strategy to execution.

#### 2. **Working Days**
- Monday through Friday
- Weekends excluded from sprint capacity calculations

**Benefit**: Accurate burndown charts and capacity planning.

#### 3. **Default Iteration**
- Set to the first upcoming sprint
- New work items automatically assigned to current sprint

**Benefit**: Reduces manual sprint assignment.

### How to View/Modify

1. Navigate to: **Project Settings** (bottom-left gear icon)
2. Select: **Boards** → **Team configuration**
3. Choose your team
4. Review **Backlog levels** and **Working days** tabs

---

## 🏷️ Tag Guidelines

### What's Created

A comprehensive **Tag Guidelines** wiki page documenting all recommended tags.

**Location**: Wiki → Tag-Guidelines

### Tag Categories

#### Status & Workflow
- `blocked` - Work is blocked
- `urgent` - Needs immediate attention
- `breaking-change` - Breaking changes
- `needs-review` - Ready for review
- `needs-testing` - Needs QA validation
- `needs-documentation` - Documentation needed

#### Technical Areas
- `frontend` - UI/UX work
- `backend` - Server-side logic
- `database` - Database changes
- `api` - API changes
- `infrastructure` - DevOps/deployment

#### Quality & Debt
- `technical-debt` - Code needing refactoring
- `performance` - Performance optimization
- `security` - Security-related
- `accessibility` - Accessibility improvements

### Usage Best Practices

✅ **DO**:
- Use lowercase with hyphens
- Apply 3-5 tags per work item
- Use tags in queries for filtering
- Update tags as work progresses

❌ **DON'T**:
- Create ad-hoc tags without discussion
- Mix capitalization styles
- Use spaces in tag names

### Tag-Based Queries

The shared queries already use tags:
- **Ready for Review**: Uses `needs-review` tag
- **Blocked Items**: Uses `blocked` tag

---

## 📚 Repository Templates

### Files Created (After First Commit)

#### 1. **README.md**
Starter README with sections for:
- Project overview
- Getting started (prerequisites, installation, running)
- Development workflow
- Project structure
- Contributing guidelines

**Location**: Repository root

#### 2. **Pull Request Template**
Standard PR description template with:
- Description section
- Related work items linking
- Type of change checklist
- Testing done checklist
- Code review checklist

**Location**: `.azuredevops/pull_request_template.md`

### How Templates Work

**README.md**: Visible on repository homepage, helps with onboarding

**PR Template**: Automatically populates when creating a pull request, ensures consistency

### When They're Added

- ✅ If repository has commits: Added immediately
- ⏳ If repository is empty: Added after first code push (Option 6 - Bulk Migration)

---

## 🎯 Complete Feature Summary

| Feature | Auto-Configured | Manual Config Needed | Benefit |
|---------|----------------|---------------------|---------|
| Sprint Iterations | ✅ Yes (6 sprints) | ❌ No | Immediate sprint planning |
| Work Item Templates | ✅ Yes (6 templates) | ❌ No | Consistent work items |
| Shared Queries | ✅ Yes (5 queries) | ❌ No | Quick access to common views |
| Team Settings | ✅ Yes (backlog, days) | ❌ No | Optimized workflow |
| Tag Guidelines | ✅ Yes (wiki page) | ❌ No | Consistent tagging |
| Repository Templates | ✅ Yes (after push) | ❌ No | Professional onboarding |
| Areas | ✅ Yes (4 areas) | ❌ No | Work organization |
| Wiki | ✅ Yes (welcome + tags) | ❌ No | Documentation hub |

---

## 🚀 Getting Started Checklist

After project initialization:

### For Project Administrators
- [ ] Review sprint schedule (Boards → Sprints)
- [ ] Verify shared queries (Boards → Queries → Shared Queries)
- [ ] Check team settings (Project Settings → Team configuration)
- [ ] Review tag guidelines (Wiki → Tag-Guidelines)
- [ ] Customize README.md if needed
- [ ] Invite team members and assign to groups (Dev, QA, BA)

### For Team Members
- [ ] Explore shared queries to understand available views
- [ ] Review tag guidelines for consistent tagging
- [ ] Check sprint schedule to understand timeline
- [ ] Create a test work item to see templates in action
- [ ] Review README.md for project setup instructions
- [ ] Create a test PR to see the template

### For First Sprint
- [ ] Run "Team Backlog" query
- [ ] Assign work items to Sprint 1
- [ ] Set capacity for team members
- [ ] Start working and track progress with burndown

---

## 📖 Related Documentation

- [Work Item Templates Guide](../WORK_ITEM_TEMPLATES.md) - Detailed template usage
- [Quick Reference](../reference/QUICK_REFERENCE.md) - Command quick reference
- [CLI Usage Guide](../guides/cli-usage-guide.md) - Automation examples
- [Sync Mode Guide](../guides/sync-mode-guide.md) - Repository synchronization

---

## 🔧 Customization Options

All features support customization via PowerShell parameters:

### Custom Sprint Configuration
```powershell
# 8 sprints, 10-day duration, starting Dec 1
Ensure-AdoIterations "MyProject" -SprintCount 8 -SprintDurationDays 10 -StartDate (Get-Date "2025-12-01")
```

### Custom Queries
Add your own queries to the Shared Queries folder via Azure DevOps UI or REST API.

### Custom Tags
Document new tags in the Tag Guidelines wiki page.

### Custom Templates
Modify existing templates in Project Settings → Boards → Templates.

---

## 💡 Pro Tips

1. **Favorite Your Queries**: Star the queries you use daily for quick access
2. **Use Tag Filters on Boards**: Click tag pills on Kanban board for instant filtering
3. **Sprint Planning**: Use "Team Backlog" query to drag items to sprint
4. **Bug Triage**: Use "Active Bugs" query sorted by severity
5. **Standup Dashboard**: Pin "My Active Work" query to your personal dashboard
6. **PR Discipline**: Always link work items in PRs using the template
7. **Tag Consistency**: Reference the Tag Guidelines wiki when unsure
8. **Capacity Planning**: Update team capacity at start of each sprint

---

## 🆘 Troubleshooting

### Sprints Not Visible
**Solution**: Navigate to Boards → Sprints. If empty, check Project Settings → Team configuration → Iterations.

### Queries Not Appearing
**Solution**: Check Boards → Queries → Shared Queries folder. Queries may take a few seconds to appear.

### Templates Not Auto-Populating
**Solution**: Verify templates are set as defaults in Project Settings → Boards → Templates → [Team] tab.

### README.md Not Added
**Solution**: Repository must have at least one commit. Use Option 6 (Bulk Migration) to push code first.

### Tags Not Following Guidelines
**Solution**: Share the Tag Guidelines wiki page with team. Consider using templates that include standard tags.

---

*Last Updated: November 5, 2025*

**Version**: 3.0.0
