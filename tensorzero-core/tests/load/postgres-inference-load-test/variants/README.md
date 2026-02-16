# Postgres Inference Load Variants

This README shows how to run the manual Postgres inference load benchmark across dedicated gateway write-mode variants.

## Prerequisites

1. Start Postgres and apply migrations.
2. Export required environment variables:

```bash
export TENSORZERO_POSTGRES_URL="postgres://postgres:postgres@localhost:5432/tensorzero_e2e_tests"
export TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1
```

3. From repository root, choose one gateway config variant and start gateway:

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file <CONFIG_PATH>
```

4. In another terminal, run benchmark:

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
  --benchmark-report-json /tmp/postgres-load-<variant>.json
```

## Variant Configs

### 1. Sync writes (baseline)

Config:

```text
tensorzero-core/tests/load/tensorzero.postgres-only.sync.toml
```

Gateway command:

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.sync.toml
```

### 2. Async writes

Config:

```text
tensorzero-core/tests/load/tensorzero.postgres-only.async.toml
```

Gateway command:

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.async.toml
```

### 3. Batch writes (fast flush / smaller batches)

Config:

```text
tensorzero-core/tests/load/tensorzero.postgres-only.batch.fast.toml
```

Gateway command:

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.batch.fast.toml
```

Recommended benchmark tweak:

```text
--drain-wait-ms 8000
```

### 4. Batch writes (balanced)

Config:

```text
tensorzero-core/tests/load/tensorzero.postgres-only.batch.balanced.toml
```

Gateway command:

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.batch.balanced.toml
```

Recommended benchmark tweak:

```text
--drain-wait-ms 10000
```

### 5. Batch writes (throughput)

Config:

```text
tensorzero-core/tests/load/tensorzero.postgres-only.batch.throughput.toml
```

Gateway command:

```bash
cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.batch.throughput.toml
```

Recommended benchmark tweak:

```text
--drain-wait-ms 12000
```

## Suggested comparison flow

1. Keep benchmark flags fixed except config path.
2. Run all variants at the same target QPS.
3. Compare `achieved_qps`, `p99_latency_ms`, `error_rate`, and DB parity in each JSON summary.
4. Repeat at a higher target QPS once baseline target is stable.
