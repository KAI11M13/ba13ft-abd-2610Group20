-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- BYD BEV Body-Segment Market Prioritisation in Singapore
-- MySQL 8.0 database: 4 dimensions + 1 reference table + 4 facts + 1 view
--
-- Built from the cleaned CSVs in github.com/KAI11M13/ba13ft-abd-2610Group20
-- (cleaned_data/). Source: LTA via data.gov.sg. MVP01 is not loaded.
-- Analysis window: 2022-07 to 2026-07 (49 months)
--
-- Row counts after load (report Table 4.2):
--   dim_date 49 | dim_make 95 | dim_fuel 8 | dim_body 7 | dim_charger 11,353
--   fact_registration 26,898 | fact_coe_month 49 | fact_fleet_month 49
--   fact_annual_reg 5,894
--
-- ERD: MySQL Workbench > File > Import > Reverse Engineer MySQL Create Script
-- =====================================================================

DROP DATABASE IF EXISTS byd_bev_sg;
CREATE DATABASE byd_bev_sg CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE byd_bev_sg;

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
