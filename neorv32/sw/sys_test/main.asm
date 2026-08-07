
main.elf:     file format elf32-littleriscv


Disassembly of section .text:

00000000 <__crt0_entry>:
   0:	f14020f3          	csrr	ra,mhartid
   4:	80002217          	auipc	tp,0x80002
   8:	ffc20213          	addi	tp,tp,-4 # 80002000 <__crt0_stack_top>
   c:	ff027113          	andi	sp,tp,-16
  10:	80000197          	auipc	gp,0x80000
  14:	7f018193          	addi	gp,gp,2032 # 80000800 <__global_pointer$>
  18:	000022b7          	lui	t0,0x2
  1c:	80028293          	addi	t0,t0,-2048 # 1800 <__crt0_copy_data_src_begin+0x998>
  20:	30029073          	csrw	mstatus,t0
  24:	00000317          	auipc	t1,0x0
  28:	15030313          	addi	t1,t1,336 # 174 <__crt0_panic>
  2c:	30531073          	csrw	mtvec,t1
  30:	30401073          	csrw	mie,zero
  34:	00001397          	auipc	t2,0x1
  38:	e3438393          	addi	t2,t2,-460 # e68 <__crt0_copy_data_src_begin>
  3c:	80000417          	auipc	s0,0x80000
  40:	fc440413          	addi	s0,s0,-60 # 80000000 <__neorv32_rte_vector_lut>
  44:	80000497          	auipc	s1,0x80000
  48:	fbc48493          	addi	s1,s1,-68 # 80000000 <__neorv32_rte_vector_lut>
  4c:	80000517          	auipc	a0,0x80000
  50:	fb450513          	addi	a0,a0,-76 # 80000000 <__neorv32_rte_vector_lut>
  54:	80000597          	auipc	a1,0x80000
  58:	0ac58593          	addi	a1,a1,172 # 80000100 <__crt0_bss_end>
  5c:	4601                	li	a2,0
  5e:	4681                	li	a3,0
  60:	4701                	li	a4,0
  62:	4781                	li	a5,0
  64:	4801                	li	a6,0
  66:	4881                	li	a7,0
  68:	4901                	li	s2,0
  6a:	4981                	li	s3,0
  6c:	4a01                	li	s4,0
  6e:	4a81                	li	s5,0
  70:	4b01                	li	s6,0
  72:	4b81                	li	s7,0
  74:	4c01                	li	s8,0
  76:	4c81                	li	s9,0
  78:	4d01                	li	s10,0
  7a:	4d81                	li	s11,0
  7c:	4e01                	li	t3,0
  7e:	4e81                	li	t4,0
  80:	4f01                	li	t5,0
  82:	4f81                	li	t6,0

00000084 <__crt0_smp_check>:
  84:	04008263          	beqz	ra,c8 <__crt0_data_copy>

00000088 <__crt0_smp_setup>:
  88:	00000797          	auipc	a5,0x0
  8c:	01c78793          	addi	a5,a5,28 # a4 <__crt0_smp_wakeup>
  90:	30579073          	csrw	mtvec,a5
  94:	30445073          	csrwi	mie,8
  98:	30046073          	csrsi	mstatus,8

0000009c <__crt0_smp_sleep>:
  9c:	10500073          	wfi
  a0:	bff5                	j	9c <__crt0_smp_sleep>
  a2:	0001                	nop

000000a4 <__crt0_smp_wakeup>:
  a4:	00000797          	auipc	a5,0x0
  a8:	0d078793          	addi	a5,a5,208 # 174 <__crt0_panic>
  ac:	30579073          	csrw	mtvec,a5
  b0:	30405073          	csrwi	mie,0
  b4:	fff44737          	lui	a4,0xfff44
  b8:	00872103          	lw	sp,8(a4) # fff44008 <__crt0_stack_top+0x7ff42008>
  bc:	4750                	lw	a2,12(a4)
  be:	fff40737          	lui	a4,0xfff40
  c2:	00072223          	sw	zero,4(a4) # fff40004 <__crt0_stack_top+0x7ff3e004>
  c6:	a881                	j	116 <__crt0_main_entry>

000000c8 <__crt0_data_copy>:
  c8:	00838b63          	beq	t2,s0,de <__crt0_bss_clear>
  cc:	00945963          	bge	s0,s1,de <__crt0_bss_clear>

000000d0 <__crt0_data_copy_loop>:
  d0:	0003a783          	lw	a5,0(t2)
  d4:	c01c                	sw	a5,0(s0)
  d6:	0391                	addi	t2,t2,4
  d8:	0411                	addi	s0,s0,4
  da:	fe944be3          	blt	s0,s1,d0 <__crt0_data_copy_loop>

000000de <__crt0_bss_clear>:
  de:	00b55763          	bge	a0,a1,ec <__crt0_bss_clear_end>

000000e2 <__crt0_bss_clear_loop>:
  e2:	00052023          	sw	zero,0(a0)
  e6:	0511                	addi	a0,a0,4
  e8:	feb54de3          	blt	a0,a1,e2 <__crt0_bss_clear_loop>

000000ec <__crt0_bss_clear_end>:
// (t0-t6, a0-a7, ra). Loop counters use s0/s1 (callee-saved), which are
// preserved by the called functions according to the RISC-V calling convention.
// ************************************************************************************************
#ifndef MAKE_BOOTLOADER
__crt0_constructors_primary:
  la    x8, __init_array_start
  ec:	00001417          	auipc	s0,0x1
  f0:	88040413          	addi	s0,s0,-1920 # 96c <__fini_array_end>
  la    x9, __init_array_end
  f4:	00001497          	auipc	s1,0x1
  f8:	87848493          	addi	s1,s1,-1928 # 96c <__fini_array_end>

000000fc <__crt0_constructors>:

__crt0_constructors:
  bge   x8, x9, __crt0_constructors_end  // skip if empty
  fc:	00945963          	bge	s0,s1,10e <__crt0_constructors_end>

00000100 <__crt0_constructors_loop>:

__crt0_constructors_loop:
  lw    x1, 0(x8)
 100:	00042083          	lw	ra,0(s0)
  jalr  x1, 0(x1) // call constructor function; put return address in ra
 104:	000080e7          	jalr	ra
  addi  x8, x8, 4
 108:	0411                	addi	s0,s0,4
  blt   x8, x9, __crt0_constructors_loop
 10a:	fe944be3          	blt	s0,s1,100 <__crt0_constructors_loop>

0000010e <__crt0_constructors_end>:

// ************************************************************************************************
// Setup arguments and call main function.
// ************************************************************************************************
__crt0_main_primary:
  la    x12, main         // primary core's (core0) entry point (#1169)
 10e:	00000617          	auipc	a2,0x0
 112:	06e60613          	addi	a2,a2,110 # 17c <main>

00000116 <__crt0_main_entry>:
__crt0_main_entry:
  fence                   // synchronize loads/stores
 116:	0ff0000f          	fence
  fence.i                 // synchronize instruction fetch
 11a:	0000100f          	fence.i
  li    x10, 0            // x10 = a0 = argc = 0
 11e:	4501                	li	a0,0
  li    x11, 0            // x11 = a1 = argv = 0
 120:	4581                	li	a1,0
  jalr  x1, x12           // call actual main function
 122:	000600e7          	jalr	a2

00000126 <__crt0_main_exit>:

.global __crt0_main_exit
__crt0_main_exit:         // main's "return" and "exit" will arrive here
  csrci mstatus, 1 << 3   // disable machine-level interrupts
 126:	30047073          	csrci	mstatus,8
  csrw  mie, zero         // disable all interrupt sources
 12a:	30401073          	csrw	mie,zero
  la    x11, __crt0_panic // re-install default crt0 trap handler
 12e:	00000597          	auipc	a1,0x0
 132:	04658593          	addi	a1,a1,70 # 174 <__crt0_panic>
  csrw  mtvec, x11
 136:	30559073          	csrw	mtvec,a1
  csrw  mscratch, x10     // backup main's return code to mscratch (for debugger or destructors)
 13a:	34051073          	csrw	mscratch,a0

0000013e <__crt0_destructors_primary>:
// (t0-t6, a0-a7, ra). Loop counters use s0/s1 (callee-saved), which are
// preserved by the called functions according to the RISC-V calling convention.
// ************************************************************************************************
#ifndef MAKE_BOOTLOADER
__crt0_destructors_primary:
  csrr  x8, mhartid
 13e:	f1402473          	csrr	s0,mhartid
  bnez  x8, __crt0_destructors_end // execute destructors only on core 0
 142:	e015                	bnez	s0,166 <__crt0_destructors_end>

  la    x8, __fini_array_start
 144:	00001417          	auipc	s0,0x1
 148:	82840413          	addi	s0,s0,-2008 # 96c <__fini_array_end>
  la    x9, __fini_array_end
 14c:	00001497          	auipc	s1,0x1
 150:	82048493          	addi	s1,s1,-2016 # 96c <__fini_array_end>

00000154 <__crt0_destructors>:

__crt0_destructors:
  bge   x8, x9, __crt0_destructors_end
 154:	00945963          	bge	s0,s1,166 <__crt0_destructors_end>

00000158 <__crt0_destructors_loop>:

__crt0_destructors_loop:
  lw    x1, 0(x8)
 158:	00042083          	lw	ra,0(s0)
  jalr  x1, 0(x1)                  // call destructor function; put return address in ra
 15c:	000080e7          	jalr	ra
  addi  x8, x8, 4
 160:	0411                	addi	s0,s0,4
  blt   x8, x9, __crt0_destructors_loop
 162:	fe944be3          	blt	s0,s1,158 <__crt0_destructors_loop>

00000166 <__crt0_destructors_end>:
// ************************************************************************************************
// Halt CPU. Bootloader should never return; if it does -> panic.
// ************************************************************************************************
#ifndef MAKE_BOOTLOADER
__crt0_halting:
  csrr x8, mhartid
 166:	f1402473          	csrr	s0,mhartid
  bnez x8, __crt0_halt
 16a:	e011                	bnez	s0,16e <__crt0_halt>

