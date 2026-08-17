// =============================================================================
// MAVLink v2 minimo para el ROV ??? UART0, dialecto common.xml
// =============================================================================
#include <neorv32.h>
#include <string.h>
#include "mavlink.h"

// rov_cfs.h se incluye solo en main.c; aqui, prototipos externos
extern uint8_t rov_read_status(void);
extern int16_t rov_read_imu_roll(void);
extern int16_t rov_read_imu_pitch(void);
extern int16_t rov_read_imu_yaw(void);
extern uint16_t rov_read_depth_cm(void);
extern int16_t rov_read_depth_temp(void);
extern void rov_set_setpoint(int axis, int16_t val_s114);
extern void rov_arm(void);
extern void rov_disarm(void);
extern void rov_calibrate_encoders(void);
extern void control_free_mode(void);   // definido en main.c

#define AXIS_SURGE 0
#define AXIS_SWAY  1
#define AXIS_HEAVE 2
#define AXIS_YAW   5

// --- IDs y crc_extra (mavlink common) ---
#define MAV_HEARTBEAT        0
#define MAV_SCALED_PRESSURE  29
#define MAV_ATTITUDE         30
#define MAV_MANUAL_CONTROL   69
#define MAV_RC_OVERRIDE      70
#define MAV_COMMAND_LONG     76

#define CRCX_HEARTBEAT       50
#define CRCX_SCALED_PRESSURE 115
#define CRCX_ATTITUDE        39
#define CRCX_MANUAL_CONTROL  243
#define CRCX_RC_OVERRIDE     124
#define CRCX_COMMAND_LONG    152

#define MAV_CMD_ARM_DISARM   400
#define MAV_CMD_PREFLIGHT_CAL 241

static int      g_on;
static uint8_t  tx_seq;
static uint8_t  tx_buf[300];
static uint64_t g_next_hb, g_next_att, g_next_press;
static uint32_t g_clk;

// --- RX state machine ---
static uint8_t  rx_buf[300];
static uint8_t  rx_len;
static uint16_t rx_idx;
static uint8_t  rx_state;   // 0=buscar STX, 1=len, 2=cuerpo

// =============================================================================
// CRC-16/MCRF4XX (polinomio X.25)
// =============================================================================
static uint16_t crc_x25(uint16_t crc, const uint8_t *buf, int n) {
    while (n--) {
        crc ^= (uint16_t)(*buf++) << 8;
        for (int i = 0; i < 8; i++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021)
                                 : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

// =============================================================================
// Empaquetado little-endian
// =============================================================================
static void put_u16(uint8_t *p, uint16_t v) { p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); }
static void put_i16(uint8_t *p, int16_t v)  { put_u16(p, (uint16_t)v); }
static void put_u32(uint8_t *p, uint32_t v) {
    p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); p[2]=(uint8_t)(v>>16); p[3]=(uint8_t)(v>>24);
}
static void put_f32(uint8_t *p, float f)   { memcpy(p, &f, 4); }

