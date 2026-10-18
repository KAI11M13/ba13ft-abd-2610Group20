-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- MySQL pipeline, step 5 of 5: build the analysis mart
--
-- Input : star schema from 03_build_star_schema.sql (validated by 04_validate.sql)
-- Output: segment_month_full   month x segment, 147 rows (Q2 tests, Q3 monthly capture, Q4 COE tests)
--         segment_period       period x segment, 12 rows (Q1 shift-share, Q2 growth, Q3 Capture Gap)
--         competitor_gap_p3p4  segment x make, P3 to P4 (Q3 competitor benchmarking)
-- Ratios use 1e0 or 100e0 so that MySQL divides in floating point (integer
-- division would keep only 4 decimal places).
-- Definitions (report Section 3.2): BEV = fuel type Electric; scope = SUV, Sedan, MPV;
-- segment market = BEV registrations of all makes in the segment;
-- BYD share = BYD BEV registrations / segment market; periods run August to July.
-- Every mart check writes one row to etl_check_log with stage 'mart'.
-- =====================================================================

USE byd_bev_sg;

DROP TABLE IF EXISTS competitor_gap_p3p4, segment_period, segment_month_full;

-- ---------------------------------------------------------------------
-- 5.1 segment_month_full: one row per month and segment
-- ---------------------------------------------------------------------
CREATE TABLE segment_month_full (
    month                    CHAR(7)       NOT NULL COMMENT 'YYYY-MM',
    year                     SMALLINT      NOT NULL,
    month_num                TINYINT       NOT NULL,
    period                   CHAR(2)       NULL     COMMENT 'P1 to P4; NULL for 2022-07',
    segment                  VARCHAR(40)   NOT NULL COMMENT 'SUV / Sedan / MPV',
    market_all               INT UNSIGNED  NOT NULL COMMENT 'All-fuel registrations in the segment',
    market_bev               INT UNSIGNED  NOT NULL COMMENT 'BEV registrations of all makes',
    bev_penetration_pct      DOUBLE        NULL,
    n_bev_makes              SMALLINT      NOT NULL COMMENT 'Makes with at least one BEV registration',
    thin_month               TINYINT(1)    NOT NULL COMMENT '1 if market_bev < 50',
    byd_bev                  INT UNSIGNED  NOT NULL,
    byd_share_pct            DOUBLE        NULL,
    byd_all                  INT UNSIGNED  NOT NULL COMMENT 'BYD registrations, all fuel types',
    byd_phev                 INT UNSIGNED  NOT NULL COMMENT 'BYD plug-in hybrid registrations',
    top_rival                VARCHAR(60)   NULL     COMMENT 'Largest non-BYD BEV make',
    top_rival_bev            INT UNSIGNED  NOT NULL,
    top_rival_share_pct      DOUBLE        NULL,
    market_bev_prev_year     INT UNSIGNED  NULL     COMMENT 'Same calendar month one year earlier',
    byd_bev_prev_year        INT UNSIGNED  NULL,
    byd_share_prev_year_pct  DOUBLE        NULL,
    benchmark_bev_month      DOUBLE        NULL     COMMENT 'Prior-year BYD share x current market',
    capture_gap_month        DOUBLE        NULL     COMMENT 'byd_bev - benchmark_bev_month',
    market_bev_mom_pct       DOUBLE        NULL,
    byd_share_mom_pp         DOUBLE        NULL,
    cat_a_premium            DECIMAL(10,1) NULL,
    cat_b_premium            DECIMAL(10,1) NULL,
    cat_a_quota              INT UNSIGNED  NULL,
    cat_b_quota              INT UNSIGNED  NULL,
    cat_a_bids_received      INT UNSIGNED  NULL,
    cat_b_bids_received      INT UNSIGNED  NULL,
    cat_a_bids_success       INT UNSIGNED  NULL,
    cat_b_bids_success       INT UNSIGNED  NULL,
    n_exercises              TINYINT       NULL,
    cat_a_premium_mom_pct    DOUBLE        NULL,
    cat_b_premium_mom_pct    DOUBLE        NULL,
    cat_a_quota_mom_pct      DOUBLE        NULL,
    cat_b_quota_mom_pct      DOUBLE        NULL,
    cars_total               INT UNSIGNED  NULL,
    cars_bev                 INT UNSIGNED  NULL,
    fleet_bev_share_pct      DOUBLE        NULL,
    PRIMARY KEY (month, segment),
    CONSTRAINT fk_smf_date FOREIGN KEY (month) REFERENCES dim_date (month_key)
) ENGINE=InnoDB COMMENT='Analysis mart: month x segment';

