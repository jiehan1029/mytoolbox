# Phase 3 — Impact Analysis

Blast radius per symbol. GitNexus-powered, cross-repo aware.

**Severity mapping**: CRITICAL risk → BLOCKER (blocks release). HIGH risk on critical path → WARNING.

## GitNexus Primary Path

For each symbol from Phase 2, ordered by tier (1 → 2 → 3):

### Per-Symbol Analysis

```
mcp__gitnexus__impact({
  target: "{symbol_name}",
  direction: "upstream",
  repo: "{release_repo_path}",        // or "@{group_name}" for cross-repo
  crossDepth: 2,              // if group mode
  maxDepth: 3
})
```

Returns:
- `risk`: LOW / MEDIUM / HIGH / CRITICAL
- `byDepth`: affected symbols at each depth
  - d=1: WILL BREAK (direct callers)
  - d=2: LIKELY AFFECTED
  - d=3: MAY NEED TESTING
- `affected_processes`: execution flows impacted
- `affected_modules`: functional areas hit

### Context Enrichment

For HIGH/CRITICAL symbols:

```
mcp__gitnexus__context({
  name: "{symbol_name}",
  repo: "{release_repo_path}"
})
```

Provides:
- All callers/callees
- Process participation
- Cross-references

## Call-Site Verification

**Problem**: "12 callers, MEDIUM risk" tells engineer nothing. Need: which callers are actually risky and why.

**Solution**: For Tier 1/2 symbols with signature changes (from Phase 2), verify top N call/instantiation sites against new signature.

### When to Run

Only when `signature_changes` table (Phase 2) has entries for the symbol. Skip for symbols with unchanged signatures.

### Call-Site Verification Approach

Use `ctx_batch_execute` to read all caller files into sandbox, then let the main agent (or one subagent) reason over `ctx_search` results:

```
ctx_batch_execute([
  {label: "caller:{file1}", command: "sed -n '{line_start},{line_end}p' {caller_file1}"},
  {label: "caller:{file2}", command: "sed -n '{line_start},{line_end}p' {caller_file2}"},
  ...
])
```

Then `ctx_search(["{symbol_name}", "old_param_name", "arg_pattern"])` to find mismatched call sites.

For large caller sets (>10), dispatch one subagent with ctx access:

```
Agent({
  subagent_type: "general-purpose",
  prompt: "Verify call/instantiation sites against new signature.
           
           Symbol: {symbol_name} | Kind: {func|constructor}
           Old signature: {old_sig} | New signature: {new_sig}
           
           Caller files are indexed in context-mode. Use ctx_search to find each call site.
           Callers: {caller_list_from_impact}
           
           Check each site:
           1. Arity match   2. Type compatibility   3. Return handling
           4. Error handling   5. Nullable params   6. Keyword arg names
           For constructors: super().__init__, new ClassName(), factory patterns.
           
           Return rows only (skip compatible sites):
           | caller | site | mismatch_kind | snippet |"
})
```

### Prioritize Callers

Prioritize:

1. **Cross-repo callers** — always verify (can't assume coordination)
2. **Subclasses** — super().__init__ changes break inheritance chain
3. **Different module callers** — higher breakage risk
4. **Test files** — skip (tests should break obviously)
5. **Same-file callers** — lower priority (likely updated together)

Limit: verify all callers in 1, 2, 3 and 5, skip 4 and inform user how many are skiped there.

### Call-Site Verification Table (Output Format)

| Symbol | Caller | Site | Mismatch | Snippet |
|--------|--------|------|----------|---------|
| `{symbol_name}` | `{file:line}` | `{call_code}` | `{mismatch_kind}` | `{explanation}` |

Mismatch kinds (all are breaking):
- `arity` — wrong number of args
- `type` — arg type incompatible
- `nullable-now-required` — optional param now required
- `return-type-changed` — caller doesn't handle new return
- `ignored-error` — new error not caught
- `param-order-swap` — args in wrong order
- `keyword-renamed` — keyword arg name changed
- `super-init-mismatch` — subclass super() call broken


## API Route Analysis

For changed files that define HTTP handlers. Uses `cypher` + `query` + `processes` resource (no dedicated `api_impact` tool exists).

### Route Impact via Cypher

First, fetch schema once: read `gitnexus://repo/{name}/schema` to learn node/edge labels in indexed graph.

Then query route consumers:

```
mcp__gitnexus__cypher({
  repo: "{release_repo_path}",       // or "@{group_name}"
  query: "MATCH (h:Function)-[:HANDLES]->(r:Route) WHERE h.file = $file RETURN r.path, r.method, r.id",
  params: {file: "{handler_file}"}
})
```

Then for each route, find consumers:

```
mcp__gitnexus__cypher({
  query: "MATCH (consumer)-[:CALLS|FETCHES]->(r:Route {path: $path}) RETURN consumer.name, consumer.file",
  params: {path: "{route_path}"}
})
```

**Cross-reference with processes resource** for end-to-end flow context:

```
Read: gitnexus://repo/{name}/processes
```

Filter to processes that include the changed handler — these are the request flows that break.

### Shape Drift Detection

No dedicated tool. Use cypher to compare handler return shape vs consumer access:

```
mcp__gitnexus__cypher({
  query: "MATCH (h:Function {file: $file})-[:RETURNS]->(f:Field) RETURN collect(f.name) AS response_keys",
  params: {file: "{handler_file}"}
})
```

```
mcp__gitnexus__cypher({
  query: "MATCH (c:Function)-[:ACCESSES]->(f:Field {parent: $route}) RETURN c.name, collect(f.name) AS accessed_keys",
  params: {route: "{route_path}"}
})
```

Compare sets: any `accessed_keys` not in `response_keys` = MISMATCH = minimum WARNING.

**Note**: cypher schema varies per indexer version. If schema lacks `RETURNS`/`ACCESSES` edges, fall back to grep on changed handler file + consumer files for shape patterns. Mark as `(grep fallback)` in report.

## Cross-Repo Mode

When `group_name` provided from Phase 1.

### Step 1: Check Staleness, Sync if Needed

```
mcp__gitnexus__group_status({name: "{group_name}"})
```

If any repo stale → `mcp__gitnexus__group_sync({name: "{group_name}"})`.

Check cross-link count:
```
mcp__gitnexus__group_contracts({name: "{group_name}"})
```

Read `crossLinks` field from result.

### Step 2: Choose Analysis Path

| Cross-links | Action |
|-------------|--------|
| >0 | Use GitNexus group mode + `group_query` for flows |
| 0 | Use grep fallback |

**GitNexus group mode:**
```
mcp__gitnexus__impact({
  target: "{symbol}",
  repo: "@{group_name}",
  crossDepth: 2
})
```

**Cross-repo flow search** (replaces some grep needs):
```
mcp__gitnexus__group_query({
  name: "{group_name}",
  query: "{symbol_name}"
})
```

Returns execution flows traversing multiple repos that touch the symbol.

**Grep fallback** (when 0 cross-links):
```bash
for repo in {cross_repos}; do
  git -C "$repo" grep -nE "{symbol_name}|{route_path}"
done
```

Note in report: "Cross-repo: grep fallback (0 bridge links)".

### Step 3: Tier Promotion

| Condition | Action |
|-----------|--------|
| Cross-repo caller in different deploy unit | → Tier 1 |
| Cross-repo caller in same deploy unit | → Tier 2 minimum |

Verify call sites for ALL cross-repo callers (no sampling).

## Symbol Fan-Out

For >5 symbols, use `ctx_batch_execute` to run all gitnexus impact calls at once — results indexed in sandbox:

```
ctx_batch_execute([
  {label: "impact:{symbol1}", command: "gitnexus impact {symbol1} --repo {release_repo_path} --direction upstream --maxDepth 3 --json"},
  {label: "impact:{symbol2}", command: "gitnexus impact {symbol2} --repo {release_repo_path} --direction upstream --maxDepth 3 --json"},
  ...
])
```

Then `ctx_search(["CRITICAL", "HIGH", "affected_processes"])` to surface high-risk symbols without reading all output.

## Tier Promotion Rules

| Condition | Promotion |
|-----------|-----------|
| Tier 3 touches shared utility used app-wide | → Tier 2 |
| Tier 2 on critical path (every request) | → Tier 1 |
| Removes/weakens error handling on external call | +1 tier |
| Cross-repo caller exists | minimum Tier 2 |
| Cross-repo caller in different deploy unit | → Tier 1 |
| Route consumer count >5 (cypher result) | minimum Tier 2 |
| Shape drift mismatch (cypher result) | minimum Tier 2 |
| Touches high-cohesion cluster (clusters resource) | minimum Tier 2 |

## Fallback: git grep

When GitNexus unavailable:

```bash
git -C {release_repo_path} grep -nE "\\b{symbol_name}\\b" -- ':(exclude)vendor' ':(exclude)node_modules' ':(exclude)dist'
```

- Caller count = grep hits - definition sites
- Mark as `(fallback)` in output
- Cannot determine risk automatically — flag for manual review

## Output (Format Specifications)

### Blast Radius Table

| Symbol | Initial Tier | Final Tier | Risk | d1 Callers | Processes | Notes |
|--------|--------------|------------|------|------------|-----------|-------|
| `{symbol_name}` | `{1\|2\|3}` | `{1\|2\|3}` | `{LOW\|MEDIUM\|HIGH\|CRITICAL}` | `{count}` | `{count}` | `{notes}` |

### Call-Site Verification Table (replaces raw counts)

| Symbol | Caller | Site | Mismatch | Snippet |
|--------|--------|------|----------|---------|
| `{symbol_name}` | `{file:line}` | `{call_code}` | `{mismatch_kind}` | `{explanation}` |

### API Impact Table

| Route | Consumers | Risk | Mismatches | Notes |
|-------|-----------|------|------------|-------|
| `{route_path}` | `{count}` | `{LOW\|MEDIUM\|HIGH}` | `{count}` | `{notes}` |

### Cross-Repo Findings (if group mode)

| Symbol | Local Repo | Remote Consumers | Deploy Units | Bridge/Fallback |
|--------|------------|------------------|--------------|-----------------|
| `{symbol_name}` | `{repo_name}` | `{count} in {repo_names}` | `{count}` | `{bridge\|grep fallback}` |

## End-of-Phase Gate

If any CRITICAL risk findings:

```
CRITICAL impact detected:
- {symbol}: {reason}

Continue to safety audit? [y/N]
```

Default NO. User must explicitly proceed.
