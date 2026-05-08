# Phase 1 — Intake

Collect inputs once, validate once, confirm once, then run a single orchestrated provisioning command.

**Flow**: Preflight (perms) → Resolve Inputs → Validate + Confirm → Provision Orchestrator → Joinpoint

## Step 0: Preflight — Permission Setup

**MANDATORY GATE. Do not proceed to Step 1 until this step completes.**

Skill makes many Bash + MCP tool calls. Without pre-approved permissions, each call prompts the user individually.

Run immediately:

```bash
bash {skill_path}/scripts/install_permissions.sh --check
```

If output is `OK: all shipguard permissions already present` → continue.

If output lists missing permissions:
- Ask: "Shipguard needs to pre-approve Bash + MCP permissions to avoid per-call prompts. Install project-local permissions now?"
- Options:
  - Install project-local (`.claude/settings.local.json`)
  - Skip (manual approval per prompt)

After response:
- Install project-local → `bash {skill_path}/scripts/install_permissions.sh`
- Skip → no installation, continue to step 1.

## Step 1: Resolve Inputs (Parse + Gather)

Resolve all fields in one pass from args, cwd, and targeted prompts.

### Required Fields

| Field | Source | Fallback |
|-------|--------|----------|
| `release_branch` | arg or current branch | prompt |
| `base_branch` | arg or `main` | prompt |
| `repo_path` | arg or cwd | — |

### Derived Fields

| Field | Derivation |
|-------|------------|
| `release_repo_path` | same as `repo_path` |
| `base_repo_path` | `{repo_path}-base` |
| `deploy_target` | branch pattern map below |

Deploy target map:
- `main`, `release/*`, `hotfix/*` → production
- `dev`, `develop`, `staging/*` → staging
- other branch names → ask user

Cross-repo dependencies (always ask once):
- Accept `/path/to/repo1,/path/to/repo2`
- Accept `/path/to/repo@branch`
- Accept `none`

## Step 2: Validate Then Confirm

Run validation first so user confirms against real repository state.

```bash
bash scripts/provision_all.sh \
  --mode validate \
  --release-repo "$RELEASE_REPO_PATH" \
  --release-branch "$RELEASE_BRANCH" \
  --base-branch "$BASE_BRANCH" \
  --cross-repo "$CROSS_1" \
  --cross-repo "$CROSS_2"
```

Validation emits `VALID:*`, `WARN:*`, `ERROR:*` and summary line `SUMMARY:errors=X:warnings=Y`.

Error handling:
- Exit `0` → proceed to confirmation
- Exit `2` (warnings only) → show warnings and proceed to confirmation
- Exit `1` (errors) → show errors and ask:
  - 1. Remove problematic cross-repos and continue
  - 2. Abort and fix paths/branches

Then prompt once:

```
Release Gatekeeper — Safety Review

Repository:      {repo_path}
Release branch:  {release_branch}
Base branch:     {base_branch}
Base repo path:  {base_repo_path}
Deploy target:   {deploy_target}
Cross-repo deps: {resolved list with warnings if any}

Confirm and begin provisioning? [Y/n]
```

## Step 3: Provision via Single Orchestrator

After confirmation, run one command. No additional user questions.

```bash
bash scripts/provision_all.sh \
  --mode all \
  --release-repo "$RELEASE_REPO_PATH" \
  --release-branch "$RELEASE_BRANCH" \
  --base-repo "$BASE_REPO_PATH" \
  --base-branch "$BASE_BRANCH" \
  --group "$GROUP_NAME" \
  --cross-repo "$CROSS_1" \
  --cross-repo "$CROSS_2"
```

The orchestrator internally performs:
- Release provisioning/index
- Base provisioning/index
- Cross-repo provisioning/index (per repo)
- Group sync after successful release + cross provisioning

Legacy scripts remain available as compatibility wrappers:
- `scripts/validate_repos.sh`
- `scripts/provision_release.sh`
- `scripts/provision_base.sh`
- `scripts/provision_cross.sh`

## Step 4: Joinpoint and Phase 2 Hand-Off

Use orchestrator output lines as source of truth:
- `STATUS:release_ready:sha=...`
- `STATUS:base_ready:sha=...` or `STATUS:base_ready_no_index:sha=...`
- `STATUS:cross_ready:PATH:sha=...` / warnings / errors per cross-repo
- `STATUS:group_synced:cross_links=N` (or skipped/warn)
- Final `JOINPOINT:...:analysis_mode=...`

### Analysis Mode Rules

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

### Hand-Off Fields for Phase 2

| Field | Value |
|-------|-------|
| `release_branch` | confirmed |
| `base_branch` | confirmed |
| `release_repo_path` | provisioned path |
| `base_repo_path` | sibling folder |
| `deploy_target` | staging/production |
| `analysis_mode` | from `JOINPOINT` |
| `group_name` | if cross-repo enabled |
| `cross_repos` | list of `{path, branch, sha_short}` from status lines |
| `cross_links` | from group sync status |
| `release_sha_short` | short SHA from release status |
| `base_sha_short` | short SHA from base status |
| `warnings` | non-fatal `WARN:*` lines |
