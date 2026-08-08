# Toolchain bare-metal para el núcleo RISC-V RV32IMC.
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv32)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(_toolchain_hints)
if(DEFINED ENV{RISCV_TOOLCHAIN_DIR})
    list(APPEND _toolchain_hints "$ENV{RISCV_TOOLCHAIN_DIR}/bin")
endif()
file(GLOB _local_toolchains "${CMAKE_CURRENT_LIST_DIR}/../.toolchains/xpack-riscv-none-elf-gcc-*/bin")
list(APPEND _toolchain_hints ${_local_toolchains})

find_program(RISCV_GCC NAMES riscv-none-elf-gcc riscv32-unknown-elf-gcc HINTS ${_toolchain_hints})
if(NOT RISCV_GCC)
    message(FATAL_ERROR
        "No se encontró un compilador RISC-V. Ejecute scripts/bootstrap-toolchain.ps1 "
        "o defina RISCV_TOOLCHAIN_DIR y vuelva a configurar.")
endif()

get_filename_component(RISCV_BIN_DIR "${RISCV_GCC}" DIRECTORY)
find_program(RISCV_GXX NAMES riscv-none-elf-g++ riscv32-unknown-elf-g++ HINTS "${RISCV_BIN_DIR}" REQUIRED NO_DEFAULT_PATH)
find_program(CMAKE_OBJCOPY NAMES riscv-none-elf-objcopy riscv32-unknown-elf-objcopy HINTS "${RISCV_BIN_DIR}" REQUIRED NO_DEFAULT_PATH)
find_program(CMAKE_OBJDUMP NAMES riscv-none-elf-objdump riscv32-unknown-elf-objdump HINTS "${RISCV_BIN_DIR}" REQUIRED NO_DEFAULT_PATH)
find_program(CMAKE_SIZE NAMES riscv-none-elf-size riscv32-unknown-elf-size HINTS "${RISCV_BIN_DIR}" REQUIRED NO_DEFAULT_PATH)

set(CMAKE_C_COMPILER "${RISCV_GCC}")
set(CMAKE_CXX_COMPILER "${RISCV_GXX}")
set(CMAKE_ASM_COMPILER "${RISCV_GCC}")

# RV32I + M (mul/div) + C (instrucciones comprimidas), ABI de 32 bits.
set(RV32IMC_ARCH_FLAGS "-march=rv32imc -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0")
set(CMAKE_C_FLAGS_INIT "${RV32IMC_ARCH_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${RV32IMC_ARCH_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "${RV32IMC_ARCH_FLAGS}")
