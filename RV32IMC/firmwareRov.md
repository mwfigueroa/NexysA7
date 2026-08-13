# Firmware ROV — NEORV32 Nexys A7

Firmware C++ para el procesador **NEORV32 RV32IMC @ 100 MHz** en la Nexys A7-100T. Controla el subsistema ROV vía CFS (Custom Functions Subsystem) con driver corregido contra la VHDL real.

## Compilación
```
cmake --preset debug
cmake --build --preset debug
```
Salida: `neorv32_exe.bin` (~7 KB) listo para cargar por bootloader UART.

## Carga en placa
```
cmake --build --preset debug --target upload
```
Autodetecta el puerto y ejecuta la secuencia del bootloader (`u` → binario → `e`).

## Comandos UART (115200 8N1)

| Cmd | Función |
|-----|---------|
| `h` | Ayuda |
| `i` | Info del sistema (CPU, versión HW, clock) |
| `s` | Status de seguridad (armed, heartbeat, failsafe) |
| `a 0\|1` | Desarmar / Armar motores |
| `c` | Calibrar encoders (poner a cero) |
| `e [0-7]` | Leer encoder (posición 32-bit + velocidad) |
| `m` | Leer IMU (roll, pitch, yaw en s1.14) |
| `d` | Leer profundidad (cm) |
| `p` | Leer salidas PID de los 6 ejes |
| `t <eje> <hex>` | Setpoint de control (s1.14, hexadecimal s16) |
| `k <eje> <kp> <ki> <kd>` | Ganancias PID (s1.14 hexadecimal) |
| `n <eje> <val>` | Posición actual del PID |
| `g <mask>` | Habilitar PID por eje (bitmask 0-63) |
| `w`, `z` | No disponibles: PWM nativo desconectado de las salidas ROV |
| `l` | Test de LEDs |
| `v` | Activar/desactivar telemetría automática |
| `r` | Re-inicializar ROV |
| `x` | Volcar los 8 registros CFS crudos para diagnóstico |

## Funcionamiento automático

| Mecanismo | Período | Descripción |
|-----------|---------|-------------|
| Heartbeat CFS | 50 ms | Mantiene vivo el watchdog de hardware |
| LED0 | 1 Hz | Indicador visual de firmware corriendo |
| Telemetría | 2 s | Status, depth, 8 encoders, IMU, 6 PID outputs |

## Correcciones críticas

> **Actualizado 2026-08-12**: la corrección anterior de offsets (basada en
> `neorv32_rov_motors.vhd:581-603`) resultó **errónea**. El driver validado en
> hardware contra el VHDL real está en
> [`neorv32/sw/rov_driver/rov_cfs.h`](../../tree/aplicacion/neorv32/sw/rov_driver/rov_cfs.h):
> CFS base `0xFFEB0000`, cmd en bits [7:4], NOP tras cada comando, y mapa de
> lectura REG0-REG7 según ground truth (ver
> [`docs/SESION-2026-08-12.md`](../../tree/aplicacion/docs/SESION-2026-08-12.md)).

### Firmware principal (nuevo, Makefile)

El firmware canónico del ROV es ahora **`neorv32/sw/rov_main/`** (C + Makefile
picolibc, mismo flujo que `cfs_test`). Esta app CMake/C++ queda como referencia
histórica con el driver corregido copiado en `app/rov_cfs.h`.
