# PROMPT DE CONTINUIDAD — PROYECTO ALERTATRIP (V4)

Fecha: 5 de septiembre de 2026
Última sesión: Integración de fuentes híbridas (Travelpayouts + Kiwi/Skypicker)

---

## PRÓXIMO PASO INMEDIATO AL RETOMAR

El usuario está implementando una **estrategia de búsqueda híbrida** para resolver el problema de que Travelpayouts Data API devuelve solo resultados cacheados (24-72h). La prioridad inmediata depende de qué componente elija tocar primero (Worker web, Bot VPS, o App Flutter). **NO empezar por otro tema sin confirmar con el usuario.**

---

## CONTEXTO GENERAL

AlertaTrip: plataforma de búsqueda de vuelos con alertas de precio.

### Repositorios

- **App Flutter:** https://github.com/stationnet2/alertatrip_app/tree/main/lib
- **Web Cloudflare Pages:** https://github.com/stationnet2/aerolineascopia/tree/main/proyectoclouflare
- **Bot (VPS):** NO está en repo. Vive en `/home/alertatrip/bot/check-flight-prices.js` (DonWeb, Ubuntu 24.04, IP `149.34.225.40`, SSH puerto `5138`)
- **Worker Cloudflare:** NO está en repo. Vive solo en el dashboard de Cloudflare (`api-alertatrip.descuentonadrian.workers.dev`). El código fuente completo (v5) está en el archivo `user_pasted_clipboard_long_content_as_file_api-alertatrip Wo.txt` de esta sesión.

### Infraestructura

- **Cloudflare Pages:** aloja `index.html` (web)
- **Cloudflare Worker:** proxy de API + admin Firestore + pagos + búsqueda de vuelos
- **Firebase:** Firestore + Auth email/password + FCM
- Project: `alerta-vuelos-49ba1`
- Colecciones: `destinations`, `popular_destinations`, `flightAlerts`, `flightNotifications`, `users`, `appConfig`
- **VPS DonWeb:** bot de alertas con cron cada 30 min (actualmente, a revisar)

### Pagos (v5) — FUNCIONANDO

- **Mercado Pago:** Checkout Pro, producción, probado `/create-mp-preference`. Webhook `/mp-webhook` escrito, NO probado end-to-end.
- **Lemon Squeezy:** Test mode funcionando (`/create-lemonsqueezy-checkout`). Cuenta en revisión por Lemon Squeezy. Webhook `/lemonsqueezy-webhook` escrito, NO probado end-to-end.
- **Activación Premium:** server-side vía webhooks → `activatePremiumInFirestore()` → escribe `plan: 'premium'`, `planExpiresAt`, `lastPaymentProvider`, `lastPaymentAt` en `users/{uid}`.
- **Variables cargadas en Cloudflare:** `MERCADOPAGO_ACCESS_TOKEN`, `LEMONSQUEEZY_API_KEY`, `LEMONSQUEEZY_STORE_ID=466721`, `LEMONSQUEEZY_PRODUCT_ID=1338284`, `LEMONSQUEEZY_WEBHOOK_SECRET`, `PREMIUM_MONTHS=6`, `PREMIUM_PRICE_ARS=6500`, `SITE_URL=https://alertatrip.com`

---

## 🔴 PROBLEMA ACTIVO: Travelpayouts solo devuelve cache

### Situación

- Travelpayouts Data API (`/v3/prices_for_dates`) devuelve precios cacheados (24-72h).
- Para muchas fechas/rutas devuelve array vacío porque no está en cache.
- El usuario pidió acceso a **Travelpayouts Flight Search API** (la oficial, en vivo). Respuesta de soporte: **requiere 50.000 MAU**.
- Kayak Affiliate: aplicación enviada, **sin respuesta**.
- Amadeus: self-service cerrado julio 2026.
- Skyscanner: requiere 5.000 visitas/mes (no se tiene todavía).

### Única alternativa viable HOY

**Kiwi.com / Skypicker API directa** (`api.skypicker.com`):

