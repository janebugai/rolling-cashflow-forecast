# Reporting tier

Transformed data is aggregated into metrics and tables designed for dashboards, analysis, and decision-making.

These files are the foundation for the Forecast tab and for other tools (BI tools and dashboards such as Tableau, Power BI, and Sigma, and LLM applications). Amounts are signed USD (inflows positive, outflows negative). Dates are month starts (`YYYY-MM-01`).

Rebuild with `python scripts/run_sql.py`. `scripts/sql/build_monthly_report.sql` reads `cash_transactions.csv` and `forecast_transactions.csv`. It does not re-map raw extracts. A month is `Forecast` when it falls after the nine actual months in `data/forecast/forecast_9_plus_3.csv`.

| File | What is kept | Used for |
| --- | --- | --- |
| `monthly_cash_flow_lines.csv` | Signed amount by month and reporting line | Statement lines and drilldown keys |
| `monthly_cash_summary.csv` | Section nets, beginning and ending cash | Chart totals and cash roll-forward |

The dashboard fetches these two files, then drills into `data/transformed/cash_transactions.csv` and `forecast_transactions.csv` by `reporting_month` and `reporting_line`.

## `monthly_cash_flow_lines.csv`

One row per reporting line per month. Months with no activity still appear with `0`.

| Column | Meaning |
| --- | --- |
| reporting_month | First day of the month |
| cash_flow_section | `Operating`, `Investing`, or `Financing` |
| business_activity | Mapped business process |
| reporting_line | Line on the management cash flow view |
| signed_amount_usd | Sum of actual and forecast events for that line and month |
| display_order | Statement order (1–6) |
| amount_type | `Actual` or `Forecast` |

| display_order | cash_flow_section | reporting_line |
| --- | --- | --- |
| 1 | Operating | Mining cash received |
| 2 | Operating | Mining power paid |
| 3 | Operating | Overhead paid |
| 4 | Investing | Data center buildout paid |
| 5 | Investing | Mining equipment paid |
| 6 | Financing | Construction loan drawn |

## `monthly_cash_summary.csv`

One row per month. Beginning cash in January is the opening bank snapshot. Later months roll forward from the prior ending cash.

| Column | Meaning |
| --- | --- |
| reporting_month | First day of the month |
| amount_type | `Actual` for January–September, `Forecast` for October–December |
| mining_cash_received | Operating inflow |
| mining_power_paid | Operating outflow |
| overhead_paid | Operating outflow |
| net_operating_cash_flow | Sum of the three operating lines |
| data_center_buildout_paid | Investing outflow |
| mining_equipment_paid | Investing outflow |
| net_investing_cash_flow | Sum of the two investing lines |
| construction_loan_drawn | Financing inflow |
| net_financing_cash_flow | Financing total |
| net_change_in_cash | Operating + investing + financing |
| beginning_cash | Opening cash for the month |
| ending_cash | Beginning cash + net change |
