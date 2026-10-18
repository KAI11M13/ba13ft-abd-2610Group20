# BYD BEV Body-Segment Market Prioritisation in Singapore

Group 20 "High Five" · EBA5011 ABD Practice Module

**Main question:** How can BYD stay Singapore's BEV leader as the market grows?

This repository holds the data pipeline behind the project: the MySQL scripts for cleaning, the star schema and the analysis mart, a Python double-check, the Q1 to Q3 dashboard and the data documentation. Every figure in the report and slides can be rebuilt from the public LTA files with the steps below.

## Repository structure

```
.
├── README.md
├── data_dictionary.md                # Field definitions and source-to-target mapping
├── SQL/
│   ├── 00_setup.sql                  # Database, check log, stop-check procedures
│   ├── 01_load_raw.sql               # Raw CSV files -> staging tables (all text)
│   ├── 02_clean.sql                  # Cleaning rules and stop checks
│   ├── 03_build_star_schema.sql      # Star schema and view v_segment_month
│   ├── 04_validate.sql               # Reconciliation and headline-figure checks
│   ├── 05_build_mart.sql             # Analysis mart tables and 17 mart checks
│   ├── Group20_BYD_BEV_schema_1.sql  # Star schema definition only
│   └── Group20_BYD_BEV_full_1.sql    # Database snapshot (schema + data)
├── cleaned_data/
│   ├── 01_clean_data.ipynb           # Python double-check of the MySQL cleaning
│   ├── registration_fact.csv         # Cleaned M03, month x make x fuel x body
│   ├── coe_clean.csv
│   ├── fleet_clean.csv
│   ├── mvp02_clean.csv
│   ├── mvp01_clean.csv
│   ├── chargers_clean.csv
│   ├── cleaning_log.csv              # Checks and counts from the double-check
│   └── data_dictionary.csv
├── mart/                             # Exported from MySQL (05_build_mart.sql)
│   ├── segment_month_full.csv        # month x segment, 147 rows
│   ├── segment_period.csv            # period x segment, 12 rows
│   └── competitor_gap_p3p4.csv       # segment x make, P3 to P4 Capture Gaps, 144 rows
└── dashboard/
    └── BYD_Q1_Q3_dashboard.html      # Q1 to Q3 dashboard, data embedded, opens offline
```

The raw LTA files are public and are not stored here. Download them from data.gov.sg (see Data sources).

## Data sources

All six datasets are published by the Land Transport Authority on data.gov.sg under the Singapore Open Data Licence 1.0.

| File | Content | Grain | Raw rows | Role |
|---|---|---|---|---|
| M03-Car_Regn_by_make.csv | New car registrations by make, fuel, body and importer type | Monthly | 61,359 | Core fact table for Q1 to Q4 |
| COEBiddingResultsPrices.csv | COE quota, bids and premium by category | Per bidding exercise | 1,975 | Q4 explanatory variables |
| M09-Vehs_by_Fuel_Type.csv | Vehicle population by fuel type | Monthly | 3,611 | Context: BEV share of car population |
| MVP02-2_New_Cars_by_make_type.csv | Annual new registrations by make and type | Annual | 6,896 | Reconciliation of M03 totals |
| MVP01-6_Cars_by_make.csv | Annual registrations by make | Annual | 2,198 | Dropped: fuel type blank in 57.4% of rows |
| Electric_Vehicle_Charging_Points_Jun 2026.csv | Registered charge points | Snapshot | 11,353 | Context: charging infrastructure |

## Pipeline

```
6 LTA CSV files
  -> MySQL: 01_load_raw.sql -> 02_clean.sql -> 03_build_star_schema.sql -> 04_validate.sql
  -> star schema byd_bev_sg + view v_segment_month
  -> MySQL: 05_build_mart.sql -> analysis mart tables, exported to mart/*.csv
  -> Q1 to Q4 analyses and dashboard/BYD_Q1_Q3_dashboard.html

Checks alongside the main path:
  - Python double-check (cleaned_data/01_clean_data.ipynb): same rules, run independently from the raw files
  - Power BI (Power Query): column quality, distribution and profile of the cleaned tables
```

1. **MySQL cleaning (production path).** Raw files are loaded into staging tables with every field stored as text, then cleaned with SQL and written to the star schema. Every check writes one row to `etl_check_log`; a failed stop check halts the run.
2. **Python double-check.** The notebook repeats the cleaning from the raw files and compares row counts and totals. It also prepares the pipeline for automation: when LTA publishes new data, the cleaning can be rerun without manual steps.
3. **Power BI profiling.** Power Query checks valid, error and empty shares for each column of the cleaned tables.
4. **Analysis mart.** Built in MySQL by `05_build_mart.sql`: one row per month and segment (segment_month_full), plus the period table and the competitor Capture Gaps, shared by all four analytical questions.

## How to run

### MySQL pipeline (MySQL 8.0)

