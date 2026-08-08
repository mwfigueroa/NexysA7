-- ================================================================================ --
-- NEORV32 ROV Motor Subsystem v5 — Safety + Encoders + Mixer + PID + Depth         --
-- ================================================================================ --
-- FIXES: single-driver processes, heartbeat 1ms, cmd edge-detect, encoder sync,     --
--        PID all 6 axes per tick, IMU/depth on sample strobe, SW debounce path      --
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
  constant SFIX_ZERO : sfix_t := (others => '0');
  constant SFIX_ONE  : sfix_t := to_signed(16384, 16);

  -- =====================================================================
  -- SINGLE PROCESS signals — no multi-driver
  -- =====================================================================

  -- Status register (sole writer: status_proc)
  signal motors_armed    : std_ulogic := '0';
  signal heartbeat_alive : std_ulogic := '0';
  signal heartbeat_cnt   : unsigned(7 downto 0) := (others => '0');

  -- Mixer
  type motor_array_t is array (0 to 7) of unsigned(15 downto 0);
  signal motor_out : motor_array_t := (others => to_unsigned(32768, 16));
  signal motor_out_slewed : motor_array_t := (others => to_unsigned(32768, 16));
  signal mixer_trig : std_ulogic := '0'; -- strobe to run mixer

  -- CFS command edge detection
  signal cfs_in_d : std_ulogic_vector(255 downto 0) := (others => '0');
  signal cmd_strobe : std_ulogic := '0';
  signal cmd        : std_ulogic_vector(3 downto 0);
  signal motor_sel  : unsigned(2 downto 0);
  signal axis_sel   : unsigned(2 downto 0);
  signal u16_val    : unsigned(15 downto 0);
  signal s16_val    : sfix_t;
  signal coeff_idx  : unsigned(5 downto 0);
  signal gain_sel   : unsigned(1 downto 0);

  -- Control + Mixer coefficients
  type ctrl_array_t is array (0 to 5) of sfix_t;
  signal control_sp : ctrl_array_t := (others => SFIX_ZERO);
  type coeff_array_t is array (0 to 47) of sfix_t;
  signal mixer_coeff : coeff_array_t := (others => SFIX_ZERO);

  -- PID
  type pid_gains_t is array (0 to 5) of sfix_t;
  signal pid_kp, pid_ki, pid_kd   : pid_gains_t := (others => SFIX_ZERO);
  signal pid_current   : ctrl_array_t := (others => SFIX_ZERO);
  signal pid_output    : ctrl_array_t := (others => SFIX_ZERO);
  signal pid_enable    : std_ulogic_vector(5 downto 0) := (others => '0');
  signal pid_error_prev : ctrl_array_t := (others => SFIX_ZERO);
  signal pid_integral   : ctrl_array_t := (others => SFIX_ZERO);

  -- Timers
  signal pid_tick    : std_ulogic := '0';  -- strobe @ 400 Hz
  signal hb_ms_tick  : std_ulogic := '0';  -- strobe @ 1 kHz
  signal enc_clear   : std_ulogic := '0';  -- strobe to zero encoders
  signal hb_toggle_last : std_ulogic := '0'; -- toggle bit for heartbeat re-trigger

  -- Encoders (with sync chain)
  type enc_array_t is array (0 to 7) of unsigned(31 downto 0);
  type enc_vel_array_t is array (0 to 7) of signed(31 downto 0);
  signal enc_pos, enc_prev : enc_array_t := (others => (others => '0'));
  signal enc_vel : enc_vel_array_t := (others => (others => '0'));
  signal enc_sync1, enc_sync2 : std_ulogic_vector(15 downto 0) := (others => '0');
  signal enc_last : std_ulogic_vector(15 downto 0) := (others => '0');

  -- ASYNC_REG attributes for encoder sync chains
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of enc_sync1 : signal is "TRUE";
  attribute ASYNC_REG of enc_sync2 : signal is "TRUE";

  -- IMU
  type imu_raw_t is array (0 to 5) of sfix_t;
  signal imu_raw   : imu_raw_t := (others => SFIX_ZERO);
  signal imu_roll, imu_pitch, imu_yaw : sfix_t := SFIX_ZERO;
  signal imu_update : std_ulogic := '0'; -- strobe on new IMU data

  -- Depth
  signal depth_raw_pressure : unsigned(31 downto 0) := to_unsigned(101300, 32);
  signal depth_raw_temp     : signed(15 downto 0) := to_signed(200, 16);
  signal depth_cm           : unsigned(15 downto 0) := (others => '0');
  signal depth_update       : std_ulogic := '0';

  -- Constants
  constant PID_DIV : natural := 249999; -- 400 Hz @ 100 MHz
  constant HB_DIV  : natural := 99999;  -- 1 kHz @ 100 MHz

