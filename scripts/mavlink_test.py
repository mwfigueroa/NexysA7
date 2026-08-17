import serial, struct, time, sys

PORT = '/dev/ttyUSB1'
CRCX = {0: 50, 29: 115, 30: 39, 69: 243, 70: 124, 76: 152}

def crc_step(crc, b):
    crc ^= b << 8
    for _ in range(8):
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc

def mav_crc(frame, ln, crcx):
    crc = 0xFFFF
    for b in frame[1:10 + ln]:
        crc = crc_step(crc, b)
    crc = crc_step(crc, crcx)
    return crc

def build_frame(msgid, payload, seq=0, sysid=255, compid=0):
    ln = len(payload)
    hdr = bytes([0xFD, ln, 0, 0, seq, sysid, compid,
                 msgid & 0xFF, (msgid >> 8) & 0xFF, (msgid >> 16) & 0xFF])
    frame = hdr + payload
    crc = 0xFFFF
    for b in frame[1:]:
        crc = crc_step(crc, b)
    crc = crc_step(crc, CRCX[msgid])
    return frame + bytes([crc & 0xFF, crc >> 8])

def main():
    ser = serial.Serial(PORT, 115200, timeout=0.5)
    time.sleep(0.3)
    ser.write(b'q on\r')
    time.sleep(0.5)
    ser.read(1000)

    buf = b''
    t0 = time.time()
    while time.time() - t0 < 5:
        chunk = ser.read(512)
        if not chunk:
            break
        buf += chunk

    counts = {}
    i = 0
    while i < len(buf) - 2:
        if buf[i] == 0xFD:
            ln = buf[i + 1]
            if ln > 250 or i + 12 + ln > len(buf):
                i += 1
                continue
            frame = buf[i:i + 12 + ln]
            msgid = frame[7] | frame[8] << 8 | frame[9] << 16
            crc_rx = frame[10 + ln] | frame[11 + ln] << 8
            ok = (mav_crc(frame, ln, CRCX[msgid]) == crc_rx) if msgid in CRCX else None
            counts[msgid] = counts.get(msgid, 0) + 1
            if msgid == 0 and ok:
                print('HEARTBEAT: type=%d base=0x%02X status=%d' %
                      (frame[14], frame[16], frame[17]))
            elif msgid == 30 and ok:
                roll, pitch, yaw = struct.unpack('<fff', frame[16:28])
                print('ATTITUDE: roll=%.3f pitch=%.3f yaw=%.3f rad' % (roll, pitch, yaw))
            elif msgid == 29 and ok:
                press, = struct.unpack('<f', frame[14:18])
                temp, = struct.unpack('<h', frame[22:24])
                print('PRESSURE: %.1f hPa temp=%d cdegC' % (press, temp))
            i += 12 + ln
        else:
            i += 1

    print('--- resumen:')
    for m, n in sorted(counts.items()):
        print('  msg %d: %d frames' % (m, n))

    # --- RX test: enviar MANUAL_CONTROL x=+1000 (surge full) ---
    mc = struct.pack('<hhhhHH', 1000, 0, 0, 0, 0, 0) + b'\x00' + struct.pack('<hhhhhh', 0, 0, 0, 0, 0, 0)
    ser.write(build_frame(69, mc))
    time.sleep(0.5)
    print('MANUAL_CONTROL enviado (x=+1000)')

    ser.write(b'q off\r')
    time.sleep(0.5)
    r = ser.read(500).decode('latin-1', errors='replace')
    print(r[-120:])
    ser.close()

if __name__ == '__main__':
    main()
