# Nexys A7-100T — Proyectos FPGA

Placa **Digilent Nexys A7-100T** (Xilinx Artix-7 XC7A100T-1CSG324).

## Proyectos

| Proyecto | Rama | Descripción |
|----------|------|-------------|
| **NEORV32 RISC-V** | [`aplicacion`](../../tree/aplicacion/neorv32) | Procesador RV32IMC @ 100 MHz, bootloader UART, hello_world |
| **Frecuencímetro** | [`aplicacion`](../../tree/aplicacion/src) | Gate 1s calibrado, eco UART con FIFO, display 7-seg |

---

## NEORV32 — Procesador RISC-V en Nexys A7

Procesador RISC-V de 32 bits (RV32IMC) corriendo a **100 MHz** con timing cerrado (WNS +0.88 ns).

```bash
vivado -mode batch -source neorv32/build.tcl    # Síntesis + bitstream
openFPGALoader -b nexys_a7_100 -f neorv32/top.bit --unprotect-flash
# Power-cycle Nexys → bootloader a 115200 baud en ttyUSB1
```

**Bootloader**: comandos `h`(help), `i`(info), `u`(upload), `e`(execute), `s`(flash program).

**Periféricos**: UART0, GPIO (16 LEDs), CLINT.

---

## Frecuencímetro + UART Echo

Medidor de frecuencia digital con eco UART interactivo.

## Características

- **Frecuencímetro calibrado**: gate de 1 s (93,2 M ciclos @ 100 MHz), precisión ~0,004 %
- **UART 115200 baud**: transmite medición cada segundo y hace eco del host
- **FIFO RX de 16 bytes**: ráfagas de hasta 26 bytes eco íntegro sin pérdidas
- **Display 7 segmentos**: frecuencia en kHz, 8 dígitos multiplexados
- **LEDs de diagnóstico**: RX busy, FIFO level, overflow, framing error
- **Simulación Vivado xSim + cocotb**: testbench con inyección UART y verificación automática

## Conexiones físicas

| Señal | Pin Nexys | Pmod | Función |
|-------|-----------|------|---------|
| `CLK100MHZ` | E3 | — | Reloj 100 MHz |
| `UART_TXD` | D4 | — | FTDI B → PC |
| `UART_RXD` | C4 | — | PC → FTDI B → FPGA |
| `FREQ_IN` | H4 | JD[1] | Señal a medir (3,3 V LVCMOS33) |

⚠ **Nunca aplicar > 3,3 V** a los pines de la Nexys.

## Estructura del proyecto

```
NexysA7/
├── src/
│   ├── top.v                 # Módulo principal (frecuencímetro + UART)
│   └── NexysA7.xdc           # Constraints (pines + clock 100 MHz)
├── sim/
│   ├── tb_top.v              # Testbench Icarus/xsim (eco + burst)
│   ├── top_sim.v             # Wrapper con GATE reducido
│   ├── test_freq_counter.py  # Cocotb (3 tests: basic, UART, eco)
│   ├── run_cocotb.py         # Runner cocotb
│   ├── Makefile              # Targets: iverilog, cocotb, verilator
│   └── sim_vivado.tcl        # xsim batch + GUI
├── scripts/
│   └── build.tcl             # Síntesis → implementación → bitstream
├── bitstreams/
│   └── top.bit               # Bitstream listo para grabar
└── README.md
```

## Compilación y simulación

### Simulación rápida (xsim batch)

```powershell
vivado -mode batch -source sim\sim_vivado.tcl
```

### Simulación con waveforms (xsim GUI)

```powershell
vivado -mode batch -source sim\sim_vivado.tcl -tclargs gui
```

### Cocotb (Python)

```bash
make -C sim cocotb
```

### Síntesis + bitstream

```powershell
vivado -mode batch -source scripts\build.tcl
```

## Grabado en placa

```bash
openFPGALoader -b nexys_a7_100 -f bitstreams/top.bit --unprotect-flash
```

Luego hacer **power‑cycle físico** de la Nexys para que el FTDI UART funcione.

## Prueba UART (115200 baud, 8N1)

Conectar por serial a `ttyUSB1` (FTDI canal B):

```bash
picocom -b 115200 /dev/ttyUSB1
```

Enviar texto → la FPGA responde con eco + medición de frecuencia:

```
01450053                    ← 1.450.053 Hz
Hello, FPGA!                ← eco íntegro
```

## Resultados de hardware

