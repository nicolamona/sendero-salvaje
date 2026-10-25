# Economía cripto — Sendero Salvaje

## Estado y alcance

Este documento define una integración gradual para el juego web actual, publicado como sitio estático/PWA. La primera etapa es de **prueba en testnet**: no recibe dinero real, no promete retiros y no modifica combate, inventario, guardado ni progreso existentes.

El juego hoy guarda el progreso en `localStorage`; por lo tanto, las monedas actuales son datos locales manipulables y **no deben convertirse automáticamente en tokens, saldo canjeable ni prueba de pago**.

## Objetivo del producto

- Permitir que el jugador conecte una billetera propia.
- Mostrar una economía cripto separada de las monedas actuales del juego.
- Más adelante, permitir compras opcionales de contenido digital mediante una transacción en cadena verificable.
- No custodiar frases semilla, claves privadas ni fondos de jugadores.
- Mantener la experiencia AR espacial y el juego disponibles si la billetera, la red o el proveedor fallan.

## Arquitectura propuesta

### 1. Cliente web (GitHub Pages)

- Módulo aislado `crypto-wallet.js`, cargado de forma opcional.
- Conexión de billetera mediante un proveedor compatible EVM; nunca pedir ni almacenar frase semilla o clave privada.
- Mostrar claramente red, activo, dirección abreviada, importe, comisión estimada y enlace de explorador antes de pedir confirmación.
- No tratar un mensaje de éxito del navegador como prueba de pago.
- No cambiar el saldo actual de monedas ni el guardado del juego por el solo hecho de conectar una billetera.
- Si no hay billetera o la red falla, ocultar/deshabilitar únicamente las funciones cripto; el juego principal sigue funcionando.

### 2. Contrato inteligente (solo después de elegir red y reglas)

- En primera instancia usar una testnet EVM y activos de prueba sin valor monetario.
- No desplegar un token con expectativa de rentabilidad ni una mecánica de inversión.
- Para una primera compra, preferir pagos directos por un producto digital definido en vez de crear un token fungible especulativo.
- Si posteriormente se necesita un token propio, definir antes suministro, emisión, distribución, utilidad, permisos administrativos, pausado de emergencia y estrategia de actualización; revisión independiente antes de usar fondos reales.
- No habilitar premios o retiros en dinero en la primera versión.

### 3. Verificador de pagos (backend separado)

Un sitio estático no puede validar pagos con seguridad por sí solo. Antes de vender contenido real se necesita un verificador de solo lectura y un registro persistente. Se puede evaluar un nivel gratuito de Cloudflare Workers + D1, sujeto a límites y disponibilidad del proveedor.

El verificador debe:
1. Recibir una referencia de compra y consultar la cadena/RPC desde el servidor.
2. Validar red/chain ID, contrato permitido, destinatario, activo, importe mínimo, emisor cuando corresponda y estado de confirmación.
3. Comprobar que la transacción/evento pertenece a una compra pendiente emitida por el servidor.
4. Guardar `chainId + transactionHash + logIndex` con restricción única para impedir doble acreditación.
5. Ser idempotente: repetir una notificación o consulta no puede entregar el artículo dos veces.
6. Acreditar únicamente el producto definido en la compra; no acreditar saldo monetario por valores enviados desde el cliente.
7. Registrar estados `pending / confirmed / failed / expired`, con límites de frecuencia y registros de auditoría.
8. No almacenar claves privadas ni firmar transacciones de los usuarios.

Los eventos de una cadena pueden reorganizarse; el número de confirmaciones debe ser configurable por red. No acreditar depósitos solo por ver un hash pegado por el usuario.

### 4. Identidad y persistencia

- Conectar una billetera no equivale a autenticar una cuenta del juego. Si se necesita un perfil en la nube, usar un desafío de un solo uso con nonce, vencimiento y firma de la billetera; verificar la firma en servidor para evitar replay.
- Mantener separadas la identidad del juego, la dirección de billetera y las compras.
- No almacenar datos sensibles ni depender de `localStorage` como registro financiero.
- Crear copias de seguridad y pruebas antes de migrar o sincronizar cualquier progreso existente.

## Fases de implementación

### Fase 0 — diseño (este documento)
- Definir alcance, límites de seguridad y separación de sistemas.
- No se cambia la lógica del juego.

### Fase 1 — prototipo de billetera en testnet
- Elegir red EVM de testnet.
- Añadir una tarjeta opcional de billetera, indicador de red y conexión/desconexión.
- Mostrar dirección abreviada y estado de conexión; sin depósitos reales, sin transferencias automáticas y sin modificar monedas del juego.
- Probar que el juego y la AR funcionan cuando no hay billetera, se rechaza una conexión o el proveedor falla.

### Fase 2 — compra de prueba
- Contrato mínimo de venta de contenido o mecanismo equivalente.
- Verificador de pagos y base de datos.
- Pruebas de doble envío, hash falso, red equivocada, importe insuficiente, transacción pendiente, reintento y desconexión.
- Solo testnet y activos sin valor.

### Fase 3 — evaluación de lanzamiento real
- Elegir activo/red, estimar comisiones y experiencia para usuarios.
- Revisión de seguridad del contrato y del backend.
- Evaluar requisitos legales, fiscales, protección al consumidor y reglas de proveedores aplicables en Argentina y otros territorios.
- Habilitar dinero real solo tras resolver estos puntos; cero presupuesto inicial no garantiza que el lanzamiento real sea gratuito.

## Criterios de aceptación

- No hay cambios en combate, recompensas actuales, inventario, guardado local ni experiencia AR espacial.
- Sin conexión de billetera, el juego sigue funcionando normalmente.
- Nunca se solicitan frases semilla ni claves privadas.
- La interfaz distingue explícitamente testnet de red principal.
- Una transacción no puede acreditarse dos veces.
- No se publicitan depósitos, token con valor o retiros hasta que existan infraestructura y condiciones verificadas.

## Decisiones pendientes antes de programar la conexión

1. Red de prueba EVM (por ejemplo, Base Sepolia o Polygon Amoy; confirmar disponibilidad y soporte actuales).
2. Primera utilidad: comprar contenido cosmético/efectos, o solo conectar la billetera para pruebas.
3. Más adelante, si corresponde, activo y red para producción.

**Recomendación:** empezar con conexión de billetera en testnet, sin token propio ni fondos reales. Es la forma de probar la experiencia sin poner en riesgo el juego ni el dinero de nadie.
