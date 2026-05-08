---
name: shipguard
description: Release safety review focused on self-consistency, migration risk, cross-service contracts, deploy dependencies, and rollback planning. GitNexus-powered blast radius analysis. Use when preparing to ship code you haven't fully reviewed, when user says "is this safe to ship", "release gate", "safety check", or "can I deploy this".
user-invocable: true
---

# ShipGuard: Pre-Release Safety Review

Safety-first release review. Not about feature completeness — about **safe to ship**.

## Workflow

| # | Phase | Goal | Detail | Gate |
|---|-------|------|--------|------|
| 1 | **Intake** | Parse args, gather cross-deps, confirm, then parallel provision (fetch + index) | [INTAKE.md](INTAKE.md) | user confirms (once) |
| 2 | **Diff Triage** | Tier changes by reversibility risk, extract symbols, signature diff | [DIFF.md](DIFF.md) | — |
| 3 | **Impact Analysis** | GitNexus blast radius, call-site verification, cross-repo contracts | [IMPACT.md](IMPACT.md) | gate on CRITICAL |
| 4 | **Safety Audit** | Deep checks: migrations, idempotency, concurrency, leaks, cross-service contracts, project principles | [SAFETY.md](SAFETY.md) | gate on BLOCKER |
| 5 | **Report** | GO/NO-GO + deploy runbook + rollback plan | [REPORT.md](REPORT.md) | user confirms rollback |

**User input in Phase 1 only.** All questions upfront, then parallel provisioning (no mid-flow prompts). Safety gates: Phase 3 (CRITICAL), Phase 4 (BLOCKER), Phase 5 (rollback confirm).

**All safety checks mandatory.** No skip option — if a check doesn't apply, it reports N/A.

## Cross-Cutting Rules

### GitNexus First, Fallback Second

**Tools used:**
- `detect_changes` — diff→symbol + `affected_processes`
- `impact` — per-symbol blast radius (`byDepth`, risk, processes)
- `context` — 360° symbol view (callers, callees, refs, process participation)
- `query` — process-grouped hybrid search (BM25 + semantic + RRF)
- `cypher` — raw Cypher graph queries (custom safety checks; replaces hallucinated `api_impact`/`shape_check`)
- `rename` — multi-file rename safety check (Tier 1 renames)
- `group_sync`, `group_status`, `group_contracts`, `group_query`, `group_list` — multi-repo

**MCP prompts (use as primary path where applicable):**
- `detect_impact` — pre-commit change analysis (Phase 2 entry point)

**MCP resources (read-only context dumps):**
- `gitnexus://repo/{name}/context` — stats + staleness
- `gitnexus://repo/{name}/processes` — all execution flows
- `gitnexus://repo/{name}/process/{name}` — full process trace
- `gitnexus://repo/{name}/clusters` — functional clusters + cohesion (blast radius hints)
- `gitnexus://repo/{name}/schema` — graph schema for cypher construction

Fallback: `git grep` when GitNexus unavailable. Mark findings as `(fallback)`.

### Group Mode for Cross-Repo

When multiple services involved, use `repo: "@{group_name}"` with `crossDepth: 2`. Run `gitnexus group sync {name}` if stale.

### Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **BLOCKER** | Cannot ship safely | NO-GO |
| **WARNING** | Risk requires mitigation | CONDITIONAL GO |
| **INFO** | Notable, not blocking | noted in report |

### Recommendation Logic

- ≥1 BLOCKER → **NO-GO**
- ≥1 WARNING → **CONDITIONAL GO** (list mitigations)
- otherwise → **GO**

### Subagent Pattern

Dispatch `general-purpose` subagents for parallel analysis. Output: **structured rows only** — no raw diffs, no GitNexus dumps.
