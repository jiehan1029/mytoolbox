# Phase 4 — Safety Audit

Deep checks for bugs that hide until production. **All checks mandatory** — reports N/A if check doesn't apply to diff.

## Check Categories

### S1: Migration Safety

**Applies to**: files matching `**/migrations/**`, `*.sql`, schema files

| Check | Severity | Signal |
|-------|----------|--------|
| S1.1 | BLOCKER | `DROP TABLE` / `DROP COLUMN` without backup plan |
| S1.2 | BLOCKER | `ALTER ... NOT NULL` on populated column without default |
| S1.3 | BLOCKER | Index on table >1M rows without `CONCURRENTLY` (Postgres) |
| S1.4 | WARNING | Column rename (breaks running queries during deploy) |
| S1.5 | WARNING | Type change that may truncate/lose data |
| S1.6 | INFO | New index (note: build time estimate needed) |
| S1.7 | WARNING | Migration does not follow expand-contract ordering: new column added as NOT NULL without a backfill-then-constraint sequence, or column removed without a deprecation-first phase (breaks old code running during rolling deploy window) |

**Output**: flag migrations for human runtime estimate (table size, lock duration).

### S2: Idempotency

**Applies to**: background jobs, event handlers, retry-able operations

| Check | Severity | Signal |
|-------|----------|--------|
| S2.1 | BLOCKER | Job lacks idempotency key / dedup mechanism |
| S2.2 | BLOCKER | Side effect (email, payment, external API) without idempotency guard |
| S2.3 | WARNING | Job signature changed (in-flight jobs may fail) |
| S2.4 | WARNING | Removed job handler (orphaned jobs in queue) |

**Detection**: look for job definitions, `@job`, `celery.task`, `sidekiq`, queue handlers.

### S3: State Machine Integrity

**Applies to**: enums, status fields, state transitions

| Check | Severity | Signal |
|-------|----------|--------|
| S3.1 | BLOCKER | Enum value removed (existing DB rows become invalid) |
| S3.2 | BLOCKER | State transition removed without migration |
| S3.3 | WARNING | New terminal state (check: can existing entities reach it?) |
| S3.4 | WARNING | Enum added without default handling in switch/match |

**Detection**: enum definitions, status columns, state machine patterns.

### S4: Concurrency Bugs

**Applies to**: all code, especially shared state

| Check | Severity | Signal |
|-------|----------|--------|
| S4.1 | BLOCKER | Race condition: read-modify-write without lock/transaction |
| S4.2 | BLOCKER | TOCTOU: time-of-check vs time-of-use gap |
| S4.3 | WARNING | New mutex/lock (potential deadlock with existing locks) |
| S4.4 | WARNING | Lock ordering change (deadlock risk) |
| S4.5 | WARNING | Removed synchronization (was it protecting something?) |

**Detection**: mutex patterns, transaction blocks, concurrent access to shared state.

### S5: Resource Leaks

**Applies to**: connection handling, goroutines/threads, caches

| Check | Severity | Signal |
|-------|----------|--------|
| S5.1 | BLOCKER | Connection opened without corresponding close |
| S5.2 | BLOCKER | Goroutine/thread spawned without termination condition |
| S5.3 | WARNING | Unbounded cache (no max size, no TTL) |
| S5.4 | WARNING | Connection pool size changed (capacity planning) |
| S5.5 | WARNING | Missing `defer close` / `try-finally` pattern |

### S6: Timeout Chains

**Applies to**: external calls, service-to-service communication

| Check | Severity | Signal |
|-------|----------|--------|
| S6.1 | BLOCKER | Downstream timeout > upstream timeout (cascading failure) |
| S6.2 | BLOCKER | External call without timeout |
| S6.3 | WARNING | Timeout increased significantly (capacity impact) |
| S6.4 | WARNING | Retry without backoff/jitter |
| S6.5 | WARNING | Circuit breaker removed/disabled |

### S7: Backward Compatibility

**Applies to**: wire formats, API contracts, queue messages, DB schema, feature flags, env vars

#### S7.A: Wire Format Contracts

| Check | Severity | Signal |
|-------|----------|--------|
| S7.0 | BLOCKER | Proto field number reused with a different type (silent deserialization corruption; worse than removal — data is silently misread by existing consumers) |
| S7.1 | BLOCKER | Required field added to existing message (breaks old producers) |
| S7.2 | BLOCKER | Field type changed (deserialization failure) |
| S7.3 | BLOCKER | Field removed that consumers depend on (verify via cypher shape drift in Phase 3) |
| S7.4 | WARNING | Field renamed (semantic break if consumers use field names) |
| S7.5 | WARNING | Default value changed (behavior shift) |

#### S7.B: Queue Message Contracts (SQS/Kafka/RabbitMQ)

**Detection**: See README.md for grep patterns.

