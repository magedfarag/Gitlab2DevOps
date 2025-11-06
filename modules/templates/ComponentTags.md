# Component Tags & Categorization

This page documents the tagging conventions used to categorize work items, PRs, and code components.

## Technical Components

Use these tags to identify which technical area a work item affects:

- `api` - Backend API/REST services
- `ui` - Frontend/User Interface
- `database` - Database schema/queries
- `cache` - Caching layer (Redis, in-memory)
- `messaging` - Message queues/event bus
- `auth` - Authentication/Authorization
- `integration` - Third-party integrations
- `infrastructure` - DevOps/Cloud infrastructure
- `testing` - Test frameworks/infrastructure
- `docs` - Documentation

## Environment Tags

- `dev` - Development environment
- `staging` - Staging/QA environment
- `prod` - Production environment
- `local` - Local development only

## Technical Categories

- `tech-debt` - Technical debt requiring refactoring
- `refactor` - Code refactoring (no behavior change)
- `performance` - Performance optimization
- `security` - Security improvements/fixes
- `accessibility` - Accessibility (a11y) improvements
- `monitoring` - Logging/monitoring/observability
- `scalability` - Scalability improvements

## Priority Tags

- `urgent` - Needs immediate attention
- `blocked` - Work is blocked by dependency
- `needs-review` - Requires code/design review
- `breaking-change` - Contains breaking changes

## Quality Tags

- `bug` - Bug fix
- `hotfix` - Urgent production fix
- `regression` - Previously working feature broke
- `known-issue` - Documented limitation

## Usage Guidelines

### Work Items

**Add tags** when creating or updating work items:
1. At least one **component tag** (what area)
2. One **environment tag** if environment-specific
3. One **category tag** if applicable
4. **Priority tags** as needed

**Example**: A performance issue in the API affecting production:
- Tags: `api`, `performance`, `prod`

### Pull Requests

**Link work items** to PRs to inherit tags automatically.

**Add PR labels** that mirror tags:
- `component:api`
- `type:performance`
- `priority:urgent`

### Queries

**Filter by tags** in WIQL queries:

```sql
SELECT [System.Id], [System.Title]
FROM WorkItems
WHERE [System.Tags] CONTAINS 'api'
  AND [System.Tags] CONTAINS 'performance'
  AND [System.State] = 'Active'
```

### Dashboards

**Create tag-based widgets**:
- Active tech debt items: `Tags CONTAINS 'tech-debt'`
- Production issues: `Tags CONTAINS 'prod' AND Type = 'Bug'`
- Blocked work: `Tags CONTAINS 'blocked'`

## Tag Best Practices

✅ **DO**:
- Use lowercase tags
- Use hyphens for multi-word tags (`tech-debt`, not `techdebt`)
- Be consistent with existing tags
- Add tags early in work item lifecycle
- Review and clean up obsolete tags

❌ **DON'T**:
- Create random tags without team discussion
- Use spaces in tags (use hyphens)
- Mix capitalization (always lowercase)
- Over-tag (3-5 tags per item is ideal)
