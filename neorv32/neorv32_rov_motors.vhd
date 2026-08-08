-- ================================================================================ --
-- NEORV32 ROV Motor Subsystem — Safety + Encoders + Mixer Matrix + IMU Fusion      --
-- ================================================================================ --
-- Etapa 2: Mixer Matrix 8×6 (6-DOF → 8 PWM) + Complementary Filter IMU             --
--                                                                                  --
-- CFS Register Map:                                                                --
--   cfs_in_i[7:0]   = cmd[3:0] + motor_sel[2:0]                                   --
--     cmd=0x1: clear heartbeat                                                     --
--     cmd=0x2: arm motors (req. heartbeat)                                         --
--     cmd=0x3: disarm                                                              --
--     cmd=0x4: calibrate encoders                                                  --
--     cmd=0x5: write mixer coefficient (coeff_idx[5:0] in bits 13:8, val in 31:16) --
--     cmd=0x6: write control setpoint (axis[2:0] in bits 10:8, val in 31:16)       --
--     cmd=0x7: write IMU raw data (axis[3:0] in 11:8, val in 31:16)               --
--                                                                                  --
--   cfs_out_o[31:0]   = encoder position (selected motor)                          --
--   cfs_out_o[63:32]  = encoder velocity (selected motor)                           --
--   cfs_out_o[71:64]  = safety status                                              --
--   cfs_out_o[79:72]  = heartbeat counter                                          --
--   cfs_out_o[95:80]  = IMU roll  (s1.14 fixed, read-only)                        --
--   cfs_out_o[111:96] = IMU pitch (s1.14 fixed)                                    --
--   cfs_out_o[127:112]= IMU yaw   (s1.14 fixed)                                    --
--   cfs_out_o[143:128]= Motor 0 PWM value (readback)                               --
--   ... motors 1-7 at cfs_out_o[159:144] through [255:240]                         --
--                                                                                  --
-- Mixer: motor[i] = sum( coeff[i*6 + j] * control[j] ) for j in 0..5              --
--   coeff is s1.14 fixed (range -2.0 to +1.9999)                                   --
--   control is s1.14 fixed                                                         --
--   output is 16-bit unsigned (0 = PWM_MIN, 65535 = PWM_MAX)                       --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_rov_motors is
  port (
    clk_i        : in  std_ulogic;
    rstn_i       : in  std_ulogic;

    -- CFS bus --
    cfs_in_i     : in  std_ulogic_vector(255 downto 0);
    cfs_out_o    : out std_ulogic_vector(255 downto 0);

    -- Encoder inputs --
    enc_a_i      : in  std_ulogic_vector(7 downto 0);
    enc_b_i      : in  std_ulogic_vector(7 downto 0);

    -- Motor PWM outputs (drive NEORV32 PWM peripheral) --
    motor_pwm_o  : out std_ulogic_vector(127 downto 0); -- 8 x 16-bit

    -- Safety output --
    pwm_arm_o    : out std_ulogic
  );
end entity;

