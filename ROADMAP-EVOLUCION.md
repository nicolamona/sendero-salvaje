# Sendero Salvaje — plan de evolución

## Objetivo
Elevar la presentación a una aventura móvil más cinematográfica, atmosférica y memorable, preservando el comportamiento actual del juego.

## Reglas de seguridad
- No modificar mecánicas, combate, recompensas, economía, misiones, inventario, descubrimientos ni estructura de datos durante la etapa visual.
- No borrar ni reinicializar `localStorage`; no cambiar las claves de guardado.
- Trabajar en una rama separada y conservar una rama de respaldo anterior a la evolución.
- Cada etapa debe ser pequeña, revisable y reversible.
- No considerar una publicación comprobada hasta verificarla en el sitio desplegado y, cuando sea posible, en un teléfono.

## Etapa 1 — pulido visual (en curso)
- Mantener la dirección de arte actual: noche mineral, piedra, niebla y cobre.
- Agregar movimiento ambiental muy sutil al bosque y al escenario de criaturas usando solo CSS.
- Respetar `prefers-reduced-motion`.
- Actualizar la caché del service worker para que el navegador pueda recibir la nueva presentación.
- No tocar JavaScript de juego.

## Etapa 2 — audiovisual, separada
- Evaluar sonidos ambientales y efectos breves de interfaz/combate.
- Añadir controles de audio accesibles y respetar el permiso/gesto explícito del usuario.
- Mantener el audio opcional, con volumen moderado y sin reproducción automática inesperada.
- Esta etapa requiere revisar el flujo de audio por separado; no forma parte del cambio CSS inicial.

## Etapa 3 — mundo y criaturas, primero presentación
- Mejorar visualmente biomas, rarezas, jefes, estados de encuentro y descubrimientos.
- Priorizar recursos livianos para móviles y alternativas cuando no haya soporte gráfico.
- Cualquier nueva conducta de criaturas o mecánica se pospone a una etapa de diseño independiente.

## Etapa 4 — pruebas antes de integrar
Lista de comprobación manual:
- La web carga en móvil y escritorio sin errores visibles.
- Las vistas de explorar, combate e inventario siguen navegables.
- Los botones de ataque, curación, huida, cámara clásica y AR mantienen su comportamiento.
- Las barras de salud/experiencia, misiones, recompensas y guardado siguen funcionando.
- El progreso preexistente permanece intacto.
- La versión publicada muestra el cambio tras actualizar la caché.
- Revisar animaciones con reducción de movimiento activada.

## Ramas
- Respaldo previo: `backup/pre-evolucion-2026-10-25`
- Trabajo visual: `visual/evolucion-integral-v1`

## Estado
La rama de trabajo es experimental y no debe considerarse desplegada ni completamente probada hasta completar las verificaciones anteriores.
