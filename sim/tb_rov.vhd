-- ============================================================================
-- End-to-end testbench for the ROV CFS path.
-- Host bus -> neorv32_cfs -> neorv32_rov_motors -> telemetry readback.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.env.all;

library neorv32;
use neorv32.neorv32_package.all;

entity tb_rov is
end entity;

architecture sim of tb_rov is
  constant CLK_PERIOD : time := 10 ns;

  signal clk : std_ulogic := '0';
  signal rstn : std_ulogic := '0';

  -- Minimal NEORV32 CFS host-bus master.
  signal req_addr : std_ulogic_vector(15 downto 0) := (others => '0');
  signal req_data : std_ulogic_vector(31 downto 0) := (others => '0');
  signal req_ben  : std_ulogic_vector(3 downto 0) := (others => '1');
  signal req_stb  : std_ulogic := '0';
  signal req_rw   : std_ulogic := '0';
  signal rsp_data : std_ulogic_vector(31 downto 0);
  signal rsp_ack  : std_ulogic;
  signal irq      : std_ulogic;

  signal cfs_to_rov : std_ulogic_vector(255 downto 0);
  signal rov_to_cfs : std_ulogic_vector(255 downto 0);
  signal enc_a : std_ulogic_vector(7 downto 0) := (others => '0');
  signal enc_b : std_ulogic_vector(7 downto 0) := (others => '0');
  signal motor_pwm : std_ulogic_vector(127 downto 0);
  signal pwm_arm : std_ulogic;
