# Team Productivity Features Guide

## Overview

This guide documents all the **team productivity features** automatically configured during project initialization. These features are designed to help teams hit the ground running with best practices already in place.

> 📖 **NEW**: Check out the [Best Practices Wiki Page](../README.md) created in your project's wiki for comprehensive guidance on using Azure DevOps effectively!

## ✨ What's Configured Automatically

When you initialize a new Azure DevOps project (Option 2 in the menu), the migration tool automatically sets up:

1. ✅ **Sprint Iterations** - 6 upcoming 2-week sprints
2. ✅ **Work Item Templates** - 6 comprehensive templates with DoR/DoD
3. ✅ **Shared Queries** - 5 essential queries for common scenarios
4. ✅ **Team Settings** - Backlog levels, working days, default iteration
5. ✅ **Team Dashboard** - World-class dashboard with key metrics ⭐ NEW
6. ✅ **Tag Guidelines** - Documented tag taxonomy in wiki
7. ✅ **Repository Templates** - README.md and PR template
8. ✅ **Areas** - Frontend, Backend, Infrastructure, Documentation
9. ✅ **Wiki** - Welcome page and guidelines
10. ✅ **Test Plan** - QA test plan with 4 test suites ⭐ NEW
11. ✅ **QA Queries** - 8 QA-specific queries for testing workflow ⭐ NEW
12. ✅ **QA Dashboard** - Comprehensive QA metrics dashboard ⭐ NEW
13. ✅ **Test Configurations** - 13 test configurations for cross-platform testing ⭐ NEW
14. ✅ **QA Guidelines** - Complete testing documentation in wiki ⭐ NEW

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

## 📊 Team Dashboard

### What's Created

A comprehensive **Team Overview Dashboard** with 8 essential widgets providing real-time insights into team performance and work status.

**Dashboard Name**: `<Team Name> - Overview`  
**Location**: Overview → Dashboards → Team Name - Overview

### Dashboard Widgets

#### 📈 Row 1: Sprint Metrics (2x2 widgets)

##### 1. Sprint Burndown Chart
**Purpose**: Track daily progress against sprint commitment

**What it shows**:
- Ideal burndown line (expected progress)
- Actual remaining work
- Work added mid-sprint
- Sprint goal trajectory

**Use Case**: 
- Daily standup discussions
- Identify if team is on track
- Spot scope creep early
- Predict sprint completion

**How to Read**:
- ✅ Green: Ahead of schedule
- ⚠️ Yellow: Slightly behind
- 🔴 Red: Significantly behind
- 📈 Upward spike: Work added

##### 2. Velocity Chart
**Purpose**: Measure team capacity and predictability over multiple sprints

**What it shows**:
- Planned work per sprint
- Completed work per sprint
- Incomplete work carried over
- Average velocity trend

**Use Case**:
- Sprint planning (how much to commit)
- Capacity forecasting
- Process improvement discussions
- Team performance trends

**Metrics**:
- **Velocity**: Story points completed per sprint
- **Trend**: Is velocity increasing, stable, or declining?
- **Predictability**: Consistency of delivery

---

#### 📊 Row 2: Work Distribution (2x2 widgets)

##### 3. Work Items by State (Pie Chart)
**Purpose**: Visualize current work distribution across workflow states

**What it shows**:
- New: Not started
- Active: In progress
- Resolved: Ready for review
- Closed: Complete
- Custom states (if any)

**Use Case**:
- Identify bottlenecks (too much in one state)
- Balance work-in-progress
- Sprint health check
- Flow efficiency analysis

**Red Flags**:
- 🚩 Too many "In Progress" (WIP overload)
- 🚩 Large "Resolved" pile (review bottleneck)
- 🚩 Very few "New" (backlog not refined)

##### 4. Work Items by Assigned To (Stacked Bar)
**Purpose**: Show workload distribution across team members

**What it shows**:
- Work items assigned to each person
- Breakdown by work item type
- Unassigned work items
- Relative team member workloads

**Use Case**:
- Balance workload
- Identify overloaded team members
- Find unassigned work
- Capacity planning

**Best Practices**:
- Aim for balanced distribution
- Leave some capacity for unplanned work
- Reassign if someone is overloaded
- Keep some items unassigned for flexibility

---

#### 🎯 Row 3: Quick Metrics (4x1 query tiles)

##### 5. My Active Work Tile
**Purpose**: Show count of work items assigned to viewer