- Endpoint no oficial (usa el sitio web de Kiwi).
- No requiere API key.
- Devuelve precios más frescos que Travelpayouts.
- Es la misma base de datos que usa Travelpayouts/Aviasales.
- **Riesgo:** puede cambiar de URL, bloquear IP, o desaparecer sin aviso.

### Decisión de negocio tomada

- **La búsqueda y las alertas usarán fuente híbrida:** Travelpayouts (oficial, afiliado) + Kiwi directo (fallback/verificación).
- **El link de compra SIEMPRE va a Aviasales con `marker=761958`** para no perder comisión.
- Kiwi se usa para saber si el vuelo existe y a qué precio, pero la monetización sigue siendo via Travelpayouts/Aviasales.

---

## 🎯 ESTRATEGIA TÉCNICA APROBADA (híbrida)

### Para la Web / App (Worker de Cloudflare)

1. El usuario busca una ruta y fecha.
2. El Worker consulta **Travelpayouts** primero.
3. Si Travelpayouts devuelve vacío, consulta **Kiwi directo** como fallback.
4. Si Travelpayouts tiene resultados, también consulta Kiwi para mostrar "precio verificado".
5. Se combinan ambos, eliminando duplicados por precio+aerolínea+fecha.
6. El `link` de cada resultado SIEMPRE se construye para Aviasales con `marker=761958`.
7. Se muestra un badge indicando la fuente ("referencial" vs "verificado").

### Para el Bot del VPS (alertas)

1. El bot consulta **Travelpayouts** para TODAS las alertas (gratis y premium).
2. **Solo para alertas Premium:** cuando Travelpayouts detecta una bajada significativa (threshold configurado, ej: 15%), el bot consulta **Kiwi** para verificar.
3. Si Kiwi confirma la bajada (precio similar o menor) → notificación push al usuario.
4. Si Kiwi NO confirma → falso positivo por cache, no se notifica.
5. **Kiwi NUNCA se consulta para alertas gratuitas.** Es un feature Premium.
6. Se agrega delay de 500ms entre requests a Kiwi para evitar rate limit.
7. Si Kiwi responde 429/403, el bot debe guardar un flag y dejar de consultar Kiwi por 6 horas.

### Deduplicación en el bot

- Agrupar alertas por ruta+fecha antes de consultar. Si 50 usuarios tienen alerta EZE→BRC 15/10, se hace 1 solo request y se compara contra los 50 umbrales.
- Cache local en VPS (`/home/alertatrip/bot/cache.json`) con TTL de 1 hora.

---

## 📋 PLANES DE USUARIO (propuesta, a confirmar por usuario)

| Feature | Gratis | Premium |
| --- | --- | --- |
| **Búsqueda de vuelos** | ✅ Ilimitada (Travelpayouts + Kiwi) | ✅ Ilimitada (Travelpayouts + Kiwi) |
| **Alertas** | **1 alerta** / 1 mes | **12 alertas** / 6 meses |
| **Monitoreo bot** | Cada **6 horas** | Cada **1 hora** |
| **Fuente de alertas** | Solo Travelpayouts | Travelpayouts + **Kiwi verificación** |
| **Notificación** | Push básica | Push "✅ Precio verificado en vivo" |
| **Precio** | Gratis | USD $5 / ARS $6.500 |

**Nota:** El usuario estaba evaluando bajar las alertas gratis de 2 a 1, y la frecuencia de 30 min a 6 horas (gratis) y 1 hora (premium). **NO está confirmado todavía.** Preguntar al retomar.

---

## 🔴 PENDIENTES POR COMPONENTE

### 1. Worker de Cloudflare (api-alertatrip)

**Estado:** v5 funcionando con pagos + búsqueda Travelpayouts.
**Falta:**

- [ ] Agregar función `searchKiwiDirect()` al Worker.
- [ ] Modificar `handleSearchFlights()` para consultar ambas fuentes en paralelo.
- [ ] Normalizar respuesta de Kiwi al mismo formato que Travelpayouts.
- [ ] Construir `link` SIEMPRE apuntando a Aviasales con `marker=761958`.
- [ ] Agregar `meta` en la respuesta JSON (`travelpayouts_count`, `kiwi_count`, `fallback_used`).
- [ ] (Opcional) Agregar endpoint `/search-kiwi` separado para debug.

