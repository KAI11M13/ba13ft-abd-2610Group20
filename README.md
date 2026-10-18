# Group20 — Original COE analysis reproduction

Reproducible Python implementation of the **COE analysis in the original `Group20 (3).docx`** (not the later extended model-comparison report).

## What this reproduces

| Original report location | Output |
|---|---|
| Section 5.3 | Same-month and lag-1 Pearson correlations and separate simple OLS regressions |
| Section 6.3.1 / Table 6.2 | 8 market-level COE tests (`outputs/table_6_2_market_coe_tests.csv`) |
| Section 6.3.2 / Appendix Table A.7 | 24 BYD segment-share COE tests (`outputs/table_A_7_byd_segment_share_tests.csv`) |
| Section 6.3.1 figure | Category B quota vs BEV market growth scatterplot |
| Section 6.3.2 figure | BYD monthly share trends for SUV, Sedan, MPV |

The script also writes a monthly modeling dataset and a machine-readable validation log.

## Run

From this directory:

```bash
python -m pip install -r requirements.txt
python scripts/reproduce_original_coe.py
```

The script reads `data/coe_clean.csv` and `data/registration_fact.csv`, writes the tables to `outputs/`, and plots to `figures/`. No MySQL connection is required for this reproduction: these are the cleaned CSV exports of the source pipeline.

## Exact definitions

- **Time window:** July 2022 to July 2026 (49 months). Month-on-month models have 48 observations; one-month lag models have 47.
- **BEV:** `fuel_type == 'Electric'` only.
- **COE monthly quota:** sum of quotas over bidding exercises for Category A or B.
- **COE monthly premium:** arithmetic mean of bidding-exercise premiums for Category A or B.
- **COE change (%):** `100 * (current_month / previous_month - 1)`.
- **Market growth (%):** `100 * (BEV registrations this month / previous month - 1)`.
- **BYD segment share (%):** `100 * BYD Electric registrations in segment / all-make Electric registrations in segment`.
- **BYD share change (percentage points):** `share_this_month - share_previous_month`, **not** relative percentage growth.
- **Lag 1:** previous month's COE percentage change regressed against this month's outcome.
- **Statistics:** Pearson r and a separate OLS with intercept for each predictor/outcome pair. Two-sided ordinary OLS p-values; no causal claim or multiple-testing correction.

## Important scope discrepancy in the original report

The original report's **market-level** COE result `r=0.288`, `p=0.047`, `R²=0.083` is reproducible when the outcome includes **all BEV body types** in `registration_fact.csv`. This is broader than the main project scope (SUV, Sedan, MPV). Restricting the market-level outcome to those three segments produces a different result (`r≈0.227`, `p≈0.121`). The code intentionally reproduces the *original report's published numbers*, and the monthly output includes both scopes for audit. Do not describe the market-level COE result as three-segment-only without correcting the analysis.

The 24 BYD share tests **do** use SUV, Sedan and MPV. In particular, the closest nominal test is Sedan share vs lagged Category B quota (`r≈-0.271`, `p≈0.065`), with **0/24** significant at 5%.

## Source files

`data/coe_clean.csv` and `data/registration_fact.csv` come from the user-provided `Clean-2.zip`. Both are cleaned LTA-derived data. The official source datasets described in the report are LTA COE Bidding Results and LTA M03 Car Registrations by Make.

## Interpretation and limitations

The Category B same-month relationship is weak (R²≈0.083), and the nominal p-value is close to 0.05 across multiple tested specifications. Correlation does not imply causality; quotas are registration capacity, not a direct measure of consumer demand. No significant COE–BYD share test is not proof of zero economic effect. This package reproduces original descriptive and exploratory results; it is not a validated forecasting pipeline.

## Suggested GitHub placement

Upload this folder as `analysis/coe_original/` in your repository, preserving the relative paths. If you already store the two CSV files elsewhere, use `--data-dir /path/to/cleaned_data` instead of duplicating them.
