# Phase 2 — Diff Triage

Extract changes, map to symbols, and tier by reversibility risk.

## Inputs (from Phase 1)

- `release_repo_path`
- `base_repo_path`
- `release_branch`, `base_branch`
- `release_sha`, `base_sha`

## Step 1: Collect Diff Evidence

Goal: gather enough evidence for triage without sending raw diff into main context.

Required evidence:
- Commit list between base and release
- Diff stat + shortstat
- Changed file list

Example shape only:

```text
ctx_batch_execute([...commit log..., ...diff stat..., ...shortstat..., ...name-only...])
ctx_search(["commit count", "files changed", "insertions deletions"])
```

Fallback:
- If base reference compare fails, compare by SHA (`{base_sha}...{release_sha}`) and continue.

## Step 2: Symbol Mapping

Preferred:
- Use GitNexus `detect_impact` prompt with best available base reference.

Fallback:
- Use `detect_changes` compare scope with best available base reference.

Optional enrichment:
- Read cluster context (`gitnexus://repo/{name}/clusters`) and treat high-cohesion cluster touches as wider blast radius.

Last-resort (no GitNexus):
- Use changed-file list + grep/AST-level symbol extraction.

## Step 3: Tier Classification

### Tier 1 (Irreversible / breaking)

| Category | Signals |
|----------|---------|
| DB migrations | `DROP`, destructive `ALTER`, rename, risky index operations |
| Schema changes | removed/renamed columns/tables, type changes |
| API breaking | removed endpoints, request/response shape breaks |
| Auth changes | permission/JWT/role-resolution logic changes |
| Data deletion | `DELETE`, `TRUNCATE`, cascade effects |

### Tier 2 (Hard to reverse)

| Category | Signals |
|----------|---------|
| Shared code | helpers/utilities with many callers |
| Middleware/runtime path | request lifecycle/interceptors |
| Jobs/workers | signature or semantic changes, idempotency impact |
| Feature flags | behavior change/removal of existing flags |
| External integrations | API clients, webhooks, contracts |

### Tier 3 (Contained)

| Category | Signals |
|----------|---------|
| Additive endpoints | new APIs with auth checks |
| Internal refactors | rename/move within bounded module |
| Config additions | new env/config with safe defaults |
| Test-only changes | tests and fixtures |

## Step 4: Special Files

Flag these paths for extra scrutiny:

| Pattern | Action |
|---------|--------|
| `**/migrations/**`, `*.sql` | migration risk review |
| `*lock*`, `*.sum`, `go.mod`, `package.json` | dependency/major-version change review |
| `*.proto`, `*.graphql`, `openapi.*` | contract change review |
| `Dockerfile`, `*.yaml` (k8s), `terraform/*` | infra/deploy change review |
| `.env*`, `*config*`, `*secret*` | config/secret handling review |

## Step 5: Analysis Strategy

Principles:
- Keep raw diff out of main context.
- Optimize for speed on small diffs, subagents on larger diffs.

Selection:

| Condition | Strategy |
|-----------|----------|
| `<300` changed lines AND `<10` files | Fast path (main agent) |
| Otherwise | Subagent path (parallel) |

### Fast Path

Main agent performs:
- Tier classification
- Signature-change extraction
- Cross-cutting scan

using captured evidence from Steps 1–4.

### Subagent Path

Run 2 subagents in parallel.

Subagent A output requirements:
- `tier_table`
- `signature_changes`

Subagent A rules:
- Apply tier definitions above.
- Compare old vs new signatures for modified functions/methods/constructors.
- Languages: Python, TS/JS, Go, Ruby best-effort; others `N/A`.
- Risk rules:
  - HIGH: arity change, required param add/remove, reorder, variadic add/remove/move, incompatible type change
  - MEDIUM: default change, keyword-sensitive rename, return narrowing
  - LOW: optional param add, return widening
- Positional-order rule: any parameter reorder is HIGH (`positional-order-changed`).

Subagent B output requirements:
- `cross_cutting_findings`

Subagent B checks:
- Deployment coupling / coordinated rollout need
- Dependency changes: new deps, major version bumps, removals

## Output Contract (for Phase 3)

### Tier Table (`tier_table`)

| Symbol | File | Tier | Category | Notes |
|--------|------|------|----------|-------|
| `{symbol_name}` | `{file_path}` | `{1\|2\|3}` | `{category}` | `{notes}` |

### Signature Changes (`signature_changes`)

| Symbol | Kind | File | Old | New | Change | Positional Exposure | Risk |
|--------|------|------|-----|-----|--------|---------------------|------|
| `{symbol_name}` | `{func\|constructor}` | `{file_path}` | `{old_sig}` | `{new_sig}` | `{change_type}` | `{HIGH\|MEDIUM\|LOW\|N/A}` | `{risk}` |

### Cross-Cutting Findings (`cross_cutting_findings`)

| Concern | File | Line | Detail | Severity |
|---------|------|------|--------|----------|
| `{concern_type}` | `{file_path}` | `{line_num}` | `{detail}` | `{BLOCKER\|WARNING\|INFO}` |

### Special Files

| Field | Contents |
|-------|----------|
| `migration_files` | list of migration files |
| `dependency_files` | lockfiles/manifests changed |
| `contract_files` | proto/graphql/openapi changed |
| `infra_files` | Docker/k8s/terraform changed |

Hand off all outputs to Phase 3.
