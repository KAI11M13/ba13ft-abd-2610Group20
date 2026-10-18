-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- MySQL cleaning pipeline, step 3 of 4: build the star schema from the cleaned tables
--
-- Input : cln_* tables from 02_clean.sql
-- Output: 4 dimensions, 1 reference table, 4 facts and view v_segment_month
-- The table definitions are identical to SQL/Group20_BYD_BEV_schema_1.sql.
-- Primary keys reject duplicate rows, foreign keys reject codes missing from a
-- dimension, and CHECK constraints reject out-of-range values during the inserts.
-- =====================================================================

USE byd_bev_sg;

SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW  IF EXISTS v_segment_month;
DROP TABLE IF EXISTS fact_registration, fact_coe_month, fact_fleet_month, fact_annual_reg;
DROP TABLE IF EXISTS dim_date, dim_make, dim_fuel, dim_body, dim_charger;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- DIMENSIONS
-- ---------------------------------------------------------------------

CREATE TABLE dim_date (
    month_key     CHAR(7)   NOT NULL COMMENT 'YYYY-MM',
    month_start   DATE      NOT NULL COMMENT 'First day of the month',
    year_num      SMALLINT  NOT NULL,
    month_num     TINYINT   NOT NULL,
    period_code   CHAR(2)   NULL     COMMENT 'Aug-Jul periods P1 to P4; NULL for 2022-07',
    PRIMARY KEY (month_key),
    UNIQUE KEY uq_dim_date_start (month_start),
    CONSTRAINT ck_dim_date_month  CHECK (month_num BETWEEN 1 AND 12),
    CONSTRAINT ck_dim_date_period CHECK (period_code IN ('P1','P2','P3','P4'))
) ENGINE=InnoDB COMMENT='Month dimension, 2022-07 to 2026-07';

CREATE TABLE dim_make (
    make_id    SMALLINT UNSIGNED NOT NULL,
    make_name  VARCHAR(60)       NOT NULL COMMENT 'Brand as recorded by LTA, upper case',
    is_byd     TINYINT(1)        NOT NULL DEFAULT 0,
    PRIMARY KEY (make_id),
    UNIQUE KEY uq_dim_make_name (make_name)
) ENGINE=InnoDB COMMENT='Make dimension (union of M03 and MVP02 makes)';

CREATE TABLE dim_fuel (
    fuel_id    TINYINT UNSIGNED NOT NULL,
    fuel_type  VARCHAR(40)      NOT NULL COMMENT 'LTA fuel category',
    is_bev     TINYINT(1)       NOT NULL DEFAULT 0 COMMENT '1 only for Electric',
    PRIMARY KEY (fuel_id),
    UNIQUE KEY uq_dim_fuel_type (fuel_type)
) ENGINE=InnoDB COMMENT='Fuel type dimension';

CREATE TABLE dim_body (
    body_id      TINYINT UNSIGNED NOT NULL,
    body_type    VARCHAR(40)      NOT NULL COMMENT 'Standardised label used in analysis',
    mvp02_label  VARCHAR(60)      NOT NULL COMMENT 'Label in the MVP02 annual file',
    is_in_scope  TINYINT(1)       NOT NULL DEFAULT 0 COMMENT '1 for SUV, Sedan, MPV',
    is_combined  TINYINT(1)       NOT NULL DEFAULT 0 COMMENT '1 for MVP02 combined MPV/Station Wagon',
    PRIMARY KEY (body_id),
    UNIQUE KEY uq_dim_body_type (body_type)
) ENGINE=InnoDB COMMENT='Body type dimension';

-- Reference table: June 2026 registry snapshot, one row per charge point.
-- Context only; it joins to no fact table.
CREATE TABLE dim_charger (
    cp_id              VARCHAR(20)   NOT NULL COMMENT 'Unique charge point ID',
    charger_code       VARCHAR(12)   NOT NULL COMMENT 'Charger registration code',
    operator_name      VARCHAR(100)  NOT NULL,
    outlets            SMALLINT UNSIGNED NOT NULL,
    plug_type          VARCHAR(12)   NOT NULL COMMENT 'Type 2 / CCS 2 / CHAdeMO',
    charging_speed_kw  DECIMAL(6,1)  NOT NULL,
    postal_code        CHAR(6)       NOT NULL,
    block_no           VARCHAR(20)   NULL,
    street_name        VARCHAR(120)  NULL,
    building_name      VARCHAR(120)  NULL,
    floor_no           VARCHAR(20)   NULL,
    lot_no             VARCHAR(40)   NULL,
    public_accessible  VARCHAR(5)    NOT NULL,
    longitude          DECIMAL(11,7) NOT NULL,
    latitude           DECIMAL(10,7) NOT NULL,
    registration_date  DATE          NULL,
    parking_lot_type   VARCHAR(100)  NULL,
    PRIMARY KEY (cp_id),
    KEY ix_charger_code (charger_code)
) ENGINE=InnoDB COMMENT='EV charging point registry, Jun 2026 snapshot';

