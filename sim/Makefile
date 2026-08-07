# Nexys A7 Frequency Counter — Simulation targets
# Usage:
#   make iverilog    — compile + run with Icarus Verilog, open gtkwave
#   make cocotb      — run cocotb Python testbench
#   make clean       — remove generated files

SRC_DIR  = ../src
SIM_DIR  = .
TOP      = top
TB       = tb_top

# ── Icarus Verilog ──────────────────────────────────────────────────────

iverilog: $(SIM_DIR)/$(TB).vvp
	vvp $(SIM_DIR)/$(TB).vvp
	@echo "Launching gtkwave..."
	bash $(SIM_DIR)/wave.sh $(SIM_DIR)/$(TB).vcd

$(SIM_DIR)/$(TB).vvp: $(SIM_DIR)/$(TB).v $(SRC_DIR)/$(TOP).v
	iverilog -g2012 -o $@ -I $(SRC_DIR) $(SIM_DIR)/$(TB).v $(SRC_DIR)/$(TOP).v

# ── cocotb ──────────────────────────────────────────────────────────────

cocotb:
	python3 $(SIM_DIR)/run_cocotb.py 2>&1 | tee $(SIM_DIR)/cocotb.log

# ── verilator (lint + C++ sim) ──────────────────────────────────────────

verilator:
	verilator --lint-only -Wall -I $(SRC_DIR) $(SRC_DIR)/$(TOP).v

# ── Clean ────────────────────────────────────────────────────────────────

clean:
	rm -f $(SIM_DIR)/*.vvp $(SIM_DIR)/*.vcd $(SIM_DIR)/*.fst
	rm -f $(SIM_DIR)/cocotb.log
	rm -rf $(SIM_DIR)/__pycache__
	rm -f uart_output.txt

.PHONY: iverilog cocotb verilator clean