**What it shows**: Number of active work items assigned to current user

**Use Case**: Personal dashboard, quick status check

##### 6. Active Bugs Tile
**Purpose**: Track open bug count

**What it shows**: Total count of bugs not yet closed

**Use Case**: Bug triage priority, quality metrics

**Thresholds**:
- ✅ 0-5 bugs: Healthy
- ⚠️ 6-15 bugs: Needs attention
- 🔴 16+ bugs: Quality issue

##### 7. Blocked Items Tile
**Purpose**: Highlight impediments needing resolution

**What it shows**: Work items tagged as "blocked" or "impediment"

**Use Case**: 
- Daily standup focus
- Management escalation
- Dependency tracking

**Action Items**:
- Red count: Review in standup
- Assign owners to remove blockers
- Track blocker resolution time

##### 8. Ready for Review Tile
**Purpose**: Show work awaiting code review

**What it shows**: Items in "Ready for Review" state or tagged "needs-review"

**Use Case**:
- Code review backlog
- Pull request tracking
- Flow bottleneck detection

**Best Practice**: Keep this number low (review within 24 hours)

---

### Dashboard Layout

```
┌─────────────────────────────────────────────────────┐
│              Team Name - Overview Dashboard          │
├──────────────────────┬──────────────────────────────┤
│                      │                              │
│  Sprint Burndown     │      Velocity Chart          │
│      (2x2)           │         (2x2)                │
│                      │                              │
├──────────────────────┼──────────────────────────────┤
│                      │                              │
│  Work Items by       │   Work Items by              │
│     State (2x2)      │   Assigned To (2x2)          │
│                      │                              │
├──────┬───────┬───────┼───────┬──────────────────────┤
│ My   │Active │Blocked│Ready  │                      │
│Active│ Bugs  │ Items │for    │                      │
│Work  │ (1x1) │ (1x1) │Review │                      │
│(1x1) │       │       │ (1x1) │                      │
└──────┴───────┴───────┴───────┴──────────────────────┘
```

---

### How to Use the Dashboard

#### Daily Standup
1. **Open dashboard** at start of standup
2. **Review Burndown**: Are we on track?
3. **Check Blocked Items**: What needs unblocking?
4. **Look at Ready for Review**: Any PRs waiting?
5. **Quick scan** of work distribution

#### Sprint Planning
1. **Review Velocity**: What's our average capacity?
2. **Check Work by Assignment**: Is anyone overloaded?
3. **Plan commitment** based on historical velocity

#### Sprint Review
1. **Show Burndown** to stakeholders
2. **Demonstrate Velocity** trend
3. **Discuss** improvements based on data

#### Continuous Monitoring
- **Morning**: Check personal work + blocked items
- **Afternoon**: Review code review queue
- **Weekly**: Analyze velocity and work distribution trends

---

### Customization Options

#### Add More Widgets
Navigate to dashboard → Edit → Add Widget

**Recommended additions**:
- **Build Status**: Show recent build results
- **Test Results Trend**: Track test pass rate
- **Pull Request Summary**: PR metrics
- **Work Item Age**: Track aging items
- **CFD (Cumulative Flow Diagram)**: Advanced flow metrics

#### Modify Queries
Click widget → Configure → Change query

Example: Change "Active Bugs" to show only P0/P1 bugs

#### Adjust Layout
Drag and drop widgets to rearrange

**Tips**:
- Put most-used widgets at top
- Group related widgets together
- Use 2-column layout for key metrics

#### Create Multiple Dashboards
Consider creating specialized dashboards:
- **Leadership Dashboard**: High-level metrics, trends
- **Developer Dashboard**: Personal work, PRs, builds
- **QA Dashboard**: Test results, bug trends
- **Sprint Dashboard**: Sprint-specific detailed view

---

### Dashboard Best Practices

#### ✅ DO
- **Review daily** - Make it part of standup ritual
- **Keep it visible** - Pin tab in browser
- **Update regularly** - Widgets refresh automatically, but check accuracy
- **Share with stakeholders** - Transparent metrics build trust
- **Use for decisions** - Data-driven sprint planning

#### ❌ DON'T
- **Ignore red flags** - Act on concerning trends
- **Micromanage from dashboard** - Use for insights, not surveillance
- **Add too many widgets** - Keep it focused and scannable
- **Forget to explain** - Train team on how to read charts
- **Use as blame tool** - Metrics for improvement, not punishment

---

### Troubleshooting

