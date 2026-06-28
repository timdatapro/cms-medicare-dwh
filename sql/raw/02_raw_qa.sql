-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 02_raw_qa.sql
-- Purpose : Validate raw layer against expected values from source analysis
-- Run as  : postgres on database cms_medicare
-- =============================================================================


-- =============================================================================
-- CHECK 1: Row counts vs expected values
-- Expected from project analysis (§7.4 of knowledge base)
-- =============================================================================

SELECT
    'CHECK 1: Row counts' AS check_name,
    table_name,
    actual_rows,
    expected_rows,
    CASE WHEN actual_rows = expected_rows THEN '✓ OK' ELSE '✗ MISMATCH' END AS result
FROM (
    SELECT 'carrier'    AS table_name, COUNT(*) AS actual_rows, 1121004 AS expected_rows FROM raw.carrier    UNION ALL
    SELECT 'outpatient'              , COUNT(*)               ,  575092                  FROM raw.outpatient  UNION ALL
    SELECT 'pde'                     , COUNT(*)               ,  515520                  FROM raw.pde         UNION ALL
    SELECT 'dme'                     , COUNT(*)               ,  103828                  FROM raw.dme         UNION ALL
    SELECT 'inpatient'               , COUNT(*)               ,   58066                  FROM raw.inpatient   UNION ALL
    SELECT 'snf'                     , COUNT(*)               ,   12548                  FROM raw.snf         UNION ALL
    SELECT 'hospice'                 , COUNT(*)               ,   12107                  FROM raw.hospice     UNION ALL
    SELECT 'hha'                     , COUNT(*)               ,    6215                  FROM raw.hha
) t
ORDER BY expected_rows DESC;


-- =============================================================================
-- CHECK 2: Beneficiary counts by year
-- Population grows from 5975 (2015) to 10000 (2025)
-- =============================================================================

SELECT
    'CHECK 2: Beneficiary by year' AS check_name,
    yr,
    actual_rows,
    expected_rows,
    CASE WHEN actual_rows = expected_rows THEN '✓ OK' ELSE '✗ MISMATCH' END AS result
FROM (
    SELECT '2015' AS yr, COUNT(*) AS actual_rows, 5975  AS expected_rows FROM raw.beneficiary_2015 UNION ALL
    SELECT '2016'      , COUNT(*)               , 6288                   FROM raw.beneficiary_2016 UNION ALL
    SELECT '2017'      , COUNT(*)               , 6613                   FROM raw.beneficiary_2017 UNION ALL
    SELECT '2018'      , COUNT(*)               , 7002                   FROM raw.beneficiary_2018 UNION ALL
    SELECT '2019'      , COUNT(*)               , 7446                   FROM raw.beneficiary_2019 UNION ALL
    SELECT '2020'      , COUNT(*)               , 7837                   FROM raw.beneficiary_2020 UNION ALL
    SELECT '2021'      , COUNT(*)               , 8246                   FROM raw.beneficiary_2021 UNION ALL
    SELECT '2022'      , COUNT(*)               , 8671                   FROM raw.beneficiary_2022 UNION ALL
    SELECT '2023'      , COUNT(*)               , 9179                   FROM raw.beneficiary_2023 UNION ALL
    SELECT '2024'      , COUNT(*)               , 9660                   FROM raw.beneficiary_2024 UNION ALL
    SELECT '2025'      , COUNT(*)               , 10000                  FROM raw.beneficiary_2025
) t
ORDER BY yr;


