cmake_minimum_required(VERSION 3.22)

project(neorv32_firmware LANGUAGES C CXX ASM)

# Compiler/GNU.cmake añade "-O3 -DNDEBUG"/"-g" a estas variables al habilitar cada
# lenguaje, es decir después del toolchain file. Se vacían aquí para que el nivel de
# optimización lo fije únicamente rv32imc_flags y no quede un -O3 anulado en silencio.
foreach(_lang C CXX ASM)
    set(CMAKE_${_lang}_FLAGS_DEBUG "")
    set(CMAKE_${_lang}_FLAGS_RELEASE "")
endforeach()

# Debe corresponder exactamente con neorv32_nexys_a7.vhd de la rama "aplicacion".
set(NEORV32_HOME "${CMAKE_CURRENT_SOURCE_DIR}/.toolchains/neorv32" CACHE PATH "Árbol fuente de NEORV32")
set(NEORV32_VERSION "v1.13.3" CACHE STRING "Etiqueta de NEORV32 que debe coincidir con el RTL sintetizado")
set(NEORV32_RTL_HOME "" CACHE PATH "Árbol RTL usado para el bitstream (opcional, para verificar la versión)")
set(RV32IMC_CPU_HZ "100000000" CACHE STRING "Frecuencia del reloj del procesador (Hz)")
set(NEORV32_IMEM_SIZE "64k" CACHE STRING "IMEM configurada en el bitstream")
set(NEORV32_DMEM_SIZE "32k" CACHE STRING "DMEM configurada en el bitstream")
set(NEORV32_DMEM_BASE "0x80000000" CACHE STRING "Base de DMEM configurada en el SoC")
set(NEORV32_HEAP_SIZE "1k" CACHE STRING "Heap reservado en DMEM (0 = sin malloc/new)")

if(NOT EXISTS "${NEORV32_HOME}/sw/common/neorv32.ld")
    message(FATAL_ERROR
        "No se encontró NEORV32 en ${NEORV32_HOME}. Ejecute scripts/bootstrap-toolchain.ps1.")
endif()

# --- Verificación de versión -------------------------------------------------
# El crt0, el linker script y los drivers deben venir de la misma versión que el RTL.
find_package(Git QUIET)
if(GIT_FOUND AND EXISTS "${NEORV32_HOME}/.git")
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${NEORV32_HOME}" describe --tags
        OUTPUT_VARIABLE NEORV32_ACTUAL_VERSION
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET)
    if(NEORV32_ACTUAL_VERSION AND NOT NEORV32_ACTUAL_VERSION STREQUAL NEORV32_VERSION)
        message(WARNING
            "NEORV32 en ${NEORV32_HOME} es ${NEORV32_ACTUAL_VERSION}, se esperaba ${NEORV32_VERSION}. "
            "Ejecute scripts/bootstrap-toolchain.ps1 para sincronizarlo.")
    endif()
endif()

# Si se indica el árbol RTL, comparar hw_version_c contra la etiqueta de software.
if(NEORV32_RTL_HOME AND EXISTS "${NEORV32_RTL_HOME}/rtl/core/neorv32_package.vhd")
    file(STRINGS "${NEORV32_RTL_HOME}/rtl/core/neorv32_package.vhd" _hw_version_line
        REGEX "hw_version_c[ \t]*:.*x\"[0-9a-fA-F]+\"")
    if(_hw_version_line MATCHES "x\"([0-9a-fA-F]+)\"")
        set(_hw_raw "${CMAKE_MATCH_1}")
        # Nibbles BCD: MM mm pp nn -> vMM.mm.pp (nn = revisión intermedia).
        string(SUBSTRING "${_hw_raw}" 0 2 _hw_major)
        string(SUBSTRING "${_hw_raw}" 2 2 _hw_minor)
        string(SUBSTRING "${_hw_raw}" 4 2 _hw_patch)
        string(SUBSTRING "${_hw_raw}" 6 2 _hw_note)
        math(EXPR _hw_major "${_hw_major}")
        math(EXPR _hw_minor "${_hw_minor}")
        math(EXPR _hw_patch "${_hw_patch}")
        set(_hw_version "v${_hw_major}.${_hw_minor}.${_hw_patch}")
        message(STATUS "NEORV32 RTL: ${_hw_version} (rev ${_hw_note}) / software: ${NEORV32_VERSION}")
        if(NOT _hw_version STREQUAL NEORV32_VERSION)
            message(WARNING
                "El RTL en ${NEORV32_RTL_HOME} es ${_hw_version} pero el software se compila "
                "contra ${NEORV32_VERSION}. Alinee NEORV32_VERSION o vuelva a sintetizar.")
        endif()
    endif()
