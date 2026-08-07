# Nexys A7 — Simulación WSL del frecuencímetro (6 agosto 2026)

## Objetivo

Simular el diseño `top.v` (frecuencímetro + UART TX + display 7-seg) íntegramente
en WSL con herramientas open-source, antes de grabar la FPGA.

## Stack de simulación verificado

| Herramienta | Versión | Rol |
|---|---|---|
| **iverilog** | 12.0 | Compilación Verilog + simulación (vvp) |
| **gtkwave** | ✓ | Visualización de waveforms (.vcd) |
| **cocotb** | 2.0.1 | Testbench Python con asserts automáticos |
| **cocotb_tools.runner** | 2.x | Runner moderno (reemplaza `python -m cocotb`) |
| **verilator** | 5.020 | Lint + simulación C++ (no usado en esta sesión) |

## Archivos creados

```
P:\NexysA7\sim\
├── tb_top.v              ← Testbench Verilog (GATE=10k para sim rápida)
├── top_sim.v             ← Wrapper con debug ports + GATE override (cocotb)
├── test_freq_counter.py  ← 3 tests cocotb (basic, UART, two-freq)
├── run_cocotb.py          ← Runner cocotb 2.x (get_runner API)
└── Makefile               ← Targets: iverilog, cocotb, verilator, clean
```

## Modificaciones al diseño

- `P:\NexysA7\src\top.v`: agregado `` `timescale 1ns / 1ps `` para
  compatibilidad con simulación.

## Lecciones aprendidas

### `FREQ_IN` debe inicializarse explícitamente

En cocotb, los puertos `input` del DUT arrancan en `Z`. Hay que asignar
`dut.FREQ_IN.value = 0` antes de arrancar el generador de estímulos.

### Cocotb 2.x: `cocotb.start_soon()` no retorna awaitable

```python
# INCORRECTO (cuelga la simulación):
await cocotb.start_soon(clock.start())

# CORRECTO:
cocotb.start_soon(clock.start())
```

### NBA delay entre `gate_done` y `freq_cal`

`freq_result` y `freq_cal` se actualizan con asignaciones no bloqueantes (`<=`).
En el ciclo donde `gate_done = 1`, `freq_cal` todavía tiene el valor anterior.
Hay que leer `freq_cal` **un ciclo después** de detectar `gate_done`.

### Alineación del UART receiver

El receptor UART del testbench debe muestrear desde el flanco de bajada exacto
del start bit, no desde el RisingEdge siguiente. Se implementó con detector de
flanco `prev_tx == 1 && tx == 0` y muestreo a `BAUD/2 + BAUD * n` desde allí.

### Display 7-seg con GATE reducido

Con `SIM_GATE=10,000` la resolución es de 1 kHz. `freq_cal=10 kHz` produce
`fk = 10/1000 = 0` → display muestra `000000`. Es correcto para esta
resolución; en hardware real con `GATE=93,200,000` la resolución es sub-Hz.

## Resultados

```
$ make iverilog   # 17 gates, freq_cal=10 constante, gtkwave abre
$ make cocotb     # 3/3 PASS

test_basic      PASS   freq_cal=10 kHz, 7-seg=000000
test_uart       PASS   UART decodifica "000010"
test_two_freqs  PASS   100 kHz→10 kHz, 200 kHz→21 kHz (ratio 2.1x)
```

## Próximos pasos

- `make verilator` para validación de lint + sim C++ rápida.
- yosys → synthesis para Artix-7 y comparar con Vivado.
- Flujo completo WSL: `sim → yosys → openFPGALoader`.
