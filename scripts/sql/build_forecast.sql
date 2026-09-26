-- Calculate October 2026–September 2027 from the 9+12 scenario.
-- Recurring operating lines use the trailing three actual months, rounded half away from zero.
-- Data center buildout repeats the last actual month. Equipment and loan draws stay 0
-- unless plan_schedule.csv supplies that reporting line and month.
-- DuckDB dialect; reads/writes CSV.
--
-- Usage (from repo root):
--     python scripts/run_sql.py

CREATE OR REPLACE TEMP TABLE scenario AS
SELECT
    trim(scenario) AS scenario,
    fiscal_year::INTEGER AS fiscal_year,
    actual_months::INTEGER AS actual_months,
    forecast_months::INTEGER AS forecast_months
FROM read_csv_auto('data/reporting/forecast_scenario.csv', header = true);

CREATE OR REPLACE TEMP TABLE actuals AS
SELECT
    reporting_month::DATE AS reporting_month,
    reporting_line,
    signed_amount_usd::DOUBLE AS signed_amount_usd
FROM read_csv_auto('data/transformed/cash_transactions.csv', header = true);

CREATE OR REPLACE TEMP TABLE plan AS
SELECT
    reporting_month,
    reporting_line,
    amount_usd
FROM read_csv(
    'data/reporting/plan_schedule.csv',
    header = true,
    columns = {
        'reporting_month': 'DATE',
        'reporting_line': 'VARCHAR',
        'amount_usd': 'BIGINT'
    }
);

CREATE OR REPLACE TEMP TABLE line_defs AS
SELECT * FROM (
    VALUES
        ('Mining cash received', 'Bitcoin mining operations', 'Operating', 'inflow', 'FCST-SALE', 'recurring'),
        ('Mining power paid', 'Bitcoin mining operations', 'Operating', 'outflow', 'FCST-PWR', 'recurring'),
        ('Overhead paid', 'Corporate operations', 'Operating', 'outflow', 'FCST-OH', 'recurring'),
        ('Data center buildout paid', 'Data center expansion', 'Investing', 'outflow', 'FCST-DC', 'last_month'),
        ('Mining equipment paid', 'Bitcoin mining operations', 'Investing', 'outflow', 'FCST-EQ', 'plan_only'),
        ('Construction loan drawn', 'Data center financing', 'Financing', 'inflow', 'FCST-DRAW', 'plan_only')
) AS d(reporting_line, business_activity, cash_flow_section, cash_direction, id_prefix, driver_kind);

CREATE OR REPLACE TEMP TABLE forecast_months AS
SELECT (make_date(s.fiscal_year, s.actual_months, 1) + gs.step * INTERVAL 1 MONTH)::DATE AS reporting_month
FROM scenario s
CROSS JOIN generate_series(1, (SELECT forecast_months FROM scenario), 1) AS gs(step);

CREATE OR REPLACE TEMP TABLE recurring AS
SELECT
    a.reporting_line,
    CAST(round(sum(a.signed_amount_usd) / 3.0) AS BIGINT) AS amount_usd
FROM actuals a
CROSS JOIN scenario s
WHERE a.reporting_line IN ('Mining cash received', 'Mining power paid', 'Overhead paid')
    AND a.reporting_month >= make_date(s.fiscal_year, s.actual_months - 2, 1)
    AND a.reporting_month <= make_date(s.fiscal_year, s.actual_months, 1)
GROUP BY a.reporting_line;

CREATE OR REPLACE TEMP TABLE last_buildout AS
SELECT CAST(sum(a.signed_amount_usd) AS BIGINT) AS amount_usd
FROM actuals a
WHERE a.reporting_line = 'Data center buildout paid'
    AND a.reporting_month = (
        SELECT max(reporting_month)
        FROM actuals
        WHERE reporting_line = 'Data center buildout paid'
    );

CREATE OR REPLACE TEMP TABLE forecast_rows AS
SELECT
    d.id_prefix || '-' || strftime(m.reporting_month, '%Y-%m') AS transaction_id,
    'Forecast' AS source_system,
    CASE
        WHEN p.amount_usd IS NOT NULL THEN 'plan_schedule.csv'
        ELSE 'forecast_scenario.csv'
    END AS source_file,
    d.reporting_line AS source_category,
    '' AS vendor,
    m.reporting_month AS cash_date,
    m.reporting_month,
    d.business_activity,
    d.cash_flow_section,
    d.reporting_line,
    d.cash_direction,
    CAST(coalesce(
        p.amount_usd,
        CASE d.driver_kind
            WHEN 'recurring' THEN r.amount_usd
            WHEN 'last_month' THEN b.amount_usd
            ELSE 0
        END,
        0
    ) AS BIGINT) AS signed_amount_usd
FROM forecast_months m
CROSS JOIN line_defs d
LEFT JOIN recurring r
    ON r.reporting_line = d.reporting_line
LEFT JOIN last_buildout b
    ON d.driver_kind = 'last_month'
LEFT JOIN plan p
    ON p.reporting_month = m.reporting_month
    AND p.reporting_line = d.reporting_line;

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
        signed_amount_usd
    FROM forecast_rows
    ORDER BY reporting_month, transaction_id
) TO 'data/transformed/forecast_transactions.csv' (HEADER, DELIMITER ',');

SELECT CASE
    WHEN (SELECT count(*) FROM forecast_rows) <> (SELECT forecast_months * 6 FROM scenario)
    THEN error('Expected one forecast transaction for each reporting line and forecast month')
    WHEN (SELECT count(*) FROM forecast_rows) <> (SELECT count(DISTINCT transaction_id) FROM forecast_rows)
    THEN error('Forecast transaction_id values are not unique')
    WHEN EXISTS (
        SELECT 1
        FROM forecast_rows
        WHERE reporting_line = 'Mining cash received' AND signed_amount_usd <> 433333
    )
    THEN error('Forecast mining cash received != 433333')
    WHEN EXISTS (
        SELECT 1
        FROM forecast_rows
        WHERE reporting_line = 'Mining power paid' AND signed_amount_usd <> -266667
    )
    THEN error('Forecast mining power paid != -266667')
    WHEN EXISTS (
        SELECT 1
        FROM forecast_rows
        WHERE reporting_line = 'Overhead paid' AND signed_amount_usd <> -66667
    )
    THEN error('Forecast overhead paid != -66667')
    WHEN EXISTS (
        SELECT 1
        FROM forecast_rows
        WHERE reporting_line = 'Data center buildout paid' AND signed_amount_usd <> -600000
    )
    THEN error('Forecast data center buildout paid != -600000')
    WHEN EXISTS (
        SELECT 1
        FROM forecast_rows
        WHERE reporting_line IN ('Mining equipment paid', 'Construction loan drawn')
            AND signed_amount_usd <> 0
    )
    THEN error('Equipment and loan-draw forecasts must stay 0 until plan_schedule.csv sets them')
    ELSE 'OK  build_forecast.sql'
END;
