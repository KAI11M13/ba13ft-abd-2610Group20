"""Reproduce Group20 (3).docx COE analyses from Clean-2.zip source CSVs.

Includes 8 market-level regressions, 24 BYD share regressions, plots, and
original-report reference checks. No additional models are mixed into this script.
"""
from pathlib import Path
import argparse
import numpy as np
import pandas as pd
import statsmodels.api as sm
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
SEGMENTS = ('SUV', 'Sedan', 'MPV')
VAR_NAMES = ('Category A premium', 'Category B premium', 'Category A quota', 'Category B quota')


def build_data(data_dir: Path):
    r = pd.read_csv(data_dir / 'registration_fact.csv')
    c = pd.read_csv(data_dir / 'coe_clean.csv')
    required_r = {'month', 'make', 'fuel_type', 'body', 'registrations'}
    required_c = {'month', 'bidding_no', 'vehicle_class', 'quota', 'premium'}
    assert required_r.issubset(r.columns), 'registration_fact.csv missing required columns'
    assert required_c.issubset(c.columns), 'coe_clean.csv missing required columns'
    r['month'] = r['month'].astype(str).str[:7]
    c['month'] = c['month'].astype(str).str[:7]
    c = c[c['vehicle_class'].isin(['Category A', 'Category B'])].copy()
    # Quotas: sum the two bidding exercises; premiums: arithmetic mean.
    monthly = c.groupby(['month', 'vehicle_class']).agg(quota=('quota', 'sum'), premium=('premium', 'mean')).unstack()
    monthly.columns = [f'{measure}_{category[-1]}' for measure, category in monthly.columns]
    bev = r[r['fuel_type'] == 'Electric'].copy()
    # Original Group20 COE market table is reproduced using ALL body types,
    # despite the main project being scoped to SUV/Sedan/MPV. Explicitly disclose.
    all_market = bev.groupby('month')['registrations'].sum().rename('bev_market_all_body_types')
    scoped = bev[bev['body'].isin(SEGMENTS)]
    scoped_market = scoped.groupby('month')['registrations'].sum().rename('bev_market_three_segments')
    data = monthly.join(all_market).join(scoped_market).loc['2022-07':'2026-07'].sort_index()
    assert len(data) == 49, f'Expected 49 months, found {len(data)}'
    data['market_growth_all_pct'] = data['bev_market_all_body_types'].pct_change() * 100
    data['market_growth_three_pct'] = data['bev_market_three_segments'].pct_change() * 100
    for measure in ['premium_A', 'premium_B', 'quota_A', 'quota_B']:
        col = 'change_' + measure
        data[col] = data[measure].pct_change() * 100
        data['lag1_' + col] = data[col].shift(1)
    for segment in SEGMENTS:
        s = scoped[scoped['body'] == segment]
        denominator = s.groupby('month')['registrations'].sum()
        numerator = s[s['make'] == 'BYD'].groupby('month')['registrations'].sum()
        share = 100 * numerator.reindex(denominator.index, fill_value=0) / denominator
        data[f'byd_{segment.lower()}_share_pct'] = share
        # Absolute percentage-point change, NOT relative percent change.
        data[f'byd_{segment.lower()}_share_change_pp'] = share.diff()
    return data


def fit_pair(data, ycol, xcol):
    sub = data[[ycol, xcol]].dropna()
    result = sm.OLS(sub[ycol], sm.add_constant(sub[[xcol]])).fit()
    return {'n':len(sub), 'pearson_r':float(sub[ycol].corr(sub[xcol])),
            'ols_intercept':float(result.params['const']), 'ols_beta':float(result.params[xcol]),
            'ols_p_value':float(result.pvalues[xcol]), 'r_squared':float(result.rsquared),
            'significant_5pct':bool(result.pvalues[xcol] < .05)}


def run_tables(data):
    predictors = [('Category A premium', 'change_premium_A'),
                  ('Category B premium', 'change_premium_B'),
                  ('Category A quota', 'change_quota_A'),
                  ('Category B quota', 'change_quota_B')]
    market_rows, share_rows = [], []
    for name, predictor in predictors:
        for timing, col in [('Same month', predictor), ('Lag 1', 'lag1_' + predictor)]:
            market_rows.append({'coe_variable':name, 'timing':timing, **fit_pair(data,'market_growth_all_pct',col)})
            for seg in SEGMENTS:
                share_rows.append({'segment':seg, 'coe_variable':name, 'timing':timing,
                                   **fit_pair(data,f'byd_{seg.lower()}_share_change_pp',col)})
    # Sort share rows in original appendix order: SUV, Sedan, MPV.
    market = pd.DataFrame(market_rows)
    share = pd.DataFrame(share_rows).sort_values(['segment','coe_variable','timing'],key=lambda s:s.map({'SUV':0,'Sedan':1,'MPV':2}) if s.name=='segment' else s,kind='stable')
    return market, share


