-- ================================================================================ --
-- NEORV32 - Top-Level Wrapper for Digilent Nexys A7-100T (XC7A100T-1CSG324)        --
-- -------------------------------------------------------------------------------- --
-- Clock:        100 MHz onboard oscillator (E3)                                     --
-- UART0:        FTDI channel B → C4 (RXD) / D4 (TXD) at 115200 baud                --
-- GPIO[15:0]:   LEDs (active high)                                                 --
-- PWM[7:0]:     PMOD JA (8 canales, servos/LED dimming/audio)                       --
-- SPI:          PMOD JB (SCK=E16, MOSI=F13, MISO=G14, CSN=H13)                      --
-- TWI (I2C):    PMOD JC (SCL=U11, SDA=U12)                                         --
-- GPTMR:        General purpose timer (4 slices, interno)                           --
-- WDT:          Watchdog timer (interno)                                            --
-- TRNG:         True random number generator (interno)                              --
-- Reset:        CPU_RESETN (C12, active low, pushbutton)                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_nexys_a7 is
  port (
    -- Global control --
    CLK100MHZ  : in  std_ulogic;
    CPU_RESETN : in  std_ulogic;
    -- UART0 (FTDI) --
    UART_RXD   : in  std_ulogic;
    UART_TXD   : out std_ulogic;
    -- GPIO / LEDs --
    LED        : out std_ulogic_vector(15 downto 0);
    -- PWM (PMOD JA) --
    PWM        : out std_ulogic_vector(7 downto 0);
    -- SPI host (PMOD JB) --
    SPI_SCK    : out std_ulogic;
    SPI_MOSI   : out std_ulogic;
    SPI_MISO   : in  std_ulogic;
    SPI_CSN    : out std_ulogic;
    -- TWI / I2C (PMOD JC) - bidirectional --
    TWI_SCL    : inout std_logic;
    TWI_SDA    : inout std_logic
  );
end entity;

architecture neorv32_nexys_a7_rtl of neorv32_nexys_a7 is

  signal gpio_o  : std_ulogic_vector(31 downto 0);
  signal pwm_all : std_ulogic_vector(31 downto 0);

  -- TWI / I2C buffering (NEORV32 uses separate in/out lines) --
  signal twi_sda_i, twi_sda_o : std_ulogic;
  signal twi_scl_i, twi_scl_o : std_ulogic;

  -- SPI chip select (NEORV32 uses 8-bit vector, we use bit 0) --
  signal spi_csn_vec : std_ulogic_vector(7 downto 0);

begin

  -- NEORV32 Processor --------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    -- General --
    CLOCK_FREQUENCY     => 100_000_000,
    -- Boot Configuration --
    BOOT_MODE_SELECT    => 0,
    -- On-Chip Debugger --
    OCD_EN              => false,
    -- RISC-V CPU Extensions --
    RISCV_ISA_C         => true,
    RISCV_ISA_M         => true,
    RISCV_ISA_Zicntr    => true,
    -- Tuning Options --
    CPU_FAST_MUL_EN     => true,
    CPU_FAST_SHIFT_EN   => true,
    CPU_RF_ARCH_SEL     => 1,
    -- Physical Memory Protection --
    PMP_NUM_REGIONS     => 0,
    -- Internal Instruction Memory --
    IMEM_EN             => true,
    IMEM_SIZE           => 32 * 1024,
    -- Internal Data Memory --
    DMEM_EN             => true,
    DMEM_SIZE           => 8 * 1024,
    -- Caches --
    ICACHE_EN           => false,
    DCACHE_EN           => false,
    -- External Bus Interface --
    XBUS_EN             => false,
    -- Processor Peripherals --
    IO_GPIO_NUM         => 16,
    IO_CLINT_EN         => true,
    IO_UART0_EN         => true,
    IO_UART0_RX_FIFO    => 64,
    IO_UART0_TX_FIFO    => 64,
    -- Phase 1: New Peripherals --
    IO_PWM_NUM          => 8,
    IO_SPI_EN           => true,
    IO_TWI_EN           => true,
    IO_GPTMR_NUM        => 4,
    IO_WDT_EN           => true,
    IO_TRNG_EN          => true
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
    -- PWM --
    pwm_o       => pwm_all,
    -- SPI host --
    spi_clk_o   => SPI_SCK,
    spi_dat_o   => SPI_MOSI,
    spi_dat_i   => SPI_MISO,
    spi_csn_o   => spi_csn_vec,
    -- TWI / I2C --
    twi_sda_i   => twi_sda_i,
    twi_sda_o   => twi_sda_o,
    twi_scl_i   => twi_scl_i,
    twi_scl_o   => twi_scl_o,
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

  -- Map PWM to PMOD JA --
  PWM <= std_ulogic_vector(pwm_all(7 downto 0));

  -- Map SPI CSN (only bit 0 used) --
  SPI_CSN <= spi_csn_vec(0);

  -- TWI / I2C bidirectional buffering --
  TWI_SDA <= '0' when twi_sda_o = '0' else 'Z';
  twi_sda_i <= std_ulogic(TWI_SDA);
  TWI_SCL <= '0' when twi_scl_o = '0' else 'Z';
  twi_scl_i <= std_ulogic(TWI_SCL);

end architecture;