#### Dashboard Not Loading
**Solution**: Check permissions. You need "View dashboards" permission for the team.

#### Widgets Show "No Data"
**Causes**:
1. **New project** - No sprint data yet (wait for first sprint)
2. **No work items** - Create some work items first
3. **Query issues** - Verify shared queries exist

#### Burndown Chart Empty
**Solution**: 
1. Assign work items to current sprint
2. Set story points on work items
3. Wait 24 hours for data to populate

#### Velocity Chart Shows One Sprint
**Solution**: Need at least 2 completed sprints for trend analysis

#### Query Tiles Show Wrong Count
**Solution**: 
1. Edit widget → Configure
2. Re-select the query from dropdown
3. Save widget

---

---

## 🧪 QA Infrastructure

### Overview

A comprehensive **Quality Assurance infrastructure** is automatically configured to support professional testing workflows from day one.

**Components Created**:
- Test Plan with 4 specialized test suites
- 8 QA-specific work item queries
- QA Metrics Dashboard with 8 widgets
- 13 test configurations for cross-platform testing
- Complete QA Guidelines documentation

---

### Test Plan & Test Suites

#### What's Created

A complete **test plan** with 4 test suites for different testing phases:

**Test Plan Name**: `<Project> - Test Plan`  
**Location**: Test Plans → Your Project - Test Plan

#### Test Suites

##### 1. **Regression Testing Suite**
**Purpose**: Verify that existing functionality still works after changes

**Use Case**:
- Run after each major release
- Validate core user journeys
- Ensure no breaking changes
- Before production deployment

**Test Types**: End-to-end scenarios, critical path validation

**When to Use**:
- Before release to production
- After major feature additions
- When refactoring existing code
- After dependency updates

##### 2. **Smoke Testing Suite**
**Purpose**: Quick validation that critical functionality works

**Use Case**:
- First test after build
- Verify app launches and basic functions work
- Catch critical blockers early
- Fast feedback for developers

**Test Types**: Login, navigation, key workflows

**Duration**: 15-30 minutes (fast execution)

**When to Use**:
- After every deployment to test environment
- Before starting regression testing
- After infrastructure changes
- Morning sanity check

##### 3. **Integration Testing Suite**
**Purpose**: Test interactions between system components

**Use Case**:
- API integration validation
- Database interactions
- Third-party service connections
- Microservices communication

**Test Types**: API tests, service integration, data flow validation

**When to Use**:
- After API changes
- When integrating new services
- After database schema updates
- Continuous integration pipeline

##### 4. **User Acceptance Testing (UAT) Suite**
**Purpose**: Validate business requirements with stakeholders

**Use Case**:
- Product owner validation
- Business user testing
- Requirement verification
- Pre-production sign-off

**Test Types**: Business scenarios, user journeys, requirement validation

**When to Use**:
- Before sprint review/demo
- Before release to production
- After new feature completion
- Stakeholder validation sessions

---

### QA Queries

#### What's Created

**8 specialized queries** in **Shared Queries/QA** folder for testing workflow management.

#### Available Queries

##### 1. **Test Execution Status**
Shows all test cases with execution results

**WIQL**:
```
[System.WorkItemType] = 'Test Case'
ORDER BY [Microsoft.VSTS.Common.Priority] ASC
```

**Use Case**: Test execution tracking, coverage analysis

**Fields Shown**: Test case title, priority, assigned tester, last result

##### 2. **Bugs by Severity**
Shows active bugs grouped by severity level

**WIQL**:
```
[System.WorkItemType] = 'Bug'
AND [System.State] <> 'Closed'
ORDER BY [Microsoft.VSTS.Common.Severity] ASC
```

**Use Case**: Bug triage, prioritization meetings

**Priority Order**: P0 (Critical) → P1 (High) → P2 (Medium) → P3 (Low)

##### 3. **Bugs by Priority**
Shows active bugs ordered by business priority

**WIQL**:
```
[System.WorkItemType] = 'Bug'
AND [System.State] <> 'Closed'
ORDER BY [Microsoft.VSTS.Common.Priority] ASC
```

**Use Case**: Sprint planning, bug fix scheduling

##### 4. **Test Coverage by Feature**
Shows features and their linked test cases

**WIQL**:
```
[System.WorkItemType] = 'Feature'
ORDER BY [System.CreatedDate] DESC
```

**Use Case**: Test coverage gaps, requirement validation

