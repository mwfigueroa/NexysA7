# ==============================================================================
# NEORV32 Nexys A7-100T — Constraints (v3: ROV motors)
# ==============================================================================

# --- Clock: 100 MHz oscillator (E3) ---
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.0 -waveform {0 5} [get_ports CLK100MHZ]

# --- Reset: CPU_RESETN (C12, active-low pushbutton) ---
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

# --- Safety switches: SW[0]=PWM_ARM (SW3=R15), SW[1]=IRQ (SW12=H6) ---
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN H6  IOSTANDARD LVCMOS33} [get_ports {SW[1]}]

# --- UART0: FTDI channel B (C4=RXD, D4=TXD) ---
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports UART_TXD]

# --- LEDs[15:0] (active-high) ---
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {LED[15]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]

# --- PWM[7:0]: PMOD JA ---
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports {PWM[0]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports {PWM[1]}]
set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports {PWM[2]}]
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports {PWM[3]}]
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33} [get_ports {PWM[4]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {PWM[5]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {PWM[6]}]
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33} [get_ports {PWM[7]}]

# --- SPI host: PMOD JB ---
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports SPI_SCK]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports SPI_MOSI]
set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports SPI_MISO]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports SPI_CSN]

# --- TWI / I2C: PMOD JC (top 2) ---
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports TWI_SCL]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports TWI_SDA]

# --- Quadrature Encoders: PMOD JD (ENC0-3) + JC (ENC4-6) + free pins (ENC7) ---
# ENC0: PMOD JD[0:1] = H4,H1
set_property -dict {PACKAGE_PIN H4  IOSTANDARD LVCMOS33} [get_ports {ENC_A[0]}]
set_property -dict {PACKAGE_PIN H1  IOSTANDARD LVCMOS33} [get_ports {ENC_B[0]}]
# ENC1: PMOD JD[2:3] = G1,H2
set_property -dict {PACKAGE_PIN G1  IOSTANDARD LVCMOS33} [get_ports {ENC_A[1]}]
set_property -dict {PACKAGE_PIN H2  IOSTANDARD LVCMOS33} [get_ports {ENC_B[1]}]
# ENC2: PMOD JD[4:5] = G3,F3
set_property -dict {PACKAGE_PIN G3  IOSTANDARD LVCMOS33} [get_ports {ENC_A[2]}]
set_property -dict {PACKAGE_PIN F3  IOSTANDARD LVCMOS33} [get_ports {ENC_B[2]}]
# ENC3: PMOD JD[6:7] = E2,D2
set_property -dict {PACKAGE_PIN E2  IOSTANDARD LVCMOS33} [get_ports {ENC_A[3]}]
set_property -dict {PACKAGE_PIN D2  IOSTANDARD LVCMOS33} [get_ports {ENC_B[3]}]
# ENC4: PMOD JC[2:3] = V10,V9
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {ENC_A[4]}]
set_property -dict {PACKAGE_PIN V9  IOSTANDARD LVCMOS33} [get_ports {ENC_B[4]}]
# ENC5: PMOD JC[4:5] = V8,U9
set_property -dict {PACKAGE_PIN V8  IOSTANDARD LVCMOS33} [get_ports {ENC_A[5]}]
set_property -dict {PACKAGE_PIN U9  IOSTANDARD LVCMOS33} [get_ports {ENC_B[5]}]
# ENC6: PMOD JC[6:7] = T9,T10
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {ENC_A[6]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {ENC_B[6]}]
# ENC7: free button pins (BTNU=M18, BTND=P18)
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports {ENC_A[7]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {ENC_B[7]}]

# --- JTAG Debug (OCD) — 7-segment cathode free pins ---
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports JTAG_TCK]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports JTAG_TDI]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports JTAG_TDO]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports JTAG_TMS]

# --- False paths on async inputs ---
set_false_path -from [get_ports UART_RXD]
set_false_path -from [get_ports CPU_RESETN]
set_false_path -from [get_ports {ENC_A[*]}]
set_false_path -from [get_ports {ENC_B[*]}]