begin

  -- =====================================================================
  -- CFS Command Edge Detection (SINGLE process drives cmd_strobe)
  -- =====================================================================
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        cfs_in_d <= (others => '0');
        cmd_strobe <= '0';
      else
        cfs_in_d <= cfs_in_i;
        -- Strobe on rising edge of cmd field (bits [7:4])
        if cfs_in_i(7 downto 4) /= cfs_in_d(7 downto 4) and cfs_in_i(7 downto 4) /= "0000" then
          cmd_strobe <= '1';
        else
          cmd_strobe <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Decode (combinational from cfs_in_i)
  cmd        <= cfs_in_i(7 downto 4);
  motor_sel  <= unsigned(cfs_in_i(2 downto 0));
  axis_sel   <= unsigned(cfs_in_i(10 downto 8));
  coeff_idx  <= unsigned(cfs_in_i(13 downto 8));
  gain_sel   <= unsigned(cfs_in_i(13 downto 12));
  u16_val    <= unsigned(cfs_in_i(31 downto 16));
  s16_val    <= signed(cfs_in_i(31 downto 16));

  -- =====================================================================
  -- Tick generators (1 kHz heartbeat, 400 Hz PID)
  -- =====================================================================
  process(clk_i)
    variable cnt_hb : natural range 0 to HB_DIV := 0;
    variable cnt_pid : natural range 0 to PID_DIV := 0;
  begin
    if rising_edge(clk_i) then
      hb_ms_tick <= '0'; pid_tick <= '0';
      if cnt_hb = HB_DIV then cnt_hb := 0; hb_ms_tick <= '1'; else cnt_hb := cnt_hb + 1; end if;
      if cnt_pid = PID_DIV then cnt_pid := 0; pid_tick <= '1'; else cnt_pid := cnt_pid + 1; end if;
    end if;
  end process;

  -- =====================================================================
  -- Encoder inputs — 2-stage sync (ASYNC_REG compatible)
  -- =====================================================================
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      enc_sync1 <= enc_a_i & enc_b_i;
      enc_sync2 <= enc_sync1;
      enc_last  <= enc_sync2;
      -- 4x quadrature decode (A[ch]=enc_last(8+ch), B[ch]=enc_last(ch))
      for ch in 0 to 7 loop
        if    enc_sync2(8+ch) = '1' and enc_sync2(ch) = '1' and enc_last(8+ch) = '0' and enc_last(ch) = '1' then
          enc_pos(ch) <= enc_pos(ch) + 1;
        elsif enc_sync2(8+ch) = '0' and enc_sync2(ch) = '1' and enc_last(8+ch) = '0' and enc_last(ch) = '0' then
          enc_pos(ch) <= enc_pos(ch) + 1;
        elsif enc_sync2(8+ch) = '0' and enc_sync2(ch) = '0' and enc_last(8+ch) = '1' and enc_last(ch) = '0' then
          enc_pos(ch) <= enc_pos(ch) + 1;
        elsif enc_sync2(8+ch) = '1' and enc_sync2(ch) = '0' and enc_last(8+ch) = '1' and enc_last(ch) = '1' then
          enc_pos(ch) <= enc_pos(ch) + 1;
        elsif enc_sync2(8+ch) = '0' and enc_sync2(ch) = '0' and enc_last(8+ch) = '0' and enc_last(ch) = '1' then
          enc_pos(ch) <= enc_pos(ch) - 1;
        elsif enc_sync2(8+ch) = '1' and enc_sync2(ch) = '0' and enc_last(8+ch) = '0' and enc_last(ch) = '0' then
          enc_pos(ch) <= enc_pos(ch) - 1;
        elsif enc_sync2(8+ch) = '1' and enc_sync2(ch) = '1' and enc_last(8+ch) = '1' and enc_last(ch) = '0' then
          enc_pos(ch) <= enc_pos(ch) - 1;
        elsif enc_sync2(8+ch) = '0' and enc_sync2(ch) = '1' and enc_last(8+ch) = '1' and enc_last(ch) = '1' then
          enc_pos(ch) <= enc_pos(ch) - 1;
        end if;
      end loop;
      -- Calibration: zero all encoders on strobe
      if enc_clear = '1' then
        for ch in 0 to 7 loop
          enc_pos(ch) <= (others => '0');
        end loop;
      end if;
    end if;
  end process;

  -- Encoder velocity
  process(clk_i)
    variable delta : signed(31 downto 0);
    variable cnt : natural range 0 to 3199999 := 0;
  begin
    if rising_edge(clk_i) then
      if cnt = 3199999 then cnt := 0;
        for ch in 0 to 7 loop
          delta := signed(enc_pos(ch)) - signed(enc_prev(ch));
          enc_vel(ch) <= delta; enc_prev(ch) <= enc_pos(ch);
        end loop;
      else cnt := cnt + 1; end if;
    end if;
  end process;

  -- =====================================================================
  -- SINGLE Status Processor: commands, mixer, safety, calibration
  -- =====================================================================
  process(clk_i)
    variable hb_timer    : natural range 0 to 999 := 0; -- ms counter
    variable hb_timeout  : natural range 0 to 255 := 100;
    variable coeff_addr  : integer range 0 to 47;
    variable i           : integer range 0 to 5;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        motors_armed <= '0'; heartbeat_alive <= '0'; heartbeat_cnt <= (others => '0');
        control_sp <= (others => SFIX_ZERO);
        mixer_coeff <= (others => SFIX_ZERO);
        -- Default OCTO coefficients
        for m in 0 to 7 loop mixer_coeff(m*6+2) <= SFIX_ONE; end loop;
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
        mixer_trig <= '0';
        pid_kp <= (others => SFIX_ZERO); pid_ki <= (others => SFIX_ZERO); pid_kd <= (others => SFIX_ZERO);
        pid_enable <= (others => '0');
        imu_update <= '0'; depth_update <= '0';
        hb_timer := 0; hb_timeout := 100;
      else
        -- Default strobe resets (single-pulse)
        mixer_trig <= '0';
        enc_clear  <= '0';
        imu_update <= '0';
        depth_update <= '0';

        -- Heartbeat timer (1ms tick)
        if hb_ms_tick = '1' then
          hb_timer := hb_timer + 1;
          if hb_timer >= 999 then hb_timer := 0; end if;
          -- Heartbeat timeout check
          heartbeat_cnt <= heartbeat_cnt + 1;
          if heartbeat_cnt >= hb_timeout then
            heartbeat_alive <= '0'; motors_armed <= '0';
          end if;
        end if;

        -- CFS Command processor (edge-triggered for most, toggle for heartbeat)
        if cmd_strobe = '1' or (cmd = x"1" and cfs_in_i(8) /= hb_toggle_last) then
          case cmd is
            when x"1" => -- clear heartbeat (toggle bit on cfs_in[8])
              if cfs_in_i(8) /= hb_toggle_last then
                heartbeat_cnt <= (others => '0');
                heartbeat_alive <= '1';
                hb_toggle_last <= cfs_in_i(8);
              end if;

            when x"2" => -- arm
              if heartbeat_alive = '1' then motors_armed <= '1'; end if;

            when x"3" => -- disarm
              motors_armed <= '0';

            when x"4" => -- calibrate encoders (strobe, cleared in encoder process)
              enc_clear <= '1';

            when x"5" => -- write mixer coefficient
              coeff_addr := to_integer(coeff_idx);
              if coeff_addr < 48 then mixer_coeff(coeff_addr) <= s16_val; end if;

            when x"6" => -- write control setpoint
              i := to_integer(axis_sel);
              if i < 6 then control_sp(i) <= s16_val; mixer_trig <= '1'; end if;

            when x"7" => -- write IMU raw data
              i := to_integer(axis_sel);
              if i < 6 then imu_raw(i) <= s16_val; imu_update <= '1'; end if;

            when x"8" => -- write PID gain
              i := to_integer(axis_sel);
              if i < 6 then
                case gain_sel is
                  when "00" => pid_kp(i) <= s16_val;
                  when "01" => pid_ki(i) <= s16_val;
                  when "10" => pid_kd(i) <= s16_val;
                  when others => null;
                end case;
              end if;

            when x"9" => -- write PID current position
              i := to_integer(axis_sel);
              if i < 6 then pid_current(i) <= s16_val; end if;

            when x"A" => -- write depth raw data (pressure in 63:32, temp in 79:64)
              if cfs_in_i(10) = '0' then depth_raw_pressure <= unsigned(cfs_in_i(63 downto 32));
              else depth_raw_temp <= signed(cfs_in_i(79 downto 64)); end if;
              depth_update <= '1';

            when x"B" => -- PID enable mask
              pid_enable <= cfs_in_i(13 downto 8);

            when x"C" => -- write heartbeat timeout (bits 63:56)
              hb_timeout := to_integer(unsigned(cfs_in_i(63 downto 56)));
              if hb_timeout = 0 then hb_timeout := 100; end if;

            when others => null;
          end case;
        end if;

        -- Auto-trigger mixer when PID is running (hardware control loop)
        if pid_tick = '1' and pid_enable /= "000000" then
          mixer_trig <= '1';
        end if;

      end if;
    end if;
  end process;

  -- =====================================================================
  -- PID Controller: all 6 axes updated on pid_tick strobe
  -- =====================================================================
  process(clk_i)
    constant I_MAX : sfix_t := to_signed(16384, 16);
    constant I_MIN : sfix_t := to_signed(-16384, 16);
    variable error, p_term, i_term, d_term : sfix_t;
    variable pid_sum : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        pid_error_prev <= (others => SFIX_ZERO);
        pid_integral <= (others => SFIX_ZERO);
        pid_output <= (others => SFIX_ZERO);
      elsif pid_tick = '1' then
        for ax in 0 to 5 loop
          if pid_enable(ax) = '1' then
            error := control_sp(ax) - pid_current(ax);
            p_term := resize(shift_right(pid_kp(ax) * error, 14), 16);
            i_term := resize(shift_right(pid_ki(ax) * error, 14), 16);
            pid_integral(ax) <= pid_integral(ax) + i_term;
            if pid_integral(ax) > I_MAX then pid_integral(ax) <= I_MAX;
            elsif pid_integral(ax) < I_MIN then pid_integral(ax) <= I_MIN; end if;
            d_term := resize(shift_right(pid_kd(ax) * (error - pid_error_prev(ax)), 14), 16);
            pid_error_prev(ax) <= error;
            pid_sum := resize(p_term, 32) + resize(pid_integral(ax), 32) + resize(d_term, 32);
            if pid_sum > 16383 then pid_output(ax) <= to_signed(16383, 16);
            elsif pid_sum < -16384 then pid_output(ax) <= to_signed(-16384, 16);
            else pid_output(ax) <= resize(pid_sum, 16); end if;
          end if;
        end loop;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Mixer: runs on mixer_trig strobe (pipelined)
  -- =====================================================================
  process(clk_i)
    type mix_fsm_t is (IDLE, MAC0, MAC1, MAC2, MAC3, MAC4, MAC5, DONE);
    variable fsm : mix_fsm_t := IDLE;
    variable m : integer range 0 to 7 := 0;
    variable acc : signed(31 downto 0) := (others => '0');
    variable prod : signed(31 downto 0);
    variable bias : unsigned(15 downto 0);
    -- Mixer input: use PID output when enabled, else manual setpoint
    impure function mix_val(ax : integer) return sfix_t is
    begin
      if pid_enable(ax) = '1' then return pid_output(ax);
      else return control_sp(ax); end if;
    end function;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        fsm := IDLE; motor_out <= (others => to_unsigned(32768, 16));
      else
        case fsm is
          when IDLE =>
            if mixer_trig = '1' then fsm := MAC0; m := 0; acc := (others => '0'); end if;
          when MAC0 | MAC1 | MAC2 | MAC3 | MAC4 | MAC5 =>
            case fsm is
              when MAC0 => prod := resize(mixer_coeff(m*6+0) * mix_val(0), 32); acc := resize(prod(29 downto 14), 32); fsm := MAC1;
              when MAC1 => prod := resize(mixer_coeff(m*6+1) * mix_val(1), 32); acc := acc + resize(prod(29 downto 14), 32); fsm := MAC2;
              when MAC2 => prod := resize(mixer_coeff(m*6+2) * mix_val(2), 32); acc := acc + resize(prod(29 downto 14), 32); fsm := MAC3;
              when MAC3 => prod := resize(mixer_coeff(m*6+3) * mix_val(3), 32); acc := acc + resize(prod(29 downto 14), 32); fsm := MAC4;
              when MAC4 => prod := resize(mixer_coeff(m*6+4) * mix_val(4), 32); acc := acc + resize(prod(29 downto 14), 32); fsm := MAC5;
              when MAC5 => prod := resize(mixer_coeff(m*6+5) * mix_val(5), 32); acc := acc + resize(prod(29 downto 14), 32); fsm := DONE;
              when others => null;
            end case;
          when DONE =>
            -- Saturation clamp: prevent wrap-around on overflow
            if acc > 32767 then acc := to_signed(32767, 32);
            elsif acc < -32768 then acc := to_signed(-32768, 32); end if;
            -- Convert to PWM duty: neutral(32768) + saturated_correction
            motor_out(m) <= resize(unsigned(to_signed(32768, 17) + resize(acc, 17)), 16);
            if m = 7 then fsm := IDLE; else m := m + 1; acc := (others => '0'); fsm := MAC0; end if;
          when others => fsm := IDLE;
        end case;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Slew Rate Limiter + Arm Sequence (1ms steps, ±160 counts/ms = ~1%/ms)
  -- Forces neutral for 2s after arm, then ramps toward target.
  -- =====================================================================
  process(clk_i)
    variable arm_timer  : natural range 0 to 2000 := 0;    -- ms counter post-arm
    variable armed_prev : std_ulogic := '0';               -- edge detect
    variable target     : unsigned(15 downto 0);           -- target from mixer
    variable current    : unsigned(15 downto 0);           -- slewed output
    constant SLEW_STEP  : unsigned(15 downto 0) := to_unsigned(160, 16); -- ~1% per ms
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        for ch in 0 to 7 loop motor_out_slewed(ch) <= to_unsigned(32768, 16); end loop;
        arm_timer := 0; armed_prev := '0';
      elsif hb_ms_tick = '1' then
        -- Arm edge detect: start timer on rising edge of motors_armed
        if motors_armed = '1' and armed_prev = '0' then
          arm_timer := 2000;
        elsif motors_armed = '0' then
          arm_timer := 0;
        elsif arm_timer > 0 then
          arm_timer := arm_timer - 1;
        end if;
        armed_prev := motors_armed;

        -- Slew each motor channel
        for ch in 0 to 7 loop
          if motors_armed = '0' then
            -- Disarmed: hold neutral
            motor_out_slewed(ch) <= to_unsigned(32768, 16);
          elsif arm_timer > 0 then
            -- 2s post-arm: force neutral
            motor_out_slewed(ch) <= to_unsigned(32768, 16);
          else
            -- Armed + timer expired: ramp toward mixer target
            target := motor_out(ch);
            current := motor_out_slewed(ch);
            if target > current then
              if target - current > SLEW_STEP then
                motor_out_slewed(ch) <= current + SLEW_STEP;
              else
                motor_out_slewed(ch) <= target;
              end if;
            elsif target < current then
              if current - target > SLEW_STEP then
                motor_out_slewed(ch) <= current - SLEW_STEP;
              else
                motor_out_slewed(ch) <= target;
              end if;
            end if;
          end if;
        end loop;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- IMU Complementary Filter (runs on imu_update strobe)
  -- =====================================================================
  process(clk_i)
    constant ALPHA : sfix_t := to_signed(16056, 16);
    constant BETA  : sfix_t := to_signed(328, 16);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then imu_roll <= SFIX_ZERO; imu_pitch <= SFIX_ZERO; imu_yaw <= SFIX_ZERO;
      elsif imu_update = '1' then
        imu_roll  <= resize(resize(signed(ALPHA) * (imu_roll + imu_raw(3)), 32)(29 downto 14) 
                   + resize(signed(BETA) * resize(imu_raw(1) * SFIX_ONE, 32)(31 downto 16), 32)(29 downto 14), 16);
        imu_pitch <= resize(resize(signed(ALPHA) * (imu_pitch + imu_raw(4)), 32)(29 downto 14) 
                   + resize(signed(BETA) * resize((-imu_raw(0)) * SFIX_ONE, 32)(31 downto 16), 32)(29 downto 14), 16);
        imu_yaw   <= imu_yaw + imu_raw(5);
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Depth computation (runs on depth_update strobe)
  -- =====================================================================
  process(clk_i)
    variable diff : signed(31 downto 0);
    variable tmp  : signed(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then depth_cm <= (others => '0');
      elsif depth_update = '1' then
        diff := signed(depth_raw_pressure) - to_signed(101300, 32);
        -- cm = diff * 0.0102 ≈ (diff * 10695) >> 20
        tmp  := resize(shift_right(diff * to_signed(10695, 32), 20), 32);
        if tmp < 0 then depth_cm <= (others => '0');
        else depth_cm <= unsigned(tmp(15 downto 0)); end if;
      end if;
    end if;
  end process;

  -- =====================================================================
  -- Outputs — SINGLE combinacional driver (no multi-driver!)
  -- =====================================================================
  pwm_arm_o <= motors_armed and heartbeat_alive;

  process(motor_sel, enc_pos, enc_vel, motors_armed, heartbeat_alive,
          heartbeat_cnt, imu_roll, imu_pitch, imu_yaw,
          pid_output, depth_cm, depth_raw_temp)
    variable v : std_ulogic_vector(255 downto 0);
  begin
    v := (others => '0');
    v(31  downto 0)   := std_ulogic_vector(enc_pos(to_integer(motor_sel)));
    v(63  downto 32)  := std_ulogic_vector(enc_vel(to_integer(motor_sel)));
    v(71) := motors_armed; v(70) := heartbeat_alive; v(69) := not motors_armed;
    v(79  downto 72)  := std_ulogic_vector(heartbeat_cnt);
    v(95  downto 80)  := std_ulogic_vector(imu_roll);
    v(111 downto 96)  := std_ulogic_vector(imu_pitch);
    v(127 downto 112) := std_ulogic_vector(imu_yaw);
    v(143 downto 128) := std_ulogic_vector(pid_output(0));
    v(159 downto 144) := std_ulogic_vector(pid_output(1));
    v(175 downto 160) := std_ulogic_vector(pid_output(2));
    v(191 downto 176) := std_ulogic_vector(pid_output(3));
    v(207 downto 192) := std_ulogic_vector(pid_output(4));
    v(223 downto 208) := std_ulogic_vector(pid_output(5));
    v(239 downto 224) := std_ulogic_vector(depth_cm);
    v(255 downto 240) := std_ulogic_vector(depth_raw_temp);
    cfs_out_o <= v;
  end process;

  motor_map: for ch in 0 to 7 generate
    motor_pwm_o(ch*16+15 downto ch*16) <= std_ulogic_vector(motor_out_slewed(ch));
  end generate;

end architecture;