**Action**: Review linked test cases per feature

##### 5. **Failed Test Cases**
Shows test cases that failed in last execution

**WIQL**:
```
[System.WorkItemType] = 'Test Case'
AND [Microsoft.VSTS.TCM.AutomatedTestName] <> ''
ORDER BY [Microsoft.VSTS.Common.Priority] ASC
```

**Use Case**: Bug investigation, test maintenance

**Next Steps**: File bugs for failures, update test cases

##### 6. **Regression Candidates**
Shows features with recent changes needing regression testing

**WIQL**:
```
[System.WorkItemType] IN ('User Story', 'Feature')
AND [System.State] = 'Resolved'
AND [System.Tags] CONTAINS 'needs-testing'
ORDER BY [System.ChangedDate] DESC
```

**Use Case**: Regression test planning, sprint testing

##### 7. **Bug Triage Queue**
Shows new bugs awaiting triage

**WIQL**:
```
[System.WorkItemType] = 'Bug'
AND [System.State] = 'New'
ORDER BY [System.CreatedDate] DESC
```

**Use Case**: Daily bug triage meetings

**Action**: Assign severity, priority, owner

##### 8. **Reopened Bugs**
Shows bugs that were reopened after being closed

**WIQL**:
```
[System.WorkItemType] = 'Bug'
AND [System.State] = 'Active'
AND [System.Reason] = 'Reactivated'
ORDER BY [Microsoft.VSTS.Common.Severity] ASC
```

**Use Case**: Quality trend analysis, recurring issues

**Red Flag**: High reopen rate indicates root cause issues

---

### QA Dashboard

#### What's Created

A specialized **QA Metrics Dashboard** with 8 widgets for testing insights.

**Dashboard Name**: `<Team Name> - QA Metrics`  
**Location**: Overview → Dashboards → Team Name - QA Metrics

#### Dashboard Widgets

##### Row 1: Test Execution

**1. Test Execution Status (2x2 Chart)**
- Shows test pass/fail/not run counts
- Visual pie chart of test results
- Quick health indicator

**2. Failed Test Cases (2x2 Query Results)**
- List of failed tests
- Priority and assigned tester
- Direct links to test cases

##### Row 2: Bug Metrics

**3. Bugs by Severity (2x2 Stacked Bar)**
- P0/P1/P2/P3 bug counts
- Color-coded by severity
- Trend over time

**4. Bug Triage Queue (2x2 Query Results)**
- New bugs needing triage
- Creation date and reporter
- Quick triage access

##### Row 3: Coverage & Trends

**5. Test Coverage (1x1 Tile)**
- Number of test cases per feature
- Coverage percentage
- Gap identification

**6. Regression Candidates (1x1 Tile)**
- Count of stories needing regression
- Tagged "needs-testing"
- Regression planning aid

**7. Reopened Bugs (1x1 Tile)**
- Count of reactivated bugs
- Quality indicator
- Trend monitoring

**8. Bugs by Priority (1x1 Stacked Bar)**
- P1/P2/P3 bug distribution
- Sprint planning metric
- Backlog health

---

### Test Configurations

#### What's Created

**13 test configurations** for comprehensive cross-platform and environment testing.

**Location**: Test Plans → Configurations

#### Test Variables

##### 1. **Browser** (4 values)
- Chrome
- Firefox
- Safari
- Edge

##### 2. **Operating System** (5 values)
- Windows
- macOS
- Linux
- iOS
- Android

##### 3. **Environment** (4 values)
- Dev
- Test
- Staging
- Production

#### Test Configurations

##### Browser/OS Combinations (10 configs)

1. **Chrome on Windows** - Most common combination
2. **Chrome on macOS** - Developer workstations
3. **Chrome on Linux** - Server environments
4. **Chrome on Android** - Mobile web testing
5. **Firefox on Windows** - Cross-browser validation
6. **Firefox on macOS** - Mac Firefox users
7. **Firefox on Linux** - Open source stacks
8. **Safari on macOS** - Mac default browser
9. **Safari on iOS** - iPhone/iPad testing
10. **Edge on Windows** - Windows default browser

##### Environment-Specific (3 configs)

11. **Dev Environment** - Development testing
12. **Staging Environment** - Pre-production validation
13. **Production Environment** - Production monitoring

#### How to Use Configurations

**Test Case Assignment**:
1. Open test case in test plan
2. Select configurations to test against
3. Run tests for each configuration
4. Track results per configuration

