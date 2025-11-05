# Work Item Templates Guide

## Overview

The GitLab to Azure DevOps Migration Tool automatically creates comprehensive work item templates for all Agile process types. These templates standardize how teams capture requirements, track work, and maintain quality across projects.

**Templates are automatically created AND configured as team defaults during project initialization**, so they auto-populate when creating new work items - no additional configuration needed!

## Quick Start Guide

### ✅ Automatic Configuration (Default Behavior)

**Good news!** Templates are automatically configured during project creation:
- ✅ Templates are created for all 6 Agile work item types
- ✅ Templates are set as team defaults automatically
- ✅ Templates auto-populate when creating new work items

**To Use Templates**:
1. Navigate to Boards → Work Items
2. Click "New Work Item" → Select type (User Story, Task, Bug, etc.)
3. **Template fields automatically populate!** 🎉
4. Customize the pre-filled content
5. Save

**That's it!** No manual configuration needed - templates work immediately after migration.

### 🔧 Manual Configuration (Optional)

If you need to change default templates or add new ones:

#### For Team Administrators
1. Project Settings → Boards → Team configuration → [Your Team]
2. Go to "Templates" tab
3. To change defaults:
   - Find the template you want
   - Click "..." menu
   - Select "Set as team default"
4. Test by creating new work items

#### For End Users (Manual Template Selection)
If you need a different template than the default:
1. Create "New Work Item" → Select type
2. Click "Templates" icon in toolbar
3. Select alternative template
4. Template populates fields
5. Customize and save

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

#### Method 1: Use Template When Creating Work Item
1. **Navigate to Work Items**: In Azure DevOps, go to Boards → Work Items
2. **Create New Work Item**: Click "New Work Item" and select type (User Story, Task, Bug, etc.)
3. **Apply Template**: 
   - Look for the "Templates" button in the toolbar (looks like a document icon)
   - Click it and select from available templates
   - Template fields will populate automatically
4. **Customize**: Adapt the pre-filled content to your specific needs
5. **Save**: Save the work item

#### Method 2: Set Template as Team Default (Recommended)
To automatically use templates when creating work items:

1. **Access Team Settings**:
   - Go to Project Settings (gear icon at bottom left)
   - Navigate to Boards → Team configuration
   - Select your team

2. **Configure Default Templates**:
   - Go to "Templates" tab
   - For each work item type, click the "..." menu
   - Select "Set as team default"
   - Repeat for all work item types you want defaults for

3. **Verify**:
   - Create a new work item of that type
   - It should automatically populate with template fields

#### Method 3: Create from Template Directly
1. **Navigate to Templates**: 
   - Go to Project Settings → Boards → Templates
   - Or from Boards → Work Items → click "Templates" in toolbar
2. **Select Template**: Click on the template you want to use
3. **Click "Create"**: Creates a new work item with template pre-filled

### Quick Access Methods

#### Keyboard Shortcut (After Configuration)
- Press `c` to create new work item
- Select work item type
- Template auto-applies if set as team default

#### From Backlog Board
- Click "+ New Work Item" on any backlog
- Select work item type from dropdown
- Click "Templates" icon to apply template
- Or template auto-applies if set as default

#### From Sprint Board
- Click "+ New item" in any column
- Select work item type
- Template auto-applies if configured as default

### Setting Templates as Team Defaults

**Step-by-Step Configuration**:

1. **Navigate to Project Settings**
   ```
   Project Settings → Boards → Team configuration → [Your Team]
   ```

2. **Go to Templates Tab**
   - You'll see all available templates for your team
   - Templates created by the migration tool will be listed here

3. **Set Default for Each Work Item Type**
   - Find the template you want (e.g., "User Story – DoR/DoD")
   - Click the "..." (More actions) menu
   - Select "Set as team default"
   - Confirm the action

4. **Repeat for All Work Item Types**
   - User Story → "User Story – DoR/DoD"
   - Task → "Task – Implementation"
   - Bug → "Bug – Triaging & Resolution"
   - Epic → "Epic – Strategic Initiative"
   - Feature → "Feature – Product Capability"
   - Test Case → "Test Case – Quality Validation"

5. **Test the Configuration**
   - Create a new work item of each type
   - Verify the template fields are pre-populated
   - Adjust if needed

**Important Notes**:
- Default templates apply only to the selected team
- Each team in a project can have different defaults
- Users can still choose different templates or create blank items
- Default templates improve consistency but don't enforce usage

### Team Customization
Teams can extend these templates by:
- Adding custom fields specific to their domain
- Creating additional templates for specialized work types
- Modifying template descriptions to match team processes
- Adding team-specific tags or naming conventions
- Setting different defaults per team within the same project