0000016c <__crt0_halt_primary>:

.global __crt0_halt_primary
__crt0_halt_primary:
  ebreak     // execution done; try to transfer control to external debugger; otherwise -> panic
 16c:	9002                	ebreak

0000016e <__crt0_halt>:

.global __crt0_halt
__crt0_halt: // same code as trap handler but with different label/address to track origin
  wfi
 16e:	10500073          	wfi
  j __crt0_halt
 172:	bff5                	j	16e <__crt0_halt>

00000174 <__crt0_panic>:
// ************************************************************************************************
.balign 4     // trap handler has to be 32-bit aligned
.option norvc // no compressed instruction to make this valid code on any platform configuration
.global __crt0_panic
__crt0_panic:
  wfi
 174:	10500073          	wfi
  j __crt0_panic
 178:	ffdff06f          	j	174 <__crt0_panic>

0000017c <main>:
#include <neorv32.h>

#define BAUD 19200

int main() {
 17c:	1101                	addi	sp,sp,-32
 17e:	ce06                	sw	ra,28(sp)
 180:	ca26                	sw	s1,20(sp)
 182:	cc22                	sw	s0,24(sp)
    neorv32_rte_setup();
 184:	2b19                	jal	69a <neorv32_rte_setup>
    neorv32_uart0_setup(BAUD, 0);
 186:	6595                	lui	a1,0x5
 188:	4601                	li	a2,0
 18a:	b0058593          	addi	a1,a1,-1280 # 4b00 <__neorv32_rom_size+0xb00>
 18e:	fff50537          	lui	a0,0xfff50
 192:	2341                	jal	712 <neorv32_uart_setup>

    neorv32_uart0_puts("\n=== NEORV32 Nexys A7 System Test ===\n\n");
 194:	6585                	lui	a1,0x1
 196:	97858593          	addi	a1,a1,-1672 # 978 <__fini_array_end+0xc>
 19a:	fff50537          	lui	a0,0xfff50
 19e:	23f9                	jal	76c <neorv32_uart_puts>
/**********************************************************************//**
 * Get current processor clock frequency.
 * @return Clock frequency in Hz.
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) neorv32_sysinfo_get_clk(void) {
  return NEORV32_SYSINFO->CLK;
 1a0:	7781                	lui	a5,0xfffe0
 1a2:	4384                	lw	s1,0(a5)

    // Clock
    uint32_t clk = neorv32_sysinfo_get_clk();
    neorv32_uart0_printf("CLK: %u Hz (%u MHz)\n", clk, clk / 1000000);
 1a4:	000f46b7          	lui	a3,0xf4
 1a8:	24068693          	addi	a3,a3,576 # f4240 <__neorv32_rom_size+0xf0240>
 1ac:	02d4d6b3          	divu	a3,s1,a3
 1b0:	6585                	lui	a1,0x1
 1b2:	8626                	mv	a2,s1
 1b4:	9a058593          	addi	a1,a1,-1632 # 9a0 <__fini_array_end+0x34>
 1b8:	fff50537          	lui	a0,0xfff50
 1bc:	736000ef          	jal	8f2 <neorv32_uart_printf>
 * @return Read data (uint32_t).
 **************************************************************************/
inline uint32_t __attribute__ ((always_inline)) neorv32_cpu_csr_read(const int csr_id) {

  uint32_t csr_data;
  asm volatile ("csrr %[dst], %[id]" : [dst] "=r" (csr_data) : [id] "i" (csr_id));
 1c0:	30102473          	csrr	s0,misa

    // ISA
    uint32_t misa = neorv32_cpu_csr_read(CSR_MISA);
    neorv32_uart0_printf("MISA: 0x%x\n", misa);
 1c4:	6585                	lui	a1,0x1
 1c6:	8622                	mv	a2,s0
 1c8:	9b858593          	addi	a1,a1,-1608 # 9b8 <__fini_array_end+0x4c>
 1cc:	fff50537          	lui	a0,0xfff50
 1d0:	722000ef          	jal	8f2 <neorv32_uart_printf>
    neorv32_uart0_printf("  RV32I: %s\n", (misa & (1<<8))  ? "YES" : "NO");
 1d4:	10047793          	andi	a5,s0,256
 1d8:	0e078563          	beqz	a5,2c2 <main+0x146>
 1dc:	6605                	lui	a2,0x1
 1de:	96c60613          	addi	a2,a2,-1684 # 96c <__fini_array_end>
 1e2:	6585                	lui	a1,0x1
 1e4:	9c458593          	addi	a1,a1,-1596 # 9c4 <__fini_array_end+0x58>
 1e8:	fff50537          	lui	a0,0xfff50
 1ec:	706000ef          	jal	8f2 <neorv32_uart_printf>
    neorv32_uart0_printf("  M-ext: %s\n", (misa & (1<<12)) ? "YES" : "NO");
 1f0:	01341793          	slli	a5,s0,0x13
 1f4:	0c07db63          	bgez	a5,2ca <main+0x14e>
 1f8:	6605                	lui	a2,0x1
 1fa:	96c60613          	addi	a2,a2,-1684 # 96c <__fini_array_end>
 1fe:	6585                	lui	a1,0x1
 200:	9d458593          	addi	a1,a1,-1580 # 9d4 <__fini_array_end+0x68>
 204:	fff50537          	lui	a0,0xfff50
    neorv32_uart0_printf("  C-ext: %s\n", (misa & (1<<2))  ? "YES" : "NO");
 208:	8811                	andi	s0,s0,4
    neorv32_uart0_printf("  M-ext: %s\n", (misa & (1<<12)) ? "YES" : "NO");
 20a:	6e8000ef          	jal	8f2 <neorv32_uart_printf>
    neorv32_uart0_printf("  C-ext: %s\n", (misa & (1<<2))  ? "YES" : "NO");
 20e:	0c040263          	beqz	s0,2d2 <main+0x156>
 212:	6605                	lui	a2,0x1
 214:	96c60613          	addi	a2,a2,-1684 # 96c <__fini_array_end>
 218:	6585                	lui	a1,0x1
 21a:	9e458593          	addi	a1,a1,-1564 # 9e4 <__fini_array_end+0x78>
 21e:	fff50537          	lui	a0,0xfff50
 222:	6d0000ef          	jal	8f2 <neorv32_uart_printf>

    // GPIO test — blink all LEDs 3 times
    neorv32_uart0_puts("\nGPIO LED test (watch LEDs[7:0])...\n");
 226:	6585                	lui	a1,0x1
 228:	9f458593          	addi	a1,a1,-1548 # 9f4 <__fini_array_end+0x88>
 22c:	fff50537          	lui	a0,0xfff50
 230:	2b35                	jal	76c <neorv32_uart_puts>
    neorv32_gpio_port_set(0);
 232:	4501                	li	a0,0
 234:	2291                	jal	378 <neorv32_gpio_port_set>
 236:	440d                	li	s0,3
    for (int i = 0; i < 3; i++) {
        neorv32_gpio_port_set(0xFF);
 238:	0ff00513          	li	a0,255
 23c:	2a35                	jal	378 <neorv32_gpio_port_set>
        neorv32_aux_delay_ms(clk, 200);
 23e:	0c800593          	li	a1,200
 242:	8526                	mv	a0,s1
 244:	2859                	jal	2da <neorv32_aux_delay_ms>
        neorv32_gpio_port_set(0x00);
 246:	4501                	li	a0,0
 248:	2a05                	jal	378 <neorv32_gpio_port_set>
        neorv32_aux_delay_ms(clk, 200);
 24a:	0c800593          	li	a1,200
 24e:	8526                	mv	a0,s1
    for (int i = 0; i < 3; i++) {
 250:	147d                	addi	s0,s0,-1
        neorv32_aux_delay_ms(clk, 200);
 252:	2061                	jal	2da <neorv32_aux_delay_ms>
    for (int i = 0; i < 3; i++) {
 254:	f075                	bnez	s0,238 <main+0xbc>
    }

    // Math test
    neorv32_uart0_puts("\nMath test...\n");
 256:	6585                	lui	a1,0x1
 258:	a1c58593          	addi	a1,a1,-1508 # a1c <__fini_array_end+0xb0>
 25c:	fff50537          	lui	a0,0xfff50
 260:	2331                	jal	76c <neorv32_uart_puts>
    volatile int a = 12345, b = 67890, c;
 262:	678d                	lui	a5,0x3
 264:	03978793          	addi	a5,a5,57 # 3039 <__neorv32_ram_size+0x1039>
 268:	c23e                	sw	a5,4(sp)
 26a:	67c5                	lui	a5,0x11
 26c:	93278793          	addi	a5,a5,-1742 # 10932 <__neorv32_rom_size+0xc932>
 270:	c43e                	sw	a5,8(sp)
    c = a * b;
 272:	4792                	lw	a5,4(sp)
 274:	4722                	lw	a4,8(sp)
    neorv32_uart0_printf("  MUL: %d * %d = %d (expect 838102050)\n", a, b, c);
 276:	6585                	lui	a1,0x1
 278:	a2c58593          	addi	a1,a1,-1492 # a2c <__fini_array_end+0xc0>
    c = a * b;
 27c:	02e787b3          	mul	a5,a5,a4
    neorv32_uart0_printf("  MUL: %d * %d = %d (expect 838102050)\n", a, b, c);
 280:	fff50537          	lui	a0,0xfff50
    c = a * b;
 284:	c63e                	sw	a5,12(sp)
    neorv32_uart0_printf("  MUL: %d * %d = %d (expect 838102050)\n", a, b, c);
 286:	4612                	lw	a2,4(sp)
 288:	46a2                	lw	a3,8(sp)
 28a:	4732                	lw	a4,12(sp)
 28c:	259d                	jal	8f2 <neorv32_uart_printf>
    c = b / a;
 28e:	47a2                	lw	a5,8(sp)
 290:	4712                	lw	a4,4(sp)
    neorv32_uart0_printf("  DIV: %d / %d = %d (expect 5)\n", b, a, c);
 292:	6585                	lui	a1,0x1
 294:	a5458593          	addi	a1,a1,-1452 # a54 <__fini_array_end+0xe8>
    c = b / a;
 298:	02e7c7b3          	div	a5,a5,a4
    neorv32_uart0_printf("  DIV: %d / %d = %d (expect 5)\n", b, a, c);
 29c:	fff50537          	lui	a0,0xfff50
    c = b / a;
 2a0:	c63e                	sw	a5,12(sp)
    neorv32_uart0_printf("  DIV: %d / %d = %d (expect 5)\n", b, a, c);
 2a2:	4622                	lw	a2,8(sp)
 2a4:	4692                	lw	a3,4(sp)
 2a6:	4732                	lw	a4,12(sp)
 2a8:	25a9                	jal	8f2 <neorv32_uart_printf>

    neorv32_uart0_puts("\n=== ALL TESTS PASSED ===\n");
 2aa:	6585                	lui	a1,0x1
 2ac:	fff50537          	lui	a0,0xfff50
 2b0:	a7458593          	addi	a1,a1,-1420 # a74 <__fini_array_end+0x108>
 2b4:	2965                	jal	76c <neorv32_uart_puts>
    return 0;
}
 2b6:	40f2                	lw	ra,28(sp)
 2b8:	4462                	lw	s0,24(sp)
 2ba:	44d2                	lw	s1,20(sp)
 2bc:	4501                	li	a0,0
 2be:	6105                	addi	sp,sp,32
 2c0:	8082                	ret
    neorv32_uart0_printf("  RV32I: %s\n", (misa & (1<<8))  ? "YES" : "NO");
 2c2:	6605                	lui	a2,0x1
 2c4:	97060613          	addi	a2,a2,-1680 # 970 <__fini_array_end+0x4>
 2c8:	bf29                	j	1e2 <main+0x66>
    neorv32_uart0_printf("  M-ext: %s\n", (misa & (1<<12)) ? "YES" : "NO");
 2ca:	6605                	lui	a2,0x1
 2cc:	97060613          	addi	a2,a2,-1680 # 970 <__fini_array_end+0x4>
 2d0:	b73d                	j	1fe <main+0x82>
    neorv32_uart0_printf("  C-ext: %s\n", (misa & (1<<2))  ? "YES" : "NO");
 2d2:	6605                	lui	a2,0x1
 2d4:	97060613          	addi	a2,a2,-1680 # 970 <__fini_array_end+0x4>
 2d8:	b781                	j	218 <main+0x9c>

000002da <neorv32_aux_delay_ms>:
 * @param[in] time_ms Time in ms to wait (unsigned 32-bit).
 **************************************************************************/
void neorv32_aux_delay_ms(uint32_t clock_hz, uint32_t time_ms) {

  // clock ticks per ms (avoid division, therefore shift by 10 instead dividing by 1000)
  uint32_t ms_ticks = clock_hz >> 10;
 2da:	8129                	srli	a0,a0,0xa
  uint64_t wait_cycles = ((uint64_t)ms_ticks) * ((uint64_t)time_ms);
 2dc:	02b507b3          	mul	a5,a0,a1
 2e0:	02b53533          	mulhu	a0,a0,a1
  // divide by clock cycles per iteration of the ASM loop (16 = shift by 4)
  uint32_t iterations = (uint32_t)(wait_cycles >> 4);
 2e4:	8391                	srli	a5,a5,0x4
 2e6:	0572                	slli	a0,a0,0x1c
 2e8:	8fc9                	or	a5,a5,a0

000002ea <__neorv32_aux_delay_ms_start>:

  asm volatile (
 2ea:	c791                	beqz	a5,2f6 <__neorv32_aux_delay_ms_end>
 2ec:	00001563          	bnez	zero,2f6 <__neorv32_aux_delay_ms_end>
 2f0:	17fd                	addi	a5,a5,-1
 2f2:	0001                	nop
 2f4:	bfdd                	j	2ea <__neorv32_aux_delay_ms_start>

000002f6 <__neorv32_aux_delay_ms_end>:
    " nop                                             \n" // 2 cycles
    " j    __neorv32_aux_delay_ms_start               \n" // 6 cycles
    " __neorv32_aux_delay_ms_end:                     \n"
    : [cnt_w] "=r" (iterations) : [cnt_r] "r" (iterations)
  );
}
 2f6:	8082                	ret

000002f8 <neorv32_aux_itoa>:
 *
 * @param[in,out] buffer Pointer to array for the result string [33 chars].
 * @param[in] num Number to convert.
 * @param[in] base Base of number representation (2..16).
 **************************************************************************/
void neorv32_aux_itoa(char *buffer, uint32_t num, uint32_t base) {
 2f8:	715d                	addi	sp,sp,-80
 2fa:	c0ca                	sw	s2,64(sp)
 2fc:	892e                	mv	s2,a1

  const char digits[16] = {'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'};
 2fe:	6585                	lui	a1,0x1
void neorv32_aux_itoa(char *buffer, uint32_t num, uint32_t base) {
 300:	c4a2                	sw	s0,72(sp)
 302:	c2a6                	sw	s1,68(sp)
  const char digits[16] = {'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'};
 304:	a9058593          	addi	a1,a1,-1392 # a90 <__fini_array_end+0x124>
void neorv32_aux_itoa(char *buffer, uint32_t num, uint32_t base) {
 308:	84b2                	mv	s1,a2
 30a:	842a                	mv	s0,a0
  const char digits[16] = {'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'};
 30c:	4641                	li	a2,16
 30e:	0068                	addi	a0,sp,12
void neorv32_aux_itoa(char *buffer, uint32_t num, uint32_t base) {
 310:	c686                	sw	ra,76(sp)
  const char digits[16] = {'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'};
 312:	2bf5                	jal	90e <memcpy>
  char *tmp_ptr = 0;
  unsigned int i = 0;

  // prevent uninitialized stack bytes
  for (i=0; i<sizeof(tmp); i++) {
    tmp[i] = 0;
 314:	02400613          	li	a2,36
 318:	4581                	li	a1,0
 31a:	0868                	addi	a0,sp,28
 31c:	2d19                	jal	932 <memset>
  }

  if ((base < 2) || (base > 16)) { // invalid base?
 31e:	ffe48693          	addi	a3,s1,-2
 322:	4739                	li	a4,14
 324:	03f10793          	addi	a5,sp,63
 328:	00d77a63          	bgeu	a4,a3,33c <neorv32_aux_itoa+0x44>
      buffer++;
    }
  }

  // terminate result string
  *buffer = '\0';
 32c:	00040023          	sb	zero,0(s0)
}
 330:	40b6                	lw	ra,76(sp)
 332:	4426                	lw	s0,72(sp)
 334:	4496                	lw	s1,68(sp)
 336:	4906                	lw	s2,64(sp)
 338:	6161                	addi	sp,sp,80
 33a:	8082                	ret
    *tmp_ptr = digits[num%base];
 33c:	02997733          	remu	a4,s2,s1
    tmp_ptr--;
 340:	17fd                	addi	a5,a5,-1
    *tmp_ptr = digits[num%base];
 342:	04070713          	addi	a4,a4,64
 346:	970a                	add	a4,a4,sp
 348:	fcc74703          	lbu	a4,-52(a4)
 34c:	00e78023          	sb	a4,0(a5)
    num /= base;
 350:	874a                	mv	a4,s2
 352:	02995933          	divu	s2,s2,s1
  } while (num != 0);
 356:	fe9773e3          	bgeu	a4,s1,33c <neorv32_aux_itoa+0x44>
  for (i=0; i<sizeof(tmp); i++) {
 35a:	4781                	li	a5,0
 35c:	02400693          	li	a3,36
    if (tmp[i] != '\0') {
 360:	0878                	addi	a4,sp,28
 362:	973e                	add	a4,a4,a5
 364:	00074703          	lbu	a4,0(a4)
 368:	c701                	beqz	a4,370 <neorv32_aux_itoa+0x78>
      *buffer = tmp[i];
 36a:	00e40023          	sb	a4,0(s0)
      buffer++;
 36e:	0405                	addi	s0,s0,1
  for (i=0; i<sizeof(tmp); i++) {
 370:	0785                	addi	a5,a5,1
 372:	fed797e3          	bne	a5,a3,360 <neorv32_aux_itoa+0x68>
 376:	bf5d                	j	32c <neorv32_aux_itoa+0x34>

00000378 <neorv32_gpio_port_set>:
 *
 * @param[in] pin_mask New output port value (32-bit).
 **************************************************************************/
void neorv32_gpio_port_set(uint32_t pin_mask) {

  NEORV32_GPIO->PORT_OUT = pin_mask;
 378:	fffc07b7          	lui	a5,0xfffc0
 37c:	c3c8                	sw	a0,4(a5)
}
 37e:	8082                	ret

00000380 <__neorv32_rte_core>:
/**********************************************************************//**
 * Core of the NEORV32 RTE (first-level trap handler).
 **************************************************************************/
static void __attribute__((naked,aligned(4))) __neorv32_rte_core(void) {

  asm volatile (
 380:	34011073          	csrw	mscratch,sp
 384:	7119                	addi	sp,sp,-128
 386:	c206                	sw	ra,4(sp)
 388:	340110f3          	csrrw	ra,mscratch,sp
 38c:	c406                	sw	ra,8(sp)
 38e:	c60e                	sw	gp,12(sp)
 390:	c812                	sw	tp,16(sp)
 392:	ca16                	sw	t0,20(sp)
 394:	cc1a                	sw	t1,24(sp)
 396:	ce1e                	sw	t2,28(sp)
 398:	d022                	sw	s0,32(sp)
 39a:	d226                	sw	s1,36(sp)
 39c:	d42a                	sw	a0,40(sp)
 39e:	d62e                	sw	a1,44(sp)
 3a0:	d832                	sw	a2,48(sp)
 3a2:	da36                	sw	a3,52(sp)
 3a4:	dc3a                	sw	a4,56(sp)
 3a6:	de3e                	sw	a5,60(sp)
 3a8:	c0c2                	sw	a6,64(sp)
 3aa:	c2c6                	sw	a7,68(sp)
 3ac:	c4ca                	sw	s2,72(sp)
 3ae:	c6ce                	sw	s3,76(sp)
 3b0:	c8d2                	sw	s4,80(sp)
 3b2:	cad6                	sw	s5,84(sp)
 3b4:	ccda                	sw	s6,88(sp)
 3b6:	cede                	sw	s7,92(sp)
 3b8:	d0e2                	sw	s8,96(sp)
 3ba:	d2e6                	sw	s9,100(sp)
 3bc:	d4ea                	sw	s10,104(sp)
 3be:	d6ee                	sw	s11,108(sp)
 3c0:	d8f2                	sw	t3,112(sp)
 3c2:	daf6                	sw	t4,116(sp)
 3c4:	dcfa                	sw	t5,120(sp)
 3c6:	defe                	sw	t6,124(sp)
 3c8:	34202573          	csrr	a0,mcause
 3cc:	01855593          	srli	a1,a0,0x18
 3d0:	01f57613          	andi	a2,a0,31
 3d4:	060a                	slli	a2,a2,0x2
 3d6:	962e                	add	a2,a2,a1
 3d8:	80000517          	auipc	a0,0x80000
 3dc:	c2850513          	addi	a0,a0,-984 # 80000000 <__neorv32_rte_vector_lut>
 3e0:	962a                	add	a2,a2,a0
 3e2:	4210                	lw	a2,0(a2)
 3e4:	000600e7          	jalr	a2
 3e8:	34202573          	csrr	a0,mcause
 3ec:	02054163          	bltz	a0,40e <__neorv32_rte_core+0x8e>
 3f0:	4585                	li	a1,1
 3f2:	00b50e63          	beq	a0,a1,40e <__neorv32_rte_core+0x8e>
 3f6:	341025f3          	csrr	a1,mepc
 3fa:	00458513          	addi	a0,a1,4
 3fe:	0005c583          	lbu	a1,0(a1)
 402:	898d                	andi	a1,a1,3
 404:	15f5                	addi	a1,a1,-3
 406:	c191                	beqz	a1,40a <__neorv32_rte_core+0x8a>
 408:	1579                	addi	a0,a0,-2
 40a:	34151073          	csrw	mepc,a0
 40e:	4092                	lw	ra,4(sp)
 410:	41b2                	lw	gp,12(sp)
 412:	4242                	lw	tp,16(sp)
 414:	42d2                	lw	t0,20(sp)
 416:	4362                	lw	t1,24(sp)
 418:	43f2                	lw	t2,28(sp)
 41a:	5402                	lw	s0,32(sp)
 41c:	5492                	lw	s1,36(sp)
 41e:	5522                	lw	a0,40(sp)
 420:	55b2                	lw	a1,44(sp)
 422:	5642                	lw	a2,48(sp)
 424:	56d2                	lw	a3,52(sp)
 426:	5762                	lw	a4,56(sp)
 428:	57f2                	lw	a5,60(sp)
 42a:	4806                	lw	a6,64(sp)
 42c:	4896                	lw	a7,68(sp)
 42e:	4926                	lw	s2,72(sp)
 430:	49b6                	lw	s3,76(sp)
 432:	4a46                	lw	s4,80(sp)
 434:	4ad6                	lw	s5,84(sp)
 436:	4b66                	lw	s6,88(sp)
 438:	4bf6                	lw	s7,92(sp)
 43a:	5c06                	lw	s8,96(sp)
 43c:	5c96                	lw	s9,100(sp)
 43e:	5d26                	lw	s10,104(sp)
 440:	5db6                	lw	s11,108(sp)
 442:	5e46                	lw	t3,112(sp)
 444:	5ed6                	lw	t4,116(sp)
 446:	5f66                	lw	t5,120(sp)
 448:	5ff6                	lw	t6,124(sp)
 44a:	4122                	lw	sp,8(sp)
 44c:	30200073          	mret
 450:	0000                	unimp

00000452 <__neorv32_rte_puth>:
static void __neorv32_rte_puth(uint32_t num) {
 452:	7179                	addi	sp,sp,-48
  const char hex[] = "0123456789ABCDEF";
 454:	6585                	lui	a1,0x1
static void __neorv32_rte_puth(uint32_t num) {
 456:	d226                	sw	s1,36(sp)
  const char hex[] = "0123456789ABCDEF";
 458:	4645                	li	a2,17
static void __neorv32_rte_puth(uint32_t num) {
 45a:	84aa                	mv	s1,a0
  const char hex[] = "0123456789ABCDEF";
 45c:	aa458593          	addi	a1,a1,-1372 # aa4 <__fini_array_end+0x138>
 460:	0068                	addi	a0,sp,12
static void __neorv32_rte_puth(uint32_t num) {
 462:	d606                	sw	ra,44(sp)
 464:	d422                	sw	s0,40(sp)
 466:	d04a                	sw	s2,32(sp)
  const char hex[] = "0123456789ABCDEF";
 468:	215d                	jal	90e <memcpy>
  if (neorv32_uart0_available() != 0) { // cannot output anything if UART0 is not implemented
 46a:	fff50537          	lui	a0,0xfff50
 46e:	2cad                	jal	6e8 <neorv32_uart_available>
 470:	c91d                	beqz	a0,4a6 <__neorv32_rte_puth+0x54>
    neorv32_uart_putc(NEORV32_UART0, '0');
 472:	03000593          	li	a1,48
 476:	fff50537          	lui	a0,0xfff50
 47a:	24d5                	jal	75e <neorv32_uart_putc>
    neorv32_uart_putc(NEORV32_UART0, 'x');
 47c:	07800593          	li	a1,120
 480:	fff50537          	lui	a0,0xfff50
 484:	2ce9                	jal	75e <neorv32_uart_putc>
 486:	4471                	li	s0,28
    for (i=0; i<8; i++) {
 488:	5971                	li	s2,-4
      neorv32_uart_putc(NEORV32_UART0, hex[(num >> (28 - 4*i)) & 0xFu]);
 48a:	0084d7b3          	srl	a5,s1,s0
 48e:	8bbd                	andi	a5,a5,15
 490:	02078793          	addi	a5,a5,32 # fffc0020 <__crt0_stack_top+0x7ffbe020>
 494:	978a                	add	a5,a5,sp
 496:	fec7c583          	lbu	a1,-20(a5)
 49a:	fff50537          	lui	a0,0xfff50
    for (i=0; i<8; i++) {
 49e:	1471                	addi	s0,s0,-4
      neorv32_uart_putc(NEORV32_UART0, hex[(num >> (28 - 4*i)) & 0xFu]);
 4a0:	2c7d                	jal	75e <neorv32_uart_putc>
    for (i=0; i<8; i++) {
 4a2:	ff2414e3          	bne	s0,s2,48a <__neorv32_rte_puth+0x38>
}
 4a6:	50b2                	lw	ra,44(sp)
 4a8:	5422                	lw	s0,40(sp)
 4aa:	5492                	lw	s1,36(sp)
 4ac:	5902                	lw	s2,32(sp)
 4ae:	6145                	addi	sp,sp,48
 4b0:	8082                	ret

000004b2 <__neorv32_rte_puts>:
static void __neorv32_rte_puts(const char *s) {
 4b2:	1101                	addi	sp,sp,-32
 4b4:	c62a                	sw	a0,12(sp)
  if (neorv32_uart0_available() != 0) { // cannot output anything if UART0 is not implemented
 4b6:	fff50537          	lui	a0,0xfff50
static void __neorv32_rte_puts(const char *s) {
 4ba:	ce06                	sw	ra,28(sp)
  if (neorv32_uart0_available() != 0) { // cannot output anything if UART0 is not implemented
 4bc:	2435                	jal	6e8 <neorv32_uart_available>
 4be:	45b2                	lw	a1,12(sp)
 4c0:	c511                	beqz	a0,4cc <__neorv32_rte_puts+0x1a>
}
 4c2:	40f2                	lw	ra,28(sp)
    neorv32_uart_puts(NEORV32_UART0, s);
 4c4:	fff50537          	lui	a0,0xfff50
}
 4c8:	6105                	addi	sp,sp,32
    neorv32_uart_puts(NEORV32_UART0, s);
 4ca:	a44d                	j	76c <neorv32_uart_puts>
}
 4cc:	40f2                	lw	ra,28(sp)
 4ce:	6105                	addi	sp,sp,32
 4d0:	8082                	ret

000004d2 <__neorv32_rte_panic>:
  __neorv32_rte_puts(RTE_TERM_HL_ON "<NEORV32-RTE-PANIC> ");
 4d2:	6505                	lui	a0,0x1
static void __neorv32_rte_panic(void) {
 4d4:	1141                	addi	sp,sp,-16
  __neorv32_rte_puts(RTE_TERM_HL_ON "<NEORV32-RTE-PANIC> ");
 4d6:	ab850513          	addi	a0,a0,-1352 # ab8 <__fini_array_end+0x14c>
static void __neorv32_rte_panic(void) {
 4da:	c606                	sw	ra,12(sp)
 4dc:	c422                	sw	s0,8(sp)
 4de:	c226                	sw	s1,4(sp)
  __neorv32_rte_puts(RTE_TERM_HL_ON "<NEORV32-RTE-PANIC> ");
 4e0:	3fc9                	jal	4b2 <__neorv32_rte_puts>
 4e2:	f14027f3          	csrr	a5,mhartid
  if (neorv32_cpu_csr_read(CSR_MHARTID) & 1) {
 4e6:	8b85                	andi	a5,a5,1
 4e8:	cf85                	beqz	a5,520 <__neorv32_rte_panic+0x4e>
    __neorv32_rte_puts("[cpu1|");
 4ea:	6505                	lui	a0,0x1
 4ec:	ad450513          	addi	a0,a0,-1324 # ad4 <__fini_array_end+0x168>
    __neorv32_rte_puts("[cpu0|");
 4f0:	37c9                	jal	4b2 <__neorv32_rte_puts>
 4f2:	300027f3          	csrr	a5,mstatus
  if (neorv32_cpu_csr_read(CSR_MSTATUS) & (3 << CSR_MSTATUS_MPP_L)) {
 4f6:	00b7d713          	srli	a4,a5,0xb
 4fa:	8b0d                	andi	a4,a4,3
 4fc:	c715                	beqz	a4,528 <__neorv32_rte_panic+0x56>
    __neorv32_rte_puts("M] "); // machine-mode
 4fe:	6505                	lui	a0,0x1
 500:	ae450513          	addi	a0,a0,-1308 # ae4 <__fini_array_end+0x178>
    __neorv32_rte_puts("U] "); // user-mode
 504:	377d                	jal	4b2 <__neorv32_rte_puts>
 506:	34202473          	csrr	s0,mcause
  switch (cause) {
 50a:	47ad                	li	a5,11
 50c:	0287e963          	bltu	a5,s0,53e <__neorv32_rte_panic+0x6c>
 510:	6705                	lui	a4,0x1
 512:	00241793          	slli	a5,s0,0x2
 516:	dc470713          	addi	a4,a4,-572 # dc4 <__fini_array_end+0x458>
 51a:	97ba                	add	a5,a5,a4
 51c:	439c                	lw	a5,0(a5)
 51e:	8782                	jr	a5
    __neorv32_rte_puts("[cpu0|");
 520:	6505                	lui	a0,0x1
 522:	adc50513          	addi	a0,a0,-1316 # adc <__fini_array_end+0x170>
 526:	b7e9                	j	4f0 <__neorv32_rte_panic+0x1e>
    __neorv32_rte_puts("U] "); // user-mode
 528:	6505                	lui	a0,0x1
 52a:	ae850513          	addi	a0,a0,-1304 # ae8 <__fini_array_end+0x17c>
 52e:	bfd9                	j	504 <__neorv32_rte_panic+0x32>
  switch (cause) {
 530:	6705                	lui	a4,0x1
 532:	078a                	slli	a5,a5,0x2
 534:	df470713          	addi	a4,a4,-524 # df4 <__fini_array_end+0x488>
 538:	97ba                	add	a5,a5,a4
 53a:	439c                	lw	a5,0(a5)
 53c:	8782                	jr	a5
 53e:	800007b7          	lui	a5,0x80000
 542:	17f5                	addi	a5,a5,-3 # 7ffffffd <__neorv32_rom_size+0x7fffbffd>
 544:	97a2                	add	a5,a5,s0
 546:	4771                	li	a4,28
 548:	fef774e3          	bgeu	a4,a5,530 <__neorv32_rte_panic+0x5e>
    default:                     __neorv32_rte_puts("Unknown trap cause "); __neorv32_rte_puth(cause); fatal = 1; break;
 54c:	6505                	lui	a0,0x1
 54e:	d3c50513          	addi	a0,a0,-708 # d3c <__fini_array_end+0x3d0>
 552:	3785                	jal	4b2 <__neorv32_rte_puts>
 554:	8522                	mv	a0,s0
 556:	3df5                	jal	452 <__neorv32_rte_puth>
 558:	a029                	j	562 <__neorv32_rte_panic+0x90>
    case TRAP_CODE_I_ACCESS:     __neorv32_rte_puts("Instruction access fault"); fatal = 1; break;
 55a:	6505                	lui	a0,0x1
 55c:	aec50513          	addi	a0,a0,-1300 # aec <__fini_array_end+0x180>
    case TRAP_CODE_I_MISALIGNED: __neorv32_rte_puts("Instruction address misaligned"); fatal = 1; break;
 560:	3f89                	jal	4b2 <__neorv32_rte_puts>
    case TRAP_CODE_I_ACCESS:     __neorv32_rte_puts("Instruction access fault"); fatal = 1; break;
 562:	4485                	li	s1,1
  __neorv32_rte_puts(" MEPC=");
 564:	6505                	lui	a0,0x1
 566:	d5050513          	addi	a0,a0,-688 # d50 <__fini_array_end+0x3e4>
 56a:	37a1                	jal	4b2 <__neorv32_rte_puts>
 56c:	34102573          	csrr	a0,mepc
  __neorv32_rte_puth(neorv32_cpu_csr_read(CSR_MEPC));
 570:	35cd                	jal	452 <__neorv32_rte_puth>
  __neorv32_rte_puts(" MTVAL=");
 572:	6505                	lui	a0,0x1
 574:	d5850513          	addi	a0,a0,-680 # d58 <__fini_array_end+0x3ec>
 578:	3f2d                	jal	4b2 <__neorv32_rte_puts>
 57a:	34302573          	csrr	a0,mtval
  __neorv32_rte_puth(neorv32_cpu_csr_read(CSR_MTVAL));
 57e:	3dd1                	jal	452 <__neorv32_rte_puth>
  if (((int32_t)cause) < 0) { // is interrupt
 580:	00045b63          	bgez	s0,596 <__neorv32_rte_panic+0xc4>
    __neorv32_rte_puts(" Disabling IRQ source");
 584:	6505                	lui	a0,0x1
 586:	d6050513          	addi	a0,a0,-672 # d60 <__fini_array_end+0x3f4>
 58a:	3725                	jal	4b2 <__neorv32_rte_puts>
    neorv32_cpu_csr_clr(CSR_MIE, 1 << (cause & 0x1f));
 58c:	4785                	li	a5,1
 58e:	008797b3          	sll	a5,a5,s0
 * @param[in] mask Bit mask (high-active) to clear bits (uint32_t).
 **************************************************************************/
inline void __attribute__ ((always_inline)) neorv32_cpu_csr_clr(const int csr_id, uint32_t mask) {

  uint32_t csr_data = mask;
  asm volatile ("csrc %[id], %[src]" :  : [id] "i" (csr_id), [src] "r" (csr_data));
 592:	3047b073          	csrc	mie,a5
  if (fatal) {
 596:	c881                	beqz	s1,5a6 <__neorv32_rte_panic_halt+0x6>
    __neorv32_rte_puts(" FATAL! Halting CPU </NEORV32-RTE-PANIC>" RTE_TERM_HL_OFF "\n");
 598:	6505                	lui	a0,0x1
 59a:	d7850513          	addi	a0,a0,-648 # d78 <__fini_array_end+0x40c>
 59e:	3f11                	jal	4b2 <__neorv32_rte_puts>

000005a0 <__neorv32_rte_panic_halt>:
    asm volatile (
 5a0:	10500073          	wfi
 5a4:	bff5                	j	5a0 <__neorv32_rte_panic_halt>
}
 5a6:	4422                	lw	s0,8(sp)
 5a8:	40b2                	lw	ra,12(sp)
 5aa:	4492                	lw	s1,4(sp)
  __neorv32_rte_puts(" </NEORV32-RTE-PANIC>\n" RTE_TERM_HL_OFF);
 5ac:	6505                	lui	a0,0x1
 5ae:	da850513          	addi	a0,a0,-600 # da8 <__fini_array_end+0x43c>
}
 5b2:	0141                	addi	sp,sp,16
  __neorv32_rte_puts(" </NEORV32-RTE-PANIC>\n" RTE_TERM_HL_OFF);
 5b4:	bdfd                	j	4b2 <__neorv32_rte_puts>
    case TRAP_CODE_I_ILLEGAL:    __neorv32_rte_puts("Illegal instruction"); break;
 5b6:	6505                	lui	a0,0x1
 5b8:	b0850513          	addi	a0,a0,-1272 # b08 <__fini_array_end+0x19c>
    case TRAP_CODE_BREAKPOINT:   __neorv32_rte_puts("Environment breakpoint"); break;
 5bc:	3ddd                	jal	4b2 <__neorv32_rte_puts>
  uint32_t fatal = 0;
 5be:	4481                	li	s1,0
 5c0:	b755                	j	564 <__neorv32_rte_panic+0x92>
    case TRAP_CODE_I_MISALIGNED: __neorv32_rte_puts("Instruction address misaligned"); fatal = 1; break;
 5c2:	6505                	lui	a0,0x1
 5c4:	b1c50513          	addi	a0,a0,-1252 # b1c <__fini_array_end+0x1b0>
 5c8:	bf61                	j	560 <__neorv32_rte_panic+0x8e>
    case TRAP_CODE_BREAKPOINT:   __neorv32_rte_puts("Environment breakpoint"); break;
 5ca:	6505                	lui	a0,0x1
 5cc:	b3c50513          	addi	a0,a0,-1220 # b3c <__fini_array_end+0x1d0>
 5d0:	b7f5                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_L_MISALIGNED: __neorv32_rte_puts("Load address misaligned"); break;
 5d2:	6505                	lui	a0,0x1
 5d4:	b5450513          	addi	a0,a0,-1196 # b54 <__fini_array_end+0x1e8>
 5d8:	b7d5                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_L_ACCESS:     __neorv32_rte_puts("Load access fault"); break;
 5da:	6505                	lui	a0,0x1
 5dc:	b6c50513          	addi	a0,a0,-1172 # b6c <__fini_array_end+0x200>
 5e0:	bff1                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_S_MISALIGNED: __neorv32_rte_puts("Store address misaligned"); break;
 5e2:	6505                	lui	a0,0x1
 5e4:	b8050513          	addi	a0,a0,-1152 # b80 <__fini_array_end+0x214>
 5e8:	bfd1                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_S_ACCESS:     __neorv32_rte_puts("Store access fault"); break;
 5ea:	6505                	lui	a0,0x1
 5ec:	b9c50513          	addi	a0,a0,-1124 # b9c <__fini_array_end+0x230>
 5f0:	b7f1                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_UENV_CALL:    __neorv32_rte_puts("Environment call from U-mode"); break;
 5f2:	6505                	lui	a0,0x1
 5f4:	bb050513          	addi	a0,a0,-1104 # bb0 <__fini_array_end+0x244>
 5f8:	b7d1                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_MENV_CALL:    __neorv32_rte_puts("Environment call from M-mode"); break;
 5fa:	6505                	lui	a0,0x1
 5fc:	bd050513          	addi	a0,a0,-1072 # bd0 <__fini_array_end+0x264>
 600:	bf75                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_MSI:          __neorv32_rte_puts("Machine software IRQ"); break;
 602:	6505                	lui	a0,0x1
 604:	bf050513          	addi	a0,a0,-1040 # bf0 <__fini_array_end+0x284>
 608:	bf55                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_MTI:          __neorv32_rte_puts("Machine timer IRQ"); break;
 60a:	6505                	lui	a0,0x1
 60c:	c0850513          	addi	a0,a0,-1016 # c08 <__fini_array_end+0x29c>
 610:	b775                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_MEI:          __neorv32_rte_puts("Machine external IRQ"); break;
 612:	6505                	lui	a0,0x1
 614:	c1c50513          	addi	a0,a0,-996 # c1c <__fini_array_end+0x2b0>
 618:	b755                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_0:       __neorv32_rte_puts("FIRQ-0 (reserved)"); break;
 61a:	6505                	lui	a0,0x1
 61c:	c3450513          	addi	a0,a0,-972 # c34 <__fini_array_end+0x2c8>
 620:	bf71                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_1:       __neorv32_rte_puts("FIRQ-1 (CFS)"); break;
 622:	6505                	lui	a0,0x1
 624:	c4850513          	addi	a0,a0,-952 # c48 <__fini_array_end+0x2dc>
 628:	bf51                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_2:       __neorv32_rte_puts("FIRQ-2 (UART0)"); break;
 62a:	6505                	lui	a0,0x1
 62c:	c5850513          	addi	a0,a0,-936 # c58 <__fini_array_end+0x2ec>
 630:	b771                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_3:       __neorv32_rte_puts("FIRQ-3 (UART1)"); break;
 632:	6505                	lui	a0,0x1
 634:	c6850513          	addi	a0,a0,-920 # c68 <__fini_array_end+0x2fc>
 638:	b751                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_4:       __neorv32_rte_puts("FIRQ-4 (TWD)"); break;
 63a:	6505                	lui	a0,0x1
 63c:	c7850513          	addi	a0,a0,-904 # c78 <__fini_array_end+0x30c>
 640:	bfb5                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_5:       __neorv32_rte_puts("FIRQ-5 (TRACER)"); break;
 642:	6505                	lui	a0,0x1
 644:	c8850513          	addi	a0,a0,-888 # c88 <__fini_array_end+0x31c>
 648:	bf95                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_6:       __neorv32_rte_puts("FIRQ-6 (SPI)"); break;
 64a:	6505                	lui	a0,0x1
 64c:	c9850513          	addi	a0,a0,-872 # c98 <__fini_array_end+0x32c>
 650:	b7b5                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_7:       __neorv32_rte_puts("FIRQ-7 (TWI)"); break;
 652:	6505                	lui	a0,0x1
 654:	ca850513          	addi	a0,a0,-856 # ca8 <__fini_array_end+0x33c>
 658:	b795                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_8:       __neorv32_rte_puts("FIRQ-8 (GPIO)"); break;
 65a:	6505                	lui	a0,0x1
 65c:	cb850513          	addi	a0,a0,-840 # cb8 <__fini_array_end+0x34c>
 660:	bfb1                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_9:       __neorv32_rte_puts("FIRQ-9 (NEOLED)"); break;
 662:	6505                	lui	a0,0x1
 664:	cc850513          	addi	a0,a0,-824 # cc8 <__fini_array_end+0x35c>
 668:	bf91                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_10:      __neorv32_rte_puts("FIRQ-10 (DMA)"); break;
 66a:	6505                	lui	a0,0x1
 66c:	cd850513          	addi	a0,a0,-808 # cd8 <__fini_array_end+0x36c>
 670:	b7b1                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_11:      __neorv32_rte_puts("FIRQ-11 (SDI)"); break;
 672:	6505                	lui	a0,0x1
 674:	ce850513          	addi	a0,a0,-792 # ce8 <__fini_array_end+0x37c>
 678:	b791                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_12:      __neorv32_rte_puts("FIRQ-12 (GPTMR)"); break;
 67a:	6505                	lui	a0,0x1
 67c:	cf850513          	addi	a0,a0,-776 # cf8 <__fini_array_end+0x38c>
 680:	bf35                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_13:      __neorv32_rte_puts("FIRQ-13 (ONEWIRE)"); break;
 682:	6505                	lui	a0,0x1
 684:	d0850513          	addi	a0,a0,-760 # d08 <__fini_array_end+0x39c>
 688:	bf15                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_14:      __neorv32_rte_puts("FIRQ-14 (SLINK)"); break;
 68a:	6505                	lui	a0,0x1
 68c:	d1c50513          	addi	a0,a0,-740 # d1c <__fini_array_end+0x3b0>
 690:	b735                	j	5bc <__neorv32_rte_panic_halt+0x1c>
    case TRAP_CODE_FIRQ_15:      __neorv32_rte_puts("FIRQ-15 (TRNG)"); break;
 692:	6505                	lui	a0,0x1
 694:	d2c50513          	addi	a0,a0,-724 # d2c <__fini_array_end+0x3c0>
 698:	b715                	j	5bc <__neorv32_rte_panic_halt+0x1c>

0000069a <neorv32_rte_setup>:
  asm volatile ("csrw %[id], %[src]" :  : [id] "i" (csr_id), [src] "r" (csr_data));
 69a:	6789                	lui	a5,0x2
 69c:	80078793          	addi	a5,a5,-2048 # 1800 <__crt0_copy_data_src_begin+0x998>
 6a0:	30079073          	csrw	mstatus,a5
 6a4:	4781                	li	a5,0
 6a6:	30479073          	csrw	mie,a5
  asm volatile ("csrr %[dst], %[id]" : [dst] "=r" (csr_data) : [id] "i" (csr_id));
 6aa:	f14027f3          	csrr	a5,mhartid

  // disable all IRQ channels
  neorv32_cpu_csr_write(CSR_MIE, 0);

  // install debug handler for all trap sources (executed only on core 0)
  if (neorv32_cpu_csr_read(CSR_MHARTID) == 0) {
 6ae:	e78d                	bnez	a5,6d8 <neorv32_rte_setup+0x3e>
    for (i=0; i<32; i++) {
      __neorv32_rte_vector_lut[0][i] = (uint32_t)(&__neorv32_rte_panic);
 6b0:	80000637          	lui	a2,0x80000
 6b4:	4d200693          	li	a3,1234
 6b8:	00060613          	mv	a2,a2
    for (i=0; i<32; i++) {
 6bc:	02000593          	li	a1,32
      __neorv32_rte_vector_lut[0][i] = (uint32_t)(&__neorv32_rte_panic);
 6c0:	00279713          	slli	a4,a5,0x2
 6c4:	9732                	add	a4,a4,a2
 6c6:	c314                	sw	a3,0(a4)
      __neorv32_rte_vector_lut[1][i] = (uint32_t)(&__neorv32_rte_panic);
 6c8:	02078713          	addi	a4,a5,32
 6cc:	070a                	slli	a4,a4,0x2
 6ce:	9732                	add	a4,a4,a2
 6d0:	c314                	sw	a3,0(a4)
    for (i=0; i<32; i++) {
 6d2:	0785                	addi	a5,a5,1
 6d4:	feb796e3          	bne	a5,a1,6c0 <neorv32_rte_setup+0x26>
    }
  }
  asm volatile ("fence"); // flush vector table to main memory
 6d8:	0ff0000f          	fence

  // configure trap handler base address (direct mode)
  neorv32_cpu_csr_write(CSR_MTVEC, (uint32_t)(&__neorv32_rte_core) & 0xfffffffcU);
 6dc:	38000793          	li	a5,896
 6e0:	9bf1                	andi	a5,a5,-4
  asm volatile ("csrw %[id], %[src]" :  : [id] "i" (csr_id), [src] "r" (csr_data));
 6e2:	30579073          	csrw	mtvec,a5
}
 6e6:	8082                	ret

000006e8 <neorv32_uart_available>:
 * @param[in,out] Hardware handle to UART register struct, #neorv32_uart_t.
 * @return 0 if UART0/1 was not synthesized, non-zero if UART0/1 is available.
 **************************************************************************/
int neorv32_uart_available(neorv32_uart_t *UARTx) {

  if (UARTx == NEORV32_UART0) {
 6e8:	fff50737          	lui	a4,0xfff50
int neorv32_uart_available(neorv32_uart_t *UARTx) {
 6ec:	87aa                	mv	a5,a0
  if (UARTx == NEORV32_UART0) {
 6ee:	00e51863          	bne	a0,a4,6fe <neorv32_uart_available+0x16>
    return (int)(NEORV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_UART0));
 6f2:	7781                	lui	a5,0xfffe0
 6f4:	4788                	lw	a0,8(a5)
 6f6:	000207b7          	lui	a5,0x20
  }
  else if (UARTx == NEORV32_UART1) {
    return (int)(NEORV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_UART1));
 6fa:	8d7d                	and	a0,a0,a5
  }
  else {
    return 0;
  }
}
 6fc:	8082                	ret
  else if (UARTx == NEORV32_UART1) {
 6fe:	fff60737          	lui	a4,0xfff60
    return 0;
 702:	4501                	li	a0,0
  else if (UARTx == NEORV32_UART1) {
 704:	fee79ce3          	bne	a5,a4,6fc <neorv32_uart_available+0x14>
    return (int)(NEORV32_SYSINFO->SOC & (1 << SYSINFO_SOC_IO_UART1));
 708:	7781                	lui	a5,0xfffe0
 70a:	4788                	lw	a0,8(a5)
 70c:	020007b7          	lui	a5,0x2000
 710:	b7ed                	j	6fa <neorv32_uart_available+0x12>

00000712 <neorv32_uart_setup>:

  uint32_t prsc_sel = 0;
  uint32_t baud_div = 0;

  // reset
  UARTx->CTRL = 0;
 712:	00052023          	sw	zero,0(a0)
 716:	7781                	lui	a5,0xfffe0
 718:	439c                	lw	a5,0(a5)

  // raw clock prescaler
  uint32_t clock = neorv32_sysinfo_get_clk(); // system clock in Hz
#ifndef MAKE_BOOTLOADER // use div instructions / library functions
  baud_div = clock / (2*baudrate);
 71a:	0586                	slli	a1,a1,0x1
  uint32_t prsc_sel = 0;
 71c:	4701                	li	a4,0
  baud_div = clock / (2*baudrate);
 71e:	02b7d7b3          	divu	a5,a5,a1
    baud_div++;
  }
#endif

  // find baud prescaler (10-bit wide))
  while (baud_div >= 0x3ffU) {
 722:	3fe00593          	li	a1,1022
 726:	02f5e363          	bltu	a1,a5,74c <neorv32_uart_setup+0x3a>
  }

  uint32_t tmp = 0;
  tmp |= (uint32_t)(1              & 1U)     << UART_CTRL_EN;
  tmp |= (uint32_t)(prsc_sel       & 3U)     << UART_CTRL_PRSC_LSB;
  tmp |= (uint32_t)((baud_div - 1) & 0x3ffU) << UART_CTRL_BAUD_LSB;
 72a:	17fd                	addi	a5,a5,-1 # fffdffff <__crt0_stack_top+0x7ffddfff>
 72c:	66c1                	lui	a3,0x10
 72e:	fc068693          	addi	a3,a3,-64 # ffc0 <__neorv32_rom_size+0xbfc0>
 732:	079a                	slli	a5,a5,0x6
 734:	8ff5                	and	a5,a5,a3
  tmp |= (uint32_t)(irq_mask       & (0xfu   << UART_CTRL_IRQ_RX_NEMPTY));
 736:	00f006b7          	lui	a3,0xf00
 73a:	8e75                	and	a2,a2,a3
  tmp |= (uint32_t)(prsc_sel       & 3U)     << UART_CTRL_PRSC_LSB;
 73c:	070e                	slli	a4,a4,0x3
  tmp |= (uint32_t)(irq_mask       & (0xfu   << UART_CTRL_IRQ_RX_NEMPTY));
 73e:	8fd1                	or	a5,a5,a2
  tmp |= (uint32_t)(prsc_sel       & 3U)     << UART_CTRL_PRSC_LSB;
 740:	8b61                	andi	a4,a4,24
  tmp |= (uint32_t)(irq_mask       & (0xfu   << UART_CTRL_IRQ_RX_NEMPTY));
 742:	8fd9                	or	a5,a5,a4
 744:	0017e793          	ori	a5,a5,1
  if (((uint32_t)UARTx) == NEORV32_UART1_BASE) {
    tmp |= 1U << UART_CTRL_SIM_MODE;
  }
#endif

  UARTx->CTRL = tmp;
 748:	c11c                	sw	a5,0(a0)
}
 74a:	8082                	ret
    if ((prsc_sel == 2) || (prsc_sel == 4))
 74c:	ffe70693          	addi	a3,a4,-2 # fff5fffe <__crt0_stack_top+0x7ff5dffe>
 750:	9af5                	andi	a3,a3,-3
 752:	e681                	bnez	a3,75a <neorv32_uart_setup+0x48>
      baud_div >>= 3;
 754:	838d                	srli	a5,a5,0x3
    prsc_sel++;
 756:	0705                	addi	a4,a4,1
 758:	b7f9                	j	726 <neorv32_uart_setup+0x14>
      baud_div >>= 1;
 75a:	8385                	srli	a5,a5,0x1
 75c:	bfed                	j	756 <neorv32_uart_setup+0x44>

0000075e <neorv32_uart_putc>:
 * @param[in,out] UARTx Hardware handle to UART register struct, #neorv32_uart_t.
 * @param[in] c Char to be send.
 **************************************************************************/
void neorv32_uart_putc(neorv32_uart_t *UARTx, char c) {

  while ((UARTx->CTRL & (1<<UART_CTRL_TX_NFULL)) == 0); // wait for free space in TX FIFO
 75e:	411c                	lw	a5,0(a0)
 760:	00c79713          	slli	a4,a5,0xc
 764:	fe075de3          	bgez	a4,75e <neorv32_uart_putc>
void neorv32_uart_tx_put(neorv32_uart_t *UARTx, char c) {

#ifdef UART_SEMIHOSTING
  neorv32_semihosting_putc(c);
#else
  UARTx->DATA = (uint32_t)c << UART_DATA_RTX_LSB;
 768:	c14c                	sw	a1,4(a0)
}
 76a:	8082                	ret

0000076c <neorv32_uart_puts>:
 * @warning "/n" line breaks are automatically converted to "/r/n".
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #neorv32_uart_t.
 * @param[in] s Pointer to string.
 **************************************************************************/
void neorv32_uart_puts(neorv32_uart_t *UARTx, const char *s) {
 76c:	1101                	addi	sp,sp,-32
 76e:	cc22                	sw	s0,24(sp)
 770:	ca26                	sw	s1,20(sp)
 772:	c64e                	sw	s3,12(sp)
 774:	ce06                	sw	ra,28(sp)
 776:	c84a                	sw	s2,16(sp)
 778:	84aa                	mv	s1,a0
 77a:	842e                	mv	s0,a1
#ifdef UART_SEMIHOSTING
  neorv32_semihosting_puts(s);
#else
  char c = 0;
  while ((c = *s++)) {
    if (c == '\n') {
 77c:	49a9                	li	s3,10
  while ((c = *s++)) {
 77e:	00044903          	lbu	s2,0(s0)
 782:	0405                	addi	s0,s0,1
 784:	00091963          	bnez	s2,796 <neorv32_uart_puts+0x2a>
      neorv32_uart_putc(UARTx, '\r');
    }
    neorv32_uart_putc(UARTx, c);
  }
#endif
}
 788:	40f2                	lw	ra,28(sp)
 78a:	4462                	lw	s0,24(sp)
 78c:	44d2                	lw	s1,20(sp)
 78e:	4942                	lw	s2,16(sp)
 790:	49b2                	lw	s3,12(sp)
 792:	6105                	addi	sp,sp,32
 794:	8082                	ret
    if (c == '\n') {
 796:	01391563          	bne	s2,s3,7a0 <neorv32_uart_puts+0x34>
      neorv32_uart_putc(UARTx, '\r');
 79a:	45b5                	li	a1,13
 79c:	8526                	mv	a0,s1
 79e:	37c1                	jal	75e <neorv32_uart_putc>
    neorv32_uart_putc(UARTx, c);
 7a0:	85ca                	mv	a1,s2
 7a2:	8526                	mv	a0,s1
 7a4:	3f6d                	jal	75e <neorv32_uart_putc>
 7a6:	bfe1                	j	77e <neorv32_uart_puts+0x12>

000007a8 <neorv32_uart_vprintf>:
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #neorv32_uart_t.
 * @param[in] format Pointer to format string.
 * @param[in] args A value identifying a variable arguments list.
 **************************************************************************/
void neorv32_uart_vprintf(neorv32_uart_t *UARTx, const char *format, va_list args) {
 7a8:	711d                	addi	sp,sp,-96
 7aa:	cca2                	sw	s0,88(sp)
 7ac:	caa6                	sw	s1,84(sp)
 7ae:	c8ca                	sw	s2,80(sp)
 7b0:	84aa                	mv	s1,a0
 7b2:	892e                	mv	s2,a1
 7b4:	8432                	mv	s0,a2
  int32_t n = 0;
  unsigned int i = 0;

  // prevent uninitialized stack bytes
  for (i=0; i<sizeof(string_buf); i++) {
    string_buf[i] = 0;
 7b6:	4581                	li	a1,0
 7b8:	02400613          	li	a2,36
 7bc:	0068                	addi	a0,sp,12
void neorv32_uart_vprintf(neorv32_uart_t *UARTx, const char *format, va_list args) {
 7be:	c6ce                	sw	s3,76(sp)
 7c0:	c4d2                	sw	s4,72(sp)
 7c2:	c0da                	sw	s6,64(sp)
 7c4:	de5e                	sw	s7,60(sp)
 7c6:	dc62                	sw	s8,56(sp)
 7c8:	da66                	sw	s9,52(sp)
 7ca:	ce86                	sw	ra,92(sp)
 7cc:	c2d6                	sw	s5,68(sp)
 7ce:	d86a                	sw	s10,48(sp)
  }

  while ((c = *format++)) {
    if (c == '%') {
 7d0:	02500b13          	li	s6,37
    string_buf[i] = 0;
 7d4:	2ab9                	jal	932 <memset>
          neorv32_uart_putc(UARTx, c);
          break;
      }
    }
    else {
      if (c == '\n') {
 7d6:	4ba9                	li	s7,10
    return isalpha(c) || isdigit(c);
}

__declare_extern_inline(int) tolower (int c)
{
    if (isupper(c))
 7d8:	4c65                	li	s8,25
      switch (c) {
 7da:	07000993          	li	s3,112
 7de:	07500c93          	li	s9,117
 7e2:	06300a13          	li	s4,99
  while ((c = *format++)) {
 7e6:	00094d03          	lbu	s10,0(s2)
 7ea:	020d1063          	bnez	s10,80a <neorv32_uart_vprintf+0x62>
        neorv32_uart_putc(UARTx, '\r');
      }
      neorv32_uart_putc(UARTx, c);
    }
  }
}
 7ee:	40f6                	lw	ra,92(sp)
 7f0:	4466                	lw	s0,88(sp)
 7f2:	44d6                	lw	s1,84(sp)
 7f4:	4946                	lw	s2,80(sp)
 7f6:	49b6                	lw	s3,76(sp)
 7f8:	4a26                	lw	s4,72(sp)
 7fa:	4a96                	lw	s5,68(sp)
 7fc:	4b06                	lw	s6,64(sp)
 7fe:	5bf2                	lw	s7,60(sp)
 800:	5c62                	lw	s8,56(sp)
 802:	5cd2                	lw	s9,52(sp)
 804:	5d42                	lw	s10,48(sp)
 806:	6125                	addi	sp,sp,96
 808:	8082                	ret
    if (c == '%') {
 80a:	0d6d1b63          	bne	s10,s6,8e0 <neorv32_uart_vprintf+0x138>
      c = tolower(*format++);
 80e:	00290a93          	addi	s5,s2,2
 812:	00194903          	lbu	s2,1(s2)
    return 'A' <= c && c <= 'Z';
 816:	fbf90793          	addi	a5,s2,-65
    if (isupper(c))
 81a:	00fc6463          	bltu	s8,a5,822 <neorv32_uart_vprintf+0x7a>
        c = c - 'A' + 'a';
 81e:	02090913          	addi	s2,s2,32
      switch (c) {
 822:	09390e63          	beq	s2,s3,8be <neorv32_uart_vprintf+0x116>
 826:	0529ce63          	blt	s3,s2,882 <neorv32_uart_vprintf+0xda>
 82a:	07490c63          	beq	s2,s4,8a2 <neorv32_uart_vprintf+0xfa>
 82e:	032a4163          	blt	s4,s2,850 <neorv32_uart_vprintf+0xa8>
 832:	02500793          	li	a5,37
          neorv32_uart_putc(UARTx, c);
 836:	02500593          	li	a1,37
      switch (c) {
 83a:	00f90863          	beq	s2,a5,84a <neorv32_uart_vprintf+0xa2>
          neorv32_uart_putc(UARTx, '%');
 83e:	02500593          	li	a1,37
 842:	8526                	mv	a0,s1
 844:	3f29                	jal	75e <neorv32_uart_putc>
          neorv32_uart_putc(UARTx, c);
 846:	0ff97593          	zext.b	a1,s2
      neorv32_uart_putc(UARTx, c);
 84a:	8526                	mv	a0,s1
 84c:	3f09                	jal	75e <neorv32_uart_putc>
 84e:	a08d                	j	8b0 <neorv32_uart_vprintf+0x108>
      switch (c) {
 850:	06400793          	li	a5,100
 854:	00f90663          	beq	s2,a5,860 <neorv32_uart_vprintf+0xb8>
 858:	06900793          	li	a5,105
 85c:	fef911e3          	bne	s2,a5,83e <neorv32_uart_vprintf+0x96>
          n = (int32_t)va_arg(args, int32_t);
 860:	00440913          	addi	s2,s0,4
 864:	4000                	lw	s0,0(s0)
          if (n < 0) {
 866:	00045863          	bgez	s0,876 <neorv32_uart_vprintf+0xce>
            neorv32_uart_putc(UARTx, '-');
 86a:	02d00593          	li	a1,45
 86e:	8526                	mv	a0,s1
            n = -n;
 870:	40800433          	neg	s0,s0
            neorv32_uart_putc(UARTx, '-');
 874:	35ed                	jal	75e <neorv32_uart_putc>
          neorv32_aux_itoa(string_buf, (uint32_t)n, 10);
 876:	4629                	li	a2,10
 878:	85a2                	mv	a1,s0
          neorv32_aux_itoa(string_buf, va_arg(args, uint32_t), 10);
 87a:	0068                	addi	a0,sp,12
 87c:	3cb5                	jal	2f8 <neorv32_aux_itoa>
          neorv32_uart_puts(UARTx, string_buf);
 87e:	006c                	addi	a1,sp,12
 880:	a831                	j	89c <neorv32_uart_vprintf+0xf4>
      switch (c) {
 882:	03990963          	beq	s2,s9,8b4 <neorv32_uart_vprintf+0x10c>
 886:	07800793          	li	a5,120
 88a:	02f90a63          	beq	s2,a5,8be <neorv32_uart_vprintf+0x116>
 88e:	07300793          	li	a5,115
 892:	faf916e3          	bne	s2,a5,83e <neorv32_uart_vprintf+0x96>
          neorv32_uart_puts(UARTx, va_arg(args, char*));
 896:	400c                	lw	a1,0(s0)
 898:	00440913          	addi	s2,s0,4
          neorv32_uart_puts(UARTx, string_buf);
 89c:	8526                	mv	a0,s1
 89e:	35f9                	jal	76c <neorv32_uart_puts>
          break;
 8a0:	a039                	j	8ae <neorv32_uart_vprintf+0x106>
          neorv32_uart_putc(UARTx, (char)va_arg(args, int));
 8a2:	00044583          	lbu	a1,0(s0)
 8a6:	8526                	mv	a0,s1
 8a8:	00440913          	addi	s2,s0,4
 8ac:	3d4d                	jal	75e <neorv32_uart_putc>
 8ae:	844a                	mv	s0,s2
          neorv32_uart_puts(UARTx, va_arg(args, char*));
 8b0:	8956                	mv	s2,s5
 8b2:	bf15                	j	7e6 <neorv32_uart_vprintf+0x3e>
          neorv32_aux_itoa(string_buf, va_arg(args, uint32_t), 10);
 8b4:	400c                	lw	a1,0(s0)
 8b6:	00440913          	addi	s2,s0,4
 8ba:	4629                	li	a2,10
 8bc:	bf7d                	j	87a <neorv32_uart_vprintf+0xd2>
          neorv32_aux_itoa(string_buf, va_arg(args, uint32_t), 16);
 8be:	400c                	lw	a1,0(s0)
 8c0:	4641                	li	a2,16
 8c2:	0068                	addi	a0,sp,12
 8c4:	3c15                	jal	2f8 <neorv32_aux_itoa>
          i = 8 - strlen(string_buf);
 8c6:	0068                	addi	a0,sp,12
          neorv32_aux_itoa(string_buf, va_arg(args, uint32_t), 16);
 8c8:	00440913          	addi	s2,s0,4
          i = 8 - strlen(string_buf);
 8cc:	2051                	jal	950 <strlen>
 8ce:	4421                	li	s0,8
 8d0:	8c09                	sub	s0,s0,a0
          while (i--) { // add leading zeros
 8d2:	d455                	beqz	s0,87e <neorv32_uart_vprintf+0xd6>
            neorv32_uart_putc(UARTx, '0');
 8d4:	03000593          	li	a1,48
 8d8:	8526                	mv	a0,s1
 8da:	3551                	jal	75e <neorv32_uart_putc>
 8dc:	147d                	addi	s0,s0,-1
 8de:	bfd5                	j	8d2 <neorv32_uart_vprintf+0x12a>
      if (c == '\n') {
 8e0:	017d1563          	bne	s10,s7,8ea <neorv32_uart_vprintf+0x142>
        neorv32_uart_putc(UARTx, '\r');
 8e4:	45b5                	li	a1,13
 8e6:	8526                	mv	a0,s1
 8e8:	3d9d                	jal	75e <neorv32_uart_putc>
  while ((c = *format++)) {
 8ea:	00190a93          	addi	s5,s2,1
      neorv32_uart_putc(UARTx, c);
 8ee:	85ea                	mv	a1,s10
 8f0:	bfa9                	j	84a <neorv32_uart_vprintf+0xa2>

000008f2 <neorv32_uart_printf>:
 * @note This function is blocking.
 *
 * @param[in,out] UARTx Hardware handle to UART register struct, #neorv32_uart_t.
 * @param[in] format Pointer to format string. See neorv32_uart_vprintf.
 **************************************************************************/
void neorv32_uart_printf(neorv32_uart_t *UARTx, const char *format, ...) {
 8f2:	7139                	addi	sp,sp,-64
 8f4:	d432                	sw	a2,40(sp)

  va_list args;
  va_start(args, format);
 8f6:	1030                	addi	a2,sp,40
void neorv32_uart_printf(neorv32_uart_t *UARTx, const char *format, ...) {
 8f8:	ce06                	sw	ra,28(sp)
 8fa:	d636                	sw	a3,44(sp)
 8fc:	d83a                	sw	a4,48(sp)
 8fe:	da3e                	sw	a5,52(sp)
 900:	dc42                	sw	a6,56(sp)
 902:	de46                	sw	a7,60(sp)
  va_start(args, format);
 904:	c632                	sw	a2,12(sp)
  neorv32_uart_vprintf(UARTx, format, args);
 906:	354d                	jal	7a8 <neorv32_uart_vprintf>
  va_end(args);
}
 908:	40f2                	lw	ra,28(sp)
 90a:	6121                	addi	sp,sp,64
 90c:	8082                	ret

0000090e <memcpy>:
 90e:	00050313          	mv	t1,a0
 912:	00060e63          	beqz	a2,92e <memcpy+0x20>
 916:	00058383          	lb	t2,0(a1)
 91a:	00730023          	sb	t2,0(t1)
 91e:	fff60613          	addi	a2,a2,-1 # 7fffffff <__neorv32_rom_size+0x7fffbfff>
 922:	00130313          	addi	t1,t1,1
 926:	00158593          	addi	a1,a1,1
 92a:	fe0616e3          	bnez	a2,916 <memcpy+0x8>
 92e:	00008067          	ret

00000932 <memset>:
 932:	00050313          	mv	t1,a0
 936:	00060a63          	beqz	a2,94a <memset+0x18>
 93a:	00b30023          	sb	a1,0(t1)
 93e:	fff60613          	addi	a2,a2,-1
 942:	00130313          	addi	t1,t1,1
 946:	fe061ae3          	bnez	a2,93a <memset+0x8>
 94a:	00008067          	ret
 94e:	0000                	.insn	2, 0x

00000950 <strlen>:
 950:	00050793          	mv	a5,a0
 954:	0007c703          	lbu	a4,0(a5)
 958:	00178793          	addi	a5,a5,1
 95c:	fe071ce3          	bnez	a4,954 <strlen+0x4>
 960:	40a78533          	sub	a0,a5,a0
 964:	fff50513          	addi	a0,a0,-1
 968:	00008067          	ret
