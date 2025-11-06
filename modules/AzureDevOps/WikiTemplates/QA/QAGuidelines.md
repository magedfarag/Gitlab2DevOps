# QA Guidelines & Testing Standards

This guide provides comprehensive testing standards and QA practices for ensuring high-quality software delivery.

---

## 📋 Table of Contents

1. [Testing Strategy](#testing-strategy)
2. [Test Configurations](#test-configurations)
3. [Test Plan Structure](#test-plan-structure)
4. [Writing Test Cases](#writing-test-cases)
5. [Bug Reporting](#bug-reporting)
6. [QA Queries & Dashboards](#qa-queries--dashboards)
7. [Testing Checklist](#testing-checklist)

---

## 🎯 Testing Strategy

### Testing Pyramid

Our testing strategy follows the testing pyramid principle:

**Unit Tests** (70%)
- Fast, isolated tests for individual functions/methods
- Run on every commit
- Owned by developers

**Integration Tests** (20%)
- Test component interactions
- API contract testing
- Database integration
- Run before deployment

**System/UI Tests** (10%)
- End-to-end user scenarios
- Cross-browser testing
- Manual exploratory testing
- Run before release

### Test Types

#### 🔄 Regression Testing
- **Purpose**: Verify existing functionality still works after changes
- **Frequency**: Every sprint
- **Suite**: Test Plans → Regression Suite
- **Priority**: High severity, high usage features

#### 💨 Smoke Testing
- **Purpose**: Validate critical paths work in deployed environment
- **Frequency**: After every deployment
- **Suite**: Test Plans → Smoke Suite
- **Duration**: < 30 minutes

#### 🔗 Integration Testing
- **Purpose**: Verify system components work together
- **Frequency**: Daily (automated), weekly (manual)
- **Suite**: Test Plans → Integration Suite
- **Focus**: API contracts, data flow, service communication

#### ✅ User Acceptance Testing (UAT)
- **Purpose**: Validate business requirements with stakeholders
- **Frequency**: End of sprint
- **Suite**: Test Plans → UAT Suite
- **Participants**: Product Owner, Business Users

---

## 🖥️ Test Configurations

Our project uses **13 predefined test configurations** for comprehensive coverage:

### Browser/OS Combinations (10 configs)

#### Desktop Browsers
- **Chrome on Windows** - Primary configuration (80% users)
- **Chrome on macOS** - Mac users
- **Chrome on Linux** - Developer workstations
- **Firefox on Windows** - Secondary browser
- **Firefox on macOS** - Mac Firefox users
- **Firefox on Linux** - Linux Firefox users
- **Edge on Windows** - Windows native browser
- **Safari on macOS** - Mac native browser

#### Mobile Browsers
- **Safari on iOS** - iPhone/iPad testing
- **Chrome on Android** - Android device testing

### Environment Configurations (3 configs)

- **Dev Environment** - Early integration testing
- **Staging Environment** - Pre-production validation
- **Production Environment** - Production smoke tests

### Using Test Configurations

**Assign configurations to test suites**:
1. Navigate to Test Plans → Your Test Plan
2. Select a test suite
3. Right-click → Assign Configuration
4. Choose appropriate configurations

**Best Practices**:
- ✅ Assign browser configs to UI test suites
- ✅ Assign environment configs to integration/smoke suites
- ✅ Use multiple configs for critical test cases
- ❌ Don't assign all configs to every test (test what matters)

---

## 📚 Test Plan Structure

### Test Plan: \``$Project - Test Plan\``

Our test plan is organized into **4 test suites**:

#### 1. Regression Suite
- **Purpose**: Verify existing functionality
- **Test Cases**: High-priority, stable features
- **Run Frequency**: Every sprint
- **Configurations**: All major browsers (Chrome, Firefox, Edge, Safari)

#### 2. Smoke Suite
- **Purpose**: Critical path validation
- **Test Cases**: Login, core workflows, data access
- **Run Frequency**: After every deployment
- **Configurations**: Chrome on Windows + Production Environment
- **Time Limit**: 30 minutes maximum

#### 3. Integration Suite
- **Purpose**: Component interaction testing
- **Test Cases**: API testing, data flow, service communication
- **Run Frequency**: Daily (automated), weekly (manual)
- **Configurations**: All environments (Dev, Staging, Production)

#### 4. UAT Suite
- **Purpose**: Business acceptance testing
- **Test Cases**: Business scenarios, user workflows
- **Run Frequency**: End of sprint
- **Configurations**: Chrome on Windows + Staging Environment
- **Participants**: Product Owner, Business Users

### Organizing Test Cases

**Naming Convention**:
````````````
[Module] - [Action] - [Expected Result]
Example: [Login] - Valid credentials - User logged in successfully
````````````

**Tags for Test Cases**:
- \``regression\`` - Include in regression suite
- \``smoke\`` - Critical path test
- \``automated\`` - Automated test exists
- \``manual-only\`` - Cannot be automated
- \``blocked\`` - Test is currently blocked

---

## ✍️ Writing Test Cases

### Test Case Template

Use the **Test Case - Quality Validation** template:

**Title Format**: \``[TEST] <scenario name>\``
- ✅ Good: "[TEST] Login with valid credentials"
- ❌ Bad: "test login"

### Test Case Sections

#### 1. Test Objective
- **Purpose**: What are we validating?
- **Test Type**: Unit / Integration / System / UAT

#### 2. Prerequisites
- Environment state before test
- Required data setup
- User permissions needed

#### 3. Test Steps
Write clear, numbered steps:
````````````
1. Navigate to login page
2. Enter username: 'testuser@example.com'
3. Enter password: 'Test123!'
4. Click 'Sign In' button
5. Verify user dashboard displays
````````````

#### 4. Expected Results
- Define success criteria for each step
- Be specific and measurable
- Include screenshots/examples if helpful

#### 5. Test Data
- List required test data
- Include valid and invalid scenarios
- Document edge cases

### Test Case Best Practices

✅ **DO**:
- Write atomic tests (one scenario per test case)
- Use clear, action-oriented language
- Include expected results for each step
- Add screenshots for UI elements
- Link to User Stories (Tested By relationship)
- Assign appropriate configurations

❌ **DON'T**:
- Write vague steps ("Check if it works")
- Skip expected results
- Combine multiple unrelated scenarios
- Assume prior knowledge
- Forget to update tests when features change

---

## 🐛 Bug Reporting

### Bug Template

Use the **Bug - Triaging &amp; Resolution** template:

**Title Format**: \``[BUG] <brief description>\``
- ✅ Good: "[BUG] Login fails with special characters in password"
- ❌ Bad: "login broken"

### Required Bug Information

#### 1. Environment
````````````
Browser/OS: Chrome 118 on Windows 11
Application Version: 2.5.3
User Role: Standard User
````````````

#### 2. Steps to Reproduce
````````````
1. Navigate to https://app.example.com/login
2. Enter username: 'test@example.com'
3. Enter password containing special chars: 'P@ssw0rd!'
4. Click 'Sign In'
5. Observe error message
````````````

#### 3. Expected vs Actual Behavior
- **Expected**: User successfully logs in
- **Actual**: Error message: "Invalid credentials"

#### 4. Additional Information
- **Frequency**: Always reproducible
- **Impact**: Users cannot log in (critical)
- **Workaround**: Use password without special characters
- **Attachments**: Screenshots, logs, network traces

### Bug Severity Guidelines

**Critical (P0)** - Fix immediately
- Complete system/feature failure
- Data loss or corruption
- Security vulnerability
- No workaround available

**High (P1)** - Fix in current sprint
- Major feature broken
- Significant functionality impaired
- Workaround exists but difficult
- Affects many users

**Medium (P2)** - Fix in next sprint
- Minor feature issue
- Cosmetic problems affecting usability
- Easy workaround available
- Affects some users

**Low (P3)** - Fix when time permits
- Cosmetic issues
- Rare edge cases
- Enhancement requests
- Minimal user impact

### Bug Lifecycle

1. **New** → Triage needed
2. **Active** → Assigned to developer
3. **Resolved** → Fixed, ready for QA verification
4. **Closed** → QA verified fix
5. **Reopened** → Issue persists (back to Active)

**Triaging Tags**:
- \``triage-needed\`` - Needs severity/priority assignment
- \``needs-repro\`` - Cannot reproduce, needs more info
- \``regression\`` - Previously working feature broke
- \``known-issue\`` - Documented limitation

---

## 📊 QA Queries &amp; Dashboards

### Available QA Queries

Navigate to **Queries → Shared Queries → QA** folder:

#### 1. Test Execution Status
- Shows test case execution progress
- Groups by outcome (Passed, Failed, Blocked, Not Run)
- Use for sprint QA status reporting

#### 2. Bugs by Severity
- Lists active bugs grouped by severity
- Use for triaging and prioritization
- Critical bugs should be addressed first

#### 3. Bugs by Priority
- Lists active bugs grouped by priority
- Use for sprint planning
- P0/P1 bugs block release

#### 4. Test Coverage
- Shows User Stories with/without test cases
- Use to identify gaps in test coverage
- Goal: 80%+ stories have test cases

#### 5. Failed Test Cases
- Lists all failed test cases
- Use for daily QA standup
- Requires immediate investigation

#### 6. Regression Candidates
- Test cases not run in last 30 days
- Use to plan regression testing
- Update stale test cases

#### 7. Bug Triage Queue
- New/unassigned bugs needing triage
- Use in bug triage meetings
- Assign severity, priority, owner

#### 8. Reopened Bugs
- Bugs that failed verification
- Use to track quality issues
- Requires root cause analysis

### QA Dashboard

Navigate to **Dashboards → <Team> - QA Metrics**:

**Row 1: Test Execution Overview**
- **Test Execution Status** (Pie Chart) - Pass/Fail distribution
- **Bugs by Severity** (Stacked Bar) - Bug severity trends

**Row 2: Bug Analysis**
- **Test Coverage** (Pie Chart) - Coverage percentage
- **Bugs by Priority** (Pivot Table) - Priority distribution

**Row 3: Action Items** (Tiles)
- **Failed Test Cases** - Count requiring investigation
- **Regression Candidates** - Count needing execution
- **Bug Triage Queue** - Count needing assignment
- **Reopened Bugs** - Count needing analysis

**Dashboard Best Practices**:
- Review daily during standup
- Track trends over sprints
- Set goals (e.g., <5% test failure rate)
- Address anomalies immediately

---

## ✅ Testing Checklist

### Before Starting Testing

- [ ] Review User Story acceptance criteria
- [ ] Verify test environment is available
- [ ] Prepare test data
- [ ] Check test configurations assigned
- [ ] Review related test cases

### During Testing

- [ ] Execute test steps sequentially
- [ ] Document actual results for each step
- [ ] Capture screenshots for failures
- [ ] Mark step outcomes (Pass/Fail)
- [ ] Log defects immediately
- [ ] Link bugs to test cases

### After Testing

- [ ] Update test case results
- [ ] Verify all test steps executed
- [ ] Update QA queries/dashboard
- [ ] Report status to team
- [ ] Identify blocked tests
- [ ] Plan next testing iteration

### Before Release

- [ ] All smoke tests passed
- [ ] No open P0/P1 bugs
- [ ] Regression suite executed
- [ ] UAT sign-off received
- [ ] Test results documented
- [ ] Known issues documented in release notes

---

## 🎓 QA Resources

### Training Materials

- **Azure Test Plans Documentation**: [Learn Test Plans](https://learn.microsoft.com/en-us/azure/devops/test/)
- **Test Configuration Guide**: Test Plans → Configurations
- **Work Item Query Language (WIQL)**: [WIQL Reference](https://learn.microsoft.com/en-us/azure/devops/boards/queries/wiql-syntax)

### Team Contacts

- **QA Lead**: <Assign QA Lead>
- **Test Automation**: <Assign Automation Lead>
- **Product Owner**: <Assign PO>

### Support

- **Questions**: Use team chat or email QA Lead
- **Tool Issues**: Create Bug work item with tag \``qa-tooling\``
- **Process Improvements**: Discuss in retrospectives

---

*Last Updated: $(Get-Date -Format 'yyyy-MM-dd')*
*Version: 1.0*