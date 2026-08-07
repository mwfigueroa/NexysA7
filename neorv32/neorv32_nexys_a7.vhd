-- ================================================================================ --
-- NEORV32 - Top-Level Wrapper for Digilent Nexys A7-100T (XC7A100T-1CSG324)        --
-- -------------------------------------------------------------------------------- --
-- Clock:        100 MHz onboard oscillator (E3)                                     --
-- UART0:        FTDI channel B → C4 (RXD) / D4 (TXD) at configured baud            --
-- GPIO[15:0]:   LEDs (active high: LED0=T14, …, LED15=V19)                         --
-- Reset:        CPU_RESETN (C12, active low, pushbutton)                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_nexys_a7 is
  port (
    -- Global control --
    CLK100MHZ  : in  std_ulogic;  -- 100 MHz from onboard oscillator (E3)
    CPU_RESETN : in  std_ulogic;  -- active-low reset button (C12)
    -- UART0 (FTDI) --
    UART_RXD   : in  std_ulogic;  -- C4, FTDI channel B TX → FPGA
    UART_TXD   : out std_ulogic;  -- D4, FPGA → FTDI channel B RX
    -- GPIO / LEDs --
    LED        : out std_ulogic_vector(15 downto 0)
  );
end entity;

architecture neorv32_nexys_a7_rtl of neorv32_nexys_a7 is

  signal gpio_o : std_ulogic_vector(31 downto 0);
  signal con_gpio_o : std_ulogic_vector(15 downto 0);

begin

  -- NEORV32 Processor --------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    -- General --
    CLOCK_FREQUENCY     => 100_000_000,
    -- Boot Configuration --
    BOOT_MODE_SELECT    => 0,            -- boot via internal bootloader
    -- On-Chip Debugger --
    OCD_EN              => false,        -- no JTAG debug in this build
    -- RISC-V CPU Extensions --
    RISCV_ISA_C         => true,         -- compressed extension
    RISCV_ISA_M         => true,         -- mul/div extension
    RISCV_ISA_Zicntr    => true,         -- base counters
    -- Tuning Options --
    CPU_FAST_MUL_EN     => true,         -- use DSPs for multiplier
    CPU_FAST_SHIFT_EN   => true,         -- barrel shifter
    CPU_RF_ARCH_SEL     => 1,            -- distributed RAM for register file
    -- Physical Memory Protection --
    PMP_NUM_REGIONS     => 0,
    -- Internal Instruction Memory --
    IMEM_EN             => true,
    IMEM_SIZE           => 32 * 1024,    -- 32 KB instruction memory
    -- Internal Data Memory --
    DMEM_EN             => true,
    DMEM_SIZE           => 8 * 1024,     -- 8 KB data memory
    -- Caches --
    ICACHE_EN           => false,
    DCACHE_EN           => false,
    -- External Bus Interface --
    XBUS_EN             => false,
    -- Processor Peripherals --
    IO_GPIO_NUM         => 16,           -- 16 LED outputs
    IO_CLINT_EN         => true,         -- core-local interruptor
    IO_UART0_EN         => true,         -- primary UART
    IO_UART0_RX_FIFO    => 64,           -- 64-entry RX FIFO
    IO_UART0_TX_FIFO    => 64            -- 64-entry TX FIFO
  )
  port map (
    -- Global control --
    clk_i       => CLK100MHZ,
    rstn_i      => CPU_RESETN,
    rstn_ocd_o  => open,
    rstn_wdt_o  => open,
    -- GPIO --
    gpio_dir_o  => open,
    gpio_o      => gpio_o,
    gpio_i      => (others => '0'),
    -- Primary UART0 --
    uart0_txd_o => UART_TXD,
    uart0_rxd_i => UART_RXD,
    uart0_rtsn_o => open,
    uart0_ctsn_i => '0',
    -- Unused JTAG --
    jtag_tck_i  => '0',
    jtag_tdi_i  => '0',
    jtag_tdo_o  => open,
    jtag_tms_i  => '0',
    -- Machine timer --
    mtime_time_o => open,
    -- Interrupts --
    irq_msi_i   => '0',
    irq_mti_i   => '0',
    irq_mei_i   => '0'
  );

  -- Map GPIO to LEDs (lower 16 bits) --
  LED <= std_ulogic_vector(gpio_o(15 downto 0));

end architecture;
