# Ethernet Telemetry Plan — ROV Nexys A7

> **Objetivo:** Monitoreo en tiempo real del ROV vía Ethernet UDP sin tocar el lazo de control.
> UART queda como respaldo/configuración. El failsafe y watchdog de hardware siguen siendo locales y deterministas.

---

## Hardware disponible

| Componente | Detalle |
|---|---|
| **PHY** | SMSC LAN8720A, RMII 10/100 |
| **Conector** | RJ-45 onboard con magnéticos integrados |
| **Clock** | ETH_REFCLK = 50 MHz (desde el PHY) |
| **Pines** | ETH_MDC(C9), ETH_MDIO(A9), ETH_RSTN(B3), ETH_CRSDV(D9), ETH_RXERR(C10), ETH_RXD[1:0](D10,C11), ETH_TXEN(B9), ETH_TXD[1:0](A8,A10), ETH_INTN(B8) |
| **FPGA libre** | ~41,000 LUTs (65% del XC7A100T) |

El PHY está físicamente conectado a la FPGA pero **no se usa en el diseño actual**.

---

## Arquitectura propuesta

```
┌──────────────────────────────────────────────────────┐
│  FPGA (Artix-7 XC7A100T)                              │
│                                                       │
│  ┌─────────┐    ┌──────────┐    ┌────────────────┐   │
│  │ LAN8720A │◄──►│ eth_mac  │◄──►│ eth_bridge_cfs │   │
│  │  (PHY)   │RMII│ (MAC TX) │    │ + UDP framer   │   │
│  │  onboard │    │ + FIFOs  │    │ + 8 regs CFS   │   │
│  └─────────┘    └──────────┘    └───────┬────────┘   │
│                                          │             │
│  ┌──────────────────────┐    ┌──────────┴────────┐   │
│  │ neorv32_rov_motors   │    │ NEORV32 RV32IMC    │   │
│  │ (PWM, PID, encoders) │◄──►│ + firmware ROV     │   │
│  └──────────────────────┘    └────────────────────┘   │
│      CFS existente               CFS + Ethernet       │
└──────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
    PMOD JA (PWM)                  UART FTDI
```

### Capa FPGA (nueva)

1. **eth_mac.vhd** — MAC RMII 10/100 Mbps
   - Recibe trama → FIFO RX → bridge
   - Toma datos de FIFO TX → arma trama → PHY
   - CRC32 automático (TX) y verificación (RX)
   - ~1,500 LUTs estimado

2. **eth_bridge_cfs.vhd** — Bridge Ethernet ↔ CFS
   - Filtro UDP: solo responde a puerto configurable (ej. 6666)
   - Payload de telemetría: arma paquete UDP/IP mínimo con datos del CFS
   - Payload de comando: recibe comando UDP → escribe registro CFS
   - 8 registros extra en el espacio CFS (direcciones 0x20-0x3F)
   - ~1,000 LUTs

3. **Registros CFS adicionales** (no toca los 8 existentes del ROV):
   | Offset | Nombre | R/W | Descripción |
   |---|---|---|---|
   | 0x20 | ETH_CTRL | R/W | Reset, enable TX, loopback |
   | 0x24 | ETH_STATUS | R | Link up, speed, FIFO levels |
   | 0x28 | ETH_TX_LEN | R/W | Bytes a transmitir |
   | 0x2C | ETH_RX_LEN | R | Bytes recibidos |
   | 0x30 | ETH_MAC_LO | R/W | MAC address [31:0] |
   | 0x34 | ETH_MAC_HI | R/W | MAC address [47:32] |
   | 0x38 | ETH_IP | R/W | IP local |
   | 0x3C | ETH_PORT | R/W | Puerto UDP |

   El espacio CFS va de 0xFFEB0000 a 0xFFEBFFFF. El ROV usa 0x00-0x1F (8 regs). Ethernet ocuparía 0x20-0x3F, dejando 0x40+ libre.

### Capa firmware (modificación)

1. **Nuevo driver:** `app/eth.h` — API C++ sobre los registros ETH_*
   ```cpp
   void eth_init(const uint8_t mac[6], uint32_t ip, uint16_t port);
   void eth_send(const uint8_t *payload, uint16_t len);
   bool eth_recv(uint8_t *buf, uint16_t *len);  // non-blocking
   bool eth_link_up();
   ```

2. **Modificación de `print_telemetry()`** — ahora envía por Ethernet además de UART:
   ```
   if (eth_link_up() && g_telemetry_eth) {
       eth_send(telem_packet, telem_len);
   }
   ```

