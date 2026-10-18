"""
Generate the Q3 figures used in Q3_Presentation.pptx.

Run from any directory:
    python generate_q3_figures.py

Expected input:
    registration_fact.csv in the same folder as this script.

Required packages:
    pip install pandas numpy matplotlib

Outputs:
    Q3_figure_outputs/Q3_fig2_P3P4_capture_gap.png
    Q3_figure_outputs/Q3_fig3_P3P4_competitor_suv.png
    Q3_figure_outputs/Q3_fig4_P3P4_competitor_mpv.png
    Q3_figure_outputs/Q3_fig5_P3P4_kmeans_validation.png
    Q3_figure_outputs/Q3_competitor_capture_gap_P3P4.csv
    Q3_figure_outputs/Q3_kmeans_monthly_P3P4.csv
    Q3_figure_outputs/Q3_kmeans_profile_P3P4.csv
    Q3_figure_outputs/Q3_kmeans_k_selection_P3P4.csv
"""

from pathlib import Path
from typing import Optional, Tuple

import numpy as np
import pandas as pd
from matplotlib import pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

# ---------------------------------------------------------------------------
# Paths and shared style
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
FACT_PATH = BASE_DIR / "registration_fact.csv"
OUTPUT_DIR = BASE_DIR / "Q3_figure_outputs"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

PALETTE = {
    "primary": "#176B66",
    "secondary": "#4FB5AE",
    "accent": "#81D8D0",
    "pale": "#BFE8E2",
    "neutral1": "#F7F3EB",
    "neutral2": "#E8DCC8",
    "contrast1": "#CDBB9F",
    "contrast2": "#A58F72",
    "text": "#1F2933",
    "muted": "#667085",
}

CLUSTER_COLORS = {
    "Under-capture": PALETTE["contrast2"],
    "Share capture": PALETTE["secondary"],
    "High-share defence": PALETTE["primary"],
}

BODY_MARKERS = {"SUV": "o", "Sedan": "s", "MPV": "D"}
BODIES = ["SUV", "Sedan", "MPV"]


def configure_style() -> None:
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
        "axes.unicode_minus": False,
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "axes.edgecolor": PALETTE["neutral2"],
        "axes.labelcolor": PALETTE["primary"],
        "xtick.color": PALETTE["muted"],
        "ytick.color": PALETTE["muted"],
        "axes.titlecolor": PALETTE["primary"],
        "axes.grid": True,
        "grid.color": PALETTE["neutral2"],
        "grid.alpha": 0.65,
        "axes.axisbelow": True,
    })


# ---------------------------------------------------------------------------
# Data preparation
# ---------------------------------------------------------------------------
def load_bev_data() -> pd.DataFrame:
    if not FACT_PATH.exists():
        raise FileNotFoundError(
            f"Could not find {FACT_PATH.name}. Put this script in the same folder "
            "as registration_fact.csv."
        )

    data = pd.read_csv(FACT_PATH, encoding="utf-8-sig")
    required = {"month", "make", "fuel_type", "body", "registrations"}
    missing = required.difference(data.columns)
    if missing:
        raise ValueError(f"registration_fact.csv is missing columns: {sorted(missing)}")

    data["month"] = pd.to_datetime(data["month"], format="%Y-%m")
    data = data[
        (data["fuel_type"] == "Electric")
        & (data["body"].isin(BODIES))
    ].copy()
    data = data[data["month"].between(pd.Timestamp("2022-07-01"), pd.Timestamp("2026-07-01"))]
    return data


def period_totals(
    data: pd.DataFrame,
    body: str,
    make: Optional[str] = None,
    start: str = "2024-08-01",
    end: str = "2025-07-01",
) -> int:
    frame = data[
        (data["body"] == body)
        & data["month"].between(pd.Timestamp(start), pd.Timestamp(end))
    ]
    if make is not None:
        frame = frame[frame["make"] == make]
    return int(frame["registrations"].sum())


