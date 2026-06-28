-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 03_staging_functions.sql
-- Purpose : Safe-cast helper functions for raw -> staging transformation
-- Run as  : postgres on database cms_medicare
-- =============================================================================
-- Why safe cast?
--   raw columns are all TEXT. Direct CAST fails on NULL, empty string,
--   or malformed values and aborts the entire INSERT.
--   These functions return NULL instead of raising an error,
--   making every bad value visible in QA rather than crashing the load.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- safe_to_date: converts DD-Mon-YYYY text to DATE
-- Examples:
--   '16-Aug-1999' -> 1999-08-16
--   ''            -> NULL
--   NULL          -> NULL
--   'garbage'     -> NULL
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION staging.safe_to_date(p_text TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_text IS NULL OR TRIM(p_text) = '' THEN
        RETURN NULL;
    END IF;
    RETURN TO_DATE(TRIM(p_text), 'DD-Mon-YYYY');
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION staging.safe_to_date IS
    'Converts DD-Mon-YYYY text to DATE. Returns NULL on empty/malformed input.';


-- ---------------------------------------------------------------------------
-- safe_to_numeric: converts text to NUMERIC
-- Examples:
--   '11179.88' -> 11179.88
--   '0'        -> 0
--   ''         -> NULL
--   NULL       -> NULL
--   'N/A'      -> NULL
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION staging.safe_to_numeric(p_text TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_text IS NULL OR TRIM(p_text) = '' THEN
        RETURN NULL;
    END IF;
    RETURN TRIM(p_text)::NUMERIC;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION staging.safe_to_numeric IS
    'Converts text to NUMERIC. Returns NULL on empty/malformed input.';


-- ---------------------------------------------------------------------------
-- safe_to_int: converts text to INTEGER
-- Examples:
--   '12'  -> 12
--   ''    -> NULL
--   '1.5' -> NULL (not integer)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION staging.safe_to_int(p_text TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_text IS NULL OR TRIM(p_text) = '' THEN
        RETURN NULL;
    END IF;
    RETURN TRIM(p_text)::INTEGER;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

COMMENT ON FUNCTION staging.safe_to_int IS
    'Converts text to INTEGER. Returns NULL on empty/malformed input.';


-- ---------------------------------------------------------------------------
-- clean_text: trims whitespace, returns NULL for empty strings
-- Ensures no '   ' or '' sneaks into staging as a value
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION staging.clean_text(p_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_text IS NULL OR TRIM(p_text) = '' THEN
        RETURN NULL;
    END IF;
    RETURN TRIM(p_text);
END;
$$;

COMMENT ON FUNCTION staging.clean_text IS
    'Trims whitespace and converts empty strings to NULL.';


-- ---------------------------------------------------------------------------
-- Verification: test all functions with known values
-- ---------------------------------------------------------------------------

SELECT
    staging.safe_to_date('16-Aug-1999')    AS date_valid,       -- 1999-08-16
    staging.safe_to_date('')               AS date_empty,       -- NULL
    staging.safe_to_date('garbage')        AS date_bad,         -- NULL
    staging.safe_to_date(NULL)             AS date_null;        -- NULL

SELECT
    staging.safe_to_numeric('11179.88')    AS num_valid,        -- 11179.88
    staging.safe_to_numeric('0')           AS num_zero,         -- 0
    staging.safe_to_numeric('')            AS num_empty,        -- NULL
    staging.safe_to_numeric('N/A')         AS num_bad;          -- NULL

SELECT
    staging.safe_to_int('42')             AS int_valid,         -- 42
    staging.safe_to_int('')               AS int_empty,         -- NULL
    staging.safe_to_int('3.14')           AS int_bad;           -- NULL

SELECT
    staging.clean_text('  hello  ')       AS text_trimmed,      -- 'hello'
    staging.clean_text('   ')             AS text_spaces,       -- NULL
    staging.clean_text('')                AS text_empty,        -- NULL
    staging.clean_text(NULL)              AS text_null;         -- NULL
