#include <neorv32.h>

// Aplicación C++ mínima para el NEORV32 de la Nexys A7.
// UART0: 115200 8N1; GPIO[15:0]: LEDs de la placa.

#ifndef RV32IMC_CPU_HZ
#error "Defina RV32IMC_CPU_HZ (lo hace CMakeLists.txt)."
#endif

// GPIO[15:0] están cableados a los LEDs en neorv32_nexys_a7.vhd.
static constexpr uint32_t kLedMask = 0x0000FFFFu;

int main() {
    neorv32_uart0_setup(115200, 0);
    neorv32_uart0_puts("\nNEORV32 RV32IMC: C++ listo.\n");

    // Imprimir la versión del hardware hace visible cualquier desfase entre el
    // bitstream y la versión de NEORV32 con la que se compiló este firmware.
    neorv32_uart0_puts("Hardware: v");
    neorv32_aux_print_hw_version(neorv32_cpu_csr_read(CSR_MIMPID));
    neorv32_uart0_puts("\n");

    // El reloj real lo publica SYSINFO; RV32IMC_CPU_HZ solo debe confirmarlo.
    const uint32_t clock_hz = neorv32_sysinfo_get_clk();
    neorv32_uart0_printf("Reloj: %u Hz\n", clock_hz);
    if (clock_hz != RV32IMC_CPU_HZ) {
        neorv32_uart0_printf("AVISO: RV32IMC_CPU_HZ=%u no coincide con el SoC.\n",
                             static_cast<uint32_t>(RV32IMC_CPU_HZ));
    }

    // El wrapper deja gpio_dir_o sin conectar, pero configurar la dirección
    // mantiene el firmware correcto si el top-level llega a usarla.
    neorv32_gpio_dir_set(kLedMask);

    for (;;) {
        neorv32_gpio_pin_toggle(0);
        neorv32_aux_delay_ms(clock_hz, 500);
    }
}
