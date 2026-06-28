-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 09_mart_facts.sql
-- Purpose : Build mart fact tables:
--           fact_enrollment, fact_claim_header,
--           fact_claim_diagnosis, fact_pde
-- Run as  : postgres on database cms_medicare
-- =============================================================================


-- =============================================================================
-- fact_enrollment: 1 row per beneficiary x year
-- Grain: annual Medicare enrollment snapshot
-- =============================================================================

DROP TABLE IF EXISTS mart.fact_enrollment;
CREATE TABLE mart.fact_enrollment (
    bene_id                 TEXT        NOT NULL,
    enrollmt_ref_yr         SMALLINT    NOT NULL,
    part_a_months           SMALLINT,
    part_b_months           SMALLINT,
    hmo_months              SMALLINT,
    dual_elgbl_months       SMALLINT,
    part_d_months           SMALLINT,
    is_full_year_part_a     BOOLEAN,
    is_full_year_part_b     BOOLEAN,
    is_full_year_part_d     BOOLEAN,
    is_any_dual_eligible    BOOLEAN,
    is_any_hmo              BOOLEAN,
    is_partial_year         BOOLEAN     DEFAULT FALSE,
    PRIMARY KEY (bene_id, enrollmt_ref_yr)
);

INSERT INTO mart.fact_enrollment (
    bene_id, enrollmt_ref_yr,
    part_a_months, part_b_months, hmo_months,
    dual_elgbl_months, part_d_months,
    is_full_year_part_a, is_full_year_part_b, is_full_year_part_d,
    is_any_dual_eligible, is_any_hmo
)
SELECT
    bene_id,
    enrollmt_ref_yr,
    bene_hi_cvrage_tot_mons     AS part_a_months,
    bene_smi_cvrage_tot_mons    AS part_b_months,
    bene_hmo_cvrage_tot_mons    AS hmo_months,
    dual_elgbl_mons             AS dual_elgbl_months,
    ptd_plan_cvrg_mons          AS part_d_months,
    bene_hi_cvrage_tot_mons  = 12   AS is_full_year_part_a,
    bene_smi_cvrage_tot_mons = 12   AS is_full_year_part_b,
    ptd_plan_cvrg_mons       = 12   AS is_full_year_part_d,
    dual_elgbl_mons          > 0    AS is_any_dual_eligible,
    bene_hmo_cvrage_tot_mons > 0    AS is_any_hmo
FROM staging.beneficiary;

-- Flag 2025 as partial year (only January-March covered)
UPDATE mart.fact_enrollment
SET is_partial_year = TRUE
WHERE enrollmt_ref_yr = 2025;

-- Verification: 86917 rows expected
SELECT
    COUNT(*)                AS total_rows,
    COUNT(DISTINCT bene_id) AS unique_bene,
    MIN(enrollmt_ref_yr)    AS min_year,
    MAX(enrollmt_ref_yr)    AS max_year,
    COUNT(*) FILTER (WHERE is_partial_year) AS partial_year_rows
FROM mart.fact_enrollment;


-- =============================================================================
-- fact_claim_header: 1 row per claim, all 7 types combined
-- CRITICAL: CLM_PMT_AMT always from header, never summed from lines (fan-trap risk)
-- Grain: 1 claim per row, typed by claim_type_key
-- =============================================================================

