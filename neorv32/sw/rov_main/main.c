// =============================================================================
// NEORV32 Nexys A7 — ROV Main Firmware (NVehicleManager-style)
// =============================================================================
// Validated against the corrected rov_cfs.h (ground-truth VHDL register map,
// CFS @ 0xFFEB0000) and the corrected Nexys A7 pinout (2026-08-12).
//
// Structure (cooperative, fixed-rate):
//   - 50 ms: heartbeat (safety watchdog) + closed-loop control (20 Hz)
//   - 2 s:   telemetry dump (toggle 'v')
//   - console: interactive command interface (cockpit / bench)
//
// Closed loops (hardware CFS PID):
//   - depth-hold: heave PID, setpoint=target depth, current=depth sensor
//   - yaw-hold:   yaw PID, setpoint=target heading, current=IMU yaw
// =============================================================================

#include <neorv32.h>
#include "rov_cfs.h"
#include "sensors.h"

#define NUM_AXES       6
#define NUM_MTRS       8
#define TELEM_MS       2000u
#define HEARTBEAT_MS   50u
#define LED_TOGGLE_MS  500u
#define DEPTH_SCALE    164    // cm -> s1.14 meters (163.84 ≈ 164)

static const char *const kAxisNames[NUM_AXES] = {
    "Surge", "Sway", "Heave", "Roll", "Pitch", "Yaw"
};

// OCTO mixer (48 coeffs, s1.14), +-0.176 contribution per axis
static const uint8_t kDefaultMixer[48] = {
    0x2D,0x00,0x00,0x00,0x2D,0x00, 0x00,0x2D,0x00,0x2D,0x00,0x00,
    0x2D,0x00,0x00,0x00,0xD3,0x00, 0x00,0x2D,0x00,0xD3,0x00,0x00,
    0xD3,0x00,0x00,0x00,0xD3,0x00, 0x00,0xD3,0x00,0x2D,0x00,0x00,
    0xD3,0x00,0x00,0x00,0x2D,0x00, 0x00,0xD3,0x00,0xD3,0x00,0x00,
};

static uint32_t g_clock_hz;
static uint64_t g_last_hb;
static uint64_t g_last_ctrl;
static uint64_t g_last_led;
static uint64_t g_last_telem;
static int      g_telem_enabled;
static int      g_depth_hold_on;     // depth-hold active
static int32_t  g_depth_target_cm;   // target depth in cm
static int      g_yaw_hold_on;       // yaw-hold active
static int16_t  g_yaw_target_s114;   // target yaw (s1.14 rad)
static int      g_failsafe_seen;

// =============================================================================
// UART helpers (SDK printf is minimal: no %02X/%ld; use explicit helpers)
// =============================================================================
static void uart_puts(const char *s) {
    while (*s) neorv32_uart0_putc(*s++);
}

static void uart_dec(int32_t n) {
    char buf[12];
    int i = 10;
    int neg = 0;
    buf[11] = '\0';
    if (n < 0) { neg = 1; n = -n; }
    do { buf[i--] = (char)('0' + (n % 10)); n /= 10; } while (n > 0 && i >= 0);
    if (neg && i >= 0) buf[i--] = '-';
    uart_puts(&buf[i + 1]);
}

static void uart_hex32(uint32_t n) {
    static const char hex[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4)
        neorv32_uart0_putc(hex[(n >> i) & 0xF]);
}

static void uart_s114(int16_t v) {
    int neg = v < 0;
    int32_t mag = v;
    if (neg) mag = -mag;
    int32_t whole = mag >> 14;
    int32_t frac  = ((uint32_t)mag * 10000u) >> 14;
    if (neg) neorv32_uart0_putc('-');
    neorv32_uart0_putc((char)('0' + (whole % 10)));
    neorv32_uart0_putc('.');
    for (int i = 1000; i >= 1; i /= 10) {
        neorv32_uart0_putc((char)('0' + ((frac / i) % 10)));
    }
}