endif()

# --- Flags comunes -----------------------------------------------------------
add_library(rv32imc_flags INTERFACE)
target_compile_options(rv32imc_flags INTERFACE
    -march=rv32imc_zicsr_zifencei -mabi=ilp32
    -mno-fdiv -mstrict-align -mbranch-cost=10
    -ffunction-sections -fdata-sections -ffp-contract=off
    $<$<CONFIG:Debug>:-Og -g3>
    $<$<CONFIG:Release>:-Os -g0 -DNDEBUG>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions -fno-rtti -fno-threadsafe-statics>
)
# SYSTEM: los encabezados de NEORV32 no deben disparar los avisos del proyecto
# (p. ej. -Wregister de neorv32_intrinsics.h al incluirlo desde C++).
target_include_directories(rv32imc_flags SYSTEM INTERFACE "${NEORV32_HOME}/sw/lib/include")

# --- Drivers de NEORV32 ------------------------------------------------------
# Biblioteca OBJECT (no STATIC): conserva el enlazado incondicional del layout
# anterior, así que newlib sigue resolviendo _sbrk/_write sin depender del orden.
file(GLOB NEORV32_DRIVER_SOURCES CONFIGURE_DEPENDS
    "${NEORV32_HOME}/sw/lib/source/*.c"
)
add_library(neorv32_drivers OBJECT ${NEORV32_DRIVER_SOURCES})
target_link_libraries(neorv32_drivers PRIVATE rv32imc_flags)

# --- Firmware ----------------------------------------------------------------
file(GLOB APP_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/app/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/app/*.cpp"
)

add_executable(${PROJECT_NAME}
    ${APP_SOURCES}
    src/cxxabi.cpp
    ${NEORV32_HOME}/sw/common/crt0.S
)

target_link_libraries(${PROJECT_NAME} PRIVATE rv32imc_flags neorv32_drivers)
target_compile_definitions(${PROJECT_NAME} PRIVATE RV32IMC_CPU_HZ=${RV32IMC_CPU_HZ}u)
target_compile_options(${PROJECT_NAME} PRIVATE -Wall -Wextra)
target_link_options(${PROJECT_NAME} PRIVATE
    -march=rv32imc_zicsr_zifencei -mabi=ilp32
    -nostartfiles
    "-T${NEORV32_HOME}/sw/common/neorv32.ld"
    -Wl,--gc-sections
    "-Wl,--defsym,__neorv32_rom_size=${NEORV32_IMEM_SIZE}"
    "-Wl,--defsym,__neorv32_ram_size=${NEORV32_DMEM_SIZE}"
    "-Wl,--defsym,__neorv32_ram_base=${NEORV32_DMEM_BASE}"
    "-Wl,--defsym,__neorv32_heap_size=${NEORV32_HEAP_SIZE}"
    "-Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.map"
)
target_link_libraries(${PROJECT_NAME} PRIVATE m c gcc)
set_target_properties(${PROJECT_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    SUFFIX ".elf"
)

add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${PROJECT_NAME}> ${CMAKE_CURRENT_BINARY_DIR}/elf.bin
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass
        -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/generate-neorv32-exe.ps1"
        -InputFile "${CMAKE_CURRENT_BINARY_DIR}/elf.bin"
        -OutputFile "${CMAKE_CURRENT_BINARY_DIR}/neorv32_exe.bin"
        -ElfFile "$<TARGET_FILE:${PROJECT_NAME}>"
    COMMAND ${CMAKE_COMMAND}
        "-DOBJDUMP=${CMAKE_OBJDUMP}"
        "-DELF=$<TARGET_FILE:${PROJECT_NAME}>"
        "-DOUTPUT=${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.lst"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/dump.cmake"
    COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${PROJECT_NAME}>
    BYPRODUCTS
        ${CMAKE_CURRENT_BINARY_DIR}/elf.bin
        ${CMAKE_CURRENT_BINARY_DIR}/neorv32_exe.bin
        ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.lst
    COMMENT "Generando ejecutable NEORV32 para el bootloader UART"
)

# Carga por UART: cmake --build --preset debug --target upload
add_custom_target(upload
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass
        -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/upload-uart.ps1"
        -ExeFile "${CMAKE_CURRENT_BINARY_DIR}/neorv32_exe.bin"
    DEPENDS ${PROJECT_NAME}
    USES_TERMINAL
    COMMENT "Cargando neorv32_exe.bin por el bootloader UART"
)
