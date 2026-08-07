# program.tcl — Programar Nexys A7 con Vivado Lab Edition
# Uso: vivado_lab -mode batch -source program.tcl

set bitfile "P:/NexysA7/bitstreams/top.bit"

puts "=============================================="
puts "  Nexys A7 — Vivado Lab Programmer"
puts "=============================================="
puts "Bitstream: $bitfile"

# Abrir hardware server
open_hw
connect_hw_server

# Abrir target (auto-detecta la Nexys A7)
open_hw_target

# Configurar dispositivo
set device [lindex [get_hw_devices] 0]
puts "Dispositivo: $device"

current_hw_device $device

# Si hay probes ILA
set probes_file "P:/NexysA7/bitstreams/debug_nets.ltx"
if {[file exists $probes_file]} {
    puts "Cargando probes ILA: $probes_file"
    set_property PROBES.FILE $probes_file $device
    set_property FULL_PROBES.FILE $probes_file $device
}

# Programar
puts "Programando..."
set_property PROGRAM.FILE $bitfile $device
program_hw_devices

puts ""
puts "=============================================="
puts "  Programacion Exitosa"
puts "=============================================="

close_hw
