# Data Dictionary

Group 20 "High Five" · EBA5011 ABD Practice Module · BYD BEV Body-Segment Market Prioritisation in Singapore

This file defines every field produced by the data pipeline and maps each source field to its target. It matches Appendix C of the project report.

- **Database:** `byd_bev_sg` (MySQL 8.0), star schema
- **Analysis window:** July 2022 to July 2026 (49 months)
- **Periods:** P1 = Aug 2022 to Jul 2023, P2 = Aug 2023 to Jul 2024, P3 = Aug 2024 to Jul 2025, P4 = Aug 2025 to Jul 2026
- **BEV:** LTA fuel category `Electric`
- **Scope:** SUV, Sedan and MPV (`dim_body.is_in_scope = 1`)
- **Data steward:** Ding Yuxiang. Changes to any definition in this file go through the data steward.

Contents

1. [MySQL star schema](#1-mysql-star-schema-byd_bev_sg)
2. [Analysis mart](#2-analysis-mart)
3. [Python double-check outputs](#3-python-double-check-outputs-cleaned_data)
4. [Pipeline work tables](#4-pipeline-work-tables)
5. [Source-to-target mapping](#5-source-to-target-mapping)

---

## 1. MySQL star schema (`byd_bev_sg`)

Built by `SQL/03_build_star_schema.sql`. PK = primary key, FK = foreign key.

### dim_date (49 rows, one row per month)

| Field | Type | Key | Definition |
|---|---|---|---|
| month_key | CHAR(7) | PK | Month in YYYY-MM format |
| month_start | DATE | Unique | First day of the month |
| year_num | SMALLINT | | Calendar year |
| month_num | TINYINT | | Calendar month; CHECK between 1 and 12 |
| period_code | CHAR(2) | | P1 to P4 (August to July); NULL for July 2022; CHECK in P1 to P4 |

### dim_make (95 rows, one row per make)

| Field | Type | Key | Definition |
|---|---|---|---|
| make_id | SMALLINT UNSIGNED | PK | Surrogate key, numbered alphabetically |
| make_name | VARCHAR(60) | Unique | Brand as recorded by LTA; spaces trimmed, upper case |
| is_byd | TINYINT(1) | | 1 for BYD |

### dim_fuel (8 rows, one row per fuel type)

| Field | Type | Key | Definition |
|---|---|---|---|
| fuel_id | TINYINT UNSIGNED | PK | Surrogate key |
| fuel_type | VARCHAR(40) | Unique | LTA fuel category |
| is_bev | TINYINT(1) | | 1 only for `Electric` (battery electric vehicle) |

### dim_body (7 rows, one row per body type)

| Field | Type | Key | Definition |
|---|---|---|---|
| body_id | TINYINT UNSIGNED | PK | Surrogate key |
| body_type | VARCHAR(40) | Unique | Standardised label: SUV, Sedan, MPV, Hatchback, Station Wagon, Coupe/Convertible, MPV/Station Wagon |
| mvp02_label | VARCHAR(60) | | Label as written in the LTA source files |
| is_in_scope | TINYINT(1) | | 1 for SUV, Sedan and MPV |
| is_combined | TINYINT(1) | | 1 for the combined MPV/Station Wagon label used in older MVP02 years |

### dim_charger (11,353 rows, one row per charge point; reference table)

June 2026 snapshot of the EV charging point registry. Context only; it joins to no fact table.

| Field | Type | Key | Definition |
|---|---|---|---|
| cp_id | VARCHAR(20) | PK | Unique charge point ID (source `evCpId`) |
| charger_code | VARCHAR(12) | Index | Charger registration code |
| operator_name | VARCHAR(100) | | Charge point operator |
| outlets | SMALLINT UNSIGNED | | Number of charging outlets |
| plug_type | VARCHAR(12) | | Type 2, CCS 2 or CHAdeMO |
| charging_speed_kw | DECIMAL(6,1) | | Rated charging speed in kW |
| postal_code | CHAR(6) | | Six-digit postal code, kept as text so leading zeros survive |
| block_no, street_name, building_name, floor_no, lot_no | VARCHAR | | Address text from the source |
| public_accessible | VARCHAR(5) | | Yes or No |
| longitude | DECIMAL(11,7) | | Longitude |
| latitude | DECIMAL(10,7) | | Latitude |
| registration_date | DATE | | Registration date, read day first (DD/MM/YYYY) |
| parking_lot_type | VARCHAR(100) | | Type of parking lot |

### fact_registration (26,898 rows, one row per month × make × fuel × body)

Every month-make-fuel combination is listed across all six body types (4,483 × 6), with 0 where nothing was registered.

| Field | Type | Key | Definition |
|---|---|---|---|
| month_key | CHAR(7) | PK, FK → dim_date | Registration month |
| make_id | SMALLINT UNSIGNED | PK, FK → dim_make | Make |
| fuel_id | TINYINT UNSIGNED | PK, FK → dim_fuel | Fuel type |
| body_id | TINYINT UNSIGNED | PK, FK → dim_body | Body type |
| registrations | INT UNSIGNED | | New car registrations, importer types AMD and PI summed |

### fact_coe_month (49 rows, one row per month)

Categories A and B. Each month has two bidding exercises: premiums are averaged; quotas and bids are summed.

| Field | Type | Key | Definition |
|---|---|---|---|
| month_key | CHAR(7) | PK, FK → dim_date | Bidding month |
| cat_a_premium, cat_b_premium | DECIMAL(10,1) | | COE premium in S$, mean of the month's exercises |
| cat_a_quota, cat_b_quota | INT UNSIGNED | | Quota, summed |
| cat_a_bids_received, cat_b_bids_received | INT UNSIGNED | | Bids received, summed |
| cat_a_bids_success, cat_b_bids_success | INT UNSIGNED | | Successful bids, summed |
| n_exercises | TINYINT UNSIGNED | | Number of bidding exercises in the month |

### fact_fleet_month (49 rows, one row per month)

| Field | Type | Key | Definition |
|---|---|---|---|
| month_key | CHAR(7) | PK, FK → dim_date | Month |
| cars_total | INT UNSIGNED | | Car population, all fuel types (M09 category `Cars`) |
| cars_bev | INT UNSIGNED | | Car population, fuel type `Electric` |
| bev_share_pct | DECIMAL(6,2) | | Generated column: 100 × cars_bev / cars_total |

### fact_annual_reg (5,894 rows, one row per year × make × fuel × body)

Used to reconcile the monthly M03 totals with the separately published MVP02 annual totals.

| Field | Type | Key | Definition |
|---|---|---|---|
| year_num | SMALLINT | PK | Year; CHECK between 2015 and 2025; annual grain, so no FK to the monthly dim_date |
| make_id | SMALLINT UNSIGNED | PK, FK → dim_make | Make |
| fuel_id | TINYINT UNSIGNED | PK, FK → dim_fuel | Fuel type |
| body_id | TINYINT UNSIGNED | PK, FK → dim_body | Body type, including the combined MPV/Station Wagon label |
| registrations | INT UNSIGNED | | Annual new registrations, importer types summed |

### v_segment_month (view, 147 rows, one row per month × segment)

| Field | Definition |
|---|---|
| month_key | Month |
| period_code | P1 to P4 |
| body | SUV, Sedan or MPV |
| market_all | Registrations of all fuel types in the segment |
| market_bev | BEV registrations of all makes (segment market) |
| byd_bev | BYD BEV registrations |
| byd_share_pct | 100 × byd_bev / market_bev, 2 decimals |
| bev_penetration_pct | 100 × market_bev / market_all, 2 decimals |

---

## 2. Analysis mart

Built in MySQL by `SQL/05_build_mart.sql` from the star schema and exported to `mart/*.csv`. The table keys are (month, segment), (period, segment) and (segment, make). Mart check 5 confirms that segment_month_full equals `v_segment_month` on market_all, market_bev and byd_bev; all 17 mart checks are logged in `etl_check_log` with stage `mart`.

### segment_month_full (147 rows, 40 fields, one row per month × segment)

| Field | Definition |
|---|---|
| month | Month, YYYY-MM |
| year, month_num | Calendar year and month |
| period | P1 to P4; blank for July 2022 |
| segment | SUV, Sedan or MPV |
| market_all | Registrations of all fuel types in the segment |
| market_bev | BEV registrations of all makes (segment market) |
| bev_penetration_pct | 100 × market_bev / market_all |
| n_bev_makes | Makes with at least one BEV registration |
| thin_month | 1 when market_bev is below 50 |
| byd_bev | BYD BEV registrations |
| byd_share_pct | 100 × byd_bev / market_bev |
| byd_all | BYD registrations, all fuel types |
| byd_phev | BYD plug-in hybrid registrations |
| top_rival | Largest non-BYD BEV make in the segment-month |
| top_rival_bev | Its BEV registrations |
| top_rival_share_pct | Its share of market_bev |
| market_bev_prev_year | market_bev for the same calendar month one year earlier (`LAG(..., 12)` within segment) |
| byd_bev_prev_year | byd_bev for the same calendar month one year earlier |
| byd_share_prev_year_pct | byd_share_pct for the same calendar month one year earlier |
| benchmark_bev_month | Maintain-share benchmark: byd_share_prev_year_pct / 100 × market_bev |
| capture_gap_month | byd_bev − benchmark_bev_month |
| market_bev_mom_pct | Month-on-month change in market_bev (%) |
| byd_share_mom_pp | Month-on-month change in byd_share_pct (percentage points) |
| cat_a_premium, cat_b_premium | COE premium in S$, mean of the month's exercises |
| cat_a_quota, cat_b_quota | COE quota, summed |
| cat_a_bids_received, cat_b_bids_received | Bids received, summed |
| cat_a_bids_success, cat_b_bids_success | Successful bids, summed |
| n_exercises | Bidding exercises in the month |
| cat_a_premium_mom_pct, cat_b_premium_mom_pct | Month-on-month change in COE premium (%) |
| cat_a_quota_mom_pct, cat_b_quota_mom_pct | Month-on-month change in COE quota (%) |
| cars_total | Car population, all fuel types |
| cars_bev | Car population, Electric |
| fleet_bev_share_pct | 100 × cars_bev / cars_total |

### segment_period (12 rows, one row per period × segment)

s = BYD share, M = segment BEV market; subscripts 0 and 1 are the previous and current period.

| Field | Definition |
|---|---|
| period, segment | Keys |
| market_bev, byd_bev, market_all | 12-month totals |
| bev_penetration_pct | 100 × market_bev / market_all |
| byd_share_pct | 100 × byd_bev / market_bev |
| market_growth_pct | 100 × (M1 / M0 − 1) |
| byd_growth_pct | 100 × (BYD1 / BYD0 − 1) |
| share_change_pp | 100 × (s1 − s0) |
| benchmark_bev | s0 × M1, the volume needed to hold the previous share |
| capture_gap | byd_bev − benchmark_bev |
| market_effect | (s0 + s1) / 2 × (M1 − M0) |
| share_effect | (M0 + M1) / 2 × (s1 − s0) |
| interaction | (s1 − s0) × (M1 − M0); capture_gap = share_effect + interaction / 2 |
| byd_change | byd_bev − BYD0; equals market_effect + share_effect |

### competitor_gap_p3p4 (144 rows, one row per segment × make)

| Field | Definition |
|---|---|
| segment, make | Keys |
| p3_bev, p4_bev | BEV registrations in P3 and P4 |
| p3_share_pct, p4_share_pct | Share of the segment BEV market in P3 and P4 |
| share_change_pp | p4_share_pct − p3_share_pct |
| benchmark_bev | p3_share_pct / 100 × P4 segment market |
| capture_gap | p4_bev − benchmark_bev |

---

## 3. Python double-check outputs (`cleaned_data/`)

Written by `cleaned_data/01_clean_data.ipynb`, which repeats the MySQL cleaning independently from the raw files.

| File | Field | Definition |
|---|---|---|
| registration_fact.csv | month | Registration month, YYYY-MM |
| registration_fact.csv | make | Brand, spaces trimmed |
| registration_fact.csv | fuel_type | Fuel type; Electric = BEV |
| registration_fact.csv | body | Standardised body type |
| registration_fact.csv | registrations | New registrations for month × make × fuel × body, importer types summed |
| coe_clean.csv | month | Bidding month |
| coe_clean.csv | bidding_no | Bidding exercise within the month (1 or 2) |
| coe_clean.csv | vehicle_class | COE category A to E |
| coe_clean.csv | quota, bids_success, bids_received, premium | Numeric values, thousands separators removed |
| fleet_clean.csv | month, category, type, number | Vehicle population by category and fuel type; "-" set to 0 |
| mvp02_clean.csv | year, make, importer_type, fuel, type, number | Annual new registrations; importer type (AMD or PI) from 2023 |
| mvp01_clean.csv | year, make, fuel_type, number | Annual registrations by make; fuel type blank in 57.4% of rows |
| chargers_clean.csv | charger_code to parking_lot_type | Charger registry with standardised names; dates read as DD/MM/YYYY; de-duplicated on cp_id |
| cleaning_log.csv | check, result | One row per logged check and count, including the full SHA-256 hash of the M03 file |

---

## 4. Pipeline work tables

Created inside `byd_bev_sg` by the MySQL scripts.

| Table | Script | Content |
|---|---|---|
| stg_m03_raw, stg_coe_raw, stg_m09_raw, stg_mvp02_raw, stg_mvp01_raw, stg_charger_raw | 01_load_raw.sql | Raw files, every field stored as text (VARCHAR 255), plus a row_id |
| ref_body_map | 02_clean.sql | LTA body labels mapped to standard body types, scope and combined flags |
| cln_registration, cln_coe, cln_fleet, cln_mvp02, cln_charger | 02_clean.sql | Cleaned, typed tables that feed the star schema |
| etl_check_log | 00_setup.sql | check_id, stage (load, clean, build, validate, mart), check_name, actual_value, expected_value, status (PASS, FAIL or INFO), checked_at |

---

## 5. Source-to-target mapping

Rules are implemented in `SQL/02_clean.sql` and `SQL/03_build_star_schema.sql` and repeated in `cleaned_data/01_clean_data.ipynb`. The mart rows are built by `SQL/05_build_mart.sql`.

| Source file | Source field | Transformation rule | Target |
|---|---|---|---|
| M03-Car_Regn_by_make.csv | month | Parse as YYYY-MM; keep July 2022 to July 2026 | dim_date.month_key; fact_registration.month_key |
| M03-Car_Regn_by_make.csv | make | Trim spaces; upper case; assign surrogate key | dim_make.make_name, make_id |
| M03-Car_Regn_by_make.csv | fuel_type | Assign surrogate key; is_bev = 1 for Electric | dim_fuel.fuel_type, is_bev |
| M03-Car_Regn_by_make.csv | vehicle_type | Map to six standard body types; is_in_scope = 1 for SUV, Sedan, MPV | dim_body.body_type, is_in_scope |
| M03-Car_Regn_by_make.csv | importer_type | Overlap check, then summed out (AMD + PI) | Absorbed into fact_registration.registrations |
| M03-Car_Regn_by_make.csv | number | Blank to 0; non-negative whole number check; sum over importer types | fact_registration.registrations |
| COEBiddingResultsPrices.csv | month, bidding_no | Parse month; count exercises per month; keep July 2022 to July 2026 | fact_coe_month.month_key, n_exercises |
| COEBiddingResultsPrices.csv | vehicle_class | Keep Category A and B; one field set per category | fact_coe_month cat_a_* and cat_b_* fields |
| COEBiddingResultsPrices.csv | premium | Remove thousands separators; monthly mean | fact_coe_month.cat_a_premium, cat_b_premium |
| COEBiddingResultsPrices.csv | quota, bids_received, bids_success | Remove thousands separators; monthly sum | fact_coe_month quota and bid fields |
| M09-Vehs_by_Fuel_Type.csv | month, category, type, number | "-" to 0; keep category Cars; total and Electric per month | fact_fleet_month.cars_total, cars_bev |
| MVP02-2_New_Cars_by_make_type.csv | year, make, fuel, type, number | Upper-case make; sum importer types; map type through dim_body.mvp02_label | fact_annual_reg |
| MVP01-6_Cars_by_make.csv | all fields | Profiled only: fuel type blank in 57.4% of rows | Not loaded |
| Electric_Vehicle_Charging_Points_Jun 2026.csv | 17 source columns | Rename; parse dates as DD/MM/YYYY and coordinates as decimals; pad postal codes to six digits; de-duplicate on cp_id | dim_charger |
| byd_bev_sg star schema | fact_registration with dimensions | Filter is_in_scope = 1; aggregate by month and segment (05_build_mart.sql) | v_segment_month; segment_month_full |
| byd_bev_sg star schema | fact_coe_month, fact_fleet_month | Join on month; month-on-month changes (05_build_mart.sql) | segment_month_full COE and fleet fields |
| segment_month_full | market_bev, byd_bev, market_all | Sum to August-July periods; shift-share terms (05_build_mart.sql) | segment_period |
| byd_bev_sg star schema | fact_registration, BEV rows in P3 and P4 | Sum by segment and make; hold each make's P3 share into P4 (05_build_mart.sql) | competitor_gap_p3p4 |
