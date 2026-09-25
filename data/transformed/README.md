# Transformed tier

Data is validated, cleaned, standardized, and mapped to consistent business definitions. Records retain a link to their sources.

Amounts are plain numbers (no `$` or commas). Dates are ISO `YYYY-MM-DD`. Receipts and loan draws are positive; payments are negative. Bitcoin sale proceeds are operating cash receipts in a management cash flow view, not a GAAP statement.

Rebuild with `python scripts/run_sql.py`. `scripts/sql/transform_actuals.sql` reads `data/raw/` plus `activity_mapping.csv` and writes `cash_transactions.csv` and `opening_balance.csv` for the nine actual months. `scripts/sql/build_forecast.sql` then writes `forecast_transactions.csv` for October–December.

| File | Role | Grain |
| --- | --- | --- |
| `activity_mapping.csv` | Lookup used in the transform; not a cash-event output | Source × category |
| `cash_transactions.csv` | Eligible cash events, mapped and signed | One row per actual transaction |
| `forecast_transactions.csv` | Calculated October–December events | One row per reporting line per forecast month |
| `opening_balance.csv` | Bank snapshot copied from raw | One account row |

## `activity_mapping.csv`

Lookup from raw source and category to business activity, cash-flow section, and reporting line. Unmapped categories fail the transform; they are not assigned to Other.

| Column | Meaning |
| --- | --- |
| source | Raw extract (`Bitcoin sales`, `Operating payments`, `Capital payments`, `Loan draws`) |
| category | Status or spend/cost category (`settled`, `funded`, `Mining power`, `Overhead`, `Data center buildout`, `Mining equipment`) |
| business_activity | Business process name |
| cash_flow_section | `Operating`, `Investing`, or `Financing` |
| reporting_line | Line used on the management cash flow view |

| source | category | business_activity | cash_flow_section | reporting_line |
| --- | --- | --- | --- | --- |
| Bitcoin sales | settled | Bitcoin mining operations | Operating | Mining cash received |
| Operating payments | Mining power | Bitcoin mining operations | Operating | Mining power paid |
| Operating payments | Overhead | Corporate operations | Operating | Overhead paid |
| Capital payments | Data center buildout | Data center expansion | Investing | Data center buildout paid |
| Capital payments | Mining equipment | Bitcoin mining operations | Investing | Mining equipment paid |
| Loan draws | funded | Data center financing | Financing | Construction loan drawn |

## `cash_transactions.csv`

One row per eligible cash event. Kept statuses: sales `SETTLED`, invoices `PAID`, loan draws `FUNDED`. `transaction_id`, `source_system`, and `source_file` trace each row back to a raw record. Opening cash is not included here.

| Column | Meaning |
| --- | --- |
| transaction_id | Unique id from the source extract (`sale_id`, `invoice_id`, `payment_id`, or `draw_id`) |
| source_system | Source-system label |
| source_file | Raw file name |
| source_category | Category used to join `activity_mapping.csv` |
| vendor | Payee on payment rows. Loan draws use the lender. Bitcoin sales have no vendor. |
| cash_date | Date cash moved |
| reporting_month | First day of the month that contains `cash_date` |
| business_activity | Mapped business process |
| cash_flow_section | `Operating`, `Investing`, or `Financing` |
| reporting_line | Mapped reporting line |
| cash_direction | `inflow` or `outflow` |
| signed_amount_usd | Signed USD amount (inflows positive, outflows negative) |

## `forecast_transactions.csv`

Same columns as `cash_transactions.csv`. One row per reporting line for October, November, and December, including zeros. `source_system` is `Forecast`. `source_file` is `forecast_9_plus_3.csv`, or `plan_schedule.csv` when that file sets the amount. Recurring operating lines are the trailing three actual months, rounded to whole dollars. Data center buildout repeats September. Mining equipment and the construction loan stay zero unless `data/forecast/plan_schedule.csv` names that line and month.

## `opening_balance.csv`

Cleaned bank snapshot from `data/raw/bank_balance.csv`. This balance is the starting point for the cash schedule, not a cash-flow transaction.

| Column | Meaning |
| --- | --- |
| account_id | Operating bank account |
| balance_date | Statement date |
| currency | Account currency |
| available_balance_usd | Available cash on that date |
