-- ================================================================================ --
-- NEORV32 - Top-Level Wrapper for Digilent Nexys A7-100T (XC7A100T-1CSG324)        --
-- ROV Edition v3 — Etapa 1: Encoders + Safety Manager                              --
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
    SW         : in  std_ulogic_vector(1 downto 0);
    -- UART0 --
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
    -- TWI / I2C (PMOD JC top 2) --
    TWI_SCL    : inout std_logic;
    TWI_SDA    : inout std_logic;
    -- Quadrature Encoders (PMOD JD + JC + buttons) --
    ENC_A      : in  std_ulogic_vector(7 downto 0);
    ENC_B      : in  std_ulogic_vector(7 downto 0)
  );
end entity;

architecture neorv32_nexys_a7_rtl of neorv32_nexys_a7 is

  signal gpio_o     : std_ulogic_vector(31 downto 0);
  signal pwm_all    : std_ulogic_vector(31 downto 0);
  signal pwm_raw    : std_ulogic_vector(7 downto 0);

  -- TWI / I2C --
  signal twi_sda_i, twi_sda_o, twi_scl_i, twi_scl_o : std_ulogic;

  -- SPI --
  signal spi_csn_vec : std_ulogic_vector(7 downto 0);

  -- Reset synchronizer --
  signal rstn_sync   : std_ulogic_vector(3 downto 0) := (others => '0');
  signal rstn_safe   : std_ulogic;
  signal irq_sync    : std_ulogic_vector(1 downto 0) := (others => '0');

  -- ROV Motor Subsystem signals --
  signal cfs_motors_in  : std_ulogic_vector(255 downto 0);
  signal cfs_motors_out : std_ulogic_vector(255 downto 0);
  signal pwm_arm_cfs    : std_ulogic;  -- CFS heartbeat-based arm
  signal pwm_sw_arm     : std_ulogic;  -- SW[0] manual safety

begin

  -- Reset Synchronizer --
  reset_sync: process(CLK100MHZ, CPU_RESETN)
  begin
    if CPU_RESETN = '0' then
      rstn_sync <= (others => '0');
    elsif rising_edge(CLK100MHZ) then
      rstn_sync <= rstn_sync(2 downto 0) & '1';
    end if;
  end process;
  rstn_safe <= rstn_sync(3);

  -- IRQ Synchronizer --
  irq_proc: process(CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      irq_sync <= irq_sync(0) & SW(1);
    end if;
  end process;

  -- PWM Safety Gate: both CFS heartbeat AND SW[0] must be high --
  pwm_sw_arm <= SW(0);
  pwm_raw <= std_ulogic_vector(pwm_all(7 downto 0));
  PWM <= pwm_raw when (pwm_arm_cfs = '1' and pwm_sw_arm = '1') else (others => '0');

  -- -----------------------------------------------------------------------
  -- ROV Motor Subsystem: PWM Safety Manager + Quadrature Encoders
  -- -----------------------------------------------------------------------
  rov_motors_inst: entity work.neorv32_rov_motors
  port map (
    clk_i      => CLK100MHZ,
    rstn_i     => rstn_safe,
    cfs_in_i   => cfs_motors_in,
    cfs_out_o  => cfs_motors_out,
    enc_a_i    => ENC_A,
    enc_b_i    => ENC_B,
    pwm_arm_o  => pwm_arm_cfs
  );

  -- NEORV32 Processor --------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY     => 100_000_000,
    BOOT_MODE_SELECT    => 0,
    OCD_EN              => false,
    RISCV_ISA_C         => true,
    RISCV_ISA_M         => true,
    RISCV_ISA_Zicntr    => true,
    CPU_FAST_MUL_EN     => true,
    CPU_FAST_SHIFT_EN   => true,
    CPU_RF_ARCH_SEL     => 1,
    PMP_NUM_REGIONS     => 0,
    IMEM_EN             => true,
    IMEM_SIZE           => 64 * 1024,
    DMEM_EN             => true,
    DMEM_SIZE           => 32 * 1024,
    ICACHE_EN           => false,
    DCACHE_EN           => false,
    XBUS_EN             => false,
    IO_GPIO_NUM         => 16,
    IO_CLINT_EN         => true,
    IO_UART0_EN         => true,
    IO_UART0_RX_FIFO    => 64,
    IO_UART0_TX_FIFO    => 64,
    IO_PWM_NUM          => 8,
    IO_SPI_EN           => true,
    IO_TWI_EN           => true,
    IO_GPTMR_NUM        => 4,
    IO_WDT_EN           => true,
    IO_TRNG_EN          => true
  )
  port map (
    clk_i       => CLK100MHZ,
    rstn_i      => rstn_safe,
    rstn_ocd_o  => open,
    rstn_wdt_o  => open,
    gpio_dir_o  => open,
    gpio_o      => gpio_o,
    gpio_i      => (others => '0'),
    uart0_txd_o => UART_TXD,
    uart0_rxd_i => UART_RXD,
    uart0_rtsn_o => open,
    uart0_ctsn_i => '0',
    pwm_o       => pwm_all,
    spi_clk_o   => SPI_SCK,
    spi_dat_o   => SPI_MOSI,
    spi_dat_i   => SPI_MISO,
    spi_csn_o   => spi_csn_vec,
    twi_sda_i   => twi_sda_i,
    twi_sda_o   => twi_sda_o,
    twi_scl_i   => twi_scl_i,
    twi_scl_o   => twi_scl_o,
    jtag_tck_i  => '0',
    jtag_tdi_i  => '0',
    jtag_tdo_o  => open,
    jtag_tms_i  => '0',
    mtime_time_o => open,
    irq_msi_i   => '0',
    irq_mti_i   => '0',
    irq_mei_i   => irq_sync(1)
  );

  -- Map GPIO to LEDs --
  LED <= std_ulogic_vector(gpio_o(15 downto 0));
  SPI_CSN <= spi_csn_vec(0);

  -- TWI / I2C bidirectional buffering --
  TWI_SDA <= '0' when twi_sda_o = '0' else 'Z';
  twi_sda_i <= std_ulogic(TWI_SDA);
  TWI_SCL <= '0' when twi_scl_o = '0' else 'Z';
  twi_scl_i <= std_ulogic(TWI_SCL);

end architecture;
