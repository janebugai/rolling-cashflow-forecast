-- Build monthly cash-flow reporting files from transformed actuals and the calculated forecast.
-- DuckDB dialect; reads/writes CSV.
-- Does not read raw extracts or change activity mappings.
--
-- Usage (from repo root):
--     python scripts/run_sql.py
--   or DuckDB CLI:
--     duckdb < scripts/sql/build_monthly_report.sql

CREATE OR REPLACE TEMP TABLE scenario AS
SELECT
    fiscal_year::INTEGER AS fiscal_year,
    actual_months::INTEGER AS actual_months,
    forecast_months::INTEGER AS forecast_months
FROM read_csv_auto('data/reporting/forecast_scenario.csv', header = true);

CREATE OR REPLACE TEMP TABLE cash_transactions AS
SELECT
    transaction_id,
    reporting_month::DATE AS reporting_month,
    cash_flow_section,
    business_activity,
    reporting_line,
    signed_amount_usd::DOUBLE AS signed_amount_usd
FROM read_csv_auto('data/transformed/cash_transactions.csv', header = true)
UNION ALL
SELECT
    transaction_id,
    reporting_month::DATE AS reporting_month,
    cash_flow_section,
    business_activity,
    reporting_line,
    signed_amount_usd::DOUBLE AS signed_amount_usd
FROM read_csv_auto('data/transformed/forecast_transactions.csv', header = true);

CREATE OR REPLACE TEMP TABLE opening_balance AS
SELECT available_balance_usd::DOUBLE AS available_balance_usd
FROM read_csv_auto('data/transformed/opening_balance.csv', header = true);

SELECT CASE
    WHEN (SELECT count(*) FROM opening_balance) <> 1
    THEN error('opening_balance.csv must contain exactly one row')
    WHEN (SELECT available_balance_usd FROM opening_balance) <> 2000000
    THEN error('Opening cash != 2000000')
    WHEN (SELECT max(reporting_month) FROM cash_transactions) <> (
        SELECT (make_date(fiscal_year, actual_months, 1) + forecast_months * INTERVAL 1 MONTH)::DATE
        FROM scenario
    )
    THEN error('Forecast does not run through September 2027')
    ELSE 'ok'
END;

CREATE OR REPLACE TEMP TABLE line_defs AS
SELECT * FROM (
    VALUES
        (1, 'Operating', 'Bitcoin mining operations', 'Mining cash received'),
        (2, 'Operating', 'Bitcoin mining operations', 'Mining power paid'),
        (3, 'Operating', 'Corporate operations', 'Overhead paid'),
        (4, 'Investing', 'Data center expansion', 'Data center buildout paid'),
        (5, 'Investing', 'Bitcoin mining operations', 'Mining equipment paid'),
        (6, 'Financing', 'Data center financing', 'Construction loan drawn')
) AS d(display_order, cash_flow_section, business_activity, reporting_line);

CREATE OR REPLACE TEMP TABLE months AS
SELECT (make_date(s.fiscal_year, 1, 1) + (gs.step - 1) * INTERVAL 1 MONTH)::DATE AS reporting_month
FROM scenario s
CROSS JOIN generate_series(1, (SELECT actual_months + forecast_months FROM scenario), 1) AS gs(step);

CREATE OR REPLACE TEMP TABLE monthly_lines AS
SELECT
    m.reporting_month,
    d.cash_flow_section,
    d.business_activity,
    d.reporting_line,
    CAST(coalesce(sum(t.signed_amount_usd), 0) AS BIGINT) AS signed_amount_usd,
    d.display_order,
    CASE
        WHEN m.reporting_month > make_date((SELECT fiscal_year FROM scenario), (SELECT actual_months FROM scenario), 1) THEN 'Forecast'
        ELSE 'Actual'
    END AS amount_type
FROM months m
CROSS JOIN line_defs d
LEFT JOIN cash_transactions t
    ON t.reporting_month = m.reporting_month
    AND t.reporting_line = d.reporting_line
GROUP BY m.reporting_month, d.cash_flow_section, d.business_activity, d.reporting_line, d.display_order, amount_type;

SELECT CASE
    WHEN EXISTS (
        SELECT 1
        FROM cash_transactions t
        WHERE t.reporting_line NOT IN (SELECT reporting_line FROM line_defs)
    )
    THEN error('Unknown reporting_line in cash_transactions.csv; do not remap here — fix the transformation layer.')
    ELSE 'ok'
END;

