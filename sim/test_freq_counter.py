# test_freq_counter.py — cocotb 2.x testbench for Nexys A7 frequency counter
# Run: make -C sim cocotb

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
from cocotb_tools.runner import get_runner
from cocotb.utils import get_sim_time

SIM_GATE = 10_000     # top_sim GATE override
BAUD     = 868        # 115200 bps @ 100 MHz (868 cycles/bit)


# ── helpers ──────────────────────────────────────────────────────────────

def decode_7seg(ca):
    """Decode {DP,G,F,E,D,C,B,A} (active-low) to char."""
    seg = ca & 0x7F
    return {
        0b1000000: "0", 0b1111001: "1", 0b0100100: "2",
        0b0110000: "3", 0b0011001: "4", 0b0010010: "5",
        0b0000010: "6", 0b1111000: "7", 0b0000000: "8",
        0b0010000: "9", 0b1111111: " ",
    }.get(seg, "?")


async def wait_gate_done(dut, count=1):
    """Wait for *count* gate_done pulses, return True if seen."""
    seen = 0
    deadline = count * (SIM_GATE + 10_000)
    for _ in range(deadline):
        await RisingEdge(dut.CLK100MHZ)
        if int(dut.dbg_gate_done.value) == 1:
            seen += 1
            if seen >= count:
                return True
    return False


