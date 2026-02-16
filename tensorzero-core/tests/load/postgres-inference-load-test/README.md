# Postgres Inference Load Test

This directory contains a configurable manual load test binary for TensorZero inference ingestion through the real `/inference` HTTP pipeline, with Postgres correctness checks.

## What it validates

1. Steady-state QPS vs target.
2. p99 latency.
3. Error rate.
4. Postgres row parity for run-scoped tags (`load_test_run_id`).

The benchmark uses synthetic requests and the built-in `dummy` provider to focus on gateway and Postgres write-path performance.

## Prerequisites

1. Start Postgres and apply migrations.
2. Export:
   - `TENSORZERO_POSTGRES_URL`
   - `TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1`
3. Start gateway with the dedicated load config (sync baseline):

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.sync.toml
```

## Run

```bash
cargo test-postgres-inference-load -- \
  --gateway-url http://localhost:3000 \
  --function-name load_test_chat \
  -r 100 \
  -c 16 \
  -d 180s \
  -w 200 \
  --max-tokens 128 \
  --drain-wait-ms 5000 \
  --max-error-rate 0.01 \
  --max-p99-latency-ms 250 \
  --benchmark-report-json /tmp/postgres-load-summary.json
```

## Notes

1. Target QPS can be provided by `-r/--rate` or by `--target-qps`.
2. DB parity compares Postgres rows against all successful HTTP requests observed by the benchmark run (including warmup requests, because warmups use the same run tags).
3. Dedicated gateway write-mode variants are documented in `tensorzero-core/tests/load/postgres-inference-load-test/variants/README.md`.
