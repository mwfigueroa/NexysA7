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
| `0xFFFFFF00` - `0xFFFFFF1F` | 32 B | **CFS** (ROV Control) |

---

## 3. CFS — Custom Functions Subsystem (Control ROV)

El CFS expone **8 registros de 32 bits** en `0xFFFFFF00` a `0xFFFFFF1C`.

### 3.1 Registros de Escritura (CPU → ROV)

El CPU escribe en `CFS_REG0` para enviar comandos al hardware ROV.

**CFS_REG0** (`0xFFFFFF00`):

| Bits | Campo | Descripción |
|------|-------|-------------|
| `[2:0]` | `motor_sel` | Motor/encoder a consultar (0-7) |
| `[7:4]` | `cmd` | Código de comando (ver tabla) |
| `[10:8]` | `axis_sel` | Eje para setpoint/PID (0-5) |
| `[13:8]` | `coeff_idx` | Índice de coeficiente del mixer (0-47) |
| `[13:12]` | `gain_sel` | Selector de ganancia PID (0=Kp, 1=Ki, 2=Kd) |
| `[31:16]` | `value` | Valor del parámetro (s1.14 para PID/mixer) |

**CFS_REG1** (`0xFFFFFF04`): heartbeat timeout por comando `0xC` en bits `[63:56]`.
**CFS_REG2** (`0xFFFFFF08`): presión raw (depth) en bits `[63:32]`.
**CFS_REG3** (`0xFFFFFF0C`): temperatura raw (depth) en bits `[79:64]`.

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
| `0xA` | **DEPTH_RAW** | `cfs_in[10]=0→presión`, `=1→temp` | Escribir presión (mbar×100) o temp (C×10) |
| `0xB` | **PID_ENABLE** | `mask[5:0]` en `cfs_in[13:8]` | Habilitar PID por eje (bitmask) |
| `0xC` | **HB_TIMEOUT** | `timeout[7:0]` en `cfs_in[63:56]` | Timeout del heartbeat en ms (default 100) |

### 3.3 Registros de Lectura (ROV → CPU)

El CPU lee de los registros CFS para obtener telemetría.

| Registro | Bits | Campo | Tipo | Descripción |
|----------|------|-------|------|-------------|
| `CFS_REG0` | `[31:0]` | `enc_pos` | u32 | Posición del encoder seleccionado (32-bit) |
| `CFS_REG1` | `[31:0]` | `enc_vel` | s32 | Velocidad del encoder (cuentas/ventana ~31ms) |
| `CFS_REG2` | `[7:0]` | `status` | u8 | `[7]=armed [6]=heartbeat_ok [5]=failsafe` |
| `CFS_REG3` | `[15:0]` | `imu_roll` | s16 | Roll IMU (s1.14 radianes) |
| `CFS_REG3` | `[31:16]` | `imu_pitch` | s16 | Pitch IMU (s1.14) |
| `CFS_REG4` | `[15:0]` | `imu_yaw` | s16 | Yaw IMU (s1.14) |
| `CFS_REG4` | `[31:16]` | `pid_out[0]` | s16 | PID output eje 0 (Surge, s1.14) |
| `CFS_REG5` | `[15:0]` | `pid_out[1]` | s16 | PID output eje 1 (Sway) |
| `CFS_REG5` | `[31:16]` | `pid_out[2]` | s16 | PID output eje 2 (Heave) |
| `CFS_REG6` | `[15:0]` | `pid_out[3]` | s16 | PID output eje 3 (Roll) |
| `CFS_REG6` | `[31:16]` | `pid_out[4]` | s16 | PID output eje 4 (Pitch) |
| `CFS_REG7` | `[15:0]` | `pid_out[5]` | s16 | PID output eje 5 (Yaw) |
| `CFS_REG7` | `[31:16]` | `depth_cm` | u16 | Profundidad en cm |

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
| 0 | LD0 (R17) | Heartbeat indicador |
| 1 | LD1 (M13) | Armed indicador |
| 2-7 | LD2-LD7 | Libre |
| 8-15 | LD8-LD15 | Libre |

---

## 7. PWM / Servo Outputs

- **Conector**: PMOD JA (8 pines)
- **Formato**: Servo pulse 1100-1900 µs, período 20 ms (50 Hz)
- **Neutral**: 1500 µs (motor_duty = 32768)
- **Rango**: motor_duty 0-65535 → pulso 1100-1900 µs
- **Safety gate**: SW[0] (R15) debe estar ON + heartbeat activo para que PWM funcione

```
PMOD JA:  JA[0]=G13  JA[1]=B11  JA[2]=A11  JA[3]=D12
          JA[4]=D13  JA[5]=B18  JA[6]=K18  JA[7]=E15
          → PWM[0]   PWM[1]     PWM[2]     PWM[3]
            PWM[4]   PWM[5]     PWM[6]     PWM[7]
```

---

## 8. Encoders (Quadrature)

- **8 canales** × 2 pines (A, B) = 16 pines total
- **Decodificación**: 4× (cuenta cada flanco)
- **Contadores**: 32-bit signed
- **Velocidad**: delta cada ~31.25 ms (3,200,000 ciclos @ 100 MHz)
- **Sync**: 2-stage synchronizer + false-paths

| Canal | Pin A | Pin B | Conector |
|-------|-------|-------|----------|
| ENC0 | H4 | H1 | PMOD JD[0:1] |
| ENC1 | G1 | H2 | PMOD JD[2:3] |
| ENC2 | G3 | F3 | PMOD JD[4:5] |
| ENC3 | E2 | D2 | PMOD JD[6:7] |
| ENC4 | V10 | V9 | PMOD JC[3:4] |
| ENC5 | T11 | U9 | 7-seg CF + PMOD JC[7] |
| ENC6 | T9 | T10 | PMOD JC[8:9] |
| ENC7 | M18 | P18 | Botones BTNU/BTND |

---

## 9. SPI (PMOD JB)

| Pin | PMOD | FPGA | Función |
|-----|------|------|---------|
| SCK | JB1 | E16 | SPI Clock |
| MOSI | JB2 | F13 | Master Out |
| MISO | JB3 | G14 | Master In |
| CSN | JB4 | H14 | Chip Select |

Para flash SPI externa, sensores IMU (MPU9250/ICM-20948), SD card.

---

## 10. I2C / TWI (PMOD JC)

| Pin | PMOD | FPGA | Función |
|-----|------|------|---------|
| SCL | JC1 | U11 | I2C Clock |
| SDA | JC2 | U12 | I2C Data |

**Requiere pull-ups externos 4.7 kΩ a 3.3V**. Para sensores de presión (MS5837) y otros I2C.

---

## 11. Interrupciones

| IRQ | Fuente | Descripción |
|-----|--------|-------------|
| `irq_mei_i` | SW[1] (H6) | Machine External Interrupt — flanco ascendente |

El SW[1] se sincroniza con edge-detect: genera un pulso en el flanco de subida.

---

## 12. Switches y Botones

| Control | Pin | Función |
|---------|-----|---------|
| SW[0] | R15 | **PWM_ARM** manual (debe estar ON) |
| SW[1] | H6 | **IRQ** externa (flanco ascendente) |
| CPU_RESETN | C12 | Reset del CPU (activo bajo, ya sincronizado) |

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
rov_init();                          // heartbeat + arm + default mixer

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
