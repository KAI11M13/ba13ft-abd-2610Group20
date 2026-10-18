"""
Create one PNG containing six small P1-P4 bar charts for BYD BEV registrations.

Run:
    python generate_bodytype_p1p4_chart.py

Expected input:
    registration_fact.csv in the same folder.

Required packages:
    pip install pandas matplotlib

Outputs:
    BodyType_P1_P4_python.png
    BodyType_P1_P4_summary.csv
"""

from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt

BASE_DIR = Path(__file__).resolve().parent
FACT_PATH = BASE_DIR / "registration_fact.csv"
OUTPUT_IMAGE = BASE_DIR / "BodyType_P1_P4_python.png"
OUTPUT_CSV = BASE_DIR / "BodyType_P1_P4_summary.csv"

PERIODS = {
    "P1": ("2022-08-01", "2023-07-01"),
    "P2": ("2023-08-01", "2024-07-01"),
    "P3": ("2024-08-01", "2025-07-01"),
    "P4": ("2025-08-01", "2026-07-01"),
}

BODY_ORDER = [
    "SUV",
    "Sedan",
    "MPV",
    "Hatchback",
    "Coupe/Convertible",
    "Station Wagon",
]

BAR_COLOR = "#CDBB9F"
BAR_EDGE = "#A58F72"
PANEL_COLOR = "#F7F3EB"
TITLE_COLOR = "#176B66"
TEXT_COLOR = "#1F2933"
MUTED_COLOR = "#667085"
GRID_COLOR = "#E8DCC8"
MIN_VISUAL_HEIGHT = 500


def load_data() -> pd.DataFrame:
    if not FACT_PATH.exists():
        raise FileNotFoundError(
            f"Could not find {FACT_PATH.name}. Put this script in the same folder "
            "as registration_fact.csv."
        )

    data = pd.read_csv(FACT_PATH, encoding="utf-8-sig")
    required = {"month", "make", "fuel_type", "body", "registrations"}
    missing = required.difference(data.columns)
    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")

    data["month"] = pd.to_datetime(data["month"], format="%Y-%m")
    return data[
        (data["make"] == "BYD")
        & (data["fuel_type"] == "Electric")
        & (data["body"].isin(BODY_ORDER))
    ].copy()


def build_summary(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for period, (start, end) in PERIODS.items():
        frame = data[
            data["month"].between(pd.Timestamp(start), pd.Timestamp(end))
        ]
        row = {"Period": period}
        for body in BODY_ORDER:
            row[body] = int(
                frame.loc[frame["body"] == body, "registrations"].sum()
            )
        rows.append(row)
    return pd.DataFrame(rows)


def draw_chart(summary: pd.DataFrame) -> None:
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
        "axes.unicode_minus": False,
    })

    fig, axes = plt.subplots(2, 3, figsize=(16, 9), facecolor="white")
    period_labels = summary["Period"].tolist()

    for ax, body in zip(axes.flat, BODY_ORDER):
        values = summary[body].tolist()
        visual_values = [max(value, MIN_VISUAL_HEIGHT) if value > 0 else 0 for value in values]
        ax.set_facecolor(PANEL_COLOR)

        bars = ax.bar(
            period_labels,
            visual_values,
            width=0.58,
            color=BAR_COLOR,
            edgecolor=BAR_EDGE,
            linewidth=0.9,
        )

        total = sum(values)
        ax.set_title(
            f"{body}\nP1-P4 total: {total:,}",
            loc="left",
            fontsize=14,
            color=TITLE_COLOR,
            fontweight="bold",
            pad=8,
        )

        for bar, value in zip(bars, values):
            height = bar.get_height()
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                min(height + 120, 8050),
                f"{value:,}",
                ha="center",
                va="bottom",
                fontsize=10,
                fontweight="bold",
                color=TEXT_COLOR,
            )

        ax.set_ylim(0, 8000)
        ax.tick_params(axis="x", labelsize=10, colors=MUTED_COLOR)
        ax.tick_params(axis="y", labelsize=8, colors=MUTED_COLOR)
        ax.grid(axis="y", color=GRID_COLOR, alpha=0.8)
        ax.set_axisbelow(True)

        for spine in ax.spines.values():
            spine.set_visible(False)

    fig.text(
        0.06,
        0.985,
        "BYD BEV registrations by body type across P1-P4",
        ha="left",
        va="top",
        fontsize=20,
        fontweight="bold",
        color=TITLE_COLOR,
    )
    fig.text(
        0.06,
        0.935,
        "Common scale: 0-8,000 units. Small positive values use a minimum visual height; labels show actual registrations. "
        "P1: Aug 2022-Jul 2023; P2: Aug 2023-Jul 2024; "
        "P3: Aug 2024-Jul 2025; P4: Aug 2025-Jul 2026.",
        ha="left",
        va="top",
        fontsize=9.5,
        color=MUTED_COLOR,
    )
    fig.text(
        0.94,
        0.015,
        "Source: LTA registrations",
        ha="right",
        fontsize=9,
        color=MUTED_COLOR,
    )

    fig.tight_layout(rect=(0.04, 0.04, 0.98, 0.88), h_pad=2.4, w_pad=1.8)
    fig.savefig(OUTPUT_IMAGE, dpi=220, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def main() -> None:
    data = load_data()
    summary = build_summary(data)
    summary.to_csv(OUTPUT_CSV, index=False, encoding="utf-8-sig")
    draw_chart(summary)

    print(f"Saved image: {OUTPUT_IMAGE}")
    print(f"Saved summary: {OUTPUT_CSV}")
    print(summary.to_string(index=False))


if __name__ == "__main__":
    main()