**Best Practices**:
- Assign critical tests to all browser/OS combos
- Use environment configs for deployment validation
- Focus mobile testing on Safari (iOS) and Chrome (Android)
- Run regression on most popular config (Chrome/Windows) first

**Common Scenarios**:
- **Web App**: Chrome+Firefox on Windows/macOS
- **Mobile-First**: Chrome/Safari on Android/iOS
- **Enterprise**: Edge on Windows + Chrome on Windows
- **Multi-Platform**: All browser/OS combinations

---

### QA Guidelines Wiki

#### What's Created

A comprehensive **QA Guidelines** wiki page with 7 major sections.

**Location**: Wiki → QA-Guidelines

#### Documentation Sections

##### 1. **Testing Strategy**
- Testing pyramid (70% unit, 20% integration, 10% E2E)
- Test types (Regression, Smoke, Integration, UAT)
- Test planning approach
- Quality gates

##### 2. **Test Configurations**
- When to use each configuration
- Browser/OS coverage guidelines
- Environment testing workflow
- Configuration selection criteria

##### 3. **Test Plan Structure**
- How to organize test suites
- Test case naming conventions
- Linking tests to requirements
- Test suite purposes

##### 4. **Writing Test Cases**
- Test case template structure
- Test step best practices
- Expected results guidelines
- Preconditions and setup

##### 5. **Bug Reporting**
- Bug severity definitions (P0-P3)
- Bug lifecycle workflow
- Required information checklist
- Bug triage process

##### 6. **QA Queries & Dashboards**
- How to use each query
- Dashboard widget explanations
- Custom query creation
- Reporting best practices

##### 7. **Testing Checklist**
- Before testing (environment, data, access)
- During testing (exploratory, documentation)
- After testing (results, reporting)
- Before release (sign-off, production readiness)

#### Key Content Highlights

**Testing Pyramid**:
```
    /\
   /  \  10% - E2E (Test Plans, Manual Testing)
  /────\
 /      \ 20% - Integration (API, Service Tests)
/────────\
/          \ 70% - Unit Tests (Automated, Fast)
```

**Bug Severity Guidelines**:
- **P0 - Critical**: System down, data loss, security breach
- **P1 - High**: Major feature broken, workaround exists
- **P2 - Medium**: Minor feature issue, usability problem
- **P3 - Low**: Cosmetic issue, enhancement

**Test Case Format**:
```
Title: [TEST] User can login with valid credentials

Preconditions:
- User account exists
- Application is accessible

Steps:
1. Navigate to login page
   Expected: Login form visible
2. Enter valid username/password
   Expected: Fields accept input
3. Click "Sign In" button
   Expected: User redirected to dashboard
```

---

### How to Use QA Infrastructure

#### For QA Team Lead

**Setup (One-Time)**:
1. Review test plan and suites structure
2. Customize test configurations if needed
3. Share QA Guidelines wiki with team
4. Set up QA Dashboard as team homepage

**Ongoing**:
1. Run "Bug Triage Queue" query daily
2. Monitor QA Dashboard during sprints
3. Update test cases in test suites
4. Review test coverage regularly

#### For QA Engineers

**Daily Workflow**:
1. Check "My Active Work" for assigned tests
2. Review "Failed Test Cases" for investigations
3. Use test configurations for test execution
4. Log bugs with proper severity/priority

**Sprint Workflow**:
1. Plan regression testing with "Regression Candidates"
2. Execute smoke tests after each deployment
3. Track progress with QA Dashboard
4. Update test execution results

#### For Product Owners

**Quality Oversight**:
1. Review QA Dashboard in sprint reviews
2. Monitor bug trends (severity, reopen rate)
3. Validate UAT results before release
4. Check test coverage per feature

**Release Decisions**:
- No P0/P1 bugs open
- Regression suite passed
- UAT sign-off complete
- Smoke tests green on production

---

### QA Metrics & KPIs

Track these metrics using QA Dashboard:

#### Test Coverage
**Metric**: Test cases per feature  
**Target**: 100% of features have test cases  
**Red Flag**: Features with no test cases

#### Test Pass Rate
**Metric**: Passed tests / Total tests  
**Target**: >95% pass rate  
**Red Flag**: <90% pass rate

#### Bug Reopen Rate
**Metric**: Reopened bugs / Total bugs  
**Target**: <5% reopen rate  
**Red Flag**: >10% reopen rate

