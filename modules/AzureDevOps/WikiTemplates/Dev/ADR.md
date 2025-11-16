# Architecture Decision Records (ADRs)

**Scope.** This page describes Architecture Decision Records (ADRs) for software architecture and platform decisions in this project. Each ADR captures a significant technical choice, the context, and its consequences.

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

---

## 📚 References

- [Architecture Decision Records (ADR) Overview](https://adr.github.io/)
- [Lightweight ADR Template](https://github.com/joelparkerhenderson/architecture-decision-record)
- [When to Use ADRs](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [Y-Statements for ADRs](https://medium.com/olzzio/y-statements-10eb07b5a177)
- [ADR Tools](https://github.com/npryce/adr-tools)

### Storage and naming conventions

- Store ADR files under `/Development/ADRs` in the same repository as the code.
- Use a consistent naming convention, for example: `ADR-001-short-title.md`.
- Keep an ADR index in the decision log and link each ADR back to the related work items.
- When an ADR is superseded, update its status and add a link to the new ADR.
