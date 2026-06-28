-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 10_mart_ccw_conditions.sql
-- Purpose : Build CCW chronic conditions mart table
--           bene_chronic_conditions: 1 row per beneficiary x condition
-- Run as  : postgres on database cms_medicare
-- =============================================================================
-- CCW (Chronic Conditions Warehouse) methodology:
--   A condition is CONFIRMED if:
--     inpatient_count >= 1  OR  outpatient_count >= 2
--   Outpatient includes: outpatient, carrier, dme, snf, hospice, hha
-- 18 conditions derived from 44 ICD-10-CM prefixes
-- =============================================================================


DROP TABLE IF EXISTS mart.bene_chronic_conditions;
CREATE TABLE mart.bene_chronic_conditions (
    bene_id             TEXT        NOT NULL,
    condition           TEXT        NOT NULL,
    condition_desc      TEXT        NOT NULL,
    first_claim_dt      DATE,
    last_claim_dt       DATE,
    claim_count         INTEGER,
    inpatient_count     INTEGER,
    outpatient_count    INTEGER,
    meets_ccw_criteria  BOOLEAN     NOT NULL,
    first_claim_year    SMALLINT,
    first_claim_date_key INTEGER,
    dwh_load_date       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (bene_id, condition)
);

INSERT INTO mart.bene_chronic_conditions (
    bene_id, condition, condition_desc,
    first_claim_dt, last_claim_dt, claim_count,
    inpatient_count, outpatient_count, meets_ccw_criteria
)
WITH ccw_codes AS (
    SELECT condition, condition_desc, icd_cd_prefix FROM (VALUES
        ('diabetes',         'Diabetes',                      'E10'),
        ('diabetes',         'Diabetes',                      'E11'),
        ('diabetes',         'Diabetes',                      'E13'),
        ('hypertension',     'Hypertension',                  'I10'),
        ('hypertension',     'Hypertension',                  'I11'),
        ('hypertension',     'Hypertension',                  'I12'),
        ('hypertension',     'Hypertension',                  'I13'),
        ('hypertension',     'Hypertension',                  'I15'),
        ('ckd',              'Chronic Kidney Disease',        'N18'),
        ('heart_failure',    'Heart Failure',                 'I50'),
        ('afib',             'Atrial Fibrillation',           'I48'),
        ('copd',             'COPD',                          'J44'),
        ('copd',             'COPD',                          'J43'),
        ('depression',       'Depression',                    'F32'),
        ('depression',       'Depression',                    'F33'),
        ('depression',       'Depression',                    'F34'),
        ('hyperlipidemia',   'Hyperlipidemia',                'E78'),
        ('ihd',              'Ischemic Heart Disease',        'I20'),
        ('ihd',              'Ischemic Heart Disease',        'I21'),
        ('ihd',              'Ischemic Heart Disease',        'I22'),
        ('ihd',              'Ischemic Heart Disease',        'I25'),
        ('stroke',           'Stroke / TIA',                  'I63'),
        ('stroke',           'Stroke / TIA',                  'I64'),
        ('stroke',           'Stroke / TIA',                  'G45'),
        ('diabetes_comp',    'Diabetes with Complications',   'E116'),
        ('diabetes_comp',    'Diabetes with Complications',   'E117'),
        ('osteoporosis',     'Osteoporosis',                  'M80'),
        ('osteoporosis',     'Osteoporosis',                  'M81'),
        ('alzheimers',       'Alzheimers / Dementia',         'G30'),
        ('alzheimers',       'Alzheimers / Dementia',         'F01'),
        ('alzheimers',       'Alzheimers / Dementia',         'F02'),
        ('alzheimers',       'Alzheimers / Dementia',         'F03'),
        ('cancer_breast',    'Breast Cancer',                 'C50'),
        ('cancer_colorectal','Colorectal Cancer',             'C18'),
        ('cancer_colorectal','Colorectal Cancer',             'C19'),
        ('cancer_colorectal','Colorectal Cancer',             'C20'),
        ('cancer_lung',      'Lung Cancer',                   'C34'),
        ('cancer_prostate',  'Prostate Cancer',               'C61'),
        ('asthma',           'Asthma',                        'J45'),
        ('obesity',          'Obesity',                       'E66'),
        ('anxiety',          'Anxiety Disorders',             'F40'),
        ('anxiety',          'Anxiety Disorders',             'F41'),
        ('schizophrenia',    'Schizophrenia / Psychosis',     'F20'),
        ('schizophrenia',    'Schizophrenia / Psychosis',     'F25')
    ) AS t(condition, condition_desc, icd_cd_prefix)
),
matched AS (
    SELECT
        d.bene_id,
        c.condition,
        c.condition_desc,
        d.clm_from_dt,
        d.claim_type_key,
        CASE WHEN d.claim_type_key = 'inpatient' THEN 1 ELSE 0 END AS is_inpatient
    FROM mart.fact_claim_diagnosis d
    JOIN ccw_codes c
      ON LEFT(d.icd_dgns_cd, LENGTH(c.icd_cd_prefix)) = c.icd_cd_prefix
),
aggregated AS (
    SELECT
        bene_id,
        condition,
        MAX(condition_desc)             AS condition_desc,
        MIN(clm_from_dt)                AS first_claim_dt,
        MAX(clm_from_dt)                AS last_claim_dt,
        COUNT(*)                        AS claim_count,
        SUM(is_inpatient)               AS inpatient_count,
        COUNT(*) - SUM(is_inpatient)    AS outpatient_count
    FROM matched
    GROUP BY bene_id, condition
)
SELECT
    bene_id, condition, condition_desc,
    first_claim_dt, last_claim_dt, claim_count,
    inpatient_count, outpatient_count,
    (inpatient_count >= 1 OR outpatient_count >= 2) AS meets_ccw_criteria
FROM aggregated;

-- Add date columns for Power BI relationship
UPDATE mart.bene_chronic_conditions
SET
    first_claim_year     = EXTRACT(YEAR FROM first_claim_dt)::SMALLINT,
    first_claim_date_key = TO_CHAR(first_claim_dt, 'YYYYMMDD')::INTEGER
WHERE first_claim_dt IS NOT NULL;

-- Verification: ~28820 rows expected
SELECT
    condition_desc,
    COUNT(*)                                        AS total_bene,
    COUNT(*) FILTER (WHERE meets_ccw_criteria)      AS confirmed_bene,
    ROUND(AVG(claim_count), 1)                      AS avg_claims
FROM mart.bene_chronic_conditions
GROUP BY condition_desc
ORDER BY confirmed_bene DESC;
