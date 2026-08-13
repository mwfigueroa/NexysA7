// =============================================================================
// PWM Sweep ??? barrido del servo en JA1 (motor 0) via CFS mixer
// =============================================================================
// mixer coeff (motor0, surge) = 0x7FFF (~2x en s1.14)
// setpoint surge -1.0..+1.0 -> motor_duty 0..65535 -> pulso 1100..1900 us
// 41 pasos x 250 ms = ciclo de ~10.25 s, repetido en diente de sierra
// =============================================================================

#include <neorv32.h>
#include "rov_cfs.h"

#define STEPS      40
#define HOLD_MS    250

static uint32_t clk;

static void hold_with_heartbeat(uint32_t ms) {
    static uint32_t ticks = 0;   // continuo entre llamadas
    while (ms--) {
        neorv32_aux_delay_ms(clk, 1);
        if (++ticks % 50 == 0) rov_heartbeat();
    }
}

int main(void) {
    neorv32_uart0_setup(115200, 0);
    clk = neorv32_sysinfo_get_clk();

    neorv32_uart0_puts("\n========================================\n");
    neorv32_uart0_puts("  PWM SWEEP - JA1 (motor 0)\n");
    neorv32_uart0_puts("  pulse 1100-1900 us @ 50 Hz\n");
    neorv32_uart0_puts("========================================\n");

    // init: hb timeout 200ms, heartbeat, arm
    rov_set_hb_timeout(200);
    rov_heartbeat();
    rov_arm();

    // mixer: solo (motor0, surge) con coeff max (~2x); resto a cero
    rov_set_mixer_coeff(0, (int16_t)0x7FFF);
    for (int i = 1; i < 48; i++) rov_set_mixer_coeff(i, 0);

    neorv32_uart0_puts("Mixer: motor0/surge = 0x7FFF, resto 0. Barriendo...\n");

    while (1) {
        // IDA: setpoint -0.9 -> +0.9 (pulse 1140 -> 1860 us), 25 ms por paso
        for (int i = 0; i <= STEPS; i++) {
            int16_t sp = (int16_t)(-14746 + (int32_t)i * 737); // ~0.9 del rango
            rov_set_setpoint(AXIS_SURGE, sp);
            uint32_t duty = (uint32_t)(32768 + (int32_t)sp * 2);
            neorv32_uart0_printf("ida %u pulse~%u us\n", i,
                                 1100u + duty * 800u / 65536u);
            hold_with_heartbeat(i == 0 ? 500 : 25);
        }
        // VUELTA: +0.9 -> -0.9
        for (int i = STEPS; i >= 0; i--) {
            int16_t sp = (int16_t)(-14746 + (int32_t)i * 737);
            rov_set_setpoint(AXIS_SURGE, sp);
            uint32_t duty = (uint32_t)(32768 + (int32_t)sp * 2);
            neorv32_uart0_printf("vuelta %u pulse~%u us\n", i,
                                 1100u + duty * 800u / 65536u);
            hold_with_heartbeat(i == 0 ? 500 : 25);
        }
    }

    return 0;
}
