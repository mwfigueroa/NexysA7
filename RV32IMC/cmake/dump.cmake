if(NOT DEFINED OBJDUMP OR NOT DEFINED ELF OR NOT DEFINED OUTPUT)
    message(FATAL_ERROR "OBJDUMP, ELF y OUTPUT son obligatorios")
endif()
execute_process(
    COMMAND "${OBJDUMP}" -d -S "${ELF}"
    OUTPUT_FILE "${OUTPUT}"
    RESULT_VARIABLE result
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "objdump falló con código ${result}")
endif()
