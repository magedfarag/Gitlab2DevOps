# Bug Lifecycle & Quality Metrics

Comprehensive guide for managing defects and tracking quality metrics throughout the development lifecycle.

---

## 🐛 Bug Lifecycle

### Bug States

```
New → Assigned → In Progress → Resolved → Closed
                      ↓
                  Reopened
```

**Detailed States**
1. **New**: Bug reported, awaiting triage
2. **Assigned**: Assigned to developer for investigation
3. **In Progress**: Developer actively working on fix
4. **Resolved**: Fix complete, awaiting verification
5. **Closed**: Verified fixed, no further action
6. **Reopened**: Issue persists or regressed

### Bug Workflow

**1. Bug Discovery & Reporting**
```markdown
Title: Login fails with valid credentials on Chrome

Environment: QA (https://qa.example.com)
Browser: Chrome 119, Windows 11
User Account: testuser@example.com

Steps to Reproduce:
1. Navigate to https://qa.example.com/login
2. Enter username: testuser@example.com
3. Enter password: Test123!
4. Click "Login" button

Expected Result:
User logged in and redirected to dashboard

Actual Result:
Error message: "Invalid credentials"
User remains on login page

Additional Info:
- Works fine in Firefox
- Issue started after deployment on 2025-11-05
- Screenshot attached
- Console shows: "TypeError: Cannot read property 'token' of undefined"
```

**2. Bug Triage**
- **Severity**: Critical/High/Medium/Low
- **Priority**: P0/P1/P2/P3
- **Type**: Functional/UI/Performance/Security
- **Assignment**: Assign to appropriate team/developer

**3. Investigation**
```markdown
Root Cause Analysis:
- Authentication service returns different response format
- Frontend expects {token: "..."} but receives {accessToken: "..."}
- Backend API changed in PR #1234

Fix Approach:
- Update frontend to handle new response format
- Add backward compatibility check
- Update integration tests
```

**4. Resolution**
- Fix developed and code reviewed
- Unit/integration tests added
- Deployed to QA environment
- Bug status → Resolved

**5. Verification**
- QA executes original test steps
- Verifies fix in affected browsers
- Checks for regression
- If passed → Closed, if failed → Reopened

---

## 📊 Bug Severity & Priority

### Severity Levels

**Critical (S1)**
- System crash or data loss
- Security vulnerability
- Production down
- No workaround available
**Example**: Payment processing completely broken

**High (S2)**
- Major functionality broken
- Affects many users
- Workaround exists but difficult
**Example**: Unable to upload files

**Medium (S3)**
- Feature partially works
- Affects some users
- Reasonable workaround exists
**Example**: Date picker doesn't validate weekends

**Low (S4)**
- Minor issue, cosmetic
- Rarely impacts users
- Easy workaround
**Example**: Button alignment off by 2px

### Priority Levels

**P0 - Blocker**
- Must fix before release
- Blocks testing or development
**SLA**: Fix within 4 hours

**P1 - High**
- Should fix before release
- Significant impact
**SLA**: Fix within 24 hours

**P2 - Medium**
- Can be fixed in next sprint
- Moderate impact
**SLA**: Fix within 1 week

**P3 - Low**
- Nice to fix eventually
- Minimal impact
**SLA**: Fix when capacity allows

### Severity vs Priority Matrix

|  | Low Impact | Medium Impact | High Impact |
|---|------------|---------------|-------------|
| **Rare** | P3 | P3 | P2 |
| **Occasional** | P3 | P2 | P1 |
| **Frequent** | P2 | P1 | P0 |

---

## 📈 Quality Metrics

### Defect Metrics

**Defect Density**
```
Defect Density = Total Defects / Size (KLOC or Story Points)

Example:
- 45 defects found
- 300 story points completed
- Defect Density = 45/300 = 0.15 defects per story point
```

**Defect Removal Efficiency (DRE)**
```
DRE = (Defects Found Pre-Release / Total Defects) × 100%

Example:
- 40 defects found in testing
- 5 defects found in production
- DRE = 40/(40+5) × 100% = 88.9%

Target: > 90%
```

**Defect Leakage**
```
Leakage = (Production Defects / Total Defects) × 100%

Example:
- 5 defects in production
- 45 total defects
- Leakage = 5/45 × 100% = 11.1%

Target: < 5%
```

### Testing Metrics

**Test Coverage**
```
Code Coverage = (Lines Executed / Total Lines) × 100%
Requirements Coverage = (Requirements Tested / Total Requirements) × 100%

Targets:
- Unit Test Coverage: > 80%
- Requirements Coverage: 100% for P0/P1
```