-- Volumes from the registration fact table
INSERT INTO segment_month_full (month, year, month_num, period, segment, market_all, market_bev,
                                n_bev_makes, thin_month, byd_bev, byd_all, byd_phev, top_rival_bev)
SELECT d.month_key, d.year_num, d.month_num, d.period_code, b.body_type,
       SUM(r.registrations),
       SUM(CASE WHEN f.is_bev = 1 THEN r.registrations ELSE 0 END),
       COUNT(DISTINCT CASE WHEN f.is_bev = 1 AND r.registrations > 0 THEN r.make_id END),
       0,
       SUM(CASE WHEN f.is_bev = 1 AND k.is_byd = 1 THEN r.registrations ELSE 0 END),
       SUM(CASE WHEN k.is_byd = 1 THEN r.registrations ELSE 0 END),
       SUM(CASE WHEN k.is_byd = 1 AND f.fuel_type LIKE '%(Plug-In)' THEN r.registrations ELSE 0 END),
       0
FROM fact_registration r
JOIN dim_date d ON d.month_key = r.month_key
JOIN dim_make k ON k.make_id   = r.make_id
JOIN dim_fuel f ON f.fuel_id   = r.fuel_id
JOIN dim_body b ON b.body_id   = r.body_id
WHERE b.is_in_scope = 1
GROUP BY d.month_key, d.year_num, d.month_num, d.period_code, b.body_type;

-- Largest non-BYD BEV make in each month and segment (ties broken by make name)
UPDATE segment_month_full s
JOIN (
    SELECT month_key, body_type, make_name, bev,
           ROW_NUMBER() OVER (PARTITION BY month_key, body_type
                              ORDER BY bev DESC, make_name COLLATE utf8mb4_bin) AS rn
    FROM (
        SELECT r.month_key, b.body_type, k.make_name, SUM(r.registrations) AS bev
        FROM fact_registration r
        JOIN dim_make k ON k.make_id = r.make_id
        JOIN dim_fuel f ON f.fuel_id = r.fuel_id
        JOIN dim_body b ON b.body_id = r.body_id
        WHERE b.is_in_scope = 1 AND f.is_bev = 1 AND k.is_byd = 0
        GROUP BY r.month_key, b.body_type, k.make_name
        HAVING SUM(r.registrations) > 0
    ) m
) t ON t.month_key = s.month AND t.body_type = s.segment AND t.rn = 1
SET s.top_rival = t.make_name, s.top_rival_bev = t.bev;

-- Shares and the thin-month flag
UPDATE segment_month_full
SET byd_share_pct       = 100e0 * byd_bev       / NULLIF(market_bev, 0),
    bev_penetration_pct = 100e0 * market_bev    / NULLIF(market_all, 0),
    top_rival_share_pct = 100e0 * top_rival_bev / NULLIF(market_bev, 0),
    thin_month          = IF(market_bev < 50, 1, 0);

-- Same calendar month one year earlier, monthly Capture Gap and month-on-month changes
UPDATE segment_month_full s
JOIN (
    SELECT month, segment,
           LAG(market_bev,    12) OVER w AS market_bev_py,
           LAG(byd_bev,       12) OVER w AS byd_bev_py,
           LAG(byd_share_pct, 12) OVER w AS share_py,
           LAG(market_bev,     1) OVER w AS market_bev_pm,
           LAG(byd_share_pct,  1) OVER w AS share_pm
    FROM segment_month_full
    WINDOW w AS (PARTITION BY segment ORDER BY month)
) l ON l.month = s.month AND l.segment = s.segment
SET s.market_bev_prev_year    = l.market_bev_py,
    s.byd_bev_prev_year       = l.byd_bev_py,
    s.byd_share_prev_year_pct = l.share_py,
    s.benchmark_bev_month     = l.share_py / 100 * s.market_bev,
    s.capture_gap_month       = s.byd_bev - l.share_py / 100 * s.market_bev,
    s.market_bev_mom_pct      = 100 * (1e0 * s.market_bev / NULLIF(l.market_bev_pm, 0) - 1),
    s.byd_share_mom_pp        = s.byd_share_pct - l.share_pm;