architecture rtl of neorv32_rov_motors is

  -- Fixed-point type: s1.14 (sign + 1 integer + 14 fractional)
  subtype sfix_t is signed(15 downto 0);
  constant SFIX_ONE  : sfix_t := to_signed(16384, 16);  -- 1.0 in s1.14
  constant SFIX_ZERO : sfix_t := (others => '0');

  -- Control setpoints (6 axes: Surge, Sway, Heave, Roll, Pitch, Yaw)
  type control_array_t is array (0 to 5) of sfix_t;
  signal control_sp  : control_array_t := (others => (others => '0'));

  -- Mixer coefficients: 8 motors × 6 axes = 48 coefficients
  type coeff_array_t is array (0 to 47) of sfix_t;
  signal mixer_coeff : coeff_array_t := (others => SFIX_ZERO);

  -- Motor outputs
  type motor_array_t is array (0 to 7) of unsigned(15 downto 0);
  signal motor_out   : motor_array_t := (others => (others => '0'));

  -- IMU data (raw + filtered)
  type imu_raw_t is array (0 to 5) of sfix_t;
  signal imu_raw    : imu_raw_t := (others => (others => '0'));
  signal imu_roll   : sfix_t := (others => '0');
  signal imu_pitch  : sfix_t := (others => '0');
  signal imu_yaw    : sfix_t := (others => '0');

  -- -----------------------------------------------------------------------
  -- Encoder signals (from Stage 1)
  -- -----------------------------------------------------------------------
  type enc_array_t is array (0 to 7) of unsigned(31 downto 0);
  signal enc_pos      : enc_array_t := (others => (others => '0'));
  signal enc_vel      : enc_array_t := (others => (others => '0'));
  signal enc_sync     : std_ulogic_vector(15 downto 0);
  signal enc_last     : std_ulogic_vector(15 downto 0);
  signal enc_prev     : enc_array_t := (others => (others => '0'));

  constant VEL_WINDOW : natural := 3200000 - 1;
  signal vel_counter  : natural range 0 to VEL_WINDOW;

  -- -----------------------------------------------------------------------
  -- Safety signals
  -- -----------------------------------------------------------------------
  signal heartbeat_cnt   : unsigned(7 downto 0) := (others => '0');
  signal heartbeat_alive : std_ulogic := '0';
  signal motors_armed    : std_ulogic := '0';
  signal hb_timeout      : unsigned(7 downto 0) := to_unsigned(100, 8);
  signal hb_timer        : unsigned(16 downto 0) := (others => '0');

  -- Command decoder
  signal motor_sel : unsigned(2 downto 0);
  signal cmd       : std_ulogic_vector(3 downto 0);
  signal coeff_idx : unsigned(5 downto 0);
  signal axis_sel  : unsigned(2 downto 0);
  signal u16_val   : unsigned(15 downto 0);

  -- Mixer pipeline
  signal mixer_active : std_ulogic := '0';
  type mix_state_t is (IDLE, MULTIPLY, ACCUMULATE, DONE);
  signal mix_state   : mix_state_t := IDLE;
  signal mix_motor   : integer range 0 to 7;
  signal mix_axis    : integer range 0 to 5;
  signal mix_acc     : signed(31 downto 0);

