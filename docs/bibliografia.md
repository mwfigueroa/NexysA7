# Bibliografía RISC-V / Organización de Computadoras

## En este repo (descarga libre y legal)

**"The RISC-V Reader: An Open Architecture Atlas"** — David Patterson & Andrew Waterman (Strawberry Canyon LLC).

- Archivo: [`the-riscv-reader.pdf`](the-riscv-reader.pdf)
- Distribución oficial gratuita: <https://riscvbook.com>
- La referencia canónica del ISA RV32: registros, instrucciones (IMC incluidas),
  calling convention, modos de direccionamiento. Ideal para seguir el firmware
  del NEORV32 (RV32IMC) y leer el assembly generado (`main.asm` de los firmwares).

## Referencia externa (libro comercial — NO incluir el PDF en repos)

**"Computer Organization and Design: The Hardware/Software Interface, RISC-V Edition"**
— David Patterson & John Hennessy (Morgan Kaufmann / Elsevier).

- Comprar / alquilar: <https://www.elsevier.com/books/computer-organization-and-design-risc-v-edition/patterson/978-0-12-820331-6>
- Copia local de consulta (fuera de git): `P:\NexysA7\Info\patterson_d_hennessy_j_computer_organization_and_design_risc.pdf`
- Cubre pipeline, memoria cache, jerarquía de memoria y mapeo al RV32 — útil para
  entender cómo el RV32IMC se sintetiza en la FPGA y por qué importa el WNS/timing.

## Relacionados

- NEORV32 Data Sheet y User Guide: en el SDK (`P:\neorv32\docs\`), gratis.
- Manual de la Nexys A7: [`nexys-a7-rm.pdf`](nexys-a7-rm.pdf).
- Especificación oficial RISC-V (última revisión): <https://riscv.org/technical/specifications/>