COPY (
    SELECT
        strftime(reporting_month, '%Y-%m-%d') AS reporting_month,
        cash_flow_section,
        business_activity,
        reporting_line,
        signed_amount_usd,
        display_order,
        amount_type
    FROM monthly_lines
    WHERE amount_type = 'Actual'
    ORDER BY reporting_month, display_order
) TO 'data/reporting/actual_cash_flow_lines.csv' (HEADER, DELIMITER ',');

COPY (
    SELECT
        strftime(reporting_month, '%Y-%m-%d') AS reporting_month,
        cash_flow_section,
        business_activity,
        reporting_line,
        signed_amount_usd,
        display_order,
        amount_type
    FROM monthly_lines
    WHERE amount_type = 'Forecast'
    ORDER BY reporting_month, display_order
) TO 'data/reporting/forecast_cash_flow_lines.csv' (HEADER, DELIMITER ',');

CREATE OR REPLACE TEMP TABLE monthly_summary AS
WITH pivoted AS (
    SELECT
        reporting_month,
        max(amount_type) AS amount_type,
        sum(CASE WHEN reporting_line = 'Mining cash received' THEN signed_amount_usd ELSE 0 END) AS mining_cash_received,
        sum(CASE WHEN reporting_line = 'Mining power paid' THEN signed_amount_usd ELSE 0 END) AS mining_power_paid,
        sum(CASE WHEN reporting_line = 'Overhead paid' THEN signed_amount_usd ELSE 0 END) AS overhead_paid,
        sum(CASE WHEN reporting_line = 'Data center buildout paid' THEN signed_amount_usd ELSE 0 END) AS data_center_buildout_paid,
        sum(CASE WHEN reporting_line = 'Mining equipment paid' THEN signed_amount_usd ELSE 0 END) AS mining_equipment_paid,
        sum(CASE WHEN reporting_line = 'Construction loan drawn' THEN signed_amount_usd ELSE 0 END) AS construction_loan_drawn
    FROM monthly_lines
    GROUP BY reporting_month
),
nets AS (
    SELECT
        *,
        mining_cash_received + mining_power_paid + overhead_paid AS net_operating_cash_flow,
        data_center_buildout_paid + mining_equipment_paid AS net_investing_cash_flow,
        construction_loan_drawn AS net_financing_cash_flow,
        mining_cash_received + mining_power_paid + overhead_paid
            + data_center_buildout_paid + mining_equipment_paid
            + construction_loan_drawn AS net_change_in_cash
    FROM pivoted
),
rolled AS (
    SELECT
        *,
        (SELECT available_balance_usd FROM opening_balance)
            + coalesce(
                sum(net_change_in_cash) OVER (
                    ORDER BY reporting_month
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                ),
                0
            ) AS beginning_cash
    FROM nets
)
SELECT
    reporting_month,
    amount_type,
    CAST(mining_cash_received AS BIGINT) AS mining_cash_received,
    CAST(mining_power_paid AS BIGINT) AS mining_power_paid,
    CAST(overhead_paid AS BIGINT) AS overhead_paid,
    CAST(net_operating_cash_flow AS BIGINT) AS net_operating_cash_flow,
    CAST(data_center_buildout_paid AS BIGINT) AS data_center_buildout_paid,
    CAST(mining_equipment_paid AS BIGINT) AS mining_equipment_paid,
    CAST(net_investing_cash_flow AS BIGINT) AS net_investing_cash_flow,
    CAST(construction_loan_drawn AS BIGINT) AS construction_loan_drawn,
    CAST(net_financing_cash_flow AS BIGINT) AS net_financing_cash_flow,
    CAST(net_change_in_cash AS BIGINT) AS net_change_in_cash,
    CAST(beginning_cash AS BIGINT) AS beginning_cash,
    CAST(beginning_cash + net_change_in_cash AS BIGINT) AS ending_cash
FROM rolled
ORDER BY reporting_month;

COPY (
    SELECT
        strftime(reporting_month, '%Y-%m-%d') AS reporting_month,
        amount_type,
        mining_cash_received,
        mining_power_paid,
        overhead_paid,
        net_operating_cash_flow,
        data_center_buildout_paid,
        mining_equipment_paid,
        net_investing_cash_flow,
        construction_loan_drawn,
        net_financing_cash_flow,
        net_change_in_cash,
        beginning_cash,
        ending_cash
    FROM monthly_summary
    WHERE amount_type = 'Actual'
    ORDER BY reporting_month
) TO 'data/reporting/actual_cash_summary.csv' (HEADER, DELIMITER ',');

