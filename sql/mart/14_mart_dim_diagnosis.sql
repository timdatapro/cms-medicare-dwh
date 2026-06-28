DROP TABLE IF EXISTS mart.dim_diagnosis;
CREATE TABLE mart.dim_diagnosis (
    icd_dgns_cd     TEXT        PRIMARY KEY,
    description     TEXT,
    is_billable     BOOLEAN,
    chapter_num     TEXT,
    chapter_desc    TEXT,
    block_code      TEXT,
    block_desc      TEXT,
    parent_code     TEXT,
    parent_desc     TEXT,
    dwh_load_date   TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

\COPY mart.dim_diagnosis (icd_dgns_cd, description, is_billable, chapter_num, chapter_desc, block_code, block_desc, parent_code, parent_desc) FROM 'C:/Temp/cms_medicare/icd10cm.csv' WITH (FORMAT csv, HEADER true, NULL '');

SELECT
    COUNT(*)                                    AS total_codes,
    COUNT(*) FILTER (WHERE is_billable)         AS billable_codes,
    COUNT(*) FILTER (WHERE NOT is_billable)     AS header_codes,
    COUNT(DISTINCT chapter_num)                 AS chapters
FROM mart.dim_diagnosis;

SELECT
    COUNT(DISTINCT f.icd_dgns_cd)               AS codes_in_claims,
    COUNT(DISTINCT CASE WHEN d.icd_dgns_cd IS NOT NULL
          THEN f.icd_dgns_cd END)               AS matched_in_dim,
    ROUND(COUNT(DISTINCT CASE WHEN d.icd_dgns_cd IS NOT NULL
          THEN f.icd_dgns_cd END) * 100.0
          / COUNT(DISTINCT f.icd_dgns_cd), 1)   AS coverage_pct
FROM mart.fact_claim_diagnosis f
LEFT JOIN mart.dim_diagnosis d ON f.icd_dgns_cd = d.icd_dgns_cd;
