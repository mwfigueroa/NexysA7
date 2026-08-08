-- ================================================================================ --
-- NEORV32 - Top-Level Wrapper for Digilent Nexys A7-100T (XC7A100T-1CSG324)        --
-- ROV Edition v5 — CFS-enabled, hardware PWM from mixer/PID                         --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_nexys_a7 is
  port (
    CLK100MHZ  : in  std_ulogic;
    CPU_RESETN : in  std_ulogic;
    SW         : in  std_ulogic_vector(1 downto 0);
    UART_RXD   : in  std_ulogic;
    UART_TXD   : out std_ulogic;
    LED        : out std_ulogic_vector(15 downto 0);
    PWM        : out std_ulogic_vector(7 downto 0);
    SPI_SCK    : out std_ulogic;
    SPI_MOSI   : out std_ulogic;
    SPI_MISO   : in  std_ulogic;
    SPI_CSN    : out std_ulogic;
    TWI_SCL    : inout std_logic;
    TWI_SDA    : inout std_logic;
    ENC_A      : in  std_ulogic_vector(7 downto 0);
    ENC_B      : in  std_ulogic_vector(7 downto 0);
    -- JTAG debug (OCD) — 7-seg cathode pins
    JTAG_TCK   : in  std_ulogic;  -- R10
    JTAG_TDI   : in  std_ulogic;  -- K16
    JTAG_TDO   : out std_ulogic;  -- K13
    JTAG_TMS   : in  std_ulogic   -- P15
  );
end entity;

architecture neorv32_nexys_a7_rtl of neorv32_nexys_a7 is

  signal gpio_o     : std_ulogic_vector(31 downto 0);
  signal twi_sda_i, twi_sda_o, twi_scl_i, twi_scl_o : std_ulogic;
  signal spi_csn_vec : std_ulogic_vector(7 downto 0);
  signal rstn_sync   : std_ulogic_vector(3 downto 0) := (others => '0');
  signal rstn_safe   : std_ulogic;
  -- IRQ + SW synchronizer (edge-detect on SW[1])
  signal irq_edge   : std_ulogic; -- rising edge pulse
  signal irq_sync_v : std_ulogic_vector(1 downto 0) := (others => '0');

  -- CFS bus (256-bit memory-mapped register interface)
  signal cfs_in      : std_ulogic_vector(255 downto 0);
  signal cfs_out     : std_ulogic_vector(255 downto 0);

  -- ROV Motor Subsystem
  signal motor_duty  : std_ulogic_vector(127 downto 0); -- 8 x 16-bit from mixer/PID
  signal pwm_arm_cfs : std_ulogic;
  signal pwm_sw_sync : std_ulogic_vector(1 downto 0) := (others => '0');

  -- Servo pulse generator: 1us tick, 20ms period, 1100-1900us pulse
  constant SERVO_PERIOD : unsigned(15 downto 0) := to_unsigned(20000, 16); -- 20ms in us
  signal servo_tick     : std_ulogic := '0';     -- 1us strobe
  signal servo_us_cnt   : unsigned(15 downto 0) := (others => '0'); -- microsecond counter
  signal servo_pulse    : unsigned(15 downto 0);  -- computed pulse width
  signal pwm_hw_out     : std_ulogic_vector(7 downto 0);

  -- ASYNC_REG attributes for synchronizer chains
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rstn_sync   : signal is "TRUE";
  attribute ASYNC_REG of irq_sync_v  : signal is "TRUE";
  attribute ASYNC_REG of pwm_sw_sync : signal is "TRUE";

