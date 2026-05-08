# Phase 1 — Intake

Collect inputs, validate early, confirm with user, then provision in parallel.

**Flow**: Preflight (perms) → Parse → Gather → **Validate** → Confirm → Provision → Joinpoint

## Step 0: Preflight — Permission Setup

**MANDATORY GATE. Do not proceed to Step 1 until this step completes.**

Skill makes many Bash + MCP tool calls. Without pre-approved permissions, each call prompts the user individually — dozens of interrupts.

**Action: Run check immediately.**

```bash
bash {skill_path}/scripts/install_permissions.sh --check
```

**If output is** `OK: all shipguard permissions already present` → proceed to Step 1.

**If output lists missing permissions** → **STOP. Do not run any other command. Do not gather git info. Present this question to the user right now using AskUserQuestion:**

- question: "Shipguard needs to pre-approve Bash + MCP permissions to avoid per-call prompts. Where should I install them?"
- options:
  - label: "User-global (~/.claude/settings.json)" — description: "Recommended. Applies across all projects."
  - label: "Project-local (.claude/settings.local.json)" — description: "Scoped to this repo only. File is gitignored."
  - label: "Skip — I'll approve each prompt manually" — description: "No install. Expect many approval prompts during the run."

**After user responds:**

- User-global → `bash {skill_path}/scripts/install_permissions.sh`
- Project-local → `bash {skill_path}/scripts/install_permissions.sh --project`
- Skip → no action

Installer is idempotent and backs up target before writing. Permissions take effect immediately — no Claude restart needed.

**Only after this step completes (or user chose Skip) → proceed to Step 1.**

## Step 1: Parse Args

Skill may be invoked with free-form text:

```
/release-gatekeeper with cross-repo analysis for /path/to/repo branch develop,
deps include repo1:develop and repo2:main
```

Extract before prompting. Map to structured fields below. Use these patterns (best-effort regex + keyword scan; do NOT hallucinate values).

## Step 2: Gather Info

### Required Fields

| Field | Source | Fallback |
|-------|--------|----------|
| `release_branch` | arg or current branch | prompt |
| `base_branch` | arg or `main` | prompt |
| `repo_path` | arg or cwd | — |

### Derived Paths

| Field | Derivation |
|-------|------------|
| `release_repo_path` | same as `repo_path` |
| `base_repo_path` | `{repo_path}-base` (sibling folder) |

### Deploy Target

| Pattern | Target |
|---------|--------|
| `main`, `release/*`, `hotfix/*` | production |
| `dev`, `develop`, `staging/*` | staging |
| Other | ask user |

### Cross-Repo (always ask)

Prompt user for cross-repo dependencies. Accept:
- Comma-separated paths: `/path/to/repo1,/path/to/repo2`
- Path with branch: `/path/to/repo@feature-branch`
- `none` to skip cross-repo analysis

---

## Step 3: Pre-Validation

**Run BEFORE user confirmation to surface problems early.**

Script: [`scripts/validate_repos.sh`](scripts/validate_repos.sh)

```bash
bash scripts/validate_repos.sh \
  --release-repo "$REPO_PATH" \
  --release-branch "$RELEASE_BRANCH" \
  --base-branch "$BASE_BRANCH" \
  --cross-repo "$CROSS_1" \
  --cross-repo "$CROSS_2"
```

### Validation Output

| Status | Meaning |
|--------|---------|
| `VALID:*` | Check passed |
| `WARN:cross_repo:PATH:cannot_fetch_remote:sha=X` | Proceed with local, show warning |
| `ERROR:cross_repo:PATH:not_found` | Repo doesn't exist locally |
| `ERROR:cross_branch:BRANCH:not_found_in:PATH` | Branch missing locally and remote |

### Error Handling

| Exit Code | Action |
|-----------|--------|
| 0 | All valid, proceed to confirmation |
| 1 | Errors found — show to user, wait for feedback |
| 2 | Warnings only — show in confirmation, can proceed |

### On Errors (exit 1)

Display errors and prompt:

```
Validation failed:
  ✗ Cross-repo /path/to/api-svc: not found locally
  ✗ Branch feature/x not found in /path/to/worker-svc

Options:
  1. Remove problematic repos and continue
  2. Abort and fix paths
  
Choice: ___
```

If user chooses 1: remove invalid cross-repos, re-validate.
If user chooses 2: abort, wait for user to fix and re-invoke.

