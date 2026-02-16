# Postgres-Only Inference Load Testing Design

## Summary

This document defines a manual load testing design for Postgres-only TensorZero inference ingestion.
The goal is to validate that we can sustain a configurable target QPS through the real `/inference` gateway path, while preserving data correctness in Postgres under load.

We will use synthetic inference requests and the built-in `dummy` provider so that benchmark cost is near-zero and the bottleneck reflects gateway + Postgres write behavior.

## Goals

1. Exercise the real inference request path (`POST /inference`) end-to-end.
2. Run in Postgres-only mode for observability ingestion (ClickHouse disabled).
3. Make target QPS configurable so we can test 100 QPS now and higher later.
4. Validate correctness using Postgres row counts, not only HTTP success.
5. Measure steady-state performance with p99 latency and error rate.
6. Support comparative testing for write modes:
   - synchronous writes
   - `async_writes`
   - `batch_writes` with Postgres batching knobs

## Non-Goals

1. CI automation in phase 1 (manual benchmark only).
2. Full production representativeness of model-provider latency (dummy provider is intentionally synthetic).
3. ClickHouse throughput testing.
4. Optimization of unrelated subsystems (auth cache, evaluations, experimentation).

## Key Constraints and Codebase Facts

1. Inference writes happen via `write_inference` in `tensorzero-core/src/endpoints/inference.rs`, which writes:
   - one chat or json inference row
   - one or more model inference rows
2. The write path uses `DelegatingDatabaseConnection` (`tensorzero-core/src/db/delegating_connection.rs`):
   - always writes to ClickHouse first
   - writes to Postgres only when `TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1`
3. With observability disabled (`gateway.observability.enabled = false`), ClickHouse becomes a no-op disabled client, so ClickHouse calls do not persist.
4. Postgres write batching already exists:
   - config fields in `gateway.observability.batch_writes`
   - Postgres-specific cap `max_rows_postgres`
   - implementation in `tensorzero-core/src/db/postgres/batching.rs`
5. The built-in `dummy` provider exists and supports low-latency synthetic responses, suitable for ingestion-focused load tests.

## Proposed Benchmark Architecture

## Components

1. New load test binary (Rust + `rlt`), proposed path:
   - `tensorzero-core/tests/load/postgres-inference-load-test`
2. Existing gateway process in HTTP mode.
3. Existing Postgres instance.
4. No mock provider dependency for baseline runs (use `dummy` provider).

## High-Level Flow

1. Load generator sends controlled-rate HTTP requests to `/inference`.
2. Gateway runs normal inference pipeline with `dummy` model/provider.
3. Gateway writes inference rows to Postgres (sync/async/batched mode based on config).
4. After run completion and drain period, load generator queries Postgres for run-scoped counts.
5. Benchmark report combines request stats and DB correctness stats.

## Benchmark Configuration

## Gateway Runtime Config

1. `gateway.observability.enabled = false`
2. `postgres.enabled = true`
3. `postgres.connection_pool_size = <configurable>`
4. One or more chat functions bound to `dummy` provider model.
5. Optional write-mode variants:
   - default (sync writes)
   - `gateway.observability.async_writes = true`
   - `gateway.observability.batch_writes = { enabled = true, flush_interval_ms = ..., max_rows = ..., max_rows_postgres = ... }`

## Required Environment Variables

1. `TENSORZERO_POSTGRES_URL=<...>`
2. `TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1`

Optional for reads/queries during benchmark:

3. `TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_READ=1` (not required for ingestion correctness checks, but may help if using internal read endpoints)

## Load Binary CLI

The new benchmark binary should expose:

1. `--gateway-url` (default `http://localhost:3000`)
2. `--function-name` (default load-test function)
3. `--duration` (or `rlt -d`)
4. `--rate` target QPS (via `rlt -r`)
5. `--concurrency` (via `rlt -c`)
6. `--warmup` (via `rlt -w`)
7. `--max-tokens` to keep request shape explicit
8. `--run-id` optional override (otherwise auto-generate UUIDv7)
9. `--drain-wait-ms` wait time after load to allow async/batch writers to flush
10. Postgres verification options:
    - `--postgres-url` (fallback to env)
    - `--verify-timeout-s`
11. Request-shape options:
    - fixed synthetic prompt length
    - optional randomized payload template (bounded distribution)

## Request Shape

Each request should include:

1. `function_name`
2. `stream = false`
3. synthetic user message content
4. `params.chat_completion.max_tokens` (required when token-based rate limiting rules exist)
5. tags including:
   - `load_test_run_id = <run-id>`
   - `load_test_case = <name>`

Using run-scoped tags enables precise DB correctness checks for only this benchmark invocation.

## Metrics and Success Criteria

## Request-Level Metrics

Collected by `rlt`:

1. achieved steady-state QPS
2. error rate
3. latency percentiles (at minimum p50, p95, p99)

## DB-Level Correctness Metrics

For rows matching `tags->>'load_test_run_id' = <run-id>`:

1. count of chat/json inference rows
2. count of model inference rows
3. expected minimum model rows:
   - at least one model inference row per successful inference for the dummy-provider baseline
4. parity checks:
   - `successful_http_requests == inference_rows` (after drain)
   - `model_inference_rows >= inference_rows`

Suggested verification SQL:

```sql
-- 1) Count inference rows for this run
WITH run_inference_ids AS (
    SELECT id
    FROM tensorzero.chat_inferences
    WHERE tags->>'load_test_run_id' = $1
    UNION ALL
    SELECT id
    FROM tensorzero.json_inferences
    WHERE tags->>'load_test_run_id' = $1
)
SELECT COUNT(*)::BIGINT AS inference_rows
FROM run_inference_ids;
```

