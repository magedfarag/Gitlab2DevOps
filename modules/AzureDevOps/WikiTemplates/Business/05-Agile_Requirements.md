# 05. Guide to Writing End-to-End Agile Requirements in Azure DevOps

## 1. Introduction

This guide explains how to write end-to-end agile requirements in Azure DevOps in a way that:

- Focuses on **business value**, not on technical layers (backend / frontend / database).
- Uses **user stories** that can be implemented and tested within a single sprint.
- Uses Excel / CSV and Azure DevOps correctly, without spreading bad habits in how requirements are written.

> **Audience:** Product Owners, business analysts, architects, developers, testers, team leads, and managers.  
> **Scope:** All Azure DevOps projects, with examples taken from supplier-portal style systems, but applicable to other domains.

You can publish this document as a wiki page in Azure DevOps or in any internal knowledge base.

---

## 2. What requirements mean in Agile

The 2020 Scrum Guide defines the **Product Backlog** as an *emergent, ordered list of what is needed to improve the product*. It is the single source of work undertaken by the Scrum Team. (Schwemmer and Sutherland, 2020; Scrum.org, no date)

This has important consequences:

- Backlog items must describe **what is needed**, not all implementation details.
- Items are ordered by **value, risk, and learning**, not by architecture layers.
- Items are refined until they are **clear, small, and ready** to be done in a sprint.

In Azure DevOps, we usually represent this as:

- **Epic** – a large initiative or product goal.
- **Feature** – a coherent capability under an epic.
- **User Story** – a small piece of value that can be delivered in one sprint.
- **Task** – technical steps chosen by the Developers during sprint planning.
- **Test Case** – detailed test procedure, when you want explicit test design.

The key point:  

- **Epics / Features / User Stories** talk about **behaviour and value**.  
- **Tasks** talk about **implementation**, and they should not be hard-coded in your requirements Excel template.

---

## 3. A simple structure in Azure DevOps

A minimal but effective structure for training looks like this:

- **Epic:** “Supplier onboarding and account management”.
- **Features (examples):**
  - Register supplier account.
  - Secure login and password reset.
  - Manage supplier company profile.
  - Manage customers and projects.
  - Manage bank accounts and credit terms.
  - Manage documents, attachments and compliance.
- **User Stories:** for each feature, a set of vertical slices that represent real behaviour from the user’s point of view.

In Excel / CSV, you can include columns such as:

- `Work Item Type` (Epic / Feature / User Story / Test Case)
- `Title`
- `Description`
- `Area Path`
- `Iteration Path`
- `Story Points`
- `Business Value`
- `State`
- `Tags`

Azure DevOps requires at least `Work Item Type` and `Title` to import items, but the additional fields make the backlog more useful for planning and reporting. (Microsoft, 2025a; Microsoft, 2025b)

For training, you can also include helper columns like `LocalId` and `ParentLocalId` to make the hierarchy obvious, even if Azure DevOps itself does not use those fields.

---

## 4. Writing user stories: template and quality criteria

### 4.1. The basic template

A widely used template for user stories is:

> **As a** \<type of user\> **I want** \<goal\> **so that** \<reason\>.

This pattern has been popularised by authors such as Mike Cohn and is referenced in many agile guides and tools. (Cohn, no date; IBM, no date)

Example from a supplier context:

> As a new supplier, I want to create an account using official company details and an official email address so that I can track my requests and deal with the ministry online.

This forces three essential questions:

1. **Who** is the user or stakeholder?
2. **What** do they want to achieve?
3. **Why** does it matter from a business point of view?

If the story cannot answer all three clearly, it is not ready.

### 4.2. The INVEST checklist

Bill Wake introduced the **INVEST** mnemonic as a quick way to evaluate the quality of a Product Backlog Item: Independent, Negotiable, Valuable, Estimable, Small, and Testable. (Wake, 2003; Agile Alliance, no date; Wikipedia, no date)

You can use INVEST as a checklist:

- **Independent:** the story does not depend heavily on other stories in the same sprint.
- **Negotiable:** it is not a contract; details can change after discussion.
- **Valuable:** it provides visible value to a user or stakeholder.
- **Estimable:** the team can size it relative to other work.
- **Small:** it is small enough to complete within one sprint.
- **Testable:** you can define clear acceptance criteria and verify them.

In practice, during refinement sessions, ask: “Does this story pass INVEST?”. If it fails on more than one letter, you probably need to split or rewrite it.

