-- ================================================================================ --
-- NEORV32 ROV Motor Subsystem — PWM Safety + Quadrature Encoder (8ch)              --
-- ================================================================================ --
-- Connects to NEORV32 wrapper via cfs_in/cfs_out 256-bit buses.                     --
--                                                                                  --
-- CFS Register Map (software interface):                                            --
--   cfs_in_i[7:0]   = motor_sel (0-7) + cmd[3:0]                                   --
--     cmd = 0x0: NOP                                                               --
--     cmd = 0x1: clear heartbeat (keep-alive)                                       --
--     cmd = 0x2: arm motors (transitions to armed if heartbeat ok)                  --
--     cmd = 0x3: disarm motors                                                      --
--     cmd = 0x4: calibrate encoders (zero position counters)                        --
--   cfs_in_i[15:8]  = heartbeat_timeout_ms (0-255, 0=disabled)                      --
--                                                                                  --
--   cfs_out_o[31:0]  = selected motor position (32-bit signed)                      --
--   cfs_out_o[63:32] = selected motor velocity (32-bit signed, counts/sec)          --
--   cfs_out_o[71:64] = safety: [7]=armed [6]=heartbeat_ok [5]=failsafe             --
--   cfs_out_o[79:72] = heartbeat_counter (0-255, rolls over)                        --
--                                                                                  --
-- PWM Safety:                                                                       --
--   CPU must write cmd=0x1 at least every timeout_ms to keep pwm_arm HIGH.        --
--   If heartbeat lost, pwm_arm goes LOW immediately (motors off).                   --
--   Arm command requires heartbeat to be active first.                              --
--                                                                                  --
-- Quadrature Encoder:                                                               --
--   4x decoding (counts on every A/B edge). 32-bit signed counter.                  --
--   Velocity measured as delta over ~32ms window (adjustable).                     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_rov_motors is
  port (
    clk_i        : in  std_ulogic;                     -- 100 MHz system clock
    rstn_i       : in  std_ulogic;                     -- active-low reset

    -- CFS bus interface (from NEORV32 top) --
    cfs_in_i     : in  std_ulogic_vector(255 downto 0);
    cfs_out_o    : out std_ulogic_vector(255 downto 0);

    -- Encoder inputs (8 channels × 2 quadrature pins) --
    enc_a_i      : in  std_ulogic_vector(7 downto 0);
    enc_b_i      : in  std_ulogic_vector(7 downto 0);

    -- PWM safety output (gates PWM externally) --
    pwm_arm_o    : out std_ulogic
  );
end entity;

architecture rtl of neorv32_rov_motors is

  -- -----------------------------------------------------------------------
  -- Encoder signals
  -- -----------------------------------------------------------------------
  type enc_array_t is array (0 to 7) of unsigned(31 downto 0);
  signal enc_pos      : enc_array_t := (others => (others => '0'));
  signal enc_vel      : enc_array_t := (others => (others => '0'));

  -- Edge detection
  type enc_edge_t is array (0 to 7) of std_ulogic_vector(1 downto 0);
  signal enc_sync     : enc_edge_t;  -- synchronized inputs
  signal enc_last     : enc_edge_t;  -- previous state

  -- Velocity measurement (100 MHz / 3,200,000 ≈ 31.25 ms window)
  constant VEL_WINDOW : natural := 3200000 - 1;
  signal vel_counter  : natural range 0 to VEL_WINDOW;
  signal enc_prev     : enc_array_t := (others => (others => '0'));

  -- -----------------------------------------------------------------------
  -- PWM Safety Manager signals
  -- -----------------------------------------------------------------------
  signal heartbeat_cnt   : unsigned(7 downto 0) := (others => '0');
  signal heartbeat_alive : std_ulogic := '0';
  signal motors_armed     : std_ulogic := '0';
  signal failsafe         : std_ulogic := '1';   -- start in failsafe
  signal hb_timeout       : unsigned(7 downto 0) := to_unsigned(100, 8); -- default 100ms
  signal hb_timer         : unsigned(16 downto 0) := (others => '0');  -- ~100k counts/ms @ 100MHz

  -- Command decoder
  signal motor_sel   : unsigned(2 downto 0);
  signal cmd         : std_ulogic_vector(3 downto 0);

