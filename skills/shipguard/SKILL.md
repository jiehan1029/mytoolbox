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

## Severity & Recommendation

| Level | Meaning | Action |
|-------|---------|--------|
| **BLOCKER** | Cannot ship safely | NO-GO |
| **WARNING** | Risk requires mitigation | CONDITIONAL GO |
| **INFO** | Notable, not blocking | noted in report |

- ≥1 BLOCKER → **NO-GO**
- ≥1 WARNING → **CONDITIONAL GO** (list mitigations)
- otherwise → **GO**

## Execution Contract

These rules apply to every phase unless a phase explicitly overrides them.

1. **Context-mode first** — prefer batch/search tools for evidence; summarize results, do not dump raw output.
2. **Outcome over command shape** — any equivalent method acceptable if evidence quality and output contract are preserved.
3. **Tool selection** — GitNexus/MCP for graph-aware analysis; CLI for git/filesystem ops; group mode when cross-links exist; grep/shell fallback when GitNexus unavailable → mark `(fallback)`.
4. **Discovery** — use help/learn mode before unfamiliar commands; try one alternative path on failure, then continue with fallback marking.
5. **Subagents** — Phase 4 (Safety Audit) always runs as a subagent; Phase 3 (Impact Analysis) runs as a subagent when `tier_table` has ≥1 Tier 1 or Tier 2 symbol.
6. **Contracts** — preserve output schema; mark fallback rows as `(fallback)`; emit `(none)` for required empty sections.

## Subagent Invocation Template

Subagents start with blank context — they do not inherit these rules automatically. When dispatching a subagent, the main agent must include this block verbatim in the prompt, filled with the relevant values:

```
You are running a ShipGuard analysis phase.
Read: {skill_path}/{PHASE_FILE}

Global rules:
- Prefer context-mode for evidence collection; summarize results, do not dump raw output.
- GitNexus-first for graph-aware analysis; grep/shell fallback when unavailable — mark (fallback).
- Outcome over command shape: any equivalent method is acceptable if evidence quality is preserved.
- Help-first discovery when command shape is uncertain.
- Mark fallback results as (fallback). Emit (none) for required empty sections.

Inputs:
{handoff_fields}

Return: {output_contract} only. Do not include raw diff or tool output.
```

Fill `{PHASE_FILE}` with the phase file to load (e.g. `IMPACT.md`, `SAFETY.md`), `{handoff_fields}` with the structured handoff from the previous phase, and `{output_contract}` with the table/summary names defined in that phase's output contract.