---

## 5. Vertical slices vs CRUD and backend/frontend/DB stories

### 5.1. What is a vertical slice?

A **vertical slice** is a backlog item that cuts through all necessary layers (UI, business logic, data storage, integration) to deliver observable behaviour to a user.

Agile training material and story-splitting guides consistently recommend vertical slicing over horizontal slicing by technical layer. (Humanizing Work, no date; Visual Paradigm, no date; monday.com, 2025)

Example:

> “Log in as a supplier with a verified account and record the time of last successful login.”

This slice involves:

- The login screen.
- Authentication logic.
- Updating the “last login” field in storage.
- Optional security/audit logging.

### 5.2. Why CRUD and “backend/frontend/db” patterns are harmful in the backlog

Examples of common anti-patterns:

- “Create customer data”
- “Update customer data”
- “View customer data”

or:

- “Backend – suppliers”
- “Frontend – suppliers”
- “Database – suppliers”

These are **horizontal slices** and have several problems:

1. They encourage **hand-offs** between roles instead of collaboration on one shared outcome.
2. They make it hard to **order by value** because each piece alone has no user-facing value.
3. They delay **learning**: nothing is “done” until multiple layers are finished and integrated.
4. They hide **business risk** behind a series of technical steps that all look the same.

User-story splitting guides explicitly warn against using layers (UI, API, database) as story boundaries; they recommend slicing by workflow, business rule, or scenario instead. (Humanizing Work, no date; Visual Paradigm, no date)

A strong operating rule for your team:

> If you see “backend / frontend / db” in the **Title** of a user story, treat it as a design smell.

### 5.3. Rewriting a CRUD trio into a single vertical story

**Before (three horizontal items):**

- “Create organisation data”
- “Edit organisation data”
- “View organisation data”

**After (one vertical story with richer acceptance criteria):**

> **Story**  
> As a supplier account manager, I want to manage organisation data (add / edit / view) from a single screen so that the organisation’s details held by the ministry remain accurate and up to date.  
>  
> **Acceptance criteria (example):**  
> 1. When all mandatory organisation fields are valid, a new record can be created and a clear success message is shown.  
> 2. Only allowed fields can be edited; all changes are logged with who made them and when.  
> 3. The user can search for an organisation by name or registration number and see its details within a reasonable response time on realistic data volumes.

Same behaviour, but now expressed as a real outcome. The team still implements UI, validation, data, and tests. They just deliver it in one slice.

---

## 6. Acceptance criteria and test cases

A user story without **acceptance criteria** is ambiguous. Acceptance criteria define **when** the story is done.

A common format, used in Behaviour‑Driven Development (BDD), is **Given / When / Then**. (SmartBear, no date; Cohn, no date)

Example for “Reset password”:

> **Acceptance criteria:**  
> 1. The user can request password reset by entering only the registered email address.  
> 2. If the email is registered, the system sends a reset link that is valid for a limited time (for example, 30 minutes).  
> 3. The system does not reveal whether the email exists or not (to protect user privacy).  
> 4. After the user sets a new password successfully, the old reset link becomes invalid and the event is written to the audit log.

In Azure DevOps:

- Put the acceptance criteria in the **Description** of the **User Story**.
- Optionally create **Test Cases** that link to the story and refer to those criteria instead of duplicating them.

This keeps the story **testable** (the “T” in INVEST) and reduces duplication between requirements and tests.

---

## 7. Estimation and business value: making the numbers meaningful

### 7.1. Story points should be relative, not cosmetic

Agile teams often estimate using **story points** based on a Fibonacci‑like sequence (1, 2, 3, 5, 8, 13). The point is not precision; the point is **relative comparison**. (Agile Alliance, no date; Mike Cohn, no date)

If every story in the Excel file has:

- `Story Points = 5`  
- `Business Value = 70`

then:

- You cannot see which stories are small and low risk.
- You cannot model capacity or forecast based on velocity.
- You cannot sensibly prioritise by **value vs effort**.

### 7.2. A practical practice for the training backlog

For the training example:

- Use a **small set** of story point values (e.g. 1, 2, 3, 5, 8).
- Make sure stories within the same feature have **different** sizes.
- Use `Business Value` to distinguish between:
  - Critical flows (account creation, secure login, legal documents).
  - Important but not critical flows (reporting, bulk management).
  - Nice‑to‑have flows (export to Excel, cosmetic improvements).