| Check | Severity | Signal |
|-------|----------|--------|
| S7.6 | BLOCKER | Message shape changed without version field |
| S7.7 | BLOCKER | Required field added to message (old producers still running) |
| S7.8 | BLOCKER | Consumer removed but producer still sends (orphan messages) |
| S7.9 | WARNING | New message type without consumer (dead letters) |
| S7.10 | WARNING | Topic/queue name changed |

**Detection**: Use `ctx_batch_execute` to grep producers/consumers (`SendMessage|Publish|produce|KafkaProducer`, `ReceiveMessage|Subscribe|consume|KafkaConsumer`) across all repos. Index results, then `ctx_search(["topic name", "queue name"])` to find cross-repo matches.

#### S7.C: DB Schema Cross-Service

**Applies to**: when multiple services read/write same database tables

| Check | Severity | Signal |
|-------|----------|--------|
| S7.11 | BLOCKER | Column removed that other services SELECT |
| S7.12 | BLOCKER | Column type changed (other services expect old type) |
| S7.13 | BLOCKER | Table renamed without updating all readers |
| S7.14 | WARNING | New NOT NULL column (other services INSERT may fail) |
| S7.15 | WARNING | Index removed that other services rely on for performance |

**Detection**: Use `ctx_batch_execute` to extract table names from migrations and grep across repos for `FROM|JOIN|INSERT INTO|UPDATE {table}` in a single batch. `ctx_search(["{table_name}"])` to find cross-service readers.

#### S7.D: Feature Flag Cross-Service

**Applies to**: feature flags read by multiple services

| Check | Severity | Signal |
|-------|----------|--------|
| S7.16 | BLOCKER | Flag removed but other services still check it |
| S7.17 | BLOCKER | Flag default changed (behavior shift for services with cached value) |
| S7.18 | WARNING | Flag renamed (other services use old name) |

**Detection**: Use `ctx_batch_execute` to grep `isEnabled|getVariant|feature_flag|LaunchDarkly|Unleash` across repos. `ctx_search(["{flag_name}"])` to find cross-service usages.

#### S7.E: Env Var Cross-Service

**Applies to**: env vars shared across services (e.g., service URLs, shared secrets)

| Check | Severity | Signal |
|-------|----------|--------|
| S7.19 | BLOCKER | Env var removed that other services expect |
| S7.20 | BLOCKER | Env var format changed (URL path, port, etc.) |
| S7.21 | WARNING | New required env var not in deployment manifests |

**Detection**: Use `ctx_batch_execute` to grep `ENV|env:|getenv|os.environ|process.env` and scan k8s/docker manifests across repos. `ctx_search(["{VAR_NAME}"])` to find cross-service dependencies.

### S8: Error Handling

**Applies to**: all code

| Check | Severity | Signal |
|-------|----------|--------|
| S8.1 | WARNING | Bare `except`/`catch` swallowing errors |
| S8.2 | WARNING | Error logged but not propagated (silent failure) |
| S8.3 | WARNING | `return None` / `return null` on failure path |
| S8.4 | INFO | New error type introduced (check: callers handle it?) |

### S9: Config Safety

**Applies to**: environment variables, config files

| Check | Severity | Signal |
|-------|----------|--------|
| S9.1 | BLOCKER | Required env var added without deployment coordination |
| S9.2 | WARNING | Missing env var fails silently (should fail fast) |
| S9.3 | WARNING | Secret/credential in code or config file |
| S9.4 | INFO | Default value may not be appropriate for production |

### S10: Observability

**Applies to**: new code paths, error handlers

| Check | Severity | Signal |
|-------|----------|--------|
| S10.1 | WARNING | New code path without tracing/metrics |
| S10.2 | WARNING | Error path missing log context (request ID, user ID) |
| S10.3 | WARNING | High-cardinality metric label (unbounded values) |
| S10.4 | INFO | New external call without latency instrumentation |

### S11: Cache Safety

**Applies to**: cache key construction, cache read/write paths, invalidation/versioning logic

| Check | Severity | Signal |
|-------|----------|--------|
| S11.1 | BLOCKER | Cache key missing tenant/user/namespace discriminator where isolation is required |
| S11.2 | BLOCKER | Key schema changed without versioning/dual-read strategy (old/new key collision risk) |
| S11.3 | WARNING | Non-canonical key construction (unordered map/object serialization) can collide |
| S11.4 | WARNING | Shared key prefix/namespace reused across domains/services without partitioning |
| S11.5 | WARNING | Cache stampede risk on hot keys (no singleflight/lock/jitter on expiry path) |

**Detection**: collect changed key builders, key templates, namespace prefixes, and invalidation/versioning behavior. Flag as BLOCKER when collisions can cause isolation or correctness violations.

### S12: Sensitive Data in Logs

**Applies to**: new/modified log statements

| Check | Severity | Signal |
|-------|----------|--------|
| S12.1 | BLOCKER | PII logged (email, phone, SSN, address) |
| S12.2 | BLOCKER | Credentials/tokens logged |
| S12.3 | WARNING | Request/response body logged without redaction |
| S12.4 | WARNING | User ID logged without business justification |