-- COE results (monthly mean premium, summed quota and bids) and month-on-month changes
UPDATE segment_month_full s
JOIN (
    SELECT c.*,
           100 * (1e0 * c.cat_a_premium / LAG(c.cat_a_premium) OVER w - 1) AS a_prem_mom,
           100 * (1e0 * c.cat_b_premium / LAG(c.cat_b_premium) OVER w - 1) AS b_prem_mom,
           100 * (1e0 * c.cat_a_quota   / LAG(c.cat_a_quota)   OVER w - 1) AS a_quota_mom,
           100 * (1e0 * c.cat_b_quota   / LAG(c.cat_b_quota)   OVER w - 1) AS b_quota_mom
    FROM fact_coe_month c
    WINDOW w AS (ORDER BY c.month_key)
) c ON c.month_key = s.month
SET s.cat_a_premium         = c.cat_a_premium,
    s.cat_b_premium         = c.cat_b_premium,
    s.cat_a_quota           = c.cat_a_quota,
    s.cat_b_quota           = c.cat_b_quota,
    s.cat_a_bids_received   = c.cat_a_bids_received,
    s.cat_b_bids_received   = c.cat_b_bids_received,
    s.cat_a_bids_success    = c.cat_a_bids_success,
    s.cat_b_bids_success    = c.cat_b_bids_success,
    s.n_exercises           = c.n_exercises,
    s.cat_a_premium_mom_pct = c.a_prem_mom,
    s.cat_b_premium_mom_pct = c.b_prem_mom,
    s.cat_a_quota_mom_pct   = c.a_quota_mom,
    s.cat_b_quota_mom_pct   = c.b_quota_mom;

-- Car population context
UPDATE segment_month_full s
JOIN fact_fleet_month v ON v.month_key = s.month
SET s.cars_total          = v.cars_total,
    s.cars_bev            = v.cars_bev,
    s.fleet_bev_share_pct = 100e0 * v.cars_bev / v.cars_total;

-- ---------------------------------------------------------------------
-- 5.2 segment_period: one row per period and segment, with shift-share terms
-- ---------------------------------------------------------------------
CREATE TABLE segment_period (
    period               CHAR(2)      NOT NULL,
    segment              VARCHAR(40)  NOT NULL,
    market_bev           INT UNSIGNED NOT NULL,
    byd_bev              INT UNSIGNED NOT NULL,
    market_all           INT UNSIGNED NOT NULL,
    bev_penetration_pct  DOUBLE       NULL,
    market_growth_pct    DOUBLE       NULL,
    byd_growth_pct       DOUBLE       NULL,
    share_change_pp      DOUBLE       NULL,
    benchmark_bev        DOUBLE       NULL COMMENT 'Previous-period BYD share x current market',
    capture_gap          DOUBLE       NULL COMMENT 'byd_bev - benchmark_bev',
    market_effect        DOUBLE       NULL COMMENT 'Average share x market change',
    share_effect         DOUBLE       NULL COMMENT 'Average market x share change',
    interaction          DOUBLE       NULL COMMENT 'Share change x market change',
    byd_change           INT          NULL,
    byd_share_pct        DOUBLE       NULL,
    PRIMARY KEY (period, segment)
) ENGINE=InnoDB COMMENT='Analysis mart: period x segment';

INSERT INTO segment_period
SELECT period, segment, m1, b1, a1,
       100e0 * m1 / a1,
       100 * (1e0 * m1 / m0 - 1),
       100 * (1e0 * b1 / b0 - 1),
       100 * (s1 - s0),
       s0 * m1,
       b1 - s0 * m1,
       (s0 + s1) / 2 * (m1 - m0),
       (m0 + m1) / 2 * (s1 - s0),
       (s1 - s0) * (m1 - m0),
       b1 - b0,
       100 * s1
FROM (
    SELECT period, segment, m1, b1, a1, 1e0 * b1 / m1 AS s1,
           LAG(m1)            OVER w AS m0,
           LAG(b1)            OVER w AS b0,
           LAG(1e0 * b1 / m1) OVER w AS s0
    FROM (
        SELECT period, segment, SUM(market_bev) AS m1, SUM(byd_bev) AS b1, SUM(market_all) AS a1
        FROM segment_month_full
        WHERE period IS NOT NULL
        GROUP BY period, segment
    ) p
    WINDOW w AS (PARTITION BY segment ORDER BY period)
) x;

