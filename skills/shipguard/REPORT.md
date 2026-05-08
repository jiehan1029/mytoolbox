# Phase 5 — Report Generation

Final output: GO/NO-GO recommendation + deploy runbook + rollback plan.

## Report Structure

```markdown
# Release Safety Report

**Branch**: {release_branch} → {base_branch}
**Generated**: {timestamp}
**Commits**: {commit_count}
**Files changed**: {file_count}

## Recommendation: {GO | CONDITIONAL GO | NO-GO}

{summary_reason}

---

## 1. Change Summary

### By Tier

| Tier | Count | Categories |
|------|-------|------------|
| 1 (Irreversible) | {n} | {categories} |
| 2 (Hard to reverse) | {n} | {categories} |
| 3 (Contained) | {n} | {categories} |

### Key Changes
- {bullet_list_of_significant_changes}

---

## 2. Blast Radius

### High-Impact Symbols

| Symbol | Risk | Direct Callers | Affected Flows |
|--------|------|----------------|----------------|
{high_risk_symbols}

### API Impact

| Route | Consumers | Risk | Shape Issues |
|-------|-----------|------|--------------|
{api_routes_if_any}

### Cross-Repo Impact (if applicable)

| Symbol | Remote Consumers | Deploy Units Affected |
|--------|------------------|----------------------|
{cross_repo_if_group_mode}

### Call-Site Mismatches (signature changes)

| Symbol | Caller | Mismatch | Snippet |
|--------|--------|----------|---------|
{call_site_mismatches_from_phase3}

{if no mismatches: "(none detected)"}

---

## 3. Safety Findings

### Blockers (must fix)

| ID | File | Finding |
|----|------|---------|
{blockers_if_any}

### Warnings (should address)

| ID | File | Finding | Mitigation |
|----|------|---------|------------|
{warnings}

---

## 4. Deploy Runbook

### Pre-Deploy Checklist

- [ ] {checklist_items_based_on_findings}

### Deploy Sequence

1. {step_1}
2. {step_2}
...

### Dependencies

| Dependency | Required State | How to Verify |
|------------|----------------|---------------|
{deploy_dependencies}

### Coordinated Deploys (if cross-service)

| Service | Order | Notes |
|---------|-------|-------|
{coordinated_deploys_if_any}

---

## 5. Rollback Plan

### Rollback Trigger Conditions

- {condition_1}
- {condition_2}

### Rollback Steps

1. {rollback_step_1}
2. {rollback_step_2}
...

### Rollback Limitations

{what_cannot_be_rolled_back}

### Data Recovery (if applicable)

{data_recovery_steps_if_tier1_changes}

---

## 6. Metadata

### Repos & Refs

| Role | Repo | Branch | Short SHA |
|------|------|--------|-----------|
| Release | `{release_repo_path}` | `{release_branch}` | `{release_sha_short}` |
| Base | `{base_repo_path}` | `{base_branch}` | `{base_sha_short}` |
| Cross-repo | `{cross_repo_path}` | `{cross_branch}` | `{cross_sha_short}` |

(Repeat cross-repo row per dependency. Omit cross-repo section if none.)

### Analysis

| Field | Value |
|-------|-------|
| Analysis mode | `{gitnexus_group \| gitnexus_local \| grep_fallback}` |
| Cross-links | `{count or "N/A"}` |
```

## Recommendation Logic

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
