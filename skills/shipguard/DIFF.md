# Phase 2 — Diff Triage

Extract changes, map to symbols, tier by reversibility risk.

**Input from Phase 1:**
- `release_repo_path`: repo with release branch checked out
- `base_repo_path`: sibling folder with base branch checked out (separate clone)
- `release_sha`, `base_sha`: HEADs of each

## Step 1: Raw Diff Stats

Use `ctx_batch_execute` to run all git commands — output is indexed in sandbox, not main context:

```
ctx_batch_execute([
  {label: "setup base remote", command: "git -C {release_repo_path} remote add base-temp {base_repo_path} 2>/dev/null || true && git -C {release_repo_path} fetch base-temp {base_branch}"},
  {label: "commit log", command: "git -C {release_repo_path} log base-temp/{base_branch}..HEAD --oneline"},
  {label: "diff stat", command: "git -C {release_repo_path} diff base-temp/{base_branch}...HEAD --stat"},
  {label: "diff shortstat", command: "git -C {release_repo_path} diff base-temp/{base_branch}...HEAD --shortstat"},
  {label: "changed files", command: "git -C {release_repo_path} diff base-temp/{base_branch}...HEAD --name-only"}
])
```

Then `ctx_search(["commit count", "files changed", "insertions deletions"])` to extract stats.

Fallback if remote approach fails:
```
ctx_batch_execute([
  {label: "folder diff", command: "diff -rq {base_repo_path} {release_repo_path} --exclude='.git' | head -100"}
])
```

## Step 2: GitNexus Symbol Mapping

**Primary path — `detect_impact` MCP prompt** (purpose-built for pre-commit analysis):

```
Use prompt: detect_impact
  repo: "{release_repo_path}"
  base_ref: "base-temp/{base_branch}"
```

Returns scoped change analysis: affected processes, risk level, blast radius hints.

**If prompt unavailable, fallback to `detect_changes` tool:**

```
mcp__gitnexus__detect_changes({
  repo: "{release_repo_path}",
  scope: "compare",
  base_ref: "base-temp/{base_branch}"
})
```

Returns: `changed_symbols`, `affected_processes`, `risk`.

**Enrich with cluster context** (read-only resource — cheap):

```
Read: gitnexus://repo/{name}/clusters
```

Cross-reference changed_symbols against cluster cohesion scores. High-cohesion cluster touched = wider blast radius.

**Last-resort fallback** (no GitNexus):

```bash
git -C {release_repo_path} diff base-temp/{base_branch}...HEAD --name-only
```

Then grep for function/class definitions in changed files.

## Step 3: Tier Classification

**Tier 1 — Irreversible** (review first, block on any concern):

| Category | Signals |
|----------|---------|
| DB migrations | `DROP`, `ALTER ... NOT NULL`, `RENAME`, index on large table |
| Schema changes | removed/renamed columns, changed types, removed tables |
| API breaking | removed endpoints, changed request/response shapes |
| Auth changes | permission logic, JWT handling, role resolution |
| Data deletion | `DELETE`, `TRUNCATE`, cascade operations |

**Tier 2 — Hard to Reverse** (deep analysis required):

| Category | Signals |
|----------|---------|
| Shared code | helpers/utilities with >5 callers |
| Middleware | request lifecycle, interceptors |
| Background jobs | signature changes, semantics, idempotency |
| Feature flags | removals, changes to existing flag behavior |
| External integrations | API clients, webhook handlers |

**Tier 3 — Contained** (standard review):

| Category | Signals |
|----------|---------|
| New endpoints | additive APIs (check auth coverage) |
| Internal refactors | renames, moves within module |
| Config additions | new env vars with safe defaults |
| Test changes | test-only files |

## Step 4: Special File Detection

Detect files requiring extra scrutiny:

| Pattern | Action |
|---------|--------|
| `**/migrations/**`, `*.sql` | flag for migration review |
| `*lock*`, `*.sum`, `go.mod`, `package.json` | dependency analysis |
| `*.proto`, `*.graphql`, `openapi.*` | contract change detection |
| `Dockerfile`, `*.yaml` (k8s), `terraform/*` | infra change flag |
| `.env*`, `*config*`, `*secret*` | config change flag |

## Step 5: Diff Analysis Strategy

