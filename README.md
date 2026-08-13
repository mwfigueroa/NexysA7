# Nexys A7-100T — Proyectos FPGA

Placa **Digilent Nexys A7-100T** (Xilinx Artix-7 XC7A100T-1CSG324).

## Herramientas

| Categoría | Doc |
|---|---|
| **PDFs** (datasheets, schematics, manuals) | [`docs/pdf-tools.md`](docs/pdf-tools.md) |
| Ethernet Telemetry Plan | [`docs/ethernet-telemetry-plan.md`](docs/ethernet-telemetry-plan.md) |

## Proyectos

| Proyecto | Rama | Descripción |
|----------|------|-------------|
| **NEORV32 RISC-V** | [`aplicacion`](../../tree/aplicacion/neorv32) | Procesador RV32IMC @ 100 MHz, bootloader UART, hello_world |
| **Frecuencímetro** | [`aplicacion`](../../tree/aplicacion/src) | Gate 1s calibrado, eco UART con FIFO, display 7-seg |

---

## NEORV32 — Procesador RISC-V en Nexys A7

Procesador RISC-V de 32 bits (RV32IMC) corriendo a **100 MHz** con timing cerrado (WNS **+0.136 ns**, validado 2026-08-12 tras la auditoría de constraints).

```bash
vivado -mode batch -source neorv32/build.tcl    # Síntesis + bitstream (auto-reemplaza CFS template)
openFPGALoader -b nexys_a7_100 -f neorv32/top.bit --unprotect-flash
# Power-cycle Nexys → bootloader a 115200 baud en ttyUSB1
```

**Bootloader**: comandos `h`(help), `i`(info), `u`(upload), `e`(execute), `s`(flash program).

**Periféricos**: UART0, SPI, TWI/I2C, GPIO (16 LEDs), PWM 8ch hardware, GPTMR, WDT, TRNG, **CFS para control ROV**.

### CFS — Custom Functions Subsystem (Control ROV)

El **CFS** es un bloque interno del NEORV32 que conecta hardware custom directamente al bus del CPU sin modificar el core. Nuestro módulo `neorv32_rov_motors.vhd` implementa:

```
                    ┌──────────────────────────┐
  CPU RV32IMC       │  CFS (256-bit bus)        │
  ┌────────┐        │  ┌────────────────────┐   │
  │ store  │──cfs──►│  │ cmd edge-detect    │   │
  │ CFS_R0 │        │  │                    │   │
  └────────┘        │  │ 0x1: heartbeat     │   │    ┌──────────────┐
                    │  │ 0x2: arm motors    │   │    │ PWM hardware │
  ┌────────┐        │  │ 0x4: calibrar enc  │   │    │ 8ch @ 24Hz   │──► PMOD JA
  │ load   │◄──cfs──│  │ 0x6: setpoint      │──►──┤    │ safety gate  │
  │ CFS_R1 │        │  │ 0x8: PID gains     │   │    └──────────────┘
  └────────┘        │  │ 0xB: PID enable    │   │
                    │  └────────────────────┘   │
  14 instrucciones  │                           │
  cada 2.5ms =      │  ┌────────────────────┐   │    ┌──────────────┐
  0.005% CPU ──────►│  │ Mixer 8×6 Matrix   │   │    │ Encoders 8ch │
                    │  │ 48 coeficientes    │   │    │ 32-bit pos   │◄── PMOD JD+JC
                    │  └────────────────────┘   │    │ 4x decode    │
                    │  ┌────────────────────┐   │    └──────────────┘
                    │  │ PID 6-DOF @ 400Hz  │   │
                    │  │ Kp/Ki/Kd por eje  │   │    ┌──────────────┐
                    │  │ anti-windup clamp  │   │    │ IMU Fusion   │
                    │  └────────────────────┘   │    │ α=0.98 gyro  │
                    │  ┌────────────────────┐   │    │ β=0.02 accel │
                    │  │ Safety Heartbeat   │   │    └──────────────┘
                    │  │ timeout 200ms      │   │
                    │  │ fail-safe auto-off │   │    ┌──────────────┐
                    │  └────────────────────┘   │    │ Depth Sensor │
                    └──────────────────────────┘    │ P→cm + temp  │
                                                    └──────────────┘
```

