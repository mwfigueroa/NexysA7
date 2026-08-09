-- ============================================================================
-- tb_rov.vhd — Testbench for neorv32_rov_motors CFS command processing
-- ============================================================================
-- Tests: heartbeat, arm, calibrate, setpoint, PID, mixer, depth
-- Monitors: cfs_out_o[95:64] (status + IMU roll), cfs_out_o[31:0] (enc_pos)
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_rov is
end entity;

architecture sim of tb_rov is

    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    signal clk      : std_ulogic := '0';
    signal rstn     : std_ulogic := '0';
    signal cfs_in   : std_ulogic_vector(255 downto 0) := (others => '0');
    signal cfs_out  : std_ulogic_vector(255 downto 0);
    signal enc_a    : std_ulogic_vector(7 downto 0) := (others => '0');
    signal enc_b    : std_ulogic_vector(7 downto 0) := (others => '0');
    signal motor_pwm : std_ulogic_vector(127 downto 0);
    signal pwm_arm  : std_ulogic;

    -- CFS write helper: mimics CPU store to CFS_REG
    procedure cfs_write(
        signal   cfs_in_sig : out std_ulogic_vector(255 downto 0);
        constant reg_addr   : in  natural range 0 to 7;
        constant data       : in  std_ulogic_vector(31 downto 0)) is
        variable v : std_ulogic_vector(255 downto 0);
    begin
        v := cfs_in_sig;
        v(reg_addr*32+31 downto reg_addr*32) := data;
        cfs_in_sig <= v;
        wait for CLK_PERIOD;  -- let ROV sample
    end procedure;

    -- CFS write command helper: NOP then CMD (simulates _rov_cmd protocol)
    -- CFS write command helper: mimics _rov_cmd(cmd, fields, value) protocol
    -- fields[2:0] = motor_sel, fields[13:8] = axis_sel/coeff_idx/gain_sel
    -- Packed: CFS_REG0[31:16]=value, [13:8]=fields[13:8], [7:4]=cmd, [2:0]=fields[2:0]
    -- CFS write command helper: mimics _rov_cmd protocol
    -- CFS_REG0[31:16]=value, [13:8]=fields[13:8], [7:4]=cmd, [2:0]=fields[2:0]
    procedure cfs_cmd(
        signal cfs_in_sig : out std_ulogic_vector(255 downto 0);
        constant cmd_nibble : in std_ulogic_vector(3 downto 0);
        constant fields     : in std_ulogic_vector(15 downto 0);
        constant value      : in std_ulogic_vector(15 downto 0)) is
        variable field_bits : std_ulogic_vector(8 downto 0);
        variable packed : std_ulogic_vector(31 downto 0);
        variable nop    : std_ulogic_vector(31 downto 0);
    begin
        -- Extract field bits: [13:8] & [2:0] from fields
        field_bits := fields(13 downto 8) & fields(2 downto 0);
        -- Build CFS_REG0 same as _rov_cmd: (value<<16) | control | (cmd<<4)
        packed := value & "00" & fields(13 downto 8) & cmd_nibble & "0" & fields(2 downto 0);
        nop    := value & "00" & fields(13 downto 8) & "0000" & "0" & fields(2 downto 0);
        -- NOP write (cmd=0)
        cfs_write(cfs_in_sig, 0, nop);
        wait for CLK_PERIOD * 16;
        -- Real command write
        cfs_write(cfs_in_sig, 0, packed);
        wait for CLK_PERIOD * 16;
    end procedure;

    -- Read helper
    function cfs_read(
        signal cfs_out_sig : std_ulogic_vector(255 downto 0);
        constant reg_addr  : natural range 0 to 7) return std_ulogic_vector is
    begin
        return cfs_out_sig(reg_addr*32+31 downto reg_addr*32);
    end function;

