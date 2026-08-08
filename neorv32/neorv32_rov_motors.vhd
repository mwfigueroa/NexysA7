-- ================================================================================ --
-- NEORV32 ROV Motor Subsystem — Safety + Encoders + Mixer + IMU + PID + Depth       --
-- ================================================================================ --
-- Etapa 3: PID Controller 6-DOF (independent per axis) + Depth Sensor computation    --
--                                                                                  --
-- CFS Register Map (cfs_in_i):                                                      --
--   [7:0]   = cmd[3:0] + motor_sel[2:0] / axis[2:0]                               --
--     cmd=0x1: clear heartbeat                                                      --
--     cmd=0x2: arm motors                                                           --
--     cmd=0x3: disarm                                                               --
--     cmd=0x4: calibrate encoders                                                   --
--     cmd=0x5: write mixer coefficient (idx[5:0] in [13:8], val in [31:16])         --
--     cmd=0x6: write control setpoint (axis in [10:8], val in [31:16])              --
--     cmd=0x7: write IMU raw (axis in [10:8], val in [31:16])                       --
--     cmd=0x8: write PID gain (axis in [10:8], Kp/Ki/Kd in [13:12], val [31:16])   --
--     cmd=0x9: write PID current position (axis [10:8], val [31:16])                --
--     cmd=0xA: write depth raw pressure/temp (0=pressure, 1=temp in [10], val [31:16]) --
--     cmd=0xB: enable PID per axis (bitmask in [13:8])                              --
--   [15:8]  = heartbeat_timeout_ms                                                  --
--   [31:16] = value for cmd 5-9                                                     --
--                                                                                  --
-- CFS Register Map (cfs_out_o):                                                     --
--   [31:0]   = encoder position                                                     --
--   [63:32]  = encoder velocity                                                     --
--   [79:64]  = safety status + heartbeat                                            --
--   [95:80]  = IMU roll (s1.14)                                                     --
--   [111:96] = IMU pitch                                                            --
--   [127:112]= IMU yaw                                                              --
--   [143:128]= PID output axis 0 (Surge)                                            --
--   [159:144]= PID output axis 1 (Sway)                                             --
--   [... axis 2-5 in following 16-bit slots]                                        --
--   [239:224]= Depth (cm, unsigned)                                                 --
--   [255:240]= Depth temperature (C*10, signed)                                     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity neorv32_rov_motors is
  port (
    clk_i        : in  std_ulogic;
    rstn_i       : in  std_ulogic;
    cfs_in_i     : in  std_ulogic_vector(255 downto 0);
    cfs_out_o    : out std_ulogic_vector(255 downto 0);
    enc_a_i      : in  std_ulogic_vector(7 downto 0);
    enc_b_i      : in  std_ulogic_vector(7 downto 0);
    motor_pwm_o  : out std_ulogic_vector(127 downto 0);
    pwm_arm_o    : out std_ulogic
  );
end entity;

