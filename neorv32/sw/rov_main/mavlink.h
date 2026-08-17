// =============================================================================
// MAVLink v2 minimo para el ROV — UART0, dialecto common.xml
// =============================================================================
// TX: HEARTBEAT (1 Hz), ATTITUDE (10 Hz), SCALED_PRESSURE (2 Hz)
// RX: MANUAL_CONTROL (69), RC_CHANNELS_OVERRIDE (70), COMMAND_LONG (76)
// sysid=1 compid=1, sin firma. CRC-16/MCRF4XX con crc_extra por mensaje.
// =============================================================================
#ifndef ROV_MAVLINK_H
#define ROV_MAVLINK_H

void mavlink_init(void);
void mavlink_tick(uint64_t now_cycles);
void mavlink_parse(uint8_t c);
void mavlink_enable(int on);
int  mavlink_is_enabled(void);
int  mavlink_in_frame(void);   // 1 si hay un frame MAVLink en recepcion

#endif
