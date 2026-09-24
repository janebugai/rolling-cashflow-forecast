# Raw tier

Data captured by operational systems in its original format, before business rules are applied.

These files are fictional extracts. Amounts are plain numbers (no `$` or commas). Dates are ISO `YYYY-MM-DD`. They are not rebuilt by SQL; edit them here, then run `python scripts/run_sql.py` to refresh transformed and reporting files.

| File | Source system | Grain |
| --- | --- | --- |
| `bitcoin_sales.csv` | Treasury / exchange | Settled sale |
| `operating_payments.csv` | Accounts payable | Paid invoice |
| `capital_payments.csv` | Capital projects / AP | Paid invoice |
| `loan_draws.csv` | Treasury / loan system | Funded draw |
| `bank_balance.csv` | Bank export | Account snapshot |

## `bitcoin_sales.csv`

Exchange settlement export of Bitcoin sold for USD. The transform keeps rows with status `SETTLED`.

| Column | Meaning |
| --- | --- |
| sale_id | Unique sale identifier |
| settlement_date | Cash-settlement date |
| asset | Asset sold (`BTC`) |
| btc_sold | Quantity of Bitcoin sold |
| usd_per_btc | USD price per Bitcoin |
| usd_received | Cash received (`btc_sold × usd_per_btc`) |
| status | Settlement status (`SETTLED`) |

## `operating_payments.csv`

AP export of paid operating invoices. Two invoices per month: Mining power and Overhead. Power usage (`mwh`, `rate_per_mwh`) is blank on Overhead rows. The transform keeps rows with status `PAID`.

| Column | Meaning |
| --- | --- |
| invoice_id | Unique invoice identifier |
| payment_date | Date cash was paid |
| vendor | Payee |
| cost_category | `Mining power` or `Overhead` |
| mwh | Megawatt-hours billed (power only) |
| rate_per_mwh | USD per MWh (power only) |
| amount_paid | Cash paid (USD) |
| status | Payment status (`PAID`) |

## `capital_payments.csv`

Capital-projects / AP export of paid project invoices. The transform keeps rows with status `PAID`.

| Column | Meaning |
| --- | --- |
| payment_id | Unique payment identifier |
| payment_date | Date cash was paid |
| project_id | Capital project |
| vendor | Payee |
| spend_category | `Data center buildout` or `Mining equipment` |
| amount_paid | Cash paid (USD) |
| status | Payment status (`PAID`) |

## `loan_draws.csv`

Treasury / loan-system export of construction-facility draws. The transform keeps rows with status `FUNDED`.

| Column | Meaning |
| --- | --- |
| draw_id | Unique draw identifier |
| funding_date | Date cash was funded |
| facility_id | Loan facility |
| lender | Counterparty bank |
| draw_amount | Cash drawn (USD) |
| status | Funding status (`FUNDED`) |

## `bank_balance.csv`

Bank export of available cash. This snapshot is opening cash for the forecast, not a cash-flow event. The transform copies it to `data/transformed/opening_balance.csv`.

| Column | Meaning |
| --- | --- |
| account_id | Operating bank account |
| balance_date | Statement date |
| currency | Account currency |
| available_balance | Available cash on that date |
