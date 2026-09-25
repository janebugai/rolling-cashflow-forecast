# Forecast

Plans, forecasts, and actuals are organized together for the reporting view. These files mark which periods are actual and which are forecast, and any planned amount that should replace a calculated driver. They are not rebuilt by SQL. Edit them here, then run `python scripts/run_sql.py`.

January–September stay actual source events. October–December are calculated in `scripts/sql/build_forecast.sql` and written to `data/transformed/forecast_transactions.csv`. The Forecast tab shows the result as a management cash flow view — not a GAAP statement — with a chart, monthly table, and drilldown to source transaction IDs. Amounts are plain signed USD (inflows positive, outflows negative). Dates are ISO `YYYY-MM-DD`.

| File | Role | Grain |
| --- | --- | --- |
| `forecast_9_plus_3.csv` | How many months are actual versus forecast | One scenario row |
| `plan_schedule.csv` | Optional replacement amounts for a forecast line and month | One planned amount |

## `forecast_9_plus_3.csv`

One row. SQL checks that `actual_months` and `forecast_months` add to 12. With the sample row, months 1–9 are actual and months 10–12 are forecast.

| Column | Meaning |
| --- | --- |
| scenario | Forecast name (`9+3`) |
| fiscal_year | Year being forecast (`2026`) |
| actual_months | Count of closed months kept from the raw extracts (`9`) |
| forecast_months | Count of months calculated after the actuals (`3`) |

## `plan_schedule.csv`

The only place a future equipment purchase or loan draw is entered. The sample file has a header and no rows, so those two lines stay `0`.

A row replaces the driver for that reporting line and month. Recurring lines and data-center buildout still calculate when this file has no row for them.

| Column | Meaning |
| --- | --- |
| reporting_month | First day of the forecast month (`YYYY-MM-01`) |
| reporting_line | Line to replace (`Mining equipment paid` or `Construction loan drawn`, or any other reporting line) |
| amount_usd | Signed USD amount for that line and month |

Recurring operating lines use the average of the last three actual months, rounded to whole dollars. Data center buildout repeats the last actual month. Mining equipment and the construction loan stay zero unless this file names that line and month.