**Variables de entorno nuevas necesarias:** Ninguna. Kiwi no requiere API key.

### 2. Web (index.html en Cloudflare Pages)

**Estado:** Actualizado con botones de pago reales (MP + Lemon Squeezy), sin `activatePremium()` en navegador.
**Falta:**

- [ ] Modificar renderizado de resultados para mostrar badge de fuente.
- [ ] Mostrar precio de Kiwi al lado del de Travelpayouts cuando ambos existen.
- [ ] Botón "Reservar" siempre con link a Aviasales (con marker).
- [ ] Subir `index.html` actualizado al repo y deployar en Cloudflare Pages (NO confirmado si ya se hizo).
- [ ] Verificar que `appConfig/system` en Firestore tenga los precios actualizados (ver sección abajo).

### 3. Bot del VPS (check-flight-prices.js)

**Estado:** Funcionando, corrige bug de re-notificación. Usa `CITY_AIRPORTS` hardcodeado (versión clásica + fix).
**Falta:**

- [ ] Agregar función `verifyPriceWithKiwi()` para alertas Premium.
- [ ] Modificar lógica de notificación: solo verificar con Kiwi cuando TP detecta bajada.
- [ ] Agregar delay de 500ms entre requests a Kiwi.
- [ ] Agregar manejo de errores 429/403 (flag + cooldown 6h).
- [ ] Implementar deduplicación por ruta+fecha.
- [ ] Implementar cache local (`cache.json`) con TTL 1h.
- [ ] Revisar frecuencia del cron (actualmente 30 min, propuesta: 1h premium / 6h gratis).
- [ ] **Confirmar:** ¿el bot lee ciudades desde Firestore (`appConfig`) o sigue con `CITY_AIRPORTS` hardcodeado? (Nunca se confirmó. Probablemente es la versión clásica sin mejoras de Kimi.)

### 4. App Flutter (alertatrip_app)

**Estado:** Compilable, sin publicar en stores. Pagos NO integrados todavía.
**Falta:**

- [ ] **PRIORIDAD:** Corregir `lib/models/flight_alert.dart` para usar `Timestamp` en vez de `toIso8601String()` / `DateTime.parse()`.
- [ ] Agregar `import 'package:cloud_firestore/cloud_firestore.dart';`
- [ ] En `toFirestore()`: `dateFrom` → `Timestamp.fromDate()`, `createdAt` → `FieldValue.serverTimestamp()`.
- [ ] En `fromFirestore()`: usar helper `_parseDate()` que soporte `Timestamp` y `String`.
- [ ] Integrar búsqueda híbrida (consumir Worker con resultados multi-fuente).
- [ ] Definir estrategia de pagos en app: ¿WebView a endpoints del Worker? ¿O In-App Purchase nativo? (Pendiente de decisión.)
- [ ] Publicar en stores (Google Play / App Store).

### 5. Firebase

**Falta:**

- [ ] **URGENTE:** Corregir reglas de Firestore. Actualmente:

```javascript
  match /flightAlerts/{doc} { allow read, write: if request.auth != null; }
  match /flightNotifications/{doc} { allow read, write: if request.auth != null; }
```

Debería ser `request.auth.uid == resource.data.userId` para evitar que cualquier usuario logueado lea/escriba alertas ajenas.

- [ ] Verificar documento `appConfig/system` en Firestore tenga los valores correctos:

```json
  {
    "defaultAlertThresholdPercent": 15,
    "freePlan": { "maxAlerts": 1, "months": 1, "name": "Gratis" },
    "premiumPlan": { "maxAlerts": 12, "months": 6, "priceUSD": 5, "priceARS": 6500, "name": "Premium" },
    "minMaxPriceUSD": 20,
    "autoMaxPriceFactor": 0.5,
    "botCheckIntervalMinutes": 60,
    "batchSize": 5,
    "batchDelayMs": 2000,
    "currency": "usd"
  }
```

