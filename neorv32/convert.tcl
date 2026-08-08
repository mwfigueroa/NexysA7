# convert.tcl — Convert .bit to .mcs for QSPI flash (Nexys A7-100T)
write_cfgmem -format mcs -interface spix1 -size 16 -loadbit "up 0x00000000 P:/NexysA7/neorv32/top.bit" -file P:/NexysA7/neorv32/top.mcs -force
puts "MCS file created: P:/NexysA7/neorv32/top.mcs"