DROP TABLE IF EXISTS mart.fact_claim_header;
CREATE TABLE mart.fact_claim_header (
    clm_id              TEXT        PRIMARY KEY,
    bene_id             TEXT        NOT NULL,
    claim_type_key      TEXT        NOT NULL,
    clm_from_dt         DATE,
    clm_thru_dt         DATE,
    from_date_key       INTEGER,        -- FK to dim_date
    thru_date_key       INTEGER,        -- FK to dim_date
    clm_pmt_amt         NUMERIC(15,2),
    clm_tot_chrg_amt    NUMERIC(15,2),
    prncpal_dgns_cd     TEXT,
    prvdr_state_cd      TEXT,
    org_npi_num         TEXT,
    clm_admsn_dt        DATE,
    nch_bene_dschrg_dt  DATE,
    clm_drg_cd          TEXT,
    clm_utlztn_day_cnt  INTEGER,
    ptnt_dschrg_stus_cd TEXT,
    condition_group     TEXT,
    condition_sort_order SMALLINT,
    dwh_load_date       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO mart.fact_claim_header (
    clm_id, bene_id, claim_type_key,
    clm_from_dt, clm_thru_dt, from_date_key, thru_date_key,
    clm_pmt_amt, clm_tot_chrg_amt, prncpal_dgns_cd,
    prvdr_state_cd, org_npi_num,
    clm_admsn_dt, nch_bene_dschrg_dt, clm_drg_cd,
    clm_utlztn_day_cnt, ptnt_dschrg_stus_cd
)
SELECT clm_id, bene_id, 'inpatient' AS claim_type_key,
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER AS from_date_key,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER AS thru_date_key,
    clm_pmt_amt, clm_tot_chrg_amt, prncpal_dgns_cd,
    prvdr_state_cd, org_npi_num,
    clm_admsn_dt, nch_bene_dschrg_dt, clm_drg_cd,
    clm_utlztn_day_cnt, ptnt_dschrg_stus_cd
FROM staging.inpatient_header

UNION ALL SELECT clm_id, bene_id, 'outpatient',
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER,
    clm_pmt_amt, clm_tot_chrg_amt, prncpal_dgns_cd,
    prvdr_state_cd, org_npi_num,
    NULL, NULL, NULL, NULL, ptnt_dschrg_stus_cd
FROM staging.outpatient_header

UNION ALL SELECT clm_id, bene_id, 'carrier',
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER,
    clm_pmt_amt, NULL, prncpal_dgns_cd,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM staging.carrier_header

UNION ALL SELECT clm_id, bene_id, 'dme',
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER,
    clm_pmt_amt, NULL, prncpal_dgns_cd,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM staging.dme_header

UNION ALL SELECT clm_id, bene_id, 'snf',
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER,
    clm_pmt_amt, clm_tot_chrg_amt, prncpal_dgns_cd,
    prvdr_state_cd, org_npi_num,
    clm_admsn_dt, nch_bene_dschrg_dt, clm_drg_cd,
    clm_utlztn_day_cnt, ptnt_dschrg_stus_cd
FROM staging.snf_header

UNION ALL SELECT clm_id, bene_id, 'hospice',
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER,
    clm_pmt_amt, clm_tot_chrg_amt, prncpal_dgns_cd,
    prvdr_state_cd, org_npi_num,
    NULL, nch_bene_dschrg_dt, NULL,
    clm_utlztn_day_cnt, ptnt_dschrg_stus_cd
FROM staging.hospice_header

UNION ALL SELECT clm_id, bene_id, 'hha',
    clm_from_dt, clm_thru_dt,
    TO_CHAR(clm_from_dt, 'YYYYMMDD')::INTEGER,
    TO_CHAR(clm_thru_dt, 'YYYYMMDD')::INTEGER,
    clm_pmt_amt, clm_tot_chrg_amt, prncpal_dgns_cd,
    prvdr_state_cd, org_npi_num,
    clm_admsn_dt, NULL, NULL, NULL, ptnt_dschrg_stus_cd
FROM staging.hha_header;

-- Verification: 555218 rows expected
SELECT
    claim_type_key,
    COUNT(*)                    AS claims,
    ROUND(SUM(clm_pmt_amt))     AS total_pmt,
    ROUND(AVG(clm_pmt_amt), 2)  AS avg_pmt
FROM mart.fact_claim_header
GROUP BY claim_type_key
ORDER BY claims DESC;


-- =============================================================================
-- fact_claim_diagnosis: long-format diagnoses
-- Grain: 1 row per claim x diagnosis position
-- Unpivots ICD_DGNS_CD1..25 from fact_claim_header source tables
-- =============================================================================

DROP TABLE IF EXISTS mart.fact_claim_diagnosis;
CREATE TABLE mart.fact_claim_diagnosis (
    clm_id          TEXT        NOT NULL,
    bene_id         TEXT        NOT NULL,
    claim_type_key  TEXT        NOT NULL,
    clm_from_dt     DATE,
    icd_dgns_cd     TEXT        NOT NULL,
    dgns_position   SMALLINT    NOT NULL,   -- 1 = principal, 2..25 = additional
    dwh_load_date   TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Inpatient: unpivot ICD_DGNS_CD1..25
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'inpatient', clm_from_dt, icd_cd, pos
FROM staging.inpatient_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1,  1), (icd_dgns_cd2,  2), (icd_dgns_cd3,  3),
    (icd_dgns_cd4,  4), (icd_dgns_cd5,  5), (icd_dgns_cd6,  6),
    (icd_dgns_cd7,  7), (icd_dgns_cd8,  8), (icd_dgns_cd9,  9),
    (icd_dgns_cd10, 10),(icd_dgns_cd11, 11),(icd_dgns_cd12, 12),
    (icd_dgns_cd13, 13),(icd_dgns_cd14, 14),(icd_dgns_cd15, 15),
    (icd_dgns_cd16, 16),(icd_dgns_cd17, 17),(icd_dgns_cd18, 18),
    (icd_dgns_cd19, 19),(icd_dgns_cd20, 20),(icd_dgns_cd21, 21),
    (icd_dgns_cd22, 22),(icd_dgns_cd23, 23),(icd_dgns_cd24, 24),
    (icd_dgns_cd25, 25)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- Outpatient
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'outpatient', clm_from_dt, icd_cd, pos
FROM staging.outpatient_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1,  1), (icd_dgns_cd2,  2), (icd_dgns_cd3,  3),
    (icd_dgns_cd4,  4), (icd_dgns_cd5,  5), (icd_dgns_cd6,  6),
    (icd_dgns_cd7,  7), (icd_dgns_cd8,  8), (icd_dgns_cd9,  9),
    (icd_dgns_cd10, 10),(icd_dgns_cd11, 11),(icd_dgns_cd12, 12),
    (icd_dgns_cd13, 13),(icd_dgns_cd14, 14),(icd_dgns_cd15, 15),
    (icd_dgns_cd16, 16),(icd_dgns_cd17, 17),(icd_dgns_cd18, 18),
    (icd_dgns_cd19, 19),(icd_dgns_cd20, 20),(icd_dgns_cd21, 21),
    (icd_dgns_cd22, 22),(icd_dgns_cd23, 23),(icd_dgns_cd24, 24),
    (icd_dgns_cd25, 25)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- Carrier
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'carrier', clm_from_dt, icd_cd, pos
FROM staging.carrier_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1, 1),(icd_dgns_cd2, 2),(icd_dgns_cd3, 3),
    (icd_dgns_cd4, 4),(icd_dgns_cd5, 5),(icd_dgns_cd6, 6),
    (icd_dgns_cd7, 7),(icd_dgns_cd8, 8)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- DME
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'dme', clm_from_dt, icd_cd, pos
FROM staging.dme_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1, 1),(icd_dgns_cd2, 2),(icd_dgns_cd3, 3),
    (icd_dgns_cd4, 4),(icd_dgns_cd5, 5)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- SNF
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'snf', clm_from_dt, icd_cd, pos
FROM staging.snf_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1,  1),(icd_dgns_cd2,  2),(icd_dgns_cd3,  3),
    (icd_dgns_cd4,  4),(icd_dgns_cd5,  5),(icd_dgns_cd6,  6),
    (icd_dgns_cd7,  7),(icd_dgns_cd8,  8),(icd_dgns_cd9,  9),
    (icd_dgns_cd10, 10),(icd_dgns_cd11, 11),(icd_dgns_cd12, 12),
    (icd_dgns_cd13, 13),(icd_dgns_cd14, 14),(icd_dgns_cd15, 15),
    (icd_dgns_cd16, 16),(icd_dgns_cd17, 17),(icd_dgns_cd18, 18),
    (icd_dgns_cd19, 19),(icd_dgns_cd20, 20),(icd_dgns_cd21, 21),
    (icd_dgns_cd22, 22),(icd_dgns_cd23, 23),(icd_dgns_cd24, 24),
    (icd_dgns_cd25, 25)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- Hospice
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'hospice', clm_from_dt, icd_cd, pos
FROM staging.hospice_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1, 1),(icd_dgns_cd2, 2),(icd_dgns_cd3, 3),
    (icd_dgns_cd4, 4),(icd_dgns_cd5, 5),(icd_dgns_cd6, 6)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- HHA