architecture rtl of neorv32_rov_motors is

  subtype sfix_t is signed(15 downto 0);
  constant SFIX_ONE  : sfix_t := to_signed(16384, 16);
  constant SFIX_ZERO : sfix_t := (others => '0');

  -- Control + Mixer
  type control_array_t is array (0 to 5) of sfix_t;
  signal control_sp : control_array_t := (others => SFIX_ZERO);
  type coeff_array_t is array (0 to 47) of sfix_t;
  signal mixer_coeff : coeff_array_t := (others => SFIX_ZERO);
  type motor_array_t is array (0 to 7) of unsigned(15 downto 0);
  signal motor_out : motor_array_t := (others => to_unsigned(32768, 16));

  -- IMU
  type imu_raw_t is array (0 to 5) of sfix_t;
  signal imu_raw   : imu_raw_t := (others => SFIX_ZERO);
  signal imu_roll, imu_pitch, imu_yaw : sfix_t := SFIX_ZERO;

  -- PID: 6 axes, each with Kp/Ki/Kd
  type pid_gains_t is array (0 to 5) of sfix_t;
  signal pid_kp, pid_ki, pid_kd : pid_gains_t := (others => SFIX_ZERO);
  signal pid_current : control_array_t := (others => SFIX_ZERO);
  signal pid_error_prev : control_array_t := (others => SFIX_ZERO);
  signal pid_integral   : control_array_t := (others => SFIX_ZERO);
  signal pid_output     : control_array_t := (others => SFIX_ZERO);
  signal pid_enable     : std_ulogic_vector(5 downto 0) := (others => '0');
  signal pid_tick       : std_ulogic := '0';  -- PID update strobe @ ~400 Hz

  constant PID_DIV      : natural := 249999; -- 100MHz / 250000 = 400 Hz
  signal pid_div_cnt    : natural range 0 to PID_DIV;

  -- Anti-windup limits
  constant I_MAX : sfix_t := to_signed(16384, 16);  -- ±1.0
  constant I_MIN : sfix_t := to_signed(-16384, 16);

  -- Depth sensor
  signal depth_raw_pressure : unsigned(31 downto 0) := to_unsigned(101300, 32); -- 1013.00 mbar * 100
  signal depth_raw_temp     : signed(15 downto 0) := to_signed(200, 16);       -- 20.0 C * 10
  signal depth_cm           : unsigned(15 downto 0) := (others => '0');

  -- Encoders
  type enc_array_t is array (0 to 7) of unsigned(31 downto 0);
  signal enc_pos, enc_vel, enc_prev : enc_array_t := (others => (others => '0'));
  signal enc_sync, enc_last : std_ulogic_vector(15 downto 0);
  constant VEL_WINDOW : natural := 3200000 - 1;
  signal vel_counter : natural range 0 to VEL_WINDOW;

  -- Safety
  signal heartbeat_cnt, hb_timeout : unsigned(7 downto 0) := (others => '0');
  signal heartbeat_alive, motors_armed : std_ulogic := '0';
  signal hb_timer : unsigned(16 downto 0) := (others => '0');

  -- Command decode
  signal motor_sel, axis_sel : unsigned(2 downto 0);
  signal cmd     : std_ulogic_vector(3 downto 0);
  signal coeff_idx : unsigned(5 downto 0);
  signal gain_sel   : unsigned(1 downto 0);
  signal u16_val    : unsigned(15 downto 0);
  signal s16_val    : sfix_t;

  -- Mixer FSM
  signal mixer_active : std_ulogic := '0';
  type mix_state_t is (IDLE, MULTIPLY, ACCUMULATE, DONE);
  signal mix_state : mix_state_t := IDLE;
  signal mix_motor : integer range 0 to 7;
  signal mix_axis  : integer range 0 to 5;
  signal mix_acc   : signed(31 downto 0);

