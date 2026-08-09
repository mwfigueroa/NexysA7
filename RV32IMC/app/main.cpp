#include <neorv32.h>
#include "rov_cfs.h"

#ifndef RV32IMC_CPU_HZ
#error "Defina RV32IMC_CPU_HZ (lo hace CMakeLists.txt)."
#endif

static constexpr uint32_t kLedMask  = 0x0000FFFFu;
static constexpr int      kNumAxes  = 6;
static constexpr int      kNumMtrs  = 8;
static constexpr uint32_t kTelemMs  = 2000u;
static constexpr uint32_t kHeartbeatMs = 50u;
static constexpr uint32_t kLedToggleMs = 500u;

static const char *const kAxisNames[] = {
    "Surge", "Sway", "Heave", "Roll", "Pitch", "Yaw"
};

static const uint8_t kDefaultMixer[48] = {
    0x2D,0x00,0x00,0x00,0x2D,0x00, 0x00,0x2D,0x00,0x2D,0x00,0x00,
    0x2D,0x00,0x00,0x00,0xD3,0x00, 0x00,0x2D,0x00,0xD3,0x00,0x00,
    0xD3,0x00,0x00,0x00,0xD3,0x00, 0x00,0xD3,0x00,0x2D,0x00,0x00,
    0xD3,0x00,0x00,0x00,0x2D,0x00, 0x00,0xD3,0x00,0xD3,0x00,0x00,
};

static uint32_t  g_clock_hz;
static uint32_t  g_last_heartbeat;
static uint32_t  g_last_led;
static uint32_t  g_last_telem;
static bool      g_telem_enabled;

// ===========================================================================
// UART helpers
// ===========================================================================
static void uart_puts(const char *s) {
    while (*s) neorv32_uart0_putc(*s++);
}

static void uart_print_dec(int32_t n) {
    char buf[12];
    int  i = 10;
    buf[11] = '\0';
    bool neg = n < 0;
    if (neg) n = -n;
    do { buf[i--] = '0' + (n % 10); n /= 10; } while (n > 0 && i >= 0);
    if (neg && i >= 0) buf[i--] = '-';
    uart_puts(&buf[i + 1]);
}

static void uart_print_hex32(uint32_t n) {
    static const char hex[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4)
        neorv32_uart0_putc(hex[(n >> i) & 0xF]);
}

static void uart_print_s114(int16_t v) {
    bool neg = v < 0;
    int32_t magnitude = v;
    if (neg) magnitude = -magnitude;
    int32_t whole = magnitude >> 14;
    int32_t frac  = ((uint32_t)magnitude * 10000u) >> 14;
    if (neg) neorv32_uart0_putc('-');
    neorv32_uart0_putc('0' + (whole & 0xF));
    neorv32_uart0_putc('.');
    char fb[5];
    fb[4] = '\0';
    for (int i = 3; i >= 0; i--) { fb[i] = '0' + (frac % 10); frac /= 10; }
    uart_puts(fb);
}

static bool elapsed(uint32_t now, uint32_t then, uint32_t interval_ms) {
    return (uint32_t)(now - then) >= (g_clock_hz / 1000u) * interval_ms;
}

static void service_heartbeat() {
    uint32_t now = neorv32_cpu_csr_read(CSR_MCYCLE);
    if (elapsed(now, g_last_heartbeat, kHeartbeatMs)) {
        g_last_heartbeat = now;
        rov_heartbeat();
    }
}

static void delay_with_heartbeat(uint32_t delay_ms) {
    while (delay_ms--) {
        neorv32_aux_delay_ms(g_clock_hz, 1);
        service_heartbeat();
    }
}

// ===========================================================================
// Command parser
// ===========================================================================
static char rx_buf[128];
static int  rx_idx;

static int  parse_int(const char **s) {
    while (**s == ' ') (*s)++;
    bool neg = false;
    if (**s == '-') { neg = true; (*s)++; }
    int val = 0;
    while (**s >= '0' && **s <= '9') { val = val * 10 + (**s - '0'); (*s)++; }
    return neg ? -val : val;
}

