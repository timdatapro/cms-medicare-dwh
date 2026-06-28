-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 06_staging_pde.sql
-- Purpose : Transform raw.pde -> staging.pde
-- Run as  : postgres on database cms_medicare
-- =============================================================================
-- PDE has no header/line split — PDE_ID is unique per row (verified in QA).
-- 36 columns, 515 520 rows.
-- Key columns for mart.fact_pde:
--   pde_id        → unique event key
--   bene_id       → FK to dim_beneficiary
--   prod_srvc_id  → NDC (11-digit) → FK to dim_drug
--   srvc_dt       → date → FK to dim_date
--   tot_rx_cst_amt, ptnt_pay_amt, cvrd_d_plan_pd_amt → cost breakdown
-- =============================================================================


DROP TABLE IF EXISTS staging.pde;
CREATE TABLE staging.pde (

    -- Keys
    pde_id                  TEXT,
    bene_id                 TEXT,

    -- Dates
    srvc_dt                 DATE,           -- prescription fill date
    pd_dt                   DATE,           -- paid date (optional)

    -- Prescriber
    prscrbr_id_qlfyr_cd     TEXT,           -- 01=NPI, 12=DEA, etc.
    prscrbr_id              TEXT,           -- NPI of prescriber

    -- Drug (NDC)
    rx_srvc_rfrnc_num       TEXT,           -- pharmacy reference number
    prod_srvc_id            TEXT,           -- NDC 11-digit (MMMMMDDDDPP)

    -- Plan
    plan_cntrct_rec_id      TEXT,
    plan_pbp_rec_num        TEXT,

    -- Dispensing details
    cmpnd_cd                TEXT,           -- 0=not compound, 2=compound
    daw_prod_slctn_cd       TEXT,           -- dispense as written code
    qty_dspnsd_num          NUMERIC(12,3),  -- quantity dispensed
    days_suply_num          INTEGER,        -- days supply
    fill_num                INTEGER,        -- refill number
    dspnsng_stus_cd         TEXT,           -- P=partial, C=completion
    brnd_gnrc_cd            TEXT,           -- B=brand, G=generic

    -- Coverage
    drug_cvrg_stus_cd       TEXT,           -- C=covered, E=supplemental, O=OTC
    adjstmt_dltn_cd         TEXT,           -- blank=original, A=adj, D=delete
    nstd_frmt_cd            TEXT,
    prcng_excptn_cd         TEXT,
    ctstrphc_cvrg_cd        TEXT,

    -- Cost breakdown (all NUMERIC — key financial fields)
    gdc_blw_oopt_amt        NUMERIC(15,2),  -- gross cost below out-of-pocket threshold
    gdc_abv_oopt_amt        NUMERIC(15,2),  -- gross cost above out-of-pocket threshold
    ptnt_pay_amt            NUMERIC(15,2),  -- patient paid
    othr_troop_amt          NUMERIC(15,2),  -- other TrOOP payments
    lics_amt                NUMERIC(15,2),  -- low-income subsidy
    plro_amt                NUMERIC(15,2),  -- other payer reductions
    cvrd_d_plan_pd_amt      NUMERIC(15,2),  -- Part D plan paid (covered drugs)
    ncvrd_plan_pd_amt       NUMERIC(15,2),  -- plan paid (non-covered drugs)
    tot_rx_cst_amt          NUMERIC(15,2),  -- total drug cost (point of sale)
    rptd_gap_dscnt_num      NUMERIC(15,2),  -- manufacturer gap discount

    -- Misc
    rx_orgn_cd              TEXT,           -- 0=unknown,1=written,3=electronic,4=fax
    phrmcy_srvc_type_cd     TEXT,           -- 01=retail,06=mail order,etc.
    ptnt_rsdnc_cd           TEXT,           -- 01=home,03=nursing facility,etc.
    submsn_clr_cd           TEXT,           -- LTC dispensing details

    -- Audit
    dwh_load_date           TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE staging.pde IS
    '1 row per prescription drug event. '
    'No header/line split — PDE_ID is unique. '
    'Source: raw.pde. 515 520 rows.';


-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------

INSERT INTO staging.pde (
    pde_id, bene_id,
    srvc_dt, pd_dt,
    prscrbr_id_qlfyr_cd, prscrbr_id,
    rx_srvc_rfrnc_num, prod_srvc_id,
    plan_cntrct_rec_id, plan_pbp_rec_num,
    cmpnd_cd, daw_prod_slctn_cd,
    qty_dspnsd_num, days_suply_num, fill_num,
    dspnsng_stus_cd, brnd_gnrc_cd,
    drug_cvrg_stus_cd, adjstmt_dltn_cd, nstd_frmt_cd,
    prcng_excptn_cd, ctstrphc_cvrg_cd,
    gdc_blw_oopt_amt, gdc_abv_oopt_amt,
    ptnt_pay_amt, othr_troop_amt, lics_amt, plro_amt,
    cvrd_d_plan_pd_amt, ncvrd_plan_pd_amt,
    tot_rx_cst_amt, rptd_gap_dscnt_num,
    rx_orgn_cd, phrmcy_srvc_type_cd,
    ptnt_rsdnc_cd, submsn_clr_cd
)
SELECT
    staging.clean_text(PDE_ID),
    staging.clean_text(BENE_ID),
    staging.safe_to_date(SRVC_DT),
    staging.safe_to_date(PD_DT),
    staging.clean_text(PRSCRBR_ID_QLFYR_CD),
    staging.clean_text(PRSCRBR_ID),
    staging.clean_text(RX_SRVC_RFRNC_NUM),
    staging.clean_text(PROD_SRVC_ID),
    staging.clean_text(PLAN_CNTRCT_REC_ID),
    staging.clean_text(PLAN_PBP_REC_NUM),
    staging.clean_text(CMPND_CD),
    staging.clean_text(DAW_PROD_SLCTN_CD),
    staging.safe_to_numeric(QTY_DSPNSD_NUM),
    staging.safe_to_int(DAYS_SUPLY_NUM),
    staging.safe_to_int(FILL_NUM),
    staging.clean_text(DSPNSNG_STUS_CD),
    staging.clean_text(BRND_GNRC_CD),
    staging.clean_text(DRUG_CVRG_STUS_CD),
    staging.clean_text(ADJSTMT_DLTN_CD),
    staging.clean_text(NSTD_FRMT_CD),
    staging.clean_text(PRCNG_EXCPTN_CD),
    staging.clean_text(CTSTRPHC_CVRG_CD),
    staging.safe_to_numeric(GDC_BLW_OOPT_AMT),
    staging.safe_to_numeric(GDC_ABV_OOPT_AMT),
    staging.safe_to_numeric(PTNT_PAY_AMT),
    staging.safe_to_numeric(OTHR_TROOP_AMT),
    staging.safe_to_numeric(LICS_AMT),
    staging.safe_to_numeric(PLRO_AMT),
    staging.safe_to_numeric(CVRD_D_PLAN_PD_AMT),
    staging.safe_to_numeric(NCVRD_PLAN_PD_AMT),
    staging.safe_to_numeric(TOT_RX_CST_AMT),
    staging.safe_to_numeric(RPTD_GAP_DSCNT_NUM),
    staging.clean_text(RX_ORGN_CD),
    staging.clean_text(PHRMCY_SRVC_TYPE_CD),
    staging.clean_text(PTNT_RSDNC_CD),
    staging.clean_text(SUBMSN_CLR_CD)
FROM raw.pde;


-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

SELECT
    COUNT(*)                                          AS total_rows,
    COUNT(DISTINCT pde_id)                            AS unique_pde_ids,
    COUNT(*) FILTER (WHERE pde_id IS NULL)            AS null_pde_id,
    COUNT(*) FILTER (WHERE bene_id IS NULL)           AS null_bene_id,
    COUNT(*) FILTER (WHERE srvc_dt IS NULL)           AS null_srvc_dt,
    COUNT(*) FILTER (WHERE prod_srvc_id IS NULL)      AS null_ndc,
    COUNT(*) FILTER (WHERE tot_rx_cst_amt IS NULL)    AS null_cost,
    MIN(srvc_dt)                                      AS min_date,
    MAX(srvc_dt)                                      AS max_date,
    ROUND(SUM(tot_rx_cst_amt))                        AS total_drug_cost,
    ROUND(AVG(tot_rx_cst_amt), 2)                     AS avg_cost_per_event
FROM staging.pde;

-- Brand vs generic breakdown
SELECT
    brnd_gnrc_cd,
    COUNT(*)                        AS events,
    ROUND(SUM(tot_rx_cst_amt))      AS total_cost,
    ROUND(AVG(tot_rx_cst_amt), 2)   AS avg_cost
FROM staging.pde
GROUP BY brnd_gnrc_cd
ORDER BY events DESC;

-- Coverage status breakdown
SELECT
    drug_cvrg_stus_cd,
    CASE drug_cvrg_stus_cd
        WHEN 'C' THEN 'Covered by Part D'
        WHEN 'E' THEN 'Supplemental'
        WHEN 'O' THEN 'Over-the-counter'
        ELSE 'Unknown'
    END                             AS description,
    COUNT(*)                        AS events,
    ROUND(SUM(tot_rx_cst_amt))      AS total_cost
FROM staging.pde
GROUP BY drug_cvrg_stus_cd
ORDER BY events DESC;
