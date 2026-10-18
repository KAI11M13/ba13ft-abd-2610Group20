-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- MySQL cleaning pipeline, step 2 of 5: clean the staging tables
--
-- Input : stg_*_raw tables from 01_load_raw.sql (all fields as text)
-- Output: cln_registration, cln_coe, cln_fleet, cln_mvp02, cln_charger
-- Rules : the same cleaning definitions as the Python double-check notebook
--         (cleaned_data/01_clean_data.ipynb), so the two results can be compared.
-- =====================================================================

USE byd_bev_sg;

-- ---------------------------------------------------------------------
-- 2.0 Reference: body type labels used by LTA in M03 and MVP02
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ref_body_map;
CREATE TABLE ref_body_map (
    body_id      TINYINT UNSIGNED NOT NULL,
    source_label VARCHAR(60)      NOT NULL COMMENT 'Label as written by LTA',
    body_type    VARCHAR(40)      NOT NULL COMMENT 'Standardised label used in analysis',
    is_in_scope  TINYINT(1)       NOT NULL,
    is_combined  TINYINT(1)       NOT NULL COMMENT '1 for the combined MPV/Station Wagon label in MVP02',
    PRIMARY KEY (body_id),
    UNIQUE KEY uq_ref_body_label (source_label)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO ref_body_map VALUES
(1, 'Sports Utility Vehicle',              'SUV',               1, 0),
(2, 'Sedan',                               'Sedan',             1, 0),
(3, 'Multi-purpose Vehicle',               'MPV',               1, 0),
(4, 'Hatchback',                           'Hatchback',         0, 0),
(5, 'Station-wagon',                       'Station Wagon',     0, 0),
(6, 'Coupe/ Convertible',                  'Coupe/Convertible', 0, 0),
(7, 'Multi-purpose Vehicle/Station-wagon', 'MPV/Station Wagon', 0, 1);

-- =====================================================================
-- 2.1 M03 monthly registrations
-- =====================================================================

-- C1 every month is in YYYY-MM format
CALL etl_check('clean', 'M03 rows with unparseable month',
    (SELECT COUNT(*) FROM stg_m03_raw WHERE month NOT REGEXP '^[0-9]{4}-(0[1-9]|1[0-2])$'), 0);

-- Study window: July 2022 (LTA split MPV from Station Wagon) to July 2026 (latest month)
DROP TABLE IF EXISTS tmp_m03_window;
CREATE TABLE tmp_m03_window AS
SELECT row_id, month, make, importer_type, fuel_type, vehicle_type, number
FROM stg_m03_raw
WHERE month BETWEEN '2022-07' AND '2026-07';

-- C2 the window contains data
CALL etl_check('clean', 'M03 study window 2022-07 to 2026-07 contains rows',
    (SELECT COUNT(*) > 0 FROM tmp_m03_window), 1);
CALL etl_info('clean', 'M03 rows in window', (SELECT COUNT(*) FROM tmp_m03_window));

-- C3 key fields are filled
CALL etl_check('clean', 'M03 rows missing make, fuel_type or vehicle_type',
    (SELECT COUNT(*) FROM tmp_m03_window WHERE make = '' OR fuel_type = '' OR vehicle_type = ''), 0);

-- LTA writes zero as a blank count
CALL etl_info('clean', 'M03 blank counts treated as 0',
    (SELECT COUNT(*) FROM tmp_m03_window WHERE number = ''));

-- C4 every non-blank count is a non-negative whole number
CALL etl_check('clean', 'M03 rows with invalid counts',
    (SELECT COUNT(*) FROM tmp_m03_window WHERE number <> '' AND number NOT REGEXP '^[0-9]+([.]0+)?$'), 0);

-- C5 no repeated raw records at the source grain
CALL etl_check('clean', 'M03 raw duplicate rows (month, make, importer, fuel, body)',
    (SELECT COALESCE(SUM(n), 0) FROM (
        SELECT COUNT(*) AS n FROM tmp_m03_window
        GROUP BY month, make, importer_type, fuel_type, vehicle_type
        HAVING COUNT(*) > 1) d), 0);

-- C6 blank and specified importer rows with registrations never share a group,
--    so summing importer types cannot double count
CALL etl_check('clean', 'M03 importer overlap groups',
    (SELECT COUNT(*) FROM (
        SELECT month, make, fuel_type, vehicle_type
        FROM tmp_m03_window
        WHERE number <> '' AND CAST(number AS DECIMAL(12,2)) > 0
        GROUP BY month, make, fuel_type, vehicle_type
        HAVING SUM(importer_type = '') > 0 AND SUM(importer_type <> '') > 0) o), 0);

-- C7 every body label maps to a standard body type
CALL etl_check('clean', 'M03 unmapped body type labels',
    (SELECT COUNT(DISTINCT w.vehicle_type) FROM tmp_m03_window w
     LEFT JOIN ref_body_map b ON b.source_label = w.vehicle_type AND b.is_combined = 0
     WHERE b.body_id IS NULL), 0);

-- Typed row-level table: blank -> 0, standard body type, upper-case make
DROP TABLE IF EXISTS tmp_m03_typed;
CREATE TABLE tmp_m03_typed AS
SELECT w.month                                         AS month_key,
       UPPER(w.make)                                   AS make_name,
       w.importer_type,
       w.fuel_type,
       b.body_type,
       CAST(IF(w.number = '', '0', w.number) AS DECIMAL(12,0)) AS registrations
FROM tmp_m03_window w
JOIN ref_body_map b ON b.source_label = w.vehicle_type AND b.is_combined = 0;

-- Aggregate to the analysis grain: month x make x fuel x body (AMD and PI summed)
DROP TABLE IF EXISTS cln_registration;
CREATE TABLE cln_registration (
    month_key      CHAR(7)      NOT NULL,
    make_name      VARCHAR(60)  NOT NULL,
    fuel_type      VARCHAR(40)  NOT NULL,
    body_type      VARCHAR(40)  NOT NULL,
    registrations  INT UNSIGNED NOT NULL,
    PRIMARY KEY (month_key, make_name, fuel_type, body_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO cln_registration (month_key, make_name, fuel_type, body_type, registrations)
SELECT month_key, make_name, fuel_type, body_type, SUM(registrations)
FROM tmp_m03_typed
GROUP BY month_key, make_name, fuel_type, body_type;

-- C8 one row per key at the final grain
CALL etl_check('clean', 'M03 duplicate keys in final table',
    (SELECT COUNT(*) - COUNT(DISTINCT month_key, make_name, fuel_type, body_type) FROM cln_registration), 0);

-- C9 aggregation keeps every registration
CALL etl_check('clean', 'M03 total registrations after aggregation equals total before',
    (SELECT SUM(registrations) FROM cln_registration),
    (SELECT SUM(registrations) FROM tmp_m03_typed));

-- C10 no negative registrations
CALL etl_check('clean', 'M03 rows with negative registrations',
    (SELECT COUNT(*) FROM tmp_m03_typed WHERE registrations < 0), 0);

-- C11 SUV, Sedan and MPV each cover all 49 months
CALL etl_check('clean', 'M03 segments covering all 49 months (SUV, Sedan, MPV)',
    (SELECT COUNT(*) FROM (
        SELECT body_type FROM cln_registration
        WHERE body_type IN ('SUV', 'Sedan', 'MPV')
        GROUP BY body_type
        HAVING COUNT(DISTINCT month_key) = 49) s), 3);

-- C12 every month-make-fuel combination carries all six body types
CALL etl_check('clean', 'M03 month-make-fuel combinations missing a body type',
    (SELECT COUNT(*) FROM (
        SELECT month_key, make_name, fuel_type FROM cln_registration
        GROUP BY month_key, make_name, fuel_type
        HAVING COUNT(*) <> 6) g), 0);

CALL etl_info('clean', 'M03 total registrations', (SELECT SUM(registrations) FROM cln_registration));
CALL etl_info('clean', 'M03 final table rows', (SELECT COUNT(*) FROM cln_registration));

-- =====================================================================
-- 2.2 COE bidding results
-- =====================================================================

-- C13 every month is in YYYY-MM format
CALL etl_check('clean', 'COE rows with unparseable month',
    (SELECT COUNT(*) FROM stg_coe_raw WHERE month NOT REGEXP '^[0-9]{4}-(0[1-9]|1[0-2])$'), 0);

CALL etl_info('clean', 'COE quota rows with thousands separators',         (SELECT COUNT(*) FROM stg_coe_raw WHERE quota LIKE '%,%'));
CALL etl_info('clean', 'COE bids_success rows with thousands separators',  (SELECT COUNT(*) FROM stg_coe_raw WHERE bids_success LIKE '%,%'));
CALL etl_info('clean', 'COE bids_received rows with thousands separators', (SELECT COUNT(*) FROM stg_coe_raw WHERE bids_received LIKE '%,%'));
CALL etl_info('clean', 'COE premium rows with thousands separators',       (SELECT COUNT(*) FROM stg_coe_raw WHERE premium LIKE '%,%'));

-- C14 after removing separators, every numeric field is a number
CALL etl_check('clean', 'COE rows with unparseable numbers after removing separators',
    (SELECT COUNT(*) FROM stg_coe_raw
     WHERE bidding_no NOT REGEXP '^[0-9]+$'
        OR REPLACE(quota, ',', '')         NOT REGEXP '^[0-9]+([.][0-9]+)?$'
        OR REPLACE(bids_success, ',', '')  NOT REGEXP '^[0-9]+([.][0-9]+)?$'
        OR REPLACE(bids_received, ',', '') NOT REGEXP '^[0-9]+([.][0-9]+)?$'
        OR REPLACE(premium, ',', '')       NOT REGEXP '^[0-9]+([.][0-9]+)?$'), 0);

DROP TABLE IF EXISTS cln_coe;
CREATE TABLE cln_coe (
    month_key      CHAR(7)           NOT NULL,
    bidding_no     TINYINT UNSIGNED  NOT NULL,
    vehicle_class  VARCHAR(30)       NOT NULL,
    quota          INT UNSIGNED      NOT NULL,
    bids_success   INT UNSIGNED      NOT NULL,
    bids_received  INT UNSIGNED      NOT NULL,
    premium        DECIMAL(12,2)     NOT NULL,
    PRIMARY KEY (month_key, bidding_no, vehicle_class)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO cln_coe
SELECT month,
       CAST(bidding_no AS UNSIGNED),
       vehicle_class,
       CAST(REPLACE(quota, ',', '')         AS DECIMAL(12,0)),
       CAST(REPLACE(bids_success, ',', '')  AS DECIMAL(12,0)),
       CAST(REPLACE(bids_received, ',', '') AS DECIMAL(12,0)),
       CAST(REPLACE(premium, ',', '')       AS DECIMAL(12,2))
FROM stg_coe_raw;

CALL etl_info('clean', 'COE rows', (SELECT COUNT(*) FROM cln_coe));
CALL etl_info('clean', 'COE month range', (SELECT CONCAT(MIN(month_key), ' to ', MAX(month_key)) FROM cln_coe));

-- =====================================================================
-- 2.3 M09 vehicle population
-- =====================================================================

-- C15 every month is in YYYY-MM format
CALL etl_check('clean', 'M09 rows with unparseable month',
    (SELECT COUNT(*) FROM stg_m09_raw WHERE month NOT REGEXP '^[0-9]{4}-(0[1-9]|1[0-2])$'), 0);

-- "-" is a placeholder in the source; it is treated as 0
CALL etl_info('clean', 'M09 "-" placeholders treated as 0', (SELECT COUNT(*) FROM stg_m09_raw WHERE number = '-'));

-- C16 every count is a number once "-" and blanks are set to 0
CALL etl_check('clean', 'M09 rows with unparseable counts',
    (SELECT COUNT(*) FROM stg_m09_raw
     WHERE number NOT IN ('', '-') AND REPLACE(number, ',', '') NOT REGEXP '^[0-9]+$'), 0);

DROP TABLE IF EXISTS cln_fleet;
CREATE TABLE cln_fleet (
    month_key  CHAR(7)         NOT NULL,
    category   VARCHAR(60)     NOT NULL,
    type       VARCHAR(60)     NOT NULL,
    number     BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (month_key, category, type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO cln_fleet
SELECT month, category, type,
       CAST(IF(number IN ('', '-'), '0', REPLACE(number, ',', '')) AS DECIMAL(15,0))
FROM stg_m09_raw;

CALL etl_info('clean', 'M09 rows', (SELECT COUNT(*) FROM cln_fleet));
CALL etl_info('clean', 'M09 month range', (SELECT CONCAT(MIN(month_key), ' to ', MAX(month_key)) FROM cln_fleet));

-- =====================================================================
-- 2.4 MVP02 annual registrations (used to reconcile M03)
-- =====================================================================

-- C17 years and counts are numeric once "-" and blanks are set to 0
CALL etl_check('clean', 'MVP02 rows with unparseable year or count',
    (SELECT COUNT(*) FROM stg_mvp02_raw
     WHERE year NOT REGEXP '^[0-9]{4}$'
        OR (number NOT IN ('', '-') AND REPLACE(number, ',', '') NOT REGEXP '^[0-9]+$')), 0);

-- C18 every MVP02 type label maps to a body type
CALL etl_check('clean', 'MVP02 unmapped type labels',
    (SELECT COUNT(DISTINCT m.type) FROM stg_mvp02_raw m
     LEFT JOIN ref_body_map b ON b.source_label = m.type
     WHERE b.body_id IS NULL), 0);

DROP TABLE IF EXISTS cln_mvp02;
CREATE TABLE cln_mvp02 (
    row_id         INT UNSIGNED  NOT NULL,
    year_num       SMALLINT      NOT NULL,
    make_name      VARCHAR(60)   NOT NULL COMMENT 'Upper case: the source mixes Mclaren and MCLAREN',
    importer_type  VARCHAR(20)   NOT NULL,
    fuel_type      VARCHAR(40)   NOT NULL,
    source_label   VARCHAR(60)   NOT NULL,
    registrations  INT UNSIGNED  NOT NULL,
    PRIMARY KEY (row_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO cln_mvp02
SELECT row_id, CAST(year AS UNSIGNED), UPPER(make), importer_type, fuel, type,
       CAST(IF(number IN ('', '-'), '0', REPLACE(number, ',', '')) AS DECIMAL(12,0))
FROM stg_mvp02_raw;

CALL etl_info('clean', 'MVP02 rows', (SELECT COUNT(*) FROM cln_mvp02));
CALL etl_info('clean', 'MVP02 year range', (SELECT CONCAT(MIN(year_num), '-', MAX(year_num)) FROM cln_mvp02));

-- =====================================================================
-- 2.5 MVP01 annual registrations by make (excluded: fuel type largely missing)
-- =====================================================================
CALL etl_info('clean', 'MVP01 rows', (SELECT COUNT(*) FROM stg_mvp01_raw));
CALL etl_info('clean', 'MVP01 share of rows with blank fuel_type (%)',
    (SELECT ROUND(100 * AVG(fuel_type = ''), 1) FROM stg_mvp01_raw));

-- =====================================================================
-- 2.6 EV charging point registry (context only)
-- =====================================================================

-- Registration dates are read day first (DD/MM/YYYY); ISO dates are also accepted
DROP TABLE IF EXISTS tmp_charger_typed;
CREATE TABLE tmp_charger_typed AS
SELECT r.*,
       CASE
         WHEN r.registration_date REGEXP '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
           THEN STR_TO_DATE(r.registration_date, '%Y-%m-%d')
         WHEN r.registration_date REGEXP '^(0?[1-9]|[12][0-9]|3[01])/(0?[1-9]|1[0-2])/[0-9]{4}$'
           THEN STR_TO_DATE(r.registration_date, '%d/%m/%Y')
       END AS reg_date
FROM stg_charger_raw r;

CALL etl_info('clean', 'Charger rows with blank registration date',
    (SELECT COUNT(*) FROM tmp_charger_typed WHERE registration_date = ''));
CALL etl_info('clean', 'Charger non-blank dates that could not be parsed',
    (SELECT COUNT(*) FROM tmp_charger_typed WHERE registration_date <> '' AND reg_date IS NULL));

-- C19 no registration date falls after the June 2026 snapshot (guards against day-month swaps)
CALL etl_check('clean', 'Charger registration dates after 2026-06-30',
    (SELECT COUNT(*) FROM tmp_charger_typed WHERE reg_date > '2026-06-30'), 0);

-- De-duplicate on cp_id, keeping the first occurrence
DROP TABLE IF EXISTS cln_charger;
CREATE TABLE cln_charger AS
SELECT t.*
FROM tmp_charger_typed t
JOIN (SELECT cp_id, MIN(row_id) AS keep_id FROM tmp_charger_typed GROUP BY cp_id) k
  ON k.keep_id = t.row_id;

CALL etl_info('clean', 'Charger rows before de-duplication', (SELECT COUNT(*) FROM tmp_charger_typed));
CALL etl_info('clean', 'Charger rows after de-duplication', (SELECT COUNT(*) FROM cln_charger));

-- Work tables are no longer needed
DROP TABLE IF EXISTS tmp_m03_window;
DROP TABLE IF EXISTS tmp_m03_typed;
DROP TABLE IF EXISTS tmp_charger_typed;
