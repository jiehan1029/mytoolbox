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
           Positional exposure: {HIGH|MEDIUM|LOW|N/A} (from Phase 2 signature table)
           
           Caller files are indexed in context-mode. Use ctx_search to find each call site.
           Callers: {caller_list_from_impact}
           
           Check each site:
           1. Arity match
           2. Positional order — FIRST determine if call is positional or keyword/named:
              - Positional: foo(a, b, c) — GO/RUST/C/C#/early-JS always positional
              - Keyword: foo(x=a, y=b) Python/Ruby, foo({x: a}) TS object pattern
              - Mixed: foo(a, y=b) — positional params still shift if order changed
              For EVERY positional or mixed call: map arg positions to new param order.
              Any param that moved position = positional-reorder mismatch even if arity unchanged.
           3. Variadic/spread: *args, **kwargs, ...rest, ...spread — does unpacking still land
              in the right parameter after reorder?
           4. Type compatibility
           5. Return handling
           6. Error handling
           7. Nullable params
           8. Keyword arg names (renamed params break keyword callers)
           For constructors: super().__init__, new ClassName(), factory patterns.
           
           For each d1 caller, also classify as:
           - TRANSPARENT: forwards args unchanged (*args/**kwargs/...rest/...spread)
           - NAMED-WRAPPER: calls changed fn with its own named params (chain stops here)
           - TRANSFORMER: reshapes/adapts args before forwarding (chain stops here)
           
           For TRANSPARENT callers: chase their callers (d2) from the blast radius data.
           Callers at d2: {d2_caller_list_from_impact_byDepth}
           Check each d2 caller's call to the transparent wrapper — apply same positional
           checks as if d2 were calling the changed fn directly (args flow through unchanged).
           Report as chain-propagation with via: {d1_wrapper@file:line}.
           Stop at d3. If d3 reached without finding a transformer, note: 'chain not fully traced'.
           
           Return rows only (skip compatible sites):
           | caller | depth | site | mismatch_kind | via (if chain) | snippet |"
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
- `positional-reorder` — param moved to different position; positional caller silently passes wrong value (arity may be unchanged)
- `variadic-shift` — *args / ...rest / spread shifts surrounding positional args
- `chain-propagation` — d1 is transparent pass-through; d2+ caller exposed to same positional/kwarg breakage (include `via: wrapper@file:line`)
- `type` — arg type incompatible
- `nullable-now-required` — optional param now required
- `return-type-changed` — caller doesn't handle new return
- `ignored-error` — new error not caught
- `keyword-renamed` — keyword arg name changed (breaks keyword/named callers)
- `super-init-mismatch` — subclass super() call broken

Note: `positional-reorder` is the highest-severity silent failure — no compile/runtime error in dynamic languages, wrong data flows silently. `chain-propagation` compounds this: breakage at d2+ is never visible at d1. Prioritize both in report.

### Call-Chain Propagation

**Problem**: d1 callers that are transparent pass-throughs expose their own callers (d2+) to the same positional/kwarg breakage. Checking only d1 misses these.

**Pass-through classifier** — for each d1 caller with a mismatch or borderline-safe finding, classify:

| Pattern | Class | Chain action |
|---------|-------|--------------|
| `def bar(*args, **kwargs): foo(*args, **kwargs)` | Transparent | Chase d2 — d2 callers see foo's new signature |
| `fn bar(...args) { foo(...args) }` | Transparent | Chase d2 |
| `def bar(x, y): foo(x, y)` | Named wrapper | Chain STOPS — d2 callers of bar see bar's unchanged signature; only bar's body is broken |
| `def bar(a, b): foo(b, a)` | Transformer | Chain STOPS — bar adapts positional order |
| `def bar(a, b, c): foo(a+b, c)` | Transformer | Chain STOPS |

**When to chase d2**:

Only when d1 is a transparent wrapper. Use blast radius data already captured (byDepth d=2 from `impact` call). Load d2 caller files via `ctx_batch_execute`, then verify against the original changed symbol's new signature — not bar's signature.

```
ctx_batch_execute([
  {label: "d2-caller:{file}", command: "sed -n '{lines}p' {d2_caller_file}"},
  ...
])
```

Report chain propagation rows with the full path:

- `chain-propagation` — arg flows through transparent wrapper; d2+ caller's positional layout may be incompatible with changed fn's new signature. Include `via: bar@file:line` in snippet.

**Chain depth limit**: stop at d3 (already the maxDepth fetched from `impact`). Beyond d3, note "chain not fully traced — manual review recommended" in report.

**Termination conditions** (stop chasing deeper regardless of depth):
- Caller is a transformer (reshapes args)
- Caller exposes a different public signature (different param count or names)
- Caller is in a separate deploy unit (cross-service boundary — flag as cross-service-chain)
- d3 reached


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

| Symbol | Caller | Depth | Site | Mismatch | Via | Snippet |
|--------|--------|-------|------|----------|-----|---------|
| `{symbol_name}` | `{file:line}` | `d1\|d2\|d3` | `{call_code}` | `{mismatch_kind}` | `{wrapper@file:line or —}` | `{explanation}` |

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
