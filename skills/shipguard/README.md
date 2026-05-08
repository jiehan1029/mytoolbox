# ShipGuard

Current developer reference for the ShipGuard skill.

## Purpose

ShipGuard is a release safety gate, not a feature-quality review.

Primary outcomes:
1. Catch release-blocking risk before deploy.
2. Surface cross-service and rollout coupling.
3. Produce a deterministic GO / CONDITIONAL GO / NO-GO report with deploy and rollback guidance.

## Workflow

ShipGuard runs five phases:
1. `INTAKE.md`: resolve inputs, validate, confirm once, and provision analysis context.
2. `DIFF.md`: classify changes by reversibility risk and extract signature/cross-cutting signals.
3. `IMPACT.md`: compute blast radius and verify risky call sites.
4. `SAFETY.md`: run mandatory S1–S15 safety checks.
5. `REPORT.md`: compile recommendation, runbook, rollback, and metadata.

Gates:
1. Phase 3 gate on CRITICAL impact.
2. Phase 4 gate on BLOCKER safety findings.
3. Phase 5 rollback confirmation before final report.

## Global Execution Model

Global execution behavior is defined in `SKILL.md` and applies across phases.

Key rules:
1. Prefer context-mode for read/query evidence collection.
2. Use outcome-based execution, not rigid command templates.
3. Let the agent choose MCP tools vs CLI by intent and evidence quality.
4. Use help/learn discovery when command shape is uncertain.
5. Use subagents when needed; include a one-line reason when used.
6. Preserve phase output contracts; mark fallback results as `(fallback)`.
7. Emit explicit `(none)` for required empty sections.

## Tooling and Fallbacks

1. GitNexus-first for diff/impact/cross-repo analysis.
2. Grep/shell fallback must remain functional when GitNexus is unavailable.
3. Cross-repo analysis should use group mode when cross-links exist.

## Permissions

ShipGuard includes `permissions.json` for Bash and MCP permissions used by the skill.

Install/check:

```bash
bash skills/shipguard/scripts/install_permissions.sh --check
bash skills/shipguard/scripts/install_permissions.sh
```

Current permission flow in Intake preflight:
1. Install project-local permissions.
2. Skip installation and approve prompts manually.

## Provisioning Scripts

Primary orchestrator:

```bash
bash skills/shipguard/scripts/provision_all.sh --mode validate ...
bash skills/shipguard/scripts/provision_all.sh --mode all ...
```

Compatibility wrappers retained:
1. `scripts/validate_repos.sh`
2. `scripts/provision_release.sh`
3. `scripts/provision_base.sh`
4. `scripts/provision_cross.sh`

## Contract Invariants

Keep these stable unless all dependent phases are updated together:
1. Tier semantics (1/2/3) across Diff, Impact, and Report.
2. Safety check IDs S1–S15 in Safety and Report output.
3. Severity mapping used for recommendation:
   - CRITICAL impact maps to BLOCKER.
   - HIGH on critical path maps to WARNING.
4. Output schemas declared in phase files.

## Language Coverage

1. Strongest signature analysis support: Python, TypeScript/JavaScript, Go, Ruby.
2. Other languages rely primarily on impact + safety checks.

## Output

Final report path:

```text
{release_repo_path}/docs/release-safety-{branch_slug}-{date}.md
```

The report must include recommendation, risk evidence, safety coverage, deploy sequence, rollback plan, and analysis metadata as defined in `REPORT.md`.

## Base Repo Provisioning

ShipGuard uses a **sibling-clone pattern** for the base branch:

- `base_repo_path` is derived as `{repo_path}-base` (e.g. `/path/to/myapp` → `/path/to/myapp-base`).
- The orchestrator (`provision_all.sh`) clones the release repo's own remote URL (`git remote get-url origin`) into that sibling path on first run.
- On subsequent runs it reuses the existing clone, validating that the remote URL matches before checking out the base branch.
- The resolved `base_repo_path` is shown in the confirmation prompt so users can catch wrong paths before provisioning begins.
- If your repos are not co-located or use a different naming convention, override by passing `--base-repo` explicitly to `provision_all.sh`.

## Skill Path Resolution (`{skill_path}`)

In INTAKE.md Step 0, `{skill_path}` refers to the directory where ShipGuard is installed. The expected default is:

```
~/.claude/skills/shipguard
```

If the path is wrong or unresolvable, the `install_permissions.sh --check` call will fail and the agent will fall through to the **manual approval** path — the skill continues running correctly, just with per-call permission prompts. No phase is blocked. Correcting the path is optional.

## Known Gaps

The following checks are intentionally out of scope:

- **Dependency CVE scanning** (would cover 1.4 from the safety gap analysis): ShipGuard performs static diff analysis only. CVE scanning requires external tooling (`npm audit`, `trivy`, `grype`, `osv-scanner`) with network access and a vulnerability database. These should run as a separate CI step, not inline in the release gate. ShipGuard flags new dependency files (S-category lockfile signals in DIFF.md) as a prompt to run those tools, but does not invoke them.

## Maintenance Notes
- **Known GitNexus Bug**: GitNexus 1.6.3, query/context do not work when mcp connection is open [!1170](https://github.com/abhigyanpatwari/GitNexus/issues/1170). This hurts the tool quality and is supposed to be fixed in 1.6.4 (not yet released as of May 7, 2026).