### Template Maintenance
- **Regular Review**: Review template effectiveness quarterly
- **Team Feedback**: Collect feedback on template usefulness
- **Continuous Improvement**: Update templates based on lessons learned
- **Training**: Ensure new team members understand template usage
- **Version Control**: Document template changes in team wiki

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
1. **Verify Project Process**: Ensure project uses Agile process template
2. **Check Team Access**: 
   - Go to Project Settings → Teams
   - Verify you're a member of the team
3. **Verify Template Creation**: 
   - Go to Project Settings → Boards → Templates
   - Confirm templates were created successfully
4. **Wait Period**: Templates may take a few minutes to appear after project creation
5. **Contact Admin**: If issues persist, contact project administrator

### Template Not Auto-Applying
If default template isn't applying automatically:
1. **Verify Default Setting**:
   - Project Settings → Boards → Team configuration
   - Check that template is set as team default
2. **Clear Browser Cache**: Sometimes cached settings interfere
3. **Check Team Context**: Ensure you're working in the correct team's backlog
4. **Refresh Page**: Try refreshing the browser
5. **Manual Application**: Use Templates button to apply manually

### Missing Fields
Some fields may not be available if:
- Process template customizations have been made
- Field permissions restrict access
- Azure DevOps version doesn't support certain fields
- Inherited process has removed fields

**Solutions**:
- Check process template customization
- Verify field permissions with admin
- Update to latest Azure DevOps version
- Restore removed fields in process template

### Cannot Set as Team Default
If you can't set a template as default:
1. **Check Permissions**: You need "Team Administrator" or "Project Administrator" role
2. **Verify Template Ownership**: Template must be available to your team
3. **Process Template Match**: Template work item type must exist in project
4. **One Default Only**: Only one template can be default per work item type

### Template Changes Not Saving
If template modifications aren't persisting:
1. **Check Permissions**: Verify you have edit permissions
2. **Required Fields**: Ensure all required fields are filled
3. **Character Limits**: Some fields have maximum character limits
4. **Special Characters**: Avoid unsupported special characters in field values

### Customization Needs
For additional template needs:
1. **Azure DevOps Administrators**: Work with admins for process changes
2. **Process Template Customization**: Consider inherited process customization
3. **Team-Specific Templates**: Create additional templates using Azure DevOps UI
4. **Field Extensions**: Add custom fields through process template
5. **API Integration**: Use Azure DevOps REST API for advanced automation

## Support

For questions about work item templates:
- Review this guide and team documentation
- Ask in team retrospectives or planning meetings
- Contact project administrators for process changes
- Reference Azure DevOps documentation for advanced customization

---

## Quick Reference: Template Configuration

### Option 1: Manual Template Selection (Default Behavior)
```
Create Work Item → Select Type → Click Templates Button → Choose Template → Customize → Save
```
**Use When**: Different templates needed for different scenarios

### Option 2: Team Default Templates (Automatic After Migration)
```
✅ AUTOMATICALLY CONFIGURED - No action needed!
Templates are set as defaults during project creation.
```
**Benefits**: 
- ✅ Automatic template application (configured by migration tool)
- ✅ Consistent team standards from day one
- ✅ Faster work item creation immediately
- ✅ Better onboarding experience
- ✅ Zero configuration required

### Configuration Checklist

**For Project Administrators** (Post-Migration Verification):
- [ ] ✅ Verify templates were created (Project Settings → Boards → Templates)
- [ ] ✅ Confirm templates are set as defaults (should already be done automatically)
- [ ] Test template application by creating sample work items
- [ ] Document any team-specific template customizations needed
- [ ] Train team members on template usage and customization

**For Team Members** (Ready to Use Immediately):
- [ ] Create new work items and see templates auto-populate 🎉
- [ ] Understand available templates for each work item type
- [ ] Customize template content for specific needs
- [ ] Follow team guidelines for template customization
- [ ] Use consistent tagging and naming conventions
- [ ] Provide feedback on template effectiveness

### Navigation Paths

| Task | Path |
|------|------|
| **View Templates** | Project Settings → Boards → Templates |
| **Set Team Defaults** | Project Settings → Boards → Team configuration → [Team] → Templates tab |
| **Create with Template** | Boards → Work Items → New Work Item → Templates button |
| **Edit Template** | Project Settings → Boards → Templates → Select template → Edit |
| **Remove Default** | Team configuration → Templates → [...] → Remove team default |

### Team Adoption Tips

1. **Start Small**: Configure defaults for most-used types first (User Story, Bug, Task)
2. **Gather Feedback**: Ask team what template sections are most/least useful
3. **Iterate**: Improve templates based on actual usage patterns
4. **Document Decisions**: Keep team wiki updated with template standards
5. **Regular Review**: Quarterly review of template effectiveness

---

**Next Steps**: After migration, configure team default templates and train your team on their usage for maximum collaboration benefit. Start with User Story and Bug templates, then expand to other types as the team adopts the practice.