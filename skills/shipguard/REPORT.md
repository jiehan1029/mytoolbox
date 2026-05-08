# Phase 5 — Report Generation

Final output: GO/NO-GO recommendation + deploy runbook + rollback plan.

## Inputs (from previous phases)

- Phase 1: branch/ref metadata
- Phase 2: `tier_table`, `signature_changes`, `special_files`
- Phase 3: blast radius, call-site mismatches, API/cross-repo findings
- Phase 4: safety findings with `BLOCKER|WARNING|INFO` and `N/A`

## Required Report Sections

Generate one markdown report containing these sections in order:

1. Header
2. Recommendation
3. Change Summary
4. Blast Radius
5. Safety Findings
6. Safety Coverage
7. Deploy Runbook
8. Rollback Plan
9. Metadata

If a section has no rows, include an explicit `(none)` marker.

## Section Contracts

### 1) Header

Required fields:
- `Branch: {release_branch} -> {base_branch}`
- `Generated: {timestamp}`
- `Commits: {commit_count}`
- `Files changed: {file_count}`

### 2) Recommendation

Required field:
- `Recommendation: {GO | CONDITIONAL GO | NO-GO}`

Required explanation:
- one short reason paragraph tied to top risks/findings

### 3) Change Summary

Required table:

| Tier | Count | Categories |
|------|-------|------------|
| 1 (Irreversible) | {n} | {categories} |
| 2 (Hard to reverse) | {n} | {categories} |
| 3 (Contained) | {n} | {categories} |

Required bullets:
- top significant changes (3-8 bullets)

### 4) Blast Radius

Required table:

| Symbol | Initial Tier | Final Tier | Risk | d1 Callers | Processes | Notes |
|--------|--------------|------------|------|------------|-----------|-------|
| {symbol_name} | {1|2|3} | {1|2|3} | {LOW|MEDIUM|HIGH|CRITICAL} | {count} | {count} | {notes} |

Required mismatch table:

| Symbol | Caller | Depth | Mismatch | Via |
|--------|--------|-------|----------|-----|
| {symbol_name} | {file:line} | {d1|d2|d3} | {mismatch_kind} | {wrapper@file:line or -} |

Optional tables (include if applicable):
- API impact (`Route | Consumers | Risk | Mismatches | Notes`)
- Cross-repo impact (`Symbol | Remote Consumers | Deploy Units | Bridge/Fallback`)

### 5) Safety Findings

Required blockers table:

| ID | File | Finding |
|----|------|---------|
| {check_id} | {file_path} | {finding} |

Required warnings table:

| ID | File | Finding | Mitigation |
|----|------|---------|------------|
| {check_id} | {file_path} | {finding} | {mitigation} |

### 6) Safety Coverage

Required summary block:

```text
Safety Coverage:
  BLOCKER: {count}
  WARNING: {count}
  INFO: {count}
  N/A: {check_ids} ({reason})
```

Check IDs in scope: S1–S15 (S1.7, S7.0, S14, S15 included). S13 is N/A when no principles file found. S14 is N/A when no auth/middleware touched. S15 is N/A when no Tier 1 changes present.

### 7) Deploy Runbook

Required checklist:
- pre-deploy checks derived from findings

Required sequence:
- ordered deployment steps

Required dependency table:

| Dependency | Required State | How to Verify |
|------------|----------------|---------------|
| {dependency} | {state} | {verification} |

Optional coordinated deploys table (if cross-service):

| Service | Order | Notes |
|---------|-------|-------|
| {service} | {order} | {notes} |

### 8) Rollback Plan

Required:
- rollback trigger conditions
- ordered rollback steps
- rollback limitations
- data recovery steps when Tier 1 changes require it

### 9) Metadata

Required refs table:

| Role | Repo | Branch | Short SHA |
|------|------|--------|-----------|
| Release | {release_repo_path} | {release_branch} | {release_sha_short} |
| Base | {base_repo_path} | {base_branch} | {base_sha_short} |
| Cross-repo | {cross_repo_path} | {cross_branch} | {cross_sha_short} |

Repeat cross-repo row per dependency. Omit cross-repo row if none.

Required analysis table:

| Field | Value |
|-------|-------|
| Analysis mode | {gitnexus_group | gitnexus_local | grep_fallback} |
| Cross-links | {count or N/A} |
| Execution notes | {subagent reason or none} |

## Recommendation Logic

- Combine findings from:
  - Phase 3 after severity mapping (`CRITICAL -> BLOCKER`, `HIGH on critical path -> WARNING`)
  - Phase 4 safety findings (`BLOCKER|WARNING|INFO`)
- ≥1 BLOCKER → **NO-GO**
- ≥1 WARNING → **CONDITIONAL GO** (list mitigations)
- otherwise → **GO**

## Deploy Runbook Inference

| Finding | Runbook Item |
|---------|--------------|
| Migration files | Pre-deploy: run migrations |
| Dependency changes | Pre-deploy: verify deps installed |
| Config additions | Pre-deploy: set env vars |
| Cross-repo impact | Sequence: deploy services in order |
| Feature flag changes | Pre-deploy: update flag state |
| Infra changes | Pre-deploy: apply terraform/k8s |

## Rollback Generation

**Automatic**: code revert, down migration, disable flag, restore config.

**Non-rollbackable** (require confirmation):
- DROP TABLE/column → restore from backup
- Enum value removed → manual data fix
- External API called → manual reversal

## User Confirmation

```
Rollback Plan Review:

Non-rollbackable changes detected:
- {list}

Mitigation documented:
- {backup_plan}

Confirm rollback plan is acceptable? [y/N]
```

Only generate final report after confirmation.

## Output

Write report to: `{release_repo_path}/docs/release-safety-{branch_slug}-{date}.md`

Display summary:

```
Release Gatekeeper Complete

Recommendation: {recommendation}
Report: {report_path}

{one_line_summary}
```
