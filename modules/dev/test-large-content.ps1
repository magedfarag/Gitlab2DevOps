# Test Large Content
Import-Module .\modules\AzureDevOps\Wikis.psm1 -Force
Import-Module .\modules\core\Core.Rest.psm1 -Force

# Test with a portion of the ProgramOverview content
$testContent = @"
# Program Overview

**Scope.** This overview describes the software development program for this product, including mission, scope, governance, and how multiple agile teams are organized to deliver value.

## Executive Summary

This page provides a high-level overview of the program, its objectives, scope, and organizational structure. Use this as the central hub for program-level information.

---

## Program Mission & Vision

### Mission Statement
Our mission is to provide a secure, reliable, and scalable digital delivery platform that enables product teams to ship high-quality features faster with lower operational risk.

### Vision Statement
Within 3–5 years, this program will be the default way business and technology teams launch new digital services, with predictable delivery, strong compliance, and clear visibility into value and risk.

---

## Program Objectives

### Primary Objectives
1. **Improve delivery reliability**: Shorten lead time for changes and reduce failed releases while keeping teams within sustainable capacity.
2. **Increase product quality**: Reduce production incidents and increase automated test coverage across critical services.
3. **Strengthen stakeholder trust**: Provide transparent, data-driven reporting so executives, business owners, and teams share the same view of status and risk.

### Key Results (OKRs)
| Objective | Key Result | Target | Current | Status |
|-----------|------------|--------|---------|--------|
| Delivery reliability | Reduce lead time for changes | 50% reduction vs. baseline | 20% | 🟡 On Track |
| Product quality | Keep P1 production bugs | < 5 per sprint | 8 | 🔴 At Risk |
| Team health | Maintain team satisfaction score | > 8.0 / 10 | 7.5 | 🟡 On Track |
"@

try {
    Set-AdoWikiPage -Project "edamah" -WikiId "e01b7cc9-aca3-4ef6-83e9-721b623ba1fb" -Path "/TestLargeContent" -Markdown $testContent
    Write-Host "SUCCESS: Large content test passed"
} catch {
    Write-Host "FAILED: $_"
}