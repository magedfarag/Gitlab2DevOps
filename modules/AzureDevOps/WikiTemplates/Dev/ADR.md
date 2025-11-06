# Architecture Decision Records (ADRs)

Architecture Decision Records document significant architectural decisions made during the project lifecycle.

## What is an ADR?

An ADR is a document that captures an important architectural decision made along with its context and consequences.

## When to Create an ADR

Create an ADR when you make a decision that:
- Affects the structure, non-functional characteristics, dependencies, interfaces, or construction techniques
- Is difficult or expensive to reverse
- Has significant impact on team productivity or system quality
- Introduces new technologies, frameworks, or patterns

## ADR Template

Use this template for new ADRs:

````````````markdown
# ADR-001: [Short Title of Decision]

**Status**: Proposed | Accepted | Superseded | Deprecated  
**Date**: YYYY-MM-DD  
**Deciders**: [List of people involved]  
**Technical Story**: [Link to work item or ticket]

## Context

[Describe the forces at play: technical, business, political, social. 
What is the problem we're trying to solve?]

## Decision

[Describe the decision we made. Use active voice: "We will..."]

## Consequences

### Positive
- [Benefit 1]
- [Benefit 2]

### Negative
- [Drawback 1]
- [Drawback 2]

### Neutral
- [Impact 1]

## Alternatives Considered

### Option A: [Name]
- **Pros**: ...
- **Cons**: ...
- **Why Not Chosen**: ...

### Option B: [Name]
- **Pros**: ...
- **Cons**: ...
- **Why Not Chosen**: ...

## Implementation Notes

[Any specific guidance for implementation]

## References

- [Link to design doc]
- [Link to spike/POC]
- [External resources]
````````````

## Example ADRs

### ADR-001: Use REST API instead of GraphQL

**Status**: Accepted  
**Date**: 2024-01-15  
**Deciders**: Tech Lead, Backend Team  

**Context**: Need to choose API architecture for new service.

**Decision**: We will use REST API with OpenAPI specification.

**Consequences**:
- ✅ Team already familiar with REST
- ✅ Better tooling support
- ❌ More endpoints to maintain

## ADR Index

| Number | Title | Status | Date |
|--------|-------|--------|------|
| ADR-001 | Example decision | Accepted | 2024-01-15 |

---

**Next Steps**: Create a new page under /Development/ADRs for each decision.