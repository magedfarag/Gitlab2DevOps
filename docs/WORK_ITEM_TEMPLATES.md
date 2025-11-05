# Work Item Templates Guide

## Overview

The GitLab to Azure DevOps Migration Tool automatically creates comprehensive work item templates for all Agile process types. These templates standardize how teams capture requirements, track work, and maintain quality across projects.

## Available Templates

### 1. User Story – DoR/DoD
**Purpose**: Capture user requirements with clear value proposition and acceptance criteria

**Key Features**:
- User story format: "As a <role>, I want <capability> so that <outcome>"
- Definition of Ready checklist ensuring stories are well-prepared
- Definition of Done checklist ensuring quality delivery
- Gherkin-style acceptance criteria for clear testing scenarios
- Business value and assumptions sections

**Best Practices**:
- Always fill out the business value to justify the story
- Ensure all DoR items are checked before sprint planning
- Use specific, testable acceptance criteria
- Link to designs or mockups in the description

**Template Fields**:
- **Title**: User story one-liner
- **Description**: Context, DoR/DoD checklists, business value
- **Acceptance Criteria**: Gherkin scenarios (Given/When/Then)
- **Priority**: Business priority (1-4)
- **Story Points**: Effort estimation (Fibonacci scale)
- **Tags**: template;user-story;team-standard

---

### 2. Task – Implementation
**Purpose**: Track specific development work with clear objectives and dependencies

**Key Features**:
- Implementation checklist covering code quality standards
- Dependency tracking for blocking and blocked work
- Technical approach documentation
- Effort estimation in hours

**Best Practices**:
- Break tasks into 8-hour or smaller units
- Clearly document technical dependencies
- Link to parent User Stories or Features
- Update remaining work regularly

**Template Fields**:
- **Title**: Brief description with [TASK] prefix
- **Description**: Objective, approach, checklist, dependencies
- **Priority**: Development priority
- **Remaining Work**: Hours estimation
- **Tags**: template;task;implementation

---

### 3. Bug – Triaging & Resolution
**Purpose**: Systematically capture and resolve defects with complete context

**Key Features**:
- Structured reproduction steps with environment details
- Clear expected vs. actual behavior sections
- Frequency and impact assessment
- Triage-friendly formatting

**Best Practices**:
- Include screenshots or error logs when possible
- Test reproduction steps before submitting
- Provide workarounds if known
- Use consistent severity ratings

**Template Fields**:
- **Title**: Brief description with [BUG] prefix
- **Repro Steps**: Environment, steps, expected/actual behavior
- **Severity**: Impact level (1-4)
- **Priority**: Fix priority
- **Tags**: template;bug;triage-needed

---

### 4. Epic – Strategic Initiative
**Purpose**: Plan and track large strategic initiatives with clear success metrics

**Key Features**:
- Business objective alignment
- Measurable success criteria
- Scope definition (in/out of scope)
- Risk and dependency management
- Timeline and milestone planning

**Best Practices**:
- Define success metrics upfront
- Review scope boundaries with stakeholders
- Identify and mitigate risks early
- Break into smaller Features or Stories

**Template Fields**:
- **Title**: Strategic initiative name with [EPIC] prefix
- **Description**: Objectives, scope, dependencies, timeline
- **Priority**: Strategic priority
- **Effort**: High-level effort estimation
- **Tags**: template;epic;strategic;roadmap

---

### 5. Feature – Product Capability
**Purpose**: Define product capabilities that deliver user value

**Key Features**:
- User value proposition
- Target user identification
- Functional and technical requirements
- Success criteria definition

**Best Practices**:
- Focus on user outcomes, not features
- Include performance and security requirements
- Link to related User Stories
- Define clear acceptance criteria

**Template Fields**:
- **Title**: Feature name with [FEATURE] prefix
- **Description**: Value, users, requirements, success criteria
- **Priority**: Product priority
- **Effort**: Development effort estimation
- **Tags**: template;feature;product;capability

---

### 6. Test Case – Quality Validation
**Purpose**: Systematically validate functionality and quality requirements

**Key Features**:
- Clear test objectives and types
- Structured test steps
- Prerequisites and test data requirements
- Expected results definition

**Best Practices**:
- Write test cases from user perspective
- Include both positive and negative scenarios
- Specify required test data
- Link to requirements being tested

**Template Fields**:
- **Title**: Test scenario name with [TEST] prefix
- **Description**: Objective, prerequisites, expected results
- **Test Steps**: Structured step-by-step instructions
- **Priority**: Test priority
- **Tags**: template;test-case;quality

## Usage Guidelines

### Getting Started
1. **Access Templates**: In Azure DevOps, go to Work Items → New Work Item
2. **Select Template**: Choose from the available templates in the dropdown
3. **Fill Required Fields**: Complete all template sections
4. **Customize as Needed**: Adapt template content to your specific needs

### Team Customization
Teams can extend these templates by:
- Adding custom fields specific to their domain
- Creating additional templates for specialized work types
- Modifying template descriptions to match team processes
- Adding team-specific tags or naming conventions

### Template Maintenance
- **Regular Review**: Review template effectiveness quarterly
- **Team Feedback**: Collect feedback on template usefulness
- **Continuous Improvement**: Update templates based on lessons learned
- **Training**: Ensure new team members understand template usage

## Integration with Agile Processes

### Sprint Planning
- Use **User Story** templates for backlog items
- Break stories into **Tasks** for sprint work
- Estimate effort using template fields

### Defect Management
- Use **Bug** templates for consistent defect reporting
- Leverage severity and priority fields for triage
- Track resolution with structured reproduction steps

### Product Planning
- Use **Epic** templates for quarterly/yearly initiatives
- Break epics into **Features** for release planning
- Define success metrics for measurable outcomes

### Quality Assurance
- Use **Test Case** templates for systematic testing
- Link test cases to requirements being validated
- Maintain test case library for regression testing

## Best Practices

### Consistency
- Always use templates when creating new work items
- Follow naming conventions (prefixes like [BUG], [TASK])
- Use standard tags for filtering and reporting

### Collaboration
- Write descriptions for team understanding, not just yourself
- Include enough context for future team members
- Link related work items to show dependencies

### Quality
- Complete all template sections before moving work to "Active"
- Review work items in team ceremonies (planning, standups)
- Use work item history to track decisions and changes

### Reporting
- Use template tags for dashboard filtering
- Generate reports by work item type and template
- Track template adoption and effectiveness metrics

## Troubleshooting

### Template Not Available
If templates aren't showing up:
1. Verify project uses Agile process template
2. Check team permissions for work item management
3. Contact project administrator if issues persist

### Missing Fields
Some fields may not be available if:
- Process template customizations have been made
- Field permissions restrict access
- Azure DevOps version doesn't support certain fields

### Customization Needs
For additional template needs:
1. Work with Azure DevOps administrators
2. Consider process template customization
3. Create team-specific templates using Azure DevOps template features

## Support

For questions about work item templates:
- Review this guide and team documentation
- Ask in team retrospectives or planning meetings
- Contact project administrators for process changes
- Reference Azure DevOps documentation for advanced customization

---

**Next Steps**: After migration, train your team on these templates and establish team agreements on their usage for maximum collaboration benefit.