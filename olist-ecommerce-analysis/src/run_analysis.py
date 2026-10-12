"""
Run the full Olist analysis end to end.

    python src/run_analysis.py

1. Loads the 8 Olist CSV files into an in-memory DuckDB database
2. Runs every query in sql/01_analysis_queries.sql
3. Saves each result to outputs/qN_<name>.csv (e.g. q7_delivery_vs_reviews.csv)
4. Writes docs/data.js, which feeds the interactive dashboard (docs/index.html)
"""
from pathlib import Path
import json
import re

import duckdb

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR, OUT_DIR, DOCS_DIR = ROOT / "sql", ROOT / "outputs", ROOT / "docs"


def load_tables(con):
    load_sql = (SQL_DIR / "00_load_tables.sql").read_text()
    load_sql = load_sql.replace("'data/", f"'{(ROOT / 'data').as_posix()}/")
    for stmt in load_sql.split(";"):
        if "CREATE" in stmt:
            con.execute(stmt)


def read_queries():
    """Split the analysis file into {number: (title, sql)} using the '-- QN.' headers."""
    text = (SQL_DIR / "01_analysis_queries.sql").read_text()
    queries = {}
    for block in text.split(";"):
        match = re.search(r"-- Q(\d+)\.\s*(.+)", block)
        if match and "SELECT" in block:
            queries[int(match.group(1))] = (match.group(2).strip(), block)
    return queries


FILE_NAMES = {1: "kpis", 2: "monthly_trend", 3: "top_categories", 4: "repeat_rate",
              5: "rfm_segments", 6: "cohort_retention", 7: "delivery_vs_reviews",
              8: "late_delivery_by_state", 9: "payment_methods"}


def main():
    OUT_DIR.mkdir(exist_ok=True)
    con = duckdb.connect()
    load_tables(con)

    results = {}
    for n, (title, query) in sorted(read_queries().items()):
        df = con.execute(query).df()
        df.to_csv(OUT_DIR / f"q{n}_{FILE_NAMES.get(n, n)}.csv", index=False)
        results[n] = df
        print(f"Q{n}: {title}  ->  {len(df)} rows")

    kpi = results[1].iloc[0]
    monthly = results[2]
    cohort = results[6]
    cohort = cohort[(cohort.month_number >= 1) & (cohort.month_number <= 6)]

    data = {
        "kpi": {k: float(kpi[k]) for k in ["orders", "customers", "revenue_brl", "avg_order_value_brl"]},
        "repeat": {k: float(results[4].iloc[0][k]) for k in ["customers", "repeat_customers", "repeat_rate_pct"]},
        "monthly": {
            "month": monthly.month.dt.strftime("%Y-%m").tolist(),
            "revenue": monthly.revenue_brl.round(0).tolist(),
            "orders": monthly.orders.tolist(),
            "aov": monthly.aov_brl.tolist(),
        },
        "categories": results[3][["category", "revenue_brl", "share_pct", "orders"]].to_dict("records"),
        "rfm": results[5][["segment", "customers", "pct_customers", "pct_revenue", "avg_recency_days"]].to_dict("records"),
        "cohort": {
            "cohorts": sorted(cohort.cohort_month.dt.strftime("%Y-%m").unique().tolist()),
            "cells": [
                {"c": r.cohort_month.strftime("%Y-%m"), "m": int(r.month_number), "v": float(r.retention_pct)}
                for r in cohort.itertuples()
            ],
        },
        "delivery": results[7].to_dict("records"),
        "states": results[8].to_dict("records"),
        "payments": results[9].to_dict("records"),
    }
    DOCS_DIR.mkdir(exist_ok=True)
    (DOCS_DIR / "data.js").write_text("window.OLIST = " + json.dumps(data, indent=1, default=float) + ";\n")
    print(f"\nSaved {len(results)} result files to outputs/ and dashboard data to docs/data.js")


if __name__ == "__main__":
    main()
