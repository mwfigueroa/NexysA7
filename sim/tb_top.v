// tb_top.v — Testbench for Nexys A7 frequency counter
// Run: iverilog -o sim/tb_top.vvp -I src sim/tb_top.v src/top.v && vvp sim/tb_top.vvp
// View: gtkwave sim/tb_top.vcd

`timescale 1ns / 1ps

module tb_top;

    // ── DUT signals ──
    reg        CLK100MHZ = 0;
    reg        FREQ_IN   = 0;
    reg        UART_RXD  = 1;
    wire       UART_TXD;
    wire [15:0] LED;
    wire [7:0]  SSEG_CA;
    wire [7:0]  SSEG_AN;

    // ── Simulation parameters ──
    // Real gate = 93,200,000.  Override to 10,000 for fast simulation.
    localparam SIM_GATE = 27'd10_000;

    // ── Instantiate DUT with reduced gate ──
    top #(.GATE(SIM_GATE)) dut (
        .CLK100MHZ (CLK100MHZ),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD),
        .FREQ_IN   (FREQ_IN),
        .LED       (LED),
        .SSEG_CA   (SSEG_CA),
        .SSEG_AN   (SSEG_AN)
    );

    // ── 100 MHz clock (10 ns period) ──
    always #5 CLK100MHZ = ~CLK100MHZ;

    // ── Stimulus: square wave on FREQ_IN ──
    // 100 kHz = 10 us period = 1000 clk cycles → 500 cycles high, 500 low
    // With SIM_GATE=10,000, gate period = 100 us → ~10 edges → freq_cal ≈ 10
    // freq_hz = 10 * 1073 / 1000 = 10 → display shows "0.010" kHz
    integer freq_in_toggle;
    initial begin
        freq_in_toggle = 0;
        FREQ_IN = 0;
        forever begin
            #(500 * 10); // 500 clk cycles * 10 ns = 5 us
            freq_in_toggle = freq_in_toggle + 1;
            FREQ_IN = ~FREQ_IN;
        end
    end

    // ── UART decoder (115200 baud, 868 cycles/bit @ 100 MHz) ──
    reg [7:0] uart_byte;
    reg       uart_byte_ready;
    integer   uart_bit_cnt;
    integer   uart_clk_cnt;
    reg       uart_prev;
    reg       uart_receiving;

    // ── UART host burst / echo checker ──
    localparam ECHO_LEN = 14;
    reg [7:0] echo_expected [0:ECHO_LEN-1];
    integer echo_match;
    integer ei;

    task send_uart_byte;
        input [7:0] data;
        integer bi;
        begin
            UART_RXD = 0;
            #(868 * 10);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                UART_RXD = data[bi];
                #(868 * 10);
            end
            UART_RXD = 1;
            #(868 * 10);
        end
    endtask

    initial begin
        uart_byte = 0;
        uart_byte_ready = 0;
        uart_bit_cnt = 0;
        uart_clk_cnt = 0;
        uart_prev = 1;
        uart_receiving = 0;
        echo_match = 0;
        echo_expected[0]  = "H"; echo_expected[1]  = "e";
        echo_expected[2]  = "l"; echo_expected[3]  = "l";
        echo_expected[4]  = "o"; echo_expected[5]  = ",";
        echo_expected[6]  = " "; echo_expected[7]  = "F";
        echo_expected[8]  = "P"; echo_expected[9]  = "G";
        echo_expected[10] = "A"; echo_expected[11] = "!";
        echo_expected[12] = 8'h0D; echo_expected[13] = 8'h0A;
        UART_RXD = 1;
        #(50_000);  // 50 us after configuration
        for (ei = 0; ei < ECHO_LEN; ei = ei + 1)
            send_uart_byte(echo_expected[ei]);
    end

    always @(posedge CLK100MHZ) begin
        uart_prev <= UART_TXD;
        uart_byte_ready <= 0;

        if (!uart_receiving) begin
            // Wait for start bit (falling edge)
            if (uart_prev && !UART_TXD) begin
                uart_receiving <= 1;
                uart_bit_cnt   <= 0;
                uart_clk_cnt   <= 0;
            end
        end else begin
            // First sample is 1.5 bits after the start edge; the remaining
            // samples are one bit apart.  This samples bit centres, not edges.
            if (uart_clk_cnt == ((uart_bit_cnt == 0) ? 1301 : 867)) begin
                uart_clk_cnt <= 0;
                if (uart_bit_cnt < 8) begin
                    uart_byte[uart_bit_cnt] <= UART_TXD;
                    uart_bit_cnt <= uart_bit_cnt + 1;
                end else if (uart_bit_cnt == 8) begin
                    // stop bit — capture byte
                    uart_byte_ready <= 1;
                    uart_receiving  <= 0;
                end
            end else begin
                uart_clk_cnt <= uart_clk_cnt + 1;
            end
        end
    end

    // ── Print UART output ──
    always @(posedge CLK100MHZ) begin
        if (uart_byte_ready) begin
            if (uart_byte >= 32 && uart_byte < 127)
                $write("%c", uart_byte);
            else if (uart_byte == 13 || uart_byte == 10)
                $write("\n");
            else
                $write("[%02X]", uart_byte);

            if (echo_match < ECHO_LEN) begin
                if (uart_byte == echo_expected[echo_match]) begin
                    echo_match <= echo_match + 1;
                end else if (uart_byte == echo_expected[0]) begin
                    echo_match <= 1;
                end else begin
                    echo_match <= 0;
                end
            end
        end
    end

    // ── Periodic status dump ──
    integer dump_timer;
    integer gate_count;
    reg [7:0] sseg_chars [0:5];
    integer ci;

    initial begin
        dump_timer = 0;
        gate_count = 0;
    end

    always @(posedge CLK100MHZ) begin
        dump_timer <= dump_timer + 1;
        if (dut.gate_done) gate_count <= gate_count + 1;

        // Capture 7-seg digits (each anode active for ~50k cycles)
        if (SSEG_AN[0] == 0) sseg_chars[0] <= SSEG_CA[6:0];
        if (SSEG_AN[1] == 0) sseg_chars[1] <= SSEG_CA[6:0];
        if (SSEG_AN[2] == 0) sseg_chars[2] <= SSEG_CA[6:0];
        if (SSEG_AN[3] == 0) sseg_chars[3] <= SSEG_CA[6:0];
        if (SSEG_AN[4] == 0) sseg_chars[4] <= SSEG_CA[6:0];
        if (SSEG_AN[5] == 0) sseg_chars[5] <= SSEG_CA[6:0];

        // Dump every 10,000 cycles (~0.1 ms simulated)
        if (dump_timer % 10_000 == 0) begin
            $write("[t=%0d ns] gate=%0d freq_result=%0d freq_cal=%0d  ",
                   $time, gate_count, dut.freq_result, dut.freq_cal);
            $write("LED[1:0]=%b%b TX_busy=%b ",
                   LED[0], LED[1], dut.tx_busy);
            $write("CA=%b AN=%b  ",
                   SSEG_CA[6:0], SSEG_AN[5:0]);
            $display("");
        end
    end

    // ── Run for N gate periods ──
    initial begin
        $display("=== Nexys A7 Frequency Counter Simulation ===");
        $display("CLK: 100 MHz, FREQ_IN: 100 kHz square wave");
        $display("SIM_GATE: %0d cycles (~%0d us per gate)", SIM_GATE,
                 SIM_GATE * 10 / 1000);
        $display("Expected: ~10 pulses/gate, freq_cal ~10 kHz");
        $display("UART output (decoded):\n");

        // Run long enough for a frequency report plus the queued echo burst.
        #(4_000_000);

        $display("\n=== Simulation complete after %0d gate(s) ===", gate_count);
        if (echo_match != ECHO_LEN) begin
            $fatal(1, "UART echo check failed: matched %0d/%0d bytes", echo_match, ECHO_LEN);
        end
        $display("UART echo burst check PASSED (%0d bytes)", echo_match);
        $finish;
    end

    // ── Waveform dump (iverilog only; xsim uses .wdb) ──
`ifndef XILINX_SIMULATOR
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end
`endif

endmodule
