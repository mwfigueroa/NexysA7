// =============================================================================
// NEORV32 Nexys A7 — ROV CFS Driver (validated in HW 2026-08-12)
// =============================================================================
// Ground truth: neorv32_rov_motors.vhd (what is actually in the bitstream)
//
// WRITE (CPU -> CFS), REG0 = cfs_in[31:0]:
//   [31:16] value (s1.14)     [13:12] gain_sel
//   [13:8]  coeff_idx / pid_enable mask
//   [10:8]  axis_sel         [7:4] cmd nibble
//   [2:0]   motor_sel        bit8 = heartbeat toggle
//   REG1 [31:24] = hb_timeout (cmd 0xC)   REG1 [31:0] = pressure (cmd 0xA)
//   REG2 [15:0]  = temp (cmd 0xA with bit10=1)
//
// READ (CFS -> CPU):
//   REG0 = enc_pos   REG1 = enc_vel
//   REG2: [7]=armed [6]=hb_alive [5]=!armed [15:8]=hb_cnt [31:16]=imu_roll
//   REG3: [15:0]=imu_pitch  [31:16]=imu_yaw
//   REG4: [15:0]=pid_out0   [31:16]=pid_out1
//   REG5: [15:0]=pid_out2   [31:16]=pid_out3
//   REG6: [15:0]=pid_out4   [31:16]=pid_out5
//   REG7: [15:0]=depth_cm   [31:16]=depth_temp
//
// NOTE: every command write must be followed by a NOP (REG0 = 0) so the
//       hardware edge-detector can re-trigger the same command again.
//       Motor select (REG0 = motor_sel, no strobe) persists until the next
//       command write — read encoders immediately after selecting.
// =============================================================================

#include <neorv32.h>

// --- CFS register map (NEORV32 v1.13.3: CFS at 0xFFEB0000) ---
#define CFS_BASE 0xFFEB0000u
#define CFS_REG0 (*(volatile uint32_t*)(CFS_BASE + 0x00))
#define CFS_REG1 (*(volatile uint32_t*)(CFS_BASE + 0x04))
#define CFS_REG2 (*(volatile uint32_t*)(CFS_BASE + 0x08))
#define CFS_REG3 (*(volatile uint32_t*)(CFS_BASE + 0x0C))
#define CFS_REG4 (*(volatile uint32_t*)(CFS_BASE + 0x10))
#define CFS_REG5 (*(volatile uint32_t*)(CFS_BASE + 0x14))
#define CFS_REG6 (*(volatile uint32_t*)(CFS_BASE + 0x18))
#define CFS_REG7 (*(volatile uint32_t*)(CFS_BASE + 0x1C))

// --- Field encoders (final word bit positions) ---
#define CFS_CMD(c)    (((uint32_t)((c) & 0xF)) << 4)    // cmd nibble  @ [7:4]
#define CFS_AXIS(a)   (((uint32_t)((a) & 0x7)) << 8)    // axis_sel    @ [10:8]
#define CFS_GAIN(g)   (((uint32_t)((g) & 0x3)) << 12)   // gain_sel    @ [13:12]
#define CFS_MASK(m)   (((uint32_t)((m) & 0x3F)) << 8)   // coeff/pid   @ [13:8]
#define CFS_MOTOR(m)  ((uint32_t)((m) & 0x7))           // motor_sel   @ [2:0]

// --- Command nibbles ---
#define CMD_HEARTBEAT   0x1
#define CMD_ARM         0x2
#define CMD_DISARM      0x3
#define CMD_CALIBRATE   0x4
#define CMD_MIXER_COEFF 0x5
#define CMD_SETPOINT    0x6
#define CMD_IMU_RAW     0x7
#define CMD_PID_GAIN    0x8
#define CMD_PID_CURRENT 0x9
#define CMD_DEPTH_RAW   0xA
#define CMD_PID_ENABLE  0xB
#define CMD_HB_TIMEOUT  0xC

// --- Status bits (REG2 [7:0]) ---
#define STATUS_ARMED     0x80
#define STATUS_HEARTBEAT 0x40
#define STATUS_FAILSAFE  0x20

// --- Axes ---
#define AXIS_SURGE 0
#define AXIS_SWAY  1
#define AXIS_HEAVE 2
#define AXIS_ROLL  3
#define AXIS_PITCH 4
#define AXIS_YAW   5

// --- Internal ---
static uint8_t _hb_bit = 0;

static void _rov_cmd(uint32_t word) {
    CFS_REG0 = word;
    CFS_REG0 = 0; // NOP: edge-detector re-trigger for identical consecutive cmds
}

// Forward declarations (rov_init uses these before their definitions)
void rov_heartbeat(void);
void rov_set_setpoint(int axis, int16_t val_s114);

// =============================================================================
// Public API
// =============================================================================

void rov_init(void) {
    _hb_bit = 0;
    CFS_REG1 = 200u << 24;            // heartbeat timeout = 200 ms
    _rov_cmd(CFS_CMD(CMD_HB_TIMEOUT));
    rov_heartbeat();                  // establish heartbeat first
    _rov_cmd(CFS_CMD(CMD_ARM));
    for (int a = 0; a < 6; a++) {
        rov_set_setpoint(a, 0);       // all setpoints neutral
    }
}

