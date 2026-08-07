#!/usr/bin/env python3
"""
Programador Nexys A7 desde OpenCode.

Usa OpenFPGALoader (WSL) si esta disponible,
o Vivado Lab Edition si esta instalado.
"""

import subprocess
import sys
import os
from pathlib import Path

BITSTREAM_DIR = Path(r"P:\NexysA7\bitstreams")
VIVADO_LAB = Path(r"P:\NexysA7\Vivado_Lab\bin\vivado_lab.bat")

def find_bitstream():
    """Encuentra el ultimo .bit en el directorio"""
    bits = list(BITSTREAM_DIR.glob("*.bit"))
    if not bits:
        print("ERROR: No hay archivos .bit en", BITSTREAM_DIR)
        return None
    latest = max(bits, key=lambda p: p.stat().st_mtime)
    return latest

def program_openfpga(bitfile):
    """Programar via OpenFPGALoader en WSL"""
    wsl_bitfile = str(bitfile).replace("\\", "/").replace("P:", "/mnt/p")
    cmd = ["wsl", "openFPGALoader", "-b", "nexys_a7", wsl_bitfile]
    print(f"Ejecutando: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print("ERROR:", result.stderr)
        return False
    print("Programacion exitosa (OpenFPGALoader)")
    return True

def program_vivado(bitfile):
    """Programar via Vivado Lab Edition"""
    if not VIVADO_LAB.exists():
        print("ERROR: Vivado Lab no encontrado en", VIVADO_LAB)
        print("Descargar de: https://www.xilinx.com/support/download.html")
        return False
    
    tcl_script = Path(r"P:\NexysA7\scripts\program.tcl")
    cmd = [str(VIVADO_LAB), "-mode", "batch", "-source", str(tcl_script)]
    print(f"Ejecutando: Vivado Lab")
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout)
    return result.returncode == 0

def main():
    print("=" * 50)
    print("  Nexys A7 Programmer")
    print("=" * 50)
    
    bitfile = find_bitstream()
    if not bitfile:
        sys.exit(1)
    
    print(f"Bitstream: {bitfile.name}")
    print(f"  ({bitfile.stat().st_size / 1024 / 1024:.1f} MB)")
    print()
    
    # Intentar OpenFPGALoader primero (mas rapido)
    print("[1] Probando OpenFPGALoader...")
    if program_openfpga(bitfile):
        return
    
    # Fallback a Vivado Lab
    print("\n[2] Probando Vivado Lab Edition...")
    if program_vivado(bitfile):
        return
    
    print("\nERROR: No se pudo programar la Nexys A7.")
    print("Verifique que la placa este conectada por USB.")
    sys.exit(1)

if __name__ == "__main__":
    main()
