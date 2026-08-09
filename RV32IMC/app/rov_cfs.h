// =============================================================================
// NEORV32 Nexys A7 — ROV CFS Driver (PWM Safety + Mixer + PID + Encoders)
// =============================================================================
// Usage:
//   rov_init()                  — initialize mixer defaults + arm sequence
//   rov_heartbeat()             — call every 50ms in main loop
//   rov_set_mixer(axis, val)    — set control setpoint (Surge/Sway/Heave/...)
//   rov_set_pid(axis, kp,ki,kd) — configure PID gains
//   rov_enable_pid(mask)        — enable PID per axis (bitmask)
//   rov_read_encoder(motor)     — returns 32-bit position
//   rov_read_depth()            — returns depth in cm
// =============================================================================

#include <neorv32.h>

// --- CFS Register Addresses (inside NEORV32 CFS space) ---
#define CFS_BASE    NEORV32_CFS_BASE
#define CFS_REG0    (*(volatile uint32_t*)(CFS_BASE + 0x00))
#define CFS_REG1    (*(volatile uint32_t*)(CFS_BASE + 0x04))
#define CFS_REG2    (*(volatile uint32_t*)(CFS_BASE + 0x08))
#define CFS_REG3    (*(volatile uint32_t*)(CFS_BASE + 0x0C))
#define CFS_REG4    (*(volatile uint32_t*)(CFS_BASE + 0x10))
#define CFS_REG5    (*(volatile uint32_t*)(CFS_BASE + 0x14))
#define CFS_REG6    (*(volatile uint32_t*)(CFS_BASE + 0x18))
#define CFS_REG7    (*(volatile uint32_t*)(CFS_BASE + 0x1C))

// --- CFS Command encoding ---
// cfs_in[7:0] = {cmd[3:0], motor_sel[2:0]} or {cmd[3:0], axis_sel[2:0]}
#define CMD_HEARTBEAT   0x01
#define CMD_ARM         0x02
#define CMD_DISARM      0x03
#define CMD_CALIBRATE   0x04
#define CMD_MIXER_COEFF 0x05
#define CMD_SETPOINT    0x06
#define CMD_IMU_RAW     0x07
#define CMD_PID_GAIN    0x08
#define CMD_PID_CURRENT 0x09
#define CMD_DEPTH_RAW   0x0A
#define CMD_PID_ENABLE  0x0B

// --- CFS output offsets (read via cfs_reg_get) ---
#define ROV_ENC_POS     0   // encoder position [31:0]
#define ROV_ENC_VEL     1   // encoder velocity [63:32]
#define ROV_STATUS      2   // safety status [71:64]
#define ROV_IMU_ROLL    3   // IMU roll [95:80]
#define ROV_IMU_PITCH   3   // IMU pitch [111:96] (upper half of reg3)
#define ROV_IMU_YAW     4   // IMU yaw [127:112]
#define ROV_PID_OUT0    4   // PID output axis 0 [143:128] (upper half)
#define ROV_PID_OUT1    5   // PID output axis 1
#define ROV_PID_OUT2    5   // PID output axis 2
#define ROV_PID_OUT3    6   // PID output axis 3
#define ROV_PID_OUT4    6   // PID output axis 4 (upper half)
#define ROV_PID_OUT5    7   // PID output axis 5
#define ROV_DEPTH       7   // depth cm [239:224] (upper half)

// --- Safety status bits in ROV_STATUS ---
#define STATUS_ARMED       0x80
#define STATUS_HEARTBEAT   0x40
#define STATUS_FAILSAFE    0x20

// --- Axis indices ---
#define AXIS_SURGE   0
#define AXIS_SWAY    1
#define AXIS_HEAVE   2
#define AXIS_ROLL    3
#define AXIS_PITCH   4
#define AXIS_YAW     5

// --- Internal ---
static void _rov_cmd(uint32_t cmd_byte, uint32_t value) {
    cmd_byte &= 0xFF;
    // Write command to CFS_REG0: [31:16]=value, [15:8]=reserved, [7:0]=cmd
    CFS_REG0 = (value << 16) | cmd_byte;
}

// =============================================================================
// Public API
// =============================================================================

void rov_init(void) {
    // Set heartbeat timeout to 200ms (safe default)
    _rov_cmd(0x00, 200); // cfs_in[15:8] = timeout
    
    // Clear heartbeat to establish connection
    _rov_cmd(CMD_HEARTBEAT, 0);
    
    // Arm motors (requires heartbeat active first)
    _rov_cmd(CMD_ARM, 0);
    
    // All setpoints to neutral (0 in s1.14 fixed-point)
    for (int a = 0; a < 6; a++) {
        _rov_cmd(CMD_SETPOINT | (a << 8), 0);
    }
}