-- ---------------------------------------------------------------------
-- FACTS
-- ---------------------------------------------------------------------

-- Grain: month x make x fuel x body. Every (month, make, fuel) combination
-- is expanded across all six body types, zero where nothing registered
-- (4,483 x 6 = 26,898 rows).
CREATE TABLE fact_registration (
    month_key      CHAR(7)           NOT NULL,
    make_id        SMALLINT UNSIGNED NOT NULL,
    fuel_id        TINYINT UNSIGNED  NOT NULL,
    body_id        TINYINT UNSIGNED  NOT NULL,
    registrations  INT UNSIGNED      NOT NULL DEFAULT 0,
    PRIMARY KEY (month_key, make_id, fuel_id, body_id),
    KEY ix_reg_make (make_id),
    KEY ix_reg_fuel (fuel_id),
    KEY ix_reg_body (body_id),
    CONSTRAINT fk_reg_date FOREIGN KEY (month_key) REFERENCES dim_date (month_key),
    CONSTRAINT fk_reg_make FOREIGN KEY (make_id)   REFERENCES dim_make (make_id),
    CONSTRAINT fk_reg_fuel FOREIGN KEY (fuel_id)   REFERENCES dim_fuel (fuel_id),
    CONSTRAINT fk_reg_body FOREIGN KEY (body_id)   REFERENCES dim_body (body_id)
) ENGINE=InnoDB COMMENT='M03 monthly new car registrations (cleaned)';

-- Categories A and B, two bidding exercises per month:
-- premium = mean of the exercises, quota and bids = sum.
CREATE TABLE fact_coe_month (
    month_key            CHAR(7)          NOT NULL,
    cat_a_premium        DECIMAL(10,1)    NOT NULL COMMENT 'S$, mean of exercises',
    cat_b_premium        DECIMAL(10,1)    NOT NULL COMMENT 'S$, mean of exercises',
    cat_a_quota          INT UNSIGNED     NOT NULL,
    cat_b_quota          INT UNSIGNED     NOT NULL,
    cat_a_bids_received  INT UNSIGNED     NOT NULL,
    cat_b_bids_received  INT UNSIGNED     NOT NULL,
    cat_a_bids_success   INT UNSIGNED     NOT NULL,
    cat_b_bids_success   INT UNSIGNED     NOT NULL,
    n_exercises          TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (month_key),
    CONSTRAINT fk_coe_date FOREIGN KEY (month_key) REFERENCES dim_date (month_key)
) ENGINE=InnoDB COMMENT='COE bidding results aggregated to month';

-- M09 car population (category = Cars), one row per month.
CREATE TABLE fact_fleet_month (
    month_key      CHAR(7)      NOT NULL,
    cars_total     INT UNSIGNED NOT NULL,
    cars_bev       INT UNSIGNED NOT NULL COMMENT 'Fuel type Electric',
    bev_share_pct  DECIMAL(6,2) AS (ROUND(100 * cars_bev / cars_total, 2)) STORED,
    PRIMARY KEY (month_key),
    CONSTRAINT fk_fleet_date FOREIGN KEY (month_key) REFERENCES dim_date (month_key)
) ENGINE=InnoDB COMMENT='M09 car population, monthly';

-- MVP02 annual new registrations, importer types summed.
-- Annual grain, so year_num carries no FK to the monthly dim_date.
CREATE TABLE fact_annual_reg (
    year_num       SMALLINT          NOT NULL,
    make_id        SMALLINT UNSIGNED NOT NULL,
    fuel_id        TINYINT UNSIGNED  NOT NULL,
    body_id        TINYINT UNSIGNED  NOT NULL,
    registrations  INT UNSIGNED      NOT NULL,
    PRIMARY KEY (year_num, make_id, fuel_id, body_id),
    KEY ix_ann_make (make_id),
    KEY ix_ann_fuel (fuel_id),
    KEY ix_ann_body (body_id),
    CONSTRAINT fk_ann_make FOREIGN KEY (make_id) REFERENCES dim_make (make_id),
    CONSTRAINT fk_ann_fuel FOREIGN KEY (fuel_id) REFERENCES dim_fuel (fuel_id),
    CONSTRAINT fk_ann_body FOREIGN KEY (body_id) REFERENCES dim_body (body_id),
    CONSTRAINT ck_ann_year CHECK (year_num BETWEEN 2015 AND 2025)
) ENGINE=InnoDB COMMENT='MVP02 annual new registrations (reconciliation)';

