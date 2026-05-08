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

### GitNexus Preference

- Prefer GitNexus-first analysis for diff, impact, and cross-repo reasoning.
- Use grep/shell fallback when GitNexus is unavailable; mark findings as (fallback).

### Cross-Repo Group Mode

- When multiple services are involved, use group mode with cross-depth and sync when stale.

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

## Global Execution Contract (All Phases)

These rules apply to every phase unless a phase explicitly overrides them.

1. Context-mode first for read/query work
- Prefer context batch/search tools for discovery and evidence collection.
- Keep bulky raw outputs in buffers; summarize results in phase outputs.

2. Outcome over command shape
- Exact commands are not mandatory.
- Any equivalent method is acceptable if evidence quality and output contract are preserved.

3. Tool and CLI selection
- Let the agent choose MCP tool calls vs CLI commands by intent and evidence quality.
- Prefer MCP/GitNexus primitives for graph-aware analysis; use CLI for filesystem or git-native operations.

4. Help-first discovery when uncertain
- For MCP hierarchical tools, use learn mode before selecting subcommands.
- For CLI tools, use help output before unfamiliar flags/subcommands.
- If a known-good command already fits the phase contract, use it directly.
- If a path fails, try one equivalent path and continue with fallback marking.

5. Subagents when needed
- Use subagents opportunistically for large or cross-repo analysis; main agent is fine for small scope.
- If subagents are used, include a one-line reason in phase output or metadata.

6. Contract preservation
- Do not change a phase output schema while executing that phase.
- If fallback paths are used (for example grep/shell), mark rows or notes as `(fallback)`.

7. Deterministic reporting
- If a required section/table has no rows, emit an explicit `(none)`.