void rov_heartbeat(void) {
    _hb_bit ^= 1;                     // toggle bit 8 on every call
    _rov_cmd(CFS_CMD(CMD_HEARTBEAT) | ((uint32_t)_hb_bit << 8));
}

void rov_arm(void) {
    _rov_cmd(CFS_CMD(CMD_ARM));
}

void rov_set_hb_timeout(uint8_t timeout_ms) {
    CFS_REG1 = (uint32_t)timeout_ms << 24;
    _rov_cmd(CFS_CMD(CMD_HB_TIMEOUT));
}

void rov_disarm(void) {
    _rov_cmd(CFS_CMD(CMD_DISARM));
}

void rov_calibrate_encoders(void) {
    _rov_cmd(CFS_CMD(CMD_CALIBRATE));
}

// --- Mixer ---
void rov_set_setpoint(int axis, int16_t val_s114) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(((uint32_t)(uint16_t)val_s114 << 16) | CFS_AXIS(axis) |
                 CFS_CMD(CMD_SETPOINT));
    }
}

void rov_set_mixer_coeff(int index, int16_t coeff_s114) {
    if (index >= 0 && index < 48) {
        _rov_cmd(((uint32_t)(uint16_t)coeff_s114 << 16) |
                 (((uint32_t)index & 0x3F) << 8) | CFS_CMD(CMD_MIXER_COEFF));
    }
}

// --- PID ---
void rov_set_pid_gain(int axis, int16_t kp, int16_t ki, int16_t kd) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(((uint32_t)(uint16_t)kp << 16) | CFS_GAIN(0) | CFS_AXIS(axis) |
                 CFS_CMD(CMD_PID_GAIN));
        _rov_cmd(((uint32_t)(uint16_t)ki << 16) | CFS_GAIN(1) | CFS_AXIS(axis) |
                 CFS_CMD(CMD_PID_GAIN));
        _rov_cmd(((uint32_t)(uint16_t)kd << 16) | CFS_GAIN(2) | CFS_AXIS(axis) |
                 CFS_CMD(CMD_PID_GAIN));
    }
}

void rov_set_pid_current(int axis, int16_t current_s114) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(((uint32_t)(uint16_t)current_s114 << 16) | CFS_AXIS(axis) |
                 CFS_CMD(CMD_PID_CURRENT));
    }
}

void rov_enable_pid(uint8_t mask) {
    _rov_cmd(CFS_MASK(mask) | CFS_CMD(CMD_PID_ENABLE));
}

// --- IMU ---
void rov_set_imu_raw(int axis, int16_t raw_s114) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(((uint32_t)(uint16_t)raw_s114 << 16) | CFS_AXIS(axis) |
                 CFS_CMD(CMD_IMU_RAW));
    }
}

// --- Depth ---
// pressure in Pascal (e.g. 101300 = surface), temp in C*10 (e.g. 250 = 25.0C)
void rov_set_depth_raw(uint32_t pressure_pa, int16_t temp_c_x10) {
    CFS_REG1 = pressure_pa;                 // REG1 [31:0] = pressure
    _rov_cmd(CFS_CMD(CMD_DEPTH_RAW));       // bit10 = 0 -> pressure
    CFS_REG2 = (uint32_t)(uint16_t)temp_c_x10; // REG2 [15:0] = temp
    _rov_cmd(CFS_CMD(CMD_DEPTH_RAW) | (1u << 10)); // bit10 = 1 -> temp
}

// --- Sensor readback ---
// Select motor (no strobe) then read immediately: motor_sel persists until
// the next command write.
uint32_t rov_read_encoder_position(int motor) {
    CFS_REG0 = CFS_MOTOR(motor);
    return CFS_REG0;
}

uint32_t rov_read_encoder_velocity(int motor) {
    CFS_REG0 = CFS_MOTOR(motor);
    return CFS_REG1;
}

uint8_t rov_read_status(void) {
    return (uint8_t)(CFS_REG2 & 0xFF);
}

uint8_t rov_read_hb_count(void) {
    return (uint8_t)((CFS_REG2 >> 8) & 0xFF);
}

int16_t rov_read_imu_roll(void) {
    return (int16_t)((CFS_REG2 >> 16) & 0xFFFF);
}

int16_t rov_read_imu_pitch(void) {
    return (int16_t)(CFS_REG3 & 0xFFFF);
}

int16_t rov_read_imu_yaw(void) {
    return (int16_t)((CFS_REG3 >> 16) & 0xFFFF);
}

int16_t rov_read_pid_output(int axis) {
    uint32_t reg;
    switch (axis) {
        case 0: reg = CFS_REG4; return (int16_t)((reg >> 0)  & 0xFFFF);
        case 1: reg = CFS_REG4; return (int16_t)((reg >> 16) & 0xFFFF);
        case 2: reg = CFS_REG5; return (int16_t)((reg >> 0)  & 0xFFFF);
        case 3: reg = CFS_REG5; return (int16_t)((reg >> 16) & 0xFFFF);
        case 4: reg = CFS_REG6; return (int16_t)((reg >> 0)  & 0xFFFF);
        case 5: reg = CFS_REG6; return (int16_t)((reg >> 16) & 0xFFFF);
        default: return 0;
    }
}

uint16_t rov_read_depth_cm(void) {
    return (uint16_t)(CFS_REG7 & 0xFFFF);
}

int16_t rov_read_depth_temp(void) {
    return (int16_t)((CFS_REG7 >> 16) & 0xFFFF);
}