-- ---------------------------------------------------------------------
-- LOAD DIMENSIONS
-- ---------------------------------------------------------------------

-- Months in the study window; August-to-July periods P1 to P4, July 2022 outside the periods
INSERT INTO dim_date (month_key, month_start, year_num, month_num, period_code)
SELECT m.month_key,
       STR_TO_DATE(CONCAT(m.month_key, '-01'), '%Y-%m-%d'),
       CAST(LEFT(m.month_key, 4) AS UNSIGNED),
       CAST(RIGHT(m.month_key, 2) AS UNSIGNED),
       CASE
         WHEN m.month_key BETWEEN '2022-08' AND '2023-07' THEN 'P1'
         WHEN m.month_key BETWEEN '2023-08' AND '2024-07' THEN 'P2'
         WHEN m.month_key BETWEEN '2024-08' AND '2025-07' THEN 'P3'
         WHEN m.month_key BETWEEN '2025-08' AND '2026-07' THEN 'P4'
       END
FROM (SELECT DISTINCT month_key FROM cln_registration) m;

-- Makes from M03 (study window) and MVP02, numbered alphabetically
INSERT INTO dim_make (make_id, make_name, is_byd)
SELECT ROW_NUMBER() OVER (ORDER BY u.make_name COLLATE utf8mb4_bin),
       u.make_name,
       u.make_name = 'BYD'
FROM (SELECT make_name FROM cln_registration
      UNION
      SELECT make_name FROM cln_mvp02) u;

-- Fuel types from M03 and MVP02; Electric is the battery electric vehicle (BEV)
INSERT INTO dim_fuel (fuel_id, fuel_type, is_bev)
SELECT ROW_NUMBER() OVER (ORDER BY u.fuel_type COLLATE utf8mb4_bin),
       u.fuel_type,
       u.fuel_type = 'Electric'
FROM (SELECT fuel_type FROM cln_registration
      UNION
      SELECT fuel_type FROM cln_mvp02) u;

-- Body types; SUV, Sedan and MPV are in scope
INSERT INTO dim_body (body_id, body_type, mvp02_label, is_in_scope, is_combined)
SELECT body_id, body_type, source_label, is_in_scope, is_combined
FROM ref_body_map;

-- Charger registry snapshot (reference table)
INSERT INTO dim_charger (cp_id, charger_code, operator_name, outlets, plug_type, charging_speed_kw,
                         postal_code, block_no, street_name, building_name, floor_no, lot_no,
                         public_accessible, longitude, latitude, registration_date, parking_lot_type)
SELECT cp_id,
       charger_code,
       operator_name,
       CAST(IF(outlets = '', '0', outlets) AS UNSIGNED),
       plug_type,
       CAST(charging_speed_kw AS DECIMAL(6,1)),
       IF(postal_code REGEXP '^[0-9]{1,6}$', LPAD(postal_code, 6, '0'), postal_code),
       NULLIF(block_no, ''),
       NULLIF(street_name, ''),
       NULLIF(building_name, ''),
       NULLIF(floor_no, ''),
       NULLIF(lot_no, ''),
       public_accessible,
       CAST(longitude AS DECIMAL(11,7)),
       CAST(latitude  AS DECIMAL(10,7)),
       reg_date,
       NULLIF(parking_lot_type, '')
FROM cln_charger;

-- ---------------------------------------------------------------------
-- LOAD FACTS
-- ---------------------------------------------------------------------

-- Registrations: replace text labels with dimension keys
INSERT INTO fact_registration (month_key, make_id, fuel_id, body_id, registrations)
SELECT r.month_key, k.make_id, f.fuel_id, b.body_id, r.registrations
FROM cln_registration r
JOIN dim_make k ON k.make_name = r.make_name
JOIN dim_fuel f ON f.fuel_type = r.fuel_type
JOIN dim_body b ON b.body_type = r.body_type;

-- COE: Categories A and B; premium = mean of the month's exercises, quota and bids = sum
INSERT INTO fact_coe_month (month_key, cat_a_premium, cat_b_premium, cat_a_quota, cat_b_quota,
                            cat_a_bids_received, cat_b_bids_received,
                            cat_a_bids_success, cat_b_bids_success, n_exercises)