static int elapsed_ms(uint64_t now, uint64_t then, uint32_t ms) {
    return (uint64_t)(now - then) >= ((uint64_t)g_clock_hz * ms) / 1000u;
}

// =============================================================================
// Heartbeat + closed-loop control (20 Hz)
// =============================================================================
static void service_heartbeat(void) {
    uint64_t now = neorv32_cpu_get_cycle();
    if (elapsed_ms(now, g_last_hb, HEARTBEAT_MS)) {
        g_last_hb = now;
        rov_heartbeat();
    }
}

static void delay_with_heartbeat(uint32_t delay_ms) {
    while (delay_ms--) {
        neorv32_aux_delay_ms(g_clock_hz, 1);
        service_heartbeat();
    }
}

static void control_tick(void) {
    uint8_t st = rov_read_status();

    // sensores -> CFS (gyro 20 Hz, profundidad 4 Hz)
    sensors_poll();

    // failsafe monitor: heartbeat lost -> motors disarmed by hardware
    if (!(st & STATUS_ARMED)) {
        if (!g_failsafe_seen) {
            g_failsafe_seen = 1;
            uart_puts("\n[SAFETY] Motors disarmed (heartbeat lost or manual disarm).\n");
        }
        g_depth_hold_on = 0;
        g_yaw_hold_on   = 0;
        return;
    }
    g_failsafe_seen = 0;

    // depth hold: feed heave PID with depth sensor (cm -> s1.14 m)
    if (g_depth_hold_on) {
        uint16_t depth_cm = rov_read_depth_cm();
        int16_t cur = (int16_t)((uint32_t)depth_cm * DEPTH_SCALE);
        int16_t sp  = (int16_t)((uint32_t)g_depth_target_cm * DEPTH_SCALE);
        rov_set_pid_current(AXIS_HEAVE, cur);
        rov_set_setpoint(AXIS_HEAVE, sp);
        rov_enable_pid(1 << AXIS_HEAVE);
    }

    // yaw hold: feed yaw PID with IMU yaw (already s1.14)
    if (g_yaw_hold_on) {
        int16_t yaw = rov_read_imu_yaw();
        rov_set_pid_current(AXIS_YAW, yaw);
        rov_set_setpoint(AXIS_YAW, g_yaw_target_s114);
        rov_enable_pid(1 << AXIS_YAW);
    }
}

// =============================================================================
// Command parser
// =============================================================================
static char rx_buf[128];
static int  rx_idx;

static int parse_int(const char **s) {
    while (**s == ' ') (*s)++;
    int neg = 0;
    if (**s == '-') { neg = 1; (*s)++; }
    int val = 0;
    while (**s >= '0' && **s <= '9') { val = val * 10 + (**s - '0'); (*s)++; }
    return neg ? -val : val;
}

