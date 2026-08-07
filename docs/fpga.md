# Nexys A7 + ADP2230 — Sesión 5-6 Agosto 2026

## Estado Final

### Nexys A7
- ✅ JTAG: XC7A100T, Flash QSPI programada
- ✅ Frecuencímetro calibrado 0.13%
- ✅ UART TX 115200, Display 7-seg
- ❌ UART RX (hardware FTDI→C4)

### ADP2230
- ✅ AWG + Scope + Logic Analyzer
- ✅ Barrido con `awg_generate` individual
- ⚠️ `awg_sweep`: implementado pero limitado por pydwf
  - `configure(True)` no re-aplica frecuencia en AWG corriendo
  - Workaround: usar `awg_generate` por paso
  - Futuro: explorar FM modulation o custom waveforms

### Cross-Instrument
- ✅ Triple: ADP2230 + TBS1102C + Nexys A7 (0.13%)

---

## Lecciones
1. ADP2230 `amplitude_vpp` = pico
2. NUNCA 5V en LVCMOS33
3. JTAG interfiere FTDI UART → flash + power cycle
4. pydwf `configure(True)` no cambia frecuencia on-the-fly
5. `awg_generate` requiere TODOS los parámetros

---

## Comandos
```bash
# Nexys flash
wsl openFPGALoader -b nexys_a7_100 -f --unprotect-flash /mnt/p/NexysA7/bitstreams/top.bit

# UART Nexys
wsl python3 -c "import serial; s=serial.Serial('/dev/ttyUSB1',115200,timeout=4); print(s.read(200).decode())"

# Barrido (workaround: llamadas individuales)
# > "genera 100Hz cuadrado" → "genera 500Hz cuadrado" → ...
```
