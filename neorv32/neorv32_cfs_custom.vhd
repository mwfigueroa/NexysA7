-- ================================================================================ --
-- NEORV32 SoC - Custom Functions Subsystem (CFS) for ROV Motor Control             --
-- ================================================================================ --
-- Maps 8×32-bit registers (256 bits) between CPU bus and cfs_in/out conduits.      --
-- CFS_REG0-7 connect to neorv32_rov_motors via cfs_out_o/cfs_in_i.                 --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cfs is
  port (
    clk_i      : in  std_ulogic;
    rstn_i     : in  std_ulogic;
    req_addr_i : in  std_ulogic_vector(15 downto 0);
    req_data_i : in  std_ulogic_vector(31 downto 0);
    req_ben_i  : in  std_ulogic_vector(3 downto 0);
    req_stb_i  : in  std_ulogic;
    req_rw_i   : in  std_ulogic;                      -- 0=read, 1=write
    rsp_data_o : out std_ulogic_vector(31 downto 0);
    rsp_ack_o  : out std_ulogic;
    irq_o      : out std_ulogic;
    cfs_in_i   : in  std_ulogic_vector(255 downto 0); -- from ROV module
    cfs_out_o  : out std_ulogic_vector(255 downto 0)  -- to ROV module
  );
end entity;

architecture neorv32_cfs_rtl of neorv32_cfs is

  -- 8 read/write registers (256 bits total)
  type cfs_regs_t is array (0 to 7) of std_ulogic_vector(31 downto 0);
  signal cfs_reg_wr : cfs_regs_t; -- CPU writes → cfs_out_o → ROV commands
  signal cfs_reg_rd : cfs_regs_t; -- ROV telemetry → cfs_in_i → CPU reads

begin

  -- No interrupt in this design
  irq_o <= '0';

  -- CPU writes go to cfs_out_o (ROV receives as cfs_in_i)
  -- cfs_out_o = REG7 & REG6 & REG5 & REG4 & REG3 & REG2 & REG1 & REG0
  cfs_out_o <= cfs_reg_wr(7) & cfs_reg_wr(6) & cfs_reg_wr(5) & cfs_reg_wr(4)
             & cfs_reg_wr(3) & cfs_reg_wr(2) & cfs_reg_wr(1) & cfs_reg_wr(0);

  -- CPU reads come from cfs_in_i (ROV sends as cfs_out_o)
  -- cfs_in_i = [REG7slice][REG6]...[REG0slice]
  cfs_reg_rd(0) <= cfs_in_i(31  downto 0);
  cfs_reg_rd(1) <= cfs_in_i(63  downto 32);
  cfs_reg_rd(2) <= cfs_in_i(95  downto 64);
  cfs_reg_rd(3) <= cfs_in_i(127 downto 96);
  cfs_reg_rd(4) <= cfs_in_i(159 downto 128);
  cfs_reg_rd(5) <= cfs_in_i(191 downto 160);
  cfs_reg_rd(6) <= cfs_in_i(223 downto 192);
  cfs_reg_rd(7) <= cfs_in_i(255 downto 224);

  -- Bus access: 8 registers at word addresses 0x00-0x1C
  host_access: process(rstn_i, clk_i)
    variable word_addr : unsigned(13 downto 0);
  begin
    if (rstn_i = '0') then
      cfs_reg_wr <= (others => (others => '0'));
      rsp_data_o <= (others => '0');
      rsp_ack_o  <= '0';
    elsif rising_edge(clk_i) then
      rsp_ack_o <= req_stb_i;
      rsp_data_o <= (others => '0');

      if (req_stb_i = '1') then
        word_addr := unsigned(req_addr_i(15 downto 2));

        -- Write access (word-wise) to registers 0-7
        if (req_rw_i = '1') then
          if word_addr < 8 then
            cfs_reg_wr(to_integer(word_addr)) <= req_data_i;
          end if;

        -- Read access (word-wise) from registers 0-7
        else
          if word_addr < 8 then
            rsp_data_o <= cfs_reg_rd(to_integer(word_addr));
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
