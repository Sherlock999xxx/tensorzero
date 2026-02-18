-- Trigram GIN indexes for partial string matching on input/output JSONB columns.
-- These enable efficient LIKE '%substring%' and ILIKE queries by casting JSONB to text.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- chat_inference_data
CREATE INDEX idx_chat_inference_data_input_trgm
    ON tensorzero.chat_inference_data USING GIN (CAST(input AS TEXT) gin_trgm_ops);
CREATE INDEX idx_chat_inference_data_output_trgm
    ON tensorzero.chat_inference_data USING GIN (CAST(output AS TEXT) gin_trgm_ops);

-- json_inference_data
CREATE INDEX idx_json_inference_data_input_trgm
    ON tensorzero.json_inference_data USING GIN (CAST(input AS TEXT) gin_trgm_ops);
CREATE INDEX idx_json_inference_data_output_trgm
    ON tensorzero.json_inference_data USING GIN (CAST(output AS TEXT) gin_trgm_ops);

-- chat_datapoints
CREATE INDEX idx_chat_datapoints_input_trgm
    ON tensorzero.chat_datapoints USING GIN (CAST(input AS TEXT) gin_trgm_ops);
CREATE INDEX idx_chat_datapoints_output_trgm
    ON tensorzero.chat_datapoints USING GIN (CAST(output AS TEXT) gin_trgm_ops);

-- json_datapoints
CREATE INDEX idx_json_datapoints_input_trgm
    ON tensorzero.json_datapoints USING GIN (CAST(input AS TEXT) gin_trgm_ops);
CREATE INDEX idx_json_datapoints_output_trgm
    ON tensorzero.json_datapoints USING GIN (CAST(output AS TEXT) gin_trgm_ops);