INSERT INTO mart.fact_claim_diagnosis (clm_id, bene_id, claim_type_key, clm_from_dt, icd_dgns_cd, dgns_position)
SELECT clm_id, bene_id, 'hha', clm_from_dt, icd_cd, pos
FROM staging.hha_header
CROSS JOIN LATERAL (VALUES
    (icd_dgns_cd1, 1),(icd_dgns_cd2, 2),(icd_dgns_cd3, 3),
    (icd_dgns_cd4, 4),(icd_dgns_cd5, 5),(icd_dgns_cd6, 6),
    (icd_dgns_cd7, 7),(icd_dgns_cd8, 8),(icd_dgns_cd9, 9),
    (icd_dgns_cd10, 10),(icd_dgns_cd11, 11),(icd_dgns_cd12, 12),
    (icd_dgns_cd13, 13),(icd_dgns_cd14, 14),(icd_dgns_cd15, 15),
    (icd_dgns_cd16, 16),(icd_dgns_cd17, 17),(icd_dgns_cd18, 18),
    (icd_dgns_cd19, 19),(icd_dgns_cd20, 20),(icd_dgns_cd21, 21),
    (icd_dgns_cd22, 22),(icd_dgns_cd23, 23),(icd_dgns_cd24, 24),
    (icd_dgns_cd25, 25)
) AS t(icd_cd, pos)
WHERE icd_cd IS NOT NULL;