static int16_t get_i16(const uint8_t *p) {
    return (int16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static uint16_t get_u16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
static float get_f32(const uint8_t *p) {
    float f; memcpy(&f, p, 4); return f;
}

// =============================================================================
// Frame TX
// =============================================================================
static void mav_send(uint32_t msgid, const uint8_t *payload, int len, uint8_t crcx) {
    tx_buf[0] = 0xFD;
    tx_buf[1] = (uint8_t)len;
    tx_buf[2] = 0;   // incompat_flags (sin firma)
    tx_buf[3] = 0;   // compat_flags
    tx_buf[4] = tx_seq++;
    tx_buf[5] = 1;   // sysid
    tx_buf[6] = 1;   // compid (AUTOPILOT1)
    tx_buf[7] = (uint8_t)(msgid & 0xFF);
    tx_buf[8] = (uint8_t)((msgid >> 8) & 0xFF);
    tx_buf[9] = (uint8_t)((msgid >> 16) & 0xFF);
    for (int i = 0; i < len; i++) tx_buf[10 + i] = payload[i];

    uint16_t crc = crc_x25(0xFFFF, &tx_buf[1], 9 + len); // desde len hasta payload
    crc = crc_x25(crc, &crcx, 1);
    tx_buf[10 + len]     = (uint8_t)(crc & 0xFF);
    tx_buf[10 + len + 1] = (uint8_t)(crc >> 8);

    for (int i = 0; i < 12 + len; i++) neorv32_uart0_putc(tx_buf[i]);
}

static uint32_t boot_ms(uint64_t now) { return (uint32_t)(now / 100000u); }

// =============================================================================
// Mensajes TX
// =============================================================================
static void send_heartbeat(void) {
    uint8_t st = rov_read_status();
    uint8_t armed = (st & 0x80) ? 1 : 0;
    uint8_t p[9];
    put_u32(p + 0, 0);                 // custom_mode
    p[4] = 16;                         // MAV_TYPE_SUBMARINE
    p[5] = 8;                          // MAV_AUTOPILOT_INVALID
    p[6] = (uint8_t)(0x80 | 0x04 | (armed ? 0x01 : 0)); // custom+auto+armed
    p[7] = armed ? 4 : 3;              // ACTIVE / STANDBY
    p[8] = 3;                          // mavlink_version
    mav_send(MAV_HEARTBEAT, p, 9, CRCX_HEARTBEAT);
}

static void send_attitude(uint64_t now) {
    uint8_t p[28];
    put_u32(p + 0, boot_ms(now));
    put_f32(p + 4,  (float)rov_read_imu_roll()  / 16384.0f);
    put_f32(p + 8,  (float)rov_read_imu_pitch() / 16384.0f);
    put_f32(p + 12, (float)rov_read_imu_yaw()   / 16384.0f);
    put_f32(p + 16, 0.0f);   // rollspeed (CFS no expone velocidad angular)
    put_f32(p + 20, 0.0f);
    put_f32(p + 24, 0.0f);
    mav_send(MAV_ATTITUDE, p, 28, CRCX_ATTITUDE);
}

static void send_scaled_pressure(uint64_t now) {
    uint8_t p[16];
    // CFS da profundidad en cm (no presion directa): aproximo presion absoluta
    // como 1013.25 hPa + depth_cm * 0.0980665 hPa/cm (~1 hPa por 10.2 cm)
    float depth_m = (float)rov_read_depth_cm() / 100.0f;
    float press_hpa = 1013.25f + depth_m * 98.0665f;
    put_u32(p + 0, boot_ms(now));
    put_f32(p + 4, press_hpa);
    put_f32(p + 8, 0.0f);                    // press_diff
    put_i16(p + 12, (int16_t)(rov_read_depth_temp() * 10)); // cdegC
    put_i16(p + 14, 0);
    mav_send(MAV_SCALED_PRESSURE, p, 16, CRCX_SCALED_PRESSURE);
}

// =============================================================================
// RX: conversion sticks -> s1.14 y aplicacion al CFS
// =============================================================================
static int16_t stick_to_s114(int16_t stick) {   // -1000..1000 -> -1.0..+1.0
    int32_t v = ((int32_t)stick * 16384) / 1000;
    if (v > 16383) v = 16383;
    if (v < -16384) v = -16384;
    return (int16_t)v;
}

static int16_t rc_to_s114(uint16_t raw) {       // 1000..2000 -> -1.0..+1.0
    int32_t v = ((int32_t)raw - 1500) * 32768 / 1000;
    if (v > 16383) v = 16383;
    if (v < -16384) v = -16384;
    return (int16_t)v;
}

static void handle_manual_control(const uint8_t *p) {
    control_free_mode();   // manual = sin holds
    rov_set_setpoint(AXIS_SURGE, stick_to_s114(get_i16(p + 0)));
    rov_set_setpoint(AXIS_SWAY,  stick_to_s114(get_i16(p + 2)));
    rov_set_setpoint(AXIS_HEAVE, stick_to_s114(get_i16(p + 4))); // z: + = abajo
    rov_set_setpoint(AXIS_YAW,   stick_to_s114(get_i16(p + 6)));
}

static void handle_rc_override(const uint8_t *p) {
    control_free_mode();
    // convencion ArduSub: ch1=surge, ch2=sway, ch3=heave, ch4=yaw
    rov_set_setpoint(AXIS_SURGE, rc_to_s114(get_u16(p + 2)));
    rov_set_setpoint(AXIS_SWAY,  rc_to_s114(get_u16(p + 4)));
    rov_set_setpoint(AXIS_HEAVE, rc_to_s114(get_u16(p + 6)));
    rov_set_setpoint(AXIS_YAW,   rc_to_s114(get_u16(p + 8)));
}

static void handle_command_long(const uint8_t *p) {
    uint16_t cmd = get_u16(p + 2);
    float p1 = get_f32(p + 5);
    if (cmd == MAV_CMD_ARM_DISARM) {
        if (p1 > 0.5f) rov_arm();
        else           rov_disarm();
    } else if (cmd == MAV_CMD_PREFLIGHT_CAL) {
        rov_calibrate_encoders();
    }
}

// =============================================================================
// Parser RX (state machine)
// rx_buf: [0]=incompat [1]=compat [2]=seq [3]=sysid [4]=compid
//         [5..7]=msgid [8..8+len-1]=payload [8+len..9+len]=crc
// =============================================================================
static void dispatch_msg(uint32_t msgid, const uint8_t *p, uint8_t len) {
    (void)len;
    switch (msgid) {
        case MAV_MANUAL_CONTROL:  handle_manual_control(p);  break;
        case MAV_RC_OVERRIDE:     handle_rc_override(p);     break;
        case MAV_COMMAND_LONG:    handle_command_long(p);    break;
        default: break;
    }
}

void mavlink_parse(uint8_t c) {
    switch (rx_state) {
        case 0:
            if (c == 0xFD) { rx_idx = 0; rx_state = 1; }
            break;
        case 1:
            rx_len = c;
            if (rx_len > 250) rx_state = 0;
            else { rx_idx = 0; rx_state = 2; }
            break;
        case 2:
            rx_buf[rx_idx++] = c;
            if (rx_idx >= (uint16_t)rx_len + 10) {
                uint16_t crc_rx = (uint16_t)rx_buf[rx_len + 8] |
                                  ((uint16_t)rx_buf[rx_len + 9] << 8);
                uint32_t msgid = (uint32_t)rx_buf[5] | ((uint32_t)rx_buf[6] << 8) |
                                 ((uint32_t)rx_buf[7] << 16);
                uint8_t known_crcx = 0;
                int known = 1;
                switch (msgid) {
                    case MAV_MANUAL_CONTROL: known_crcx = CRCX_MANUAL_CONTROL; break;
                    case MAV_RC_OVERRIDE:    known_crcx = CRCX_RC_OVERRIDE;    break;
                    case MAV_COMMAND_LONG:   known_crcx = CRCX_COMMAND_LONG;   break;
                    default: known = 0; break;
                }
                if (known) {
                    // recomponer: len + incompat..payload (mismo layout que TX)
                    tx_buf[0] = rx_len;
                    for (int i = 0; i < 8 + rx_len; i++) tx_buf[1 + i] = rx_buf[i];
                    uint16_t crc = crc_x25(0xFFFF, tx_buf, 9 + rx_len);
                    crc = crc_x25(crc, &known_crcx, 1);
                    if (crc == crc_rx) dispatch_msg(msgid, &rx_buf[8], rx_len);
                }
                rx_state = 0;
            }
            break;
    }
}

// =============================================================================
// API
// =============================================================================
void mavlink_init(void) {
    g_clk = neorv32_sysinfo_get_clk();
    g_on = 0;
    tx_seq = 0;
    rx_state = 0;
    g_next_hb = g_next_att = g_next_press = neorv32_cpu_get_cycle();
}

void mavlink_enable(int on) {
    g_on = on;
    if (on) neorv32_uart0_puts("\nMAVLink mode ON (telemetria por UART0, 'q off' para consola)\n");
    else    neorv32_uart0_puts("MAVLink mode OFF (consola)\n");
}

int mavlink_is_enabled(void) { return g_on; }

int mavlink_in_frame(void) { return rx_state != 0; }

void mavlink_tick(uint64_t now) {
    if (!g_on) return;

    if ((uint64_t)(now - g_next_hb) >= g_clk) {           // 1 Hz
        g_next_hb = now;
        send_heartbeat();
    }
    if ((uint64_t)(now - g_next_att) >= g_clk / 10) {     // 10 Hz
        g_next_att = now;
        send_attitude(now);
    }
    if ((uint64_t)(now - g_next_press) >= g_clk / 2) {    // 2 Hz
        g_next_press = now;
        send_scaled_pressure(now);
    }
}
