#!/usr/bin/env python3
"""Run cocotb tests for the Nexys A7 frequency counter."""
from cocotb_tools.runner import get_runner
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"
SIM = Path(__file__).resolve().parent

def main():
    runner = get_runner("icarus")
    runner.build(
        sources=[SIM / "top_sim.v", SRC / "top.v"],
        hdl_toplevel="top_sim",
        build_dir="sim_build",
        build_args=["-g2012", "-I", str(SRC), "-I", str(SIM)],
    )
    runner.test(
        hdl_toplevel="top_sim",
        test_module="test_freq_counter",
    )

if __name__ == "__main__":
    main()