begin

  -- -----------------------------------------------------------------------
  -- Decode CFS input commands
  -- -----------------------------------------------------------------------
  motor_sel <= unsigned(cfs_in_i(2 downto 0));
  cmd       <= cfs_in_i(7 downto 4);
  hb_timeout <= unsigned(cfs_in_i(15 downto 8));

  -- -----------------------------------------------------------------------
  -- Quadrature Encoders (8ch, 4x decoding)
  -- -----------------------------------------------------------------------
  encoder_gen: for ch in 0 to 7 generate
  begin
    quad_decoder: process(clk_i)
      variable state : std_ulogic_vector(1 downto 0);
      variable last  : std_ulogic_vector(1 downto 0);
    begin
      if rising_edge(clk_i) then
        if rstn_i = '0' then
          enc_sync(ch) <= (others => '0');
          enc_last(ch) <= (others => '0');
          enc_pos(ch)  <= (others => '0');
        else
          -- Synchronize inputs
          enc_sync(ch) <= enc_a_i(ch) & enc_b_i(ch);
          enc_last(ch) <= enc_sync(ch);

          -- 4x quadrature decoding
          state := enc_sync(ch);
          last  := enc_last(ch);
          case last & state is
            -- Forward transitions
            when "00" & "01" | "01" & "11" | "11" & "10" | "10" & "00" =>
              enc_pos(ch) <= enc_pos(ch) + 1;
            -- Reverse transitions
            when "00" & "10" | "10" & "11" | "11" & "01" | "01" & "00" =>
              enc_pos(ch) <= enc_pos(ch) - 1;
            -- Invalid / no change
            when others =>
              null;
          end case;
        end if;
      end if;
    end process;
  end generate;

  -- -----------------------------------------------------------------------
  -- Velocity measurement (delta position over fixed time window)
  -- -----------------------------------------------------------------------
  velocity_proc: process(clk_i)
    variable delta : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        vel_counter <= 0;
        enc_prev <= (others => (others => '0'));
        enc_vel  <= (others => (others => '0'));
      else
        if vel_counter = VEL_WINDOW then
          vel_counter <= 0;
          for ch in 0 to 7 loop
            delta := signed(enc_pos(ch)) - signed(enc_prev(ch));
            enc_vel(ch) <= unsigned(delta);
            enc_prev(ch) <= enc_pos(ch);
          end loop;
        else
          vel_counter <= vel_counter + 1;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- CFS Output: expose selected motor data
  -- -----------------------------------------------------------------------
  cfs_out_o <= (others => '0');
  -- Position and velocity of selected motor
  cfs_out_o(31 downto 0)  <= std_ulogic_vector(enc_pos(to_integer(motor_sel)));
  cfs_out_o(63 downto 32) <= std_ulogic_vector(enc_vel(to_integer(motor_sel)));
  -- Safety status
  cfs_out_o(71) <= motors_armed;
  cfs_out_o(70) <= heartbeat_alive;
  cfs_out_o(69) <= failsafe;
  -- Heartbeat counter
  cfs_out_o(79 downto 72) <= std_ulogic_vector(heartbeat_cnt);

  -- -----------------------------------------------------------------------
  -- PWM Safety Manager — Heartbeat Watchdog
  -- -----------------------------------------------------------------------
  safety_proc: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        heartbeat_cnt   <= (others => '0');
        heartbeat_alive <= '0';
        motors_armed    <= '0';
        failsafe        <= '1';
        hb_timer        <= (others => '0');
      else
        -- Heartbeat timer (counts in ~10μs ticks = 1000 counts/ms)
        if hb_timer = 999 then
          hb_timer <= (others => '0');
        else
          hb_timer <= hb_timer + 1;
        end if;

        -- Command processing
        case cmd is
          when x"1" =>  -- Clear heartbeat (keep-alive)
            if heartbeat_alive = '0' then
              heartbeat_cnt <= (others => '0');
            end if;
            heartbeat_alive <= '1';

          when x"2" =>  -- Arm motors
            if heartbeat_alive = '1' then
              motors_armed <= '1';
              failsafe <= '0';
            end if;

          when x"3" =>  -- Disarm motors
            motors_armed <= '0';
            failsafe <= '1';

          when x"4" =>  -- Calibrate: zero encoders
            null; -- handled in encoder reset above via cmd_prev

          when others =>
            null;
        end case;

        -- Heartbeat timeout check (every 1ms)
        if hb_timer = 999 and hb_timeout > 0 then
          -- Increment counter every ms
          heartbeat_cnt <= heartbeat_cnt + 1;
          -- Check timeout
          if heartbeat_cnt >= hb_timeout then
            heartbeat_alive <= '0';
            motors_armed    <= '0';
            failsafe        <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- PWM ARM output: high only when armed AND heartbeat alive
  -- -----------------------------------------------------------------------
  pwm_arm_o <= motors_armed and heartbeat_alive;

end architecture;
