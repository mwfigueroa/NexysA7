# Sistema ROV NEORV32 — Hardware Reference para Firmware

> **Placa**: Digilent Nexys A7-100T (XC7A100T-1CSG324)
> **CPU**: NEORV32 RV32IMC @ 100 MHz
> **Build**: WNS=-0.67ns, 0 Critical Warnings, 0 DRC Errors
> **Repositorio**: [mwfigueroa/NexysA7 (aplicacion)](https://github.com/mwfigueroa/NexysA7/tree/aplicacion)

---

## 1. Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────┐
│  NEORV32 RV32IMC @ 100 MHz                              │
│                                                         │
│  ┌──────────┐   ┌─────────┐   ┌──────────────────────┐ │
│  │ CPU      │───│ IMEM    │   │ CFS (ROV Subsystem)   │ │
│  │ RV32IMC  │   │ 64 KB   │   │ ┌──────────────────┐  │ │
│  │          │   └─────────┘   │ │ SAFETY: heartbeat │  │ │
│  │          │   ┌─────────┐   │ │   slew, arm seq   │  │ │
│  │          │───│ DMEM    │   │ ├──────────────────┤  │ │
│  │          │   │ 32 KB   │   │ │ MIXER: 8×6 mat   │  │ │
│  └──────────┘   └─────────┘   │ ├──────────────────┤  │ │
│       │                        │ │ PID: 6-DOF 400Hz │  │ │
│  ┌────┴────────────────────┐   │ ├──────────────────┤  │ │
│  │ Periféricos             │   │ │ ENCODERS: 8ch    │  │ │
│  │ UART0 @ 115200          │   │ │ 32-bit pos+vel   │  │ │
│  │ GPIO[15:0] → LEDs       │   │ ├──────────────────┤  │ │
│  │ SPI (PMOD JB)           │   │ │ IMU: filtro      │  │ │
│  │ TWI/I2C (PMOD JC)       │   │ │ complementario   │  │ │
│  │ GPTMR (4 slices)        │   │ ├──────────────────┤  │ │
│  │ WDT + TRNG              │   │ │ DEPTH: P→cm      │  │ │
│  │ PWM 8ch hardware        │   │ └──────────────────┘  │ │
│  │ OCD/JTAG debug          │   └──────────────────────┘ │
│  └─────────────────────────┘                            │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Mapa de Memoria

| Rango | Tamaño | Descripción |
|-------|--------|-------------|
| `0x00000000` - `0x0000FFFF` | 64 KB | **IMEM** (Instruction Memory, BRAM) |
| `0x80000000` - `0x80007FFF` | 32 KB | **DMEM** (Data Memory, BRAM) |
| `0xF0000000` - `0xF000001F` | 32 B | **GPIO** (LEDs en GPIO[15:0]) |
| `0xF0010000` - `0xF001000F` | 16 B | **UART0** (FTDI channel B, 115200 baud) |
| `0xF0040000` - `0xF004000F` | 16 B | **SPI** (PMOD JB, host mode) |
| `0xF0050000` - `0xF005000F` | 16 B | **TWI/I2C** (PMOD JC) |
| `0xF00A0000` - `0xF00A000F` | 16 B | **GPTMR** (4 timers) |
| `0xF00B0000` - `0xF00B000F` | 16 B | **WDT** (Watchdog) |
| `0xF00C0000` - `0xF00C000F` | 16 B | **TRNG** (Random) |
| `0xFFFF0000` - `0xFFFF1FFF` | 8 KB | **Boot ROM** (bootloader) |
| `0xFFEB0000` - `0xFFEB001F` | 32 B | **CFS** (ROV Control) |

---

## 3. CFS — Custom Functions Subsystem (Control ROV)

El CFS expone **8 registros de 32 bits** en `0xFFEB0000` a `0xFFEB001C`.
> **Validado en hardware (2026-08-12)**: este mapa es el ground truth del VHDL
> `neorv32_rov_motors.vhd` en el bitstream actual (SDK v1.13.3).

### 3.1 Registros de Escritura (CPU → ROV)

El CPU escribe en `CFS_REG0` para enviar comandos al hardware ROV.

**CFS_REG0** (`0xFFEB0000`):

| Bits | Campo | Descripción |
|------|-------|-------------|
| `[2:0]` | `motor_sel` | Motor/encoder a consultar (0-7) |
| `[7:4]` | `cmd` | Código de comando (ver tabla) |
| `[10:8]` | `axis_sel` | Eje para setpoint/PID (0-5) |
| `[13:8]` | `coeff_idx` | Índice de coeficiente del mixer (0-47) |
| `[13:12]` | `gain_sel` | Selector de ganancia PID (0=Kp, 1=Ki, 2=Kd) |
| `[31:16]` | `value` | Valor del parámetro (s1.14 para PID/mixer) |

**CFS_REG1** (`0xFFEB0004`): timeout del heartbeat (comando `0xC`) en bits `[31:24]` (ms); presión raw en `[31:0]` (comando `0xA`, bit10=0, unidades **Pascal**).
**CFS_REG2** (`0xFFEB0008`): temperatura raw en `[15:0]` (comando `0xA`, bit10=1, unidades **C×10**).

### 3.2 Comandos CFS

| Cmd | Nombre | Parámetros | Descripción |
|-----|--------|-----------|-------------|
| `0x1` | **HEARTBEAT** | `cfs_in[8]` toggle | Keep-alive. Alternar bit 8 en cada llamada. |
| `0x2` | **ARM** | — | Armar motores (requiere heartbeat activo) |
| `0x3` | **DISARM** | — | Desarmar motores |
| `0x4` | **CALIBRATE** | — | Poner a cero los 8 contadores de encoder |
| `0x5` | **MIXER_COEFF** | `coeff_idx[5:0]`, `value[15:0]` | Escribir coeficiente del mixer (s1.14) |
| `0x6` | **SETPOINT** | `axis[2:0]`, `value[15:0]` | Escribir setpoint de control (s1.14) |
| `0x7` | **IMU_RAW** | `axis[2:0]`, `value[15:0]` | Escribir dato raw de IMU (s1.14) |
| `0x8` | **PID_GAIN** | `axis[2:0]`, `gain[1:0]`, `value[15:0]` | Escribir Kp/Ki/Kd del PID (s1.14) |
| `0x9` | **PID_CURRENT** | `axis[2:0]`, `value[15:0]` | Escribir posición actual del PID (s1.14) |
| `0xA` | **DEPTH_RAW** | `cfs_in[10]=0→presión`, `=1→temp` | Escribir presión (Pa) o temp (C×10) |
| `0xB` | **PID_ENABLE** | `mask[5:0]` en `cfs_in[13:8]` | Habilitar PID por eje (bitmask) |
| `0xC` | **HB_TIMEOUT** | `timeout[7:0]` en `CFS_REG1[31:24]` | Timeout del heartbeat en ms (driver usa 200) |

> **IMPORTANTE**: cada escritura de comando debe ir seguida de un NOP
> (`CFS_REG0 = 0`) para que el edge-detector del hardware pueda
> re-disparar el mismo comando dos veces seguidas.

### 3.3 Registros de Lectura (ROV → CPU)

El CPU lee de los registros CFS para obtener telemetría.

| Registro | Bits | Campo | Tipo | Descripción |
|----------|------|-------|------|-------------|
| `CFS_REG0` | `[31:0]` | `enc_pos` | u32 | Posición del encoder seleccionado (32-bit) |
| `CFS_REG1` | `[31:0]` | `enc_vel` | s32 | Velocidad del encoder (cuentas/ventana ~31ms) |
| `CFS_REG2` | `[7:0]` | `status` | u8 | `[7]=armed [6]=heartbeat_ok [5]=failsafe(!armed)` |
| `CFS_REG2` | `[15:8]` | `hb_cnt` | u8 | Contador de heartbeats recibidos |
| `CFS_REG2` | `[31:16]` | `imu_roll` | s16 | Roll IMU (s1.14 radianes) |
| `CFS_REG3` | `[15:0]` | `imu_pitch` | s16 | Pitch IMU (s1.14) |
| `CFS_REG3` | `[31:16]` | `imu_yaw` | s16 | Yaw IMU (s1.14) |
| `CFS_REG4` | `[15:0]` | `pid_out[0]` | s16 | PID output eje 0 (Surge, s1.14) |
| `CFS_REG4` | `[31:16]` | `pid_out[1]` | s16 | PID output eje 1 (Sway) |
| `CFS_REG5` | `[15:0]` | `pid_out[2]` | s16 | PID output eje 2 (Heave) |
| `CFS_REG5` | `[31:16]` | `pid_out[3]` | s16 | PID output eje 3 (Roll) |
| `CFS_REG6` | `[15:0]` | `pid_out[4]` | s16 | PID output eje 4 (Pitch) |
| `CFS_REG6` | `[31:16]` | `pid_out[5]` | s16 | PID output eje 5 (Yaw) |
| `CFS_REG7` | `[15:0]` | `depth_cm` | u16 | Profundidad en cm |
| `CFS_REG7` | `[31:16]` | `depth_temp` | s16 | Temperatura raw (C×10) |

---

## 4. Ejes de Control (6-DOF)

| Índice | Nombre | Descripción |
|--------|--------|-------------|
| 0 | **Surge** | Avance/retroceso (eje X) |
| 1 | **Sway** | Desplazamiento lateral (eje Y) |
| 2 | **Heave** | Profundidad (eje Z) |
| 3 | **Roll** | Rotación sobre eje X |
| 4 | **Pitch** | Rotación sobre eje Y |
| 5 | **Yaw** | Rotación sobre eje Z (rumbo) |

---

## 5. Mixer Matrix (8×6)

48 coeficientes configurables (8 motores × 6 ejes). Coeficientes default para frame OCTO.
Cada coeficiente y setpoint usa formato **s1.14 fixed-point**:

| Valor s1.14 | Decimal | Significado |
|-------------|---------|-------------|
| `0x4000` | +1.0 | Contribución positiva máxima |
| `0x0000` | 0.0 | Sin contribución |
| `0xC000` | -1.0 | Contribución negativa máxima |

Los índices de coeficiente son: `coeff_idx = motor*6 + eje`.

---

## 6. GPIO (LEDs)

| GPIO | LED Nexys | Función sugerida |
|------|-----------|-----------------|
| 0 | LD0 (H17) | Heartbeat indicador |
| 1 | LD1 (K15) | Armed indicador |
| 2-7 | LD2-LD7 | Libre |
| 8-15 | LD8-LD15 | Libre |

---

## 7. PWM / Servo Outputs

- **Conector**: PMOD JA (8 pines de señal, borde derecho de la placa, vertical)
- **Formato**: Servo pulse 1100-1900 µs, período 20 ms (50 Hz)
- **Neutral**: 1500 µs (motor_duty = 32768)
- **Rango**: motor_duty 0-65535 → pulso 1100-1900 µs
- **Safety gate**: SW[0] (J15, silkscreen SW0) debe estar ON + heartbeat activo para que PWM funcione
- **Verificado en hardware (2026-08-12)**: los 8 pines de señal emiten el walk de 1 kHz (modo test) / pulsos servo

> **Layout del conector PMOD** (vista frontal, según manual de referencia pág. 25):
> pines **5 y 11 = GND**, pines **6 y 12 = VCC (3.3 V)**.
> Columna A: 1,2,3,4,5=GND,6=VCC — Columna B: 7,8,9,10,11=GND,12=VCC

```
PMOD JA:  JA1=C17 → PWM[0]      JA7=D17 → PWM[4]
          JA2=D18 → PWM[1]      JA8=E17 → PWM[5]
          JA3=E18 → PWM[2]      JA9=F18 → PWM[6]
          JA4=G17 → PWM[3]      JA10=G18 → PWM[7]
          5=GND  6=VCC          11=GND  12=VCC
```

---

## 8. Encoders (Quadrature)

- **8 canales** × 2 pines (A, B) = 16 pines total
- **Decodificación**: 4× (cuenta cada flanco)
- **Contadores**: 32-bit signed
- **Velocidad**: delta cada ~31.25 ms (3,200,000 ciclos @ 100 MHz)
- **Sync**: 2-stage synchronizer + false-paths

> **⚠️ ESTADO ACTUAL (2026-08-12)**: el mapping de encoders NO coincide con lo
> documentado antes. Tras la auditoría contra el manual de referencia, los pines
> reales son los siguientes. **Pendiente**: reasignar ENC3/ENC5/ENC6/ENC7 a pines
> libres de PMOD JC (JC3=J2, JC4=G6, JC7=E7, JC8=J3, JC9=J4, JC10=E6).

| Canal | Pin A | Pin B | Ubicación física REAL |
|-------|-------|-------|-----------------------|
| ENC0 | H4 | H1 | PMOD JD1/JD2 ✓ |
| ENC1 | G1 | H2 | PMOD JD3/JD7 ✓ |
| ENC2 | G3 | F3 | PMOD JD4/JD10 ✓ |
| ENC3 | E2 | D2 | ⚠️ **SD_RESET / SD_DAT[3]** (slot SD, no PMOD) |
| ENC4 | D14 | F16 | PMOD JB1/JB2 (reubicado 2026-08-12) |
| ENC5 | T11 | G13 | ⚠️ T11 = 7-seg CF; G13 = JB9 |
| ENC6 | T9 | T10 | ⚠️ T9 = 7-seg AN2; T10 = 7-seg CA |
| ENC7 | M18 | P18 | ⚠️ Botones BTNU/BTND |

---

## 9. SPI (PMOD JB)

| Señal | Pin PMOD | FPGA | Nota |
|-------|----------|------|------|
| SCK | JB7 | E16 | SPI Clock ✓ |
| MOSI | JB8 | F13 | Master Out ✓ |
| MISO | JB3 | G16 | Master In ✓ (antes G14 ✗) |
| CSN | JB4 | H14 | Chip Select ✓ |

Otros pines de JB en uso por encoders reubicados: JB1=D14 (ENC_A[4]), JB2=F16 (ENC_B[4]), JB9=G13 (ENC_B[5]). JB10=H16 libre.
Para flash SPI externa, sensores IMU (MPU9250/ICM-20948), SD card.

---

## 10. I2C / TWI (PMOD JC)

| Señal | Pin PMOD | FPGA | Nota |
|-------|----------|------|------|
| SCL | JC1 | K1 | I2C Clock ✓ (antes U11 ✗) |
| SDA | JC2 | F6 | I2C Data ✓ (antes U12 ✗) |

Pines libres de JC: JC3=J2, JC4=G6, JC7=E7, JC8=J3, JC9=J4, JC10=E6 (candidatos para reasignar encoders).
**Requiere pull-ups externos 4.7 kΩ a 3.3V**. Para sensores de presión (MS5837) y otros I2C.

---

## 11. Interrupciones

| IRQ | Fuente | Descripción |
|-----|--------|-------------|
| `irq_mei_i` | SW[1] (L16) | Machine External Interrupt — flanco ascendente |

El SW[1] se sincroniza con edge-detect: genera un pulso en el flanco de subida.

---

## 12. Switches y Botones

| Control | Pin | Función |
|---------|-----|---------|
| SW[0] | J15 | **PWM_ARM** manual (silkscreen SW0, debe estar ON) |
| SW[1] | L16 | **IRQ** externa (silkscreen SW1, flanco ascendente) |
| SW[2..15] | M13,R15,R17,T18,U18,R13,T8,U8,R16,T13,H6,U12,U11,V10 | GPIO inputs (espejo LED, leídos por CPU) |
| CPU_RESETN | C12 | Reset del CPU (activo bajo, ya sincronizado) |

Nota: SW[8]=T8 y SW[9]=U8 están en el banco 34 del FPGA (VCCO 1.8V) → IOSTANDARD LVCMOS18.

---

## 13. JTAG Debug (OCD)

| Pin | FPGA | Función |
|-----|------|---------|
| TCK | R10 | JTAG Clock |
| TDI | K16 | JTAG Data In |
| TDO | K13 | JTAG Data Out |
| TMS | P15 | JTAG Mode Select |

Compatible con OpenOCD + GDB. Los pines son del 7-segmentos (no se usa display).

---

## 14. UART / Bootloader

- **Puerto**: `/dev/ttyUSB1` (FTDI canal B, 115200 baud, 8N1)
- **Bootloader**: Comandos `h`, `i`, `u`, `e`, `r`, `l`, `s`, `x`
- **Upload**: Enviar `u` (sin `\r`) → esperar "Awaiting" → enviar `neorv32_exe.bin` → `e` para ejecutar

---

## 15. Compilación de Firmware

### Toolchain

```bash
# Compilador
RISCV_PREFIX=riscv64-unknown-elf-
MARCH=rv32i_zicsr_zifencei
MABI=ilp32

# Flags para picolibc
USER_FLAGS += -isystem /usr/lib/picolibc/riscv64-unknown-elf/include
USER_FLAGS += -nostartfiles -nodefaultlibs
USER_FLAGS += -L/usr/lib/picolibc/riscv64-unknown-elf/lib/rv32iac/ilp32
USER_FLAGS += -lc -lgcc
USER_FLAGS += -flto -msave-restore
```

### Makefile ejemplo

```makefile
NEORV32_HOME ?= ../../..
RISCV_PREFIX ?= riscv64-unknown-elf-
MARCH = rv32i_zicsr_zifencei
MABI = ilp32
EFFORT = -Os
USER_FLAGS += -isystem /usr/lib/picolibc/riscv64-unknown-elf/include
USER_FLAGS += -nostartfiles -nodefaultlibs
USER_FLAGS += -L/usr/lib/picolibc/riscv64-unknown-elf/lib/rv32iac/ilp32
USER_FLAGS += -lc -lgcc -flto -msave-restore
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_base=0x80000000
include $(NEORV32_HOME)/sw/common/common.mk
```

### Subir firmware

```bash
python3 upload.py firmware/neorv32_exe.bin
```

---

## 16. Driver CFS (rov_cfs.h)

Ubicación: `neorv32/sw/rov_driver/rov_cfs.h`

```c
#include "rov_cfs.h"

// Inicialización
rov_init();                          // hb timeout 200ms + heartbeat + arm + setpoints=0

// Loop principal (cada 50ms)
while (1) {
    rov_heartbeat();                 // mantener vivo el watchdog

    // Control manual
    rov_set_setpoint(AXIS_HEAVE, 0); // profundidad constante

    // Leer telemetría
    uint32_t pos = rov_read_encoder_position(3);
    uint16_t depth = rov_read_depth_cm();
    uint8_t status = rov_read_status();

    // Configurar PID (una sola vez)
    rov_set_pid_gain(AXIS_HEAVE, kp, ki, kd);
    rov_set_pid_current(AXIS_HEAVE, current_depth);
    rov_enable_pid(1 << AXIS_HEAVE);
}
```

---

## 17. Recursos del FPGA

| Recurso | Usado | Total | % |
|---------|-------|-------|---|
| LUTs | ~5,000 | 63,400 | 7.9% |
| Registros | ~5,700 | 126,800 | 4.5% |
| BRAM | 26 | 135 | 19.3% |
| DSPs | 25 | 240 | 10.4% |

**Libres**: ~58,000 LUTs para expansiones futuras.