---

## Step 4: User Confirmation

**Single prompt with validation results.**

```
Release Gatekeeper — Safety Review

Repository:      {repo_path}
Release branch:  {release_branch} ✓
Base branch:     {base_branch} ✓
Base repo path:  {base_repo_path}
Deploy target:   {deploy_target}

Cross-repo dependencies:
{for each cross_repo:}
  ✓ {path}@{branch}
  ⚠ {path}@{branch} — cannot fetch remote, using local (sha: abc123)
{end}

{if no cross-repos:}
  (none — single-repo analysis only)
{end}

Confirm and begin provisioning? [Y/n]
```

If user wants changes → re-gather, re-validate, re-confirm.

---

## Step 5: Parallel Provisioning

After confirmation, run tasks in parallel. **No user interaction.**

### Task Overview

| Task | Script | Depends On |
|------|--------|------------|
| T1 | [`provision_release.sh`](scripts/provision_release.sh) | — |
| T2 | [`provision_base.sh`](scripts/provision_base.sh) | — |
| T3 | [`provision_cross.sh`](scripts/provision_cross.sh) × N | — |
| T4 | [`group_sync.sh`](scripts/group_sync.sh) | T1, T3 |

**Note**: T2 (base) NOT in GitNexus group — only for diff.

### T1: Release Repo

```bash
bash scripts/provision_release.sh \
  --repo "$RELEASE_REPO_PATH" \
  --branch "$RELEASE_BRANCH"
```

### T2: Base Repo

```bash
bash scripts/provision_base.sh \
  --release-repo "$RELEASE_REPO_PATH" \
  --base-repo "$BASE_REPO_PATH" \
  --branch "$BASE_BRANCH"
```

### T3: Cross-Repos (parallel per repo)

```bash
bash scripts/provision_cross.sh \
  --repo "$CROSS_REPO" \
  --branch "$CROSS_BRANCH"
```

### T4: Group Sync (after T1, T3)

```bash
bash scripts/group_sync.sh \
  --group "$GROUP_NAME" \
  --release-repo "$RELEASE_REPO_PATH" \
  --cross-repo "$CROSS_1" \
  --cross-repo "$CROSS_2"
```

### Subagent Dispatch

Launch T1, T2, T3 in parallel (single message with multiple Agent calls):

```
Agent({
  subagent_type: "general-purpose",
  prompt: "Run: bash {skill_path}/scripts/provision_release.sh --repo {path} --branch {branch}
           Return the STATUS line only."
})
// ... T2, T3 similarly
```

After T1+T3 complete → run T4.

---

## Step 6: Joinpoint

Collect results:

| Task | Status | Detail |
|------|--------|--------|
| T1 Release | {ok/failed} | sha={sha} |
| T2 Base | {ok/failed} | sha={sha} |
| T3 Cross-repo X | {ok/warn/failed} | sha={sha} |
| T4 Group sync | {ok/failed/skipped} | cross_links={N} |

### Failure Handling

| Failure | Action |
|---------|--------|
| T1 fails | ABORT — cannot proceed |
| T2 fails | ABORT — cannot compute diff |
| T3 partial (some warn) | WARN — proceed with available |
| T3 fails (error) | WARN — remove from group, proceed |
| T4 fails | WARN — cross-repo analysis degraded |
| gitnexus not installed | FALLBACK — grep mode |

### Analysis Mode

```python
if not gitnexus_installed:
    mode = "grep_fallback"
elif cross_repo_enabled and cross_links > 0:
    mode = "gitnexus_group"
elif cross_repo_enabled and cross_links == 0:
    mode = "gitnexus_local_grep_cross"
else:
    mode = "gitnexus_local"
```

---

## Hand-Off to Phase 2

| Field | Value |
|-------|-------|
| `release_branch` | confirmed |
| `base_branch` | confirmed |
| `release_repo_path` | provisioned path |
| `base_repo_path` | sibling folder |
| `deploy_target` | staging/production |
| `analysis_mode` | determined above |
| `group_name` | if cross-repo |
| `cross_repos` | list of `{path, branch, sha_short}` per cross-repo |
| `cross_links` | from T4 |
| `release_sha_short` | from T1 (`git rev-parse --short HEAD`) |
| `base_sha_short` | from T2 |
| `warnings` | list of non-fatal issues |

All SHAs captured as **short** form (7-char) via `git rev-parse --short HEAD` for report readability.
