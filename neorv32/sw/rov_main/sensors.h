// =============================================================================
// ROV sensors — MPU9250 (SPI, PMOD JB) + MS5837-30BA (I2C, PMOD JC)
// =============================================================================
// - sensors_init(): detecta ambos sensores; degradación elegante si faltan
// - sensors_poll(): llamado a 20 Hz — gyro al CFS (CMD_IMU_RAW) y, cada 5
//   ticks, presión/temp al CFS (CMD_DEPTH_RAW)
// Mapping IMU (según montaje): gx -> roll, gy -> pitch, gz -> yaw
// =============================================================================
#ifndef ROV_SENSORS_H
#define ROV_SENSORS_H

void sensors_init(void);
void sensors_poll(void);
void sensors_status(void);

int  sensors_imu_present(void);
int  sensors_depth_present(void);

#endif
