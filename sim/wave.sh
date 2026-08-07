#!/bin/bash
# Launch gtkwave for Nexys A7 simulation, routing through VcXsrv.
# Usage: ./wave.sh [vcd_file]

set -euo pipefail
SIMDIR="$(cd "$(dirname "$0")" && pwd)"
VCD="${1:-$SIMDIR/tb_top.vcd}"

# VcXsrv on Windows host (WSL2 gateway)
VCXSRV_IP="$(ip route show default | awk '/via/ {print $3}')"
export DISPLAY="${VCXSRV_IP}:0.0"

# Avoid WSLg interference
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11

# Launch
gtkwave "$VCD" &
echo "gtkwave launched on DISPLAY=$DISPLAY"
echo "VCD: $VCD"
