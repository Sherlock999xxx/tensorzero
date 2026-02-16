# Load Testing

- Install `vegeta` [→](https://github.com/tsenart/vegeta).
- Launch the ClickHouse instance:

  ```
  docker compose -f tensorzero-core/tests/load/docker-compose.yml up -d --build --force-recreate --remove-orphans
  ```

- Launch the mock inference provider:

  ```
  cargo run --profile performance --bin mock-provider-api
  ```

- Launch the gateway.
  - With observability:

    ```
    cargo run --profile performance --bin gateway tensorzero-core/tests/load/tensorzero.toml
    ```

  - Without observability:

    ```
    cargo run --profile performance --bin gateway tensorzero-core/tests/load/tensorzero-without-observability.toml
    ```

- Then, you can run a load test with `sh path/to/test/run.sh`.

## Postgres-Only Inference Load Test

For the Postgres ingestion benchmark that uses the built-in `dummy` provider and verifies DB row parity:

1. Start Postgres and apply migrations.
2. Export:

   ```bash
   export TENSORZERO_POSTGRES_URL="postgres://postgres:postgres@localhost:5432/tensorzero_e2e_tests"
   export TENSORZERO_INTERNAL_FLAG_ENABLE_POSTGRES_WRITE=1
   ```

3. Start gateway with the dedicated Postgres-only config:

   ```bash
   cargo run --profile performance --features e2e_tests --bin gateway -- --config-file tensorzero-core/tests/load/tensorzero.postgres-only.sync.toml
   ```

4. Run the benchmark:

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

5. For async and batch write-mode variants, see:
   `tensorzero-core/tests/load/postgres-inference-load-test/variants/README.md`
