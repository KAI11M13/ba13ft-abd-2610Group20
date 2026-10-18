# COE revision using the original calculation method

This package retains the original market-level outcome: BEV registrations across all makes and all body types. The eight original Table 6.2 correlations, slopes and p-values reproduce to the report's three decimals. BYD segment-share tests continue to use SUV, Sedan and MPV.

Read `Group20_COE_Original_Method_Revision_Guide.docx` or `COE_Revision_Guide.md` for Chinese editing instructions and complete English replacement text. The CSV and chart outputs have already been generated. No rerun is needed to use them in the report.

## Optional reproducibility steps

Open a terminal in this package's extracted folder. Python 3.12 is recommended.

```bash
python -m pip install -r requirements.txt
python run_coe_analysis.py
```

The script reads `inputs/registration_fact.csv` and `inputs/coe_clean.csv`, and writes to `results/`. To use another local folder:

```bash
python run_coe_analysis.py --data-dir /path/to/cleaned_data --output-dir /path/to/results
```

The original table reproduction assertions intentionally flag a changed input snapshot. The supplied inputs are pinned to repository commit `dcda40a6899000e253ac588ed3719a496336795f`. The script does not use the network, mutate input files, or rerun MySQL.

## Analytical interpretation

The original simple result is r = 0.288, beta = 1.161, nominal p = 0.047, R² = 0.083. Calendar controls improve in-sample fit, and the calendar-controlled quota p-value is 0.028. Calendar-only fit must be shown alongside this result. A quadratic extension adds little. Residual dependence, influential months and multiple testing limit inference. Leave-one-month-out refits are sensitivity checks, not forecasting validation.

See `results/analysis_metadata.json` for versions, input hashes, source provenance and review limits. This COE package supersedes the three-segment COE replacement material in the previous combined guide. The K-means material from that guide is unaffected.
