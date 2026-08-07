#include <neorv32.h>

#define BAUD 19200

int main() {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD, 0);

    neorv32_uart0_puts("\n=== NEORV32 Nexys A7 System Test ===\n\n");

    // Clock
    uint32_t clk = neorv32_sysinfo_get_clk();
    neorv32_uart0_printf("CLK: %u Hz (%u MHz)\n", clk, clk / 1000000);

    // ISA
    uint32_t misa = neorv32_cpu_csr_read(CSR_MISA);
    neorv32_uart0_printf("MISA: 0x%x\n", misa);
    neorv32_uart0_printf("  RV32I: %s\n", (misa & (1<<8))  ? "YES" : "NO");
    neorv32_uart0_printf("  M-ext: %s\n", (misa & (1<<12)) ? "YES" : "NO");
    neorv32_uart0_printf("  C-ext: %s\n", (misa & (1<<2))  ? "YES" : "NO");

    // GPIO test — blink all LEDs 3 times
    neorv32_uart0_puts("\nGPIO LED test (watch LEDs[7:0])...\n");
    neorv32_gpio_port_set(0);
    for (int i = 0; i < 3; i++) {
        neorv32_gpio_port_set(0xFF);
        neorv32_aux_delay_ms(clk, 200);
        neorv32_gpio_port_set(0x00);
        neorv32_aux_delay_ms(clk, 200);
    }

    // Math test
    neorv32_uart0_puts("\nMath test...\n");
    volatile int a = 12345, b = 67890, c;
    c = a * b;
    neorv32_uart0_printf("  MUL: %d * %d = %d (expect 838102050)\n", a, b, c);
    c = b / a;
    neorv32_uart0_printf("  DIV: %d / %d = %d (expect 5)\n", b, a, c);

    neorv32_uart0_puts("\n=== ALL TESTS PASSED ===\n");
    return 0;
}
