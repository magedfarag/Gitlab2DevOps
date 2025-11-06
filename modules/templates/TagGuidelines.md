# Work Item Tag Guidelines

This page documents the standard tags used across the project for consistent work item organization.

## Status & Workflow Tags

### 🚫 Blockers & Issues
- **blocked** - Work is blocked by external dependencies
- **impediment** - Team-level impediment requiring resolution
- **urgent** - Requires immediate attention
- **breaking-change** - Changes that break backward compatibility

### 📋 Review & Validation
- **needs-review** - Ready for code/design review
- **needs-testing** - Requires QA validation
- **needs-documentation** - Documentation updates needed
- **tech-review** - Requires technical architect review

## Technical Area Tags

### 💻 Component Tags
- **frontend** - UI/UX related work
- **backend** - Server-side logic and APIs
- **database** - Database schema or queries
- **api** - API design or changes
- **infrastructure** - DevOps, deployment, infrastructure

### 🏗️ Technical Classification
- **technical-debt** - Code that needs refactoring
- **performance** - Performance optimization work
- **security** - Security-related changes
- **accessibility** - Accessibility improvements

## Work Type Tags

### 🔧 Development Categories
- **feature** - New feature development
- **bugfix** - Bug resolution
- **refactoring** - Code improvement without functional changes
- **tooling** - Development tools and automation
- **investigation** - Research or spike work

### 📚 Documentation & Quality
- **documentation** - Documentation work
- **testing** - Test creation or improvement
- **automation** - Test or process automation

## Usage Guidelines

### How to Use Tags

1. **Apply Multiple Tags**: Work items can have multiple tags
   - Example: `frontend, needs-review, breaking-change`

2. **Use in Queries**: Filter work items by tags
   - Queries → "Contains" operator for tag searches

3. **Board Filtering**: Use tag pills on boards for quick filtering

4. **Consistency**: Use exact tag names (lowercase with hyphens)

### Best Practices

✅ **DO**:
- Use consistent, predefined tags
- Apply tags during work item creation
- Update tags as work progresses
- Use tags in work item templates

❌ **DON'T**:
- Create ad-hoc tags without team discussion
- Use spaces in tag names (use hyphens)
- Mix capitalization styles
- Overuse tags (3-5 tags per item is ideal)

## Creating New Tags

Before creating a new tag:
1. Check if an existing tag fits your need
2. Discuss with the team if creating a new category
3. Document the new tag here
4. Update work item templates if needed

## Tag Queries

Use these queries to find tagged work items:
- **Blocked Work**: `Tags Contains 'blocked'`
- **Technical Debt**: `Tags Contains 'technical-debt'`
- **Needs Review**: `Tags Contains 'needs-review'`
- **Breaking Changes**: `Tags Contains 'breaking-change'`

---

*Last Updated: {{CURRENT_DATE}}*
