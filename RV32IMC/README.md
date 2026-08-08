# Entorno NEORV32 para Nexys A7

Proyecto C/C++ para el **NEORV32 RV32IMC** (`-march=rv32imc_zicsr_zifencei`, `-mabi=ilp32`) de la rama [`aplicacion`](https://github.com/mwfigueroa/NexysA7/tree/aplicacion): 100 MHz, IMEM 64 KiB, DMEM 32 KiB en `0x80000000`, bootloader UART y UART0 a 115200 baudios. El WNS es una propiedad de la implementación FPGA, no del firmware.

## Inicio rápido (Windows / PowerShell)

1. Instale localmente la cadena cruzada, Ninja y NEORV32 (solo se descarga en `.toolchains`, ignorado por Git):

   ```powershell
   .\scripts\bootstrap-toolchain.ps1
   ```

2. Configure y compile:

   ```powershell
   cmake --preset debug
   cmake --build --preset debug
   ```

Los artefactos quedan en `build/debug/`: `neorv32_firmware.elf`, `elf.bin`, `neorv32_exe.bin`, `.map` y `.lst`. **El archivo que se carga por UART es `neorv32_exe.bin`**: lleva la cabecera `NEO!`, dirección base, tamaño y checksum que espera el bootloader. La dirección base se toma del punto de entrada del ELF, igual que hace `image_gen` en el flujo oficial.

Coloque su programa en `app/`. Se compilan automáticamente los archivos `.c` y `.cpp`; debe existir exactamente una función `main`. El ejemplo actual está en C++ y usa UART0 y el LED 0.

## Parámetros que coinciden con este SoC

| Parámetro | Valor inicial | Uso |
| --- | ---: | --- |
| `NEORV32_VERSION` | `v1.13.3` | Versión de NEORV32 para crt0, linker script y drivers |
| `NEORV32_IMEM_SIZE` | `64k` | Memoria de instrucciones configurada |
| `NEORV32_DMEM_SIZE` | `32k` | Datos, heap y pila |
| `NEORV32_DMEM_BASE` | `0x80000000` | Base de la RAM del SoC |
| `NEORV32_HEAP_SIZE` | `1k` | Heap para `malloc`/`new` (`0` los deshabilita) |
| `RV32IMC_CPU_HZ` | `100000000` | Valor esperado del reloj; el firmware lo contrasta con SYSINFO al arrancar |

No cambie esos valores sin reconstruir también el bitstream.

### Sincronía entre software y RTL

El crt0, el linker script y la biblioteca de periféricos deben venir de la **misma versión de NEORV32 que el RTL sintetizado**. Hay tres comprobaciones:

- `bootstrap-toolchain.ps1` vuelve a clonar `.toolchains/neorv32` si la etiqueta local no es `NEORV32_VERSION`.
- CMake avisa al configurar si el checkout no coincide con `NEORV32_VERSION`.
- Si indica dónde está el RTL, CMake decodifica `hw_version_c` y lo compara:

  ```powershell
  cmake --preset debug -DNEORV32_RTL_HOME=P:/neorv32
  ```

Además, el firmware imprime por UART0 la versión del hardware (CSR `mimpid`) y el reloj real al arrancar, así que cualquier desfase se ve en el banner.

## Configuraciones

| Preset | Flags | Para qué |
| --- | --- | --- |
| `debug` | `-Og -g3` | Desensamblado y `.lst` legibles |
| `release` | `-Os -g0 -DNDEBUG` | Imagen final |

El SoC se sintetiza con `OCD_EN => false`, así que no hay depurador JTAG: `debug` solo cambia la legibilidad de los símbolos, no permite ejecutar paso a paso.

## Soporte C++

Se compila sin excepciones, RTTI ni `libstdc++`. Los constructores globales funcionan y `new`/`delete` están disponibles siempre que `NEORV32_HEAP_SIZE` sea distinto de cero — con el valor por defecto el heap ocupa 1 KiB de los 32 KiB de DMEM y la pila baja desde `0x80008000`. Los operadores de `src/cxxabi.cpp` son `noexcept` y devuelven `nullptr` si el heap se agota; compruebe el resultado.

## Cargar en FPGA

Tras programar el bitstream y reiniciar físicamente la placa:

```powershell
cmake --build --preset debug --target upload
```

El script `scripts/upload-uart.ps1` autodetecta el puerto si solo hay uno; si hay varios, indíquelo:

```powershell
.\scripts\upload-uart.ps1 -ExeFile build\debug\neorv32_exe.bin -Port COM5
```

Hace la secuencia del bootloader (`u`, transferencia, `e`). Para hacerlo a mano, abra la UART de FTDI B a 115200 8N1 y envíe esos comandos.