begin
  clk <= not clk after CLK_PERIOD / 2;
  rstn <= '0', '1' after CLK_PERIOD * 20;

  cfs: entity neorv32.neorv32_cfs
    port map (
      clk_i      => clk,
      rstn_i     => rstn,
      req_addr_i => req_addr,
      req_data_i => req_data,
      req_ben_i  => req_ben,
      req_stb_i  => req_stb,
      req_rw_i   => req_rw,
      rsp_data_o => rsp_data,
      rsp_ack_o  => rsp_ack,
      irq_o      => irq,
      cfs_in_i   => rov_to_cfs,
      cfs_out_o  => cfs_to_rov
    );

  rov: entity work.neorv32_rov_motors
    port map (
      clk_i       => clk,
      rstn_i      => rstn,
      cfs_in_i    => cfs_to_rov,
      cfs_out_o   => rov_to_cfs,
      enc_a_i     => enc_a,
      enc_b_i     => enc_b,
      motor_pwm_o => motor_pwm,
      pwm_arm_o   => pwm_arm
    );

  stimulus: process
    procedure wait_cycles(constant cycles : natural) is
    begin
      for i in 1 to cycles loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    procedure bus_write(
      constant reg_addr : natural range 0 to 7;
      constant data : std_ulogic_vector(31 downto 0)) is
    begin
      req_addr <= std_ulogic_vector(to_unsigned(reg_addr * 4, req_addr'length));
      req_data <= data;
      req_rw <= '1';
      req_stb <= '1';
      wait_cycles(1);
      assert rsp_ack = '1' report "CFS write was not acknowledged" severity failure;
      req_stb <= '0';
      wait_cycles(1);
    end procedure;

    procedure bus_read(
      constant reg_addr : natural range 0 to 7;
      variable data : out std_ulogic_vector(31 downto 0)) is
    begin
      req_addr <= std_ulogic_vector(to_unsigned(reg_addr * 4, req_addr'length));
      req_rw <= '0';
      req_stb <= '1';
      wait_cycles(1);
      assert rsp_ack = '1' report "CFS read was not acknowledged" severity failure;
      data := rsp_data;
      req_stb <= '0';
      wait_cycles(1);
    end procedure;

    -- Matches the firmware _rov_cmd(): NOP, then command, with the command
    -- stable long enough for both synchronous RTL command processes.
    procedure cfs_cmd(
      constant cmd : std_ulogic_vector(3 downto 0);
      constant fields : std_ulogic_vector(15 downto 0);
      constant value : std_ulogic_vector(15 downto 0)) is
      variable nop_word : std_ulogic_vector(31 downto 0);
      variable cmd_word : std_ulogic_vector(31 downto 0);
    begin
      nop_word := x"0000" & "00" & fields(13 downto 8) & "0000" & "0" & fields(2 downto 0);
      cmd_word := value & "00" & fields(13 downto 8) & cmd & "0" & fields(2 downto 0);
      bus_write(0, nop_word);
      wait_cycles(8);
      bus_write(0, cmd_word);
      wait_cycles(8);
    end procedure;

    variable status_reg : std_ulogic_vector(31 downto 0);
    variable telem_reg  : std_ulogic_vector(31 downto 0);
  begin
    wait until rstn = '1';
    wait_cycles(10);

    report "=== CFS bridge: reset telemetry ===" severity note;
    bus_read(2, status_reg);
    assert status_reg(7 downto 5) = "001"
      report "Unexpected reset safety state" severity failure;

    report "=== CFS bridge: timeout, heartbeat and arm ===" severity note;
    bus_write(1, x"C8000000"); -- heartbeat timeout = 200 ms
    cfs_cmd(x"C", x"0000", x"0000");
    cfs_cmd(x"1", x"0100", x"0000");
    bus_read(2, status_reg);
    assert status_reg(6) = '1' report "Heartbeat command did not reach ROV" severity failure;
    cfs_cmd(x"1", x"0000", x"0000");
    cfs_cmd(x"2", x"0000", x"0000");
    bus_read(2, status_reg);
    assert status_reg(7 downto 6) = "11" report "Arm command did not reach ROV" severity failure;
    assert pwm_arm = '1' report "PWM arm output was not asserted" severity failure;

    report "=== CFS bridge: IMU and depth payload registers ===" severity note;
    cfs_cmd(x"7", x"0500", x"0100"); -- IMU yaw raw = +1.0 s1.14
    wait_cycles(4);
    bus_read(3, telem_reg);
    assert telem_reg(31 downto 16) = x"0100"
      report "IMU command or telemetry mapping failed" severity failure;

    bus_write(1, std_ulogic_vector(to_unsigned(101300, 32))); -- pressure at sea level
    cfs_cmd(x"A", x"0000", x"0000");
    bus_write(2, x"000000FA"); -- 25.0 C in deci-degrees
    cfs_cmd(x"A", x"0400", x"0000");
    wait_cycles(4);
    bus_read(7, telem_reg);
    assert telem_reg(31 downto 16) = x"00FA"
      report "Depth temperature payload did not reach ROV" severity failure;
    assert telem_reg(15 downto 0) = x"0000"
      report "Depth calculation at sea-level pressure is not zero" severity failure;

    report "=== CFS bridge: setpoint, PID gain/current and enable ===" severity note;
    cfs_cmd(x"6", x"0000", x"2000"); -- axis 0 setpoint = +0.5
    cfs_cmd(x"8", x"0000", x"4000"); -- axis 0 Kp = +1.0
    cfs_cmd(x"9", x"0000", x"0000"); -- axis 0 current = 0
    cfs_cmd(x"B", x"0100", x"0000"); -- enable PID axis 0
    wait for 3 ms; -- 400 Hz PID tick plus its three pipeline stages
    bus_read(4, telem_reg);
    assert signed(telem_reg(15 downto 0)) > 0
      report "PID configuration commands did not produce output" severity failure;

    report "=== CFS bridge: heartbeat failsafe ===" severity note;
    bus_write(1, x"01000000"); -- timeout = 1 ms
    cfs_cmd(x"C", x"0000", x"0000");
    wait for 2 ms;
    bus_read(2, status_reg);
    assert status_reg(7) = '0' and status_reg(6) = '0'
      report "Failsafe did not disarm after heartbeat timeout" severity failure;

    report "=== ALL END-TO-END CFS TESTS PASSED ===" severity note;
    finish;
    wait;
  end process;
end architecture;
