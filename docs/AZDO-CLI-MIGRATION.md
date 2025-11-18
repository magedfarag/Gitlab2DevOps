# Mapping: Current usages -> Official high-level replacements

This file maps the Azure DevOps REST endpoints and current `Invoke-AdoRest` usages in this repository to higher level, more maintainable alternatives (Azure DevOps CLI `az devops`, .NET Azure DevOps SDK, and native git). It also includes example commands/snippets and migration effort guidance.

Generated: 2025-11-17

## How to read this file
- "Current usage" shows the common REST endpoint or pattern called from `Invoke-AdoRest` in this repo (module references are examples).
- "Recommended replacement" shows the preferred high-level approach (az devops CLI, .NET SDK, git, or keep REST with improvements).
- "Example" contains a short PowerShell or shell snippet you can copy.
- "Effort" gives a relative migration effort estimate (Low/Medium/High) to switch that code path to the recommended approach.

---

| Current usage (endpoint / module) | Recommended replacement | Example | Rationale / Notes | Effort |
|---|---:|---|---|---|
| `GET /_apis/projects` (project listing) — used in `modules/Migration/Core/MigrationCore.psm1`, `Projects.psm1` | az devops: `az devops project list` or .NET SDK `ProjectHttpClient.GetProjectsAsync()` | ```powershell
az devops configure --defaults organization=https://dev.azure.com/ORG
az devops project list --output json | ConvertFrom-Json
``` | Official CLI handles auth and pagination; simple JSON output for scripts. Use SDK if you want typed project objects. | Low |
| `GET /_apis/projects/{proj}?includeCapabilities=true` (project details) — init checks | az devops invoke (or keep REST for includeCapabilities) | ```powershell
az devops invoke --route-parameters project=MyProject --area core --resource projects --api-version 7.1 --org https://dev.azure.com/ORG | ConvertFrom-Json
``` | `az devops` provides `invoke` when no first-class command exists; keeps auth and headers consistent. | Low |
| `GET /{project}/_apis/git/repositories` (list repos) — `modules/AzureDevOps/Repositories.psm1` | az devops: `az repos list` or SDK `GitHttpClient.GetRepositoriesAsync()` | ```powershell
az repos list --project "MyProject" --org "https://dev.azure.com/ORG" --output json | ConvertFrom-Json
``` | Use CLI for orchestration; SDK for typed access. For content transfer use native git (below). | Low |
| `GET /{project}/_apis/git/repositories/{id}/commits` — latest commit checks | Keep REST for commit metadata or use SDK `GitHttpClient.GetCommitsAsync()` | SDK example (C#): use GitHttpClient to get commits. For PS, `az repos` has fewer commit helpers — fallback to REST or SDK. | Medium |
| `GET items?path=/README.md` (get file content) — currently using repo items endpoint | Use native git clone/checkout for file operations or `az repos` + `git` | For reading a single file in scripts, REST is fine; for many files or binary content, prefer `git` operations. | Low-Medium |
| `POST /{project}/_apis/git/repositories/{repoId}/pushes` (REST push) — server-side push | Prefer native git mirror/push for full repo import; use REST pushes only for small programmatic commits. | ```powershell
# Mirror + push
git clone --mirror "https://gitlab/.../project.git" "C:\tmp\project.git"
Set-Location "C:\tmp\project.git"
git remote add ado "https://{pat}@dev.azure.com/ORG/Project/_git/RepoName"
git push --mirror ado
``` | `git push --mirror` is faster and reliable for large repositories and preserves refs/LFS. Use REST pushes only for small updates. | Low (but setup for CI) |
| Work items: `POST /{project}/_apis/wit/workitems` and `PATCH /{project}/_apis/wit/workitems/{id}` — `modules/AzureDevOps/WorkItems.psm1` | Use .NET SDK `WorkItemTrackingHttpClient` for typed create/update or keep REST wrapper but use Work Item Batch APIs for bulk creates. | Example (az devops has limited direct create workitem commands) — use REST or SDK. For batch: call `/_apis/wit/$batch` endpoints (see docs). | SDK: Medium; REST (batch): Medium |
| Queries: `POST/GET /{project}/_apis/wit/queries` (Shared Queries) | az devops invoke (or SDK `WorkItemTrackingHttpClient`), or keep REST with better URL encoding helpers | ```powershell
az devops invoke --area wit --resource queries --route-parameters project=MyProject --org https://dev.azure.com/ORG --http-method get | ConvertFrom-Json
``` | `az devops` handles auth; `invoke` is good when no high-level CLI command exists. | Low |
| `GET /_apis/process/processes` (resolve process templates) | Keep REST or use SDK `ProcessHttpClient` | Process APIs are less frequently wrapped by CLI; use REST via `az devops invoke` or SDK. | Low-Medium |
| `GET/POST /{project}/_apis/wit/classificationnodes/areas` (areas/iterations) | az devops invoke or SDK (`ClassificationNode` helpers) | ```powershell
# create area via invoke
az devops invoke --area wit --resource classificationnodes --route-parameters project=MyProject --api-version 7.1 --org https://dev.azure.com/ORG --http-method post --in-file create-area.json
``` | CLI `invoke` is suitable; SDK is cleaner for typed work. | Medium |
| Wiki APIs: `POST /{project}/_apis/wiki/wikis` and `PUT /pages` | Use `az repos` + git for Git-backed wikis (preferred) or `az devops invoke` / REST for code-backed wikis | For Git-backed wiki: treat it as a repo and push via git. For page-level operations, CLI invoke or REST is fine. | Low-Medium |
| Policy configs: `/_apis/policy/configurations` | az devops: some policy commands exist in `az repos policy` extension, or use `az devops invoke`/REST | Use `az devops` where the CLI exposes the specific policy commands; otherwise use `az devops invoke` with REST endpoint. | Medium |
| Security ACLs: `/_apis/securitynamespaces/{ns}/accesscontrolentries` | Keep REST but prefer higher-level group/team APIs; `az devops` may not expose fine-grained ACL operations — use REST carefully. | ACLs are low-level; keep REST wrapper with strong validation. Consider high-level group APIs for most tasks. | Medium-High |
| Test Plan APIs: `/ _apis/testplan/...` | Use REST or SDK `TestPlanHttpClient` | Test plan management is complex; SDK yields typed objects. Consider whether test artifacts must be migrated fully. | Medium-High |

---

## Recommended migration pattern for this repo
1. Keep `modules/core/Core.Rest.psm1` as the canonical low-level client. Improve it (retry/backoff, api-version defaults, telemetry). Use it for low-level or niche endpoints.
2. Add `az devops` shim functions in the codebase for high-level operations. Example strategy:
   - `Invoke-AdoHighLevel -Operation ProjectList` -> calls `az devops project list` and returns PS object.
   - `Invoke-AdoHighLevel -Operation RepoList -Project MyProject` -> `az repos list`.
   - `Invoke-AdoViaAzDevops -RouteParameters ...` -> fallback to `az devops invoke` for any REST route.
3. For repository content migration, implement a `Use-GitMirrorPush` helpers and switch heavy pushes to git mirror commands.
4. For work item bulk creates, replace per-item REST POSTs with the Work Item Batch API or implement a .NET helper that uses `WorkItemTrackingHttpClient`.

## Example helper: `Invoke-AdoViaAzDevops` (PowerShell pattern)
```powershell
function Invoke-AdoViaAzDevops {
    param(
        [string] $Area, [string] $Resource, [hashtable] $RouteParameters, [string] $HttpMethod = 'GET', [string] $InFile = $null
    )
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI `az` not installed or not in PATH.'
    }
    $rp = $RouteParameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } -join ' '
    $cmd = @('az','devops','invoke','--area',$Area,'--resource',$Resource)
    if ($rp) { $cmd += @('--route-parameters',$rp) }
    $cmd += @('--http-method',$HttpMethod,'--output','json')
    if ($InFile) { $cmd += @('--in-file',$InFile) }
    $out = & $cmd 2>&1
    return $out | ConvertFrom-Json
}
```

## Auth and CI notes
- For automation, set `AZURE_DEVOPS_EXT_PAT` environment variable (the az devops extension picks it up) or use `az login` where interactive login is possible.
- When using git remote pushes with PAT, avoid embedding PAT in scripts; prefer CI secret variables or credential managers.

## Migration effort guidance
- Low: `GET` and `LIST` operations (projects, repos, queries) — replaceable by `az devops` quickly.
- Medium: Areas/iterations, wiki pages, and some policy operations — need careful mapping and small code changes.
- High: Security ACLs and custom policy configs — require careful validation; likely keep REST wrapper with stronger safety guards.

---

## Next actionable items (from todo)
- Implement `Invoke-AdoViaAzDevops` shim (not started)
- Add retry/backoff in `Core.Rest.psm1` (not started)
- Add Pester tests for wrapper and shim (not started)
- Decide repo list to convert to `git push --mirror` pattern (not started)

---

If you'd like, I can: 
- Apply a patch to `modules/core/Core.Rest.psm1` to add a fallback shim and initial retry logic (I can draft a minimal safe change and Pester tests), or
- Create a `scripts/` folder with migration helper scripts (`migrate-project-using-az.ps1`, `mirror-repo.ps1`).

Which should I do next? 
