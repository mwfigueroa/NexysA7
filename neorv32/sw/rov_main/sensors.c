// =============================================================================
// ROV sensors — MPU9250 (SPI, PMOD JB) + MS5837-30BA (I2C, PMOD JC)
// =============================================================================
#include <neorv32.h>
#include "sensors.h"

// rov_cfs.h se incluye solo en main.c (define funciones no-static);
// aqui usamos unicamente estos dos puntos de entrada del driver.
#define AXIS_ROLL  3
#define AXIS_PITCH 4
#define AXIS_YAW   5
extern void rov_set_imu_raw(int axis, int16_t raw_s114);
extern void rov_set_depth_raw(uint32_t pressure_pa, int16_t temp_c_x10);

// --- MPU9250 (SPI) ---
#define MPU_WHO_AM_I     0x75
#define MPU_PWR_MGMT_1   0x6B
#define MPU_GYRO_CONFIG  0x1B
#define MPU_GYRO_XOUT_H  0x43
#define MPU_WHO_AM_I_VAL 0x71

static int imu_ok = 0;
static int depth_ok = 0;

// --- MS5837-30BA (I2C, addr 0x76) ---
#define MS_ADDR       0x76
#define MS_CMD_RESET  0x1E
#define MS_CMD_D1_4096 0x48
#define MS_CMD_D2_4096 0x58
#define MS_CMD_ADC_READ 0x00
#define MS_CMD_PROM0   0xA0

static uint16_t ms_C[8];
static uint32_t ms_pressure_pa;
static int16_t  ms_temp_c10;

static uint32_t clk;
static uint32_t poll_ctr;

// =============================================================================
// SPI helpers (MPU9250, mode 0)
// =============================================================================
static void mpu_cs(uint8_t cs) { if (cs) neorv32_spi_cs_en(0); else neorv32_spi_cs_dis(); }

static void mpu_write(uint8_t reg, uint8_t val) {
  mpu_cs(1);
  neorv32_spi_transfer(reg);
  neorv32_spi_transfer(val);
  mpu_cs(0);
}

static uint8_t mpu_read(uint8_t reg) {
  uint8_t r;
  mpu_cs(1);
  neorv32_spi_transfer((uint8_t)(0x80 | reg));
  r = neorv32_spi_transfer(0);
  mpu_cs(0);
  return r;
}

static void mpu_read_burst(uint8_t reg, uint8_t *buf, int n) {
  mpu_cs(1);
  neorv32_spi_transfer((uint8_t)(0x80 | reg));
  for (int i = 0; i < n; i++) buf[i] = neorv32_spi_transfer(0);
  mpu_cs(0);
}

static int mpu_init(void) {
  neorv32_spi_setup(5, 3, 0, 0);   // ~390 kHz, mode 0 (MPU9250 <= 1 MHz)
  neorv32_spi_enable();
  neorv32_aux_delay_ms(clk, 50);

  mpu_write(MPU_PWR_MGMT_1, 0x80); // reset
  neorv32_aux_delay_ms(clk, 100);
  mpu_write(MPU_PWR_MGMT_1, 0x01); // clock = PLL X-gyro
  neorv32_aux_delay_ms(clk, 50);
  mpu_write(MPU_GYRO_CONFIG, 0x08); // gyro +-500 dps (65.5 LSB/dps)

  uint8_t who = mpu_read(MPU_WHO_AM_I);
  if (who != MPU_WHO_AM_I_VAL) {
    neorv32_uart0_printf("MPU9250: no detectado (WHO_AM_I=0x%x, esperado 0x71)\n", who);
    return 0;
  }
  return 1;
}

// gyro raw (16-bit signed) -> s1.14 rad/s : raw * 16384 * pi / (180 * 65.5)
static int16_t gyro_to_s114(int16_t raw) {
  return (int16_t)(((int32_t)raw * 4471) / 1024);
}

// =============================================================================
// TWI helpers (MS5837)
// =============================================================================
static int twi_wr(uint8_t reg_cmd) {
  uint8_t b = (uint8_t)((MS_ADDR << 1) | 0);
  neorv32_twi_generate_start();
  if (neorv32_twi_transfer(&b, 1)) { neorv32_twi_generate_stop(); return -1; }
  neorv32_twi_transfer(&reg_cmd, 1);
  neorv32_twi_generate_stop();
  return 0;
}

static int twi_rd(uint8_t reg_cmd, uint8_t *buf, int n) {
  uint8_t b = (uint8_t)((MS_ADDR << 1) | 0);
  neorv32_twi_generate_start();
  if (neorv32_twi_transfer(&b, 1)) { neorv32_twi_generate_stop(); return -1; }
  neorv32_twi_transfer(&reg_cmd, 1);
  b = (uint8_t)((MS_ADDR << 1) | 1);
  neorv32_twi_generate_start();      // repeated start
  if (neorv32_twi_transfer(&b, 1)) { neorv32_twi_generate_stop(); return -1; }
  for (int i = 0; i < n; i++) {
    neorv32_twi_transfer(&buf[i], (i == n - 1) ? 0 : 1);
  }
  neorv32_twi_generate_stop();
  return 0;
}