static int parse_hex(const char **s) {
    while (**s == ' ') (*s)++;
    if ((*s)[0] == '0' && ((*s)[1] == 'x' || (*s)[1] == 'X')) *s += 2;
    int val = 0;
    for (;;) {
        char c = **s;
        if      (c >= '0' && c <= '9') val = (val << 4) | (c - '0');
        else if (c >= 'a' && c <= 'f') val = (val << 4) | (c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') val = (val << 4) | (c - 'A' + 10);
        else break;
        (*s)++;
    }
    return val;
}

static void cmd_help(void) {
    uart_puts(
        "\nROV Firmware Commands:\n"
        " h              Help\n"
        " i              System info\n"
        " s              Safety status (armed, heartbeat, failsafe)\n"
        " a [0|1]        Disarm (0) / Arm (1)\n"
        " c              Calibrate encoders\n"
        " e [motor]      Read encoder (0-7, or all)\n"
        " m              Read IMU (roll, pitch, yaw)\n"
        " d              Read depth (cm)\n"
        " u              Sensor status (MPU9250 / MS5837)\n"
        " p              Read PID outputs (6 axes)\n"
        " t <axis> <hex> Set setpoint (s1.14)\n"
        " k <axis> <kp> <ki> <kd>  Set PID gains (s1.14 hex)\n"
        " n <axis> <hex> Set PID current position\n"
        " g <mask>       Enable PID axes (bitmask 0-63)\n"
        " o <cm>         Depth-hold: target depth in cm\n"
        " y <hex>        Yaw-hold: target heading (s1.14 rad)\n"
        " f              Free mode: disable depth/yaw hold\n"
        " l [mask]       LED test\n"
        " v              Toggle telemetry\n"
        " r              ROV re-init\n"
        " x              Dump raw CFS registers\n"
    );
}

static void cmd_info(void) {
    uart_puts("\n=== NEORV32 ROV System ===\n");
    uart_puts("Hardware: v");
    neorv32_aux_print_hw_version(neorv32_cpu_csr_read(CSR_MIMPID));
    uart_puts("\nClock: "); uart_dec((int32_t)g_clock_hz); uart_puts(" Hz\n");
    uart_puts("IMEM: 64 KiB  DMEM: 32 KiB\n");
    uart_puts("CFS @ 0xFFEB0000 (8 regs, ROV control, SDK v1.13.3)\n");
}

static void cmd_status(void) {
    uint8_t st = rov_read_status();
    uart_puts("\n--- Safety Status ---\n");
    uart_puts("Armed:      "); uart_puts((st & STATUS_ARMED)     ? "YES\n" : "NO\n");
    uart_puts("Heartbeat:  "); uart_puts((st & STATUS_HEARTBEAT) ? "OK\n"  : "FAIL\n");
    uart_puts("Failsafe:   "); uart_puts((st & STATUS_FAILSAFE)  ? "ACTIVE\n" : "normal\n");
    uart_puts("HB count:   "); uart_dec(rov_read_hb_count()); uart_puts("\n");
    uart_puts("Depth hold: "); uart_puts(g_depth_hold_on ? "ON (" : "off");
    if (g_depth_hold_on) { uart_dec(g_depth_target_cm); uart_puts(" cm)"); }
    uart_puts("\nYaw hold:   "); uart_puts(g_yaw_hold_on ? "ON (" : "off");
    if (g_yaw_hold_on) { uart_s114(g_yaw_target_s114); uart_puts(" rad)"); }
    uart_puts("\n");
}

static void cmd_arm(int arm) {
    if (arm) {
        uart_puts("\nArming motors...\n");
        for (int i = 0; i < 5; i++) { rov_heartbeat(); delay_with_heartbeat(10); }
        rov_arm();
    } else {
        uart_puts("\nDisarming motors.\n");
        rov_disarm();
        g_depth_hold_on = 0;
        g_yaw_hold_on   = 0;
    }
    delay_with_heartbeat(100);
    cmd_status();
}

static void cmd_calibrate(void) {
    uart_puts("\nCalibrating encoders...\n");
    rov_calibrate_encoders();
    uart_puts("Done.\n");
}

static void cmd_encoders(int motor) {
    uart_puts("\n--- Encoders ---\n");
    int start = motor < 0 ? 0 : motor;
    int end   = motor < 0 ? NUM_MTRS - 1 : motor;
    for (int m = start; m <= end; m++) {
        uint32_t pos = rov_read_encoder_position(m);
        int32_t  vel = (int32_t)rov_read_encoder_velocity(m);
        uart_puts("ENC"); uart_dec(m); uart_puts(": pos=");
        uart_hex32(pos); uart_puts(" vel="); uart_dec(vel); uart_puts("\n");
    }
}

static void cmd_imu(void) {
    uart_puts("\n--- IMU (s1.14 rad) ---\n");
    uart_puts("Roll:  "); uart_s114(rov_read_imu_roll());  uart_puts("\n");
    uart_puts("Pitch: "); uart_s114(rov_read_imu_pitch()); uart_puts("\n");
    uart_puts("Yaw:   "); uart_s114(rov_read_imu_yaw());   uart_puts("\n");
}

static void cmd_depth(void) {
    uart_puts("\nDepth: "); uart_dec(rov_read_depth_cm()); uart_puts(" cm\n");
    uart_puts("Temp:  "); uart_dec(rov_read_depth_temp()); uart_puts(" (C*10)\n");
}

static void cmd_pid_outputs(void) {
    uart_puts("\n--- PID Outputs (s1.14) ---\n");
    for (int a = 0; a < NUM_AXES; a++) {
        uart_puts(kAxisNames[a]); uart_puts(": ");
        uart_s114(rov_read_pid_output(a)); uart_puts("\n");
    }
}

static void cmd_setpoint(int axis, int16_t val) {
    if (axis < 0 || axis >= NUM_AXES) { uart_puts("Invalid axis\n"); return; }
    uart_puts("Setpoint "); uart_puts(kAxisNames[axis]); uart_puts(" = ");
    uart_s114(val); uart_puts("\n");
    rov_set_setpoint(axis, val);
}

static void cmd_pid_gain(int axis, int16_t kp, int16_t ki, int16_t kd) {
    if (axis < 0 || axis >= NUM_AXES) { uart_puts("Invalid axis\n"); return; }
    uart_puts("PID "); uart_puts(kAxisNames[axis]); uart_puts(" Kp=");
    uart_s114(kp); uart_puts(" Ki="); uart_s114(ki);
    uart_puts(" Kd="); uart_s114(kd); uart_puts("\n");
    rov_set_pid_gain(axis, kp, ki, kd);
}

static void cmd_pid_current(int axis, int16_t val) {
    if (axis < 0 || axis >= NUM_AXES) { uart_puts("Invalid axis\n"); return; }
    uart_puts("PID current "); uart_puts(kAxisNames[axis]); uart_puts(" = ");
    uart_s114(val); uart_puts("\n");
    rov_set_pid_current(axis, val);
}

static void cmd_pid_enable(uint8_t mask) {
    uart_puts("PID enable mask: 0b");
    for (int i = 5; i >= 0; i--) neorv32_uart0_putc((mask & (1 << i)) ? '1' : '0');
    uart_puts("\n");
    rov_enable_pid(mask);
}

static void cmd_depth_hold(int32_t cm) {
    g_depth_target_cm = cm;
    g_depth_hold_on   = 1;
    uart_puts("Depth hold: target "); uart_dec(cm); uart_puts(" cm\n");
    // seed the PID with current depth right away
    uint16_t depth_cm = rov_read_depth_cm();
    rov_set_pid_current(AXIS_HEAVE, (int16_t)((uint32_t)depth_cm * DEPTH_SCALE));
    rov_set_setpoint(AXIS_HEAVE, (int16_t)((uint32_t)cm * DEPTH_SCALE));
    rov_enable_pid(1 << AXIS_HEAVE);
}

static void cmd_yaw_hold(int16_t target_s114) {
    g_yaw_target_s114 = target_s114;
    g_yaw_hold_on     = 1;
    uart_puts("Yaw hold: target "); uart_s114(target_s114); uart_puts(" rad\n");
    rov_set_pid_current(AXIS_YAW, rov_read_imu_yaw());
    rov_set_setpoint(AXIS_YAW, target_s114);
    rov_enable_pid(1 << AXIS_YAW);
}

static void cmd_free_mode(void) {
    g_depth_hold_on = 0;
    g_yaw_hold_on   = 0;
    rov_enable_pid(0);
    uart_puts("Free mode: depth/yaw hold disabled, PID off.\n");
}

static void cmd_leds(uint32_t mask) {
    for (int i = 0; i < 3; i++) {
        neorv32_gpio_port_set(mask & 0xFFFF);
        delay_with_heartbeat(200);
        neorv32_gpio_port_set(0);
        delay_with_heartbeat(200);
    }
}

static void cmd_reinit(void) {
    uart_puts("\nRe-initializing ROV...\n");
    rov_disarm();
    delay_with_heartbeat(100);
    rov_init();
    for (int i = 0; i < 48; i++) {
        int16_t c = (int16_t)((uint16_t)kDefaultMixer[i] << 8);
        rov_set_mixer_coeff(i, c);
    }
    g_depth_hold_on = 0;
    g_yaw_hold_on   = 0;
    cmd_status();
}

// ===========================================================================
// Telemetry
// ===========================================================================
static void print_telemetry(void) {
    uint8_t st = rov_read_status();
    uart_puts("\n--- TEL ---\n");
    uart_puts("Status: ");
    uart_puts((st & STATUS_ARMED) ? "ARMED " : "disarmed ");
    uart_puts((st & STATUS_HEARTBEAT) ? "HB_OK " : "HB_FAIL ");
    uart_puts((st & STATUS_FAILSAFE) ? "FAILSAFE" : "safe");
    uart_puts("\n");
    uart_puts("Depth: "); uart_dec(rov_read_depth_cm()); uart_puts(" cm\n");
    uart_puts("Encoders: ");
    for (int m = 0; m < NUM_MTRS; m++) {
        uart_dec((int32_t)rov_read_encoder_position(m)); uart_puts(" ");
    }
    uart_puts("\nIMU: R="); uart_s114(rov_read_imu_roll());
    uart_puts(" P=");      uart_s114(rov_read_imu_pitch());
    uart_puts(" Y=");      uart_s114(rov_read_imu_yaw());
    uart_puts("\nPID: ");
    for (int a = 0; a < NUM_AXES; a++) {
        uart_puts(kAxisNames[a]); uart_puts("=");
        uart_s114(rov_read_pid_output(a)); uart_puts(" ");
    }
    uart_puts("\n---------------\n");
}

// ===========================================================================
// Command dispatch
// ===========================================================================
static void process_command(void) {
    if (rx_idx == 0) return;
    const char *s = rx_buf;

    switch (s[0]) {
    case 'h': cmd_help(); break;
    case 'i': cmd_info(); break;
    case 's': cmd_status(); break;
    case 'a': { s++; cmd_arm(parse_int(&s) != 0); break; }
    case 'c': cmd_calibrate(); break;
    case 'e': {
        s++;
        int m = -1;
        while (*s == ' ') s++;
        if (*s >= '0' && *s <= '9') m = parse_int(&s);
        cmd_encoders(m);
        break;
    }
    case 'm': cmd_imu(); break;
    case 'd': cmd_depth(); break;
    case 'u': sensors_status(); break;
    case 'p': cmd_pid_outputs(); break;
    case 't': {
        s++;
        int     axis = parse_int(&s);
        int16_t val  = (int16_t)parse_hex(&s);
        cmd_setpoint(axis, val);
        break;
    }
    case 'k': {
        s++;
        int     axis = parse_int(&s);
        int16_t kp   = (int16_t)parse_hex(&s);
        int16_t ki   = (int16_t)parse_hex(&s);
        int16_t kd   = (int16_t)parse_hex(&s);
        cmd_pid_gain(axis, kp, ki, kd);
        break;
    }
    case 'n': {
        s++;
        int     axis = parse_int(&s);
        int16_t val  = (int16_t)parse_hex(&s);
        cmd_pid_current(axis, val);
        break;
    }
    case 'g': { s++; cmd_pid_enable((uint8_t)parse_int(&s)); break; }
    case 'o': { s++; cmd_depth_hold(parse_int(&s)); break; }
    case 'y': { s++; cmd_yaw_hold((int16_t)parse_hex(&s)); break; }
    case 'f': cmd_free_mode(); break;
    case 'l': {
        s++;
        while (*s == ' ') s++;
        cmd_leds(*s ? (uint32_t)parse_hex(&s) : 0xFFu);
        break;
    }
    case 'v': g_telem_enabled = !g_telem_enabled;
              uart_puts(g_telem_enabled ? "\nTelemetry ON\n" : "\nTelemetry OFF\n"); break;
    case 'r': cmd_reinit(); break;
    case 'x':
        uart_puts("\n--- Raw CFS registers ---\n");
        for (int i = 0; i < 8; i++) {
            uart_puts("REG"); uart_dec(i); uart_puts(": 0x");
            uart_hex32(NEORV32_CFS->REG[i]); uart_puts("  ");
        }
        uart_puts("\nGPIO_IN (switches): 0x");
        uart_hex32(neorv32_gpio_port_get());
        uart_puts("\n");
        break;
    default:  uart_puts("\nUnknown command. 'h' for help.\n"); break;
    }

    rx_idx = 0;
    for (int i = 0; i < 128; i++) rx_buf[i] = 0;
}

// ===========================================================================
// Main
// ===========================================================================
int main(void) {
    g_clock_hz       = neorv32_sysinfo_get_clk();
    g_last_hb        = neorv32_cpu_get_cycle();
    g_last_ctrl      = g_last_hb;
    g_last_led       = g_last_hb;
    g_last_telem     = g_last_hb;
    g_telem_enabled  = 0;
    g_depth_hold_on  = 0;
    g_yaw_hold_on    = 0;
    g_failsafe_seen  = 0;
    rx_idx           = 0;

    neorv32_uart0_setup(115200, 0);
    neorv32_uart0_puts("\n\n");
    uart_puts("========================================\n");
    uart_puts(" NEORV32 Nexys A7 - ROV Main Firmware\n");
    uart_puts(" RV32IMC @ 100 MHz | CFS @ 0xFFEB0000\n");
    uart_puts(" Driver: corrected VHDL map (2026-08-12)\n");
    uart_puts("========================================\n\n");

    uart_puts("Clock: "); uart_dec((int32_t)g_clock_hz); uart_puts(" Hz\n");

    neorv32_gpio_port_set(0);

    // --- Sensores primero (init lento; si se hiciera tras arm, el failsafe
    //     desarmaría al ROV antes de arrancar el loop) ---
    sensors_init();

    // --- ROV init: hb timeout 200ms, heartbeat, arm, setpoints neutral ---
    uart_puts("CFS: initializing ROV subsystem...\n");
    rov_init();
    for (int i = 0; i < 48; i++) {
        int16_t c = (int16_t)((uint16_t)kDefaultMixer[i] << 8);
        rov_set_mixer_coeff(i, c);
    }
    uart_puts("Mixer: OCTO defaults loaded.\n");
    cmd_status();

    uart_puts("\nType 'h' for help.\n\nCMD:> ");

    for (;;) {
        // --- UART RX ---
        if (neorv32_uart0_char_received()) {
            char c = (char)neorv32_uart0_char_received_get();
            if (c == '\r' || c == '\n') {
                rx_buf[rx_idx] = '\0';
                neorv32_uart0_puts("\r\n");
                process_command();
                uart_puts("CMD:> ");
            } else if (c == '\b' || c == 0x7F) {
                if (rx_idx > 0) { rx_idx--; neorv32_uart0_puts("\b \b"); }
            } else if (rx_idx < 127) {
                rx_buf[rx_idx++] = c;
                neorv32_uart0_putc(c);
            }
        }

        // --- 50 ms heartbeat + 20 Hz control ---
        uint64_t now = neorv32_cpu_get_cycle();
        service_heartbeat();
        if (elapsed_ms(now, g_last_ctrl, HEARTBEAT_MS)) {
            g_last_ctrl = now;
            control_tick();
        }

        // --- LED heartbeat ---
        if (elapsed_ms(now, g_last_led, LED_TOGGLE_MS)) {
            g_last_led = now;
            neorv32_gpio_pin_toggle(0);
        }

        // --- Telemetry ---
        if (g_telem_enabled && elapsed_ms(now, g_last_telem, TELEM_MS)) {
            g_last_telem = now;
            print_telemetry();
        }
    }

    return 0;
}
