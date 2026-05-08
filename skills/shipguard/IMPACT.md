# Phase 3 — Impact Analysis

Blast radius per symbol. GitNexus-first, cross-repo aware.

Severity mapping:
- `CRITICAL` risk -> `BLOCKER` (blocks release)
- `HIGH` on critical path -> `WARNING`

## Inputs (from Phase 2)

- `tier_table`
- `signature_changes`
- `special_files`
- `release_repo_path`
- `analysis_mode`, `group_name` (if cross-repo)

## Step 1: Symbol Blast Radius

Goal: compute risk and fan-out for each changed symbol, ordered by tier `1 -> 2 -> 3`.

Preferred path:
- Use GitNexus impact analysis (`impact`) with upstream direction.
- Use group repo mode (`@{group_name}` + `crossDepth`) when cross-repo links are available.

Required per-symbol outputs:
- `risk` (`LOW|MEDIUM|HIGH|CRITICAL`)
- `byDepth` (`d1`, `d2`, `d3` callers/consumers)
- `affected_processes`
- `affected_modules` (if available)

Optional enrichment:
- For HIGH/CRITICAL symbols, use symbol context (`context`) to confirm process participation and caller/callee shape.

Fallback:
- If GitNexus unavailable, use grep caller discovery and mark rows as `(fallback)`.

## Step 2: Call-Site Verification (Signature-Changed Symbols)

When to run:
- Run only for symbols that appear in `signature_changes`.

Coverage policy:
- Always verify all cross-repo callers.
- Always verify Tier 1/2 signature-changed symbols.
- Tier 3 may be sampled only if caller volume is very high; record sampling note.

Verification checks:
1. Arity
2. Positional order
3. Variadic/spread behavior
4. Type compatibility
5. Return handling
6. Error handling
7. Nullable/required transitions
8. Keyword/named argument renames
9. Constructor/super init compatibility

Mismatch kinds (breaking):
- `arity`
- `positional-reorder`
- `variadic-shift`
- `chain-propagation`
- `type`
- `nullable-now-required`
- `return-type-changed`
- `ignored-error`
- `keyword-renamed`
- `super-init-mismatch`

Notes:
- `positional-reorder` is the highest-priority silent failure.
- Keep only mismatched sites in output (skip compatible sites).

### Call-Chain Propagation

Problem:
- Transparent wrappers at `d1` can hide breakage that appears at `d2+`.

Classifier for d1 wrappers:
- `TRANSPARENT`: forwards args unchanged -> chase d2
- `NAMED-WRAPPER`: presents its own stable signature -> chain stops
- `TRANSFORMER`: reshapes/adapts args -> chain stops

Depth policy:
- Chase transparent chains to `d3` max.
- If still unresolved at d3, record `chain not fully traced - manual review recommended`.

Termination conditions:
- transformer detected
- wrapper exposes different public signature
- cross-service/deploy boundary crossed
- d3 reached

## Step 3: API Route Impact (for changed handlers)

Goal:
- identify route consumers and response-shape breakage.

Preferred path:
- Use graph queries/resources to get:
  - route handlers affected
  - route consumers
  - process flows containing changed handlers
  - handler response fields vs consumer-accessed fields

Rule:
- Accessed keys missing from handler response keys => mismatch (minimum `WARNING`).

Fallback:
- If graph schema does not support route/field edges, use grep-based handler/consumer checks and mark `(grep fallback)`.

## Step 4: Cross-Repo Mode

When `group_name` is provided:
1. Check group status; sync if stale.
2. Read cross-link count.
3. Choose path:
   - `crossLinks > 0`: group mode analysis
   - `crossLinks = 0`: grep fallback across cross repos

Cross-repo tier promotion:
- Cross-repo caller in different deploy unit -> Tier 1
- Cross-repo caller in same deploy unit -> minimum Tier 2

Requirement:
- Verify call sites for all cross-repo callers (no sampling).

## Step 5: Fan-Out Optimization

For large symbol sets:
- Batch impact collection with context-mode.
- Surface HIGH/CRITICAL symbols first.
- Preserve deterministic ordering: Tier 1 first, then Tier 2, then Tier 3.

## Tier Promotion Rules

| Condition | Promotion |
|-----------|-----------|
| Tier 3 touches app-wide shared utility | -> Tier 2 |
| Tier 2 on critical path | -> Tier 1 |
| External-call error handling weakened/removed | +1 tier |
| Cross-repo caller exists | minimum Tier 2 |
| Cross-repo caller in different deploy unit | -> Tier 1 |
| Route consumer count >5 | minimum Tier 2 |
| Shape drift mismatch | minimum Tier 2 |
| High-cohesion cluster touched | minimum Tier 2 |

## Output Contract

### Blast Radius Table

| Symbol | Initial Tier | Final Tier | Risk | d1 Callers | Processes | Notes |
|--------|--------------|------------|------|------------|-----------|-------|
| `{symbol_name}` | `{1|2|3}` | `{1|2|3}` | `{LOW|MEDIUM|HIGH|CRITICAL}` | `{count}` | `{count}` | `{notes}` |

### Call-Site Verification Table

| Symbol | Caller | Depth | Site | Mismatch | Via | Snippet |
|--------|--------|-------|------|----------|-----|---------|
| `{symbol_name}` | `{file:line}` | `d1|d2|d3` | `{call_code}` | `{mismatch_kind}` | `{wrapper@file:line or -}` | `{explanation}` |

### API Impact Table

| Route | Consumers | Risk | Mismatches | Notes |
|-------|-----------|------|------------|-------|
| `{route_path}` | `{count}` | `{LOW|MEDIUM|HIGH}` | `{count}` | `{notes}` |

### Cross-Repo Findings (if group mode)

| Symbol | Local Repo | Remote Consumers | Deploy Units | Bridge/Fallback |
|--------|------------|------------------|--------------|-----------------|
| `{symbol_name}` | `{repo_name}` | `{count} in {repo_names}` | `{count}` | `{bridge|grep fallback}` |

## End-of-Phase Gate

If any CRITICAL findings:

```text
CRITICAL impact detected:
- {symbol}: {reason}

Continue to safety audit? [y/N]
```

Default is `N`. User must explicitly proceed.
