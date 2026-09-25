# Rolling cash flow forecast

## 1. Overview

This report is a picture of cash going in and out of one fictional site as it moves from Bitcoin mining to a data center. The numbers are examples, not a live company feed. Raw extracts cover Bitcoin sales, operating bills, capital payments, loan draws, and the bank balance. Those pieces are tidied so months and dollars line up, then named the way a cash-flow statement does (day-to-day operations, building the facility, money from lenders). The Forecast tab shows that management cash flow view — not a GAAP statement — with a chart, monthly table, and drilldown to source transaction IDs.

Then open the **Data Flow** tab in `cashflow-forecast.html` to see the full tables. Column details are in `data/raw/README.md`.

| System | Files | Grain | Payload |
| --- | --- | --- | --- |
| Treasury / exchange | `bitcoin_sales.csv` | Settled sale | BTC sold, USD received |
| Accounts payable | `operating_payments.csv` | Paid invoice | Mining power and overhead cash paid |
| Capital projects / AP | `capital_payments.csv` | Paid invoice | Data center buildout and mining equipment |
| Treasury / loan system | `loan_draws.csv` | Funded draw | Construction-loan draws |
| Bank export | `bank_balance.csv` | Account snapshot | Opening available cash |

## 2. Data Model

![FP&A data model: data sources feed the raw, transformed, and reporting tiers, which feed output](chart/data-model.svg)

Data Sources – Structured Data (ERP, Vena, etc), Unstructured Data (pdf, wiki pages etc), and Other Internal Sources provide the original records.

Raw Tier – Data captured by operational systems in its original format, before business rules are applied.

Transformed Tier – Data is validated, cleaned, standardized, and mapped to consistent business definitions. Records retain a link to their sources.

Reporting Tier – Transformed data is aggregated into metrics and tables designed for dashboards, analysis, and decision-making.

Output – Output can use BI tools and dashboards (Tableau, Power BI, Sigma, etc.) and LLM applications on top of the foundation data model.

The SQL transform keeps eligible settled, paid, and funded events, maps them through `activity_mapping.csv`, and writes one cash-activity row per transaction. Opening cash is stored separately and is not a cash-flow event. Column details are in `data/transformed/README.md`.

| Table | Grain | Keys / measures |
| --- | --- | --- |
| `data/transformed/activity_mapping.csv` | Source × category | business activity, cash-flow section, reporting line |
| `data/transformed/cash_transactions.csv` | Eligible cash event | `transaction_id`, `cash_date`, `reporting_month`, `signed_amount_usd` |
| `data/transformed/opening_balance.csv` | Account snapshot | `available_balance_usd` |

Rebuild with DuckDB SQL (`scripts/sql/`):

```
python scripts/run_sql.py
```

That runs three scripts: actuals for January–September, the October–December forecast, then the monthly report. The forecast is calculated in SQL. The browser only displays it.

## 3. Semantic Layer

The semantic layer centralizes business definitions, dimensions, and calculation rules so they can be reused across reports. In this design, shared SQL views define cash-flow classifications and measures such as cash inflows, cash outflows, and net cash movement, with the underlying code maintained in GitHub.

For example, a **Tableau published data source** makes these definitions available to everyone building connected dashboards. Teams use shared dimensions such as “Reporting Month,” “Cash-Flow Category,” and “Actual / Forecast,” along with approved calculations.

| Shared dimension: Cash-Flow Category | Example transactions |
| --- | --- |
| Operating | Electricity and other operating payments |
| Investing | Equipment purchases and capital expenditures |
| Financing | Loan proceeds and principal repayments |

The **Finance team** can use this dimension to summarize monthly cash flow by category, while the **Operations team** uses it to review individual payments. Both reports apply the same classifications, while each team chooses its own layout, filters, and level of detail. This maintains consistent business definitions while giving teams the flexibility to create their own views, dashboards, and reports. Other tools can also reuse the underlying SQL views.

**The semantic layer also provides essential business context for AI.** It gives AI workflows access to approved definitions, relationships, and calculation rules—for example, what counts as a cash inflow and which periods contain actuals versus forecasts. Without this context, AI may misinterpret fields, apply inconsistent calculations, or invent definitions and unsupported figures. Connecting AI workflows to shared models and requiring answers to use queried results helps keep responses consistent with reporting tools. Validation and traceability to source data remain necessary to verify accuracy.

## 4. Data Governance

The Data Flow tab walks through payment `INV-PWR-2026-01` in five selectable steps: the original Accounts Payable record, the shared mapping, quality checks with two what-if simulations, the January operating cash-flow lines, and Finance versus Operations views. Displayed amounts are read from the sample files. The simulations describe how the existing SQL rejects a repeated transaction ID or an unmapped category; they do not change the files or run the pipeline. “View this payment in the report” opens the Forecast tab on that payment’s reporting-line drilldown.

The reporting layer turns the shared definitions into the tables that reports actually read: one row per reporting line per month, and a monthly summary carrying the section nets and the cash roll-forward. It is built for a rolling twelve-month view refreshed after each close, so treasury, FP&A, and operations all work from the same numbers at the level of detail each one needs.

| Report | Audience | Question it answers | Built with |
| --- | --- | --- | --- |
| Rolling twelve-month cash flow | Treasury and finance leadership | Where is cash heading over the next year? | `monthly_cash_summary.csv` |
| Monthly cash flow detail | FP&A | Which lines moved, and by how much? | `monthly_cash_flow_lines.csv` |
| Payment-level review | Operations | Which transactions sit behind a line? | `cash_transactions.csv` drilldown |

Reports carry no business logic of their own. Every figure arrives precomputed from `data/reporting/`, so a chart and a spreadsheet built on the same file cannot disagree, and a definition changes in one place rather than in each report. Amounts are signed once, with inflows positive and outflows negative, and months are stored as month starts so periods line up across files.

Each number stays traceable back to a transaction. A bar in the chart is a section net, which resolves to statement lines in `monthly_cash_flow_lines.csv`, which join to individual `transaction_id` values in `data/transformed/cash_transactions.csv` on `reporting_month` and `reporting_line`. The Forecast tab works that path end to end: expand a section, then click a monthly figure to list the source transactions behind it. Column-level detail for both reporting files is in `data/reporting/README.md`.

| Reporting file | What is kept | Used for |
| --- | --- | --- |
| `monthly_cash_flow_lines.csv` | Signed amount by month and reporting line | Statement lines and drilldown keys |
| `monthly_cash_summary.csv` | Section nets, beginning and ending cash | Chart totals and cash roll-forward |

Serve the folder and open the dashboard:

```
python -m http.server 8000
```

Then open [http://localhost:8000/cashflow-forecast.html](http://localhost:8000/cashflow-forecast.html).