1. Enable local file loading:
   - Server: `SET GLOBAL local_infile = 1;` (admin rights)
   - MySQL Workbench: Edit connection > Advanced > Others: `OPT_LOCAL_INFILE=1`
2. In `SQL/01_load_raw.sql`, replace `C:/Group20/raw_data/` with the folder that holds the raw files. Use forward slashes on Windows.
3. Run the scripts in order: `00_setup.sql`, `01_load_raw.sql`, `02_clean.sql`, `03_build_star_schema.sql`, `04_validate.sql`, `05_build_mart.sql`.
4. Read the results:
   ```sql
   SELECT check_id, stage, check_name, actual_value, expected_value, status
   FROM byd_bev_sg.etl_check_log ORDER BY check_id;
   ```

If a header check fails, open that CSV, read its first line and reorder the `@c` variables in the matching `LOAD DATA` statement. If a line-break check fails, the file has CRLF line endings: change `LINES TERMINATED BY '\n'` to `'\r\n'` for that file.

### Python double-check

Place the raw CSV files in the same folder as the notebook or one level up, then run `cleaned_data/01_clean_data.ipynb` (requires `pandas`). It writes the six cleaned CSV files and `cleaning_log.csv`.

### Analysis mart

`05_build_mart.sql` creates `segment_month_full`, `segment_period` and `competitor_gap_p3p4` in `byd_bev_sg` and runs 17 mart checks. Export each table to `mart/` as CSV (MySQL Workbench: right-click the table > Table Data Export Wizard). The script divides with `1e0` or `100e0` so that MySQL keeps full floating-point precision in shares.

### Dashboard

Open `dashboard/BYD_Q1_Q3_dashboard.html` in a browser. The data are embedded in the file, so no server or internet connection is needed. Filters select the comparison (P1 to P2, P2 to P3, P3 to P4) and the segment.

## Key cleaning rules

- **Study window:** July 2022 to July 2026 (49 months). LTA split MPV from Station Wagon in July 2022, so segment definitions stay constant from that month.
- **Blank counts:** LTA writes zero as a blank; blanks are set to 0.
- **Body types:** LTA labels are mapped to SUV, Sedan, MPV, Hatchback, Station Wagon and Coupe/Convertible.
- **Importer types:** AMD and PI rows are summed after checking that blank and specified importer rows never overlap.
- **Grain:** month × make × fuel × body; 26,898 rows, with the 172,394 registrations unchanged by aggregation.
- **BEV:** fuel type `Electric`.
- **COE:** thousands separators removed (109 bids_received rows, 41 bids_success rows); monthly premium = mean of the exercises, quota and bids = sum.
- **M09:** five "-" placeholders set to 0; category Cars only.
- **Makes:** upper case, because MVP02 records one brand as both Mclaren and MCLAREN; 95 makes.
- **Chargers:** de-duplicated on `cp_id`; registration dates read day first (DD/MM/YYYY).

## Quality checks

| Stage | Where | Stop checks |
|---|---|---|
| Load | SQL/01_load_raw.sql | 12 |
| Clean | SQL/02_clean.sql | 19 |
| Validate | SQL/04_validate.sql | 23 |
| Double-check | cleaned_data/01_clean_data.ipynb | 19 |
| Mart | SQL/05_build_mart.sql | 17 |

Validation includes reconciliation with the separately published MVP02 annual totals (2023: 30,225; 2024: 43,022; 2025: 52,678) and the headline figures: SUV Capture Gap −1,426, Sedan +979, MPV −475.

## Star schema

| Table | Grain | Rows |
|---|---|---|
| fact_registration | month × make × fuel × body | 26,898 |
| fact_coe_month | month | 49 |
| fact_fleet_month | month | 49 |
| fact_annual_reg | year × make × fuel × body | 5,894 |
| dim_date | month (with period P1 to P4) | 49 |
| dim_make | make (with is_byd) | 95 |
| dim_fuel | fuel type (with is_bev) | 8 |
| dim_body | body type (with is_in_scope) | 7 |
| dim_charger | charge point, June 2026 snapshot | 11,353 |

Field definitions are in [data_dictionary.md](data_dictionary.md).

## Data governance

- **Data steward:** Ding Yuxiang. Changes to shared tables, definitions or headline figures go through the data steward, are re-checked and are then released to the team.
- **Lineage:** the double-check records the full SHA-256 hash of the M03 file, which identifies the exact LTA release behind the figures.
- **Documentation:** `data_dictionary.md` holds the data dictionary and the source-to-target mapping.

## Notes

- `SQL/Group20_BYD_BEV_full_1.sql` is an earlier snapshot of the database. Its charger registration dates were read month first; rebuild the database with the pipeline scripts to get the corrected dates.
- Charger data provide context only; no finding depends on them.

## Team

| Member | Workstream |
|---|---|
| Ding Yuxiang | Project design, data engineering (data steward) |
| Liang Huiru | Project design, Q1 growth source |
| Wang Jintian | Q2 market opportunity |
| Shen Dapeng | Q3 share capture |
| Kang Weichen | Q4 COE environment |
