"""Write docs/data-model.svg, the README copy of the Data Model chart.

The chart itself lives in cashflow-forecast.html as HTML/CSS (.pipe-board), which
GitHub cannot render inside a README. This redraws the same panels, tiers, and
file names as flat SVG so both stay in step. Edit the tiers below and rerun:

    python scripts/build_data_model_svg.py
"""

from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "docs" / "data-model.svg"

FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
INK = "#1f2430"
CHIP_FILL = "#ffffff"
CHIP_STROKE = "#eceef5"
ARROW = "#b7bdd0"
INNER_FILL = "#fbfbfe"
TEAL = "#e8f7f2"
BLUE = "#e8eefb"
BLUE_SOFT = "#eef2fb"
VIOLET = "#f1eef8"
VIOLET_DEEP = "#eee9f6"

WIDTH, HEIGHT = 1040, 300
MARGIN = 10
GAP = 10
RAIL_W = 170
PANEL_Y = MARGIN
PANEL_H = HEIGHT - 2 * MARGIN
TITLE_DY = 24
CHIP_H = 34
CHIP_GAP = 8
ARROW_W = 22

SOURCES = ["ERP", "Planning tools", "Operational systems"]
REPORTS = ["Tableau", "Power BI", "Static HTML", "AI workflows"]
TIERS = [
    ("Raw Tier", TEAL,
     ["bitcoin_sales", "operating_payments", "capital_payments", "loan_draws", "bank_balance"]),
    ("Transformed Tier", BLUE_SOFT,
     ["activity_mapping", "cash_transactions", "opening_balance"]),
    ("Reporting Tier", VIOLET,
     ["monthly_cash_flow_lines", "monthly_cash_summary"]),
]

parts = []


def rect(x, y, w, h, fill, r=16, stroke=None):
    tag = f'    <rect x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" rx="{r}" ry="{r}" fill="{fill}"'
    if stroke:
        tag += f' stroke="{stroke}"'
    parts.append(tag + "/>")


def label(x, y, s, weight=600, size=12):
    parts.append(
        f'    <text x="{x:.0f}" y="{y:.0f}" font-size="{size}" font-weight="{weight}" '
        f'text-anchor="middle" fill="{INK}">{s}</text>'
    )


def chips(items, x, w, y, h=CHIP_H):
    for i, item in enumerate(items):
        top = y + i * (h + CHIP_GAP)
        rect(x, top, w, h, CHIP_FILL, r=10, stroke=CHIP_STROKE)
        label(x + w / 2, top + h / 2 + 4, item)


def rail(x, title, items, fill):
    rect(x, PANEL_Y, RAIL_W, PANEL_H, fill)
    label(x + RAIL_W / 2, PANEL_Y + TITLE_DY, title, weight=700)
    chips(items, x + 12, RAIL_W - 24, PANEL_Y + TITLE_DY + 12)


alt = "Data sources feed the FP&amp;A data model, which feeds reports"
parts.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" '
    f'width="{WIDTH}" height="{HEIGHT}" role="img" aria-label="{alt}" font-family="{FONT}">'
)
parts.append(f"  <title>{alt}</title>")
parts.append("  <g>")

rail(MARGIN, "Data Sources", SOURCES, TEAL)

model_x = MARGIN + RAIL_W + GAP
model_w = WIDTH - 2 * MARGIN - 2 * RAIL_W - 2 * GAP
rect(model_x, PANEL_Y, model_w, PANEL_H, BLUE)
label(model_x + model_w / 2, PANEL_Y + TITLE_DY, "FP&amp;A Data Model", weight=700)

inner_x = model_x + 10
inner_y = PANEL_Y + TITLE_DY + 12
inner_w = model_w - 20
inner_h = PANEL_H - (TITLE_DY + 12) - 10
rect(inner_x, inner_y, inner_w, inner_h, INNER_FILL, r=12)

card_w = (inner_w - 20 - (len(TIERS) - 1) * ARROW_W) / len(TIERS)
card_y = inner_y + 10
card_h = inner_h - 20

x = inner_x + 10
for i, (title, fill, items) in enumerate(TIERS):
    rect(x, card_y, card_w, card_h, fill, r=12)
    label(x + card_w / 2, card_y + 22, title, weight=700)
    chips(items, x + 8, card_w - 16, card_y + 32, h=30)
    if i < len(TIERS) - 1:
        ax = x + card_w
        ay = card_y + card_h / 2
        parts.append(f'    <path d="M{ax + 5:.0f} {ay:.0f} H{ax + ARROW_W - 9:.0f}" '
                     f'stroke="{ARROW}" stroke-width="1.5" fill="none"/>')
        parts.append(f'    <path d="M{ax + ARROW_W - 10:.0f} {ay - 4:.0f} l5 4 l-5 4z" fill="{ARROW}"/>')
    x += card_w + ARROW_W

rail(WIDTH - MARGIN - RAIL_W, "Reports", REPORTS, VIOLET_DEEP)

parts.append("  </g>")
parts.append("</svg>")

OUT.write_text("\n".join(parts) + "\n", encoding="utf-8", newline="\n")
print(f"wrote {OUT.relative_to(Path.cwd())}" if OUT.is_relative_to(Path.cwd()) else f"wrote {OUT}")
