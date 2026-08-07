# Nexys A7 — Herramientas y Scripts

> Placa: Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
> USB: FTDI FT2232H (Canal A = JTAG, Canal B = UART)

---

## Estructura

```
P:\NexysA7\
├── src\
│   ├── top.v               ← diseño Verilog (LED blinker + UART echo)
│   └── NexysA7.xdc         ← constraints (pines, clock)
├── bitstreams\
│   └── top.bit             ← 3.65 MB generado (0 errores)
├── build\                  ← proyecto Vivado (autogenerado)
├── scripts\
│   ├── build.tcl           ← síntesis completa
│   ├── program.tcl         ← programar con Vivado
│   ├── program.py          ← programador Python
│   └── program_fast.bat    ← one-click programmer
└── docs\
    ├── README.md           ← este archivo
    └── SESION-2026-08-05.md ← bitácora de la sesión
```

---

## Herramientas instaladas

### Windows
| Herramienta | Ubicación | Estado |
|---|---|---|
| **Vivado 2026.1** | `P:\AMDDesignTools\2026.1\Vivado\` | ✅ Licencia Basic Tier activa |
| **OpenFPGALoader** | WSL | ✅ v0.12 |

### WSL
| Herramienta | Versión |
|---|---|
| yosys | 0.33 |
| iverilog | 12.0 |
| verilator | 5.020 |
| GTKWave | 3.3.116 |
| cocotb | 2.0.1 |
| fusesoc | 2.4.6 |
| LiteX | 2024.12 |
| picocom | 3.1 |

---

## Uso

### Sintetizar
```powershell
P:\AMDDesignTools\2026.1\Vivado\bin\vivado -mode batch -source P:\NexysA7\scripts\build.tcl
```

### Programar (con OpenFPGALoader, no necesita Vivado)
```bash
wsl openFPGALoader -b nexys_a7_100 /mnt/p/NexysA7/bitstreams/top.bit
```

### Verificar UART
```bash
wsl stty -F /dev/ttyUSB0 115200 raw
echo "test" > /dev/ttyUSB0 && timeout 1 cat /dev/ttyUSB0
```

---

## Licencia Vivado

| Dato | Valor |
|---|---|
| Tipo | Basic Tier, Node-Locked |
| Host ID | `D843AE8CEFC5` |
| Cuenta AMD | martinfigueroa447@hotmail.com |
| Expira | 06-Ago-2027 |
| Archivo | `C:\.Xilinx\Xilinx.lic` |

---

## Ver también

- [SESION-2026-08-05.md](SESION-2026-08-05.md) — bitácora completa de la sesión
- [GitHub repo](https://github.com/mwfigueroa/opencode-electronics) — documentación del ecosistema
