# Code Review Checklist

Comprehensive checklist for both code authors and reviewers to ensure high-quality code reviews.

## For Authors: Before Creating PR

### Code Quality

- [ ] **Self-review completed** - Read your own diff line by line
- [ ] **All tests passing** - Run full test suite locally
- [ ] **No console warnings** - Clean build output
- [ ] **Code follows style guide** - Consistent formatting
- [ ] **No commented-out code** - Remove or explain why kept
- [ ] **No debug statements** - Remove console.log, print, etc.
- [ ] **Variable names are clear** - Self-documenting code

### Testing

- [ ] **Unit tests added** - For new functionality
- [ ] **Unit tests updated** - For modified functionality
- [ ] **Edge cases covered** - Null, empty, boundary values
- [ ] **Integration tests** - If touching multiple components
- [ ] **Manual testing done** - Actually used the feature

### Documentation

- [ ] **XML/JSDoc comments** - For public APIs
- [ ] **README updated** - If setup process changed
- [ ] **API docs updated** - If endpoints changed
- [ ] **Wiki updated** - For architectural changes
- [ ] **CHANGELOG entry** - For user-facing changes

### Security

- [ ] **No secrets in code** - Use configuration/environment variables
- [ ] **Input validation** - All user input validated
- [ ] **SQL injection prevented** - Use parameterized queries
- [ ] **XSS prevented** - Escape output, sanitize input
- [ ] **Authentication checked** - Endpoints require auth
- [ ] **Authorization checked** - Users can only access their data

### Performance

- [ ] **No N+1 queries** - Optimize database calls
- [ ] **Appropriate caching** - Cache expensive operations
- [ ] **Large collections paginated** - Don't load all data
- [ ] **No blocking calls** - Use async where appropriate
- [ ] **Resource cleanup** - Dispose connections, streams

### Work Item

- [ ] **Work item linked** - PR references ticket (required)
- [ ] **Description clear** - What/why/testing explained
- [ ] **Screenshots attached** - For UI changes
- [ ] **Reviewers assigned** - 2-3 appropriate reviewers
- [ ] **Labels added** - Mark as feature/bugfix/etc.

## For Reviewers: Review Checklist

### Code Correctness

- [ ] **Logic is sound** - Code does what it claims
- [ ] **Edge cases handled** - Null checks, empty collections
- [ ] **Error handling present** - Try-catch where appropriate
- [ ] **No obvious bugs** - Race conditions, off-by-one errors
- [ ] **Thread-safe** - Concurrent access handled correctly

### Code Quality

- [ ] **Readable code** - Can understand without asking
- [ ] **Appropriate abstractions** - Not over/under-engineered
- [ ] **DRY principle** - No unnecessary duplication
- [ ] **SOLID principles** - Well-structured OOP
- [ ] **Consistent with codebase** - Matches existing patterns
- [ ] **Appropriate complexity** - Not unnecessarily complex

### Testing

- [ ] **Tests are valuable** - Test behavior, not implementation
- [ ] **Tests are maintainable** - Clear arrange-act-assert
- [ ] **Tests are fast** - No unnecessary delays
- [ ] **Test coverage adequate** - Critical paths covered
- [ ] **Tests will catch regressions** - Actually validate functionality

### Performance

- [ ] **No obvious performance issues** - Check algorithms
- [ ] **Database queries optimized** - Indexes, joins appropriate
- [ ] **Memory usage reasonable** - No memory leaks
- [ ] **Network calls minimized** - Batch where possible

### Security

- [ ] **Authentication enforced** - Login required where needed
- [ ] **Authorization enforced** - Permissions checked
- [ ] **Input validated** - Both client and server side
- [ ] **Output escaped** - Prevent XSS
- [ ] **No hardcoded secrets** - Config files not committed
- [ ] **Dependencies secure** - No known vulnerabilities

### Documentation

- [ ] **Code is self-documenting** - Clear naming
- [ ] **Comments explain "why"** - Not "what"
- [ ] **Public APIs documented** - XML/JSDoc present
- [ ] **Complex logic explained** - Non-obvious code has comments

### Architecture

