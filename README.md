# BA13FT ABD 2610 · Group 20 — Singapore EV (EV SG) Market Analysis

Group project repository for the ABD Practice Module. It currently holds the **cleaned analysis datasets** and the cleaning notebook that produces them. The data covers four public Singapore datasets: passenger car registrations, COE bidding results, vehicle population and public EV chargers, used to study the Singapore battery electric vehicle (BEV) market.

## Repository structure

```
.
├── README.md
└── cleaned_data/
    ├── 01_clean_data.ipynb     # Cleaning notebook (raw data -> CSVs below)
    ├── registration_fact.csv   # Monthly registration fact table (analysis backbone)
    ├── coe_clean.csv           # COE bidding results
    ├── fleet_clean.csv         # Vehicle population by fuel type
    ├── mvp02_clean.csv         # Annual new registrations (make x fuel x body)
    ├── mvp01_clean.csv         # Annual registrations (by make)
    ├── chargers_clean.csv      # Public EV charger registry
    ├── cleaning_log.csv        # Cleaning checks and results
    └── data_dictionary.csv     # Field definitions for every table
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

## Usage

```python
import pandas as pd

reg = pd.read_csv("cleaned_data/registration_fact.csv", encoding="utf-8-sig")
bev = reg[reg["fuel_type"] == "Electric"]
monthly_bev = bev.groupby("month")["registrations"].sum()
```

> All CSVs are UTF-8 with BOM, so they open correctly in Excel.

To regenerate the cleaned data, place the raw CSVs in the same folder as the notebook (or one level up) and run `cleaned_data/01_clean_data.ipynb` (requires `pandas`).

## Data sources

Public datasets from Singapore's Land Transport Authority (LTA) DataMall / data.gov.sg.