-- Verification: ~9,535,901 rows expected
SELECT
    claim_type_key,
    COUNT(*)                        AS diagnosis_rows,
    COUNT(DISTINCT clm_id)          AS unique_claims,
    COUNT(DISTINCT icd_dgns_cd)     AS unique_codes
FROM mart.fact_claim_diagnosis
GROUP BY claim_type_key
ORDER BY diagnosis_rows DESC;


-- =============================================================================
-- fact_pde: 1 row per prescription drug event
-- Grain: one dispensing event per row
-- =============================================================================

DROP TABLE IF EXISTS mart.fact_pde;
CREATE TABLE mart.fact_pde (
    pde_id              TEXT        PRIMARY KEY,
    bene_id             TEXT        NOT NULL,
    srvc_dt             DATE,
    srvc_date_key       INTEGER,        -- FK to dim_date
    prod_srvc_id        TEXT,           -- NDC 11-digit
    prscrbr_id          TEXT,
    plan_cntrct_rec_id  TEXT,
    days_suply_num      INTEGER,
    qty_dspnsd_num      NUMERIC(12,3),
    fill_num            INTEGER,
    brnd_gnrc_cd        TEXT,           -- B=brand, G=generic
    drug_cvrg_stus_cd   TEXT,           -- C=covered, E=supplemental, O=OTC
    tot_rx_cst_amt      NUMERIC(15,2),
    ptnt_pay_amt        NUMERIC(15,2),
    cvrd_d_plan_pd_amt  NUMERIC(15,2),
    lics_amt            NUMERIC(15,2),
    dwh_load_date       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO mart.fact_pde (
    pde_id, bene_id, srvc_dt, srvc_date_key,
    prod_srvc_id, prscrbr_id, plan_cntrct_rec_id,
    days_suply_num, qty_dspnsd_num, fill_num,
    brnd_gnrc_cd, drug_cvrg_stus_cd,
    tot_rx_cst_amt, ptnt_pay_amt, cvrd_d_plan_pd_amt, lics_amt
)
SELECT
    pde_id, bene_id, srvc_dt,
    TO_CHAR(srvc_dt, 'YYYYMMDD')::INTEGER AS srvc_date_key,
    prod_srvc_id, prscrbr_id, plan_cntrct_rec_id,
    days_suply_num, qty_dspnsd_num, fill_num,
    brnd_gnrc_cd, drug_cvrg_stus_cd,
    tot_rx_cst_amt, ptnt_pay_amt, cvrd_d_plan_pd_amt, lics_amt
FROM staging.pde;

-- Verification: 515520 rows expected
SELECT
    COUNT(*)                        AS total_pde,
    ROUND(SUM(tot_rx_cst_amt))      AS total_drug_cost,
    ROUND(AVG(tot_rx_cst_amt), 2)   AS avg_cost_per_event,
    COUNT(DISTINCT bene_id)         AS unique_bene,
    COUNT(DISTINCT prod_srvc_id)    AS unique_ndcs
FROM mart.fact_pde;
