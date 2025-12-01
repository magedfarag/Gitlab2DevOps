<!--
Guidance for AI coding agents (Copilot / Codegen assistants)
Target: make an AI immediately productive in the Gitlab2DevOps repo
Do not include secrets or attempt network access.
-->

# Copilot / AI Assistant Instructions

Purpose: give concise, repository-specific context so an AI assistant can make safe, useful changes quickly.

Keep responses focused and actionable. When proposing edits, reference exact file paths (e.g. `modules/Core.Rest.psm1`) and small, testable changes, never remove any feature or function unless approved and confirmed.

## Big-picture architecture (what to know first)

- This is a PowerShell-based migration toolkit: entrypoint script is `Gitlab2DevOps.ps1` at repo root.
- Core modules live under `modules/` and `modules/Core.Rest.psm1` contains the REST client logic used across Azure DevOps and GitLab adapters.
- Azure DevOps specific operations are under `modules/AzureDevOps/` (Projects, Repositories, Wikis, WorkItems, Dashboards).
- Migration workspace and outputs live under `migrations/` (self-contained per ADO project). Logs and JSON reports are written to `migrations/{Project}/logs` and `migrations/{Project}/reports`.
- Templates and wiki content are in `modules/Templates/` and `modules/AzureDevOps/WikiTemplates/` — avoid editing templates unless intentionally changing shipped content.

Why this structure: the repo uses modular PowerShell design (one module per responsibility) so changes should be small, localized, and idempotent.

## Key developer workflows (how humans run things)

- Interactive: open PowerShell and run `.\\Gitlab2DevOps.ps1` and follow menu prompts.
- CLI (automated):
  - Preflight: `.\Gitlab2DevOps.ps1 -Mode Preflight -Source "group/project"`
  - Migrate: `.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project" -Project "MyADOProject"`
- Configuration is loaded from `.env` files (via `modules/core/EnvLoader.psm1`) or environment variables. `.env` has priority below command-line params.
- Tests: project uses Pester. Run `Invoke-Pester -Path '.\tests' -Output Detailed`. Use mocks for external API calls.

## Project-specific conventions and patterns

- PowerShell style: Approved verbs and PascalCase function names (see `CONTRIBUTING.md`). Prefer `[CmdletBinding()]` and proper parameter attributes.
- Idempotency: most operations are written to be safe to re-run. Favor checks like "exists? -> create" rather than blind create/delete.
- REST abstraction: use `modules/Core.Rest.psm1` and its wrapper (Invoke-AdoRest / Invoke-GitLabRest equivalents) — don't call `Invoke-RestMethod` directly unless adding a new thin client.
- Logging: use the centralized logging module (`modules/core/Logging.psm1`) so output goes to consistent files under `migrations/*/logs`.

## Integration points and external dependencies

- Azure DevOps REST API (via PAT) — code interacts with endpoints under `modules/AzureDevOps/*.psm1`.
- GitLab REST API v4 — adapters under `modules/GitLab` (or in top-level modules) for fetching project metadata and cloning.
- Git/Git LFS - required on host system; migrations rely on local `git` for mirror/push operations.
- ImportExcel module is an optional dependency for Excel-based work item import (docs and examples reference `Install-Module ImportExcel`).

## What to change and what to avoid

- Safe edits: documentation in `README.md` and files under `docs/`, minor fixes to help text, adding tests, small bugfixes in modules with local unit tests.
- Sensitive/unsafe: do not add secrets into `.env` or checked-in config. Avoid editing templates in `modules/Templates/` unless the change is intentional for a release.
- Large refactors: propose and discuss before implementing. This repo is used for production migrations; keep behavior backward-compatible or add clear flags.

## How to run and validate changes locally (quick checklist)

1. Copy `.env.example` to `.env` and fill minimal values (or set env vars). Do NOT commit `.env`.
2. Run linting/formatting checks (not enforced; follow `CONTRIBUTING.md` conventions).
3. Run targeted Pester tests: `Invoke-Pester -Path '.\tests\ModuleName.Tests.ps1'` and mock external calls.
4. For end-to-end checks, use small non-production GitLab/Azure DevOps test instances and run `-Mode Preflight`.

## Example quick edits (how to compose PRs)

- When fixing a REST error: update specific function in `modules/Core.Rest.psm1`, add unit test in `tests/Core.Rest.Tests.ps1` that mocks `Invoke-RestMethod` and asserts normalized error handling.
- When updating documentation links: update `README.md` and `docs/README.md` and run a repo-wide link check (search for old version strings like `2.1.0`).

## Files to reference when making changes

- Entry & orchestration: `Gitlab2DevOps.ps1`
- REST helpers: `modules/Core.Rest.psm1`
- Azure DevOps adapters: `modules/AzureDevOps/*.psm1`
- Env loader: `core/EnvLoader.psm1` (or `modules/core/EnvLoader.psm1`)
- Logging: `modules/core/Logging.psm1`
- Templates & wikis: `modules/Templates/`, `modules/AzureDevOps/WikiTemplates/`
- Docs: `README.md`, `docs/README.md`, `docs/quickstart.md`, `docs/cli-usage.md`

## When you need human review

- Non-trivial changes to migration logic (git push flows, repository deletion, destructive `-Replace` behavior)
- Changes that modify authentication, token handling, or storage of secrets
- Large UI/UX changes to CLI menu flows

---

If any section is unclear or you want more detail (examples/tests/PR templates), tell me which area to expand and I'll iterate.

## Concrete examples (copyable)

1) Minimal Pester test to add for `Invoke-AdoRest` error handling

Create `tests/Core.Rest.InvokeAdoRest.Tests.ps1` with:

```powershell
Describe "Invoke-AdoRest" {
    Context "when ADO returns 500" {
        It "throws a normalized error" {
            Mock Invoke-RestMethod { Throw "Server error" }
            Mock Write-RestCallLog { }

            { Import-Module -Name .\modules\core\Core.Rest.psm1; Invoke-AdoRest -Method GET -Url '/_apis/projects' -AdoContext @{ } } | Should -Throw
        }
    }
}
```

Notes: Use `Mock` to replace `Invoke-RestMethod` and `Write-RestCallLog`. Run with `Invoke-Pester -Path 'tests/Core.Rest.InvokeAdoRest.Tests.ps1'`.

2) Example: Small REST wrapper change (safe pattern)

- File to edit: `modules/core/Core.Rest.psm1`
- Change: add a custom header for a caller: find `New-AuthHeader` and update to include `X-Tool-Version`.
- Test: add the Pester test above and a small unit test that calls `Get-CoreRestConfig` then `New-AuthHeader` and asserts header contains `X-Tool-Version`.

3) Example: Add a new wiki template usage

- To update shipped templates, modify `modules/Templates/README.template.md` and one page in `modules/AzureDevOps/WikiTemplates/Business/`.
- Use `Initialize-AdoProjectWikis` in `modules/AzureDevOps/Wikis.psm1` to validate changes by running a dry-run (or use `-WhatIf` if supported).

## When to view each key file (quick guide)

- `Gitlab2DevOps.ps1` — startup, menu routing. Inspect when adding or modifying CLI `-Mode` behavior.
- `modules/core/Core.Rest.psm1` — central REST logic, retries, header generation. Inspect for any API-related change.
- `modules/core/EnvLoader.psm1` — `.env` loading and variable expansion. Inspect when changing config priority or adding env keys.
- `modules/core/Logging.psm1` — all migration logs, run-manifest generation. Inspect when changing log formats or output paths.
- `modules/AzureDevOps/*.psm1` — adapters for projects, repos, wikis, work items. Inspect when changing ADO behavior (e.g., policies, wiki creation).
- `modules/GitLab/GitLab.psm1` — GitLab API client and repository preparation. Inspect when fetching repo metadata or cloning behavior.
- `modules/Migration/Initialization/ProjectInitialization.psm1` — orchestrates project init checkpoints. Inspect when changing the migration workflow or adding checkpoints.
- `modules/Migration/Workflows/*.psm1` — Single/Bulk migration flows. Inspect when changing end-to-end orchestration.

## Project structure map (top-level and purpose)

- `Gitlab2DevOps.ps1` — CLI entrypoint and menu.
- `modules/` — All PowerShell modules grouped by responsibility:
  - `core/` — env loader, REST core, logging, config loader
  - `AzureDevOps/` — ADO adapters: Projects.psm1, Repositories.psm1, Wikis.psm1, WorkItems.psm1, Security.psm1
  - `GitLab/` — GitLab adapter and export helpers
  - `Migration/` — orchestration: Initialization, Workflows, TeamPacks, Menu
  - `Templates/` — repository files and wiki page templates shipped with the tool
  - `dev/` — developer helpers and telemetry (not for production changes without tests)
- `migrations/` — runtime workspace created per migration; do not commit runtime artifacts
- `docs/` & `README.md` — user-facing documentation

## Public functions you will most often interact with

  - `Invoke-AdoRest` (modules/core/Core.Rest.psm1) — perform ADO REST calls
  - `Invoke-GitLabRest` (modules/GitLab/GitLab.psm1) — perform GitLab REST calls
  - `Import-DotEnvFile` (modules/core/EnvLoader.psm1) — load `.env`
  - `Invoke-SingleMigration` (modules/Migration/Workflows/SingleMigration.psm1)
  - `Invoke-BulkMigrationWorkflow` (modules/Migration/Workflows/BulkMigration.psm1)
  - `Initialize-AdoProject` (modules/Migration/Initialization/ProjectInitialization.psm1)
  - `New-AdoRepository`, `Remove-AdoDefaultRepository` (modules/AzureDevOps/Repositories.psm1)
  - `Initialize-AdoProjectWikis`, `Set-AdoWikiPage` (modules/AzureDevOps/Wikis.psm1)
  - `Import-AdoWorkItemsFromExcel` (modules/AzureDevOps/WorkItems.psm1)

## Troubleshooting: Malformed Team Descriptor REST API URLs

**Never generate REST API calls to endpoints like:**
```
/E-Services/_apis/teams/-version=7.1?api-version=7.1
```
This is a sign of a missing, empty, or incorrectly substituted team ID/descriptor variable in PowerShell migration logic.

**How to prevent:**
- Always validate team ID/descriptor variables before building REST URLs.
- If the team ID is missing, empty, or invalid, log a clear error and skip the REST call.
- Use defensive coding: do not concatenate or interpolate variables into REST URLs unless they are verified non-empty and valid.
- The correct endpoint for team membership is:
  - `/organization/_apis/teams/{teamId}?api-version=7.1` (for a specific team)
  - `/organization/{project}/_apis/projects/{projectId}/teams?api-version=7.1` (for all teams in a project)
- Add unit tests or Pester tests to assert that no REST calls are made with empty or malformed team IDs.

**If you see a URL with `-version=7.1` or similar, fix the variable substitution and add a test to prevent regression.**

## Quick safety rules for AI edits

- Prefer small, focused changes with tests. If adding a new exported function, update `Export-ModuleMember` in the module file.
- When changing REST behavior, update logging calls (`Write-RestCallLog`) so run manifests capture changes.
- Never commit real credentials. Use `.env.example` and document new config keys in `docs/env-configuration.md`.

---

If you want, I can also auto-generate the minimal Pester test file and a small change example (PR-ready) for you to review. Tell me which example to generate first.