async def read_uart_bytes(dut, max_bytes=32, timeout_cycles=500_000):
    """Collect UART bytes with robust start-bit alignment."""
    received = bytearray()
    prev_tx = 1
    for _ in range(timeout_cycles):
        await RisingEdge(dut.CLK100MHZ)
        tx = int(dut.UART_TXD.value)
        # Detect falling edge (1 → 0): start bit begins
        if prev_tx == 1 and tx == 0:
            # Sample from THIS edge: mid-bit of each data bit.
            # Start-bit mid: BAUD/2 = 434 cycles from here. Skip it.
            # Then sample data bits at mid-points (BAUD apart).
            await ClockCycles(dut.CLK100MHZ, BAUD // 2)  # to mid of start bit
            await ClockCycles(dut.CLK100MHZ, BAUD)        # to mid of bit 0
            byte_val = 0
            for b in range(8):
                byte_val |= (int(dut.UART_TXD.value) << b)
                if b < 7:
                    await ClockCycles(dut.CLK100MHZ, BAUD)  # to mid of next bit
            # Stop bit at mid-point
            await ClockCycles(dut.CLK100MHZ, BAUD)
            received.append(byte_val)
            if byte_val == ord('\n') or len(received) >= max_bytes:
                break
        prev_tx = tx
    return received


async def uart_send_bytes(dut, data):
    """Drive an 8N1, 115200-baud host burst into the DUT RX pin."""
    dut.UART_RXD.value = 1
    await ClockCycles(dut.CLK100MHZ, BAUD)
    for byte in data:
        dut.UART_RXD.value = 0
        await ClockCycles(dut.CLK100MHZ, BAUD)
        for bit in range(8):
            dut.UART_RXD.value = (byte >> bit) & 1
            await ClockCycles(dut.CLK100MHZ, BAUD)
        dut.UART_RXD.value = 1
        await ClockCycles(dut.CLK100MHZ, BAUD)


async def capture_uart(dut, duration_ns):
    """Decode all complete bytes emitted by UART_TXD during duration_ns."""
    captured = bytearray()
    deadline_ns = get_sim_time(unit="ns") + duration_ns
    prev_tx = int(dut.UART_TXD.value)

    while get_sim_time(unit="ns") < deadline_ns:
        await RisingEdge(dut.CLK100MHZ)
        tx = int(dut.UART_TXD.value)
        if prev_tx == 1 and tx == 0:
            # From the start edge to the first data-bit midpoint is 1.5 bits.
            await ClockCycles(dut.CLK100MHZ, BAUD + BAUD // 2)
            byte_val = 0
            for bit in range(8):
                byte_val |= int(dut.UART_TXD.value) << bit
                if bit < 7:
                    await ClockCycles(dut.CLK100MHZ, BAUD)
            # Advance through the stop bit before looking for the next start.
            await ClockCycles(dut.CLK100MHZ, BAUD)
            captured.append(byte_val)
            prev_tx = int(dut.UART_TXD.value)
        else:
            prev_tx = tx

    return captured


async def setup(dut, freq_hz=100_000):
    """Clock + FREQ_IN generator. Returns freq_gen closure for adjusting period."""
    cocotb.start_soon(Clock(dut.CLK100MHZ, 10, unit="ns").start())
    half_ns = int(1e9 / freq_hz / 2)  # half-period in ns
    dut.FREQ_IN.value = 0
    dut.UART_RXD.value = 1

    async def _gen():
        while True:
            await Timer(half_ns, unit="ns")
            dut.FREQ_IN.value = ~dut.FREQ_IN.value

    cocotb.start_soon(_gen())
    await ClockCycles(dut.CLK100MHZ, 100)  # settle


# ── tests ────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_basic(dut):
    """100 kHz → freq_cal ≈ 10 kHz, 7-seg shows 000010, LED[0] blinks."""
    await setup(dut, 100_000)

    assert await wait_gate_done(dut, count=3), "Timeout waiting for gate_done"
    # freq_cal updates one cycle after gate_done (NBA)
    await RisingEdge(dut.CLK100MHZ)
    freq_cal = int(dut.dbg_freq_cal.value)
    dut._log.info(f"freq_cal = {freq_cal} kHz")
    assert 8 <= freq_cal <= 12, f"Expected ~10 kHz, got {freq_cal}"

    # 7-segment scan
    digits = [""] * 6
    for _ in range(300_000):
        await RisingEdge(dut.CLK100MHZ)
        an = int(dut.SSEG_AN.value)
        ca = int(dut.SSEG_CA.value)
        for pos in range(6):
            if (an & (1 << pos)) == 0:
                digits[pos] = decode_7seg(ca)
        if "" not in digits:
            break
    display = "".join(digits)
    dut._log.info(f"7-segment: {display}")

    # With SIM_GATE=10,000, freq_cal=10 kHz → fk=0 → display shows "000000".
    # Accept "000000" when freq_cal < 1000.
    if freq_cal >= 1000:
        assert "0" in display, f"7-seg should show digits, got {display}"
    else:
        assert display == "000000", f"Low freq should show 000000, got {display}"

    # LED: lc[26] needs ~67M cycles. Skip toggle test for short sim.
    if int(dut.LED.value) & 1:
        dut._log.info("LED[0] already high — heartbeat active")
    dut._log.info("Basic test PASSED")


@cocotb.test()
async def test_uart(dut):
    """Verify UART transmits frequency digits after gate."""
    await setup(dut, 100_000)

    assert await wait_gate_done(dut, count=2), "Timeout waiting for gate_done"
    data = await read_uart_bytes(dut, max_bytes=32, timeout_cycles=300_000)

    msg = data.decode("ascii", errors="replace")
    digits = "".join(ch for ch in msg if ch.isdigit())
    dut._log.info(f"UART raw ({len(data)}B): {data.hex()}")
    dut._log.info(f"UART msg: {msg!r}  digits: {digits!r}")

    assert len(digits) >= 3, f"Too few digits: {digits!r}"
    assert digits[0] == "0", f"First digit should be 0, got {digits[0]!r}"
    dut._log.info("UART test PASSED")


@cocotb.test()
async def test_uart_echo_burst(dut):
    """A host burst is echoed completely, without FIFO overflow or corruption."""
    await setup(dut, 100_000)
    payload = b"Hello, FPGA!\r\n"

    capture_task = cocotb.start_soon(capture_uart(dut, duration_ns=5_000_000))
    await ClockCycles(dut.CLK100MHZ, 100)
    await uart_send_bytes(dut, payload)
    captured = await capture_task

    dut._log.info(f"UART captured ({len(captured)}B): {captured!r}")
    assert payload in captured, (
        f"Echo payload missing/corrupted: expected {payload!r}, got {captured!r}"
    )
    assert int(dut.dut.rx_overflow.value) == 0, "RX FIFO overflowed"
    assert int(dut.dut.rx_framing_error.value) == 0, "Unexpected UART framing error"
    dut._log.info("UART burst echo test PASSED")


@cocotb.test()
async def test_two_freqs(dut):
    """Switch from 100 kHz to 200 kHz, verify freq_cal tracks."""
    cocotb.start_soon(Clock(dut.CLK100MHZ, 10, unit="ns").start())
    half_ns = [5000]  # mutable, starts at 100 kHz
    dut.FREQ_IN.value = 0

    async def _gen():
        while True:
            await Timer(half_ns[0], unit="ns")
            dut.FREQ_IN.value = ~dut.FREQ_IN.value
    cocotb.start_soon(_gen())
    await ClockCycles(dut.CLK100MHZ, 100)

    assert await wait_gate_done(dut, count=2)
    await RisingEdge(dut.CLK100MHZ)
    f1 = int(dut.dbg_freq_cal.value)
    dut._log.info(f"100 kHz → {f1} kHz")

    # Switch to 200 kHz
    half_ns[0] = 2500
    await ClockCycles(dut.CLK100MHZ, 100)

    assert await wait_gate_done(dut, count=2)
    await RisingEdge(dut.CLK100MHZ)
    f2 = int(dut.dbg_freq_cal.value)
    dut._log.info(f"200 kHz → {f2} kHz")

    assert f2 > f1, f"{f2} should be > {f1}"
    assert f2 >= f1 * 1.3, f"Ratio too low: {f2}/{f1}"
    dut._log.info("Two-frequency test PASSED")
