#include <cstddef>

extern "C" void *malloc(std::size_t);
extern "C" void free(void *);

// Soporte mínimo para C++ bare-metal. No se vincula libstdc++ en esta toolchain.
void *operator new(std::size_t size) noexcept { return malloc(size); }
void *operator new[](std::size_t size) noexcept { return malloc(size); }
void operator delete(void *ptr) noexcept { free(ptr); }
void operator delete[](void *ptr) noexcept { free(ptr); }
void operator delete(void *ptr, std::size_t) noexcept { free(ptr); }
void operator delete[](void *ptr, std::size_t) noexcept { free(ptr); }

extern "C" void __cxa_pure_virtual() { for (;;) __asm__ volatile("nop"); }
extern "C" int __cxa_atexit(void (*)(void *), void *, void *) { return 0; }
void *__dso_handle;

