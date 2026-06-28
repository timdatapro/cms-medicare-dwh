-- =============================================================================
-- CMS Synthetic Medicare Claims DWH
-- Script  : 08_mart_dimensions.sql
-- Purpose : Build mart dimensions: dim_date, dim_claim_type, dim_beneficiary
-- Run as  : postgres on database cms_medicare
-- =============================================================================


-- =============================================================================
-- dim_date: 2014-01-01 to 2025-12-31
-- date_key = YYYYMMDD integer (e.g. 20200101)
-- Starts 2014 to cover one hospice claim dated 2014-11-18 (CMS User Guide edge case)
-- =============================================================================

DROP TABLE IF EXISTS mart.dim_date;
CREATE TABLE mart.dim_date (
    date_key            INTEGER     PRIMARY KEY,    -- YYYYMMDD
    full_date           DATE        NOT NULL,
    year                SMALLINT    NOT NULL,
    quarter             SMALLINT    NOT NULL,
    month               SMALLINT    NOT NULL,
    month_name          TEXT        NOT NULL,
    week_of_year        SMALLINT    NOT NULL,
    day_of_month        SMALLINT    NOT NULL,
    day_of_week         SMALLINT    NOT NULL,
    day_name            TEXT        NOT NULL,
    is_weekend          BOOLEAN     NOT NULL,
    cms_fiscal_year     SMALLINT    NOT NULL,
    cms_fiscal_quarter  SMALLINT    NOT NULL
);