-- =============================================================================
-- CHECK 3: BENE_ID is never NULL (it's the master key linking all 19 files)
-- =============================================================================

SELECT
    'CHECK 3: BENE_ID nulls' AS check_name,
    table_name,
    null_count,
    CASE WHEN null_count = 0 THEN '✓ OK' ELSE '✗ HAS NULLS' END AS result
FROM (
    SELECT 'inpatient'  AS table_name, COUNT(*) FILTER (WHERE BENE_ID IS NULL) AS null_count FROM raw.inpatient  UNION ALL
    SELECT 'outpatient'              , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.outpatient UNION ALL
    SELECT 'carrier'                 , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.carrier    UNION ALL
    SELECT 'dme'                     , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.dme        UNION ALL
    SELECT 'snf'                     , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.snf        UNION ALL
    SELECT 'hospice'                 , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.hospice    UNION ALL
    SELECT 'hha'                     , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.hha        UNION ALL
    SELECT 'pde'                     , COUNT(*) FILTER (WHERE BENE_ID IS NULL)               FROM raw.pde
) t
ORDER BY table_name;


-- =============================================================================
-- CHECK 4: CLM_ID uniqueness per file
-- Each claim spans multiple rows — CLM_ID should NOT be unique per row
-- but should exist on every row (no NULLs)
-- =============================================================================

SELECT
    'CHECK 4: CLM_ID nulls' AS check_name,
    table_name,
    total_rows,
    unique_claims,
    null_clm_id,
    ROUND(total_rows::NUMERIC / NULLIF(unique_claims, 0), 1) AS avg_rows_per_claim,
    CASE WHEN null_clm_id = 0 THEN '✓ OK' ELSE '✗ HAS NULLS' END AS result
FROM (
    SELECT 'inpatient'  AS table_name, COUNT(*) AS total_rows, COUNT(DISTINCT CLM_ID) AS unique_claims, COUNT(*) FILTER (WHERE CLM_ID IS NULL) AS null_clm_id FROM raw.inpatient  UNION ALL
    SELECT 'outpatient'              , COUNT(*)               , COUNT(DISTINCT CLM_ID)                , COUNT(*) FILTER (WHERE CLM_ID IS NULL)               FROM raw.outpatient UNION ALL
    SELECT 'carrier'                 , COUNT(*)               , COUNT(DISTINCT CLM_ID)                , COUNT(*) FILTER (WHERE CLM_ID IS NULL)               FROM raw.carrier    UNION ALL
    SELECT 'dme'                     , COUNT(*)               , COUNT(DISTINCT CLM_ID)                , COUNT(*) FILTER (WHERE CLM_ID IS NULL)               FROM raw.dme        UNION ALL
    SELECT 'snf'                     , COUNT(*)               , COUNT(DISTINCT CLM_ID)                , COUNT(*) FILTER (WHERE CLM_ID IS NULL)               FROM raw.snf        UNION ALL
    SELECT 'hospice'                 , COUNT(*)               , COUNT(DISTINCT CLM_ID)                , COUNT(*) FILTER (WHERE CLM_ID IS NULL)               FROM raw.hospice    UNION ALL
    SELECT 'hha'                     , COUNT(*)               , COUNT(DISTINCT CLM_ID)                , COUNT(*) FILTER (WHERE CLM_ID IS NULL)               FROM raw.hha
) t
ORDER BY total_rows DESC;


-- =============================================================================
-- CHECK 5: BENE_ID format — must be negative numbers (synthetic data marker)
-- =============================================================================

SELECT
    'CHECK 5: BENE_ID format (must be negative)' AS check_name,
    table_name,
    total_bene,
    negative_bene,
    positive_bene,
    CASE WHEN positive_bene = 0 THEN '✓ OK' ELSE '✗ HAS POSITIVE IDs' END AS result
FROM (
    SELECT
        'beneficiary_2025'  AS table_name,
        COUNT(DISTINCT BENE_ID)                                        AS total_bene,
        COUNT(DISTINCT BENE_ID) FILTER (WHERE BENE_ID::BIGINT < 0)    AS negative_bene,
        COUNT(DISTINCT BENE_ID) FILTER (WHERE BENE_ID::BIGINT >= 0)   AS positive_bene
    FROM raw.beneficiary_2025
) t;


-- =============================================================================
-- CHECK 6: Date format — must be DD-Mon-YYYY (e.g. '16-Aug-1999')
-- If dates are ISO (YYYY-MM-DD) the safe_to_date function needs adjustment
-- =============================================================================

SELECT
    'CHECK 6: Date format sample' AS check_name,
    BENE_BIRTH_DT                 AS sample_birth_date,
    BENE_DEATH_DT                 AS sample_death_date,
    CASE
        WHEN BENE_BIRTH_DT ~ '^\d{2}-[A-Za-z]{3}-\d{4}$' THEN '✓ DD-Mon-YYYY'
        WHEN BENE_BIRTH_DT ~ '^\d{4}-\d{2}-\d{2}$'       THEN '! ISO format'
        ELSE '? Unknown format'
    END AS date_format_detected
FROM raw.beneficiary_2025
LIMIT 3;


-- =============================================================================
-- CHECK 7: CLM_PMT_AMT not null in claim files (key financial field)
-- =============================================================================

SELECT
    'CHECK 7: CLM_PMT_AMT nulls' AS check_name,
    table_name,
    total_rows,
    null_pmt,
    zero_pmt,
    CASE WHEN null_pmt = 0 THEN '✓ OK' ELSE '✗ HAS NULLS' END AS result
FROM (
    SELECT 'inpatient'  AS table_name, COUNT(*) AS total_rows, COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL) AS null_pmt, COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0') AS zero_pmt FROM raw.inpatient  UNION ALL
    SELECT 'outpatient'              , COUNT(*)               , COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL)             , COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0')             FROM raw.outpatient UNION ALL
    SELECT 'carrier'                 , COUNT(*)               , COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL)             , COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0')             FROM raw.carrier    UNION ALL
    SELECT 'dme'                     , COUNT(*)               , COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL)             , COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0')             FROM raw.dme        UNION ALL
    SELECT 'snf'                     , COUNT(*)               , COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL)             , COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0')             FROM raw.snf        UNION ALL
    SELECT 'hospice'                 , COUNT(*)               , COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL)             , COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0')             FROM raw.hospice    UNION ALL
    SELECT 'hha'                     , COUNT(*)               , COUNT(*) FILTER (WHERE CLM_PMT_AMT IS NULL)             , COUNT(*) FILTER (WHERE CLM_PMT_AMT = '0')             FROM raw.hha
) t
ORDER BY total_rows DESC;