-- ---------------------------------------------------------------------
-- 5.3 competitor_gap_p3p4: each make's own P3 share held into P4
-- ---------------------------------------------------------------------
CREATE TABLE competitor_gap_p3p4 (
    segment          VARCHAR(40)  NOT NULL,
    make             VARCHAR(60)  NOT NULL,
    p3_bev           INT UNSIGNED NOT NULL,
    p4_bev           INT UNSIGNED NOT NULL,
    p3_share_pct     DOUBLE       NOT NULL,
    p4_share_pct     DOUBLE       NOT NULL,
    share_change_pp  DOUBLE       NOT NULL,
    benchmark_bev    DOUBLE       NOT NULL,
    capture_gap      DOUBLE       NOT NULL,
    PRIMARY KEY (segment, make)
) ENGINE=InnoDB COMMENT='Analysis mart: make x segment Capture Gaps, P3 to P4';

INSERT INTO competitor_gap_p3p4
SELECT c.segment, c.make, c.p3, c.p4,
       100e0 * c.p3 / m3.market_bev,
       100e0 * c.p4 / m4.market_bev,
       100e0 * c.p4 / m4.market_bev - 100e0 * c.p3 / m3.market_bev,
       1e0 * c.p3 / m3.market_bev * m4.market_bev,
       c.p4 - 1e0 * c.p3 / m3.market_bev * m4.market_bev
FROM (
    SELECT b.body_type AS segment, k.make_name AS make,
           SUM(CASE WHEN d.period_code = 'P3' THEN r.registrations ELSE 0 END) AS p3,
           SUM(CASE WHEN d.period_code = 'P4' THEN r.registrations ELSE 0 END) AS p4
    FROM fact_registration r
    JOIN dim_date d ON d.month_key = r.month_key
    JOIN dim_make k ON k.make_id   = r.make_id
    JOIN dim_fuel f ON f.fuel_id   = r.fuel_id
    JOIN dim_body b ON b.body_id   = r.body_id
    WHERE b.is_in_scope = 1 AND f.is_bev = 1 AND d.period_code IN ('P3', 'P4')
    GROUP BY b.body_type, k.make_name
) c
JOIN segment_period m3 ON m3.segment = c.segment AND m3.period = 'P3'
JOIN segment_period m4 ON m4.segment = c.segment AND m4.period = 'P4';

-- ---------------------------------------------------------------------
-- 5.4 Mart checks (17)
-- ---------------------------------------------------------------------
-- Structure and completeness
CALL etl_check('mart', 'segment_month_full rows (49 months x 3 segments)',
    (SELECT COUNT(*) FROM segment_month_full), 147);

CALL etl_check('mart', 'Missing values in core segment_month_full fields',
    (SELECT SUM((market_bev_prev_year IS NULL AND month >= '2023-07')
              + (byd_share_pct IS NULL) + (bev_penetration_pct IS NULL)
              + (cat_a_premium IS NULL) + (cat_b_premium IS NULL)
              + (cat_a_quota IS NULL)   + (cat_b_quota IS NULL)
              + (cars_total IS NULL)    + (cars_bev IS NULL))
     FROM segment_month_full), 0);

CALL etl_check('mart', 'Rows breaking byd_bev <= market_bev <= market_all',
    (SELECT COUNT(*) FROM segment_month_full WHERE byd_bev > market_bev OR market_bev > market_all), 0);

CALL etl_check('mart', 'Share values outside 0 to 100',
    (SELECT COUNT(*) FROM segment_month_full
     WHERE byd_share_pct NOT BETWEEN 0 AND 100 OR bev_penetration_pct NOT BETWEEN 0 AND 100
        OR top_rival_share_pct NOT BETWEEN 0 AND 100 OR fleet_bev_share_pct NOT BETWEEN 0 AND 100), 0);

CALL etl_check('mart', 'Difference from v_segment_month (market_all, market_bev, byd_bev)',
    (SELECT COUNT(*) FROM segment_month_full s
     LEFT JOIN v_segment_month v ON v.month_key = s.month AND v.body = s.segment
     WHERE v.month_key IS NULL OR v.market_all <> s.market_all
        OR v.market_bev <> s.market_bev OR v.byd_bev <> s.byd_bev), 0);