INSERT INTO mart.dim_date (
    date_key, full_date, year, quarter, month, month_name,
    week_of_year, day_of_month, day_of_week, day_name,
    is_weekend, cms_fiscal_year, cms_fiscal_quarter
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER                                 AS date_key,
    d                                                               AS full_date,
    EXTRACT(YEAR    FROM d)::SMALLINT                               AS year,
    EXTRACT(QUARTER FROM d)::SMALLINT                               AS quarter,
    EXTRACT(MONTH   FROM d)::SMALLINT                               AS month,
    TO_CHAR(d, 'Month')                                             AS month_name,
    EXTRACT(WEEK    FROM d)::SMALLINT                               AS week_of_year,
    EXTRACT(DAY     FROM d)::SMALLINT                               AS day_of_month,
    EXTRACT(DOW     FROM d)::SMALLINT                               AS day_of_week,
    TO_CHAR(d, 'Day')                                               AS day_name,
    EXTRACT(DOW FROM d) IN (0, 6)                                   AS is_weekend,
    -- CMS fiscal year: Oct 1 of year N = start of FY N+1
    CASE WHEN EXTRACT(MONTH FROM d) >= 10
         THEN EXTRACT(YEAR FROM d)::SMALLINT + 1
         ELSE EXTRACT(YEAR FROM d)::SMALLINT
    END                                                             AS cms_fiscal_year,
    -- CMS fiscal quarter: Q1=Oct-Dec, Q2=Jan-Mar, Q3=Apr-Jun, Q4=Jul-Sep
    CASE
        WHEN EXTRACT(MONTH FROM d) IN (10, 11, 12) THEN 1
        WHEN EXTRACT(MONTH FROM d) IN (1,  2,  3)  THEN 2
        WHEN EXTRACT(MONTH FROM d) IN (4,  5,  6)  THEN 3
        ELSE 4
    END::SMALLINT                                                   AS cms_fiscal_quarter
FROM GENERATE_SERIES('2014-01-01'::DATE, '2025-12-31'::DATE, '1 day'::INTERVAL) AS gs(d);

-- Verification: 4383 rows expected
SELECT COUNT(*) AS total_days,
       MIN(full_date) AS min_date,
       MAX(full_date) AS max_date
FROM mart.dim_date;


-- =============================================================================
-- dim_claim_type: 7 FFS claim types
-- =============================================================================

DROP TABLE IF EXISTS mart.dim_claim_type;
CREATE TABLE mart.dim_claim_type (
    claim_type_key  TEXT    PRIMARY KEY,
    claim_type_desc TEXT    NOT NULL,
    is_part_a       BOOLEAN NOT NULL,
    is_part_b       BOOLEAN NOT NULL,
    nch_clm_type_cd TEXT
);

INSERT INTO mart.dim_claim_type VALUES
    ('inpatient',  'Inpatient Hospital',             TRUE,  FALSE, '60'),
    ('outpatient', 'Outpatient Hospital',             FALSE, TRUE,  '40'),
    ('carrier',    'Carrier (Physician/Supplier)',    FALSE, TRUE,  '71'),
    ('dme',        'Durable Medical Equipment',       FALSE, TRUE,  '82'),
    ('snf',        'Skilled Nursing Facility',        TRUE,  FALSE, '20'),
    ('hospice',    'Hospice',                         TRUE,  FALSE, '50'),
    ('hha',        'Home Health Agency',              TRUE,  FALSE, '10');

SELECT * FROM mart.dim_claim_type ORDER BY claim_type_key;


-- =============================================================================
-- dim_beneficiary: 1 row per beneficiary from most recent snapshot year
-- Uses DISTINCT ON to select the latest available year per bene_id
-- bene_id kept as natural key (stable synthetic negative integer, no surrogate needed)
-- =============================================================================

DROP TABLE IF EXISTS mart.dim_beneficiary;
CREATE TABLE mart.dim_beneficiary (
    bene_id             TEXT        PRIMARY KEY,
    bene_birth_dt       DATE,
    bene_death_dt       DATE,
    sex_desc            TEXT,
    race_desc           TEXT,
    is_alive            BOOLEAN,
    state_code          TEXT,
    county_cd           TEXT,
    zip_cd              TEXT,
    esrd_ind            TEXT,
    entlmt_rsn_orig     TEXT,
    entlmt_rsn_curr     TEXT,
    first_year_in_data  SMALLINT,
    last_year_in_data   SMALLINT,
    years_in_data       SMALLINT,
    dwh_load_date       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO mart.dim_beneficiary (
    bene_id, bene_birth_dt, bene_death_dt, sex_desc, race_desc, is_alive,
    state_code, county_cd, zip_cd, esrd_ind, entlmt_rsn_orig, entlmt_rsn_curr,
    first_year_in_data, last_year_in_data, years_in_data
)
WITH latest AS (
    SELECT DISTINCT ON (bene_id)
        bene_id, bene_birth_dt, bene_death_dt, sex_ident_cd,
        bene_race_cd, rti_race_cd, state_code, county_cd, zip_cd,
        esrd_ind, entlmt_rsn_orig, entlmt_rsn_curr
    FROM staging.beneficiary
    ORDER BY bene_id, enrollmt_ref_yr DESC
),
year_stats AS (
    SELECT bene_id,
           MIN(enrollmt_ref_yr)  AS first_year,
           MAX(enrollmt_ref_yr)  AS last_year,
           COUNT(*)::SMALLINT    AS years_count
    FROM staging.beneficiary
    GROUP BY bene_id
)
SELECT
    l.bene_id,
    l.bene_birth_dt,
    l.bene_death_dt,
    CASE l.sex_ident_cd
        WHEN '1' THEN 'Male'
        WHEN '2' THEN 'Female'
        ELSE 'Unknown'
    END AS sex_desc,
    CASE l.rti_race_cd
        WHEN '1' THEN 'White'
        WHEN '2' THEN 'Black'
        WHEN '4' THEN 'Asian/Pacific Islander'
        WHEN '5' THEN 'Hispanic'
        WHEN '6' THEN 'American Indian/Alaska Native'
        ELSE 'Unknown'
    END AS race_desc,
    l.bene_death_dt IS NULL     AS is_alive,
    l.state_code,
    l.county_cd,
    l.zip_cd,
    l.esrd_ind,
    l.entlmt_rsn_orig,
    l.entlmt_rsn_curr,
    y.first_year                AS first_year_in_data,
    y.last_year                 AS last_year_in_data,
    y.years_count               AS years_in_data
FROM latest l
JOIN year_stats y ON l.bene_id = y.bene_id;

-- Verification: 10000 rows expected
SELECT
    COUNT(*)                                        AS total_bene,
    COUNT(*) FILTER (WHERE is_alive)                AS alive,
    COUNT(*) FILTER (WHERE NOT is_alive)            AS deceased,
    COUNT(*) FILTER (WHERE sex_desc = 'Male')       AS male,
    COUNT(*) FILTER (WHERE sex_desc = 'Female')     AS female
FROM mart.dim_beneficiary;
