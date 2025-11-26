# Security-First Software Factory – On-Prem Overview

## Table of Contents

### [Business & Product Management](Business/)
- [Business Welcome](Business/01-BusinessWelcome) - Getting started with Azure DevOps
- [Training Quick Start](Business/02-TrainingQuickStart) - Getting up to speed
- [Ways of Working](Business/03-WaysOfWorking) - Team collaboration patterns
- [Value Streams](Business/04-ValueStreams) - Mapping and optimizing delivery flow
- [Agile Requirements](Business/05-Agile_Requirements) - Writing testable user stories
- [Business Analyst Guide](Business/06-guide) - Working in the software factory
- [Product Owner Guide](Business/07-product-owner-guide) - Product ownership in DevSecOps
- [Business Playbook](Business/08-playbook) - Practical day-to-day guidance
- [Product Owner Playbook](Business/09-product-owner-playbook) - PO practical guidance
- [KPIs and Success Metrics](Business/10-KPIsAndSuccess) - Measuring business outcomes
- [Risk Appetite and Guardrails](Business/11-RiskAppetiteAndGuardrails) - Risk management framework
- [Communication Templates](Business/12-CommunicationTemplates) - Standard templates
- [Decision Log](Business/13-DecisionLog) - Recording key decisions
- [Risks and Issues](Business/14-RisksIssues) - Risk tracking
- [Glossary](Business/15-Glossary) - Common terms and definitions

### [Development](Dev/)
- [Development Environment Setup](Dev/01-DevSetup) - Local development environment
- [Developers Guide](Dev/02-guide) - Working in the software factory
- [Developers Playbook](Dev/03-playbook) - Practical day-to-day guidance
- [Git Workflow & Branching](Dev/04-GitWorkflow) - Version control practices
- [Code Review Checklist](Dev/05-CodeReview) - Code review standards
- [CI/CD Pipelines](Dev/06-CICDPipelines) - Pipeline configuration
- [Dependencies Management](Dev/07-Dependencies) - Managing dependencies
- [API Documentation](Dev/08-APIDocs) - API standards
- [Architecture Decision Records](Dev/09-ADR) - Recording architecture decisions
- [Observability for Developers](Dev/10-ObservabilityForDevelopers) - Monitoring and logging
- [Troubleshooting](Dev/11-Troubleshooting) - Common issues and solutions

### [Quality Assurance](QA/)
- [QA Guide](QA/01-guide) - Working in the software factory
- [QA Playbook](QA/02-playbook) - Practical day-to-day guidance
- [Test Strategy](QA/03-TestStrategy) - Testing approach and framework
- [QA Guidelines](QA/04-QAGuidelines) - Quality standards
- [Automation Framework](QA/05-AutomationFramework) - Test automation tools
- [Test Data Management](QA/06-TestDataManagement) - Managing test data
- [Non-Functional Testing](QA/07-NonFunctionalTesting) - Performance, security, and load testing
- [Bug Lifecycle](QA/08-BugLifecycle) - Bug tracking and resolution

### [Security](Security/)
- [Security Guide](Security/01-guide) - Working in the software factory
- [Security Playbook](Security/02-playbook) - Practical day-to-day guidance
- [Security Policies](Security/03-SecurityPolicies) - Security standards and policies
- [Security Requirements](Security/04-SecurityRequirements) - Security requirements
- [Threat Modeling](Security/05-ThreatModeling) - Threat modeling process
- [Security Testing](Security/06-SecurityTesting) - Security testing practices
- [Vulnerability Management](Security/07-VulnerabilityManagement) - Handling vulnerabilities
- [Incident Response](Security/08-IncidentResponse) - Security incident handling
- [Secret Management](Security/09-SecretManagement) - Managing secrets and credentials
- [Security Champions](Security/10-SecurityChampions) - Security champions program
- [Compliance](Security/11-Compliance) - Regulatory compliance

### [Management & Governance](Management/)
- [Management Guide](Management/01-guide) - Working in the software factory
- [Management Playbook](Management/02-playbook) - Practical day-to-day guidance
- [Program Overview](Management/03-ProgramOverview) - Program management
- [Roadmap](Management/04-Roadmap) - Product roadmap management
- [Capacity Planning](Management/05-CapacityPlanning) - Resource and capacity planning
- [Sprint Planning](Management/06-SprintPlanning) - Sprint planning and execution
- [Metrics Dashboard](Management/07-MetricsDashboard) - Tracking key metrics
- [Retrospectives](Management/08-Retrospectives) - Continuous improvement
- [Change Management and Release Governance](Management/09-ChangeManagementAndReleaseGovernance) - Change management
- [Stakeholder Communications](Management/10-StakeholderComms) - Communication strategies
- [RAID Log](Management/11-RAID) - Risks, Assumptions, Issues, Dependencies