#### Bug Resolution Time
**Metric**: Days from New → Closed  
**Target**: P0 <1 day, P1 <3 days, P2 <7 days  
**Red Flag**: Exceeding targets

#### Test Execution Progress
**Metric**: Executed tests / Planned tests  
**Target**: 100% before sprint end  
**Red Flag**: <80% executed in last 3 days

---

### Troubleshooting QA Features

#### Test Plan Not Visible
**Solution**: Navigate to Test Plans (left sidebar). If missing, check project permissions.

#### Test Configurations Not Appearing
**Solution**: 
1. Go to Test Plans → Configurations
2. If empty, verify "Ensure-AdoTestConfigurations" ran successfully
3. Check migration logs for errors

#### QA Queries Empty
**Solution**: 
1. Verify queries exist in Shared Queries/QA folder
2. Check that work items (test cases, bugs) have been created
3. Run query with no filters to see all items

#### QA Dashboard Shows "No Data"
**Causes**:
1. **New project** - No test execution data yet
2. **No test cases** - Create test cases in test plan first
3. **No bugs** - Create test bugs for testing

**Solution**: 
1. Create test cases in test plan
2. Execute some tests (mark as passed/failed)
3. Create a few test bugs
4. Wait 1-2 hours for dashboard to refresh

#### Test Execution Results Not Saving
**Solution**: 
1. Ensure test case is in a test suite
2. Run tests through Test Plans → Execute tests
3. Check permissions (need "Manage test runs" permission)

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
| Team Dashboard | ✅ Yes (8 widgets) | ❌ No | Sprint metrics & insights |
| Tag Guidelines | ✅ Yes (wiki page) | ❌ No | Consistent tagging |
| Repository Templates | ✅ Yes (after push) | ❌ No | Professional onboarding |
| Areas | ✅ Yes (4 areas) | ❌ No | Work organization |
| Wiki | ✅ Yes (welcome + tags) | ❌ No | Documentation hub |
| **Test Plan** | ✅ **Yes (4 suites)** | ❌ **No** | **Professional QA workflow** |
| **QA Queries** | ✅ **Yes (8 queries)** | ❌ **No** | **Testing workflow management** |
| **QA Dashboard** | ✅ **Yes (8 widgets)** | ❌ **No** | **Quality metrics & insights** |
| **Test Configurations** | ✅ **Yes (13 configs)** | ❌ **No** | **Cross-platform testing** |
| **QA Guidelines** | ✅ **Yes (wiki page)** | ❌ **No** | **Testing documentation** |

---

## 🚀 Getting Started Checklist

After project initialization:

### For Project Administrators
- [ ] Review sprint schedule (Boards → Sprints)
- [ ] Verify shared queries (Boards → Queries → Shared Queries)
- [ ] Check team settings (Project Settings → Team configuration)
- [ ] Review tag guidelines (Wiki → Tag-Guidelines)
- [ ] **Review test plan and test suites (Test Plans)** ⭐ NEW
- [ ] **Check QA Dashboard (Overview → Dashboards → QA Metrics)** ⭐ NEW
- [ ] **Verify test configurations (Test Plans → Configurations)** ⭐ NEW
- [ ] Customize README.md if needed
- [ ] Invite team members and assign to groups (Dev, QA, BA)

### For Team Members
- [ ] Explore shared queries to understand available views
- [ ] Review tag guidelines for consistent tagging
- [ ] Check sprint schedule to understand timeline
- [ ] Create a test work item to see templates in action
- [ ] Review README.md for project setup instructions
- [ ] Create a test PR to see the template

### For QA Team
- [ ] **Review QA Guidelines wiki (Wiki → QA-Guidelines)** ⭐ NEW
- [ ] **Explore QA queries folder (Boards → Queries → Shared Queries → QA)** ⭐ NEW
- [ ] **Review test plan structure (Test Plans → Test Plan)** ⭐ NEW
- [ ] **Set up QA Dashboard as homepage** ⭐ NEW
- [ ] **Review test configurations for testing scenarios** ⭐ NEW
- [ ] **Create initial test cases in test suites** ⭐ NEW

### For First Sprint
- [ ] Run "Team Backlog" query
- [ ] Assign work items to Sprint 1
- [ ] Set capacity for team members
- [ ] Start working and track progress with burndown
- [ ] **Plan regression testing using "Regression Candidates" query** ⭐ NEW
- [ ] **Execute smoke tests after first deployment** ⭐ NEW

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
