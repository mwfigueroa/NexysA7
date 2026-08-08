// =============================================================================
// NEORV32 Nexys A7 — Motor Sweep Test (8 canales PWM para ROV/Drone)
// =============================================================================
// PWM[7:0] en PMOD JA a ~190 Hz (CLK_PRSC_8), 16-bit resolution.
// Barrido secuencial: cada motor acelera de 0→100→0 mientras los demas en neutro.
// Salida UART 115200 con estado en tiempo real.
// =============================================================================

#include <neorv32.h>

// --- PWM Config ---
#define PWM_PRESCALER  CLK_PRSC_8   // ~190 Hz @ 100 MHz → ESCs modernos
#define PWM_MIN        12500        // 1.0 ms → motor parado
#define PWM_NEUTRAL    18750        // 1.5 ms → neutro/arm
#define PWM_MAX        25000        // 2.0 ms → maxima potencia
#define NUM_MOTORS     8

// --- UART ---
#define BAUD_RATE  115200
#define CPU_CLK_HZ 100000000

static void motor_init(void) {
    neorv32_pwm_set_clock(PWM_PRESCALER);
    for (int i = 0; i < NUM_MOTORS; i++) {
        neorv32_pwm_ch_set_duty(i, PWM_NEUTRAL);
    }
    neorv32_pwm_ch_enable_mask(0xFF);
}

static void motor_set(int ch, int duty) {
    if (duty < PWM_MIN)   duty = PWM_MIN;
    if (duty > PWM_MAX)   duty = PWM_MAX;
    neorv32_pwm_ch_set_duty(ch, duty);
}

static int duty_to_pct(int duty) {
    return ((duty - PWM_MIN) * 100) / (PWM_MAX - PWM_MIN);
}

static void uart_print(const char *s) {
    while (*s) neorv32_uart0_putc(*s++);
}

static void uart_print_dec(int n) {
    char buf[12];
    int i = 10;
    buf[11] = '\0';
    if (n == 0) { buf[10] = '0'; i = 9; }
    else {
        while (n > 0 && i >= 0) { buf[i--] = '0' + (n % 10); n /= 10; }
    }
    uart_print(&buf[i + 1]);
}

static void uart_print_hex32(uint32_t n) {
    static const char hex[] = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) {
        neorv32_uart0_putc(hex[(n >> i) & 0xF]);
    }
}

int main(void) {
    uint32_t clk = neorv32_sysinfo_get_clk();

    neorv32_uart0_setup(BAUD_RATE, 0);

    uart_print("\n========================================\n");
    uart_print(" NEORV32 Motor Sweep Test\n");
    uart_print(" 8 channels PWM @ ~190 Hz (CLK_PRSC_8)\n");
    uart_print(" PMOD JA: PWM[7:0] for ROV/Drone ESCs\n");
    uart_print("========================================\n\n");

    uart_print("CLK: ");
    uart_print_hex32(clk);
    uart_print(" Hz\n");

    uint32_t misa = neorv32_cpu_csr_read(CSR_MISA);
    uart_print("MISA: 0x");
    uart_print_hex32(misa);
    uart_print("\n\n");

    // Initialize all motors to neutral
    motor_init();
    uart_print("All motors at NEUTRAL (1.5 ms).\n");
    uart_print("Connect ESCs to PMOD JA + GND.\n\n");

    neorv32_aux_delay_ms(clk, 2000);

    // --- Sweep test: each motor individually ---
    for (int motor = 0; motor < NUM_MOTORS; motor++) {
        uart_print("Testing Motor ");
        uart_print_dec(motor);
        uart_print(" (PMOD JA[");
        uart_print_dec(motor);
        uart_print("])...\n");

        // Ramp up: 0% → 100%
        for (int duty = PWM_MIN; duty <= PWM_MAX; duty += 250) {
            motor_set(motor, duty);
            uart_print("  M");
            uart_print_dec(motor);
            uart_print(" UP   -> ");
            uart_print_dec(duty_to_pct(duty));
            uart_print("%\n");
            neorv32_aux_delay_ms(clk, 30);
        }

        neorv32_aux_delay_ms(clk, 500);

        // Ramp down: 100% → 0%
        for (int duty = PWM_MAX; duty >= PWM_MIN; duty -= 250) {
            motor_set(motor, duty);
            uart_print("  M");
            uart_print_dec(motor);
            uart_print(" DOWN -> ");
            uart_print_dec(duty_to_pct(duty));
            uart_print("%\n");
            neorv32_aux_delay_ms(clk, 30);
        }

        motor_set(motor, PWM_NEUTRAL);
    }

    // --- All motors simultaneous ramp ---
    uart_print("\nAll motors simultaneous ramp...\n");

    for (int duty = PWM_MIN; duty <= PWM_MAX; duty += 500) {
        for (int m = 0; m < NUM_MOTORS; m++) {
            motor_set(m, duty);
        }
        uart_print("  ALL -> ");
        uart_print_dec(duty_to_pct(duty));
        uart_print("%\n");
        neorv32_aux_delay_ms(clk, 50);
    }

    neorv32_aux_delay_ms(clk, 1000);

    for (int m = 0; m < NUM_MOTORS; m++) {
        motor_set(m, PWM_NEUTRAL);
    }

    uart_print("\n=== MOTOR SWEEP COMPLETE ===\n");
    uart_print("All channels at NEUTRAL. Ready.\n");

    while (1) {
        neorv32_aux_delay_ms(clk, 500);
        neorv32_gpio_pin_set(0, 1);
        neorv32_aux_delay_ms(clk, 500);
        neorv32_gpio_pin_set(0, 0);
    }
}
