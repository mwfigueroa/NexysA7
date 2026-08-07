#!/usr/bin/env python3
"""Parse tb_top.vcd and print a text waveform summary."""
import re
from pathlib import Path

vcd = Path(__file__).resolve().parent / "tb_top.vcd"
raw = vcd.read_text(encoding="latin-1", errors="replace")

# ── Map signal code → name ──────────────────────────────────────────
signals = {}
for m in re.finditer(r'\$var\s+\w+\s+(\d+)\s+(\S+)\s+(\S+)\s+\$end', raw):
    width, code, name = m.groups()
    signals[code] = name.strip()

# ── Parse time-value pairs (sample every 50 us) ─────────────────────
records = []
current_time = 0
snap = {}
for line in raw.split("\n"):
    line = line.strip()
    if line.startswith("#"):
        if snap and current_time % 50000 == 0:
            records.append((current_time, dict(snap)))
        current_time = int(line[1:])
        snap = {}
    elif line and line[0] in "01x":
        code = line[1:]
        if code in signals:
            snap[signals[code]] = line[0]

if snap:
    records.append((current_time, snap))

# ── Find interesting signal codes ───────────────────────────────────
def find_code(sigs, name):
    for c, n in sigs.items():
        if n == name:
            return c
    return None

clk_code = find_code(signals, "CLK100MHZ")
freq_code = find_code(signals, "FREQ_IN")
gd_code = find_code(signals, "gate_done")
tx_code = find_code(signals, "UART_TXD")
an_codes = [find_code(signals, f"SSEG_AN[{i}]") for i in range(6)]

# ── Print table ─────────────────────────────────────────────────────
print("=== VCD Waveform Summary (tb_top.vcd) ===")
print(f"Signals: {len(signals)},  Time snapshots: {len(records)}")
print()
hdr = f"{'Time(us)':>8s}  {'CLK':>4s}  {'FREQ_IN':>7s}  {'gate_done':>9s}  {'TX':>4s}  {'SSEG_AN[5:0]':>12s}"
print(hdr)
print("-" * len(hdr))

for t, v in records[:25]:
    clk = v.get("CLK100MHZ", "?")
    freq = v.get("FREQ_IN", "?")
    gd = v.get("gate_done", "?")
    tx = v.get("UART_TXD", "?")
    an = "".join(v.get(f"SSEG_AN[{i}]", "?") for i in range(5, -1, -1))
    gate_marker = " <-- GATE" if gd == "1" else ""
    print(f"{t/1000:8.1f}  {clk:>4s}  {freq:>7s}  {gd:>9s}  {tx:>4s}  {an:>12s}{gate_marker}")

print()
print("Notes:")
print("  GATE = 10,000 cycles @ 100 MHz = 100 us")
print("  FREQ_IN = 100 kHz square wave → 10 edges/gate")
print("  freq_cal = 10 * 1073/1000 = 10 kHz")
print("  SSEG_AN active-low: 0 = digit ON, scans left to right")
print("  TX: 0 = transmitting (start bit / data), 1 = idle")