static int ms5837_init(void) {
  neorv32_twi_setup(6, 1, 1);        // ~200 kHz SCL (MS5837 <= 400 kHz)
  neorv32_twi_enable();
  neorv32_aux_delay_ms(clk, 10);

  if (twi_wr(MS_CMD_RESET) != 0) {
    neorv32_uart0_puts("MS5837: sin ACK en reset (sin pull-ups o sin sensor)\n");
    return 0;
  }
  neorv32_aux_delay_ms(clk, 10);

  for (int i = 0; i < 7; i++) {
    uint8_t buf[2] = {0, 0};
    if (twi_rd((uint8_t)(MS_CMD_PROM0 + i * 2), buf, 2) != 0) return 0;
    ms_C[i] = (uint16_t)((buf[0] << 8) | buf[1]);
  }
  if (ms_C[1] == 0 || ms_C[1] == 0xFFFF) {
    neorv32_uart0_puts("MS5837: PROM invalida\n");
    return 0;
  }
  return 1;
}

static void ms5837_convert(void) {
  uint8_t buf[3];

  // D1 (presion), OSR 4096 -> ~9 ms
  twi_wr(MS_CMD_D1_4096);
  neorv32_aux_delay_ms(clk, 12);
  twi_rd(MS_CMD_ADC_READ, buf, 3);
  uint32_t D1 = ((uint32_t)buf[0] << 16) | ((uint32_t)buf[1] << 8) | buf[2];

  // D2 (temperatura)
  twi_wr(MS_CMD_D2_4096);
  neorv32_aux_delay_ms(clk, 12);
  twi_rd(MS_CMD_ADC_READ, buf, 3);
  uint32_t D2 = ((uint32_t)buf[0] << 16) | ((uint32_t)buf[1] << 8) | buf[2];

  // Calibracion primer orden (30BA), aritmetica 64-bit
  int64_t dT   = (int64_t)D2 - ((int64_t)ms_C[5] << 8);
  int64_t TEMP = 2000 + (dT * ms_C[6]) / 8388608;
  int64_t OFF  = ((int64_t)ms_C[2] << 16) + (ms_C[4] * dT) / 128;
  int64_t SENS = ((int64_t)ms_C[1] << 15) + (ms_C[3] * dT) / 256;

  // Compensacion de segundo orden (TEMP < 20 C)
  if (TEMP < 2000) {
    int64_t T2  = (dT * dT) / 2147483648LL;
    int64_t OFF2  = OFF  - 6 * (TEMP - 2000) * (TEMP - 2000) / 4;
    int64_t SENS2 = SENS - 3 * (TEMP - 2000) * (TEMP - 2000) / 8;
    TEMP = TEMP - T2;
    OFF  = OFF2;
    SENS = SENS2;
  }

  int64_t P_mbar = ((int64_t)D1 * SENS / 2097152 - OFF) / 8192;
  ms_pressure_pa = (uint32_t)(P_mbar * 100);   // mbar -> Pa (CFS espera Pa)
  ms_temp_c10    = (int16_t)(TEMP / 10);       // 0.01C -> C*10
}

// =============================================================================
// Public API
// =============================================================================
void sensors_init(void) {
  clk = neorv32_sysinfo_get_clk();
  imu_ok   = mpu_init();
  depth_ok = ms5837_init();
  poll_ctr = 0;
  if (imu_ok)   neorv32_uart0_puts("MPU9250: OK (SPI PMOD JB)\n");
  if (depth_ok) neorv32_uart0_puts("MS5837: OK (I2C PMOD JC)\n");
}

void sensors_poll(void) {
  if (imu_ok) {
    uint8_t buf[6];
    mpu_read_burst(MPU_GYRO_XOUT_H, buf, 6);
    int16_t gx = (int16_t)((buf[0] << 8) | buf[1]);
    int16_t gy = (int16_t)((buf[2] << 8) | buf[3]);
    int16_t gz = (int16_t)((buf[4] << 8) | buf[5]);
    rov_set_imu_raw(AXIS_ROLL,  gyro_to_s114(gx));
    rov_set_imu_raw(AXIS_PITCH, gyro_to_s114(gy));
    rov_set_imu_raw(AXIS_YAW,   gyro_to_s114(gz));
  }

  // profundidad a 4 Hz (cada 5 ticks de 20 Hz)
  if (depth_ok && (++poll_ctr % 5 == 0)) {
    ms5837_convert();
    rov_set_depth_raw(ms_pressure_pa, ms_temp_c10);
  }
}

void sensors_status(void) {
  neorv32_uart0_puts("\n--- Sensores ---\n");
  neorv32_uart0_puts("IMU (MPU9250): ");  neorv32_uart0_puts(imu_ok   ? "OK\n" : "no detectado\n");
  neorv32_uart0_puts("Depth (MS5837): "); neorv32_uart0_puts(depth_ok ? "OK\n" : "no detectado\n");
  if (depth_ok) {
    neorv32_uart0_printf("  presion=%u Pa temp=%d (C*10)\n", ms_pressure_pa, ms_temp_c10);
  }
}

int sensors_imu_present(void)   { return imu_ok; }
int sensors_depth_present(void) { return depth_ok; }
