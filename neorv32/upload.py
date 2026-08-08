#!/usr/bin/env python3
"""Upload and execute a NEORV32 executable via UART bootloader.

Usage (from WSL):
  python3 upload_neorv32.py /mnt/p/neorv32/sw/example/hello_world/neorv32_exe.bin

Requires: pyserial (pip install pyserial)
"""

import serial, time, sys

PORT = "/dev/ttyUSB1"
BAUD = 115200

def main():
    exe_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not exe_path:
        print(f"Usage: {sys.argv[0]} <neorv32_exe.bin>")
        sys.exit(1)

    with open(exe_path, "rb") as f:
        binary = f.read()
    if binary[:4] != b"NEO!":
        print("ERROR: not a NEORV32 executable (missing NEO! header)")
        sys.exit(1)
    print(f"Executable: {len(binary)} bytes")

    ser = serial.Serial(PORT, BAUD, timeout=2)
    time.sleep(0.3)

    # Wake / abort autoboot
    ser.write(b" ")
    time.sleep(0.5)
    ser.read(512)

    # Upload
    ser.write(b"u")
    time.sleep(0.3)
    data = ser.read(256)
    if b"Awaiting" not in data:
        print("ERROR: bootloader not ready\n")
        ser.close()
        sys.exit(1)

    print("Uploading...", end="", flush=True)
    ser.write(binary)
    ser.flush()
    time.sleep(3)
    result = ser.read(256)
    print(f" {result.decode().strip()}")

    # Execute
    print("Booting...")
    ser.write(b"e")
    time.sleep(1.5)
    output = ser.read(4096)
    print(output.decode("latin-1", errors="replace"))
    ser.close()

if __name__ == "__main__":
    main()
