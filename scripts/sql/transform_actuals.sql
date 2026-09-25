-- Transform raw extracts into cleaned cash-activity actuals.
-- DuckDB dialect; reads/writes CSV.
-- January–September stay actuals. Later months are calculated in build_forecast.sql.
--
-- Usage (from repo root):
--     python scripts/run_sql.py
--   or DuckDB CLI:
--     duckdb < scripts/sql/transform_actuals.sql

CREATE OR REPLACE TEMP TABLE scenario AS
SELECT
    trim(scenario) AS scenario,
    fiscal_year::INTEGER AS fiscal_year,
    actual_months::INTEGER AS actual_months,
    forecast_months::INTEGER AS forecast_months
FROM read_csv_auto('data/forecast/forecast_9_plus_3.csv', header = true);

SELECT CASE
    WHEN (SELECT count(*) FROM scenario) <> 1
        OR (SELECT scenario FROM scenario) <> '9+3'
        OR (SELECT actual_months + forecast_months FROM scenario) <> 12
    THEN error('forecast_9_plus_3.csv must contain one 9+3 row whose months add to 12')
    ELSE 'ok'
END;

CREATE OR REPLACE TEMP TABLE mapping AS
SELECT
    trim(source) AS source,
    trim(category) AS category,
    trim(business_activity) AS business_activity,
    trim(cash_flow_section) AS cash_flow_section,
    trim(reporting_line) AS reporting_line
FROM read_csv_auto('data/transformed/activity_mapping.csv', header = true);

CREATE OR REPLACE TEMP TABLE staged AS
SELECT
    trim(sale_id) AS transaction_id,
    'Treasury / exchange' AS source_system,
    'bitcoin_sales.csv' AS source_file,
    'Bitcoin sales' AS source,
    lower(trim(status)) AS source_category,
    '' AS vendor,
    settlement_date::DATE AS cash_date,
    'inflow' AS cash_direction,
    usd_received::DOUBLE AS unsigned_amount_usd
FROM read_csv_auto('data/raw/bitcoin_sales.csv', header = true)
WHERE upper(trim(status)) = 'SETTLED'

UNION ALL

SELECT
    trim(invoice_id),
    'Accounts payable',
    'operating_payments.csv',
    'Operating payments',
    trim(cost_category),
    trim(vendor),
    payment_date::DATE,
    'outflow',
    amount_paid::DOUBLE
FROM read_csv_auto('data/raw/operating_payments.csv', header = true)
WHERE upper(trim(status)) = 'PAID'

UNION ALL

SELECT
    trim(payment_id),
    'Capital projects / AP',
    'capital_payments.csv',
    'Capital payments',
    trim(spend_category),
    trim(vendor),
    payment_date::DATE,
    'outflow',
    amount_paid::DOUBLE
FROM read_csv_auto('data/raw/capital_payments.csv', header = true)
WHERE upper(trim(status)) = 'PAID'

UNION ALL

SELECT
    trim(draw_id),
    'Treasury / loan system',
    'loan_draws.csv',
    'Loan draws',
    lower(trim(status)),
    trim(lender),
    funding_date::DATE,
    'inflow',
    draw_amount::DOUBLE
FROM read_csv_auto('data/raw/loan_draws.csv', header = true)
WHERE upper(trim(status)) = 'FUNDED';

CREATE OR REPLACE TEMP TABLE mapped AS
SELECT
    s.transaction_id,
    s.source_system,
    s.source_file,
    s.source_category,
    s.vendor,
    s.cash_date,
    date_trunc('month', s.cash_date)::DATE AS reporting_month,
    m.business_activity,
    m.cash_flow_section,
    m.reporting_line,
    s.cash_direction,
    CASE
        WHEN s.cash_direction = 'inflow' THEN s.unsigned_amount_usd
        ELSE -s.unsigned_amount_usd
    END AS signed_amount_usd
FROM staged s
LEFT JOIN mapping m
    ON m.source = s.source
    AND m.category = s.source_category;

SELECT CASE
    WHEN EXISTS (SELECT 1 FROM mapped WHERE reporting_line IS NULL)
    THEN error('Unmapped category found. Add it to activity_mapping.csv; unmapped activity is not assigned to Other.')
    WHEN (SELECT count(*) FROM mapped) <> (SELECT count(DISTINCT transaction_id) FROM mapped)
    THEN error('Transformed transaction_id values are not unique.')
    WHEN EXISTS (
        SELECT 1 FROM mapped
        WHERE source_file IN ('operating_payments.csv', 'capital_payments.csv', 'loan_draws.csv')
          AND trim(coalesce(vendor, '')) = ''
    )
    THEN error('A payment or loan draw is missing its vendor')
    ELSE 'ok'
END;

CREATE OR REPLACE TEMP TABLE actuals AS
SELECT mapped.*
FROM mapped
CROSS JOIN scenario
WHERE year(mapped.cash_date) = scenario.fiscal_year
    AND month(mapped.cash_date) <= scenario.actual_months;

SELECT CASE
    WHEN (SELECT count(*) FROM mapped) <> (SELECT count(*) FROM actuals)
    THEN error('A source event falls outside the 9 actual months. Remove it from data/raw/; October–December are calculated, not typed as actuals.')
    ELSE 'ok'
END;

COPY (
    SELECT
        transaction_id,
        source_system,
        source_file,
        source_category,
        vendor,
        strftime(cash_date, '%Y-%m-%d') AS cash_date,
        strftime(reporting_month, '%Y-%m-%d') AS reporting_month,
        business_activity,
        cash_flow_section,
        reporting_line,
        cash_direction,
        CAST(signed_amount_usd AS BIGINT) AS signed_amount_usd
    FROM actuals
    ORDER BY cash_date, transaction_id
) TO 'data/transformed/cash_transactions.csv' (HEADER, DELIMITER ',');

SELECT CASE
    WHEN (SELECT count(*) FROM read_csv_auto('data/raw/bank_balance.csv', header = true)) <> 1
    THEN error('bank_balance.csv must contain exactly one opening-balance record')
    ELSE 'ok'
END;

COPY (
    SELECT
        trim(account_id) AS account_id,
        strftime(balance_date::DATE, '%Y-%m-%d') AS balance_date,
        trim(currency) AS currency,
        CAST(available_balance AS BIGINT) AS available_balance_usd
    FROM read_csv_auto('data/raw/bank_balance.csv', header = true)
) TO 'data/transformed/opening_balance.csv' (HEADER, DELIMITER ',');

SELECT CASE
    WHEN (SELECT sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Operating' AND cash_direction = 'inflow') FROM actuals) <> 3500000
    THEN error('Nine-month operating inflows != 3500000')
    WHEN (SELECT sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Operating' AND cash_direction = 'outflow') FROM actuals) <> -3000000
    THEN error('Nine-month operating outflows != -3000000')
    WHEN (SELECT sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Investing' AND cash_direction = 'outflow') FROM actuals) <> -3500000
    THEN error('Nine-month investing outflows != -3500000')
    WHEN (SELECT sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Financing' AND cash_direction = 'inflow') FROM actuals) <> 2000000
    THEN error('Nine-month financing inflows != 2000000')
    WHEN (SELECT sum(signed_amount_usd) FROM actuals) <> -1000000
    THEN error('Nine-month change in cash != -1000000')
    ELSE 'OK  transform_actuals.sql'
END;
