-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 07_staging_qa.sql
-- Purpose : Validate staging layer — optimized for speed
-- Run as  : postgres on database cms_medicare
-- Strategy:
--   1. Create indexes once at the top
--   2. All JOINs use indexed columns
--   3. No IN (SELECT ...) subqueries — all replaced with LEFT JOIN
--   4. COUNT(*) FILTER instead of separate subqueries
--   5. Drop indexes at the end
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Step 0: Create indexes for all join columns (runs once, speeds everything)
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_qa_stg_bene_bene_id
    ON staging.beneficiary (bene_id);

CREATE INDEX IF NOT EXISTS idx_qa_stg_inpH_clm_id
    ON staging.inpatient_header (clm_id);
CREATE INDEX IF NOT EXISTS idx_qa_stg_inpL_clm_id
    ON staging.inpatient_line (clm_id);

CREATE INDEX IF NOT EXISTS idx_qa_stg_outH_clm_id
    ON staging.outpatient_header (clm_id);
CREATE INDEX IF NOT EXISTS idx_qa_stg_outL_clm_id
    ON staging.outpatient_line (clm_id);

CREATE INDEX IF NOT EXISTS idx_qa_stg_carH_clm_id
    ON staging.carrier_header (clm_id);
CREATE INDEX IF NOT EXISTS idx_qa_stg_carL_clm_id
    ON staging.carrier_line (clm_id);

CREATE INDEX IF NOT EXISTS idx_qa_stg_dmeH_clm_id
    ON staging.dme_header (clm_id);
CREATE INDEX IF NOT EXISTS idx_qa_stg_dmeL_clm_id
    ON staging.dme_line (clm_id);

CREATE INDEX IF NOT EXISTS idx_qa_stg_pde_bene_id
    ON staging.pde (bene_id);
CREATE INDEX IF NOT EXISTS idx_qa_stg_carH_bene_id
    ON staging.carrier_header (bene_id);
CREATE INDEX IF NOT EXISTS idx_qa_stg_inpH_bene_id
    ON staging.inpatient_header (bene_id);


-- =============================================================================
-- CHECK 1: Row counts vs expected — all in one scan per table
-- =============================================================================

SELECT 'CHECK 1: Row counts' AS check_name, table_name, rows, expected,
    CASE WHEN rows = expected THEN 'OK' ELSE 'MISMATCH' END AS result
FROM (VALUES
    ('beneficiary',         (SELECT COUNT(*) FROM staging.beneficiary),         86217::BIGINT),
    ('inpatient_header',    (SELECT COUNT(*) FROM staging.inpatient_header),    20867),
    ('inpatient_line',      (SELECT COUNT(*) FROM staging.inpatient_line),      58066),
    ('outpatient_header',   (SELECT COUNT(*) FROM staging.outpatient_header),   402653),
    ('outpatient_line',     (SELECT COUNT(*) FROM staging.outpatient_line),     575092),
    ('carrier_header',      (SELECT COUNT(*) FROM staging.carrier_header),      90705),
    ('carrier_line',        (SELECT COUNT(*) FROM staging.carrier_line),        1121004),
    ('dme_header',          (SELECT COUNT(*) FROM staging.dme_header),          37782),
    ('dme_line',            (SELECT COUNT(*) FROM staging.dme_line),            103828),
    ('snf_header',          (SELECT COUNT(*) FROM staging.snf_header),          1632),
    ('snf_line',            (SELECT COUNT(*) FROM staging.snf_line),            12548),
    ('hospice_header',      (SELECT COUNT(*) FROM staging.hospice_header),      1086),
    ('hospice_line',        (SELECT COUNT(*) FROM staging.hospice_line),        12107),
    ('hha_header',          (SELECT COUNT(*) FROM staging.hha_header),          493),
    ('hha_line',            (SELECT COUNT(*) FROM staging.hha_line),            6215),
    ('pde',                 (SELECT COUNT(*) FROM staging.pde),                 515520)
) AS t(table_name, rows, expected)
ORDER BY table_name;


