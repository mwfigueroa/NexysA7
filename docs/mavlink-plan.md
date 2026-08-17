# Plan MAVLink para el ROV (NEORV32 + Nexys A7)

## Objetivo
Operar el ROV desde una estación de control (QGroundControl / MAVProxy) usando
MAVLink v2 sobre UART0 (FTDI canal B). Fase 2 futura: mismo protocolo sobre
Ethernet (ver `docs/ethernet-telemetry-plan.md`).

## Decisiones de diseño

1. **Implementación mínima a mano** (~500 líneas C) — no se usa la librería
   generada `mavlink-c_library` (demasiado grande para los 32 KB de IMEM;
   rov_main ya ocupa ~13 KB).
2. **MAVLink v2** (STX 0xFD) sin firma (incompat_flags=0). CRC-16/MCRF4XX (X.25)
   con seed `crc_extra` por mensaje.
3. **Dialecto common.xml** — QGroundControl reconoce todo sin configuración.
4. **Toggle por consola**: `q on` / `q off`. En modo MAVLink, el TX solo emite
   frames MAVLink; el RX sigue aceptando comandos de consola en paralelo
   (los frames empiezan con 0xFD, los comandos con ASCII — no colisionan).
5. sysid=1, compid=1 (MAV_COMP_ID_AUTOPILOT1), MAV_TYPE=16 (SUBMARINE).

## Mensajes

### TX (telemetría)
| Mensaje | ID | crc_extra | Rate | Datos |
|---|---|---|---|---|
| HEARTBEAT | 0 | 50 | 1 Hz | type=16, autopilot=8, base_mode según armed, status 3/4 |
| ATTITUDE | 30 | 39 | 10 Hz | roll/pitch/yaw + velocidades angulares desde CFS (rad) |
| SCALED_PRESSURE | 29 | 115 | 2 Hz | presión absoluta (hPa) + temp (cdegC) desde CFS |

### RX (control)
| Mensaje | ID | crc_extra | Acción |
|---|---|---|---|
| MANUAL_CONTROL | 69 | 243 | sticks x/y/z/r (-1000..1000) → setpoints surge/sway/heave/yaw (s1.14) |
| RC_CHANNELS_OVERRIDE | 70 | 124 | canales RC raw → setpoints |
| COMMAND_LONG | 76 | 152 | 400=ARM/DISARM, 241=calibrar encoders |

## Mapeo de sticks (convención ArduSub)
- x → Surge (avance), y → Sway (lateral), z → Heave (vertical),
  r → Yaw (giro). Stick +1000 → setpoint +1.0 (s1.14 0x4000).
- z positivo = abajo (convención QGC para subs).

## Prueba (sin QGC)
```bash
mavproxy.py --master=/dev/ttyUSB1 --baudrate 115200
# o parser python propio: valida STX/CRC y decodifica los campos
```

## Fase 2 (no ahora)
- Ethernet RMII (LiteETH) + UDP MAVLink: requiere re-síntesis FPGA con MAC.
- Cámara/streaming por el mismo enlace.