### [Other Roles](OtherRoles/)
- [Enterprise Architect Guide](OtherRoles/01-enterprise-architect-guide) - Architecture guidance
- [Enterprise Architect Playbook](OtherRoles/02-enterprise-architect-playbook) - Architecture practices
- [Infrastructure Guide](OtherRoles/03-infrastructure-guide) - Infrastructure management
- [Infrastructure Playbook](OtherRoles/04-infrastructure-playbook) - Infrastructure practices
- [Platform Guide](OtherRoles/05-platform-guide) - Platform engineering
- [Platform Playbook](OtherRoles/06-platform-playbook) - Platform practices
- [Operations Guide](OtherRoles/07-operations-guide) - Operations management
- [Operations Playbook](OtherRoles/08-operations-playbook) - Operations practices
- [SOC Guide](OtherRoles/09-soc-guide) - Security operations
- [SOC Playbook](OtherRoles/10-soc-playbook) - SOC practices
- [Support Guide](OtherRoles/11-support-guide) - Support processes
- [Support Playbook](OtherRoles/12-support-playbook) - Support practices
- [Project Manager Guide](OtherRoles/13-project-manager-guide) - Project management
- [Project Manager Playbook](OtherRoles/14-project-manager-playbook) - PM practices
- [Vendors Guide](OtherRoles/15-vendors-guide) - Vendor management
- [Vendors Playbook](OtherRoles/16-vendors-playbook) - Vendor practices

### [Best Practices](BestPractices/)
- [Best Practices Overview](BestPractices/01-BestPractices) - Cross-cutting best practices
- [Architecture and Design Guidelines](BestPractices/02-ArchitectureAndDesignGuidelines) - Design principles
- [Testing Strategies](BestPractices/03-TestingStrategies) - Testing best practices
- [Error Handling](BestPractices/04-ErrorHandling) - Error handling patterns
- [Logging Standards](BestPractices/05-LoggingStandards) - Logging best practices
- [Monitoring and Alerting Standards](BestPractices/06-MonitoringAndAlertingStandards) - Monitoring practices
- [Performance Optimization](BestPractices/07-PerformanceOptimization) - Performance best practices
- [Documentation Guidelines](BestPractices/08-DocumentationGuidelines) - Documentation standards

---

## 1. Purpose

This page explains how our enterprise **Software Factory** works on-premises and what it means for every team:

- One **standard way of building, testing, securing and deploying** software.
- All flows anchored on **Azure DevOps Server 2022**, **OpenText Fortify**, **HashiCorp Vault**, **Red Hat OpenShift**, and our existing **AD / WAF / SIEM** stack.
- A transformation roadmap over **24 months** with clear expectations per phase.

If you are a developer, tester, product owner, architect, security engineer, operator, or support analyst, this is your starting point.

---

## 2. What the Software Factory Is

The Software Factory is our **shared on-premises DevSecOps platform**:

- **DC-A (DevSecOps Platform)**  
  - Azure DevOps Server: Git repos, Boards, Pipelines, Artifacts, Test Plans.  
  - OpenText Fortify: SAST, SCA, DAST (WebInspect) integrated into pipelines.  
  - HashiCorp Vault: all app secrets, certificates and DB credentials.  
  - OpenShift clusters for dev/test/pre-prod workloads.  
  - SIEM + monitoring (Splunk/ELK, Prometheus/Grafana, Application telemetry).

- **DC-B (Air-Gapped Production)**  
  - Isolated OpenShift production clusters.  
  - Quarantine zone for signed artifacts, re-scan and approvals.  
  - One-way transfer (data diode) from DC-A with strict verification and logging.

All software products pass through the same **secure pipeline stages**: work item → code → pull request → CI build with tests & security scans → signed artifact → automated deployments through test and pre-prod → approval → production (DC-A) → air-gapped production (DC-B).

---

## 3. How Work Flows (Idea to Air-Gapped Prod)

At a high level, every product follows this lifecycle:

1. **Demand and Backlog**
   - Business and product roles define Epics, Features and User Stories in Azure Boards.
   - Each change has a clear business outcome and acceptance criteria.

