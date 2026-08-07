# build.tcl — Nexys A7 build script for Vivado
# Usage: vivado -mode batch -source build.tcl

set project_name "nexys_a7_top"
set vivado_bin   "P:/AMDDesignTools/2026.1/Vivado"
set project_dir  "P:/NexysA7"
set src_dir      "P:/NexysA7/src"
set bitstream    "P:/NexysA7/bitstreams/top.bit"

puts "=============================================="
puts "  Nexys A7-100T — Build Script"
puts "=============================================="
puts ""

# Create project
create_project -force $project_name $project_dir/build -part xc7a100tcsg324-1

# Add sources
add_files -norecurse [glob $src_dir/*.v]
add_files -fileset constrs_1 -norecurse [glob $src_dir/*.xdc]

# Set top module
set_property top top [current_fileset]

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
file copy -force "$project_dir/build/$project_name.runs/impl_1/top.bit" $bitstream

puts ""
puts "=============================================="
puts "  Build Complete!"
puts "  Bitstream: $bitstream"
puts "=============================================="

close_project
