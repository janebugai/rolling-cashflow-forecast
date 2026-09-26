# Reporting tier

Transformed data is aggregated into metrics and tables designed for dashboards, analysis, and decision-making.

These files are the foundation for the Forecast tab and for other tools (BI tools and dashboards such as Tableau, Power BI, and Sigma, and LLM applications). Amounts are signed USD (inflows positive, outflows negative). Dates are month starts (`YYYY-MM-01`).

Actuals and forecast stay in this folder as separate files.

Rebuild with `python scripts/run_sql.py`. `scripts/sql/build_monthly_report.sql` reads `cash_transactions.csv` and `forecast_transactions.csv`. It does not re-map raw extracts. `forecast_scenario.csv` marks January–September 2026 as actual and October 2026–September 2027 as forecast.

| File | What is kept | Used for |
| --- | --- | --- |
| `actual_cash_flow_lines.csv` | Signed amount by actual month and reporting line | Statement lines and drilldown keys |
| `actual_cash_summary.csv` | Actual section nets, beginning and ending cash | Chart totals and cash roll-forward |
| `forecast_cash_flow_lines.csv` | Signed amount by forecast month and reporting line | Statement lines and drilldown keys |
| `forecast_cash_summary.csv` | Forecast section nets, beginning and ending cash | Chart totals and cash roll-forward |
| `forecast_scenario.csv` | How many months are actual versus forecast | One scenario row, edited here |
| `plan_schedule.csv` | Optional replacement amounts for a forecast line and month | Edited here; not rebuilt by SQL |

The dashboard reads the actual and forecast summary and line files, then drills into `data/transformed/cash_transactions.csv` and `forecast_transactions.csv` by `reporting_month` and `reporting_line`.

`forecast_scenario.csv` and `plan_schedule.csv` are not rebuilt by SQL. Edit them here, then run `python scripts/run_sql.py`.

## `forecast_scenario.csv`

One row. The sample is a 9+12: months 1–9 of 2026 are actual, and the next 12 months, through September 2027, are forecast.

| Column | Meaning |
| --- | --- |
| scenario | Forecast name (`9+12`) |
| fiscal_year | Year the actuals start (`2026`) |
| actual_months | Count of closed months kept from the raw extracts (`9`) |
| forecast_months | Count of months calculated after the actuals (`12`, through September 2027) |

## `plan_schedule.csv`

The only place a future equipment purchase or loan draw is entered. The sample file has a header and no rows, so those two lines stay `0`.

A row replaces the driver for that reporting line and month. Recurring lines and data-center buildout still calculate when this file has no row for them.

| Column | Meaning |
| --- | --- |
| reporting_month | First day of the forecast month (`YYYY-MM-01`) |
| reporting_line | Line to replace (`Mining equipment paid` or `Construction loan drawn`, or any other reporting line) |
| amount_usd | Signed USD amount for that line and month |

Recurring operating lines use the average of the last three actual months, rounded to whole dollars. Data center buildout repeats the last actual month. Mining equipment and the construction loan stay zero unless this file names that line and month. `scripts/sql/build_forecast.sql` writes the result to `data/transformed/forecast_transactions.csv`.

## `actual_cash_flow_lines.csv` and `forecast_cash_flow_lines.csv`

One row per reporting line per month. Months with no activity still appear with `0`.

| Column | Meaning |
| --- | --- |
| reporting_month | First day of the month |
| cash_flow_section | `Operating`, `Investing`, or `Financing` |
| business_activity | Mapped business process |
| reporting_line | Line on the management cash flow view |
| signed_amount_usd | Sum of events for that line and month |
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

## `actual_cash_summary.csv` and `forecast_cash_summary.csv`

One row per month. Beginning cash in January is the opening bank snapshot. Later months, including the first forecast month, roll forward from the prior ending cash.

| Column | Meaning |
| --- | --- |
| reporting_month | First day of the month |
| amount_type | `Actual` for January–September 2026, `Forecast` for October 2026–September 2027 |
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