-- =============================================================================
-- CHECK 8: PDE_ID uniqueness — each PDE row must be unique (no header/line)
-- =============================================================================

SELECT
    'CHECK 8: PDE_ID uniqueness'    AS check_name,
    COUNT(*)                        AS total_rows,
    COUNT(DISTINCT PDE_ID)          AS unique_pde_ids,
    COUNT(*) - COUNT(DISTINCT PDE_ID) AS duplicates,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT PDE_ID) THEN '✓ OK — each row is unique'
        ELSE '✗ DUPLICATES FOUND'
    END AS result
FROM raw.pde;


-- =============================================================================
-- CHECK 9: Leading zeros preserved in STATE_CODE and ZIP_CD
-- STATE_CODE must be 2 chars (e.g. '01', not '1')
-- =============================================================================

SELECT
    'CHECK 9: Leading zeros' AS check_name,
    MIN(LENGTH(STATE_CODE))  AS min_state_len,
    MAX(LENGTH(STATE_CODE))  AS max_state_len,
    MIN(LENGTH(ZIP_CD))      AS min_zip_len,
    MAX(LENGTH(ZIP_CD))      AS max_zip_len,
    COUNT(*) FILTER (WHERE LENGTH(STATE_CODE) < 2) AS short_state_codes,
    CASE
        WHEN COUNT(*) FILTER (WHERE LENGTH(STATE_CODE) < 2) = 0 THEN '✓ OK'
        ELSE '✗ LEADING ZEROS LOST'
    END AS result
FROM raw.beneficiary_2025;


-- =============================================================================
-- CHECK 10: BENE_ID cross-file consistency
-- All BENE_IDs in claims must exist in at least one beneficiary file
-- =============================================================================

SELECT
    'CHECK 10: BENE_ID cross-file' AS check_name,
    table_name,
    total_bene_ids,
    matched_in_beneficiary,
    total_bene_ids - matched_in_beneficiary AS unmatched,
    CASE
        WHEN total_bene_ids = matched_in_beneficiary THEN '✓ OK'
        ELSE '! Some IDs not in beneficiary (may be OK for partial years)'
    END AS result
FROM (
    SELECT
        'inpatient' AS table_name,
        COUNT(DISTINCT i.BENE_ID) AS total_bene_ids,
        COUNT(DISTINCT i.BENE_ID) FILTER (
            WHERE i.BENE_ID IN (SELECT BENE_ID FROM raw.beneficiary_2025)
        ) AS matched_in_beneficiary
    FROM raw.inpatient i
    UNION ALL
    SELECT
        'pde',
        COUNT(DISTINCT p.BENE_ID),
        COUNT(DISTINCT p.BENE_ID) FILTER (
            WHERE p.BENE_ID IN (SELECT BENE_ID FROM raw.beneficiary_2025)
        )
    FROM raw.pde p
) t;


-- =============================================================================
-- SUMMARY
-- =============================================================================

SELECT '════════════════════════════════════════════════════' AS summary
UNION ALL
SELECT 'QA COMPLETE — review results above'
UNION ALL
SELECT 'If all checks show OK → proceed to staging';
