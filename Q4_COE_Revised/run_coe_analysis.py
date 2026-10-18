#!/usr/bin/env python3
"""Reproduce the original all-body BEV COE analysis and add matched-sample diagnostics.

Inputs are the supplied cleaned snapshot. No network, MySQL, source-file mutation,
model selection by p-value, or forecasting validation is performed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import platform
import numpy as np
import pandas as pd
import scipy
from scipy.stats import pearsonr, linregress
import statsmodels
import statsmodels.api as sm
from statsmodels.stats.diagnostic import acorr_ljungbox, het_breuschpagan
from statsmodels.stats.stattools import durbin_watson
from statsmodels.stats.outliers_influence import variance_inflation_factor
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

START, END = '2022-07-01', '2026-07-01'
SEGMENTS = ['SUV', 'Sedan', 'MPV']
COMMIT = 'dcda40a6899000e253ac588ed3719a496336795f'
VARIABLES = ['a_premium', 'b_premium', 'a_quota', 'b_quota']
TEAL, PALE, TAN = '#176F70', '#47B4B0', '#AA9371'
plt.rcParams.update({'font.family':'DejaVu Sans', 'font.size':10,
    'axes.titlesize':12, 'axes.spines.top':False, 'axes.spines.right':False,
    'figure.facecolor':'white', 'axes.facecolor':'white', 'savefig.facecolor':'white'})

def write_csv(frame, path):
    frame.to_csv(path, index=False, encoding='utf-8-sig', float_format='%.12g')

def ols(y, x):
    return sm.OLS(y, sm.add_constant(x, has_constant='add')).fit()

def save_chart(fig, name, folder):
    for suffix in ['.png', '.svg']:
        fig.savefig(folder / (name+suffix), dpi=300, bbox_inches='tight')
    plt.close(fig)

def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=here/'inputs')
    parser.add_argument('--output-dir', type=Path, default=here/'results')
    args = parser.parse_args()
    out = args.output_dir
    tables, figures = out/'tables', out/'figures'
    tables.mkdir(parents=True, exist_ok=True)
    figures.mkdir(parents=True, exist_ok=True)
    raw = pd.read_csv(args.data_dir/'registration_fact.csv', parse_dates=['month'])
    coe = pd.read_csv(args.data_dir/'coe_clean.csv', parse_dates=['month'])
    assert not raw.duplicated(['month','make','fuel_type','body']).any()
    assert raw.registrations.notna().all() and raw.registrations.ge(0).all()
    raw = raw.loc[raw.month.between(START, END)].copy()
    electric = raw.loc[raw.fuel_type.eq('Electric')].copy()
    all_body = electric.groupby('month').registrations.sum()
    assert all_body.index.equals(pd.date_range(START, END, freq='MS'))
    assert all_body.gt(0).all()
    segment = electric.loc[electric.body.isin(SEGMENTS)]
    market = segment.groupby(['month','body']).registrations.sum().unstack().reindex(columns=SEGMENTS)
    byd = (segment.loc[segment.make.str.upper().eq('BYD')]
           .groupby(['month','body']).registrations.sum().unstack()
           .reindex(index=market.index, columns=SEGMENTS).fillna(0))
    assert market.gt(0).all().all() and byd.le(market).all().all()
    shares = 100*byd/market
    cc = coe.loc[coe.month.between(START, END) & coe.vehicle_class.isin(['Category A','Category B'])].copy()
    assert not cc.duplicated(['month','vehicle_class','bidding_no']).any()
    g = cc.groupby(['month','vehicle_class']).agg(premium=('premium','mean'),
        quota=('quota','sum'), n_exercises=('bidding_no','nunique'))
    assert len(cc)==196 and len(g)==98 and g.n_exercises.eq(2).all()
    levels = g[['premium','quota']].unstack('vehicle_class')
    levels.columns = [('a_' if cat=='Category A' else 'b_')+v for v,cat in levels.columns]
    monthly = levels.copy()
    monthly['market_bev_all_body'] = all_body
    for col in VARIABLES+['market_bev_all_body']:
        monthly[col+'_mom_pct'] = 100*monthly[col].pct_change(fill_method=None)
    for seg in SEGMENTS:
        monthly[seg+'_byd_share_pct'] = shares[seg]
        monthly[seg+'_share_change_pp'] = shares[seg].diff()
    monthly.index.name = 'month'
    write_csv(monthly.reset_index(), tables/'coe_monthly_inputs.csv')
    write_csv(electric.groupby('body',as_index=False).registrations.sum(), tables/'coe_body_type_coverage.csv')

    rows = []
    for variable in VARIABLES:
        for lag in [0,1]:
            z = pd.concat([monthly.market_bev_all_body_mom_pct.rename('y'),
                monthly[variable+'_mom_pct'].shift(lag).rename('x')], axis=1).dropna()
            model = ols(z.y, z[['x']])
            r, p = pearsonr(z.x, z.y)
            # Independent implementations check the consequential published results.
            independent = linregress(z.x, z.y)
            assert np.isclose(independent.slope, model.params.x)
            assert np.isclose(independent.rvalue, r)
            assert np.isclose(p, model.pvalues.x)
            assert np.isclose(r*r, model.rsquared)
            low, high = model.conf_int().loc['x']
            rows.append(dict(variable=variable,timing='same month' if lag==0 else 'lag 1',
                n=len(z),pearson_r=r,beta=model.params.x,p_value=p,r_squared=model.rsquared,
                ci_low=low,ci_high=high,p_bonferroni_8=min(1,8*p)))
    tests = pd.DataFrame(rows)
    original_r = [-.038,-.180,-.207,-.164,.097,.145,.288,.219]
    original_beta = [-.158,-.745,-.803,-.634,.411,.615,1.161,.883]
    original_p = [.798,.227,.158,.271,.514,.331,.047,.139]
    assert np.array_equal(np.round(tests.pearson_r,3), original_r)
    assert np.array_equal(np.round(tests.beta,3), original_beta)
    assert np.array_equal(np.round(tests.p_value,3), original_p)
    write_csv(tests, tables/'coe_table_6_2_original_method.csv')
    share_tests = []
    for seg in SEGMENTS:
        for variable in VARIABLES:
            for lag in [0,1]:
                z = pd.concat([monthly[seg+'_share_change_pp'].rename('y'),
                    monthly[variable+'_mom_pct'].shift(lag).rename('x')],axis=1).dropna()
                r,p = pearsonr(z.x,z.y)
                share_tests.append(dict(segment=seg,variable=variable,
                    timing='same month' if lag==0 else 'lag 1',n=len(z),pearson_r=r,p_value=p))
    st = pd.DataFrame(share_tests)
    assert len(st)==24 and st.p_value.min()>.05
    write_csv(st,tables/'coe_segment_share_tests.csv')

    z = pd.concat([monthly.market_bev_all_body_mom_pct.rename('y'),
        monthly.b_quota_mom_pct.rename('x')],axis=1).dropna()
    assert len(z)==48
    dummies = pd.get_dummies(z.index.month,drop_first=True,dtype=float)
    dummies.index = z.index
    dummies.columns = ['calendar_month_'+str(v) for v in dummies]
    x1 = pd.concat([z[['x']],dummies],axis=1)
    x2 = x1.copy(); x2['x_squared'] = z.x**2
    specifications = {'M0 quota only':z[['x']], 'S0 calendar only':dummies,
        'M1 calendar plus quota':x1, 'M2 M1 plus quota squared':x2}
    fits = {name:ols(z.y,x) for name,x in specifications.items()}
    comp, diag = [], []
    for name, f in fits.items():
        low, high = f.conf_int().loc['x'] if 'x' in f.params else [np.nan,np.nan]
        comp.append(dict(model=name,n=int(f.nobs),parameters=len(f.params),r_squared=f.rsquared,
            adjusted_r_squared=f.rsquared_adj,rmse_in_sample=float(np.sqrt(np.mean(f.resid**2))),aic=f.aic,
            beta_quota=f.params.get('x',np.nan),p_quota=f.pvalues.get('x',np.nan),
            quota_ci_low=low,quota_ci_high=high,beta_squared=f.params.get('x_squared',np.nan),
            p_squared=f.pvalues.get('x_squared',np.nan)))
        diag.append(dict(model=name,durbin_watson=durbin_watson(f.resid),
            ljung_box_lag1_p=acorr_ljungbox(f.resid,lags=[1],return_df=True).iloc[0].lb_pvalue,
            breusch_pagan_p=het_breuschpagan(f.resid,f.model.exog)[1]))
    comparison = pd.DataFrame(comp)
    diagnostics = pd.DataFrame(diag)
    write_csv(comparison,tables/'coe_table_6_3_models.csv')
    write_csv(diagnostics,tables/'coe_residual_diagnostics.csv')
    nested = []
    for full, reduced in [('M1 calendar plus quota','S0 calendar only'),
                          ('M2 M1 plus quota squared','M1 calendar plus quota')]:
        fval,pval,dfdiff = fits[full].compare_f_test(fits[reduced])
        nested.append(dict(full_model=full,reduced_model=reduced,nominal_f=fval,
            nominal_p=pval,df_added=dfdiff))
    write_csv(pd.DataFrame(nested),tables/'coe_nested_comparisons.csv')
    f = fits['M0 quota only']
    inf = f.get_influence()
    influence = z.copy()
    influence['fitted']=f.fittedvalues; influence['residual']=f.resid
    influence['leverage']=inf.hat_matrix_diag; influence['cooks_distance']=inf.cooks_distance[0]
    influence['screen_cooks_4_over_n'] = influence.cooks_distance>4/len(z)
    write_csv(influence.reset_index(),tables/'coe_influence.csv')
    loo=[]
    for month in z.index:
        keep=z.index!=month
        ff=ols(z.y.loc[keep],z.loc[keep,['x']])
        loo.append(dict(omitted_month=month.strftime('%Y-%m'),n=int(ff.nobs),
            beta=ff.params.x,p_value=ff.pvalues.x,r_squared=ff.rsquared))
    leave=pd.DataFrame(loo)
    write_csv(leave,tables/'coe_leave_one_month_out.csv')
    xv=sm.add_constant(monthly[[v+'_mom_pct' for v in VARIABLES]].dropna())
    vifs=[dict(specification='Four COE variables together',variable=c,vif=variance_inflation_factor(xv.values,j))
        for j,c in enumerate(xv.columns) if c!='const']
    xcal=sm.add_constant(x1)
    vifs.append(dict(specification='M1 calendar plus quota',variable='b_quota_mom_pct',
        vif=variance_inflation_factor(xcal.values,list(xcal.columns).index('x'))))
    write_csv(pd.DataFrame(vifs),tables/'coe_vif_context.csv')

    xx=np.linspace(z.x.min(),z.x.max(),200)
    lowess=sm.nonparametric.lowess(z.y,z.x,frac=.65,return_sorted=True)
    fig,ax=plt.subplots(figsize=(7.5,4.7),layout='constrained')
    ax.scatter(z.x,z.y,s=33,color=PALE,edgecolors='white',linewidth=.35)
    ax.plot(xx,f.params['const']+f.params.x*xx,color=TEAL,lw=1.7,label='Simple OLS')
    ax.plot(lowess[:,0],lowess[:,1],color=TAN,lw=1.6,label='LOWESS, descriptive')
    ax.text(.98,.97,f'N = 48\nr = {tests.iloc[6].pearson_r:.3f}\nR² = {f.rsquared:.3f}\nnominal p = {f.pvalues.x:.3f}',
        transform=ax.transAxes,ha='right',va='top')
    ax.axhline(0,color='#aaaaaa',lw=.7)
    ax.set(xlabel='Category B quota MoM change (%)',ylabel='All-body BEV registration MoM growth (%)',
        title='Category B quota and all-body BEV growth')
    ax.legend(loc='lower right',frameon=False,fontsize=9);ax.grid(alpha=.15)
    save_chart(fig,'coe_scatter_original_method',figures)

    fig,axes=plt.subplots(2,2,figsize=(10.2,7.4),layout='constrained')
    ax=axes[0,0];ax.scatter(z.x,z.y,s=27,color=PALE)
    ax.plot(xx,f.params['const']+f.params.x*xx,c=TEAL,label='Simple OLS')
    ax.plot(lowess[:,0],lowess[:,1],c=TAN,label='LOWESS, descriptive')
    ax.set(xlabel='Category B quota MoM change (%)',ylabel='All-body BEV MoM growth (%)',title='Observed relationship')
    ax.legend(fontsize=8,frameon=False)
    ax=axes[0,1];ax.scatter(f.fittedvalues,f.resid,s=25,c=TEAL);ax.axhline(0,c='#777777',lw=.8)
    ax.set(xlabel='Fitted BEV growth (%)',ylabel='Residual (percentage points)',title='Residuals against fitted values')
    ax=axes[1,0];ax.plot(z.index,f.resid,'o-',c=TEAL,ms=3,lw=.9);ax.axhline(0,c='#777777',lw=.8)
    ax.set(xlabel='Month',ylabel='Residual (percentage points)',title='Residuals over time')
    ax.set_xticks(z.index[[0,12,24,36,47]]);ax.xaxis.set_major_formatter(mdates.DateFormatter('%b %Y'))
    ax.tick_params(axis='x',labelrotation=20,labelsize=8)
    ax=axes[1,1];ax.vlines(np.arange(len(z)),0,influence.cooks_distance,color=TEAL,lw=1.2)
    ax.axhline(4/len(z),color=TAN,ls='--',label='Screening reference 4/N')
    for month in influence.nlargest(2,'cooks_distance').index:
        j=z.index.get_loc(month)
        ax.annotate(month.strftime('%b %Y'),(j,influence.loc[month,'cooks_distance']),
            xytext=(2,4),textcoords='offset points',fontsize=8,ha='left')
    ax.set_xticks([0,12,24,36,47],[d.strftime('%b %Y') for d in z.index[[0,12,24,36,47]]])
    ax.tick_params(axis='x',labelrotation=20,labelsize=8)
    ax.set(xlabel='Observation month',ylabel="Cook's distance",title='Influence screening');ax.legend(fontsize=8,frameon=False)
    for ax in axes.flat:ax.grid(alpha=.12)
    save_chart(fig,'coe_diagnostics_original_method',figures)

    fig,axes=plt.subplots(1,2,figsize=(9.8,4.0),layout='constrained')
    names=['M0\nQuota only','S0\nCalendar\nmonths','M1\nMonths +\nquota','M2\nM1 +\nquota squared']
    axes[0].bar(names,comparison.adjusted_r_squared,color=[TAN,'#C6D8D6',TEAL,PALE])
    for j,v in enumerate(comparison.adjusted_r_squared):axes[0].text(j,v+.013,f'{v:.3f}',ha='center',fontsize=9)
    axes[0].set(ylabel='Adjusted R²',ylim=(0,.65),title='In-sample explanatory fit')
    axes[0].tick_params(axis='x',labelsize=9)
    sub=comparison.iloc[[0,2]];betas=sub.beta_quota.to_numpy()
    axes[1].errorbar(betas,[1,0],xerr=np.array([betas-sub.quota_ci_low.to_numpy(),sub.quota_ci_high.to_numpy()-betas]),
        fmt='o',color=TEAL,capsize=5)
    axes[1].axvline(0,c='#777777',ls='--',lw=.9)
    axes[1].set(yticks=[1,0],yticklabels=['M0 quota','M1 months + quota'],ylim=(-.7,1.7),
        xlabel='Quota coefficient with nominal 95% OLS CI',title='Quota association with calendar controls')
    for ax in axes:ax.grid(alpha=.15)
    save_chart(fig,'coe_model_comparison_original_method',figures)
    summary=dict(source_repository='https://github.com/KAI11M13/ba13ft-abd-2610Group20',commit=COMMIT,
        market_scope='All body types with fuel_type = Electric',segment_scope=SEGMENTS,
        study_start=START,study_end=END,monthly_rows=len(monthly),same_month_n=48,lag_1_n=47,
        coe_exercise_rows=len(cc),original_table_6_2_reproduced_to_3_decimals=True,
        original_model=dict(r=float(tests.iloc[6].pearson_r),beta=float(f.params.x),p=float(f.pvalues.x),
            r_squared=float(f.rsquared),adjusted_r_squared=float(f.rsquared_adj),
            ci=f.conf_int().loc['x'].tolist(),p_bonferroni_8=float(tests.iloc[6].p_bonferroni_8)),
        maximum_cooks_distance_month=influence.cooks_distance.idxmax().strftime('%Y-%m'),
        maximum_cooks_distance=float(influence.cooks_distance.max()),
        leave_one_month_out=dict(beta_min=float(leave.beta.min()),beta_max=float(leave.beta.max()),
            p_min=float(leave.p_value.min()),p_max=float(leave.p_value.max()),
            nominal_significant_refits=int(leave.p_value.lt(.05).sum()),total_refits=len(leave)),
        versions=dict(python=platform.python_version(),numpy=np.__version__,pandas=pd.__version__,
            scipy=scipy.__version__,statsmodels=statsmodels.__version__,matplotlib=matplotlib.__version__),
        input_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [args.data_dir/'registration_fact.csv',args.data_dir/'coe_clean.csv']})
    (out/'analysis_metadata.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(json.dumps(summary,indent=2))
    print(comparison.to_string(index=False))
    print(diagnostics.to_string(index=False))
    print(pd.DataFrame(vifs).to_string(index=False))

if __name__=='__main__':
    main()