-- =============================================================================
-- CHECK 2+3+6+7: One pass per table — dates, nulls, ranges, type codes
-- Each table scanned exactly once
-- =============================================================================

-- beneficiary: birth dates
SELECT
    'CHECK 2-3: beneficiary'        AS check_name,
    COUNT(*)                        AS total_rows,
    COUNT(*) FILTER (WHERE bene_birth_dt IS NULL)           AS null_birth_dt,
    COUNT(*) FILTER (WHERE bene_birth_dt < '1900-01-01')    AS suspicious_birth,
    COUNT(DISTINCT enrollmt_ref_yr)                         AS years_loaded,
    MIN(enrollmt_ref_yr)                                    AS min_year,
    MAX(enrollmt_ref_yr)                                    AS max_year
FROM staging.beneficiary;

-- inpatient header: one scan for dates + amounts + type code + ICD format
SELECT
    'CHECK 2-3-4-6-7: inpatient_header' AS check_name,
    COUNT(*)                             AS total_rows,
    COUNT(*) FILTER (WHERE clm_from_dt IS NULL)                          AS null_clm_from_dt,
    COUNT(*) FILTER (WHERE clm_admsn_dt IS NULL)                         AS null_clm_admsn_dt,
    COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL)                          AS null_clm_pmt_amt,
    COUNT(*) FILTER (WHERE clm_pmt_amt < 0)                              AS negative_pmt,
    COUNT(*) FILTER (WHERE nch_clm_type_cd <> '60')                      AS wrong_type_cd,
    COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01'
                       OR  clm_from_dt > '2025-12-31')                   AS out_of_range_dt,
    COUNT(*) FILTER (WHERE prncpal_dgns_cd IS NOT NULL
                       AND LENGTH(prncpal_dgns_cd) NOT BETWEEN 3 AND 7)  AS bad_icd_length,
    COUNT(*) FILTER (WHERE prncpal_dgns_cd ~ '\.')                       AS icd_has_dots,
    COUNT(DISTINCT prncpal_dgns_cd)                                       AS unique_icd_codes,
    ROUND(SUM(clm_pmt_amt))                                               AS total_pmt_amt
FROM staging.inpatient_header;

-- outpatient header
SELECT
    'CHECK 2-3-4-6: outpatient_header'  AS check_name,
    COUNT(*)                             AS total_rows,
    COUNT(*) FILTER (WHERE clm_from_dt IS NULL)                          AS null_clm_from_dt,
    COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL)                          AS null_clm_pmt_amt,
    COUNT(*) FILTER (WHERE nch_clm_type_cd <> '40')                      AS wrong_type_cd,
    COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01'
                       OR  clm_from_dt > '2025-12-31')                   AS out_of_range_dt,
    ROUND(SUM(clm_pmt_amt))                                               AS total_pmt_amt
FROM staging.outpatient_header;

-- carrier header
SELECT
    'CHECK 2-3-4-6: carrier_header'     AS check_name,
    COUNT(*)                             AS total_rows,
    COUNT(*) FILTER (WHERE clm_from_dt IS NULL)                          AS null_clm_from_dt,
    COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL)                          AS null_clm_pmt_amt,
    COUNT(*) FILTER (WHERE nch_clm_type_cd <> '71')                      AS wrong_type_cd,
    COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01'
                       OR  clm_from_dt > '2025-12-31')                   AS out_of_range_dt,
    ROUND(SUM(clm_pmt_amt))                                               AS total_pmt_amt
FROM staging.carrier_header;

-- remaining claim types in one query
SELECT
    claim_type, total_rows, null_from_dt, null_pmt, wrong_code, out_of_range,
    CASE WHEN null_from_dt = 0 AND null_pmt = 0
          AND wrong_code = 0 AND out_of_range = 0
         THEN 'OK' ELSE 'CHECK DETAILS' END AS result