static int  parse_hex(const char **s) {
    while (**s == ' ') (*s)++;
    if ((*s)[0] == '0' && ((*s)[1] == 'x' || (*s)[1] == 'X')) *s += 2;
    int val = 0;
    while (1) {
        char c = **s;
        if      (c >= '0' && c <= '9') val = (val << 4) | (c - '0');
        else if (c >= 'a' && c <= 'f') val = (val << 4) | (c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') val = (val << 4) | (c - 'A' + 10);
        else break;
        (*s)++;
    }
    return val;
}

// ===========================================================================
// Command handlers
// ===========================================================================
static void cmd_help() {
    uart_puts(
        "\nROV Firmware Commands:\n"
        " h              Help\n"
        " i              System info (CPU, version, clock)\n"
        " s              Safety status (armed, heartbeat, failsafe)\n"
        " a [0|1]        Disarm (0) / Arm (1)\n"
        " c              Calibrate encoders (zero all)\n"
        " e [motor]      Read encoder (0-7, or all if omitted)\n"
        " m              Read IMU (roll, pitch, yaw)\n"
        " d              Read depth (cm)\n"
        " p              Read all PID outputs (6 axes)\n"
        " t <axis> <hex> Set setpoint (s1.14)\n"
        " k <axis> <kp> <ki> <kd>  Set PID gains (s1.14 hex)\n"
        " n <axis> <hex> Set PID current position\n"
        " g <mask>       Enable PID axes (bitmask 0-63)\n"
        " w, z           Unavailable: native PWM is not connected to the ROV\n"
        " l [mask]       LED test (default 0xFF)\n"
        " v              Toggle telemetry on/off\n"
        " r              ROV re-init\n"
        " x              Dump raw CFS registers (diagnostic)\n"
    );
}

static void cmd_info() {
    uart_puts("\n=== NEORV32 ROV System ===\n");
    uart_puts("Hardware: v");
    neorv32_aux_print_hw_version(neorv32_cpu_csr_read(CSR_MIMPID));
    uart_puts("\nClock: "); uart_print_dec(g_clock_hz); uart_puts(" Hz\n");
    uint32_t misa = neorv32_cpu_csr_read(CSR_MISA);
    uart_puts("MISA: 0x"); uart_print_hex32(misa); uart_puts("\n");
    uart_puts("IMEM: 64 KiB  DMEM: 32 KiB\n");
    uart_puts("CFS @ 0xFFFFFF00 (8 regs, ROV control)\n");
}

static void cmd_status() {
    uint8_t st = rov_read_status();
    uart_puts("\n--- Safety Status ---\n");
    uart_puts("Armed:      "); uart_puts((st & STATUS_ARMED)     ? "YES\n" : "NO\n");
    uart_puts("Heartbeat:  "); uart_puts((st & STATUS_HEARTBEAT) ? "OK\n"  : "FAIL\n");
    uart_puts("Failsafe:   "); uart_puts((st & STATUS_FAILSAFE)  ? "ACTIVE\n" : "normal\n");
}

static void cmd_arm(bool arm) {
    if (arm) {
        uart_puts("\nArming motors...\n");
        for (int i = 0; i < 5; i++) { rov_heartbeat(); delay_with_heartbeat(10); }
        rov_arm();
    } else {
        uart_puts("\nDisarming motors.\n");
        rov_disarm();
    }
    delay_with_heartbeat(100);
    cmd_status();
}

static void cmd_calibrate() {
    uart_puts("\nCalibrating encoders...\n");
    rov_calibrate_encoders();
    uart_puts("Done.\n");
}

static void cmd_encoders(int motor) {
    uart_puts("\n--- Encoders ---\n");
    int start = motor < 0 ? 0 : motor;
    int end   = motor < 0 ? kNumMtrs - 1 : motor;
    for (int m = start; m <= end; m++) {
        uint32_t pos = rov_read_encoder_position(m);
        int32_t  vel = (int32_t)rov_read_encoder_velocity(m);
        uart_puts("ENC"); uart_print_dec(m); uart_puts(": pos=");
        uart_print_hex32(pos); uart_puts(" vel="); uart_print_dec(vel); uart_puts("\n");
    }
}

static void cmd_imu() {
    int16_t roll  = rov_read_imu_roll();
    int16_t pitch = rov_read_imu_pitch();
    int16_t yaw   = rov_read_imu_yaw();
    uart_puts("\n--- IMU (s1.14 rad) ---\n");
    uart_puts("Roll:  "); uart_print_s114(roll);  uart_puts("\n");
    uart_puts("Pitch: "); uart_print_s114(pitch); uart_puts("\n");
    uart_puts("Yaw:   "); uart_print_s114(yaw);   uart_puts("\n");
}

static void cmd_depth() {
    uint16_t d = rov_read_depth_cm();
    uart_puts("\nDepth: "); uart_print_dec(d); uart_puts(" cm\n");
}

static void cmd_pid_outputs() {
    uart_puts("\n--- PID Outputs (s1.14) ---\n");
    for (int a = 0; a < kNumAxes; a++) {
        uart_puts(kAxisNames[a]); uart_puts(": ");
        int16_t out = rov_read_pid_output(a);
        uart_print_s114(out); uart_puts("\n");
    }
}

static void cmd_setpoint(int axis, int16_t val) {
    if (axis < 0 || axis >= kNumAxes) { uart_puts("Invalid axis\n"); return; }
    uart_puts("Setpoint "); uart_puts(kAxisNames[axis]); uart_puts(" = ");
    uart_print_s114(val); uart_puts("\n");
    rov_set_setpoint(axis, val);
}

static void cmd_pid_gain(int axis, int16_t kp, int16_t ki, int16_t kd) {
    if (axis < 0 || axis >= kNumAxes) { uart_puts("Invalid axis\n"); return; }
    uart_puts("PID "); uart_puts(kAxisNames[axis]); uart_puts(" Kp=");
    uart_print_s114(kp); uart_puts(" Ki="); uart_print_s114(ki);
    uart_puts(" Kd="); uart_print_s114(kd); uart_puts("\n");
    rov_set_pid_gain(axis, kp, ki, kd);
}

static void cmd_pid_current(int axis, int16_t val) {
    if (axis < 0 || axis >= kNumAxes) { uart_puts("Invalid axis\n"); return; }
    uart_puts("PID current "); uart_puts(kAxisNames[axis]); uart_puts(" = ");
    uart_print_s114(val); uart_puts("\n");
    rov_set_pid_current(axis, val);
}

static void cmd_pid_enable(uint8_t mask) {
    uart_puts("PID enable mask: 0b");
    for (int i = 5; i >= 0; i--) neorv32_uart0_putc((mask & (1 << i)) ? '1' : '0');
    uart_puts("\n");
    rov_enable_pid(mask);
}

static void cmd_native_pwm_unavailable() {
    uart_puts("Native PWM is disconnected from the ROV outputs; command unavailable.\n");
}

static void cmd_leds(uint32_t mask) {
    neorv32_gpio_pin_toggle(0);
    for (int i = 0; i < 3; i++) {
        neorv32_gpio_port_set(mask & 0xFFFF);
        delay_with_heartbeat(200);
        neorv32_gpio_port_set(0);
        delay_with_heartbeat(200);
    }
    neorv32_gpio_port_set(0);
}

static void cmd_reinit() {
    uart_puts("\nRe-initializing ROV...\n");
    rov_disarm();
    delay_with_heartbeat(100);
    rov_init();
    for (int i = 0; i < 48; i++) {
        int16_t c = (int16_t)((uint16_t)kDefaultMixer[i] << 8);
        rov_set_mixer_coeff(i, c);
    }
    cmd_status();
}

// ===========================================================================
// Telemetry
// ===========================================================================
static void print_telemetry() {
    uint8_t st = rov_read_status();
    uart_puts("\n--- TEL ---\n");
    uart_puts("Status: ");
    uart_puts((st & STATUS_ARMED) ? "ARMED " : "disarmed ");
    uart_puts((st & STATUS_HEARTBEAT) ? "HB_OK " : "HB_FAIL ");
    uart_puts((st & STATUS_FAILSAFE) ? "FAILSAFE" : "safe");
    uart_puts("\n");

    uint16_t depth = rov_read_depth_cm();
    uart_puts("Depth: "); uart_print_dec(depth); uart_puts(" cm\n");

    uart_puts("Encoders (pos): ");
    for (int m = 0; m < kNumMtrs; m++) {
        uart_print_dec(rov_read_encoder_position(m));
        uart_puts(" ");
    }
    uart_puts("\n");

    uart_puts("IMU: R="); uart_print_s114(rov_read_imu_roll());
    uart_puts(" P=");   uart_print_s114(rov_read_imu_pitch());
    uart_puts(" Y=");   uart_print_s114(rov_read_imu_yaw());
    uart_puts("\n");

    uart_puts("PID: ");
    for (int a = 0; a < kNumAxes; a++) {
        uart_puts(kAxisNames[a]); uart_puts("=");
        uart_print_s114(rov_read_pid_output(a)); uart_puts(" ");
    }
    uart_puts("\n---------------\n");
}

// ===========================================================================
// Main dispatch
// ===========================================================================
static void process_command() {
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
    case 'w': case 'z': cmd_native_pwm_unavailable(); break;
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
        uart_puts("\n--- CFS Raw ---\n");
        for (int i = 0; i < 8; i++) {
            uart_puts("R"); neorv32_uart0_putc('0'+i); uart_puts(":0x");
            uart_print_hex32(*(volatile uint32_t*)(NEORV32_CFS_BASE + i*4));
            uart_puts(" ");
        }
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
int main() {
    g_clock_hz        = neorv32_sysinfo_get_clk();
    g_last_heartbeat  = neorv32_cpu_csr_read(CSR_MCYCLE);
    g_last_led        = g_last_heartbeat;
    g_last_telem      = 0;
    g_telem_enabled   = false;
    rx_idx            = 0;

    neorv32_uart0_setup(115200, 0);
    neorv32_uart0_puts("\n\n");
    uart_puts("========================================\n");
    uart_puts(" NEORV32 Nexys A7 — ROV Firmware\n");
    uart_puts(" RV32IMC @ 100 MHz | CFS ROV Control\n");
    uart_puts("========================================\n\n");

    uart_puts("Hardware: v");
    neorv32_aux_print_hw_version(neorv32_cpu_csr_read(CSR_MIMPID));
    uart_puts("\nClock: "); uart_print_dec(g_clock_hz); uart_puts(" Hz\n");
    if (g_clock_hz != RV32IMC_CPU_HZ)
        uart_puts("WARNING: clock mismatch with RV32IMC_CPU_HZ\n");

    neorv32_gpio_dir_set(kLedMask);
    neorv32_gpio_port_set(0);

    // --- ROV CFS init ---
    uart_puts("CFS: initializing ROV subsystem...\n");
    rov_init();
    for (int i = 0; i < 48; i++) {
        int16_t c = (int16_t)((uint16_t)kDefaultMixer[i] << 8);
        rov_set_mixer_coeff(i, c);
    }
    uart_puts("Mixer: OCTO defaults loaded.\n");
    cmd_status();

    uart_puts("\nType 'h' for help.\n\nCMD:> ");

    // =======================================================================
    // Main loop
    // =======================================================================
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

        // --- Heartbeat every 50ms ---
        service_heartbeat();

        // --- LED heartbeat ---
        uint32_t now = neorv32_cpu_csr_read(CSR_MCYCLE);
        if (elapsed(now, g_last_led, kLedToggleMs)) {
            g_last_led = now;
            neorv32_gpio_pin_toggle(0);
        }

        // --- Telemetry ---
        if (g_telem_enabled) {
            if (now - g_last_telem >= g_clock_hz * kTelemMs / 1000) {
                g_last_telem = now;
                print_telemetry();
            }
        }
    }
}