**Nota:** `freePlan.maxAlerts` y `botCheckIntervalMinutes` pueden cambiar según decisión final del usuario.

---

## ✅ COMPLETADO EN SESIONES ANTERIORES (resumen)

### Pagos (v5)

- Mercado Pago: `/create-mp-preference` probado y funcionando en producción.
- Lemon Squeezy: `/create-lemonsqueezy-checkout` probado en test mode.
- Activación Premium: server-side vía webhooks, sin agujero de seguridad en navegador.
- `index.html`: botones reales de pago, manejo de URL params `?premium=success/pending/failure`.

### Seguridad

- Agujero `activatePremium()` en navegador: **CERRADO** ✅
- Reglas Firestore permisivas: **SIGUEN SIN RESOLVER** 🔴

### Bot VPS

- Bug de re-notificación de mismo precio: **CORREGIDO** ✅
- Instalación en VPS con cron + flock: **FUNCIONANDO** ✅

---

## 🛡️ RIESGOS Y MITIGACIONES

| Riesgo | Impacto | Mitigación |
| --- | --- | --- |
| Kiwi bloquea IP del VPS | Alto | Bot usa Kiwi solo para premium + delay entre requests + cooldown ante 429/403. Si falla, seguir con TP solo. |
| Kiwi cambia URL o cierra endpoint | Alto | Código encapsulado en función `searchKiwiDirect()`. Si falla, retorna `[]` silenciosamente. TP sigue funcionando. |
| Rate limit en Worker de Cloudflare | Bajo | Worker usa IPs rotativas de Cloudflare. Volumen bajo (solo búsquedas de usuarios). |
| Usuario anónimo hace miles de búsquedas | Medio | Sin límite actual. Si aparece abuso, implementar rate limit por IP en el Worker. |
| Precisión de precios ida y vuelta | Medio | Problema histórico sin resolver. `/v3/prices_for_dates` es cacheada. Con Kiwi + TP se mejora pero no se elimina. |
| Lemon Squeezy no aprueba cuenta | Medio | Si rechazan, evaluar alternativas (Stripe no funciona en Argentina sin trucos, PayPal no es ideal). MP cubre ARS. |

---

## 📝 NOTAS PARA LA PRÓXIMA IA

1. **El usuario NO quiere que le pases todo el código de una.** Prefiere ir paso a paso, confirmando cada parte antes de seguir.
2. **El usuario pega código sensible directo en el chat** (tokens, service accounts). NUNCA pedirle que los pegue si no es necesario.
3. **El usuario usa FileZilla + nano en el VPS.** Dar instrucciones explícitas paso a paso, un comando a la vez.
4. **El usuario no tiene experiencia previa en terminal.** Fue aprendiendo sobre la marcha.
5. **El código del Worker v5 está en el archivo adjunto** de esta sesión (`user_pasted_clipboard_long_content_as_file_api-alertatrip Wo.txt`). Si no está en contexto, pedirselo al usuario.
6. **La app Flutter tiene un bug en `flight_alert.dart`** sin corregir (formato de fecha Timestamp vs String). Es prioridad cuando se retome "lo de la app".
7. **El bot en el VPS probablemente es la versión clásica** (sin mejoras de Kimi). Confirmar antes de asumir.
8. **El usuario cobra Premium por alertas, no por búsqueda.** La búsqueda es gratuita y anónima. El valor está en las alertas verificadas.

---

## 📞 CONTACTOS Y REFERENCIAS

- **Travelpayouts soporte:** Pedido de Flight Search API rechazado (requiere 50k MAU).
- **Kayak Affiliate:** Aplicación enviada, sin respuesta.
- **Lemon Squeezy:** Cuenta en revisión. Store "AlertaTrip" (`alertatrip.lemonsqueezy.com`).
- **Mercado Pago:** Cuenta developer + app "alertatrip" en producción.
- **VPS DonWeb:** `ssh -p5138 alertatrip@149.34.225.40`, bot en `/home/alertatrip/bot/`

---

*Documento generado el 5 de septiembre de 2026. Última actualización: estrategia híbrida Travelpayouts + Kiwi/Skypicker aprobada por el usuario.*