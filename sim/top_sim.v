// top_sim.v — Simulation wrapper for the frequency counter
// Overrides GATE and exposes internal debug signals.
`timescale 1ns / 1ps

module top_sim (
    input  wire       CLK100MHZ,
    output wire       UART_TXD,
    input  wire       UART_RXD,
    input  wire       FREQ_IN,
    output wire [15:0] LED,
    output wire [7:0]  SSEG_CA,
    output wire [7:0]  SSEG_AN,
    // Debug outputs
    output wire        dbg_gate_done,
    output wire [36:0] dbg_freq_cal,
    output wire [26:0] dbg_pulse_count,
    output wire [26:0] dbg_gate_timer,
    output wire        dbg_signal
);

    top #(.GATE(27'd10_000)) dut (
        .CLK100MHZ (CLK100MHZ),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD),
        .FREQ_IN   (FREQ_IN),
        .LED       (LED),
        .SSEG_CA   (SSEG_CA),
        .SSEG_AN   (SSEG_AN)
    );

    assign dbg_gate_done   = dut.gate_done;
    assign dbg_freq_cal    = dut.freq_cal;
    assign dbg_pulse_count = dut.pulse_count;
    assign dbg_gate_timer  = dut.gate_timer;
    assign dbg_signal      = dut.signal;

endmodule