void rov_heartbeat(void) {
    _rov_cmd(CMD_HEARTBEAT, 0);
}

void rov_disarm(void) {
    _rov_cmd(CMD_DISARM, 0);
}

void rov_calibrate_encoders(void) {
    _rov_cmd(CMD_CALIBRATE, 0);
}

// --- Mixer ---
void rov_set_setpoint(int axis, int16_t val_s114) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(CMD_SETPOINT | (axis << 8), (uint32_t)(uint16_t)val_s114);
    }
}

void rov_set_mixer_coeff(int index, int16_t coeff_s114) {
    if (index >= 0 && index < 48) {
        _rov_cmd(CMD_MIXER_COEFF | (index << 8), (uint32_t)(uint16_t)coeff_s114);
    }
}

// --- PID ---
void rov_set_pid_gain(int axis, int16_t kp, int16_t ki, int16_t kd) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(CMD_PID_GAIN | (axis << 8) | (0 << 12), (uint32_t)(uint16_t)kp);
        _rov_cmd(CMD_PID_GAIN | (axis << 8) | (1 << 12), (uint32_t)(uint16_t)ki);
        _rov_cmd(CMD_PID_GAIN | (axis << 8) | (2 << 12), (uint32_t)(uint16_t)kd);
    }
}

void rov_set_pid_current(int axis, int16_t current_s114) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(CMD_PID_CURRENT | (axis << 8), (uint32_t)(uint16_t)current_s114);
    }
}

void rov_enable_pid(uint8_t mask) {
    _rov_cmd(CMD_PID_ENABLE | (mask << 8), 0);
}

// --- IMU ---
void rov_set_imu_raw(int axis, int16_t raw_s114) {
    if (axis >= 0 && axis < 6) {
        _rov_cmd(CMD_IMU_RAW | (axis << 8), (uint32_t)(uint16_t)raw_s114);
    }
}

// --- Depth ---
void rov_set_depth_raw(uint32_t pressure_mbar_x100, int16_t temp_c_x10) {
    _rov_cmd(CMD_DEPTH_RAW | (0 << 10), pressure_mbar_x100);
    _rov_cmd(CMD_DEPTH_RAW | (1 << 10), (uint32_t)(uint16_t)temp_c_x10);
}

// --- Sensor Readback ---
uint32_t rov_read_encoder_position(int motor) {
    // Select motor by writing to register (motor_sel in bits 2:0 via any cmd)
    // Read back position from cfs register address 0
    // Actually, motor_sel comes from cfs_in[2:0] on every access
    // We need to write a NOP with motor_sel to select, then read
    _rov_cmd(0x00 | (motor & 0x7), 0); // NOP with motor_sel
    return CFS_REG0; // reads back encoder position
}

uint32_t rov_read_encoder_velocity(int motor) {
    _rov_cmd(0x00 | (motor & 0x7), 0);
    return CFS_REG1; // reads back encoder velocity
}

uint8_t rov_read_status(void) {
    _rov_cmd(0, 0);
    return (CFS_REG2 >> 0) & 0xFF;
}

int16_t rov_read_imu_roll(void) {
    _rov_cmd(0, 0);
    return (int16_t)((CFS_REG2 >> 16) & 0xFFFF);
}

int16_t rov_read_imu_pitch(void) {
    _rov_cmd(0, 0);
    return (int16_t)((CFS_REG3 >> 0) & 0xFFFF);
}

int16_t rov_read_imu_yaw(void) {
    _rov_cmd(0, 0);
    return (int16_t)((CFS_REG3 >> 16) & 0xFFFF);
}

int16_t rov_read_pid_output(int axis) {
    _rov_cmd(0x00 | (axis & 0x7), 0);
    uint32_t reg;
    switch (axis) {
        case 0: reg = CFS_REG4; return (int16_t)((reg >> 0) & 0xFFFF);
        case 1: reg = CFS_REG4; return (int16_t)((reg >> 16) & 0xFFFF);
        case 2: reg = CFS_REG5; return (int16_t)((reg >> 0) & 0xFFFF);
        case 3: reg = CFS_REG5; return (int16_t)((reg >> 16) & 0xFFFF);
        case 4: reg = CFS_REG6; return (int16_t)((reg >> 0) & 0xFFFF);
        case 5: reg = CFS_REG6; return (int16_t)((reg >> 16) & 0xFFFF);
        default: return 0;
    }
}

uint16_t rov_read_depth_cm(void) {
    _rov_cmd(0, 0);
    return (uint16_t)((CFS_REG7 >> 0) & 0xFFFF);
}
