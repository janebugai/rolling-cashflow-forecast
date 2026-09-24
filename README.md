
Cash Flow Forecasting MVP — Mining-to-Data-Center Transition
An interactive, single-page dashboard modeling 12 months of cash flow for a fictional company converting one site from Bitcoin mining to data center hosting. All data is illustrative. This is a portfolio demo, not a forecast for any real company.

How to run it
From the repo root, rebuild the reporting mart from the raw extracts, then serve the folder over HTTP (browsers block fetch() of local JSON from file://):

python scripts/build_report_data.py
python -m http.server 8000

Then open http://localhost:8000/cashflow-forecast.html. Edit source numbers in data/raw/, rebuild, and refresh. The dashboard only reads data/reporting/cashflow-forecast.json.

Data architecture
Three file-based tiers (illustrative extracts, not live ERP):

1. Raw (data/raw/) — source-shaped dumps: erp_finance.json (SAP cash, G&A, construction AP, treasury), mining_ops.json, dc_commercial.json, planning.json.
2. Transformed (data/transformed/) — cleaned, typed USD tables aligned to forecast months. Written by the script; the browser does not load this folder.
3. Reporting (data/reporting/cashflow-forecast.json) — mart shaped for this dashboard only (forecast window, defaultInputs, fixedAssumptions, mining, construction, dataCenter, cashFlowCategories).

What's on the dashboard
Scenario Modeling inputs: the page loads with the Base scenario's values filled in (see "Scenario reference values" below). Edit any field directly to explore other cases.
Editable inputs: BTC price, construction cost overrun %, and construction delay (months). Every change recalculates the forecast immediately — nothing needs to be submitted. Everything else (starting cash, data center revenue and opening month, debt draw, equity funding) is a fixed assumption, not user-editable — see "Fixed assumptions" below.
Chart: monthly bars stack the same three cash flow statement categories (Operating Activities in blue, Investing Activities in mint green, Financing Activities in periwinkle — see "Chart color palette" below) both above zero as Cash Inflow and below zero as Cash Outflow (shown at reduced opacity so the two directions stay visually distinct), with a dashed amber-brown line tracing net cash flow. The y-axis top is set to the exact value of the tallest bar (not rounded up to a bigger round number), so there's no wasted headroom above it. A value ticker above each bar shows total Cash Inflow for the month, and one below each bar shows total Cash Outflow. Hover any bar segment or line point for its exact value.
Monthly Detail table with drill-down: Cash Inflow and Cash Outflow are both expanded by default, showing their three Operating/Investing/Financing Activities categories underneath; click either row (▾ / ▸) to collapse or re-expand it independently. Cash Inflow, Cash Outflow, Net Cash Flow, and Ending Cash Balance are semi-bold to stand out as the table's totals; the category sub-rows are normal weight. The only color coding is per-value, not per-row: any negative number, in any row, renders in red with accounting-style parentheses (e.g. ($1.51M) instead of -$1.51M) — everything else uses the same neutral text color and plain $ format. The chart's tooltips and value tickers use the same parentheses convention for negative amounts; only the compact y-axis gridline labels keep the plain minus sign. Hover a category's name for what it represents and its driver formula.
Chart color palette
The bar/line chart uses four colors, set as CSS variables in cashflow-forecast.html:

Category	Color	Hex
Operating Activities	Blue	#57b8ff
Investing Activities	Mint green	#42e2b8
Financing Activities	Light periwinkle	#b4c5e4
Net Cash Flow	Amber-brown	#b1740f
Category identity is never color-only: each stacked segment keeps the same vertical position every month (Operating at the bottom, Investing in the middle, Financing on top), and every bar segment, line point, and table row also carries a text label or hover tooltip.

The forecast model
The model covers one site over 12 monthly periods, labeled as calendar months (MM/YYYY). The forecast is hardcoded to start October 2026 — a fixed, arbitrary illustrative starting point, not derived from the real current date, so the labels stay the same every time the demo is opened (forecast.startYear / forecast.startMonth in data/reporting/cashflow-forecast.json, sourced from data/raw/planning.json). Every month is calculated in order, left to right:

Total inflow   = Operating Activities (in) + Investing Activities (in) + Financing Activities (in)
Total outflow  = Operating Activities (out) + Investing Activities (out) + Financing Activities (out)
Net cash flow  = Total inflow − Total outflow
Ending cash    = Beginning cash + Net cash flow
Next month's beginning cash = this month's ending cash
Month 1's beginning cash is the Starting cash input.

Operating / Investing / Financing Activities
The Monthly Detail table's Cash Inflow and Cash Outflow rows each expand to the same three categories — the classic split from a cash flow statement (click either row, or see cashFlowCategories in data/reporting/cashflow-forecast.json):

Category	Inflow driver	Outflow driver
Operating Activities	Bitcoin sales + Data center customer payments	Mining costs + Other fixed operating costs
Investing Activities	Not modeled in this MVP — always $0	Construction payments (baseline × cost overrun, shifted by delay)
Financing Activities	Debt draws + Equity funding	Not modeled in this MVP — always $0
Bitcoin sales[m] = btcProductionByMonth[m] × BTC price
Data center customer payments[m] = dcMonthlyRevenueFullRamp × ramp fraction for month m (0 before the data center's opening month). The "contracted capacity × price per MW" part of a real driver is collapsed into the single Data center revenue at full ramp ($/mo) input in this MVP — the model doesn't ask for capacity and price separately, only their product.
Mining costs[m] = btcProductionByMonth[m] × powerCostPerBtc + otherMiningOpexMonthly
Investing Activities inflow and Financing Activities outflow have no driver in this MVP — they're included as categories (and always show $0) so the structure matches a standard three-part cash flow statement on both the inflow and outflow side. A future version could add, for example, proceeds from selling retired mining hardware (investing inflow) or debt repayments and dividends (financing outflow).

Mining production schedule
btcProductionByMonth is a fixed, illustrative monthly BTC output schedule that winds down over the year (from 40 BTC in month 1 to 3 BTC in month 12) as the site pivots away from mining toward hosting. powerCostPerBtc ($26,000) and otherMiningOpexMonthly ($120,000) are fixed assumptions from data/raw/mining_ops.json. BTC price is the one editable driver of mining economics.

Construction payments and delay
Construction has a fixed baseline payment schedule for months 1–6 (ERP AP in data/raw/erp_finance.json, then construction.baselinePaymentsByMonth in the reporting mart). Two inputs adjust it:

Cost overrun % multiplies every baseline payment by (1 + overrun / 100).
Delay (months) shifts every remaining baseline payment later by that many months — a payment originally due in baseline month i is paid in month (i + delay).
This is a simplification: in reality a delay might also change payment sizes (extended overhead, re-mobilization costs) or add new line items. For this MVP, a delay only pushes the same dollar amounts later — it does not add or remove cost.

Payments that shift past month 12 fall outside the 12-month view and are dropped, not rolled into month 12. For example, with a 3-month delay, the baseline month-6 payment (originally month 6) would move to month 9 and still show; but if the delay were large enough to push a payment past month 12, it simply disappears from the displayed period rather than being dumped into the last visible month. A production version would extend the forecast window or carry a payments backlog forward explicitly.

Data center revenue ramp
Data center opening month = dcBaseOpenMonth + delay months, where dcBaseOpenMonth is the editable Data center opening month (1–12, before delay) input (default 7). A construction delay pushes the opening back by the same number of months on top of whatever opening month you set, on the assumption that the facility can't open before construction finishes. If the resulting month falls after month 12, the data center simply never opens within the displayed window.
After opening, revenue ramps over 4 months as a fraction of full-ramp revenue: [25%, 50%, 80%, 100%], then stays at 100% for the rest of the 12-month window (see the Data center customer payments formula above).
Debt draws and equity funding (Financing Activities)
These are the two underlying drivers of Financing Activities, each a single planned cash injection:

Debt draws[m] = debtDrawAmount in exactly debtDrawMonth (1–12), 0 elsewhere.
Equity funding[m] = equityFundingAmount in exactly equityFundingMonth (1–12), 0 elsewhere.
There is no interest, repayment, dilution, or amortization modeled for either — each is a one-time cash injection, which keeps the MVP simple. Equity funding defaults to $0 in the Base scenario (an equity round is "if applicable," not assumed).

Other fixed operating costs
A flat otherFixedOpexMonthly ($350,000) — illustrative corporate G&A — is charged every month regardless of scenario or inputs.

Input validation
All three editable fields are clamped so the chart can't break:

BTC price and cost overrun % can't go below their floor (0, or −100% for overrun).
Construction delay is rounded to a whole number and clamped to 0–24 months.
If a field is edited to an out-of-range value, it's clamped for the calculation and the field is outlined in red until corrected.
Fixed assumptions
Everything below is held constant at fixedAssumptions in data/reporting/cashflow-forecast.json (from ERP cash/treasury, DC commercial, and G&A) — not exposed in the Scenario Modeling panel, and the same for every scenario:

Assumption	Value
Starting cash	$10,000,000
Data center revenue at full ramp	$1,800,000/mo
Data center opening month (before delay)	7
Debt draw amount	$8,000,000
Debt draw month	3 (12/2026)
Equity funding amount	$0
Equity funding month	1 (n/a — amount is $0)
A construction delay still pushes the data center's effective opening month later (fixed opening month 7 + delay), even though the base opening month itself isn't editable.

Scenario reference values
The dashboard loads with defaultInputs from data/raw/planning.json (the Base column below). Downside and Upside aren't wired to a button in the UI — they're reference value-sets you can key in by hand to reproduce those cases. Since only BTC price, cost overrun, and delay are editable, that's all that varies between scenarios — the fixed assumptions above stay the same in every case.

Input	Base	Downside	Upside
BTC price	$65,000	$35,000	$95,000
Construction cost overrun	8%	50%	0%
Construction delay	0 months	5 months	0 months
These are illustrative starting points, not predictions. Base stays cash-positive throughout with moderate dips (lowest ending cash ~$5.8M in 11/2026). Upside grows steadily throughout (lowest ~$8.6M in 11/2026, before the debt draw lands). Downside needs both a much lower BTC price and a much larger, longer construction delay/overrun to turn cash-negative here, since the $8M debt draw and $1.8M/mo data center revenue are now fixed rather than scaled down with the scenario — it dips negative starting 06/2027 and bottoms out around -$5.7M in 08/2027, as the delayed data center pushes revenue outside most of the window while construction costs balloon.

Design notes / known simplifications
Single site, single currency, no taxes, no debt service/interest, no inventory or receivables timing — this is a cash model, not a full three-statement model.
The construction delay's "shift remaining payments" rule is intentionally simple (see above).
The data center ramp curve (25/50/80/100%) is a fixed illustrative shape, not editable in this MVP.
Chart and table are rendered with plain SVG/HTML/CSS and vanilla JavaScript — no chart library, no build tooling. The page fetches data/reporting/cashflow-forecast.json, so it needs a local HTTP server rather than a file:// open.