| Parámetro | Valor |
|-----------|-------|
| Rango medido | ~500 kHz – ~1,42 MHz (verificado con barrido) |
| Precisión @ 1,45 MHz | ±53 Hz (0,004 %) |
| Echo burst 26 bytes | 100 % íntegro |
| FIFO overflow | No observado |
| Timing (WNS) | ⚠ –38 ns — no cerrado; requiere pipeline de aritmética |

## Limitaciones conocidas

1. **Timing no cerrado**: la división/módulo combinacional (`freq_cal`, display) viola el período de 10 ns. El bitstream funciona pero los valores de display/UART pueden ser incorrectos en hardware para frecuencias altas. Pendiente: pipeline o conversión secuencial BCD.
2. **Rango máximo teórico**: ~53 MHz (contador de 27 bits en gate de 1 s). El reporte UART está limitado a 8 dígitos (99.999.999 Hz).
3. **Sin reset externo**: el diseño depende de la inicialización por configuración FPGA (estándar en Xilinx 7-series, no portable a ASIC).

---

## Capacidad del XC7A100T

La Nexys A7-100T monta un **Xilinx Artix-7 XC7A100T-1CSG324**.

| Recurso | Disponible |
|---------|-----------|
| LUTs | **63,400** |
| Flip-Flops | **126,800** |
| BRAM | **135 bloques (4860 Kb = ~607 KB)** |
| DSPs | **240 slices** |
| I/Os | **210 pines** (PMODs, conectores, etc.) |

### Uso actual de la FPGA

| Diseño | LUTs | % FPGA |
|--------|------|--------|
| Frecuencímetro | ~200 | <1% |
| NEORV32 RV32IMC @ 100 MHz | ~22,000 | 35% |
| **Total usado** | **~22,200** | **35%** |

→ Quedan libres ~**41,000 LUTs** (**65% del chip**).

### Qué más cabe en el espacio libre

| Proyecto | LUTs estimados | % FPGA |
|----------|---------------|--------|
| **Z80A** (T80 core) + UART | ~2,500 | 4% |
| **6502/6510** | ~1,500 | 2% |
| **Z80 + 6502** juntos | ~4,600 | 7% |
| **2do NEORV32** (dual-core RISC-V) | ~22,000 | 35% |
| **Amiga 500** (68000 + Agnus + Denise + Paula) | ~40,000 | 63% |
| **NES** (6502 + PPU + APU) | ~12,000 | 19% |
| **Game Boy** (Z80-like + GPU) | ~8,000 | 13% |
| **ZX Spectrum** (Z80 + ULA) | ~4,000 | 6% |
| **8x Z80A** simultáneos | ~18,000 | 28% |
| **Acelerador IA** (CNN en DSPs) | ~5,000 | 8% |
| **Analizador lógico** 32 canales @ 200 MHz | ~2,000 | 3% |
| **SID 6581** (8 voces) | ~600 | 1% |
| **AY-3-8910** (sonido) | ~1,000 | 2% |
| **Controlador VGA/HDMI** | ~3,000 | 5% |
| **MAC Ethernet 10/100** | ~2,000 | 3% |

### Combinaciones posibles (todo simultáneo)

```
┌────────────────────────────────────────────────────────────┐
│  XC7A100T — 63,400 LUTs libres                             │
│                                                            │
│  ┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │
│  │ NEORV32       │ │ T80 Z80  │ │ 65C02    │ │ VGA out   │ │
│  │ 22,000 LUTs   │ │ 2,200    │ │ 1,300    │ │ 3,000      │ │
│  └──────────────┘ └──────────┘ └──────────┘ └───────────┘ │
│                                                            │
│  ┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │
│  │ SID 8580 x8  │ │ YM2149   │ │ UART x4  │ │ BRAM disp │ │
│  │ 600           │ │ 1,000    │ │ 800      │ │ ~8,000    │ │
│  └──────────────┘ └──────────┘ └──────────┘ └───────────┘ │
│                                                            │
│  Total: ~41,000 LUTs — todavía sobran ~22,000              │
└────────────────────────────────────────────────────────────┘
```

En resumen: la Nexys A7-100T es una placa **sobredimensionada** para un solo micro. Se puede usar como laboratorio de **múltiples CPUs antiguas** corriendo en paralelo, o como plataforma de **cómputo heterogéneo** (RISC-V + Z80 + DSPs para IA).

---

## Licencia

MIT — Usá, modificá y compartí libremente.
