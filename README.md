# BA13FT ABD 2610 · Group 20 — 新加坡电动车 (EV SG) 市场分析

ABD Practice Module 小组项目仓库。本仓库目前收录**清洗后的分析数据**及对应的清洗脚本，覆盖新加坡乘用车注册、COE 拥车证、车辆保有量和公共充电桩四类公开数据，用于研究新加坡纯电 (BEV) 市场。

## 目录结构

```
.
├── README.md
└── cleaned_data/
    ├── 01_clean_data.ipynb     # 清洗脚本(原始数据 -> 下列 CSV)
    ├── registration_fact.csv   # 月度注册事实表(分析主干)
    ├── coe_clean.csv           # COE 投标结果
    ├── fleet_clean.csv         # 按燃料类型的车辆保有量
    ├── mvp02_clean.csv         # 年度新车注册(品牌 x 燃料 x 车身)
    ├── mvp01_clean.csv         # 年度注册(按品牌)
    ├── chargers_clean.csv      # 公共充电桩登记
    ├── cleaning_log.csv        # 清洗检查项与结果
    └── 数据字典.csv             # 各表字段定义
```

## 数据表一览

| 文件 | 原始数据 | 粒度 | 时间范围 | 行数 |
|---|---|---|---|---|
| `registration_fact.csv` | M03-Car_Regn_by_make | 月 × 品牌 × 燃料 × 车身 | 2022-07 ~ 2026-07 | 26,898 |
| `coe_clean.csv` | COEBiddingResultsPrices | 月 × 投标轮次 × COE 类别 | 2010-01 ~ 2026-09 | 1,975 |
| `fleet_clean.csv` | M09-Vehs_by_Fuel_Type | 月 × 车辆类别 × 燃料 | 2016-01 ~ 2026-07 | 3,611 |
| `mvp02_clean.csv` | MVP02-2_New_Cars_by_make_type | 年 × 品牌 × 进口商 × 燃料 × 车身 | 2015 ~ 2025 | 6,896 |
| `mvp01_clean.csv` | MVP01-6_Cars_by_make | 年 × 品牌 × 燃料 | 2005 ~ 2025 | 2,198 |
| `chargers_clean.csv` | Electric_Vehicle_Charging_Points_Jun 2026 | 单个充电桩 | 登记日期 2024-01 ~ 2026-12 | 11,353 (16,935 个充电点) |

各字段含义见 [`cleaned_data/数据字典.csv`](cleaned_data/数据字典.csv)。

## 主要清洗规则

- **M03 月度注册(分析主干)**
  - 研究窗口从 **2022-07** 开始(LTA 车身分类于该月变更)，至 2026-07。
  - 空白注册量按 0 处理；检查非法数量、重复记录、关键字段缺失(均为 0)。
  - 车身类别标准化为 SUV / Sedan / MPV / Hatchback / Station Wagon / Coupe-Convertible。
  - 进口商类别 (AMD / PI) 加总后汇总到 月 × 品牌 × 燃料 × 车身；汇总前后总量一致 (172,394 辆)。
  - `fuel_type = Electric` 即纯电 BEV。
- **COE**：去除 `bids_success`、`bids_received` 中的千分位逗号并转为数值。
- **M09 保有量**：占位符 `-` 按 0 处理。
- **充电桩**：列名标准化、日期与经纬度数值化、按 `cp_id` 去重。

完整检查项及结果见 [`cleaned_data/cleaning_log.csv`](cleaned_data/cleaning_log.csv)。

## 使用方法

```python
import pandas as pd

reg = pd.read_csv("cleaned_data/registration_fact.csv", encoding="utf-8-sig")
bev = reg[reg["fuel_type"] == "Electric"]
monthly_bev = bev.groupby("month")["registrations"].sum()
```

> CSV 文件均为 UTF-8 (带 BOM) 编码，可直接用 Excel 打开。

重新生成清洗数据：将原始 CSV 放在 notebook 同一目录下，运行 `cleaned_data/01_clean_data.ipynb`(依赖 `pandas`)。

## 数据来源

新加坡陆路交通管理局 (LTA) DataMall / data.gov.sg 公开数据集。
