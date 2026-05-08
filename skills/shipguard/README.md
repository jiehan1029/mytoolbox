# ShipGuard — Design Notes

For skill developers and maintainers only. Not loaded during execution.

## Prerequisites

**Required:**
- **context-mode MCP** (`mcp__plugin_context-mode_context-mode__*`) — keeps large command output (git diffs, grep results, gitnexus dumps) out of the main context window. Skill will not function correctly without it.

**Recommended:**
- **GitNexus** (`mcp__gitnexus__*`) — powers blast radius analysis, route consumer/shape-drift cypher queries, cross-repo contracts. Without it, skill falls back to grep (reduced accuracy, no process/flow analysis). Skill uses 11 tools, 1 MCP prompt (`detect_impact`), and 5 read-only resources (`gitnexus://repo/{name}/processes`, `clusters`, `context`, etc.).

## GitNexus Surface Used

| Type | Names |
|------|-------|
| Tools | `detect_changes`, `impact`, `context`, `query`, `cypher`, `rename`, `list_repos`, `group_sync`, `group_status`, `group_contracts`, `group_query` |
| Prompts | `detect_impact` (Phase 2 entry point) |
| Resources | `gitnexus://repo/{name}/{context, processes, process/{name}, clusters, schema}` |

**NOT used / does not exist:**
- ~~`api_impact`~~ — hallucinated tool. Replaced with `cypher` queries against route nodes.
- ~~`shape_check`~~ — hallucinated tool. Replaced with `cypher` field-set comparison.

If GitNexus adds dedicated API/shape tools later, swap cypher blocks back.

## Permissions

Skill ships `permissions.json` listing all Bash + MCP tools it invokes. Without these pre-approved, every call prompts for approval.

Install via Phase 1 Step 0 preflight (skill asks user/project scope at runtime), or manually:

```bash
# User-global (recommended)
bash skills/shipguard/scripts/install_permissions.sh

# Project-local (gitignored .claude/settings.local.json)
bash skills/shipguard/scripts/install_permissions.sh --project

# Check only — list missing perms without writing
bash skills/shipguard/scripts/install_permissions.sh --check
```

Idempotent. Backs up target as `.bak.<timestamp>` before merge. Effective immediately, no Claude restart.

**Trust note**: Permissions are blanket allow-lists for tool patterns (e.g., `Bash(git:*)`, `mcp__gitnexus__*`). Review `permissions.json` before installing. Project-local scope limits blast radius if you don't fully trust the skill's bundled scripts.

## Indexing Flags

Provision scripts run `gitnexus analyze --skip-agents-md --skip-embeddings`.

**`--skip-embeddings` rationale**: Skill uses graph tools only (`detect_changes`, `impact`, `context`, `cypher`, `rename`, `group_*`). Embeddings feed only the `query` tool's semantic component (BM25 + semantic + RRF), which skill never invokes. Embeddings ~2-3× indexing time — no payoff.

**`--skip-agents-md` rationale**: Preserves user's custom AGENTS.md/CLAUDE.md edits across re-analysis.

If skill ever adopts `query` tool or shares index with semantic-search skills, drop `--skip-embeddings` from provision scripts.

## Philosophy

Safety gate, not quality gate. User hasn't reviewed every line but needs confidence:
1. Code internally consistent (no orphaned references)
2. Migrations won't break production
3. Cross-service contracts honored
4. Deploy order explicit
5. Rollback possible

## Language Support

**Full support** (signature extraction + safety checks):
- Python
- TypeScript
- JavaScript
- Go
- Ruby

**Partial support** (safety checks only, no signature analysis):
- Java, Kotlin, Rust, C#, PHP, etc.

Safety checks S1-S13 use grep patterns that work across languages. Signature extraction (DIFF Phase 2) is language-specific — other languages skip this step and rely on safety checks + impact analysis.

## Out of Scope

- Feature completeness
- Requirements alignment
- Full code review
- Test adequacy (coverage is informational)

## Severity Model

| Term | Context | Meaning |
|------|---------|---------|
| BLOCKER | Safety checks | Cannot ship — must fix |
| WARNING | Safety checks | Risk requires mitigation |
| CRITICAL | Impact analysis | Highest blast radius → promotes to BLOCKER |
| HIGH | Impact risk | May promote to WARNING if on critical path |

## Subagent Strategy

Minimize subagent count to reduce cost/latency:

| Phase | Subagents | Trigger |
|-------|-----------|---------|
| Diff | 2 | >300 lines OR >10 files |
| Impact | 1 per 5 symbols | >5 Tier 1/2 symbols |
| Safety | 1 | Always |

Target: ~4 subagents max per release.

## Gate Strategy

Mid-flow gates exist at:
- Phase 3: CRITICAL impact (user can abort)
- Phase 4: BLOCKER safety (user can abort)
- Phase 5: Rollback confirmation (required for Tier 1 changes)

Design decision: Safety gates are valuable interrupts. User should consciously proceed past blockers rather than auto-continue.

## Maintenance Notes

- S1-S13 check IDs must remain stable (referenced in reports)
- Tier definitions (1/2/3) used across DIFF, IMPACT, REPORT — keep consistent
- GitNexus tools are optional — grep fallback must work standalone
- **Known GitNexus Bug**: GitNexus 1.6.3, query/context do not work when mcp connection is open [!1170](https://github.com/abhigyanpatwari/GitNexus/issues/1170). This hurts the tool quality and is supposed to be fixed in 1.6.4 (not yet released as of May 7, 2026).