3. **Formato de paquete de telemetría** (binario, ~60 bytes):
   ```
   Offset  Size  Campo
   0       1     Versión (0x01)
   1       1     Flags (armed|hb|failsafe|eth_link)
   2       2     Sequence number
   4       2     Depth (cm, u16)
   6       2     Temperature (deci-C, i16)
   8       4×3   Timestamp ticks (u32)
   20      2×3   IMU roll/pitch/yaw (s1.14)
   26      2×6   PID outputs (s1.14)
   38      4×8   Encoder positions (u32)
   70      2     CRC16
   ```

4. **Nuevo comando UART:** `E [on|off]` — activar/desactivar telemetría Ethernet

### Capa PC

Recibir y visualizar con un script Python simple:
```python
import socket, struct
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 6666))
while True:
    data, addr = sock.recvfrom(1024)
    # parse + print or feed to plot
```
Evolución futura: dashboard web, Grafana, ROS bridge.

---

## Plan de implementación

### Fase 1 — MAC + Loopback (semana 1)
- [ ] Crear `eth_mac.vhd` (RMII TX/RX, CRC, FIFOs)
- [ ] Simular con testbench (XOR de payload, loopback interno)
- [ ] Agregar constraints de pines ETH_*
- [ ] Sintetizar y verificar timing
- [ ] Validar en hardware: loopback externo con cable Ethernet + PC

### Fase 2 — Bridge CFS + UDP (semana 2)
- [ ] Crear `eth_bridge_cfs.vhd` (filtro UDP/IP mínimo)
- [ ] Mapear los 8 registros CFS extra en `neorv32_cfs_custom.vhd`
- [ ] Probar escritura/lectura de registros ETH desde firmware
- [ ] Enviar primer paquete UDP desde firmware
- [ ] Recibirlo en PC con Wireshark + script Python

### Fase 3 — Telemetría (semana 3)
- [ ] Driver `eth.h` en firmware
- [ ] Adaptar `print_telemetry()` para envío binario por Ethernet
- [ ] Agregar comando `E` y flag `g_telemetry_eth`
- [ ] Script Python con display en consola
- [ ] Prueba de estrés: telemetría a 10 Hz por 1 hora

### Fase 4 — Comandos por Ethernet (semana 4, opcional)
- [ ] Filtro RX UDP en bridge: recibir comandos del PC
- [ ] Mismo formato que comandos UART, encapsulados en UDP
- [ ] Rate limiting y autenticación mínima
- [ ] **Nunca** permitir armado por Ethernet sin confirmación física

---

## Lo que NO cambia

| Componente | Sigue igual |
|---|---|
| `neorv32_rov_motors.vhd` | Sin cambios |
| `neorv32_cfs_custom.vhd` | Solo se agregan 8 regs extra, los 8 del ROV intactos |
| Watchdog / failsafe | Hardware, determinista, no depende de Ethernet |
| UART | Sigue funcionando como respaldo |
| PWM / encoders / PID | Sin cambios |
| Simulaciones existentes | No se rompen (los 8 regs del ROV no se tocan) |
| Heartbeat CFS | Igual, cada 50 ms |

---

## Riesgos y mitigación

| Riesgo | Prob. | Mitigación |
|---|---|---|
| Timing closure con MAC a 100 MHz | Media | El diseño actual tiene WNS=+6.49 ns; sobra margen |
| PHY no responde (hardware dañado) | Baja | Probar con loopback interno de FPGA primero |
| UDP fragmenta paquetes > MTU | Nula | Payload de telemetría < 80 bytes, bien por debajo de 1500 |
| Ethernet satura el bus CFS | Baja | El bridge usa FIFOs; el CPU solo lee/escribe registros, no cada byte |
| Interferencia con UART | Nula | Periféricos independientes |

---

## Recursos FPGA estimados

| Módulo | LUTs | FFs | BRAM |
|---|---|---|---|
| eth_mac (RMII + FIFO) | ~800 | ~600 | 2 |
| eth_bridge_cfs (UDP + registros) | ~400 | ~300 | 1 |
| **Total nuevo** | **~1,200** | **~900** | **3** |
| ROV actual | ~22,000 | — | — |
| **Total** | **~23,200** | — | — |
| **% FPGA** | **36.6%** | | |

Sobran ~40,000 LUTs.

---

## Notas de implementación

- MAC address: usar la OUI de Digilent o una local (02:00:00:xx:xx:xx)
- IP fija configurable desde firmware (ej. 192.168.1.100)
- El PHY LAN8720A requiere configuración MDIO inicial (auto-negotiation)
- ETH_REFCLK de 50 MHz viene del PHY, no del oscilador de 100 MHz
- La MAC RMII muestrea datos en el dominio de 50 MHz; necesita CDC hacia los 100 MHz del sistema