COPY (
    SELECT
        strftime(reporting_month, '%Y-%m-%d') AS reporting_month,
        amount_type,
        mining_cash_received,
        mining_power_paid,
        overhead_paid,
        net_operating_cash_flow,
        data_center_buildout_paid,
        mining_equipment_paid,
        net_investing_cash_flow,
        construction_loan_drawn,
        net_financing_cash_flow,
        net_change_in_cash,
        beginning_cash,
        ending_cash
    FROM monthly_summary
    WHERE amount_type = 'Forecast'
    ORDER BY reporting_month
) TO 'data/reporting/forecast_cash_summary.csv' (HEADER, DELIMITER ',');

SELECT CASE
    WHEN EXISTS (
        SELECT 1
        FROM monthly_lines l
        LEFT JOIN (
            SELECT reporting_month, reporting_line, sum(signed_amount_usd) AS txn_sum
            FROM cash_transactions
            GROUP BY 1, 2
        ) t
            ON t.reporting_month = l.reporting_month
           AND t.reporting_line = l.reporting_line
        WHERE l.signed_amount_usd <> coalesce(t.txn_sum, 0)
    )
    THEN error('A reporting line does not equal the sum of its transactions')
    WHEN EXISTS (
        SELECT 1
        FROM (
            SELECT
                reporting_month,
                cash_flow_section,
                business_activity,
                sum(signed_amount_usd) AS line_sum
            FROM monthly_lines
            GROUP BY 1, 2, 3
        ) a
        LEFT JOIN (
            SELECT
                reporting_month,
                cash_flow_section,
                business_activity,
                sum(signed_amount_usd) AS txn_sum
            FROM cash_transactions
            GROUP BY 1, 2, 3
        ) t
            ON t.reporting_month = a.reporting_month
           AND t.cash_flow_section = a.cash_flow_section
           AND t.business_activity = a.business_activity
        WHERE a.line_sum <> coalesce(t.txn_sum, 0)
    )
    THEN error('An activity total does not equal the sum of its transactions')
    WHEN EXISTS (
        SELECT 1
        FROM monthly_summary s
        LEFT JOIN (
            SELECT
                reporting_month,
                sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Operating') AS operating_sum,
                sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Investing') AS investing_sum,
                sum(signed_amount_usd) FILTER (WHERE cash_flow_section = 'Financing') AS financing_sum,
                sum(signed_amount_usd) AS total_sum
            FROM cash_transactions
            GROUP BY reporting_month
        ) t
            ON t.reporting_month = s.reporting_month
        WHERE s.net_operating_cash_flow <> coalesce(t.operating_sum, 0)
           OR s.net_investing_cash_flow <> coalesce(t.investing_sum, 0)
           OR s.net_financing_cash_flow <> coalesce(t.financing_sum, 0)
           OR s.net_change_in_cash <> coalesce(t.total_sum, 0)
    )
    THEN error('A section total or net change does not equal the sum of its transactions')
    WHEN (SELECT count(*) FROM monthly_summary) <> 21
    THEN error('Expected 21 monthly summary rows')
    WHEN (SELECT count(*) FROM monthly_lines) <> 126
    THEN error('Expected 126 line rows')
    WHEN EXISTS (
        SELECT 1 FROM monthly_summary
        WHERE beginning_cash + net_change_in_cash <> ending_cash
    )
    THEN error('beginning_cash + net_change_in_cash != ending_cash')
    WHEN (SELECT count(*) FROM monthly_summary WHERE amount_type = 'Actual') <> 9
    THEN error('Expected 9 Actual months')
    WHEN (SELECT count(*) FROM monthly_summary WHERE amount_type = 'Forecast') <> 12
    THEN error('Expected 12 Forecast months')
    WHEN (SELECT max(reporting_month) FROM monthly_summary) <> DATE '2027-09-01'
    THEN error('Last reporting month is not September 2027')
    WHEN (SELECT sum(net_change_in_cash) FROM monthly_summary) <> -7000012
    THEN error('Change in cash through September 2027 != -7000012')
    WHEN (SELECT ending_cash FROM monthly_summary ORDER BY reporting_month DESC LIMIT 1) <> -5000012
    THEN error('September 2027 ending cash != -5000012')
    WHEN EXISTS (
        SELECT 1
        FROM monthly_summary
        WHERE amount_type = 'Forecast'
            AND (
                mining_cash_received <> 433333
                OR mining_power_paid <> -266667
                OR overhead_paid <> -66667
                OR data_center_buildout_paid <> -600000
                OR mining_equipment_paid <> 0
                OR construction_loan_drawn <> 0
                OR net_change_in_cash <> -500001
            )
    )
    THEN error('A forecast month does not match the 9+12 drivers')
    ELSE 'OK  build_monthly_report.sql'
END;
