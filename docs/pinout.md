# Nexys A7-100T — Mapa de I/O

> Fuente: XDC oficial de Digilent (Nexys-A7-100T-Master.xdc)
> FPGA: XC7A100T-1CSG324C (324-pin CSG324, 100K logic cells)

---

## Clock

| Señal | Pin | Estándar |
|---|---|---|
| CLK100MHZ | E3 | LVCMOS33 (100 MHz osc) |

---

## USB-UART Bridge (FTDI FT2232H)

| Señal | Pin | Dirección |
|---|---|---|
| UART_TXD_IN (FPGA RX) | **C4** | FTDI → FPGA |
| UART_RXD_OUT (FPGA TX) | **D4** | FPGA → FTDI |
| UART_CTS | D3 | Flow control |
| UART_RTS | E5 | Flow control |

---

## LEDs (16 + 2 RGB)

| LED | Pin |
|---|---|
| LED[0] | H17 |
| LED[1] | K15 |
| LED[2] | J13 |
| LED[3] | N14 |
| LED[4] | R18 |
| LED[5] | V17 |
| LED[6] | U17 |
| LED[7] | U16 |
| LED[8] | V16 |
| LED[9] | T15 |
| LED[10] | U14 |
| LED[11] | T16 |
| LED[12] | V15 |
| LED[13] | V14 |
| LED[14] | V12 |
| LED[15] | V11 |
| LED16_R | N16 |
| LED16_G | M16 |
| LED16_B | R12 |
| LED17_R | N16 |
| LED17_G | R11 |
| LED17_B | G14 |

---

## 7-Segment Display (ánodo común)

| Segmento | Pin |
|---|---|
| CA | T10 |
| CB | R10 |
| CC | K16 |
| CD | K13 |
| CE | P15 |
| CF | T11 |
| CG | L18 |
| DP | H15 |
| AN[0] | J17 |
| AN[1] | J18 |
| AN[2] | T9 |
| AN[3] | J14 |
| AN[4] | P14 |
| AN[5] | T14 |
| AN[6] | K2 |
| AN[7] | U13 |

---

## Switches (16)

| SW | Pin |
|---|---|
| SW[0] | J15 |
| SW[1] | L16 |
| SW[2] | M13 |
| SW[3] | R15 |
| SW[4] | R17 |
| SW[5] | T18 |
| SW[6] | U18 |
| SW[7] | R13 |
| SW[8] | T8 |
| SW[9] | U8 |
| SW[10] | R16 |
| SW[11] | T13 |
| SW[12] | H6 |
| SW[13] | U12 |
| SW[14] | U11 |
| SW[15] | V10 |

---

## Buttons (5)

| Botón | Pin |
|---|---|
| BTNC (center) | N17 |
| BTNU (up) | M18 |
| BTNL (left) | P17 |
| BTNR (right) | M17 |
| BTND (down) | P18 |
| CPU_RESETN | C12 |

---

## Pmod Headers

### JA (top row, right)
| Pin | FPGA |
|---|---|
| JA[1] | C17 |
| JA[2] | D18 |
| JA[3] | E18 |
| JA[4] | G17 |
| JA[7] | D17 |
| JA[8] | E17 |
| JA[9] | F18 |
| JA[10] | G18 |

### JB
| Pin | FPGA |
|---|---|
| JB[1] | D14 |
| JB[2] | F16 |
| JB[3] | G16 |
| JB[4] | H14 |
| JB[7] | E16 |
| JB[8] | F13 |
| JB[9] | G13 |
| JB[10] | H16 |

### JC
| Pin | FPGA |
|---|---|
| JC[1] | K1 |
| JC[2] | F6 |
| JC[3] | J2 |
| JC[4] | G6 |
| JC[7] | E7 |
| JC[8] | J3 |
| JC[9] | J4 |
| JC[10] | E6 |

### JD
| Pin | FPGA |
|---|---|
| JD[1] | H4 |
| JD[2] | H1 |
| JD[3] | G1 |
| JD[4] | G3 |
| JD[7] | H2 |
| JD[8] | G4 |
| JD[9] | G2 |
| JD[10] | F3 |

### JXADC (analog)
| Pin | FPGA |
|---|---|
| XA_N[1] | A14 |
| XA_P[1] | A13 |
| XA_N[2] | A16 |
| XA_P[2] | A15 |
| XA_N[3] | B17 |
| XA_P[3] | B16 |
| XA_N[4] | A18 |
| XA_P[4] | B18 |

---

## VGA (12-bit, 4-4-4)

| Señal | Pin |
|---|---|
| VGA_R[0] | A3 |
| VGA_R[1] | B4 |
| VGA_R[2] | C5 |
| VGA_R[3] | A4 |
| VGA_G[0] | C6 |
| VGA_G[1] | A5 |
| VGA_G[2] | B6 |
| VGA_G[3] | A6 |
| VGA_B[0] | B7 |
| VGA_B[1] | C7 |
| VGA_B[2] | D7 |
| VGA_B[3] | D8 |
| VGA_HS | B11 |
| VGA_VS | B12 |

---

## Ethernet (SMSC LAN8720A)

| Señal | Pin |
|---|---|
| ETH_MDC | C9 |
| ETH_MDIO | A9 |
| ETH_RSTN | B3 |
| ETH_CRSDV | D9 |
| ETH_RXERR | C10 |
| ETH_RXD[0] | C11 |
| ETH_RXD[1] | D10 |
| ETH_TXEN | B9 |
| ETH_TXD[0] | A10 |
| ETH_TXD[1] | A8 |
| ETH_REFCLK | D5 |
| ETH_INTN | B8 |

---

## Sensores onboard

### Acelerómetro (ADXL362, SPI)
| Señal | Pin |
|---|---|
| ACL_MISO | E15 |
| ACL_MOSI | F14 |
| ACL_SCLK | F15 |
| ACL_CSN | D15 |
| ACL_INT[1] | B13 |
| ACL_INT[2] | C16 |

### Temperatura (ADT7420, I2C)
| Señal | Pin |
|---|---|
| TMP_SCL | C14 |
| TMP_SDA | C15 |
| TMP_INT | D13 |
| TMP_CT | B14 |

### Micrófono (MEMS PDM)
| Señal | Pin |
|---|---|
| M_CLK | J5 |
| M_DATA | H5 |
| M_LRSEL | F5 |

---

## Audio (PWM mono)

| Señal | Pin |
|---|---|
| AUD_PWM | A11 |
| AUD_SD | D12 |

---

## Micro SD

| Señal | Pin |
|---|---|
| SD_RESET | E2 |
| SD_CD | A1 |
| SD_SCK | B1 |
| SD_CMD | C1 |
| SD_DAT[0] | C2 |
| SD_DAT[1] | E1 |
| SD_DAT[2] | F1 |
| SD_DAT[3] | D2 |

---

## QSPI Flash (16 MB)

| Señal | Pin |
|---|---|
| QSPI_DQ[0] | K17 |
| QSPI_DQ[1] | K18 |
| QSPI_DQ[2] | L14 |
| QSPI_DQ[3] | M14 |
| QSPI_CSN | L13 |

---

## PS/2 (USB HID)

| Señal | Pin |
|---|---|
| PS2_CLK | F4 |
| PS2_DATA | B2 |