**Principle**: Raw diff never enters main context. Use `ctx_batch_execute` for data gathering; subagents for reasoning on large diffs.

### Check Diff Size

Extract from ctx index (already captured in Step 1 shortstat).

### Strategy Selection

| Condition | Strategy |
|-----------|----------|
| <300 lines AND <10 files | **Fast path**: main agent reasons directly using ctx_search |
| Everything else | **Subagent path**: parallel subagents, structured output |

### Fast Path (small diffs)

`ctx_search(["changed files", "diff stat"])` to extract file list + symbols. Main agent classifies tiers and extracts signatures directly. Skip subagents.

### Subagent Path (standard)

Dispatch 3 parallel subagents in single message. **Raw diff stays in subagent context, never enters main.**

#### Subagent A: Tier + Signature Analysis

```
Agent({
  subagent_type: "general-purpose",
  prompt: "Analyze diff for tier classification and signature changes.
           
           Repo: {release_repo_path}
           Base repo: {base_repo_path}
           
           PART 1 - Tier Classification:
           Run: git diff base-temp/{base_branch}...HEAD
           
           Tier definitions:
           - Tier 1 (Irreversible): migrations, schema DROP/ALTER, API breaking, auth changes
           - Tier 2 (Hard to reverse): shared code >5 callers, middleware, background jobs
           - Tier 3 (Contained): new endpoints, internal refactors, config additions
           
           PART 2 - Signature Changes:
           For modified files with functions/classes, compare old (base) vs new (release).
           Include: functions, methods, __init__, constructor, initialize, NewXxx
           
           Signature patterns (skip if language not listed):
           - Python: def name(params) -> type, def __init__(self, params)
           - TypeScript/JS: function name(params): Type, constructor(params)
           - Go: func Name(params) (returns), func NewXxx(params)
           - Ruby: def name(params), def initialize(params)
           - Other languages: skip signature table, note in output
           
           Change severity:
           - HIGH: arity change, param removed, type change, required param added
           - MEDIUM: return type narrowed, default changed, param renamed
           - LOW: optional param added, return type widened
           
           Return TWO tables:
           
           TIER TABLE:
           | symbol | file | tier | category | notes |
           
           SIGNATURE TABLE:
           | symbol | kind | file | old_sig | new_sig | change_type | risk |
           
           No raw diff or file contents in output."
})
```

#### Subagent B: Cross-Cutting Checks

```
Agent({
  subagent_type: "general-purpose",
  prompt: "Scan diff for cross-cutting concerns.
           
           Repo: {release_repo_path}
           Base: base-temp/{base_branch}
           
           Check for:
           - Deployment coupling: coordinated deploy needed?
           - Lockfile/dep changes: new deps, major bumps, removals
           - Dependency CVEs: check if updated deps have known vulnerabilities
           
           Return ONLY structured table:
           | concern | file | line | detail | severity |
           
           No raw diff in output."
})
```

### Dispatch Pattern

```python
# Single message, both subagents launch in parallel
Agent(subagent_A_prompt)
Agent(subagent_B_prompt)

# Merge results into:
#   - tier_table (from A)
#   - signature_changes (from A)
#   - cross_cutting_findings (from B)
```

## Output (Merged from Subagents)

### Tier Table (from Subagent A)

| Symbol | File | Tier | Category | Notes |
|--------|------|------|----------|-------|
| `{symbol_name}` | `{file_path}` | `{1\|2\|3}` | `{category}` | `{notes}` |

### Signature Changes (from Subagent B)

| Symbol | Kind | File | Old | New | Change | Risk |
|--------|------|------|-----|-----|--------|------|
| `{symbol_name}` | `{func\|constructor}` | `{file_path}` | `{old_sig}` | `{new_sig}` | `{change_type}` | `{risk}` |

### Cross-Cutting Findings (from Subagent C)

| Concern | File | Line | Detail | Severity |
|---------|------|------|--------|----------|
| `{concern_type}` | `{file_path}` | `{line_num}` | `{detail}` | `{BLOCKER\|WARNING\|INFO}` |

### Special Files (from Step 4)

| Field | Contents |
|-------|----------|
| `migration_files` | list of migration files |
| `dependency_files` | lockfiles/manifests changed |
| `contract_files` | proto/graphql/openapi changed |
| `infra_files` | Docker/k8s/terraform changed |

Hand off all tables to Phase 3.