**Detection**: grep for `log.`, `logger.`, `console.log`, `print` near sensitive field names.

### S13: Project Principles

**Applies to**: if project has principles file. Optional — skip if no file found.

**File search** (project-level only, no user/global):
```bash
find {release_repo_path} -maxdepth 3 -type f \( \
  -iname "claude.md" -o \
  -iname "agent.md" -o \
  -iname "agents.md" -o \
  -iname "constitution.md" -o \
  -iname "principles.md" -o \
  -iname "engineering_principles.md" \
\) 2>/dev/null
```

**Extract from**: sections mentioning "principle", "must", "never", "always", "require", "block", "forbid".

**Audit scope**: Only principles with clear pass/fail criteria related to safety/correctness. Skip style guides, naming conventions, documentation requirements.

| Check | Severity | Signal |
|-------|----------|--------|
| S13.1 | BLOCKER | Direct violation causing security/data/availability risk |
| S13.2 | WARNING | Incomplete compliance, mitigatable |

**If no principles file**: Report `S13: N/A (no principles file found)`.

### S14: Auth Regression

**Applies to**: auth middleware, permission guards, role checks, JWT/session validation, any route/handler touched by the diff

| Check | Severity | Signal |
|-------|----------|--------|
| S14.1 | BLOCKER | Permission guard removed or bypassed on existing endpoint |
| S14.2 | BLOCKER | New endpoint added without auth middleware |
| S14.3 | BLOCKER | Role/permission check weakened (e.g. `AND` → `OR`, stricter role replaced by broader role) |
| S14.4 | BLOCKER | JWT/session validation logic changed (algorithm, expiry, scope handling) |
| S14.5 | WARNING | RBAC model change: new role added, permission mapping changed, or scope set widened |
| S14.6 | WARNING | Auth bypass condition added (e.g. new `if dev_mode` / `if internal_request` path without validation) |

**Detection**: grep for auth middleware patterns (`@require_auth`, `authenticate`, `authorize`, `jwt.verify`, `hasPermission`, `requireRole`, `@login_required`, `before_action`) across changed handlers and their call chains. Flag removed decorators or guards on modified routes.

### S15: Rolling Deploy Window Safety

**Applies to**: any Tier 1 change deployed to a service with multiple instances or a rolling restart strategy

| Check | Severity | Signal |
|-------|----------|--------|
| S15.1 | BLOCKER | New code writes a field that old schema does not have (forward-incompatible write during mixed-version window) |
| S15.2 | BLOCKER | Old code reads a field that new schema removes (backward-incompatible read during mixed-version window) |
| S15.3 | BLOCKER | Migration acquires table lock on high-traffic table without zero-downtime strategy (no `CONCURRENTLY`, no lock timeout) |
| S15.4 | WARNING | Column added as NOT NULL without default — old running instances that INSERT will fail immediately |
| S15.5 | WARNING | New required field in queue message sent by new code before all consumers are deployed |
| S15.6 | INFO | Changes appear safe for rolling deploy but no explicit backward-compat evidence found — recommend smoke test on first instance before continuing rollout |

**Detection**: cross-reference Tier 1 diff symbols against migration files and API/queue contracts from Phase 2. For each schema change, verify the dual-safety property: (1) new code + old schema = safe? (2) old code + new schema = safe? Flag if either fails.

## Execution Strategy

### Execution Approach

Required evidence set:
- Changed files and diff hunks needed for S1-S13 checks.
- Symbol/path evidence for compatibility checks (S7) and cache checks (S11).
- Search evidence for jobs, concurrency/state transitions, config/env usage, and logging changes.

Example shape only (equivalent commands are acceptable):

```text
ctx_batch_execute([...diff evidence..., ...migration/job/config/log scans..., ...S7 cross-service scans..., ...S11 key-space scans...])
ctx_search(["S1", "S2", "S7", "S11", "breaking", "collision", "orphan", "timeout"])
```

### N/A Handling

If a check category doesn't apply to the diff (e.g., no migrations, no background jobs):
- Report as `N/A` with reason
- Does not count toward BLOCKER/WARNING totals

## Output

### Safety Findings Table (Format)

| Check | Severity | File | Line | Finding | Evidence |
|-------|----------|------|------|---------|----------|
| `{check_id}` | `{BLOCKER\|WARNING\|INFO}` | `{file_path}` | `{line_num}` | `{finding_description}` | `{code_snippet}` |

### Summary

```
Safety Audit Summary:
  BLOCKER: {count}
  WARNING: {count}
  INFO: {count}
  N/A: {check_ids} ({reason})
```

## End-of-Phase Gate

If any BLOCKER findings:

```
BLOCKER safety issues detected:
- {check_id}: {file_path}:{line} — {finding}
- {check_id}: {file_path}:{line} — {finding}

These MUST be addressed before release.
Continue to report generation anyway? [y/N]
```

Default NO.
