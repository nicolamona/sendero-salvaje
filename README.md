# Sendero Salvaje — primera versión web

## Qué incluye
- Juego móvil con combate por turnos contra tres monstruos.
- Experiencia, niveles, monedas, pociones, trofeos y curación.
- Guardado local del progreso mediante `localStorage`.
- Acceso opcional al GPS del dispositivo (solicita permiso).
- Modo de realidad aumentada espacial con WebXR Hit Test para colocar una criatura en una superficie detectada (requiere dispositivo/navegador compatibles y permisos).
- Modo de cámara clásica como alternativa visual si el dispositivo no admite AR espacial.
- Contrato del explorador: derrota 3 criaturas para cobrar 50 monedas y una poción.
- Acceso opcional a la cámara trasera (solicita permiso).
- Estructura PWA básica para instalar/abrir como app cuando se publique por HTTPS.

## Cómo probar
1. Descomprimí el ZIP.
2. Para una prueba sencilla, abrí `index.html` en el navegador. El combate funciona, pero GPS/cámara y PWA pueden no funcionar desde `file://`.
3. Para GPS/cámara, publicá los archivos en un hosting HTTPS estático, por ejemplo GitHub Pages.
4. Abrí la URL HTTPS desde el celular y aceptá permisos cuando el navegador los solicite.

## Límites de esta versión
- No tiene cuentas ni sincronización en la nube; el progreso queda en ese navegador/dispositivo.
- Los monstruos se generan dentro del juego, no por GPS real ni por ubicación geográfica.
- La AR espacial usa WebXR Hit Test cuando el navegador y el dispositivo lo admiten; no todos los teléfonos Android son compatibles. La cámara clásica sigue siendo una superposición visual de prueba.
- El GPS no se envía a ningún servidor.
- Antes de usarlo caminando, hay que detenerse en un lugar seguro para combatir.

## Publicación
Subí `index.html`, `manifest.json` y `sw.js` a un repositorio nuevo e independiente y activá Pages/hosting estático con HTTPS. No reutilices repositorios de otros proyectos.