This teaches the team that numbers are there to support decisions, not to fill mandatory fields.

---

## 8. Using Excel / CSV with Azure DevOps without spreading bad habits

Microsoft documents two main ways to use Excel with Azure DevOps work items: **flat lists** and **tree lists**. (Microsoft, 2025a; Microsoft, 2025b)

### 8.1. What to include in the training Excel

Your training file should contain:

- **Epics** with clear business intent.
- **Features** under each epic, describing coherent capabilities.
- **User Stories** that are vertical slices with good acceptance criteria.
- A limited number of **Test Cases** as examples, each linked to a story.

It **should not contain**:

- Pre‑created tasks named “Develop / Test / DB / UI” for every story.
- Stories that are only about one layer (backend / frontend / database).
- Empty or trivial test cases that add no information beyond “test this story”.

According to Scrum, the Developers decide how to break Product Backlog Items into tasks during Sprint Planning; this is not pre‑defined by an external template. (Schwemmer and Sutherland, 2020; Scrum.org, no date)

So, use Excel and import mainly for **Epics, Features, User Stories, and example Test Cases**. Let the team create tasks directly within Azure DevOps when they plan the sprint.

---

## 9. Review checklist for the team

Before accepting backlog items as “ready”, use this checklist:

1. **Perspective:**  
   Is the story written from a user or stakeholder point of view (“As a \<user\> I want \<goal\> so that \<reason\>”), instead of describing only a technical layer?

2. **Value:**  
   Can someone outside the team understand the business value in one minute?

3. **Slice:**  
   Is this a **vertical** slice that you can demonstrate at the end of the sprint?

4. **INVEST:**  
   Does the story satisfy Independent, Negotiable, Valuable, Estimable, Small, Testable?

5. **Acceptance criteria:**  
   Are there clear, concrete acceptance criteria, or just a vague statement?

6. **Numbers:**  
   Do `Story Points` and `Business Value` tell you something about size and impact, or are they all identical?

7. **Structure:**  
   Does the story sit in a logical place in the Epic / Feature hierarchy?

If an item fails on several of these points, do not bring it into a sprint. Bring it back into refinement and fix it first.

---

## 10. References

Agile Alliance (no date) *Estimation*. Available at: https://www.agilealliance.org (Accessed: 21 November 2025).

Cohn, M. (no date) *User stories and user story examples*. Mountain Goat Software. Available at: https://www.mountaingoatsoftware.com (Accessed: 21 November 2025).

Humanizing Work (no date) *The Humanizing Work guide to splitting user stories*. Available at: https://www.humanizingwork.com (Accessed: 21 November 2025).

IBM (no date) ‘User stories’, *IBM Documentation*. Available at: https://www.ibm.com (Accessed: 21 November 2025).

Microsoft (2025a) ‘Import work items from CSV’, *Azure DevOps Services Documentation*. Available at: https://learn.microsoft.com (Accessed: 21 November 2025).

Microsoft (2025b) ‘Bulk add or modify work items with Excel’, *Azure DevOps Services Documentation*. Available at: https://learn.microsoft.com (Accessed: 21 November 2025).

monday.com (2025) ‘Vertical slice explained: build better features faster’, *monday.com Blog*. Available at: https://monday.com (Accessed: 21 November 2025).

Schwemmer, K. and Sutherland, J. (2020) *The Scrum Guide: The definitive guide to Scrum*. Available at: https://scrumguides.org (Accessed: 21 November 2025).

Scrum.org (no date) ‘What is a Product Backlog?’. Available at: https://www.scrum.org (Accessed: 21 November 2025).

SmartBear (no date) ‘What is behavior-driven development (BDD)?’. Available at: https://smartbear.com (Accessed: 21 November 2025).

Visual Paradigm (no date) ‘User story splitting – vertical slice vs horizontal slice’. Available at: https://www.visual-paradigm.com (Accessed: 21 November 2025).

Wake, B. (2003) ‘INVEST in Good Stories, and SMART Tasks’. In: *INVEST (mnemonic)*, Wikipedia. Available at: https://www.wikipedia.org (Accessed: 21 November 2025).

Wikipedia (no date) ‘User story’. Available at: https://www.wikipedia.org (Accessed: 21 November 2025).

Mike Cohn (no date) ‘Estimation and story points’. Mountain Goat Software. Available at: https://www.mountaingoatsoftware.com (Accessed: 21 November 2025).
