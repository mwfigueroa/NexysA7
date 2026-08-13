NEORV32_HOME ?= ../../..
MARCH = rv32imc_zicsr_zifencei
EFFORT = -Os
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=32k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k
include $(NEORV32_HOME)/sw/common/common.mk