**El CPU no gasta ciclos en control**: escribe setpoints (6 stores) y lee telemetría (8 loads). Todo el cálculo pesado — mezcla 8×6, 6 PID, filtro IMU, lectura de encoders — ocurre en hardware a 100 MHz.

**Driver en firmware**: [`neorv32/sw/rov_driver/rov_cfs.h`](neorv32/sw/rov_driver/rov_cfs.h)

```c
#include "rov_cfs.h"
rov_init();                              // heartbeat + arm
rov_set_setpoint(AXIS_HEAVE, 0);        // control profundidad
rov_set_pid_gain(AXIS_HEAVE, kp,ki,kd); // sintonizar PID
uint16_t depth = rov_read_depth_cm();   // leer profundidad
```

### Etapas implementadas

| Etapa | Commit | Hardware |
|-------|--------|----------|
| **0** | `be1364b` | CPU base + UART + SPI + I2C + GPIO LEDs |
| **1** | `79332e4` | PWM Safety Manager + Quadrature Encoder 8ch |
| **2** | `abfb880` | Mixer Matrix 8×6 + IMU Complementary Filter |
| **3** | `bfe9df6` | PID Controller 6-DOF + Depth Sensor |
| **fix** | `c5a21d0` | CFS habilitado y cableado, edge-detect, sync, driver |
| **fix** | `6f8e776` | 5 bugs P0: cfs_out, encoder, heartbeat, presión, calibración |
| **fix** | `357ae30` | 4 bugs P1: mixer saturation, servo pulse, slew, heartbeat toggle |
| **fix** | `7be7f07` | P2: constraints, ASYNC_REG, IRQ edge, enc_vel signed, PID→mixer |
| **4** | `d9ae69e` | JTAG Debug (OCD) habilitado |
| **fix** | `718d97f` | 0 Critical Warnings (pin V8→T11) |
| **fix** | `0834dd6` | **CFS real** (8 regs CPU↔ROV) + strobes + arm_timer + servo_pulse |
| **fix** | `e0ddde4` | motor_sweep: barrido PWM 8 canales |
| **fix** | `f328225` | XDC auditado vs Master XDC oficial: LEDs/switches/PWM→JA/SPI/TWI corregidos, SW[15:0]→GPIO, firmware rov_main + cfs_test validados en HW |

### ⚠️ Estado actual

| Aspecto | Estado |
|---------|--------|
| **CFS** | ✅ Funcional — 8 registros mapeados CPU↔ROV, validado en hardware (T1-T11 PASS) |
| **Constraints** | ✅ XDC auditado contra el Master XDC oficial de Digilent (LEDs, switches, PWM→JA, SPI, TWI corregidos — ver [`docs/SESION-2026-08-12.md`](docs/SESION-2026-08-12.md)) |
| **PWM** | ✅ Verificado en los 8 pines de PMOD JA (C17, D18, E18, G17, D17, E17, F18, G18) |
| **Firmware** | ✅ [`neorv32/sw/rov_main`](neorv32/sw/rov_main) — consola + heartbeat + depth/yaw-hold validados |
| **Build** | ✅ 0 Critical Warnings, 0 Errors |
| **Timing** | ✅ WNS=+0.136 ns / WHS=+0.029 ns @ 100 MHz |
| **LUTs** | ~5,000 / 63,400 (7.9%) |
| **DSPs** | ~33 / 240 (13.8%) — validan que el CFS está activo |

**Firmware disponible**: `neorv32/sw/cfs_test` (test de subsistema) y
`neorv32/sw/rov_main` (firmware principal estilo NVehicleManager). Driver
corregido: [`neorv32/sw/rov_driver/rov_cfs.h`](neorv32/sw/rov_driver/rov_cfs.h).

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