begin

  -- Decode
  motor_sel <= unsigned(cfs_in_i(2 downto 0));
  axis_sel  <= unsigned(cfs_in_i(10 downto 8));
  cmd       <= cfs_in_i(7 downto 4);
  coeff_idx <= unsigned(cfs_in_i(13 downto 8));
  gain_sel  <= unsigned(cfs_in_i(13 downto 12));
  u16_val   <= unsigned(cfs_in_i(31 downto 16));
  s16_val   <= signed(cfs_in_i(31 downto 16));
  hb_timeout <= unsigned(cfs_in_i(15 downto 8));

  -- =====================================================================
  -- PID Update Strobe (400 Hz)
  -- =====================================================================
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        pid_div_cnt <= 0;
        pid_tick <= '0';
      else
        if pid_div_cnt = PID_DIV then
          pid_div_cnt <= 0;
          pid_tick <= '1';
        else
          pid_div_cnt <= pid_div_cnt + 1;
          pid_tick <= '0';
        end if;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- PID Controller (6 axes, sequential pipeline @ 400 Hz)
  -- =====================================================================
  pid_proc: process(clk_i)
    variable error   : sfix_t;
    variable p_term  : sfix_t;
    variable i_term  : sfix_t;
    variable d_term  : sfix_t;
    variable pid_sum : signed(31 downto 0);
    variable axis    : integer range 0 to 5;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        pid_kp <= (others => SFIX_ZERO);
        pid_ki <= (others => SFIX_ZERO);
        pid_kd <= (others => SFIX_ZERO);
        pid_current <= (others => SFIX_ZERO);
        pid_error_prev <= (others => SFIX_ZERO);
        pid_integral <= (others => SFIX_ZERO);
        pid_output <= (others => SFIX_ZERO);
        pid_enable <= (others => '0');
      end if;
    end if;
  end process;

  -- PID round-robin axis counter
  process(clk_i)
    variable axis_cnt : integer range 0 to 5 := 0;
    variable error, p_term, i_term, d_term : sfix_t;
    variable pid_sum : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        axis_cnt := 0;
        pid_error_prev <= (others => SFIX_ZERO);
        pid_integral <= (others => SFIX_ZERO);
        pid_output <= (others => SFIX_ZERO);
      elsif pid_tick = '1' then
        if pid_enable(axis_cnt) = '1' then
          -- Error calculation
          error := control_sp(axis_cnt) - pid_current(axis_cnt);
          
          -- Proportional: Kp * error
          p_term := resize(shift_right(pid_kp(axis_cnt) * error, 14), 16);
          
          -- Integral: Ki * error + I_prev, with anti-windup
          i_term := resize(shift_right(pid_ki(axis_cnt) * error, 14), 16);
          pid_integral(axis_cnt) <= pid_integral(axis_cnt) + i_term;
          -- Anti-windup clamp
          if pid_integral(axis_cnt) > I_MAX then
            pid_integral(axis_cnt) <= I_MAX;
          elsif pid_integral(axis_cnt) < I_MIN then
            pid_integral(axis_cnt) <= I_MIN;
          end if;
          
          -- Derivative: Kd * (error - error_prev)
          d_term := resize(shift_right(pid_kd(axis_cnt) * (error - pid_error_prev(axis_cnt)), 14), 16);
          pid_error_prev(axis_cnt) <= error;
          
          -- Sum: P + I + D, clamp to s1.14 range
          pid_sum := resize(p_term, 32) + resize(pid_integral(axis_cnt), 32) + resize(d_term, 32);
          if pid_sum > 16383 then
            pid_output(axis_cnt) <= to_signed(16383, 16);
          elsif pid_sum < -16384 then
            pid_output(axis_cnt) <= to_signed(-16384, 16);
          else
            pid_output(axis_cnt) <= resize(pid_sum, 16);
          end if;
        else
          pid_output(axis_cnt) <= control_sp(axis_cnt); -- pass-through
        end if;
        
        -- Next axis
        if axis_cnt = 5 then axis_cnt := 0; else axis_cnt := axis_cnt + 1; end if;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Encoders (8ch, 4x decoding)
  -- =====================================================================
  encoder_gen: for ch in 0 to 7 generate
  begin
    process(clk_i)
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

  -- Velocity
  process(clk_i)
    variable delta : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        vel_counter <= 0; enc_prev <= (others => (others => '0')); enc_vel <= (others => (others => '0'));
      else
        if vel_counter = VEL_WINDOW then
          vel_counter <= 0;
          for ch in 0 to 7 loop
            delta := signed(enc_pos(ch)) - signed(enc_prev(ch));
            enc_vel(ch) <= unsigned(delta); enc_prev(ch) <= enc_pos(ch);
          end loop;
        else vel_counter <= vel_counter + 1; end if;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Command Processor
  -- =====================================================================
  process(clk_i)
    variable coeff_addr : integer range 0 to 47;
    variable i : integer range 0 to 5;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        control_sp <= (others => SFIX_ZERO);
        pid_kp <= (others => SFIX_ZERO); pid_ki <= (others => SFIX_ZERO); pid_kd <= (others => SFIX_ZERO);
        pid_enable <= (others => '0');
        mixer_active <= '0';
        heartbeat_alive <= '0'; motors_armed <= '0';
        depth_raw_pressure <= to_unsigned(101300, 32);
        depth_raw_temp <= to_signed(200, 16);
        -- Default mixer OCTO coefficients
        for m in 0 to 7 loop mixer_coeff(m*6+2) <= SFIX_ONE; end loop; -- Heave all+
        mixer_coeff(0*6) <= SFIX_ONE;  mixer_coeff(0*6+5) <= SFIX_ONE;
        mixer_coeff(1*6+1) <= SFIX_ONE; mixer_coeff(1*6+5) <= -SFIX_ONE;
        mixer_coeff(2*6) <= -SFIX_ONE; mixer_coeff(2*6+5) <= SFIX_ONE;
        mixer_coeff(3*6+1) <= -SFIX_ONE; mixer_coeff(3*6+5) <= -SFIX_ONE;
        mixer_coeff(4*6) <= SFIX_ONE;  mixer_coeff(4*6+5) <= -SFIX_ONE;
        mixer_coeff(5*6+1) <= SFIX_ONE; mixer_coeff(5*6+5) <= SFIX_ONE;
        mixer_coeff(6*6) <= -SFIX_ONE; mixer_coeff(6*6+5) <= -SFIX_ONE;
        mixer_coeff(7*6+1) <= -SFIX_ONE; mixer_coeff(7*6+5) <= SFIX_ONE;
        mixer_coeff(1*6+3) <= SFIX_ONE; mixer_coeff(5*6+3) <= SFIX_ONE;
        mixer_coeff(3*6+3) <= -SFIX_ONE; mixer_coeff(7*6+3) <= -SFIX_ONE;
        mixer_coeff(0*6+4) <= SFIX_ONE; mixer_coeff(4*6+4) <= SFIX_ONE;
        mixer_coeff(2*6+4) <= -SFIX_ONE; mixer_coeff(6*6+4) <= -SFIX_ONE;
      else
        case cmd is
          when x"1" => heartbeat_alive <= '1';
          when x"2" => if heartbeat_alive = '1' then motors_armed <= '1'; end if;
          when x"3" => motors_armed <= '0';
          when x"5" => coeff_addr := to_integer(coeff_idx); if coeff_addr < 48 then mixer_coeff(coeff_addr) <= s16_val; end if;
          when x"6" => i := to_integer(axis_sel); if i < 6 then control_sp(i) <= s16_val; mixer_active <= '1'; end if;
          when x"7" => i := to_integer(axis_sel); if i < 6 then imu_raw(i) <= s16_val; end if;
          when x"8" => -- PID gain
            i := to_integer(axis_sel);
            if i < 6 then
              case gain_sel is
                when "00" => pid_kp(i) <= s16_val;
                when "01" => pid_ki(i) <= s16_val;
                when "10" => pid_kd(i) <= s16_val;
                when others => null;
              end case;
            end if;
          when x"9" => i := to_integer(axis_sel); if i < 6 then pid_current(i) <= s16_val; end if;
          when x"A" =>
            if cfs_in_i(10) = '0' then depth_raw_pressure <= resize(unsigned(cfs_in_i(31 downto 0)), 32);
            else depth_raw_temp <= signed(cfs_in_i(31 downto 16)); end if;
          when x"B" => pid_enable <= cfs_in_i(13 downto 8);
          when others => null;
        end case;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Mixer
  -- =====================================================================
  process(clk_i)
    variable product  : signed(31 downto 0);
    variable coeff_base : integer range 0 to 47;
    variable bias_val : unsigned(15 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        mix_state <= IDLE; mix_motor <= 0; mix_axis <= 0; mix_acc <= (others => '0');
        motor_out <= (others => to_unsigned(32768, 16));
      else
        case mix_state is
          when IDLE =>
            if mixer_active = '1' then
              mix_state <= MULTIPLY; mix_motor <= 0; mix_axis <= 0; mix_acc <= (others => '0');
            end if;
          when MULTIPLY =>
            coeff_base := mix_motor * 6;
            -- Use PID output if enabled, else manual control
            if pid_enable(mix_axis) = '1' then
              product := resize(signed(mixer_coeff(coeff_base + mix_axis)) * pid_output(mix_axis), 32);
            else
              product := resize(signed(mixer_coeff(coeff_base + mix_axis)) * control_sp(mix_axis), 32);
            end if;
            mix_acc <= mix_acc + resize(product(29 downto 14), 32);
            if mix_axis = 5 then mix_state <= ACCUMULATE; else mix_axis <= mix_axis + 1; end if;
          when ACCUMULATE =>
            bias_val := to_unsigned(32768, 16);
            if mix_acc(15) = '0' then motor_out(mix_motor) <= bias_val + unsigned(mix_acc(15 downto 0));
            else motor_out(mix_motor) <= bias_val - unsigned((not mix_acc(15 downto 0)) + 1); end if;
            if mix_motor = 7 then mix_state <= DONE;
            else mix_motor <= mix_motor + 1; mix_axis <= 0; mix_acc <= (others => '0'); mix_state <= MULTIPLY; end if;
          when DONE => mix_state <= IDLE; mixer_active <= '0';
          when others => mix_state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- IMU Filter
  -- =====================================================================
  process(clk_i)
    constant ALPHA : sfix_t := to_signed(16056, 16);
    constant BETA  : sfix_t := to_signed(328, 16);
    variable roll_acc, pitch_acc : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then imu_roll <= SFIX_ZERO; imu_pitch <= SFIX_ZERO; imu_yaw <= SFIX_ZERO;
      else
        roll_acc := resize(imu_raw(1) * SFIX_ONE, 32);
        pitch_acc := resize(imu_raw(0) * (-SFIX_ONE), 32);
        imu_roll  <= resize(resize(signed(ALPHA) * (imu_roll + imu_raw(3)), 32)(29 downto 14) + resize(signed(BETA) * signed(roll_acc(31 downto 16)), 32)(29 downto 14), 16);
        imu_pitch <= resize(resize(signed(ALPHA) * (imu_pitch + imu_raw(4)), 32)(29 downto 14) + resize(signed(BETA) * signed(pitch_acc(31 downto 16)), 32)(29 downto 14), 16);
        imu_yaw   <= imu_yaw + imu_raw(5);
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Depth Computation: cm = (P_mbar - 1013) * 100 / 98  (freshwater)
  -- =====================================================================
  process(clk_i)
    variable press_diff : signed(31 downto 0);
    variable depth_raw  : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      -- depth_cm = (P_mbar - 1013) * 102 / 100
      -- with P stored as mbar*100: depth_cm = (raw - 101300) * 102 / 10000
      press_diff := resize(signed(depth_raw_pressure) - to_signed(101300, 32), 32);
      depth_raw  := resize(press_diff * 102 / 10000, 32);
      if depth_raw < 0 then depth_cm <= (others => '0');
      else depth_cm <= unsigned(depth_raw(15 downto 0)); end if;
    end if;
  end process;

  -- =====================================================================
  -- Safety
  -- =====================================================================
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        heartbeat_cnt <= (others => '0'); heartbeat_alive <= '0'; motors_armed <= '0'; hb_timer <= (others => '0');
      else
        if hb_timer = 999 then hb_timer <= (others => '0'); else hb_timer <= hb_timer + 1; end if;
        if hb_timer = 999 and hb_timeout > 0 then
          heartbeat_cnt <= heartbeat_cnt + 1;
          if heartbeat_cnt >= hb_timeout then heartbeat_alive <= '0'; motors_armed <= '0'; mixer_active <= '0'; end if;
        end if;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Outputs
  -- =====================================================================
  pwm_arm_o <= motors_armed and heartbeat_alive;

  cfs_out_o <= (others => '0');
  cfs_out_o(31 downto 0)   <= std_ulogic_vector(enc_pos(to_integer(motor_sel)));
  cfs_out_o(63 downto 32)  <= std_ulogic_vector(enc_vel(to_integer(motor_sel)));
  cfs_out_o(71) <= motors_armed; cfs_out_o(70) <= heartbeat_alive; cfs_out_o(69) <= not motors_armed;
  cfs_out_o(79 downto 72) <= std_ulogic_vector(heartbeat_cnt);
  cfs_out_o(95 downto 80) <= std_ulogic_vector(imu_roll);
  cfs_out_o(111 downto 96) <= std_ulogic_vector(imu_pitch);
  cfs_out_o(127 downto 112) <= std_ulogic_vector(imu_yaw);
  -- PID outputs
  cfs_out_o(143 downto 128) <= std_ulogic_vector(pid_output(0));
  cfs_out_o(159 downto 144) <= std_ulogic_vector(pid_output(1));
  cfs_out_o(175 downto 160) <= std_ulogic_vector(pid_output(2));
  cfs_out_o(191 downto 176) <= std_ulogic_vector(pid_output(3));
  cfs_out_o(207 downto 192) <= std_ulogic_vector(pid_output(4));
  cfs_out_o(223 downto 208) <= std_ulogic_vector(pid_output(5));
  -- Depth
  cfs_out_o(239 downto 224) <= std_ulogic_vector(depth_cm);
  cfs_out_o(255 downto 240) <= std_ulogic_vector(depth_raw_temp);

  motor_map: for ch in 0 to 7 generate
    motor_pwm_o(ch*16+15 downto ch*16) <= std_ulogic_vector(motor_out(ch));
  end generate;

end architecture;
