# BA13FT ABD 2610 · Group 20 — Singapore EV (EV SG) Market Analysis

Group project repository for the ABD Practice Module. It holds the **cleaned analysis datasets**, the cleaning notebook that produces them, the MySQL database scripts and the **analysis mart** used by all four analytical questions (Q1 to Q4). The data covers public Singapore datasets on passenger car registrations, COE bidding results, vehicle population and public EV chargers, used to study the Singapore battery electric vehicle (BEV) market.

## Repository structure

```
.
├── README.md
├── cleaned_data/
│   ├── 01_clean_data.ipynb     # Cleaning notebook (raw data -> CSVs below), 17 stop checks
│   ├── registration_fact.csv   # Monthly registration fact table (analysis backbone)
│   ├── coe_clean.csv           # COE bidding results
│   ├── fleet_clean.csv         # Vehicle population by fuel type
│   ├── mvp02_clean.csv         # Annual new registrations (make x fuel x body)
│   ├── mvp01_clean.csv         # Annual registrations (by make)
│   ├── chargers_clean.csv      # Public EV charger registry
│   ├── cleaning_log.csv        # Cleaning checks and results
│   └── data_dictionary.csv     # Field definitions for every table
├── SQL/
│   ├── Group20_BYD_BEV_schema_1.sql  # MySQL star schema (9 tables + v_segment_month view)
│   └── Group20_BYD_BEV_full_1.sql    # Schema with data loaded
└── mart/
    ├── 02_build_mart.ipynb     # Builds the analysis mart from cleaned_data/, 7 input + 12 mart checks
    ├── segment_month_full.csv  # month x segment (147 rows), used by Q2, Q3 and Q4
    ├── segment_period.csv      # period x segment (12 rows): growth, shift-share, Capture Gap
    ├── competitor_gap_p3p4.csv # make x segment, P3 to P4 competitor Capture Gaps
    └── mart_check_log.csv      # Mart checks and results
```

## Datasets

| File | Raw source | Grain | Time range | Rows |
|---|---|---|---|---|
| `registration_fact.csv` | M03-Car_Regn_by_make | month × make × fuel × body | 2022-07 – 2026-07 | 26,898 |
| `coe_clean.csv` | COEBiddingResultsPrices | month × bidding round × COE category | 2010-01 – 2026-09 | 1,975 |
| `fleet_clean.csv` | M09-Vehs_by_Fuel_Type | month × vehicle category × fuel | 2016-01 – 2026-07 | 3,611 |
| `mvp02_clean.csv` | MVP02-2_New_Cars_by_make_type | year × make × importer × fuel × body | 2015 – 2025 | 6,896 |
| `mvp01_clean.csv` | MVP01-6_Cars_by_make | year × make × fuel | 2005 – 2025 | 2,198 |
| `chargers_clean.csv` | Electric_Vehicle_Charging_Points_Jun 2026 | one row per charge point | registered 2024-01 – 2026-12 | 11,353 (16,935 outlets) |

See [`cleaned_data/data_dictionary.csv`](cleaned_data/data_dictionary.csv) for field definitions.

## Key cleaning rules

- **M03 monthly registrations (analysis backbone)**
  - Study window starts in **2022-07** (when LTA changed its body-type classification) and ends in 2026-07.
  - Blank registration counts are treated as 0. Checks for invalid counts, duplicate records and missing key fields all returned 0.
  - Body types standardised to SUV / Sedan / MPV / Hatchback / Station Wagon / Coupe-Convertible.
  - Importer types (AMD / PI) are summed and the data aggregated to month × make × fuel × body; totals match before and after aggregation (172,394 vehicles).
  - `fuel_type = Electric` means battery electric (BEV).
- **COE**: thousands separators removed from `bids_success` and `bids_received`, then converted to numbers.
- **M09 vehicle population**: `-` placeholders treated as 0.
- **Chargers**: column names standardised, dates and coordinates parsed, de-duplicated on `cp_id`.

All checks and their results are in [`cleaned_data/cleaning_log.csv`](cleaned_data/cleaning_log.csv).

## Analysis mart

`mart/02_build_mart.ipynb` reads the cleaned CSVs and builds one shared mart, so every workstream uses the same figures.

- **Scope**: BEV (`fuel_type = Electric`) registrations in SUV, Sedan and MPV. Segment market = BEV registrations of all makes; BYD share = BYD BEV ÷ segment market.
- **Periods**: August to July. P1 = 2022-08 to 2023-07, P2, P3, P4 = 2025-08 to 2026-07.
- **Capture Gap**: actual registrations − previous-period share × current-period market.
- **Input checks (7)**: unique fact keys, 49 contiguous months, valid counts, total of 172,394, complete body-type grid, COE coverage, car population coverage.
- **Mart checks (12)**: grain, completeness, logical bounds, share ranges, an independent SQL recomputation (zero difference), fact-table reconciliation, period roll-up, the shift-share identity, the Capture Gap identity, COE alignment, reconciliation with MVP02 annual totals (2023 to 2025) and the frozen headline figures.

Results are in [`mart/mart_check_log.csv`](mart/mart_check_log.csv). The notebook was added on 14 Oct 2026 and rebuilds the mart from the cleaned data; it reproduces the headline figures used in the report and slides.

## Usage

```python
import pandas as pd

reg = pd.read_csv("cleaned_data/registration_fact.csv", encoding="utf-8-sig")
bev = reg[reg["fuel_type"] == "Electric"]
monthly_bev = bev.groupby("month")["registrations"].sum()
```

> All CSVs are UTF-8 with BOM, so they open correctly in Excel.

To regenerate the cleaned data, place the raw CSVs in the same folder as the notebook (or one level up) and run `cleaned_data/01_clean_data.ipynb` (requires `pandas`). Then run `mart/02_build_mart.ipynb` from the `mart/` folder to rebuild the analysis mart (requires `pandas` and `numpy`).

## Data sources

Public datasets from Singapore's Land Transport Authority (LTA) DataMall / data.gov.sg.