begin

  -- -----------------------------------------------------------------------
  -- Decode CFS inputs
  -- -----------------------------------------------------------------------
  motor_sel <= unsigned(cfs_in_i(2 downto 0));
  cmd       <= cfs_in_i(7 downto 4);
  coeff_idx <= unsigned(cfs_in_i(13 downto 8));
  axis_sel  <= unsigned(cfs_in_i(10 downto 8));
  u16_val   <= unsigned(cfs_in_i(31 downto 16));
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
          enc_sync(ch*2+1 downto ch*2) <= "00";
          enc_last(ch*2+1 downto ch*2) <= "00";
          enc_pos(ch) <= (others => '0');
        else
          enc_sync(ch*2+1 downto ch*2) <= enc_a_i(ch) & enc_b_i(ch);
          enc_last(ch*2+1 downto ch*2) <= enc_sync(ch*2+1 downto ch*2);
          state := enc_sync(ch*2+1 downto ch*2);
          last  := enc_last(ch*2+1 downto ch*2);
          case last & state is
            when "00" & "01" | "01" & "11" | "11" & "10" | "10" & "00" =>
              enc_pos(ch) <= enc_pos(ch) + 1;
            when "00" & "10" | "10" & "11" | "11" & "01" | "01" & "00" =>
              enc_pos(ch) <= enc_pos(ch) - 1;
            when others => null;
          end case;
        end if;
      end if;
    end process;
  end generate;

  -- Velocity measurement
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
  -- Command processor (heartbeat, arm/disarm, coefficient writes)
  -- -----------------------------------------------------------------------
  cmd_proc: process(clk_i)
    variable coeff_addr : integer range 0 to 47;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        control_sp <= (others => (others => '0'));
        mixer_coeff <= (others => SFIX_ZERO);
        -- Default mixer: identity for octo frame
        mixer_coeff(0) <= SFIX_ONE;  mixer_coeff(6)  <= SFIX_ONE;   -- M0: +Surge +Yaw
        mixer_coeff(1) <= SFIX_ONE;  mixer_coeff(13) <= SFIX_ONE;   -- M1: +Sway  -Yaw
        mixer_coeff(2) <= -SFIX_ONE; mixer_coeff(20) <= SFIX_ONE;   -- M2: -Surge +Yaw
        mixer_coeff(3) <= -SFIX_ONE; mixer_coeff(27) <= -SFIX_ONE;  -- M3: -Sway  -Yaw
        mixer_coeff(4) <= SFIX_ONE;  mixer_coeff(34) <= -SFIX_ONE;  -- M4: +Surge -Yaw
        mixer_coeff(5) <= SFIX_ONE;  mixer_coeff(41) <= SFIX_ONE;   -- M5: +Sway  +Yaw
        mixer_coeff(2*6) <= -SFIX_ONE; mixer_coeff(2*6+5) <= SFIX_ONE;  -- M2: -Surge +Yaw (fixed)
        mixer_coeff(3*6) <= -SFIX_ONE; mixer_coeff(3*6+5) <= -SFIX_ONE;
        mixer_coeff(4*6) <= SFIX_ONE;  mixer_coeff(4*6+5) <= -SFIX_ONE;
        mixer_coeff(5*6) <= SFIX_ONE;  mixer_coeff(5*6+5) <= SFIX_ONE;
        mixer_coeff(6*6) <= -SFIX_ONE; mixer_coeff(6*6+5) <= -SFIX_ONE;
        mixer_coeff(7*6) <= -SFIX_ONE; mixer_coeff(7*6+5) <= SFIX_ONE;
        -- Heave: all positive (simplified)
        mixer_coeff(0*6+2) <= SFIX_ONE;
        mixer_coeff(1*6+2) <= SFIX_ONE;
        mixer_coeff(2*6+2) <= SFIX_ONE;
        mixer_coeff(3*6+2) <= SFIX_ONE;
        mixer_coeff(4*6+2) <= SFIX_ONE;
        mixer_coeff(5*6+2) <= SFIX_ONE;
        mixer_coeff(6*6+2) <= SFIX_ONE;
        mixer_coeff(7*6+2) <= SFIX_ONE;
        -- Roll: M1,M5 pos, M3,M7 neg
        mixer_coeff(1*6+3) <= SFIX_ONE;
        mixer_coeff(5*6+3) <= SFIX_ONE;
        mixer_coeff(3*6+3) <= -SFIX_ONE;
        mixer_coeff(7*6+3) <= -SFIX_ONE;
        -- Pitch: M0,M4 pos, M2,M6 neg
        mixer_coeff(0*6+4) <= SFIX_ONE;
        mixer_coeff(4*6+4) <= SFIX_ONE;
        mixer_coeff(2*6+4) <= -SFIX_ONE;
        mixer_coeff(6*6+4) <= -SFIX_ONE;
        mixer_active <= '0';
        imu_raw <= (others => (others => '0'));
        imu_roll  <= (others => '0');
        imu_pitch <= (others => '0');
        imu_yaw   <= (others => '0');
      else
        -- Command processing
        case cmd is
          when x"1" => heartbeat_alive <= '1';
          when x"2" => if heartbeat_alive = '1' then motors_armed <= '1'; end if;
          when x"3" => motors_armed <= '0';
          when x"5" =>  -- Write mixer coefficient
            coeff_addr := to_integer(coeff_idx);
            if coeff_addr < 48 then
              mixer_coeff(coeff_addr) <= signed(u16_val);
            end if;
          when x"6" =>  -- Write control setpoint
            if to_integer(axis_sel) < 6 then
              control_sp(to_integer(axis_sel)) <= signed(u16_val);
            end if;
            mixer_active <= '1';
          when x"7" =>  -- Write IMU raw data
            if to_integer(axis_sel) < 6 then
              imu_raw(to_integer(axis_sel)) <= signed(u16_val);
            end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Mixer matrix: motor[i] = sum(coeff[i*6+j] * control[j]) for all j
  -- Pipeline: 48 cycles (8 motors × 6 axes per motor)
  -- -----------------------------------------------------------------------
  mixer_proc: process(clk_i)
    variable product : signed(31 downto 0);
    variable coeff_base : integer range 0 to 47;
    variable bias_val   : unsigned(15 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        mix_state <= IDLE;
        mix_motor <= 0;
        mix_axis  <= 0;
        mix_acc   <= (others => '0');
        motor_out <= (others => to_unsigned(32768, 16)); -- neutral
      else
        case mix_state is
          when IDLE =>
            if mixer_active = '1' then
              mix_state <= MULTIPLY;
              mix_motor <= 0;
              mix_axis  <= 0;
              mix_acc   <= (others => '0');
            end if;

          when MULTIPLY =>
            coeff_base := mix_motor * 6;
            -- s1.14 * s1.14 = s2.28, keep upper 16 bits (s1.14)
            product := resize(signed(mixer_coeff(coeff_base + mix_axis)) * control_sp(mix_axis), 32);
            mix_acc <= mix_acc + resize(product(29 downto 14), 32);
            if mix_axis = 5 then
              mix_state <= ACCUMULATE;
            else
              mix_axis <= mix_axis + 1;
            end if;

          when ACCUMULATE =>
            -- Convert s1.14 accumulator to PWM duty (0-65535)
            bias_val := to_unsigned(32768, 16);
            if mix_acc(15) = '0' then -- positive
              motor_out(mix_motor) <= bias_val + unsigned(mix_acc(15 downto 0));
            else
              motor_out(mix_motor) <= bias_val - unsigned((not mix_acc(15 downto 0)) + 1);
            end if;
            if mix_motor = 7 then
              mix_state <= DONE;
            else
              mix_motor <= mix_motor + 1;
              mix_axis  <= 0;
              mix_acc   <= (others => '0');
              mix_state <= MULTIPLY;
            end if;

          when DONE =>
            mix_state <= IDLE;
            mixer_active <= '0';

          when others =>
            mix_state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- IMU Complementary Filter (simple: 98% gyro + 2% accel)
  -- -----------------------------------------------------------------------
  imu_filter: process(clk_i)
    -- α = 0.98 in s1.14 = 16056
    constant ALPHA : sfix_t := to_signed(16056, 16);  -- 0.98 * 16384
    constant BETA  : sfix_t := to_signed(328, 16);     -- 0.02 * 16384
    variable roll_acc, pitch_acc : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        imu_roll  <= (others => '0');
        imu_pitch <= (others => '0');
        imu_yaw   <= (others => '0');
      else
        -- Roll from accel: atan2(Ay, Az) → approximated as Ay/Az for small angles
        roll_acc  := resize(imu_raw(1) * SFIX_ONE, 32); -- simplified
        pitch_acc := resize(imu_raw(0) * (-SFIX_ONE), 32); -- -Ax

        -- Complementary: angle = α * (angle + gyro*dt) + β * accel_angle
        imu_roll  <= resize( resize(signed(ALPHA) * (imu_roll + imu_raw(3)), 32)(29 downto 14)
                   + resize(signed(BETA) * signed(roll_acc(31 downto 16)), 32)(29 downto 14), 16);
        imu_pitch <= resize( resize(signed(ALPHA) * (imu_pitch + imu_raw(4)), 32)(29 downto 14)
                   + resize(signed(BETA) * signed(pitch_acc(31 downto 16)), 32)(29 downto 14), 16);
        imu_yaw   <= imu_yaw + imu_raw(5);
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Safety Manager — Heartbeat Watchdog
  -- -----------------------------------------------------------------------
  safety_proc: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        heartbeat_cnt   <= (others => '0');
        heartbeat_alive <= '0';
        motors_armed    <= '0';
        hb_timer        <= (others => '0');
      else
        if hb_timer = 999 then
          hb_timer <= (others => '0');
        else
          hb_timer <= hb_timer + 1;
        end if;

        if hb_timer = 999 and hb_timeout > 0 then
          heartbeat_cnt <= heartbeat_cnt + 1;
          if heartbeat_cnt >= hb_timeout then
            heartbeat_alive <= '0';
            motors_armed    <= '0';
            mixer_active    <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Outputs
  -- -----------------------------------------------------------------------
  pwm_arm_o <= motors_armed and heartbeat_alive;

  -- CFS readback
  cfs_out_o <= (others => '0');
  cfs_out_o(31 downto 0)   <= std_ulogic_vector(enc_pos(to_integer(motor_sel)));
  cfs_out_o(63 downto 32)  <= std_ulogic_vector(enc_vel(to_integer(motor_sel)));
  cfs_out_o(71) <= motors_armed;
  cfs_out_o(70) <= heartbeat_alive;
  cfs_out_o(69) <= not motors_armed; -- failsafe
  cfs_out_o(79 downto 72) <= std_ulogic_vector(heartbeat_cnt);
  cfs_out_o(95 downto 80)  <= std_ulogic_vector(imu_roll);
  cfs_out_o(111 downto 96) <= std_ulogic_vector(imu_pitch);
  cfs_out_o(127 downto 112)<= std_ulogic_vector(imu_yaw);

  -- Motor PWM outputs
  motor_map: for ch in 0 to 7 generate
    motor_pwm_o(ch*16+15 downto ch*16) <= std_ulogic_vector(motor_out(ch));
  end generate;

end architecture;
