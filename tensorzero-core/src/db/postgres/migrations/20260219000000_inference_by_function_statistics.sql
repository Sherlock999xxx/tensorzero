-- Incrementally-maintained rollup table for inference counts by function/variant.
-- Replaces slow COUNT(*) + MAX(created_at) queries on chat_inferences/json_inferences
-- with pre-aggregated per-minute counts.

CREATE TABLE IF NOT EXISTS tensorzero.inference_by_function_statistics (
    function_name TEXT NOT NULL,
    variant_name TEXT NOT NULL,
    function_type TEXT NOT NULL,  -- 'chat' or 'json'
    minute TIMESTAMPTZ NOT NULL,
    inference_count BIGINT NOT NULL,
    PRIMARY KEY (function_name, variant_name, function_type, minute)
);

CREATE INDEX IF NOT EXISTS idx_inference_by_function_stats_minute
    ON tensorzero.inference_by_function_statistics(minute);

-- Watermark state for incremental refresh.
CREATE TABLE IF NOT EXISTS tensorzero.inference_by_function_statistics_refresh_state (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    last_processed_created_at TIMESTAMPTZ
);

-- Initialize watermark at the current tail to avoid a full-table first refresh.
INSERT INTO tensorzero.inference_by_function_statistics_refresh_state (
    singleton,
    last_processed_created_at
)
SELECT
    TRUE,
    GREATEST(chat_max, json_max)
FROM (
    SELECT
        (SELECT MAX(created_at) FROM tensorzero.chat_inferences) AS chat_max,
        (SELECT MAX(created_at) FROM tensorzero.json_inferences) AS json_max
) AS latest
WHERE GREATEST(chat_max, json_max) IS NOT NULL
ON CONFLICT (singleton) DO NOTHING;

-- Incremental refresh for inference_by_function_statistics.
-- Reprocesses a trailing lookback window to absorb slightly late-arriving rows.
CREATE OR REPLACE FUNCTION tensorzero.refresh_inference_by_function_statistics_incremental(
    lookback INTERVAL DEFAULT INTERVAL '10 minutes',
    full_refresh BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    state_created_at TIMESTAMPTZ;
    refresh_from TIMESTAMPTZ;
    refresh_to TIMESTAMPTZ := NOW();
    newest_created_at TIMESTAMPTZ;
    oldest_created_at TIMESTAMPTZ;
BEGIN
    INSERT INTO tensorzero.inference_by_function_statistics_refresh_state (singleton)
    VALUES (TRUE)
    ON CONFLICT (singleton) DO NOTHING;

    SELECT last_processed_created_at
    INTO state_created_at
    FROM tensorzero.inference_by_function_statistics_refresh_state
    WHERE singleton = TRUE
    FOR UPDATE;

    IF full_refresh THEN
        TRUNCATE TABLE tensorzero.inference_by_function_statistics;
        refresh_from := TIMESTAMPTZ '-infinity';
    ELSIF state_created_at IS NULL THEN
        refresh_from := TIMESTAMPTZ '-infinity';
    ELSE
        refresh_from := date_trunc('minute', state_created_at - lookback);
    END IF;

    -- Upsert only affected minute buckets in the trailing refresh window.
    INSERT INTO tensorzero.inference_by_function_statistics (
        function_name,
        variant_name,
        function_type,
        minute,
        inference_count
    )
    SELECT
        function_name,
        variant_name,
        'chat' AS function_type,
        date_trunc('minute', created_at) AS minute,
        COUNT(*)::BIGINT AS inference_count
    FROM tensorzero.chat_inferences
    WHERE created_at >= refresh_from
      AND created_at <= refresh_to
    GROUP BY function_name, variant_name, date_trunc('minute', created_at)

    UNION ALL

    SELECT
        function_name,
        variant_name,
        'json' AS function_type,
        date_trunc('minute', created_at) AS minute,
        COUNT(*)::BIGINT AS inference_count
    FROM tensorzero.json_inferences
    WHERE created_at >= refresh_from
      AND created_at <= refresh_to
    GROUP BY function_name, variant_name, date_trunc('minute', created_at)

    ON CONFLICT (function_name, variant_name, function_type, minute) DO UPDATE
    SET inference_count = EXCLUDED.inference_count;

    -- Keep retention correct: if old source partitions were dropped,
    -- remove stale stats buckets older than the earliest source row.
    SELECT LEAST(
        (SELECT MIN(created_at) FROM tensorzero.chat_inferences),
        (SELECT MIN(created_at) FROM tensorzero.json_inferences)
    ) INTO oldest_created_at;

    IF oldest_created_at IS NULL THEN
        TRUNCATE TABLE tensorzero.inference_by_function_statistics;
    ELSE
        DELETE FROM tensorzero.inference_by_function_statistics
        WHERE minute < date_trunc('minute', oldest_created_at);
    END IF;

    SELECT GREATEST(
        (SELECT MAX(created_at) FROM tensorzero.chat_inferences),
        (SELECT MAX(created_at) FROM tensorzero.json_inferences)
    ) INTO newest_created_at;

    UPDATE tensorzero.inference_by_function_statistics_refresh_state
    SET last_processed_created_at = newest_created_at
    WHERE singleton = TRUE;
END;
$$;

-- Backfill from existing data.
SELECT tensorzero.refresh_inference_by_function_statistics_incremental(full_refresh => TRUE);
