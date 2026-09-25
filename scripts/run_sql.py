"""Run the DuckDB SQL pipeline: transform actuals, calculate the forecast, then build monthly reporting CSVs.

Usage (from repo root):
    python scripts/run_sql.py
"""

from __future__ import annotations

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "scripts" / "sql"


def run_sql(name: str) -> None:
    path = SQL_DIR / name
    con = duckdb.connect()
    con.execute(path.read_text(encoding="utf-8"))
    row = con.fetchone()
    print(row[0] if row else f"OK  {name}")


def main() -> None:
    run_sql("transform_actuals.sql")
    run_sql("build_forecast.sql")
    run_sql("build_monthly_report.sql")


if __name__ == "__main__":
    main()