def build_byd_scorecard(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for body in BODIES:
        market_p3 = period_totals(data, body)
        market_p4 = period_totals(data, body, start="2025-08-01", end="2026-07-01")
        byd_p3 = period_totals(data, body, make="BYD")
        byd_p4 = period_totals(
            data, body, make="BYD", start="2025-08-01", end="2026-07-01"
        )

        share_p3 = byd_p3 / market_p3 * 100
        share_p4 = byd_p4 / market_p4 * 100
        benchmark = share_p3 / 100 * market_p4

        rows.append({
            "body": body,
            "market_p3": market_p3,
            "market_p4": market_p4,
            "byd_p3": byd_p3,
            "byd_p4": byd_p4,
            "market_growth_pct": (market_p4 / market_p3 - 1) * 100,
            "byd_growth_pct": (byd_p4 / byd_p3 - 1) * 100,
            "share_p3_pct": share_p3,
            "share_p4_pct": share_p4,
            "share_change_pp": share_p4 - share_p3,
            "benchmark": benchmark,
            "capture_gap_units": byd_p4 - benchmark,
        })
    return pd.DataFrame(rows)


def build_competitor_gap(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for body in ["SUV", "MPV"]:
        makes = sorted(data.loc[data["body"] == body, "make"].unique())
        body_rows = []
        for make in makes:
            p3 = period_totals(data, body, make=make)
            p4 = period_totals(
                data, body, make=make, start="2025-08-01", end="2026-07-01"
            )
            if p3 or p4:
                body_rows.append({"make": make, "registrations_p3": p3, "registrations_p4": p4})

        frame = pd.DataFrame(body_rows)
        market_p3 = frame["registrations_p3"].sum()
        market_p4 = frame["registrations_p4"].sum()
        frame["market_p3"] = market_p3
        frame["market_p4"] = market_p4
        frame["share_p3_pct"] = frame["registrations_p3"] / market_p3 * 100
        frame["share_p4_pct"] = frame["registrations_p4"] / market_p4 * 100
        frame["share_change_pp"] = frame["share_p4_pct"] - frame["share_p3_pct"]
        frame["benchmark"] = frame["share_p3_pct"] / 100 * market_p4
        frame["capture_gap_units"] = frame["registrations_p4"] - frame["benchmark"]
        frame["body"] = body
        rows.append(frame.reindex(columns=[
            "body", "make", "registrations_p3", "registrations_p4",
            "market_p3", "market_p4", "share_p3_pct", "share_p4_pct",
            "share_change_pp", "benchmark", "capture_gap_units",
        ]))

    return pd.concat(rows, ignore_index=True)


def build_monthly_performance(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for body in BODIES:
        body_data = data[data["body"] == body]
        monthly = (
            body_data.groupby(["month", "make"])["registrations"]
            .sum()
            .unstack(fill_value=0)
        )
        market = monthly.sum(axis=1)
        byd = monthly.get("BYD", pd.Series(0, index=monthly.index))
        share = byd / market * 100

        for current_month in pd.date_range("2025-08-01", "2026-07-01", freq="MS"):
            prior_month = current_month - pd.DateOffset(years=1)
            benchmark = share.loc[prior_month] / 100 * market.loc[current_month]
            rows.append({
                "body": body,
                "month": current_month,
                "share_p4": share.loc[current_month],
                "share_change_pp": share.loc[current_month] - share.loc[prior_month],
                "capture_gap_m": byd.loc[current_month] - benchmark,
            })
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# K-means validation
# ---------------------------------------------------------------------------
def kmeans_numpy(
    values: np.ndarray,
    k: int,
    seed: int = 99,
    n_init: int = 100,
    max_iter: int = 300,
 ) -> Tuple[float, np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    best = None

    for _ in range(n_init):
        centers = values[rng.choice(len(values), k, replace=False)].copy()
        for _ in range(max_iter):
            distances = ((values[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2)
            labels = distances.argmin(axis=1)
            new_centers = np.array([
                values[labels == cluster].mean(axis=0)
                if np.any(labels == cluster)
                else centers[cluster]
                for cluster in range(k)
            ])
            if np.allclose(new_centers, centers):
                break
            centers = new_centers

        inertia = ((values - centers[labels]) ** 2).sum()
        if best is None or inertia < best[0]:
            best = (inertia, labels.copy(), centers.copy())
    return best


def silhouette_numpy(values: np.ndarray, labels: np.ndarray) -> float:
    scores = np.zeros(len(values))
    for i in range(len(values)):
        same_cluster = np.where(labels == labels[i])[0]
        same_cluster = same_cluster[same_cluster != i]
        if len(same_cluster) == 0:
            scores[i] = 0
            continue

        a = np.linalg.norm(values[i] - values[same_cluster], axis=1).mean()
        b = np.inf
        for cluster in np.unique(labels):
            if cluster == labels[i]:
                continue
            other_cluster = np.where(labels == cluster)[0]
            b = min(b, np.linalg.norm(values[i] - values[other_cluster], axis=1).mean())
        scores[i] = (b - a) / max(a, b)
    return float(scores.mean())



def build_k_selection_table(
    standardized: np.ndarray, k_values: range = range(2, 6)
) -> pd.DataFrame:
    """Compare candidate K-means solutions using inertia and silhouette."""
    rows = []
    for k in k_values:
        inertia, labels, _ = kmeans_numpy(standardized, k=k)
        silhouette = silhouette_numpy(standardized, labels)
        sizes = np.bincount(labels, minlength=k)
        rows.append({
            "k": k,
            "inertia": round(float(inertia), 4),
            "silhouette": round(float(silhouette), 4),
            "cluster_sizes": " | ".join(str(int(size)) for size in sizes),
            "min_cluster_size": int(sizes.min()),
            "max_cluster_size": int(sizes.max()),
        })

    return pd.DataFrame(rows)

def build_kmeans_results(monthly: pd.DataFrame) -> Tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    features = ["share_p4", "share_change_pp"]
    values = monthly[features].to_numpy(dtype=float)
    standardized = (values - values.mean(axis=0)) / values.std(axis=0, ddof=0)

    _, labels, _ = kmeans_numpy(standardized, k=3)
    clustered = monthly.copy()
    clustered["cluster"] = labels

    profile = clustered.groupby("cluster").agg(
        months=("body", "size"),
        mean_share_p4=("share_p4", "mean"),
        mean_share_change_pp=("share_change_pp", "mean"),
        mean_capture_gap=("capture_gap_m", "mean"),
    )

    capture_id = profile["mean_share_change_pp"].idxmax()
    defence_id = profile.loc[
        profile["mean_share_change_pp"] < 0, "mean_share_p4"
    ].idxmax()
    under_id = next(
        cluster_id
        for cluster_id in profile.index
        if cluster_id not in {capture_id, defence_id}
    )

    cluster_names = {
        under_id: "Under-capture",
        capture_id: "Share capture",
        defence_id: "High-share defence",
    }
    clustered["cluster_name"] = clustered["cluster"].map(cluster_names)

    named_profile = clustered.groupby("cluster_name").agg(
        months=("body", "size"),
        mean_share_p4=("share_p4", "mean"),
        mean_share_change_pp=("share_change_pp", "mean"),
        mean_capture_gap=("capture_gap_m", "mean"),
    ).reset_index()

    body_mix = (
        pd.crosstab(clustered["body"], clustered["cluster_name"])
        .reset_index()
    )
    return clustered, named_profile, body_mix


# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------
def style_axis(ax) -> None:
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(axis="both", labelsize=10)


def sign_number(value: float) -> str:
    return f"{value:+,.0f}"


def save_figure(fig, filename: str) -> None:
    path = OUTPUT_DIR / filename
    fig.savefig(path, dpi=220, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"Saved: {path}")


def plot_capture_gap(scorecard: pd.DataFrame) -> None:
    plot_data = scorecard.set_index("body").reindex(BODIES).reset_index()
    colors = [
        PALETTE["secondary"] if value >= 0 else PALETTE["contrast2"]
        for value in plot_data["capture_gap_units"]
    ]

    fig, ax = plt.subplots(figsize=(9, 5.4))
    bars = ax.bar(
        plot_data["body"], plot_data["capture_gap_units"],
        color=colors, width=0.62,
        edgecolor=PALETTE["primary"], linewidth=0.7,
    )
    ax.axhline(0, color=PALETTE["contrast1"], linewidth=1.4)

    for bar, value in zip(bars, plot_data["capture_gap_units"]):
        offset = 14 if value >= 0 else -14
        vertical_alignment = "bottom" if value >= 0 else "top"
        ax.annotate(
            sign_number(value),
            (bar.get_x() + bar.get_width() / 2, value),
            xytext=(0, offset), textcoords="offset points",
            ha="center", va=vertical_alignment,
            fontsize=11, fontweight="bold", color=PALETTE["text"],
        )

    ax.set_ylabel("Capture Gap (units, P4)")
    ax.set_title(
        "Capture Gap by body type | P3 vs P4",
        loc="left", pad=14, fontsize=15, fontweight="bold",
    )
    ax.grid(axis="y")
    style_axis(ax)
    save_figure(fig, "Q3_fig2_P3P4_capture_gap.png")


def plot_competitor_gap(
    competitor_gap: pd.DataFrame,
    body: str,
    figure_number: int,
    max_bars: int,
) -> None:
    positive = (
        competitor_gap[
            (competitor_gap["body"] == body)
            & (competitor_gap["capture_gap_units"] > 0)
        ]
        .sort_values("capture_gap_units", ascending=False)
        .head(max_bars)
        .sort_values("capture_gap_units", ascending=True)
    )
    byd = competitor_gap[
        (competitor_gap["body"] == body)
        & (competitor_gap["make"] == "BYD")
    ].iloc[0]

    fig, ax = plt.subplots(figsize=(10, 6.6))
    bars = ax.barh(
        positive["make"], positive["capture_gap_units"],
        color=PALETTE["secondary"], height=0.62,
        edgecolor=PALETTE["primary"], linewidth=0.7,
    )
    ax.axvline(0, color=PALETTE["contrast1"], linewidth=1.3)

    max_value = positive["capture_gap_units"].max()
    for bar, (_, row) in zip(bars, positive.iterrows()):
        ax.text(
            row["capture_gap_units"] + max_value * 0.02,
            bar.get_y() + bar.get_height() / 2,
            f"+{row['capture_gap_units']:,.0f} units | {row['share_change_pp']:+.2f} pp",
            va="center", ha="left", fontsize=9.5, color=PALETTE["primary"],
        )

    ax.set_xlim(0, max_value * 1.42)
    ax.set_xlabel("Capture Gap vs own P3 benchmark (units)")
    ax.set_title(
        f"{body} competitors exceeding their own benchmark | P3 vs P4",
        loc="left", pad=14, fontsize=15, fontweight="bold",
    )
    ax.text(
        0.99, -0.18,
        f"BYD reference: {sign_number(byd['capture_gap_units'])} units | "
        f"{byd['share_change_pp']:+.2f} pp",
        transform=ax.transAxes, ha="right", va="top",
        fontsize=10.5, fontweight="bold", color=PALETTE["contrast2"],
    )
    ax.grid(axis="x")
    style_axis(ax)
    save_figure(fig, f"Q3_fig{figure_number}_P3P4_competitor_{body.lower()}.png")


def plot_kmeans(clustered: pd.DataFrame, silhouette: float) -> None:
    fig, ax = plt.subplots(figsize=(10, 6.4))

    for cluster_name, group in clustered.groupby("cluster_name"):
        color = CLUSTER_COLORS[cluster_name]
        for body, body_group in group.groupby("body"):
            ax.scatter(
                body_group["share_change_pp"],
                body_group["share_p4"],
                s=78,
                marker=BODY_MARKERS[body],
                color=color,
                edgecolor="white",
                linewidth=0.8,
                alpha=0.92,
                zorder=3,
            )

    ax.axvline(0, color=PALETTE["contrast1"], linestyle="--", linewidth=1.2)
    ax.axhline(0, color=PALETTE["neutral2"], linewidth=1.0, alpha=0.7)
    ax.axvline(65, color=PALETTE["contrast2"], linestyle="--", linewidth=1.2)

    for cluster_name, group in clustered.groupby("cluster_name"):
        center_x = group["share_change_pp"].mean()
        center_y = group["share_p4"].mean()
        ax.scatter(
            center_x, center_y, s=220, facecolors="none",
            edgecolors=CLUSTER_COLORS[cluster_name], linewidths=2.2, zorder=4,
        )
        ax.annotate(
            cluster_name, (center_x, center_y),
            xytext=(8, 9), textcoords="offset points",
            fontsize=10, fontweight="bold",
            color=CLUSTER_COLORS[cluster_name],
        )

    cluster_legend = [
        Patch(facecolor=CLUSTER_COLORS[name], label=name)
        for name in ["Under-capture", "Share capture", "High-share defence"]
    ]
    body_legend = [
        Line2D([0], [0], marker=marker, color="none", markerfacecolor=PALETTE["muted"],
               markeredgecolor="white", markersize=8, label=body)
        for body, marker in BODY_MARKERS.items()
    ]
    first_legend = ax.legend(
        handles=cluster_legend, title="Cluster", loc="upper left",
        frameon=False, fontsize=9,
    )
    ax.add_artist(first_legend)
    ax.legend(
        handles=body_legend, title="Segment", loc="lower right",
        frameon=False, fontsize=9,
    )

    ax.set_xlabel("P3-to-P4 share change (pp)")
    ax.set_ylabel("P4 BYD share (%)")
    ax.set_xlim(-35, 40)
    ax.set_ylim(15, 100)
    ax.set_title(
        f"K-means validation of monthly performance states | k = 3 | silhouette = {silhouette:.2f}",
        loc="left", pad=14, fontsize=15, fontweight="bold",
    )
    style_axis(ax)
    save_figure(fig, "Q3_fig5_P3P4_kmeans_validation.png")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    configure_style()
    data = load_bev_data()

    scorecard = build_byd_scorecard(data)
    competitor_gap = build_competitor_gap(data)
    monthly = build_monthly_performance(data)
    clustered, cluster_profile, cluster_body_mix = build_kmeans_results(monthly)

    features = ["share_p4", "share_change_pp"]
    standardized = (
        monthly[features].to_numpy(dtype=float)
        - monthly[features].to_numpy(dtype=float).mean(axis=0)
    ) / monthly[features].to_numpy(dtype=float).std(axis=0, ddof=0)
    _, labels, _ = kmeans_numpy(standardized, k=3)
    silhouette = silhouette_numpy(standardized, labels)
    k_selection = build_k_selection_table(standardized, k_values=range(2, 6))

    competitor_gap.to_csv(
        OUTPUT_DIR / "Q3_competitor_capture_gap_P3P4.csv",
        index=False, encoding="utf-8-sig",
    )
    clustered.to_csv(
        OUTPUT_DIR / "Q3_kmeans_monthly_P3P4.csv",
        index=False, encoding="utf-8-sig",
    )
    cluster_profile.to_csv(
        OUTPUT_DIR / "Q3_kmeans_profile_P3P4.csv",
        index=False, encoding="utf-8-sig",
    )
    cluster_body_mix.to_csv(
        OUTPUT_DIR / "Q3_kmeans_body_mix_P3P4.csv",
        index=False, encoding="utf-8-sig",
    )
    k_selection.to_csv(
        OUTPUT_DIR / "Q3_kmeans_k_selection_P3P4.csv",
        index=False, encoding="utf-8-sig",
    )

    plot_capture_gap(scorecard)
    plot_competitor_gap(competitor_gap, "SUV", figure_number=3, max_bars=8)
    plot_competitor_gap(competitor_gap, "MPV", figure_number=4, max_bars=8)
    plot_kmeans(clustered, silhouette)

    print("\nQ3 scorecard")
    print(scorecard.round(2).to_string(index=False))
    print("\nK-means profile")
    print(cluster_profile.round(2).to_string(index=False))
    print("\nK-means k selection diagnostics")
    print(k_selection.to_string(index=False))
    print(f"\nSilhouette score (k=3): {silhouette:.3f}")


if __name__ == "__main__":
    try:
        main()
    except ImportError as exc:
        raise SystemExit(
            "Missing Python package. Install with: pip install pandas numpy matplotlib"
        ) from exc