FROM (
    SELECT 'dme'     AS claim_type, COUNT(*) AS total_rows,
        COUNT(*) FILTER (WHERE clm_from_dt IS NULL)                        AS null_from_dt,
        COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL)                        AS null_pmt,
        COUNT(*) FILTER (WHERE nch_clm_type_cd <> '82')                    AS wrong_code,
        COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01'
                            OR clm_from_dt > '2025-12-31')                 AS out_of_range
    FROM staging.dme_header
    UNION ALL
    SELECT 'snf', COUNT(*),
        COUNT(*) FILTER (WHERE clm_from_dt IS NULL),
        COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL),
        COUNT(*) FILTER (WHERE nch_clm_type_cd <> '20'),
        COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01' OR clm_from_dt > '2025-12-31')
    FROM staging.snf_header
    UNION ALL
    SELECT 'hospice', COUNT(*),
        COUNT(*) FILTER (WHERE clm_from_dt IS NULL),
        COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL),
        COUNT(*) FILTER (WHERE nch_clm_type_cd <> '50'),
        COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01' OR clm_from_dt > '2025-12-31')
    FROM staging.hospice_header
    UNION ALL
    SELECT 'hha', COUNT(*),
        COUNT(*) FILTER (WHERE clm_from_dt IS NULL),
        COUNT(*) FILTER (WHERE clm_pmt_amt IS NULL),
        COUNT(*) FILTER (WHERE nch_clm_type_cd <> '10'),
        COUNT(*) FILTER (WHERE clm_from_dt < '2015-01-01' OR clm_from_dt > '2025-12-31')
    FROM staging.hha_header
) t;

-- pde: one scan for all checks
SELECT
    'CHECK 2-3-8: pde'                  AS check_name,
    COUNT(*)                             AS total_rows,
    COUNT(*) FILTER (WHERE srvc_dt IS NULL)                              AS null_srvc_dt,
    COUNT(*) FILTER (WHERE tot_rx_cst_amt IS NULL)                       AS null_cost,
    COUNT(*) FILTER (WHERE tot_rx_cst_amt < 0)                          AS negative_cost,
    COUNT(*) FILTER (WHERE srvc_dt < '2015-01-01'
                       OR  srvc_dt > '2025-12-31')                      AS out_of_range_dt,
    COUNT(*) FILTER (WHERE LENGTH(prod_srvc_id) <> 11)                  AS bad_ndc_length,
    COUNT(*) FILTER (WHERE prod_srvc_id ~ '[^0-9]')                     AS ndc_non_numeric,
    COUNT(DISTINCT prod_srvc_id)                                         AS unique_ndcs,
    MIN(srvc_dt)                                                         AS min_date,
    MAX(srvc_dt)                                                         AS max_date,
    ROUND(SUM(tot_rx_cst_amt))                                           AS total_drug_cost
FROM staging.pde;


-- =============================================================================
-- CHECK 5: Orphan lines — LEFT JOIN on indexed clm_id columns
-- =============================================================================

SELECT
    'CHECK 5: Orphan lines' AS check_name,
    claim_type,
    orphans,
    CASE WHEN orphans = 0 THEN 'OK' ELSE 'ORPHANS FOUND' END AS result
FROM (
    SELECT 'inpatient' AS claim_type,
           COUNT(*) FILTER (WHERE h.clm_id IS NULL) AS orphans
    FROM staging.inpatient_line l
    LEFT JOIN staging.inpatient_header h USING (clm_id)

    UNION ALL

    SELECT 'outpatient',
           COUNT(*) FILTER (WHERE h.clm_id IS NULL)
    FROM staging.outpatient_line l
    LEFT JOIN staging.outpatient_header h USING (clm_id)

    UNION ALL

    SELECT 'carrier',
           COUNT(*) FILTER (WHERE h.clm_id IS NULL)
    FROM staging.carrier_line l
    LEFT JOIN staging.carrier_header h USING (clm_id)

    UNION ALL

    SELECT 'dme',
           COUNT(*) FILTER (WHERE h.clm_id IS NULL)
    FROM staging.dme_line l
    LEFT JOIN staging.dme_header h USING (clm_id)
) t;