SELECT c.month_key,
       ROUND(AVG(CASE WHEN c.vehicle_class = 'Category A' THEN c.premium END), 1),
       ROUND(AVG(CASE WHEN c.vehicle_class = 'Category B' THEN c.premium END), 1),
       SUM(CASE WHEN c.vehicle_class = 'Category A' THEN c.quota         ELSE 0 END),
       SUM(CASE WHEN c.vehicle_class = 'Category B' THEN c.quota         ELSE 0 END),
       SUM(CASE WHEN c.vehicle_class = 'Category A' THEN c.bids_received ELSE 0 END),
       SUM(CASE WHEN c.vehicle_class = 'Category B' THEN c.bids_received ELSE 0 END),
       SUM(CASE WHEN c.vehicle_class = 'Category A' THEN c.bids_success  ELSE 0 END),
       SUM(CASE WHEN c.vehicle_class = 'Category B' THEN c.bids_success  ELSE 0 END),
       COUNT(DISTINCT c.bidding_no)
FROM cln_coe c
JOIN dim_date d ON d.month_key = c.month_key
WHERE c.vehicle_class IN ('Category A', 'Category B')
GROUP BY c.month_key;

-- Car population: category Cars, all fuels and Electric
INSERT INTO fact_fleet_month (month_key, cars_total, cars_bev)
SELECT f.month_key,
       SUM(f.number),
       SUM(CASE WHEN f.type = 'Electric' THEN f.number ELSE 0 END)
FROM cln_fleet f
JOIN dim_date d ON d.month_key = f.month_key
WHERE f.category = 'Cars'
GROUP BY f.month_key;

-- MVP02 annual registrations: importer types summed, labels mapped to dimension keys
INSERT INTO fact_annual_reg (year_num, make_id, fuel_id, body_id, registrations)
SELECT m.year_num, k.make_id, f.fuel_id, b.body_id, SUM(m.registrations)
FROM cln_mvp02 m
JOIN dim_make k ON k.make_name   = m.make_name
JOIN dim_fuel f ON f.fuel_type   = m.fuel_type
JOIN dim_body b ON b.mvp02_label = m.source_label
GROUP BY m.year_num, k.make_id, f.fuel_id, b.body_id;

-- ---------------------------------------------------------------------
-- VIEW: segment-month base of the analysis mart (49 x 3 = 147 rows)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_segment_month AS
SELECT
    r.month_key,
    d.period_code,
    b.body_type AS body,
    SUM(r.registrations) AS market_all,
    SUM(CASE WHEN f.is_bev = 1 THEN r.registrations ELSE 0 END) AS market_bev,
    SUM(CASE WHEN f.is_bev = 1 AND k.is_byd = 1 THEN r.registrations ELSE 0 END) AS byd_bev,
    ROUND(100 * SUM(CASE WHEN f.is_bev = 1 AND k.is_byd = 1 THEN r.registrations ELSE 0 END)
          / NULLIF(SUM(CASE WHEN f.is_bev = 1 THEN r.registrations ELSE 0 END), 0), 2) AS byd_share_pct,
    ROUND(100 * SUM(CASE WHEN f.is_bev = 1 THEN r.registrations ELSE 0 END)
          / NULLIF(SUM(r.registrations), 0), 2) AS bev_penetration_pct
FROM fact_registration r
JOIN dim_date d ON d.month_key = r.month_key
JOIN dim_make k ON k.make_id   = r.make_id
JOIN dim_fuel f ON f.fuel_id   = r.fuel_id
JOIN dim_body b ON b.body_id   = r.body_id
WHERE b.is_in_scope = 1
GROUP BY r.month_key, d.period_code, b.body_type;

-- ---------------------------------------------------------------------
-- ROW COUNTS
-- ---------------------------------------------------------------------
CALL etl_info('build', 'dim_date rows',          (SELECT COUNT(*) FROM dim_date));
CALL etl_info('build', 'dim_make rows',          (SELECT COUNT(*) FROM dim_make));
CALL etl_info('build', 'dim_fuel rows',          (SELECT COUNT(*) FROM dim_fuel));
CALL etl_info('build', 'dim_body rows',          (SELECT COUNT(*) FROM dim_body));
CALL etl_info('build', 'dim_charger rows',       (SELECT COUNT(*) FROM dim_charger));
CALL etl_info('build', 'fact_registration rows', (SELECT COUNT(*) FROM fact_registration));
CALL etl_info('build', 'fact_coe_month rows',    (SELECT COUNT(*) FROM fact_coe_month));
CALL etl_info('build', 'fact_fleet_month rows',  (SELECT COUNT(*) FROM fact_fleet_month));
CALL etl_info('build', 'fact_annual_reg rows',   (SELECT COUNT(*) FROM fact_annual_reg));