2. **Secure Design and Planning**
   - Threat modelling for non-trivial changes.
   - Architecture review where patterns, reference architectures and security controls are applied.
   - Non-functional requirements (availability, performance, auditability, security) agreed early.

3. **Development and Local Testing**
   - Developers work in **short-lived branches** linked to work items.
   - Local unit tests and basic security checks run before pushing.

4. **Pull Request and CI Validation**
   - Pull Request triggers a **PR validation pipeline**:
     - Build, lint, fast unit tests.
     - SAST + secrets scan + SCA on dependencies.
   - PR cannot merge until all checks pass and peer reviews complete.

5. **Main Branch CI and Artifact Signing**
   - On merge to `main`, full CI pipeline runs:
     - Extended tests, packaging, SBOM generation.
     - Artifact signing; SBOM and scan results attached as evidence.
   - Signed artifacts stored in **Azure Artifacts** or the internal container registry.

6. **Automated Deployments in DC-A**
   - **Dev/Test:** smoke tests, integration tests, DAST in non-prod.
   - **Pre-Prod:** performance tests, resilience tests, operational runbooks validated.
   - Approvals (Product Owner, Platform/Ops, Security) are recorded in Azure DevOps and ITSM.

7. **Production in DC-A**
   - Standard deployment strategies: rolling, blue-green, canary (where supported).
   - Monitoring, logging and SLOs enforced in OpenShift plus SIEM.

8. **Air-Gap Transfer to DC-B**
   - Only **signed, scanned, approved** artifacts move from DC-A to DC-B via one-way transfer.
   - DC-B re-scans artifacts, verifies signatures and SBOMs, and then deploys using the same automation patterns.
   - All actions linked back to work items, tests, approvals and change records.

---

## 4. What Stays Central vs. What Teams Own

**Centralized (Platform / Security / Infra / SOC / Compliance)**

- Azure DevOps, Fortify, Vault, OpenShift, SIEM, WAF, reverse proxies.
- Pipeline templates and golden patterns for:
  - Build, test, scan, sign, deploy, promote, roll back.
- Security policies, secure-by-default baselines, vulnerability thresholds, break-glass processes.
- Change management policies, CAB, regulatory alignment and evidence requirements.
- Shared monitoring, logging and incident management processes.

**Delegated to Product-Aligned Teams**

- How to break down features into user stories and tasks.
- System design within approved patterns.
- Automated tests (unit, integration, E2E, performance) for their products.
- Day-to-day operation of the service within defined SLOs, with support from Ops/SRE.
- Continuous improvement of pipelines (within guardrails).

---

## 5. Transformation Phases (What to Expect)

The Software Factory rollout is phased:

1. **Foundation (Months 0–3)**  
   - Exec kick-off, department briefings, FAQs.  
   - Platform team training on Azure DevOps + Fortify + Vault.  
   - Initial governance, RACI and policy baselines.

2. **Pilot (Months 4–8)**  
   - 2 pilot teams use full factory end-to-end.  
   - Git + PR labs, test automation training, IaC workshops, secure coding & SAST labs.  
   - First DORA metrics and security metrics baselines.

3. **Hardening (Months 8–12)**  
   - Fix issues from pilot, tune gates, improve performance and DX.  
   - Expand air-gap workflows, legacy hosting patterns, and compliance evidence automation.

4. **Enterprise Rollout (Months 12–18)**  
   - Most teams onboard (target ~80% of apps).  
   - Legacy manual release paths sunsetted.  
   - Train-the-trainer model and mandatory factory usage for new changes.

5. **Optimization (Months 18–24)**  
   - Advanced capabilities (chaos testing, service mesh, GitOps).  
   - External certifications and audits.  
   - Continuous improvement based on DORA and security metrics.

Each role guide (below) explains what these phases mean for you in concrete actions.

---

## 6. Who Does What (Short Version)

- **Dev / QA:** own code, tests, and local quality; use pipelines and Vault correctly.  
- **PO / PM / BA / EA:** own value, scope, architecture decisions and prioritisation; enforce small, testable changes.  
- **Platform / Infra / Ops:** own platform reliability, golden patterns, environment automation and incident response.  
- **Security / SOC / Compliance:** own policies, gates, monitoring, investigation, and regulatory evidence.  
- **Support:** front-line triage, user feedback, link incidents back to work items and backlog.

Read your role-specific page next.