-- =============================================================================
-- CHECK 9: BENE_ID referential integrity — hash join on indexed bene_id
-- =============================================================================

SELECT
    'CHECK 9: BENE_ID integrity' AS check_name,
    claim_type,
    total_bene,
    unmatched,
    CASE WHEN unmatched = 0 THEN 'OK'
         ELSE 'UNMATCHED (may span years)'
    END AS result
FROM (
    SELECT 'inpatient_header' AS claim_type,
           COUNT(DISTINCT h.bene_id)                                           AS total_bene,
           COUNT(DISTINCT h.bene_id) FILTER (WHERE b.bene_id IS NULL)          AS unmatched
    FROM staging.inpatient_header h
    LEFT JOIN (SELECT DISTINCT bene_id FROM staging.beneficiary) b
           ON h.bene_id = b.bene_id

    UNION ALL

    SELECT 'carrier_header',
           COUNT(DISTINCT h.bene_id),
           COUNT(DISTINCT h.bene_id) FILTER (WHERE b.bene_id IS NULL)
    FROM staging.carrier_header h
    LEFT JOIN (SELECT DISTINCT bene_id FROM staging.beneficiary) b
           ON h.bene_id = b.bene_id

    UNION ALL

    SELECT 'pde',
           COUNT(DISTINCT p.bene_id),
           COUNT(DISTINCT p.bene_id) FILTER (WHERE b.bene_id IS NULL)
    FROM staging.pde p
    LEFT JOIN (SELECT DISTINCT bene_id FROM staging.beneficiary) b
           ON p.bene_id = b.bene_id
) t;


-- =============================================================================
-- CHECK 10: Financial totals — staging vs raw (one scan each)
-- =============================================================================

SELECT
    'CHECK 10: Financial totals' AS check_name,
    claim_type,
    staging_total,
    raw_total,
    ABS(staging_total - raw_total) AS diff,
    CASE WHEN ABS(staging_total - raw_total) < 0.01 THEN 'OK' ELSE 'MISMATCH' END AS result
FROM (
    SELECT 'inpatient' AS claim_type,
           (SELECT ROUND(SUM(clm_pmt_amt))  FROM staging.inpatient_header)    AS staging_total,
           (SELECT ROUND(SUM(staging.safe_to_numeric(CLM_PMT_AMT)))
            FROM raw.inpatient WHERE CLM_LINE_NUM = '1')                       AS raw_total
    UNION ALL
    SELECT 'carrier',
           (SELECT ROUND(SUM(clm_pmt_amt))  FROM staging.carrier_header),
           (SELECT ROUND(SUM(staging.safe_to_numeric(CLM_PMT_AMT)))
            FROM raw.carrier WHERE LINE_NUM = '1')
    UNION ALL
    SELECT 'pde',
           (SELECT ROUND(SUM(tot_rx_cst_amt)) FROM staging.pde),
           (SELECT ROUND(SUM(staging.safe_to_numeric(TOT_RX_CST_AMT)))
            FROM raw.pde)
) t;


-- ---------------------------------------------------------------------------
-- Step Z: Drop QA indexes (keep DB clean after validation)
-- ---------------------------------------------------------------------------

DROP INDEX IF EXISTS idx_qa_stg_bene_bene_id;
DROP INDEX IF EXISTS idx_qa_stg_inpH_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_inpL_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_outH_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_outL_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_carH_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_carL_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_dmeH_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_dmeL_clm_id;
DROP INDEX IF EXISTS idx_qa_stg_pde_bene_id;
DROP INDEX IF EXISTS idx_qa_stg_carH_bene_id;
DROP INDEX IF EXISTS idx_qa_stg_inpH_bene_id;

