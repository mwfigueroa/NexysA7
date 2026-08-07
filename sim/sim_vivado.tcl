# sim_vivado.tcl — Behavioral simulation in Vivado xsim
# Usage:
#   vivado -mode batch -source sim/sim_vivado.tcl               (batch)
#   vivado -mode batch -source sim/sim_vivado.tcl -tclargs gui  (GUI)

set project_dir  "P:/NexysA7"
set src_dir      "P:/NexysA7/src"
set sim_dir      "P:/NexysA7/sim"
set sim_out      "$project_dir/sim_out"
set launch_gui   0
if { $argc > 0 && [lindex $argv 0] eq "gui" } { set launch_gui 1 }

file delete -force $sim_out
file mkdir $sim_out
cd $sim_out

puts "=============================================="
puts "  Nexys A7 — Vivado xsim Behavioral Simulation"
puts "=============================================="
puts "  Sources:   $src_dir/top.v"
puts "  Testbench: $sim_dir/tb_top.v"
puts "  Output:    $sim_out"
puts ""

# ── Compile ─────────────────────────────────────────────────────────────
puts "--- Compile (xvlog) ---"
exec xvlog --sv --incr --relax -work xil_defaultlib \
    "$src_dir/top.v" "$sim_dir/tb_top.v" 2>&1

# ── Elaborate ───────────────────────────────────────────────────────────
puts "--- Elaborate (xelab) ---"
exec xelab --incr --debug typical --relax --mt 2 \
    --snapshot tb_top_snap xil_defaultlib.tb_top 2>&1

# ── Simulate ────────────────────────────────────────────────────────────
if { $launch_gui } {
    puts "--- Launching xsim GUI ---"
    exec xsim tb_top_snap --gui &
} else {
    puts "--- Simulate (xsim batch, 5 ms) ---"
    set fh [open "run.tcl" w]
    puts $fh "log_wave -r /*"
    puts $fh "run 5 ms"
    puts $fh "quit"
    close $fh
    exec xsim tb_top_snap --tclbatch run.tcl 2>&1

    puts ""
    puts "=============================================="
    puts "  Simulation complete"
    puts "  Waveform: $sim_out/tb_top_snap.wdb"
    puts "  Replay:   vivado -mode batch -source sim/sim_vivado.tcl -tclargs gui"
    puts "=============================================="
}
