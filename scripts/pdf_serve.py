#!/usr/bin/env python3
"""
pdf_serve.py — Serve a PDF as plain text over stdout (drop-in for reading PDFs).

Usage:  python3 pdf_serve.py <file.pdf> [--pages 2-5] [--head 100]

Designed for electronics datasheets and schematics.
Uses pdftotext (poppler) for layout-preserving text extraction.
"""
import subprocess, sys, os, argparse

def main():
    p = argparse.ArgumentParser()
    p.add_argument("file")
    p.add_argument("--pages", help="Page range, e.g. '2-5' or '3'")
    p.add_argument("--head", type=int, help="Show only first N lines")
    args = p.parse_args()
    if not os.path.isfile(args.file):
        print(f"ERROR: {args.file} not found", file=sys.stderr)
        sys.exit(1)
    cmd = ["pdftotext", "-layout"]
    if args.pages:
        if "-" in args.pages:
            a, b = args.pages.split("-")
            cmd += ["-f", a, "-l", b]
        else:
            cmd += ["-f", args.pages, "-l", args.pages]
    cmd += [args.file, "-"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    lines = r.stdout.split("\n")
    if args.head:
        lines = lines[:args.head]
    print("\n".join(lines))

if __name__ == "__main__":
    main()
