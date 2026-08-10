#!/usr/bin/env python3
"""
pdf_extract.py — Swiss-army knife for electronics PDFs (datasheets, schematics, manuals).

Usage:
  python3 pdf_extract.py <file.pdf> [--mode text|tables|metadata|search] [options]

Modes:
  text      Extract all text with page layout (default). Good for datasheets/manuals.
  tables    Extract tables (pinouts, electrical characteristics, BOM).
  metadata  Show PDF metadata + outline/TOC.
  search    Search for a keyword across all pages.
  schem     Extract text from schematic PDFs (labels, net names, component refs).

Tools required in WSL:
  apt install poppler-utils           (pdftotext, pdfinfo, pdftoppm)
  pip3 install pdfplumber pymupdf    (advanced extraction)
"""

import argparse, json, os, subprocess, sys

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def run_pdftotext(path: str, extra: list[str] | None = None) -> str:
    cmd = ["pdftotext"] + (extra or []) + [path, "-"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0 and "Syntax Warning" not in r.stderr:
        sys.stderr.write(f"pdftotext warning: {r.stderr}")
    return r.stdout

def require(pkg: str):
    try: __import__(pkg); return True
    except ImportError:
        sys.stderr.write(f"ERROR: pip3 install {pkg}\n")
        return False

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
def mode_text(path: str, args):
    """pdftotext -layout: preserves columns and indentation."""
    extra = ["-layout"]
    if args.start_page: extra += ["-f", str(args.start_page)]
    if args.end_page:   extra += ["-l", str(args.end_page)]
    print(run_pdftotext(path, extra))

def mode_metadata(path: str, args):
    import pymupdf as fitz
    doc = fitz.open(path)
    meta = doc.metadata
    print(json.dumps({
        "pages": len(doc),
        "title": meta.get("title"),
        "author": meta.get("author"),
        "subject": meta.get("subject"),
        "format": meta.get("format"),
        "producer": meta.get("producer"),
    }, indent=2))
    toc = doc.get_toc()
    if toc:
        print("\n--- Table of Contents ---")
        for level, title, page in toc:
            print(f"{'  ' * (level - 1)}{title}  (p.{page})")
    doc.close()

def mode_tables(path: str, args):
    if not require("pdfplumber"): sys.exit(1)
    import pdfplumber
    with pdfplumber.open(path) as pdf:
        pages = pdf.pages
        if args.page:
            pages = [pdf.pages[args.page - 1]]
        for p in pages:
            tables = p.extract_tables()
            if not tables:
                continue
            for ti, table in enumerate(tables):
                print(f"\n=== Page {p.page_number}, Table {ti + 1} ===")
                print(format_table(table))

def format_table(table: list[list[str | None]]) -> str:
    if not table: return "(empty)"
    cols = len(table[0])
    widths = [0] * cols
    for row in table:
        for ci, cell in enumerate(row):
            if ci < cols and cell:
                widths[ci] = max(widths[ci], len(str(cell)))
    lines = []
    for ri, row in enumerate(table):
        line = " | ".join(str(row[ci] or "").ljust(widths[ci]) for ci in range(cols))
        lines.append(line)
        if ri == 0 and row[0]:
            lines.append("-+-".join("-" * w for w in widths))
    return "\n".join(lines)

def mode_search(path: str, args):
    if not require("pymupdf"): sys.exit(1)
    import pymupdf
    doc = pymupdf.open(path)
    for pi in range(len(doc)):
        page = doc[pi]
        found = page.search_for(args.query)
        if found:
            text = page.get_text("text", clip=found[0] if found else None)
            print(f"[p.{pi + 1}] {text.strip()[:200]}")
    doc.close()

def mode_schem(path: str, args):
    """pdftotext with -raw -f/-l, then grep for component refs and net names."""
    text = run_pdftotext(path, ["-raw"])
    lines = text.split("\n")
    import re
    # Patterns for schematic text
    patterns = {
        "component_refs": re.compile(r'\b([RCLDUJQTP]\d+)\b'),
        "net_names":      re.compile(r'\b(NET|SIG|VCC|VDD|GND|VIN|VOUT|CLK|RST|INT|SCL|SDA|MISO|MOSI|CS|TX|RX)[\w_]*\b', re.I),
        "values":         re.compile(r'\b(\d+\.?\d*[kMmunpµ]?[A-Za-z]*)\b'),
        "pin_numbers":    re.compile(r'\b(P?\d+)\b'),
    }
    for line in lines:
        line = line.strip()
        if not line or len(line) < 2: continue
        tags = []
        for tag, pat in patterns.items():
            if pat.search(line):
                tags.append(tag)
        if tags:
            print(f"[{','.join(tags)}] {line}")

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser(description="PDF extractor for electronics")
    p.add_argument("file", help="PDF file path")
    p.add_argument("--mode", choices=["text","tables","metadata","search","schem"],
                   default="text")
    p.add_argument("--start-page", type=int, help="First page")
    p.add_argument("--end-page",   type=int, help="Last page")
    p.add_argument("--page",       type=int, help="Single page (for tables)")
    p.add_argument("--query",      help="Search query")
    p.add_argument("--json", action="store_true", help="JSON output")
    args = p.parse_args()
    if not os.path.isfile(args.file):
        sys.stderr.write(f"File not found: {args.file}\n")
        sys.exit(1)
    if args.mode == "text":     mode_text(args.file, args)
    elif args.mode == "metadata": mode_metadata(args.file, args)
    elif args.mode == "tables": mode_tables(args.file, args)
    elif args.mode == "search": mode_search(args.file, args)
    elif args.mode == "schem":  mode_schem(args.file, args)

if __name__ == "__main__":
    main()
