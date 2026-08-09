# sim_rov.tcl — Behavioral simulation of neorv32_rov_motors
# Usage: vivado -mode batch -source sim/sim_rov.tcl
#        vivado -mode batch -source sim/sim_rov.tcl -tclargs gui

set project_dir  "P:/NexysA7"
set neorv32_dir  "P:/NexysA7/neorv32"
set neorv32_home "P:/neorv32"
set sim_dir      "P:/NexysA7/sim"
set sim_out      "$project_dir/sim_out"
set launch_gui   0
if { $argc > 0 && [lindex $argv 0] eq "gui" } { set launch_gui 1 }

file delete -force $sim_out
file mkdir $sim_out
cd $sim_out

puts "=============================================="
puts "  ROV CFS — Vivado xsim Behavioral Simulation"
puts "=============================================="
puts "  DUT:     $neorv32_dir/neorv32_rov_motors.vhd"
puts "  TB:      $sim_dir/tb_rov.vhd"
puts ""

# Compile VHDL sources
puts "--- Compile (xvhdl) ---"
exec xvhdl --incr --relax --2008 -work neorv32 \
    "$neorv32_home/rtl/core/neorv32_package.vhd" \
    "$neorv32_dir/neorv32_cfs_custom.vhd" 2>&1
exec xvhdl --incr --relax --2008 -work xil_defaultlib \
    "$neorv32_dir/neorv32_rov_motors.vhd" \
    "$sim_dir/tb_rov.vhd" 2>&1

# Elaborate
puts "--- Elaborate (xelab) ---"
exec xelab --incr --debug typical --relax --mt 2 \
    --snapshot tb_rov_snap xil_defaultlib.tb_rov 2>&1

# Simulate
if { $launch_gui } {
    puts "--- Launching xsim GUI ---"
    exec xsim tb_rov_snap --gui &
} else {
    puts "--- Simulate (xsim batch) ---"
    set fh [open "run.tcl" w]
    puts $fh "run all"
    puts $fh "quit"
    close $fh
    exec xsim tb_rov_snap --tclbatch run.tcl 2>&1

    puts ""
    puts "=============================================="
    puts "  Simulation complete"
    puts "  Waveform: $sim_out/tb_rov_snap.wdb"
    puts "  Replay:   vivado -mode batch -source sim/sim_rov.tcl -tclargs gui"
    puts "=============================================="
}
