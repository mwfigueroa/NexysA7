#!/usr/bin/env python3
"""Verify NEORV32 bootloader at 115200 after QSPI power-cycle.
Run this AFTER moving jumper to QSPI and power-cycling the Nexys."""
import serial, time

PORT = "/dev/ttyUSB1"
BAUD = 115200

ser = serial.Serial(PORT, BAUD, timeout=3)
ser.reset_input_buffer()
time.sleep(2)  # wait for FPGA to boot from QSPI

# Send space to abort autoboot
ser.write(b' ')
time.sleep(1)
data = ser.read(1024)
print("=== Boot banner ===")
print(data.decode('latin-1', 'replace'))

# Send system info
ser.write(b'i')
time.sleep(0.8)
r = ser.read(1024)
print("\n=== System info ===")
print(r.decode('latin-1', 'replace'))

# Try hello
ser.write(b'h')
time.sleep(0.8)
r = ser.read(1024)
print("\n=== Help ===")
print(r.decode('latin-1', 'replace'))

print("\n=== VERIFICATION COMPLETE ===")
ser.close()
