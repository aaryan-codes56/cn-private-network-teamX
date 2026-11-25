#!/usr/bin/env python3
"""
Build docs/PHASE2_REPORT.pdf from docs/PHASE2_REPORT.md.

  python3 -m venv ~/rl && ~/rl/bin/pip install reportlab     # once
  ~/rl/bin/python scripts/build_report_pdf.py                # re-run after filling in the results
  ~/rl/bin/python scripts/build_report_pdf.py docs/OTHER.md  # any other doc -> docs/OTHER.pdf

Supports the subset of Markdown used in the report: # / ## headings, paragraphs,
"- " bullets, | tables |, ![image](path), **bold**, `code`, [links](...).
Unfilled "⟨fill in⟩" placeholders are rendered highlighted so none are missed.
"""
import os
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, ListFlowable, ListItem, Paragraph,
                                SimpleDocTemplate, Spacer, Table, TableStyle)

TITLE = "Report"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "PHASE2_REPORT.md")
OUT = os.path.splitext(SRC)[0] + ".pdf"

# ---------------------------------------------------------------- fonts
FONT_DIR = "/System/Library/Fonts/Supplemental"
try:
    pdfmetrics.registerFont(TTFont("Body", f"{FONT_DIR}/Arial.ttf"))
    pdfmetrics.registerFont(TTFont("Body-Bold", f"{FONT_DIR}/Arial Bold.ttf"))
    pdfmetrics.registerFont(TTFont("Body-Italic", f"{FONT_DIR}/Arial Italic.ttf"))
    pdfmetrics.registerFont(TTFont("Body-BoldItalic", f"{FONT_DIR}/Arial Bold Italic.ttf"))
    pdfmetrics.registerFontFamily("Body", normal="Body", bold="Body-Bold",
                                  italic="Body-Italic", boldItalic="Body-BoldItalic")
    pdfmetrics.registerFont(TTFont("Mono", f"{FONT_DIR}/Courier New.ttf"))
    BODY, BOLD, MONO = "Body", "Body-Bold", "Mono"
except Exception:  # not macOS: fall back to the PDF core fonts
    BODY, BOLD, MONO = "Helvetica", "Helvetica-Bold", "Courier"

NAVY, TEAL, INK, MUTED = colors.HexColor("#1e3a5f"), colors.HexColor("#0f766e"), \
    colors.HexColor("#1f2937"), colors.HexColor("#4b5563")
RULE, HEAD_BG, ZEBRA = colors.HexColor("#cbd5e1"), colors.HexColor("#1e3a5f"), colors.HexColor("#f1f5f9")

ST = {
    "title": ParagraphStyle("title", fontName=BOLD, fontSize=21, leading=26, textColor=NAVY, spaceAfter=4),
    "sub": ParagraphStyle("sub", fontName=BODY, fontSize=10, leading=14, textColor=MUTED, spaceAfter=2),
    "h2": ParagraphStyle("h2", fontName=BOLD, fontSize=14.5, leading=19, textColor=NAVY, spaceBefore=14, spaceAfter=6),
    "body": ParagraphStyle("body", fontName=BODY, fontSize=9.8, leading=14, textColor=INK, spaceAfter=6, alignment=TA_LEFT),
    "quote": ParagraphStyle("quote", fontName=BODY, fontSize=9.8, leading=14, textColor=INK, leftIndent=10,
                            borderPadding=(6, 8, 6, 8), backColor=colors.HexColor("#eef4fb"),
                            borderColor=colors.HexColor("#1e3a5f"), borderWidth=0, spaceBefore=4, spaceAfter=10),
    "cell": ParagraphStyle("cell", fontName=BODY, fontSize=8.2, leading=10.6, textColor=INK),
    "headcell": ParagraphStyle("headcell", fontName=BOLD, fontSize=8.4, leading=10.6, textColor=colors.white),
}


