-- Covering indexes on (function_name, created_at) for chat_inferences and json_inferences.
-- Enables Index Only Scans for queries that aggregate by function_name with MAX(created_at) and COUNT(*).

CREATE INDEX IF NOT EXISTS idx_chat_inferences_function_created_at
    ON tensorzero.chat_inferences(function_name, created_at);

CREATE INDEX IF NOT EXISTS idx_json_inferences_function_created_at
    ON tensorzero.json_inferences(function_name, created_at);

-- Expression indexes for fast COUNT(DISTINCT evaluation_run_id) queries.
-- Partial indexes covering only rows with the evaluation tag, excluding internal functions.

CREATE INDEX IF NOT EXISTS idx_chat_inferences_eval_run_id
    ON tensorzero.chat_inferences((tags->>'tensorzero::evaluation_run_id'))
    WHERE tags ? 'tensorzero::evaluation_run_id' AND NOT function_name LIKE 'tensorzero::%';

CREATE INDEX IF NOT EXISTS idx_json_inferences_eval_run_id
    ON tensorzero.json_inferences((tags->>'tensorzero::evaluation_run_id'))
    WHERE tags ? 'tensorzero::evaluation_run_id' AND NOT function_name LIKE 'tensorzero::%';

-- Rebuild generic tags GIN indexes with `jsonb_ops` to support both `?` and `@>` efficiently.
DROP INDEX IF EXISTS tensorzero.idx_chat_inferences_tags;
DROP INDEX IF EXISTS tensorzero.idx_json_inferences_tags;

CREATE INDEX IF NOT EXISTS idx_chat_inferences_tags
    ON tensorzero.chat_inferences USING GIN (tags jsonb_ops);

CREATE INDEX IF NOT EXISTS idx_json_inferences_tags
    ON tensorzero.json_inferences USING GIN (tags jsonb_ops);
