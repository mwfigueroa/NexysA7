# build.tcl — NEORV32 for Nexys A7-100T
# Usage: vivado -mode batch -source build.tcl
#   Runs from P:/NexysA7/neorv32/

set project_name "neorv32_nexys"
set project_dir  [file normalize [file dirname [info script]]]
set neorv32_home "P:/neorv32"
set bitstream    "$project_dir/top.bit"

puts "=============================================="
puts "  NEORV32 on Nexys A7-100T — Build"
puts "=============================================="

# Create project
create_project -force $project_name "$project_dir/build" -part xc7a100tcsg324-1

# Read NEORV32 file list and add VHDL sources
set file_list_raw [read [open "$neorv32_home/rtl/file_list_core.f" r]]
set file_list [string map [list {$NEORV32_HOME} $neorv32_home] $file_list_raw]
add_files $file_list
set_property library neorv32 [get_files $file_list]

# Add top-level wrapper and custom modules (in default work library)
add_files "$project_dir/neorv32_rov_motors.vhd"
add_files "$project_dir/neorv32_nexys_a7.vhd"

# Add constraints
add_files -fileset constrs_1 "$project_dir/neorv32_nexys.xdc"

# Set top
set_property top neorv32_nexys_a7 [current_fileset]

update_compile_order -fileset sources_1

puts "Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

puts "Running implementation..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Copy bitstream
file copy -force "$project_dir/build/$project_name.runs/impl_1/neorv32_nexys_a7.bit" $bitstream

puts ""
puts "=============================================="
puts "  Build Complete!"
puts "  Bitstream: $bitstream"
puts "=============================================="

close_project
