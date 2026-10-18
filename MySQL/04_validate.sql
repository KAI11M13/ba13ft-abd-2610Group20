-- =====================================================================
-- Group 20 "High Five" | EBA5011 ABD Practice Module
-- MySQL cleaning pipeline, step 4 of 4: validate the star schema
--
-- Expected values are the figures reported for the raw files downloaded for
-- this project (analysis window 2022-07 to 2026-07). A newer download of the
-- LTA files will change some of them.
-- =====================================================================

USE byd_bev_sg;

-- ---------------------------------------------------------------------
-- 4.1 Table sizes
-- ---------------------------------------------------------------------
CALL etl_check('validate', 'dim_date rows',          (SELECT COUNT(*) FROM dim_date),          49);
CALL etl_check('validate', 'dim_make rows',          (SELECT COUNT(*) FROM dim_make),          95);
CALL etl_check('validate', 'dim_fuel rows',          (SELECT COUNT(*) FROM dim_fuel),          8);
CALL etl_check('validate', 'dim_body rows',          (SELECT COUNT(*) FROM dim_body),          7);
CALL etl_check('validate', 'dim_charger rows',       (SELECT COUNT(*) FROM dim_charger),       11353);
CALL etl_check('validate', 'fact_registration rows', (SELECT COUNT(*) FROM fact_registration), 26898);
CALL etl_check('validate', 'fact_coe_month rows',    (SELECT COUNT(*) FROM fact_coe_month),    49);
CALL etl_check('validate', 'fact_fleet_month rows',  (SELECT COUNT(*) FROM fact_fleet_month),  49);
CALL etl_check('validate', 'fact_annual_reg rows',   (SELECT COUNT(*) FROM fact_annual_reg),   5894);

-- ---------------------------------------------------------------------
-- 4.2 Completeness and integrity
-- ---------------------------------------------------------------------
CALL etl_check('validate', 'Total registrations in fact_registration',
    (SELECT SUM(registrations) FROM fact_registration), 172394);

CALL etl_check('validate', 'Body-type grid: rows = month-make-fuel combinations x 6',
    (SELECT COUNT(*) FROM fact_registration)
    - 6 * (SELECT COUNT(*) FROM (SELECT DISTINCT month_key, make_id, fuel_id FROM fact_registration) g), 0);

CALL etl_check('validate', 'fact_registration rows without a matching dimension member',
    (SELECT COUNT(*) FROM fact_registration r
     LEFT JOIN dim_date d ON d.month_key = r.month_key
     LEFT JOIN dim_make k ON k.make_id   = r.make_id
     LEFT JOIN dim_fuel f ON f.fuel_id   = r.fuel_id
     LEFT JOIN dim_body b ON b.body_id   = r.body_id
     WHERE d.month_key IS NULL OR k.make_id IS NULL OR f.fuel_id IS NULL OR b.body_id IS NULL), 0);

CALL etl_check('validate', 'Months with both COE categories present',
    (SELECT COUNT(*) FROM fact_coe_month WHERE cat_a_quota > 0 AND cat_b_quota > 0), 49);

CALL etl_check('validate', 'Months with car population including Electric',
    (SELECT COUNT(*) FROM fact_fleet_month WHERE cars_total > 0 AND cars_bev > 0), 49);

-- ---------------------------------------------------------------------
-- 4.3 Reconciliation with the separately published MVP02 annual totals
-- ---------------------------------------------------------------------
CALL etl_check('validate', 'Monthly M03 total minus MVP02 annual total, 2023',
    (SELECT SUM(r.registrations) FROM fact_registration r JOIN dim_date d ON d.month_key = r.month_key WHERE d.year_num = 2023)
    - (SELECT SUM(registrations) FROM fact_annual_reg WHERE year_num = 2023), 0);
CALL etl_check('validate', 'Monthly M03 total minus MVP02 annual total, 2024',
    (SELECT SUM(r.registrations) FROM fact_registration r JOIN dim_date d ON d.month_key = r.month_key WHERE d.year_num = 2024)
    - (SELECT SUM(registrations) FROM fact_annual_reg WHERE year_num = 2024), 0);
CALL etl_check('validate', 'Monthly M03 total minus MVP02 annual total, 2025',
    (SELECT SUM(r.registrations) FROM fact_registration r JOIN dim_date d ON d.month_key = r.month_key WHERE d.year_num = 2025)
    - (SELECT SUM(registrations) FROM fact_annual_reg WHERE year_num = 2025), 0);

-- ---------------------------------------------------------------------
-- 4.4 Analysis mart view and headline figures
-- ---------------------------------------------------------------------
CALL etl_check('validate', 'v_segment_month rows (49 months x 3 segments)',
    (SELECT COUNT(*) FROM v_segment_month), 147);
CALL etl_check('validate', 'In-scope BEV registrations in v_segment_month',
    (SELECT SUM(market_bev) FROM v_segment_month), 63131);

CALL etl_check('validate', 'SUV Capture Gap, P3 to P4',
    (SELECT ROUND(b4 - b3 / m3 * m4) FROM (
        SELECT SUM(CASE WHEN period_code = 'P3' THEN market_bev END) AS m3,
               SUM(CASE WHEN period_code = 'P4' THEN market_bev END) AS m4,
               SUM(CASE WHEN period_code = 'P3' THEN byd_bev END)    AS b3,
               SUM(CASE WHEN period_code = 'P4' THEN byd_bev END)    AS b4
        FROM v_segment_month WHERE body = 'SUV') p), -1426);
CALL etl_check('validate', 'Sedan Capture Gap, P3 to P4',
    (SELECT ROUND(b4 - b3 / m3 * m4) FROM (
        SELECT SUM(CASE WHEN period_code = 'P3' THEN market_bev END) AS m3,
               SUM(CASE WHEN period_code = 'P4' THEN market_bev END) AS m4,
               SUM(CASE WHEN period_code = 'P3' THEN byd_bev END)    AS b3,
               SUM(CASE WHEN period_code = 'P4' THEN byd_bev END)    AS b4
        FROM v_segment_month WHERE body = 'Sedan') p), 979);
CALL etl_check('validate', 'MPV Capture Gap, P3 to P4',
    (SELECT ROUND(b4 - b3 / m3 * m4) FROM (
        SELECT SUM(CASE WHEN period_code = 'P3' THEN market_bev END) AS m3,
               SUM(CASE WHEN period_code = 'P4' THEN market_bev END) AS m4,
               SUM(CASE WHEN period_code = 'P3' THEN byd_bev END)    AS b3,
               SUM(CASE WHEN period_code = 'P4' THEN byd_bev END)    AS b4
        FROM v_segment_month WHERE body = 'MPV') p), -475);
CALL etl_check('validate', 'BYD BEV change P3 to P4, three segments',
    (SELECT SUM(CASE WHEN period_code = 'P4' THEN byd_bev ELSE 0 END)
          - SUM(CASE WHEN period_code = 'P3' THEN byd_bev ELSE 0 END) FROM v_segment_month), 4147);

-- ---------------------------------------------------------------------
-- 4.5 Run summary
-- ---------------------------------------------------------------------
SELECT stage,
       SUM(status = 'PASS') AS passed,
       SUM(status = 'FAIL') AS failed,
       SUM(status = 'INFO') AS info_rows
FROM etl_check_log
GROUP BY stage
ORDER BY MIN(check_id);

SELECT check_id, stage, check_name, actual_value, expected_value, status
FROM etl_check_log
ORDER BY check_id;
