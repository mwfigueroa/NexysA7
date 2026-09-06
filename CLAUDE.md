# Nexys A7-100T — FPGA

Placa Digilent **Nexys A7-100T**, Xilinx Artix-7 **XC7A100T-1CSG324**.

## Estado del diseño

NEORV32 **RV32IMC a 100 MHz**, timing cerrado con **WNS +0.136 ns**
(validado 2026-08-12, después de la auditoría de constraints).

**Ese margen es de 136 ps.** Cualquier cambio en RTL, constraints o estrategia
de síntesis puede consumirlo entero: re-verificá el WNS y reportá el número, no
"cerró". Si no corriste la síntesis, no sabés si cerró.

## Flujo verificado

```bash
vivado -mode batch -source neorv32/build.tcl     # síntesis + bitstream
openFPGALoader -b nexys_a7_100 -f neorv32/top.bit --unprotect-flash
# power-cycle → bootloader UART 115200 en ttyUSB1
```

Bootloader: `h` ayuda, `i` info, `u` upload, `e` execute, `s` grabar flash.

Periféricos habilitados: UART0, SPI, TWI/I2C, GPIO (16 LEDs), PWM 8ch por
hardware, GPTMR, WDT, TRNG y **CFS**.

## CFS — control del ROV en hardware

`neorv32/rtl/neorv32_rov_motors.vhd` cuelga del bus del CPU sin tocar el core.
Hace la mezcla 8×6 (48 coeficientes), 6 PID a 400 Hz con anti-windup, fusión
IMU (α=0.98 giro / β=0.02 acel), lectura de 8 encoders con decodificación 4x y
PWM de 8 canales a 24 Hz hacia PMOD JA.

**El CPU no calcula control**: escribe setpoints (6 stores) y lee telemetría
(8 loads) — 14 instrucciones cada 2.5 ms, 0.005 % de CPU. Si te ves moviendo
lazo de control al firmware, es la dirección equivocada.

**Safety**: heartbeat con timeout de 200 ms y apagado automático. No lo
deshabilites para depurar sin decirlo explícitamente en el reporte.

Driver: `neorv32/sw/rov_driver/rov_cfs.h` (`rov_init`, `rov_set_setpoint`,
`rov_set_pid_gain`, `rov_read_depth_cm`).

## Otros

Segundo proyecto en la rama `aplicacion`: frecuencímetro con gate de 1 s
calibrado, eco UART con FIFO y display de 7 segmentos.

El core NEORV32 upstream está espejado en `P:\neorv32`.
Herramientas de PDF y plan de telemetría Ethernet en `docs/`.
