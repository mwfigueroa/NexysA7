-- ================================================================================ --
-- NEORV32 - Top-Level Wrapper for Digilent Nexys A7-100T (XC7A100T-1CSG324)        --
-- -------------------------------------------------------------------------------- --
-- Clock:        100 MHz onboard oscillator (E3)                                     --
-- UART0:        FTDI channel B → C4 (RXD) / D4 (TXD) at 115200 baud                --
-- GPIO[15:0]:   LEDs (active high)                                                 --
-- PWM[7:0]:     PMOD JA (8 canales, gated by SW[0] safety)                          --
-- SPI:          PMOD JB (SCK=E16, MOSI=F13, MISO=G14, CSN=H14)                      --
-- TWI (I2C):    PMOD JC (SCL=U11, SDA=U12)                                         --
-- GPTMR:        General purpose timer (4 slices, interno)                           --
-- WDT:          Watchdog timer (interno)                                            --
-- TRNG:         True random number generator (interno)                              --
-- Safety:       SW[0]=PWM ARM, SW[1]=IRQ input, reset synchronizer                  --
-- Memory:       IMEM 64 KB, DMEM 32 KB                                              --
-- Reset:        CPU_RESETN (C12, active low, pushbutton) debounced                  --
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
    -- Safety switches --
    SW         : in  std_ulogic_vector(1 downto 0);  -- SW[0]=PWM_ARM, SW[1]=IRQ
    -- UART0 (FTDI) --
    UART_RXD   : in  std_ulogic;
    UART_TXD   : out std_ulogic;
    -- GPIO / LEDs --
    LED        : out std_ulogic_vector(15 downto 0);
    -- PWM (PMOD JA) - safety gated --
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

  signal gpio_o     : std_ulogic_vector(31 downto 0);
  signal pwm_all    : std_ulogic_vector(31 downto 0);
  signal pwm_safe   : std_ulogic_vector(7 downto 0);

  -- TWI / I2C buffering --
  signal twi_sda_i, twi_sda_o : std_ulogic;
  signal twi_scl_i, twi_scl_o : std_ulogic;

  -- SPI chip select --
  signal spi_csn_vec : std_ulogic_vector(7 downto 0);

  -- Reset synchronizer (async assert, sync deassert, debounce) --
  signal rstn_sync   : std_ulogic_vector(3 downto 0) := (others => '0');
  signal rstn_safe   : std_ulogic;

  -- IRQ synchronizer for SW[1] --
  signal irq_sync    : std_ulogic_vector(1 downto 0) := (others => '0');

begin

  -- ---------------------------------------------------------------------------
  -- Reset Synchronizer (async assert, sync release, 4-stage debounce)
  -- ---------------------------------------------------------------------------
  reset_sync: process(CLK100MHZ, CPU_RESETN)
  begin
    if CPU_RESETN = '0' then
      rstn_sync <= (others => '0');
    elsif rising_edge(CLK100MHZ) then
      rstn_sync <= rstn_sync(2 downto 0) & '1';
    end if;
  end process;
  rstn_safe <= rstn_sync(3);  -- released after 4 stable high cycles

  -- ---------------------------------------------------------------------------
  -- IRQ Synchronizer (2-stage for SW[1])
  -- ---------------------------------------------------------------------------
  irq_sync_proc: process(CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      irq_sync <= irq_sync(0) & SW(1);
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  -- PWM Safety Gate: SW[0]=1 enables PWM outputs, else pull LOW (motors off)
  -- ---------------------------------------------------------------------------
  pwm_safe <= std_ulogic_vector(pwm_all(7 downto 0)) when SW(0) = '1' else (others => '0');

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
    IMEM_SIZE           => 64 * 1024,    -- 64 KB
    -- Internal Data Memory --
    DMEM_EN             => true,
    DMEM_SIZE           => 32 * 1024,    -- 32 KB
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
    -- Phase 1 Peripherals --
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
    rstn_i      => rstn_safe,
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
    irq_mei_i   => irq_sync(1)    -- SW[1] → machine external interrupt
  );

  -- Map GPIO to LEDs --
  LED <= std_ulogic_vector(gpio_o(15 downto 0));

  -- Map safety-gated PWM to PMOD JA --
  PWM <= pwm_safe;

  -- Map SPI CSN --
  SPI_CSN <= spi_csn_vec(0);

  -- TWI / I2C bidirectional buffering --
  TWI_SDA <= '0' when twi_sda_o = '0' else 'Z';
  twi_sda_i <= std_ulogic(TWI_SDA);
  TWI_SCL <= '0' when twi_scl_o = '0' else 'Z';
  twi_scl_i <= std_ulogic(TWI_SCL);

end architecture;
