// top.v — Frequency counter v2 (fixed)
// Added: double-flop synchronizer on FREQ_IN, calibrated gate
`timescale 1ns / 1ps

module top (
    input  wire       CLK100MHZ,
    output wire       UART_TXD,
    input  wire       UART_RXD,      // FTDI channel B → FPGA pin C4
    input  wire       FREQ_IN,       // Pmod JD[1] = H4
    output wire [15:0] LED,
    output wire [7:0]  SSEG_CA,
    output wire [7:0]  SSEG_AN
);

    // ===== Synchronize async input =====
    reg [1:0] sync = 0;
    reg       prev_in = 0;
    always @(posedge CLK100MHZ) begin
        sync <= {sync[0], FREQ_IN};
        prev_in <= sync[1];
    end
    wire signal = sync[1];

    // ===== Frequency counter with calibrated 1s gate =====
    reg [26:0] gate_timer = 0;
    reg [26:0] pulse_count = 0;
    reg [26:0] freq_result = 0;
    reg        gate_done = 0;
    
    // Empirically calibrated: 93,200,000 cycles @ 100MHz ≈ 1 real second
    // Calibrated gate: 93.2M cycles = 1 real second
    parameter GATE = 27'd93_200_000;
    // freq_hz = count * 1073 / 1000
    wire [36:0] freq_cal = freq_result * 1073 / 1000;
    
    always @(posedge CLK100MHZ) begin
        gate_done <= 0;
        gate_timer <= gate_timer + 1;
        if (signal && !prev_in) pulse_count <= pulse_count + 1;
        if (gate_timer == GATE) begin
            gate_timer <= 0;
            freq_result <= pulse_count;
            pulse_count <= 0;
            gate_done <= 1;
        end
    end

    // ===== UART TX + RX =====
    parameter BAUD = 868;
    reg [15:0] tx_div = 0;
    reg [3:0]  tx_bit = 0;
    reg [7:0]  tx_data = 0;
    reg        tx = 1;
    reg        tx_busy = 0;
    assign UART_TXD = tx;

    // ===== UART RX =====
    // The receiver samples the asynchronous FTDI signal only after a two-flop
    // synchronizer.  A framing error discards the byte rather than echoing it.
    reg [1:0] rxd_sync = 0;
    reg [15:0] rx_div = 0;
    reg [3:0]  rx_bit = 0;
    reg [7:0]  rx_data = 0;
    reg        rx_busy = 0;
    reg        rx_valid = 0;
    reg        rx_framing_error = 0;

    // Synchronize async RXD, detect falling edge
    wire rxd_fall = (rxd_sync == 2'b10);

    always @(posedge CLK100MHZ) begin
        rxd_sync <= {rxd_sync[0], UART_RXD};
        rx_valid <= 0;

        if (!rx_busy) begin
            if (rxd_fall) begin           // start bit detected
                rx_busy <= 1;
                rx_div  <= 0;
                rx_bit  <= 0;
                rx_data <= 0;
            end
        end else begin
            rx_div <= rx_div + 1;
            // Sample strategy: skip start-bit mid (BAUD/2), then
            // sample data bits at mid-points every BAUD cycles.
            if (rx_bit == 0 && rx_div == (BAUD/2 - 1)) begin
                // Reject a short low glitch that is not a valid start bit.
                if (!rxd_sync[1]) begin
                    rx_div <= 0;
                    rx_bit <= 1;  // advance to data-bit sampling phase
                end else begin
                    rx_busy <= 0;
                end
            end else if (rx_bit >= 1 && rx_bit <= 8 && rx_div == BAUD - 1) begin
                rx_div <= 0;
                rx_data[rx_bit - 1] <= rxd_sync[1];
                rx_bit <= rx_bit + 1;
            end else if (rx_bit == 9 && rx_div == BAUD - 1) begin
                // Stop bit must be high.  A bad frame is discarded.
                rx_busy <= 0;
                if (rxd_sync[1]) begin
                    rx_valid <= 1;
                end else begin
                    rx_framing_error <= 1;
                end
            end
        end
    end

    // ===== RX FIFO and the sole UART TX owner =====
    // A 16-byte FIFO absorbs a host burst while the transmitter is busy.
    // Only this block owns FIFO pointers/count and all TX state; this avoids
    // procedural multi-drivers and prevents an echo from corrupting a report.
    localparam FIFO_DEPTH = 16;
    reg [7:0] rx_fifo [0:FIFO_DEPTH-1];
    reg [3:0] fifo_wr_ptr = 0;
    reg [3:0] fifo_rd_ptr = 0;
    reg [4:0] fifo_count = 0;
    reg       rx_overflow = 0;
    wire      fifo_empty = (fifo_count == 0);
    wire      fifo_full  = (fifo_count == FIFO_DEPTH);
    wire      fifo_push  = rx_valid && !fifo_full;

    reg        freq_pending = 0;
    reg        report_active = 0;
    reg [3:0]  report_idx = 0;
    reg [36:0] report_freq = 0;
    reg        tx_is_report = 0;
    wire       fifo_pop = !tx_busy && !report_active && !fifo_empty;

    function [7:0] report_char;
        input [3:0]  index;
        input [36:0] value;
        begin
            case (index)
                0: report_char = (value / 10000000) % 10 + "0";
                1: report_char = (value / 1000000)  % 10 + "0";
                2: report_char = (value / 100000)   % 10 + "0";
                3: report_char = (value / 10000)    % 10 + "0";
                4: report_char = (value / 1000)     % 10 + "0";
                5: report_char = (value / 100)      % 10 + "0";
                6: report_char = (value / 10)       % 10 + "0";
                7: report_char =  value              % 10 + "0";
                8: report_char = "\r";
                default: report_char = "\n";
            endcase
        end
    endfunction

    always @(posedge CLK100MHZ) begin
        // FIFO push/pop and count are deliberately owned by this one block.
        if (fifo_push) begin
            rx_fifo[fifo_wr_ptr] <= rx_data;
            fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
        end
        if (fifo_pop) begin
            fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
        end
        case ({fifo_push, fifo_pop})
            2'b10: fifo_count <= fifo_count + 1'b1;
            2'b01: fifo_count <= fifo_count - 1'b1;
            default: fifo_count <= fifo_count;
        endcase
        if (rx_valid && fifo_full) begin
            rx_overflow <= 1;
        end

        // Start a byte only when the previous byte has fully completed.
        if (!tx_busy) begin
            if (report_active) begin
                tx_data <= report_char(report_idx, report_freq);
                tx_div <= 0;
                tx_bit <= 0;
                tx <= 0;
                tx_busy <= 1;
                tx_is_report <= 1;
            end else if (fifo_pop) begin
                tx_data <= rx_fifo[fifo_rd_ptr];
                tx_div <= 0;
                tx_bit <= 0;
                tx <= 0;
                tx_busy <= 1;
                tx_is_report <= 0;
            end else if (freq_pending && !rx_valid) begin
                // Snapshot the value so all eight report characters agree.
                report_freq <= freq_cal;
                report_idx <= 0;
                report_active <= 1;
                freq_pending <= 0;
            end
        end else begin
            if (tx_div == BAUD - 1) begin
                tx_div <= 0;
                tx_bit <= tx_bit + 1'b1;
                case (tx_bit)
                    0,1,2,3,4,5,6,7: tx <= tx_data[tx_bit];
                    8: tx <= 1;
                    9: begin
                        tx <= 1;
                        tx_busy <= 0;
                        if (tx_is_report) begin
                            if (report_idx == 4'd9) begin
                                report_active <= 0;
                                report_idx <= 0;
                            end else begin
                                report_idx <= report_idx + 1'b1;
                            end
                        end
                    end
                    default: begin
                        // Recover to the UART idle state if TX state is upset.
                        tx <= 1;
                        tx_busy <= 0;
                    end
                endcase
            end else begin
                tx_div <= tx_div + 1;
            end
        end

        // A measurement event is retained even while a report or echo runs.
        // This assignment is last so a coincident new measurement is not lost.
        if (gate_done) begin
            freq_pending <= 1;
        end
    end

    // ===== 7-segment =====
    reg [2:0] scan = 0;
    reg [15:0] scan_div = 0;
    wire [36:0] freq_khz = freq_cal / 1000;
    reg [3:0] digit [0:7];
    always @(posedge CLK100MHZ) begin
        digit[0] <= (freq_khz / 100000) % 10; digit[1] <= (freq_khz / 10000) % 10;
        digit[2] <= (freq_khz / 1000) % 10;   digit[3] <= (freq_khz / 100) % 10;
        digit[4] <= (freq_khz / 10) % 10;     digit[5] <= freq_khz % 10;
        digit[6] <= 4'hF;                     digit[7] <= 4'hF;
    end
    always @(posedge CLK100MHZ) begin
        scan_div <= scan_div + 1;
        if (scan_div == 16'd50000) begin scan_div <= 0; scan <= scan + 1; end
    end
    function [6:0] seg; input [3:0] d;
        case (d)
            0: seg=7'b1000000; 1: seg=7'b1111001; 2: seg=7'b0100100; 3: seg=7'b0110000;
            4: seg=7'b0011001; 5: seg=7'b0010010; 6: seg=7'b0000010; 7: seg=7'b1111000;
            8: seg=7'b0000000; 9: seg=7'b0010000; default: seg=7'b1111111;
        endcase
    endfunction
    assign SSEG_CA = {1'b1, seg(digit[scan])};
    assign SSEG_AN = ~(8'b1 << scan);

    // ===== LEDs =====
    reg [26:0] lc = 0;
    always @(posedge CLK100MHZ) lc <= lc + 1;
    assign LED[0]  = lc[26];
    assign LED[1]  = tx_busy;
    assign LED[2]  = signal;
    assign LED[3]  = rx_busy;             // LED on while receiving
    assign LED[4]  = !fifo_empty;         // queued echo bytes
    assign LED[5]  = rx_overflow;         // FIFO overflow, sticky until reload
    assign LED[6]  = rx_framing_error;    // bad UART stop bit, sticky until reload
    assign LED[15:7] = 0;
endmodule