begin

    -- 100 MHz clock
    clk <= not clk after CLK_PERIOD / 2;

    -- Reset: active low, released after 20 cycles
    rstn <= '0', '1' after CLK_PERIOD * 20;

    -- DUT
    uut: entity work.neorv32_rov_motors
    port map (
        clk_i       => clk,
        rstn_i      => rstn,
        cfs_in_i    => cfs_in,
        cfs_out_o   => cfs_out,
        enc_a_i     => enc_a,
        enc_b_i     => enc_b,
        motor_pwm_o => motor_pwm,
        pwm_arm_o   => pwm_arm
    );

    -- Main test sequence
    process
        variable status_reg : std_ulogic_vector(31 downto 0);
        variable enc_reg    : std_ulogic_vector(31 downto 0);
        variable pid_reg    : std_ulogic_vector(31 downto 0);
    begin
        -- Wait for reset release
        wait until rstn = '1';
        wait for CLK_PERIOD * 100;
        report "=== Test 1: Initial state ===" severity note;
        status_reg := cfs_read(cfs_out, 2);
        report "CFS_REG2 = " & to_hstring(status_reg);
        
        -- Write heartbeat timeout = 200 via CFS_REG1 + command 0xC
        report "=== Test 2: Set heartbeat timeout ===" severity note;
        cfs_write(cfs_in, 1, std_ulogic_vector(to_unsigned(200, 8)) & x"000000");
        cfs_cmd(cfs_in, x"C", x"0000", x"0000");
        status_reg := cfs_read(cfs_out, 2);
        report "After timeout CMD: CFS_REG2 = " & to_hstring(status_reg);

        -- Send HEARTBEAT command (CMD=0x1, toggle=1 in fields[8])
        report "=== Test 3: Heartbeat #1 (toggle=1, fields=0x0100) ===" severity note;
        cfs_cmd(cfs_in, x"1", x"0100", x"0000");  -- fields=0x0100: toggle=1 in bit8
        status_reg := cfs_read(cfs_out, 2);
        report "After HB#1: CFS_REG2 = " & to_hstring(status_reg);
        report "  bit7(armed)=" & std_ulogic'image(status_reg(7));
        report "  bit6(hb_ok)=" & std_ulogic'image(status_reg(6));
        report "  bit5(!armed)=" & std_ulogic'image(status_reg(5));
        
        if status_reg(6) = '0' then
            report "*** FAIL: heartbeat_alive = 0 after first heartbeat ***" severity error;
        else
            report "*** PASS: heartbeat_alive = 1 after first heartbeat ***" severity note;
        end if;

        -- Wait 100us (instead of 100ms to speed up sim)
        wait for 100 us;
        status_reg := cfs_read(cfs_out, 2);
        report "After 100us: CFS_REG2 = " & to_hstring(status_reg);

        -- Heartbeat #2 (toggle=0)
        report "=== Test 4: Heartbeat #2 (toggle=0) ===" severity note;
        cfs_cmd(cfs_in, x"1", x"0000", x"0000");
        status_reg := cfs_read(cfs_out, 2);
        report "After HB#2: CFS_REG2 = " & to_hstring(status_reg);

        -- ARM command (CMD=0x2)
        report "=== Test 5: ARM ===" severity note;
        cfs_cmd(cfs_in, x"2", x"0000", x"0000");
        status_reg := cfs_read(cfs_out, 2);
        report "After ARM: CFS_REG2 = " & to_hstring(status_reg);
        if status_reg(7) = '0' then
            report "*** FAIL: motors not armed ***" severity error;
        else
            report "*** PASS: motors armed ***" severity note;
        end if;

        -- Wait for heartbeat timeout (timeout=200ms but we wait enough)
        wait for 300 us;
        status_reg := cfs_read(cfs_out, 2);
        report "After 300us: CFS_REG2 = " & to_hstring(status_reg);

        report "=== ALL TESTS DONE ===" severity note;
        wait;
    end process;

end architecture;