**Test Execution Metrics**
```
Pass Rate = (Tests Passed / Tests Executed) × 100%
Test Velocity = Tests Executed / Time Period

Example Sprint:
- 450 test cases executed
- 425 passed, 13 failed, 12 blocked
- Pass Rate = 425/450 × 100% = 94.4%
- Test Velocity = 450 tests / 10 days = 45 tests/day
```

**Defect Age**
```
Average Age = Total Days Open / Number of Defects

Example:
- Bug 1: 2 days
- Bug 2: 5 days
- Bug 3: 3 days
- Average Age = (2+5+3)/3 = 3.3 days

Target: < 5 days for High priority bugs
```

---

## 🎯 Quality Goals & Targets

### Sprint Quality Gates

**Entry Criteria**
- [ ] All P0 bugs from previous sprint closed
- [ ] Code coverage ≥ 80%
- [ ] Build success rate ≥ 95%
- [ ] No known Critical/High bugs

**Exit Criteria**
- [ ] All planned test cases executed
- [ ] Pass rate ≥ 95%
- [ ] Zero open Critical bugs
- [ ] All High bugs resolved or have approved mitigation
- [ ] Defect density < 0.2 per story point
- [ ] Test automation coverage ≥ 70%

### Release Quality Gates

**Pre-Release**
- [ ] DRE ≥ 90%
- [ ] All Critical/High bugs closed
- [ ] Performance tests pass
- [ ] Security scan complete
- [ ] Load test targets met
- [ ] Disaster recovery tested

**Post-Release Monitoring**
- [ ] Defect leakage < 5% (first 30 days)
- [ ] Production incidents < 2 per month
- [ ] Mean time to resolution (MTTR) < 4 hours
- [ ] Customer-reported bugs < 10% of total

---

## 📊 Quality Dashboard

### Key Metrics to Track

**Daily Dashboard**
```markdown
### Sprint 24 - Day 7

**Test Execution**
- Executed: 298/450 (66%)
- Pass Rate: 95%
- Blocked: 8 tests

**Defects**
- Open: 15 (2 High, 13 Medium)
- Resolved Today: 7
- Average Age: 3.2 days

**Automation**
- Coverage: 72%
- Execution Time: 45 minutes
- Flaky Tests: 3
```

**Weekly Trends**
```markdown
### Week of Nov 1-7, 2025

**Defect Trend** ↓
Week 1: 25 defects
Week 2: 18 defects  (-28%)
Week 3: 15 defects  (-17%)

**Quality Score: 87/100** ↑

Breakdown:
- Test Coverage: 88% (20pts)
- Pass Rate: 94% (20pts)
- Defect Density: 0.15 (18pts)
- DRE: 91% (19pts)
- Velocity: 48 tests/day (10pts)
```

---

## 🔍 Root Cause Analysis

### 5 Whys Technique

```markdown
Bug: Customers unable to complete checkout

Why 1: Payment button not responding
Why 2: JavaScript error on button click
Why 3: Payment service returned unexpected error format
Why 4: API contract changed without updating frontend
Why 5: No integration tests for payment flow

Root Cause: Missing integration tests + lack of API versioning
Action Items:
1. Add integration tests for payment flow
2. Implement API versioning strategy
3. Add contract testing (Pact)
4. Update change management process
```

---

## ✅ Bug Management Checklist

### Bug Reporting
- [ ] Clear, descriptive title
- [ ] Steps to reproduce included
- [ ] Expected vs actual results documented
- [ ] Environment details provided
- [ ] Screenshots/videos attached
- [ ] Severity and priority assigned

### Bug Triage
- [ ] Bug reviewed within 24 hours
- [ ] Severity/priority validated
- [ ] Duplicate check performed
- [ ] Root cause investigated
- [ ] Assigned to appropriate team

### Bug Resolution
- [ ] Fix developed and code reviewed
- [ ] Unit tests added
- [ ] Regression tests performed
- [ ] Deployed to test environment
- [ ] Verified by QA
- [ ] Release notes updated

### Metrics & Reporting
- [ ] Defect metrics tracked weekly
- [ ] Trends analyzed and reported
- [ ] Quality gates monitored
- [ ] Lessons learned documented
- [ ] Process improvements identified

---

## 📚 Resources

- [Azure Boards - Bug Tracking](https://docs.microsoft.com/en-us/azure/devops/boards/backlogs/manage-bugs)
- [IEEE Standard for Software Quality](https://standards.ieee.org/standard/730-2014.html)
- [ISTQB Bug Lifecycle](https://www.istqb.org/)

---

*Last updated: 2025-11-06*