def create_figures(data, figures):
    figures.mkdir(parents=True,exist_ok=True)
    plt.rcParams.update({'font.size':10,'axes.spines.top':False,'axes.spines.right':False})
    d = data[['change_quota_B','market_growth_all_pct']].dropna()
    r = d.corr().iloc[0,1]
    p = fit_pair(data,'market_growth_all_pct','change_quota_B')['ols_p_value']
    slope, intercept = np.polyfit(d['change_quota_B'],d['market_growth_all_pct'],1)
    xx = np.linspace(d['change_quota_B'].min(),d['change_quota_B'].max(),100)
    fig, ax = plt.subplots(figsize=(9,5.3))
    ax.scatter(d['change_quota_B'],d['market_growth_all_pct'],color='#59B9B3',alpha=.8)
    ax.plot(xx,intercept+slope*xx,color='#146F6A',linestyle='--',linewidth=2)
    ax.axhline(0,color='#aaa',lw=.8);ax.axvline(0,color='#aaa',lw=.8)
    ax.set(title='Category B quota and BEV registration performance',xlabel='Category B quota month-on-month change (%)',ylabel='BEV market month-on-month change (%)')
    ax.text(.97,.95,f'r = {r:.3f}\np = {p:.3f}',ha='right',va='top',transform=ax.transAxes,fontweight='bold')
    fig.tight_layout();fig.savefig(figures/'category_b_quota_vs_bev_market.png',dpi=200);plt.close(fig)
    fig, ax = plt.subplots(figsize=(10,5))
    for segment, color in [('SUV','#146F6A'),('Sedan','#58B9B4'),('MPV','#A48D72')]:
        ax.plot(pd.to_datetime(data.index),data[f'byd_{segment.lower()}_share_pct'],label=segment,color=color,lw=1.7)
    ax.set(title='BYD segment share across SUV, Sedan and MPV',ylabel='BYD segment share (%)',ylim=(0,105))
    ax.legend(frameon=False,ncol=3);fig.autofmt_xdate();fig.tight_layout()
    fig.savefig(figures/'byd_segment_share_trend.png',dpi=200);plt.close(fig)


def validate(market,share,strict=True):
    m=market[(market.coe_variable=='Category B quota')&(market.timing=='Same month')].iloc[0]
    s=share[(share.segment=='Sedan')&(share.coe_variable=='Category B quota')&(share.timing=='Lag 1')].iloc[0]
    checks={'market_category_b_r':abs(m.pearson_r-.288)<.001,
            'market_category_b_p':abs(m.ols_p_value-.047)<.001,
            'market_category_b_beta':abs(m.ols_beta-1.161)<.002,
            'market_category_b_R2':abs(m.r_squared-.083)<.002,
            'sedan_lag1_r':abs(s.pearson_r-(-.271))<.001,
            'sedan_lag1_p':abs(s.ols_p_value-.065)<.001,
            'market_eight_tests':len(market)==8,
            'share_24_tests':len(share)==24,
            'share_none_significant':int(share.significant_5pct.sum())==0}
    if strict: assert all(checks.values()),f'Original-report reproduction check failed: {checks}'
    return checks


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--data-dir',type=Path,default=ROOT/'data')
    parser.add_argument('--output-dir',type=Path,default=ROOT/'outputs')
    parser.add_argument('--figures-dir',type=Path,default=ROOT/'figures')
    args=parser.parse_args()
    args.output_dir.mkdir(parents=True,exist_ok=True)
    data=build_data(args.data_dir)
    market,share=run_tables(data)
    market.to_csv(args.output_dir/'table_6_2_market_coe_tests.csv',index=False,float_format='%.8f')
    share.to_csv(args.output_dir/'table_A_7_byd_segment_share_tests.csv',index=False,float_format='%.8f')
    data.to_csv(args.output_dir/'coe_analysis_monthly_dataset.csv',float_format='%.8f',index_label='month')
    create_figures(data,args.figures_dir)
    checks=validate(market,share)
    (args.output_dir/'validation_checks.txt').write_text('\n'.join(f'{k}: {"PASS" if v else "FAIL"}' for k,v in checks.items())+'\n')
    print('Original report replication checks:',checks)
    print('\nMarket-level tests:\n',market[['coe_variable','timing','n','pearson_r','ols_beta','ols_p_value','r_squared']].round(3).to_string(index=False))
    print('\nBYD share: statistically significant tests =',int(share.significant_5pct.sum()),'out of',len(share))
    print('Outputs:',args.output_dir,'Figures:',args.figures_dir)

if __name__=='__main__':main()