begin

  -- Reset Synchronizer --
  process(CLK100MHZ, CPU_RESETN)
  begin
    if CPU_RESETN = '0' then rstn_sync <= (others => '0');
    elsif rising_edge(CLK100MHZ) then rstn_sync <= rstn_sync(2 downto 0) & '1'; end if;
  end process;
  rstn_safe <= rstn_sync(3);

  -- IRQ + SW synchronizer (edge-detect on SW[1])
  process(CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      irq_sync_v <= irq_sync_v(0) & SW(1);
      pwm_sw_sync <= pwm_sw_sync(0) & SW(0);
    end if;
  end process;
  -- Rising edge pulse: irq_sync_v[1]=1 and irq_sync_v[0]=0 means new edge
  irq_edge <= '1' when irq_sync_v(1) = '1' and irq_sync_v(0) = '0' else '0';

  -- -----------------------------------------------------------------------
  -- ROV Motor Subsystem (Safety + Encoders + Mixer + PID + Depth)
  -- -----------------------------------------------------------------------
  rov_motors_inst: entity work.neorv32_rov_motors
  port map (
    clk_i      => CLK100MHZ,
    rstn_i     => rstn_safe,
    cfs_in_i   => cfs_in,
    cfs_out_o  => cfs_out,
    enc_a_i    => ENC_A,
    enc_b_i    => ENC_B,
    motor_pwm_o => motor_duty,
    pwm_arm_o  => pwm_arm_cfs
  );

  -- -----------------------------------------------------------------------
  -- Servo Pulse Generator: 1us tick, 20ms period, 1100-1900us pulse
  -- motor_duty 0-65535 maps to pulse 1100-1900us (neutral=1500us @ 32768)
  -- Compatible with ESC (T200/Basic ESC et al.) and servo motors.
  -- -----------------------------------------------------------------------
  process(CLK100MHZ)
    variable us_div : natural range 0 to 99 := 0; -- 100MHz/100 = 1MHz
  begin
    if rising_edge(CLK100MHZ) then
      if rstn_safe = '0' then
        us_div := 0; servo_tick <= '0';
        servo_us_cnt <= (others => '0');
        pwm_hw_out <= (others => '0');
      else
        servo_tick <= '0';
        if us_div = 99 then
          us_div := 0;
          servo_tick <= '1';
        else
          us_div := us_div + 1;
        end if;

        if servo_tick = '1' then
          if servo_us_cnt = SERVO_PERIOD - 1 then
            servo_us_cnt <= (others => '0');
          else
            servo_us_cnt <= servo_us_cnt + 1;
          end if;
          -- Generate pulse per channel
          for ch in 0 to 7 loop
            -- pulse_us = 1100 + motor_duty * 800 / 65536
            servo_pulse <= to_unsigned(1100, 16)
              + resize(unsigned(motor_duty(ch*16+15 downto ch*16)) * 800 / 65536, 16);
            if servo_us_cnt < servo_pulse then
              pwm_hw_out(ch) <= '1';
            else
              pwm_hw_out(ch) <= '0';
            end if;
          end loop;
        end if;
      end if;
    end if;
  end process;

  -- PWM outputs: gated by CFS heartbeat AND SW[0] (both synchronized)
  PWM <= pwm_hw_out when (pwm_arm_cfs = '1' and pwm_sw_sync(1) = '1') else (others => '0');

  -- -----------------------------------------------------------------------
  -- NEORV32 Processor — CFS ENABLED
  -- -----------------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY     => 100_000_000,
    BOOT_MODE_SELECT    => 0,
    OCD_EN              => true,     -- JTAG debug enabled!
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
    -- CFS: ENABLED --
    IO_CFS_EN           => true,
    -- Peripherals --
    IO_GPIO_NUM         => 16,
    IO_CLINT_EN         => true,
    IO_UART0_EN         => true,
    IO_UART0_RX_FIFO    => 64,
    IO_UART0_TX_FIFO    => 64,
    IO_PWM_NUM          => 0,     -- PWM native disabled, usamos hardware PWM
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
    -- CFS: CONNECTED --
    cfs_in_i    => cfs_out,    -- ROV cfs_out → CPU cfs_in (CPU reads ROV data)
    cfs_out_o   => cfs_in,     -- CPU cfs_out → ROV cfs_in (CPU writes ROV commands)
    -- PWM native: disconnected --
    pwm_o       => open,
    -- SPI --
    spi_clk_o   => SPI_SCK,
    spi_dat_o   => SPI_MOSI,
    spi_dat_i   => SPI_MISO,
    spi_csn_o   => spi_csn_vec,
    -- TWI --
    twi_sda_i   => twi_sda_i,
    twi_sda_o   => twi_sda_o,
    twi_scl_i   => twi_scl_i,
    twi_scl_o   => twi_scl_o,
    -- JTAG --
    jtag_tck_i  => JTAG_TCK,
    jtag_tdi_i  => JTAG_TDI,
    jtag_tdo_o  => JTAG_TDO,
    jtag_tms_i  => JTAG_TMS,
    mtime_time_o => open,
    irq_msi_i   => '0',
    irq_mti_i   => '0',
    irq_mei_i   => irq_edge
  );

  LED <= std_ulogic_vector(gpio_o(15 downto 0));
  SPI_CSN <= spi_csn_vec(0);

  TWI_SDA <= '0' when twi_sda_o = '0' else 'Z';
  twi_sda_i <= std_ulogic(TWI_SDA);
  TWI_SCL <= '0' when twi_scl_o = '0' else 'Z';
  twi_scl_i <= std_ulogic(TWI_SCL);

end architecture;
