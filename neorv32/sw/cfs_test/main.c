// =============================================================================
// CFS ROV Subsystem Test — validates the hardware control path end-to-end
// =============================================================================
// Ground truth: neorv32_rov_motors.vhd (what's actually in the bitstream)
//
// WRITE (CPU -> CFS), REG0 = cfs_in[31:0]:
//   [31:16] value (s1.14)   [13:8] coeff_idx / pid_enable mask
//   [13:12] gain_sel        [10:8] axis_sel
//   [7:4]   cmd nibble      [2:0]  motor_sel      bit8 = heartbeat toggle
//   REG1 [31:24] = hb_timeout (cmd C)   REG1 [31:0] = pressure (cmd A)
//   REG2 [15:0]  = temp (cmd A with bit10=1)
//
// READ (CFS -> CPU):
//   REG0 = enc_pos   REG1 = enc_vel
//   REG2: [7]=armed [6]=hb_alive [5]=!armed [15:8]=hb_cnt [31:16]=imu_roll
//   REG3: [15:0]=imu_pitch  [31:16]=imu_yaw
//   REG4: [15:0]=pid_out0   [31:16]=pid_out1
//   REG5: [15:0]=pid_out2   [31:16]=pid_out3
//   REG6: [15:0]=pid_out4   [31:16]=pid_out5
//   REG7: [15:0]=depth_cm   [31:16]=depth_temp
// =============================================================================

#include <neorv32.h>

#define BAUD 115200

// --- CFS register map (NEORV32 v1.13.3: CFS moved to 0xFFEB0000) ---
#define CFS_BASE 0xFFEB0000u
#define REG0 (*(volatile uint32_t*)(CFS_BASE + 0x00))
#define REG1 (*(volatile uint32_t*)(CFS_BASE + 0x04))
#define REG2 (*(volatile uint32_t*)(CFS_BASE + 0x08))
#define REG3 (*(volatile uint32_t*)(CFS_BASE + 0x0C))
#define REG4 (*(volatile uint32_t*)(CFS_BASE + 0x10))
#define REG5 (*(volatile uint32_t*)(CFS_BASE + 0x14))
#define REG6 (*(volatile uint32_t*)(CFS_BASE + 0x18))
#define REG7 (*(volatile uint32_t*)(CFS_BASE + 0x1C))

// --- Commands (nibble @ [7:4]) ---
#define CMD_HB     0x1   // heartbeat (toggle bit 8)
#define CMD_ARM    0x2   // arm motors
#define CMD_DIS    0x3   // disarm
#define CMD_CAL    0x4   // calibrate encoders
#define CMD_MIX    0x5   // mixer coefficient (coeff_idx @ [13:8])
#define CMD_SETPT  0x6   // setpoint (axis @ [10:8])
#define CMD_IMU    0x7   // IMU raw (axis @ [10:8])
#define CMD_PGAIN  0x8   // PID gain (axis @ [10:8], gain_sel @ [13:12])
#define CMD_PCUR   0x9   // PID current (axis @ [10:8])
#define CMD_DEPTH  0xA   // depth raw (bit10: 0=pressure REG1, 1=temp REG2)
#define CMD_PEN    0xB   // PID enable (mask @ [13:8])
#define CMD_HBTO   0xC   // heartbeat timeout (REG1 [31:24], ms)

// --- Axes ---
#define AX_SURGE  0
#define AX_SWAY   1
#define AX_HEAVE  2
#define AX_ROLL   3
#define AX_PITCH  4
#define AX_YAW    5

// --- Status bits (REG2) ---
#define ST_ARMED   0x80
#define ST_HB      0x40
#define ST_DISARM  0x20  // !armed (failsafe indicator)

// --- s1.14 fixed point ---
static inline int16_t F14(float x) { return (int16_t)(x * 16384.0f); }

static uint32_t clk = 0;
static uint8_t  hb_bit = 0;
static int      failures = 0;

// Write command word + NOP (NOP lets the edge-detector re-trigger same cmd)
static void cmd_wr(uint32_t w) {
    REG0 = w;
    REG0 = 0;
}

static void heartbeat(void) {
    hb_bit ^= 1;
    REG0 = ((uint32_t)hb_bit << 8) | (CMD_HB << 4);
    REG0 = 0;
}

static uint32_t read_status(void) {
    return REG2 & 0xFF;   // [7]=armed [6]=hb [5]=!armed
}

static uint32_t read_hbcnt(void) {
    return (REG2 >> 8) & 0xFF;
}

static void select_motor(uint8_t m) {
    REG0 = m & 0x7;       // motor_sel @ [2:0], cmd nibble = 0 (no strobe)
}

static int16_t pid_out(int axis) {
    uint32_t r;
    switch (axis) {
        case 0: r = REG4; return (int16_t)(r & 0xFFFF);
        case 1: r = REG4; return (int16_t)((r >> 16) & 0xFFFF);
        case 2: r = REG5; return (int16_t)(r & 0xFFFF);
        case 3: r = REG5; return (int16_t)((r >> 16) & 0xFFFF);
        case 4: r = REG6; return (int16_t)(r & 0xFFFF);
        case 5: r = REG6; return (int16_t)((r >> 16) & 0xFFFF);
        default: return 0;
    }
}