```sql
-- 2) Count model inference rows for this run (join by inference_id)
WITH run_inference_ids AS (
    SELECT id
    FROM tensorzero.chat_inferences
    WHERE tags->>'load_test_run_id' = $1
    UNION ALL
    SELECT id
    FROM tensorzero.json_inferences
    WHERE tags->>'load_test_run_id' = $1
)
SELECT COUNT(*)::BIGINT AS model_inference_rows
FROM tensorzero.model_inferences m
JOIN run_inference_ids r ON m.inference_id = r.id;
```

## Pass/Fail Definition for a Target QPS

A run passes for target QPS `R` only if all are true:

1. Achieved steady-state QPS is at or above `R` within tolerance.
2. p99 latency is within configured threshold for that test profile.
3. error rate is within configured threshold for that test profile.
4. DB correctness checks pass after drain window.

The benchmark should print explicit failure reasons per dimension.

## Steady-State Methodology

1. Run warmup phase to stabilize pools and runtime effects.
2. Measure during fixed window after warmup.
3. Separate drain phase after traffic stops:
   - wait `drain_wait_ms`
   - verify DB row parity
4. For batched writes, drain duration is part of correctness evaluation but not request latency percentiles.

Recommended calculation:

1. Exclude warmup and drain from achieved QPS measurement.
2. Compute achieved QPS over measurement window:
   - `achieved_qps = successful_requests_in_window / window_seconds`
3. Evaluate p99 and error rate from the same measurement window.

## Manual Benchmark Procedure

1. Start Postgres with expected schema/migrations.
2. Start gateway in Postgres-only mode with selected write configuration.
3. Export:
   - `TENSORZERO_POSTGRES_URL`
   - `TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1`
4. Run load test binary with desired `-r`, `-c`, `-d`.
5. Capture report output and persist JSON report artifact.
6. Repeat for matrix of:
   - target QPS values
   - write modes
   - pool and batch settings
7. Compare:
   - p99
   - error rate
   - DB parity and drain lag

Example (illustrative):

```bash
# Gateway env
export TENSORZERO_POSTGRES_URL="postgres://postgres:postgres@localhost:5432/tensorzero-e2e-tests"
export TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1

# Start gateway in Postgres-only mode using a dedicated load-test config
cargo run --profile performance --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.toml

# Run load benchmark at 100 QPS
cargo test-postgres-inference-load -- \
  --gateway-url http://localhost:3000 \
  --function-name load_test_chat \
  -r 100 \
  -c 16 \
  -d 180s \
  --warmup 200 \
  --drain-wait-ms 5000
```

## Suggested Test Matrix

Phase 1 (current target):

1. QPS: 50, 75, 100
2. Modes:
   - sync writes
   - async writes
   - batch writes (`flush_interval_ms`: 50/100/250, `max_rows_postgres`: 100/500/1000)
3. Concurrency sweep per QPS point (for example `c=4,8,16,32`)

Phase 2 (future higher QPS):

1. Increase QPS ladder (for example 150, 200, 300, ...)
2. Re-tune pool size and batch thresholds.
3. Re-run the same correctness gates.

## Risks and Mitigations

## Risk: False positives from HTTP-only success

Mitigation:
DB row parity is a required gate. We do not declare success from transport metrics alone.

## Risk: Async/batch delayed persistence

Mitigation:
enforce drain phase before DB verification and report drain lag.

## Risk: Feature flag misconfiguration causing missing Postgres writes

Mitigation:
startup preflight should assert `ENABLE_POSTGRES_WRITE` and fail fast if not enabled.

## Risk: Incorrect model row validation due to missing tags on `model_inferences`

Mitigation:
derive model-row scope by joining `model_inferences.inference_id` against run-scoped inference IDs from `chat_inferences` and `json_inferences` (never filter model rows directly by tags).

## Risk: Cache effects masking write load

Mitigation:
disable cache at request level (`cache_options.enabled = "off"` in load payload) unless cache behavior is explicitly under test.

## Risk: Dummy provider under-represents real provider latency

Mitigation:
this is accepted for ingestion-focused load tests; optional secondary profile can introduce synthetic provider delay later.

## Implementation Outline

1. Add workspace member crate under `tensorzero-core/tests/load/postgres-inference-load-test`.
2. Reuse `rlt::cli::BenchCli` pattern used by existing load binaries.
3. Implement worker-local HTTP client and shared run metadata (`run_id`, payload template).
4. Implement final verification step that queries Postgres directly for run-scoped counts.
5. Emit:
   - human-readable summary
   - machine-readable JSON report for later comparison.

## TODO: Make Runnable in CI

Phase 1 TODO (not implemented now):

1. Add a dedicated CI workflow/job that:
   - starts Postgres service
   - applies Postgres migrations
   - starts gateway with Postgres-only config and `ENABLE_POSTGRES_WRITE=1`
   - runs the load binary with a short deterministic profile
2. Use fixed seed/randomization and fixed duration for reproducibility.
3. Persist benchmark JSON artifact.
4. Add regression guardrails:
   - fail job if DB parity fails
   - fail job if error rate exceeds threshold
   - optionally fail on p99/QPS regressions against checked-in baseline window.
5. Keep CI profile intentionally lighter than manual perf runs to control cost and variance.

## Open Questions

1. Final numeric thresholds for p99 and acceptable error rate at each QPS target.
2. Exact steady-state tolerance policy (for example minimum achieved QPS as absolute value vs percentage of target).
3. Whether we also want an optional profile that introduces synthetic provider delay to emulate real model latency distributions.