CALL etl_check('mart', 'Rows with COE and car population data',
    (SELECT COUNT(*) FROM segment_month_full WHERE n_exercises >= 1 AND cars_total > 0), 147);

-- Period table
CALL etl_check('mart', 'segment_period rows (4 periods x 3 segments)',
    (SELECT COUNT(*) FROM segment_period), 12);

CALL etl_check('mart', 'segment_period minus the sum of its monthly rows',
    (SELECT SUM(ABS(p.market_bev - m.mb) + ABS(p.byd_bev - m.bb) + ABS(p.market_all - m.ma))
     FROM segment_period p
     JOIN (SELECT period, segment, SUM(market_bev) AS mb, SUM(byd_bev) AS bb, SUM(market_all) AS ma
           FROM segment_month_full WHERE period IS NOT NULL GROUP BY period, segment) m
       ON m.period = p.period AND m.segment = p.segment), 0);

CALL etl_check('mart', 'Shift-share identity: market effect + share effect - BYD change (x 1e6)',
    (SELECT ROUND(1e6 * MAX(ABS(market_effect + share_effect - byd_change)))
     FROM segment_period WHERE period <> 'P1'), 0);

CALL etl_check('mart', 'Capture Gap identity: share effect + interaction / 2 - Capture Gap (x 1e6)',
    (SELECT ROUND(1e6 * MAX(ABS(share_effect + interaction / 2 - capture_gap)))
     FROM segment_period WHERE period <> 'P1'), 0);

-- Competitor table
CALL etl_check('mart', 'BYD rows in competitor_gap_p3p4 minus segment Capture Gaps (x 1e6)',
    (SELECT ROUND(1e6 * MAX(ABS(c.capture_gap - p.capture_gap)))
     FROM competitor_gap_p3p4 c
     JOIN segment_period p ON p.segment = c.segment AND p.period = 'P4'
     WHERE c.make = 'BYD'), 0);

CALL etl_check('mart', 'Competitor Capture Gaps sum to zero in each segment (x 1e6)',
    (SELECT ROUND(1e6 * MAX(ABS(g))) FROM
        (SELECT SUM(capture_gap) AS g FROM competitor_gap_p3p4 GROUP BY segment) z), 0);

-- Headline figures in the report
CALL etl_check('mart', 'SUV Capture Gap, P3 to P4',
    (SELECT ROUND(capture_gap) FROM segment_period WHERE period = 'P4' AND segment = 'SUV'), -1426);
CALL etl_check('mart', 'Sedan Capture Gap, P3 to P4',
    (SELECT ROUND(capture_gap) FROM segment_period WHERE period = 'P4' AND segment = 'Sedan'), 979);
CALL etl_check('mart', 'MPV Capture Gap, P3 to P4',
    (SELECT ROUND(capture_gap) FROM segment_period WHERE period = 'P4' AND segment = 'MPV'), -475);
CALL etl_check('mart', 'BYD share of three-segment BEV market, P3 (x 10)',
    (SELECT ROUND(1000 * SUM(byd_bev) / SUM(market_bev)) FROM segment_period WHERE period = 'P3'), 466);
CALL etl_check('mart', 'BYD share of three-segment BEV market, P4 (x 10)',
    (SELECT ROUND(1000 * SUM(byd_bev) / SUM(market_bev)) FROM segment_period WHERE period = 'P4'), 409);

-- ---------------------------------------------------------------------
-- 5.5 Export
-- In MySQL Workbench, right-click each table > Table Data Export Wizard > CSV,
-- and save as mart/segment_month_full.csv, mart/segment_period.csv and
-- mart/competitor_gap_p3p4.csv. The SELECT statements below give the same rows.
-- ---------------------------------------------------------------------
SELECT * FROM segment_month_full  ORDER BY month, segment;
SELECT * FROM segment_period      ORDER BY period, segment;
SELECT * FROM competitor_gap_p3p4 ORDER BY segment, capture_gap DESC;

SELECT stage,
       SUM(status = 'PASS') AS passed,
       SUM(status = 'FAIL') AS failed,
       SUM(status = 'INFO') AS info_rows
FROM etl_check_log
GROUP BY stage
ORDER BY MIN(check_id);