static void report(const char *name, int pass) {
    if (!pass) failures++;
    neorv32_uart0_printf("  [%s] %s\n", pass ? "PASS" : "FAIL", name);
}

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD, 0);
    clk = neorv32_sysinfo_get_clk();

    neorv32_uart0_puts("\n============================================\n");
    neorv32_uart0_puts("  CFS ROV SUBSYSTEM TEST\n");
    neorv32_uart0_puts("  (VHDL ground-truth register map)\n");
    neorv32_uart0_puts("============================================\n\n");

    // ---------------------------------------------------------------
    // T1: Initial status — nothing armed, no heartbeat
    // ---------------------------------------------------------------
    neorv32_uart0_puts("T1: Initial state\n");
    uint32_t st = read_status();
    neorv32_uart0_printf("  status=0x%x (expect 0x00, unarmed)\n", st);
    report("T1 initial disarmed", (st & (ST_ARMED | ST_HB)) == 0);

    // ---------------------------------------------------------------
    // T2: Heartbeat
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT2: Heartbeat\n");
    heartbeat();
    neorv32_aux_delay_ms(clk, 5);
    st = read_status();
    neorv32_uart0_printf("  status=0x%x (expect hb=1 -> 0x40)\n", st);
    report("T2 heartbeat alive", (st & ST_HB) != 0);

    // ---------------------------------------------------------------
    // T3: Arm
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT3: Arm motors\n");
    cmd_wr(CMD_ARM << 4);
    neorv32_aux_delay_ms(clk, 5);
    st = read_status();
    neorv32_uart0_printf("  status=0x%x (expect armed+hb -> 0xC0)\n", st);
    report("T3 armed", (st & ST_ARMED) != 0 && (st & ST_HB) != 0);

    // ---------------------------------------------------------------
    // T4: Encoder readback (floating pins may give noise — informational)
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT4: Encoder readback (8 ch, floating inputs)\n");
    for (int m = 0; m < 8; m++) {
        select_motor(m);
        uint32_t pos = REG0;
        int32_t  vel = (int32_t)REG1;
        neorv32_uart0_printf("  ENC%d: pos=%u vel=%d\n", m, pos, vel);
    }

    // ---------------------------------------------------------------
    // T5: Calibrate encoders -> zero
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT5: Calibrate encoders\n");
    cmd_wr(CMD_CAL << 4);
    neorv32_aux_delay_ms(clk, 5);
    uint32_t enc0 = 0; {
        select_motor(0);
        enc0 = REG0;
    }
    neorv32_uart0_printf("  ENC0 after cal = %u (expect 0)\n", enc0);
    report("T5 calibrate", enc0 == 0);

    // ---------------------------------------------------------------
    // T6: Setpoint with PID disabled -> pid_out stays 0
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT6: Setpoint heave=+0.5, PID off\n");
    cmd_wr(((uint32_t)(uint16_t)F14(0.5f) << 16) | (AX_HEAVE << 8) | (CMD_SETPT << 4));
    neorv32_aux_delay_ms(clk, 20);
    int16_t p2 = pid_out(AX_HEAVE);
    neorv32_uart0_printf("  pid_out(heave) = %d (expect 0, PID disabled)\n", p2);
    report("T6 pid off passthrough", p2 == 0);

    // ---------------------------------------------------------------
    // T7: PID enable + gains -> pid_out(heave) = Kp * error = 0.5
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT7: PID heave Kp=1.0, enable\n");
    cmd_wr(((uint32_t)(uint16_t)F14(1.0f) << 16) | (0u << 12) | (AX_HEAVE << 8) | (CMD_PGAIN << 4));  // Kp
    cmd_wr(((uint32_t)(uint16_t)F14(0.0f) << 16) | (1u << 12) | (AX_HEAVE << 8) | (CMD_PGAIN << 4));  // Ki
    cmd_wr(((uint32_t)(uint16_t)F14(0.0f) << 16) | (2u << 12) | (AX_HEAVE << 8) | (CMD_PGAIN << 4));  // Kd
    cmd_wr(((uint32_t)(uint16_t)F14(0.0f) << 16) | (AX_HEAVE << 8) | (CMD_PCUR << 4));                // current=0
    cmd_wr((1u << AX_HEAVE) << 8 | (CMD_PEN << 4));                                                   // enable heave
    neorv32_aux_delay_ms(clk, 30);
    p2 = pid_out(AX_HEAVE);
    neorv32_uart0_printf("  pid_out(heave) = %d (expect ~8192 = 0x2000)\n", p2);
    report("T7 pid computes 0.5", p2 > 7500 && p2 < 8500);

    // ---------------------------------------------------------------
    // T8: IMU — yaw is a pure integrator of IMU_RAW(5)
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT8: IMU yaw integration (2 x 0.25 rad)\n");
    cmd_wr(((uint32_t)(uint16_t)F14(0.25f) << 16) | (AX_YAW << 8) | (CMD_IMU << 4));
    cmd_wr(((uint32_t)(uint16_t)F14(0.25f) << 16) | (AX_YAW << 8) | (CMD_IMU << 4));
    neorv32_aux_delay_ms(clk, 5);
    int16_t yaw = (int16_t)((REG3 >> 16) & 0xFFFF);
    int16_t roll = (int16_t)((REG2 >> 16) & 0xFFFF);
    int16_t pitch = (int16_t)(REG3 & 0xFFFF);
    neorv32_uart0_printf("  imu_yaw = %d (expect ~8192 = 0.5 rad)\n", yaw);
    neorv32_uart0_printf("  imu_roll=%d imu_pitch=%d (info)\n", roll, pitch);
    report("T8 imu yaw integral", yaw > 7500 && yaw < 8500);

    // ---------------------------------------------------------------
    // T9: Depth sensor math — pressure -> cm, temp passthrough
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT9: Depth computation\n");
    // Surface pressure 101300 Pa -> 0 cm
    REG1 = 101300;
    cmd_wr((CMD_DEPTH << 4) | (0u << 10));
    neorv32_aux_delay_ms(clk, 5);
    uint16_t d0 = (REG7 >> 0) & 0xFFFF;
    // 202600 Pa -> ~1033 cm (~10.3 m)
    REG1 = 202600;
    cmd_wr((CMD_DEPTH << 4) | (0u << 10));
    neorv32_aux_delay_ms(clk, 5);
    uint16_t d1 = (REG7 >> 0) & 0xFFFF;
    // Temperature 25.0 C -> 250 raw
    REG2 = 250;
    cmd_wr((CMD_DEPTH << 4) | (1u << 10));
    neorv32_aux_delay_ms(clk, 5);
    int16_t temp = (int16_t)((REG7 >> 16) & 0xFFFF);
    neorv32_uart0_printf("  depth@101300Pa = %d cm (expect 0)\n", d0);
    neorv32_uart0_printf("  depth@202600Pa = %d cm (expect ~1033)\n", d1);
    neorv32_uart0_printf("  temp raw = %d (expect 250 = 25.0C)\n", temp);
    report("T9 depth surface", d0 <= 2);
    report("T9 depth 10m", d1 > 1020 && d1 < 1050);
    report("T9 temp passthrough", temp == 250);

    // ---------------------------------------------------------------
    // T10: Failsafe — heartbeat timeout disarms motors
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT10: Failsafe (heartbeat timeout)\n");
    REG1 = 20u << 24;                  // 20 ms timeout
    cmd_wr(CMD_HBTO << 4);
    neorv32_aux_delay_ms(clk, 200);    // stop heartbeating, wait > timeout
    st = read_status();
    uint32_t cnt = read_hbcnt();
    neorv32_uart0_printf("  status=0x%x hb_cnt=%u (expect disarmed: armed=0 hb=0)\n",
                         st, cnt);
    report("T10 failsafe disarms", (st & (ST_ARMED | ST_HB)) == 0);

    // ---------------------------------------------------------------
    // T11: Re-arm and keep heartbeat running (leaves PWM active)
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\nT11: Re-arm for PWM probing\n");
    REG1 = 200u << 24;                 // restore 200 ms timeout
    cmd_wr(CMD_HBTO << 4);
    heartbeat();
    cmd_wr(CMD_ARM << 4);
    neorv32_aux_delay_ms(clk, 5);
    st = read_status();
    neorv32_uart0_printf("  status=0x%x (expect 0xC0 armed+hb)\n", st);
    report("T11 re-armed", (st & (ST_ARMED | ST_HB)) == 0xC0);

    // ---------------------------------------------------------------
    // Summary
    // ---------------------------------------------------------------
    neorv32_uart0_puts("\n============================================\n");
    if (failures == 0) {
        neorv32_uart0_puts("  ALL CFS TESTS PASSED\n");
    } else {
        neorv32_uart0_printf("  %d TEST(S) FAILED\n", failures);
    }
    neorv32_uart0_puts("============================================\n\n");
    neorv32_uart0_puts("  PWM is ARMED. Set SW[0]=ON to see pulses on PMOD JA.\n");
    neorv32_uart0_puts("  Neutral=1500us. Heartbeat running @ 50ms.\n\n");

    // SW mirror demo: LED[i] = SW[i] for all 16. Heartbeat keeps PWM armed.
    uint32_t ticks = 0;
    while (1) {
        heartbeat();
        neorv32_aux_delay_ms(clk, 50);
        uint32_t sw = neorv32_gpio_port_get();
        neorv32_gpio_port_set(sw & 0xFFFF);
        if (++ticks % 40 == 0) {
            neorv32_uart0_printf("sw=0x%x status=0x%x\n", sw, read_status());
        }
    }

    return 0;
}
