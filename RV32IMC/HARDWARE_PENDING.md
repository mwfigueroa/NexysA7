# Backlog de mejoras menores de hardware

Estado: pendiente de implementar. Estas mejoras no sustituyen la revisión de
integración ROV; son endurecimientos para el diseño base de Nexys A7/NEORV32.

1. **Debounce real del reset.** El sincronizador de cuatro flip-flops libera el
   reset de forma segura, pero solo dura 40 ns a 100 MHz y no filtra el rebote
   mecánico del pulsador. Añadir un contador de aproximadamente 5 a 20 ms antes
   de liberar `rstn_safe`.

2. **Armar PWM sin glitches.** Sincronizar `SW[0]` con dos flip-flops y aplicar
   su cambio al comienzo de un período PWM (o mediante un estado de desarme).
   Así no se recorta un pulso cuando se mueve la llave de armado.

3. **IRQ de usuario como evento limpio.** Aplicar debounce a `SW[1]` y generar
   un pulso de un ciclo en el flanco, en lugar de entregar un nivel sostenido a
   `irq_mei_i`. Esto evita una cascada de interrupciones mientras la llave sigue
   activada.

