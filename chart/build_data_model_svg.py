"""Write chart/data-model.svg, the README copy of the Data Model chart.

The chart itself lives in cashflow-forecast.html as HTML/CSS (.pipe-board), which
GitHub cannot render inside a README. This redraws the same panels and tier
descriptions as flat SVG so both stay in step. Edit the tiers below and rerun:

    python chart/build_data_model_svg.py
"""

from pathlib import Path

OUT = Path(__file__).resolve().parent / "data-model.svg"

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

WIDTH, HEIGHT = 1106, 500
MARGIN = 10
GAP = 10
SIDE_W = 236
PANEL_Y = MARGIN
PANEL_H = HEIGHT - 2 * MARGIN
TITLE_DY = 24
CHIP_H = 34
CHIP_GAP = 8
ARROW_W = 22

SOURCES = [
    "Structured Data\n(ERP, Vena, etc)",
    "Unstructured Data\n(pdf, wiki pages etc)",
    "Other Internal\nSources",
]
REPORTS = [
    "BI Tools and Dashboard\n(Tableau, Power BI, Sigma, etc)",
    "LLM Applications",
]
TIERS = [
    ("Raw Tier", TEAL,
     "Retains the original records and their history to support data lineage"),
    ("Transformed Tier", BLUE_SOFT,
     "Validates, cleans, and standardizes the data while maintaining source traceability"),
    ("Reporting Tier", VIOLET,
     "Organizes data into purpose-specific metrics and tables, including plans, forecasts, actuals, and related analysis"),
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


def wrap(text, width):
    lines, current = [], ""
    for word in text.split():
        trial = word if not current else f"{current} {word}"
        if len(trial) <= width:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def blurb(text, x, w, y):
    for i, line in enumerate(wrap(text, max(16, int(w / 6.2)))):
        label(x, y + i * 15, line, size=11)


def chips(items, x, w, y, h=CHIP_H):
    top = y
    for item in items:
        lines = item.split("\n")
        height = h if len(lines) == 1 else 16 + 14 * len(lines)
        rect(x, top, w, height, CHIP_FILL, r=10, stroke=CHIP_STROKE)
        if len(lines) == 1:
            label(x + w / 2, top + height / 2 + 4, lines[0])
        else:
            first = top + (height - 14 * (len(lines) - 1)) / 2 + 4
            for j, line in enumerate(lines):
                label(x + w / 2, first + j * 14, line, size=11)
        top += height + CHIP_GAP


def rail(x, title, items, fill, width=SIDE_W):
    rect(x, PANEL_Y, width, PANEL_H, fill)
    label(x + width / 2, PANEL_Y + TITLE_DY, title, weight=700)
    chips(items, x + 12, width - 24, PANEL_Y + TITLE_DY + 12)


alt = "Data sources feed the FP&amp;A data model, which feeds output"
parts.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" '
    f'width="{WIDTH}" height="{HEIGHT}" role="img" aria-label="{alt}" font-family="{FONT}">'
)
parts.append(f"  <title>{alt}</title>")
parts.append("  <g>")

rail(MARGIN, "Data Sources", SOURCES, TEAL, SIDE_W)

model_x = MARGIN + SIDE_W + GAP
model_w = WIDTH - 2 * MARGIN - 2 * SIDE_W - 2 * GAP
rect(model_x, PANEL_Y, model_w, PANEL_H, BLUE)
label(model_x + model_w / 2, PANEL_Y + TITLE_DY, "FP&amp;A Data Model", weight=700)

box_x = model_x + 10
box_w = model_w - 20
sem_y = PANEL_Y + TITLE_DY + 12
sem_h = 154
rect(box_x, sem_y, box_w, sem_h, INNER_FILL, r=12)
label(box_x + box_w / 2, sem_y + 20, "Semantic Layer", weight=700)
semantics = [
    ("Business Entities", "Customers, vendors, invoices, payments, departments, and legal entities"),
    ("Metrics and KPIs", "i.e. Monthly cash outflow = qualifying cash payments made during the month. Forecast accuracy is measured using an agreed calculation and compared with a target."),
    ("Security and Access Control", "Business managers see their own department’s expenses. Accountants see company-wide totals; individual salary details are restricted to authorized users."),
]
sem_gap = 8
sem_card_w = (box_w - 24 - sem_gap * (len(semantics) - 1)) / len(semantics)
sem_card_h = 110
sem_fills = [TEAL, BLUE_SOFT, VIOLET]
for i, (name, detail) in enumerate(semantics):
    sx = box_x + 12 + i * (sem_card_w + sem_gap)
    sy = sem_y + 32
    rect(sx, sy, sem_card_w, sem_card_h, sem_fills[i], r=10)
    name_lines = wrap(name, max(14, int(sem_card_w / 6.4)))
    name_y = sy + 18
    for j, line in enumerate(name_lines):
        label(sx + sem_card_w / 2, name_y + j * 13, line, size=11, weight=700)
    if detail:
        for j, line in enumerate(wrap(detail, max(18, int(sem_card_w / 5.6)))):
            label(sx + sem_card_w / 2, name_y + 14 * len(name_lines) + 6 + j * 12, line, size=10)

dim_y = sem_y + sem_h + 8
dim_h = PANEL_Y + PANEL_H - 10 - dim_y
rect(box_x, dim_y, box_w, dim_h, INNER_FILL, r=12)
label(box_x + box_w / 2, dim_y + 22, "Dimensional Models", weight=700)

inner_x = box_x + 10
inner_w = box_w - 20
card_y = dim_y + 34
card_h = dim_h - 46
card_w = (inner_w - (len(TIERS) - 1) * ARROW_W) / len(TIERS)

x = inner_x
for i, (title, fill, text) in enumerate(TIERS):
    rect(x, card_y, card_w, card_h, fill, r=12)
    label(x + card_w / 2, card_y + 22, title, weight=700)
    blurb(text, x + card_w / 2, card_w - 20, card_y + 42)
    if i < len(TIERS) - 1:
        ax = x + card_w
        ay = card_y + card_h / 2
        parts.append(f'    <path d="M{ax + 5:.0f} {ay:.0f} H{ax + ARROW_W - 9:.0f}" '
                     f'stroke="{ARROW}" stroke-width="1.5" fill="none"/>')
        parts.append(f'    <path d="M{ax + ARROW_W - 10:.0f} {ay - 4:.0f} l5 4 l-5 4z" fill="{ARROW}"/>')
    x += card_w + ARROW_W

rail(WIDTH - MARGIN - SIDE_W, "Output", REPORTS, VIOLET_DEEP, SIDE_W)

parts.append("  </g>")
parts.append("</svg>")

OUT.write_text("\n".join(parts) + "\n", encoding="utf-8", newline="\n")
print(f"wrote {OUT.relative_to(Path.cwd())}" if OUT.is_relative_to(Path.cwd()) else f"wrote {OUT}")
