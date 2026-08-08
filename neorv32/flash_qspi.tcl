# flash_qspi.tcl — Program NEORV32 to QSPI via Vivado TCL
# Run: vivado -mode batch -source flash_qspi.tcl

set bitfile "P:/NexysA7/neorv32/top.bit"
set mcsfile "P:/NexysA7/neorv32/top.mcs"

puts "Opening hardware..."
open_hw
connect_hw_server
open_hw_target
set device [lindex [get_hw_devices] 0]

puts "Creating flash config..."
set cfgmem [get_property PROGRAM.HW_CFGMEM $device]
if {$cfgmem eq ""} {
    # Nexys A7 uses the Artix-7-supported single S25FL128S QSPI definition.
    create_hw_cfgmem -hw_device $device -mem_dev [lindex [get_cfgmem_parts {s25fl128sxxxxxx0-spi-x1_x2_x4}] 0]
    set cfgmem [get_property PROGRAM.HW_CFGMEM $device]
}

puts "Setting flash parameters..."
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.FILES [list $mcsfile] $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem
set_property PROGRAM.CHECKSUM 0 $cfgmem

puts "Programming (this will take 2-3 minutes)..."
set start [clock seconds]
program_hw_cfgmem $cfgmem
set elapsed [expr {[clock seconds] - $start}]
puts "Done in ${elapsed}s!"

close_hw
