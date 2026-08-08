NEORV32_HOME ?= ../../..
RISCV_PREFIX ?= riscv64-unknown-elf-
MARCH = rv32i_zicsr_zifencei
MABI = ilp32
EFFORT = -Os
USER_FLAGS += -isystem /usr/lib/picolibc/riscv64-unknown-elf/include
USER_FLAGS += -nostartfiles
USER_FLAGS += -nodefaultlibs
USER_FLAGS += -L/usr/lib/picolibc/riscv64-unknown-elf/lib/rv32iac/ilp32
USER_FLAGS += -lc -lgcc
USER_FLAGS += -msave-restore
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_base=0x80000000
include $(NEORV32_HOME)/sw/common/common.mk