def inline(text):
    """Markdown inline -> ReportLab mini-HTML."""
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    codes = []

    def keep_code(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"
    text = re.sub(r"`([^`]+)`", keep_code, text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)                 # links -> text
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", text)
    text = re.sub(r"\x00(\d+)\x00",
                  lambda m: f'<font name="{MONO}" color="#0f3d63">{codes[int(m.group(1))]}</font>', text)
    # highlight blanks still to be filled in
    text = re.sub(r"⟨([^⟩]*)⟩", r'<font backColor="#fde68a" color="#7c2d12"><b>[\1]</b></font>', text)
    return text


def table(rows, width):
    ncol = len(rows[0])
    # column widths proportional to (clipped) content length
    lens = [max(min(len(r[c]) if c < len(r) else 0, 60) for r in rows) + 6 for c in range(ncol)]
    total = sum(lens)
    widths = [max(width * l / total, 11 * mm) for l in lens]
    extra = sum(widths) - width
    if extra > 0:  # take the overflow from the widest column
        k = widths.index(max(widths)); widths[k] -= extra
    data = []
    for i, r in enumerate(rows):
        r = (r + [""] * ncol)[:ncol]
        style = ST["headcell"] if i == 0 else ST["cell"]
        data.append([Paragraph(inline(c), style) for c in r])
    t = Table(data, colWidths=widths, repeatRows=1)
    ts = [("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
          ("VALIGN", (0, 0), (-1, -1), "TOP"),
          ("GRID", (0, 0), (-1, -1), 0.4, RULE),
          ("TOPPADDING", (0, 0), (-1, -1), 3.2), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.2),
          ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4)]
    for i in range(2, len(data), 2):
        ts.append(("BACKGROUND", (0, i), (-1, i), ZEBRA))
    t.setStyle(TableStyle(ts))
    return t


def split_row(line):
    cells = line.strip().strip("|").split("|")
    # re-join cells that were split on an escaped pipe "\|"
    out = []
    for c in cells:
        if out and out[-1].endswith("\\"):
            out[-1] = out[-1][:-1] + "|" + c
        else:
            out.append(c)
    return [c.strip() for c in out]


def build():
    global TITLE
    lines = open(SRC, encoding="utf-8").read().splitlines()
    TITLE = next((l[2:].split(":")[0].split("(")[0].strip() for l in lines if l.startswith("# ")), "Report")
    doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=17 * mm, rightMargin=17 * mm,
                            topMargin=16 * mm, bottomMargin=16 * mm,
                            title=TITLE, author="TeamX")
    W = doc.width
    story, para, i = [], [], 0

    def flush():
        if para:
            story.append(Paragraph(inline(" ".join(para)), ST["body"]))
            para.clear()

    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        if not s:
            flush(); i += 1; continue
        if s.startswith("# "):
            flush(); story.append(Paragraph(inline(s[2:]), ST["title"]))
            story.append(Spacer(1, 2))
        elif s.startswith("## "):
            flush(); story.append(Paragraph(inline(s[3:]), ST["h2"]))
        elif s.startswith("!["):
            flush()
            m = re.match(r"!\[[^\]]*\]\(([^)]+)\)", s)
            path = os.path.join(ROOT, "docs", m.group(1))
            if os.path.exists(path):
                img = Image(path)
                scale = min(W / img.imageWidth, 105 * mm / img.imageHeight)
                img.drawWidth, img.drawHeight = img.imageWidth * scale, img.imageHeight * scale
                story += [Spacer(1, 4), img, Spacer(1, 6)]
        elif s.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                r = split_row(lines[i])
                if not all(re.fullmatch(r":?-{2,}:?", c) for c in r):
                    rows.append(r)
                i += 1
            story += [table(rows, W), Spacer(1, 8)]
            continue
        elif s.startswith("> "):
            flush(); story.append(Paragraph(inline(s[2:]), ST["quote"]))
        elif s.startswith("- "):
            flush()
            items = []
            while i < len(lines) and lines[i].strip().startswith("- "):
                items.append(ListItem(Paragraph(inline(lines[i].strip()[2:]), ST["body"]), leftIndent=12))
                i += 1
            story.append(ListFlowable(items, bulletType="bullet", start="•", leftIndent=12, bulletFontName=BODY,
                                      bulletFontSize=10, bulletOffsetY=-1))
            continue
        elif story and len(story) <= 2 and s.startswith("**Team"):
            story.append(Paragraph(inline(s), ST["sub"]))        # header lines under the title
        elif s.startswith("**Course"):
            flush(); story.append(Paragraph(inline(s), ST["sub"])); story.append(Spacer(1, 8))
        else:
            para.append(s)
        i += 1
    flush()

    def footer(canvas, d):
        canvas.saveState()
        canvas.setFont(BODY, 8)
        canvas.setFillColor(MUTED)
        canvas.drawString(d.leftMargin, 9 * mm, f"TeamX · Private Network Service Platform · {TITLE}")
        canvas.drawRightString(A4[0] - d.rightMargin, 9 * mm, f"Page {d.page}")
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    blanks = open(SRC, encoding="utf-8").read().count("⟨")
    print(f"wrote {os.path.relpath(OUT, ROOT)}" + (f"  ({blanks} blanks still to fill in)" if blanks else ""))


if __name__ == "__main__":
    sys.exit(build())
