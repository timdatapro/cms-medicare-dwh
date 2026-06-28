-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 11_mart_powerbi_helpers.sql
-- Purpose : Build helper tables for Power BI visualizations
--           bene_condition_count: distribution chart
--           ckd_diabetes_cost: CKD vs Diabetes cost comparison
-- Run as  : postgres on database cms_medicare
-- =============================================================================


-- =============================================================================
-- bene_condition_count: 1 row per beneficiary
-- Powers the "Beneficiaries by condition count" column chart
-- condition_group is TEXT ('0'..'7+'), sort_order is INTEGER for correct sorting
-- sex_desc denormalized here to avoid ambiguous paths in Power BI
-- =============================================================================

DROP TABLE IF EXISTS mart.bene_condition_count;
CREATE TABLE mart.bene_condition_count AS
SELECT
    b.bene_id,
    COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE)             AS condition_count,
    CASE
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 0  THEN '0'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 1  THEN '1'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 2  THEN '2'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 3  THEN '3'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 4  THEN '4'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 5  THEN '5'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) = 6  THEN '6'
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) >= 7 THEN '7+'
    END AS condition_group,
    CASE
        WHEN COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE) >= 7 THEN 7
        ELSE COUNT(*) FILTER (WHERE c.meets_ccw_criteria = TRUE)
    END::SMALLINT AS sort_order
FROM mart.dim_beneficiary b
LEFT JOIN mart.bene_chronic_conditions c ON b.bene_id = c.bene_id
GROUP BY b.bene_id;

-- Add first_claim_date_key for dim_date relationship in Power BI
ALTER TABLE mart.bene_condition_count
    ADD COLUMN IF NOT EXISTS first_claim_date_key INTEGER;

UPDATE mart.bene_condition_count bc
SET first_claim_date_key = (
    SELECT TO_CHAR(MIN(first_claim_dt), 'YYYYMMDD')::INTEGER
    FROM mart.bene_chronic_conditions c
    WHERE c.bene_id = bc.bene_id AND c.meets_ccw_criteria = TRUE
);

-- Fill NULLs (beneficiaries with 0 conditions) with 2015-01-01
UPDATE mart.bene_condition_count
SET first_claim_date_key = 20150101
WHERE first_claim_date_key IS NULL;

-- Denormalize sex_desc to avoid dim_beneficiary -> bene_condition_count path in Power BI
ALTER TABLE mart.bene_condition_count
    ADD COLUMN IF NOT EXISTS sex_desc TEXT;

UPDATE mart.bene_condition_count bc
SET sex_desc = b.sex_desc
FROM mart.dim_beneficiary b
WHERE bc.bene_id = b.bene_id;

-- Verification: 10000 rows expected
SELECT
    condition_group,
    sort_order,
    COUNT(*) AS bene_count
FROM mart.bene_condition_count
GROUP BY condition_group, sort_order
ORDER BY sort_order;


-- =============================================================================
-- Add condition_group to fact_claim_header for avg cost chart in Power BI
-- Needed because bene_condition_count has no direct join to fact_claim_header
-- =============================================================================

ALTER TABLE mart.fact_claim_header
    ADD COLUMN IF NOT EXISTS condition_group TEXT;
ALTER TABLE mart.fact_claim_header
    ADD COLUMN IF NOT EXISTS condition_sort_order SMALLINT;

UPDATE mart.fact_claim_header fch
SET
    condition_group      = COALESCE(bc.condition_group, '0'),
    condition_sort_order = bc.sort_order
FROM mart.bene_condition_count bc
WHERE fch.bene_id = bc.bene_id;

UPDATE mart.fact_claim_header
SET condition_sort_order = 0
WHERE condition_sort_order IS NULL;


-- =============================================================================
-- ckd_diabetes_cost: claims for CKD / Diabetes / CKD+Diabetes patients
-- Powers the clustered bar chart comparing cost by claim type
-- bene_id and first_claim_date_key included for filter relationships in Power BI
-- =============================================================================

DROP TABLE IF EXISTS mart.ckd_diabetes_cost;
CREATE TABLE mart.ckd_diabetes_cost AS
SELECT
    CASE
        WHEN ckd.bene_id IS NOT NULL AND dm.bene_id IS NOT NULL THEN 'CKD + Diabetes'
        WHEN ckd.bene_id IS NOT NULL                            THEN 'CKD only'
        WHEN dm.bene_id  IS NOT NULL                            THEN 'Diabetes only'
    END                                     AS patient_group,
    h.claim_type_key,
    h.clm_pmt_amt,
    h.bene_id,
    h.from_date_key                         AS first_claim_date_key
FROM mart.fact_claim_header h
LEFT JOIN (
    SELECT DISTINCT bene_id
    FROM mart.bene_chronic_conditions
    WHERE condition = 'ckd' AND meets_ccw_criteria = TRUE
) ckd ON h.bene_id = ckd.bene_id
LEFT JOIN (
    SELECT DISTINCT bene_id
    FROM mart.bene_chronic_conditions
    WHERE condition = 'diabetes' AND meets_ccw_criteria = TRUE
) dm ON h.bene_id = dm.bene_id
WHERE ckd.bene_id IS NOT NULL OR dm.bene_id IS NOT NULL;

-- Verification
SELECT
    patient_group,
    claim_type_key,
    COUNT(*)                    AS claims,
    ROUND(AVG(clm_pmt_amt), 2)  AS avg_payment
FROM mart.ckd_diabetes_cost
GROUP BY patient_group, claim_type_key
ORDER BY patient_group, claim_type_key;