- [ ] **Follows project architecture** - Layers respected
- [ ] **Dependencies appropriate** - Not introducing circular deps
- [ ] **API design consistent** - Follows REST/naming conventions
- [ ] **Database changes safe** - Migrations backward compatible

## Review Feedback Guidelines

### Effective Feedback Format

**Use Clear Categories**:
- **[CRITICAL]**: Must be fixed (blocks merge)
- **[MAJOR]**: Should be fixed (discuss if not)
- **[MINOR]**: Nice to have (optional)
- **[QUESTION]**: Seeking clarification
- **[PRAISE]**: Positive feedback

**Examples**:

✅ **Good Feedback**:
````````````
[CRITICAL] Security: User input not validated
Line 45: userId comes directly from request without validation.
This could allow SQL injection.
Suggestion: Use parameterized query or validate as integer.
````````````

````````````
[MAJOR] Performance: N+1 query detected
Line 120: Loading users in loop will cause N queries.
Consider using Include() or single query with join.
````````````

````````````
[MINOR] Naming: Variable name could be clearer
Line 78: 'temp' doesn't convey purpose.
Consider 'validatedUsers' or 'activeUsers'.
````````````

````````````
[PRAISE] Nice abstraction!
Love how you extracted this into a reusable service.
Makes testing much easier.
````````````

❌ **Poor Feedback**:
````````````
This is wrong.
```````````` 
(Not specific, not actionable)

````````````
Why did you do it this way?
````````````
(Sounds confrontational, no context)

### Feedback Tone

✅ **DO**:
- Be respectful and constructive
- Assume good intent
- Ask questions, don't accuse
- Praise good patterns
- Explain reasoning
- Suggest alternatives
- Offer to pair program for complex issues

❌ **DON'T**:
- Use absolute statements ("This is bad")
- Be condescending ("Obviously this is wrong")
- Nitpick style if auto-formatter exists
- Request changes without explanation
- Block on personal preferences

### Responding to Feedback

**For Authors**:

✅ **DO**:
- Thank reviewer for feedback
- Ask for clarification if unclear
- Explain decisions if needed
- Push back respectfully if you disagree
- Mark resolved after addressing

❌ **DON'T**:
- Take feedback personally
- Get defensive
- Ignore feedback without discussion
- Mark resolved without addressing

## Review Turnaround Time

| PR Type | Target Review Time |
|---------|-------------------|
| **Hotfix** | 2-4 hours |
| **Small PR** (< 200 lines) | 4-8 hours |
| **Medium PR** (200-500 lines) | 1 business day |
| **Large PR** (> 500 lines) | 2 business days |

**If PR is urgent**: Mark with \``urgent\`` label and notify in chat.

## When to Approve

**Approve when**:
- All CRITICAL and MAJOR issues resolved
- Tests passing
- No security concerns
- Code meets quality bar
- Minor issues documented for follow-up

**Request Changes when**:
- Critical security/performance issues
- Tests failing or missing
- Doesn't meet requirements
- Significant refactoring needed

**Comment (no approval) when**:
- Minor suggestions
- Questions for clarification
- Positive feedback only

## Large PR Guidelines

**For PRs > 500 lines**:

1. **Provide Context**: Extra detailed description
2. **Highlight Changes**: Point to key files/changes
3. **Offer Walkthrough**: Schedule 15-min review session
4. **Break Down**: Consider splitting into multiple PRs

**For Reviewers**:
- Schedule dedicated review time
- Review in multiple sessions if needed
- Focus on architecture first, then details
- Use "Start Review" to batch comments

## Automated Checks

Before human review, these should pass:
- ✅ All tests passing
- ✅ Build successful
- ✅ Code coverage > 80%
- ✅ No linting errors
- ✅ Security scan passed
- ✅ Work item linked

## Review Metrics

**Healthy Team Metrics**:
- PR turnaround time: < 24 hours
- Comments per PR: 5-15 (not too few, not too many)
- Review participation: Everyone reviews, not just seniors
- Approval rate: 80%+ on first submission (indicates clear expectations)

---

**Next Steps**: Start reviewing PRs using this checklist. Give constructive feedback!