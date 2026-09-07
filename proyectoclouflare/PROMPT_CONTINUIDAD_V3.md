# PROMPT DE CONTINUIDAD — PROYECTO ALERTATRIP (V3, el más actualizado)
Fecha: 4 de septiembre de 2026

## PRÓXIMO PASO INMEDIATO AL RETOMAR
El usuario dijo explícitamente: **"recordá que también tenemos que seguir con lo de la app"** —
la próxima prioridad es la **app Flutter**, específicamente el bug de `flight_alert.dart` sin
corregir (ver sección "PENDIENTE #1" más abajo). Empezar preguntando por eso, no por otra cosa,
salvo que el usuario diga lo contrario.

---

## CONTEXTO GENERAL
AlertaTrip: plataforma de búsqueda de vuelos con alertas de precio.
- **Travelpayouts/Aviasales** como fuente de vuelos (marker=761958)
- **Firebase** (Firestore + Auth email/password + FCM) — NO se migra a Postgres/VPS (decisión tomada y fundamentada, Firestore aguanta la escala que busca el usuario, el tema sería de costo no de capacidad)
- **Cloudflare Pages** aloja la web (`aerolineascopia/proyectoclouflare/index.html`)
- **Cloudflare Worker** (`api-alertatrip.descuentonadrian.workers.dev`) — proxy de API + admin Firestore + **pagos** (nuevo). Código fuente NO vive en ningún repo, el usuario lo pega directo en el chat cuando hace falta.
- **Bot** (`check-flight-prices.js`) corriendo en **VPS propio** (DonWeb), ya NO en GitHub Actions
- **App Flutter** (`alertatrip_app` repo) — compilable a Android/iOS, aún no publicada en stores

## REPOS
- App Flutter: https://github.com/stationnet2/alertatrip_app
- Web Cloudflare: https://github.com/stationnet2/aerolineascopia/tree/main/proyectoclouflare
- Bot: NO está en ningún repo, vive solo en el VPS
- Worker de Cloudflare: NO está en ningún repo, vive solo en el dashboard de Cloudflare

## VPS (bot) — funcionando, sin cambios recientes
- Host `149.34.225.40`, DonWeb, Ubuntu 24.04, Node v24, **puerto SSH 5138** (no 22)
- Conectar: `ssh -p5138 alertatrip@149.34.225.40`
- Bot en `/home/alertatrip/bot/`, cron cada 30 min con `flock` anti-solapamiento
- Bug de re-notificación de mismo precio ya corregido y confirmado funcionando
- El usuario sube archivos con FileZilla, edita con nano, sin experiencia previa en terminal (aprendió durante esta sesión)

## FIREBASE
- Project: `alerta-vuelos-49ba1`
- Colecciones: `destinations`, `popular_destinations`, `flightAlerts`, `flightNotifications`, `users`, `appConfig`

---

## ✅ COMPLETADO EN ESTA ÚLTIMA SESIÓN: Pagos reales (Mercado Pago + Lemon Squeezy)

### Decisiones de negocio
- Plan Premium: 12 alertas, **6 meses**, renovación **manual** (no recurrente)
- Precio: **USD $5** (internacional, vía Lemon Squeezy) / **ARS $6.500** (Argentina, vía Mercado Pago)
- El usuario cobra en Lemon Squeezy con **payout a PayPal** (no bancario) — así el dinero queda "afuera" del circuito bancario argentino, que era su objetivo (eventualmente comprar USDT). Se le avisó que esto tiene implicancias impositivas en Argentina y se le recomendó un contador; no se dio asesoramiento legal/fiscal.

### Mercado Pago — LISTO Y PROBADO
- Cuenta developer + app "alertatrip" creada, modalidad **Checkout Pro**
- **Credenciales de PRODUCCIÓN obtenidas** (Access Token `APP_USR-...`), cargadas en Cloudflare como secret `MERCADOPAGO_ACCESS_TOKEN`
- Endpoint `/create-mp-preference` **probado y funcionando** (devuelve `init_point` real)
- Endpoint `/mp-webhook` escrito pero **NO probado end-to-end todavía** (falta hacer un pago de prueba real o simular el webhook)

### Lemon Squeezy — LISTO Y PROBADO, cuenta pendiente de aprobación
- Cuenta creada, país Argentina, tienda "AlertaTrip" (`alertatrip.lemonsqueezy.com`)
- Store ID: `466721` — Product ID: `1338284` ("AlertaTrip Premium", $5 USD, single payment)
- **Cuenta en proceso de revisión por Lemon Squeezy** ("Your application has been received and will be reviewed"). Mientras tanto solo se pueden usar credenciales/API Keys de **test mode**.
- Payout configurado a **PayPal** (después de descartar CBU argentino y de que Wise no fuera aceptado por Stripe Connect — Lemon Squeezy usa Stripe por detrás para los payouts, y Stripe exige CBU si el país registrado es Argentina, salvo que se elija PayPal como método alternativo, que sí se pudo activar)
- Formulario W-8BEN completado (persona no-US)
- Endpoint `/create-lemonsqueezy-checkout` **probado y funcionando** en modo test (devuelve URL de checkout real). Busca dinámicamente la variante del producto vía API (`?include=variants`), no requiere hardcodear el variant ID.
- Endpoint `/lemonsqueezy-webhook` escrito, webhook configurado en Lemon Squeezy apuntando a `https://api-alertatrip.descuentonadrian.workers.dev/lemonsqueezy-webhook`, evento `order_created`, firma HMAC-SHA256 verificada con signing secret. **NO probado end-to-end todavía** (falta completar un pago de prueba real con tarjeta de test).

### ⚠️ PENDIENTE cuando Lemon Squeezy apruebe la cuenta
1. Ir a Settings → API → generar una API Key nueva en modo **Live** (reemplaza la de test en la variable `LEMONSQUEEZY_API_KEY` de Cloudflare)
2. Ir al producto "AlertaTrip Premium" → usar la opción **"Copy to Live Mode"** (los productos de test mode NO pasan solos a producción)
3. Confirmar que el nuevo Product ID en modo Live sea el mismo o actualizarlo en `LEMONSQUEEZY_PRODUCT_ID`

### Worker de Cloudflare — v5, código completo entregado al usuario
Contiene, sin tocar las rutas viejas (`/special-offers`, `/search-flights`, `/admin-destinations`):
- `/create-mp-preference` (POST, body `{userId}`) → devuelve `{init_point}`
- `/mp-webhook` → verifica el pago consultando la API de MP con el Access Token (nunca confía en el payload solo), si `status==='approved'` activa premium
- `/create-lemonsqueezy-checkout` (POST, body `{userId}`) → busca la variante del producto dinámicamente, devuelve `{url}`
- `/lemonsqueezy-webhook` → verifica firma HMAC con el signing secret, si `event_name==='order_created' && status==='paid'` activa premium
- Función común `activatePremiumInFirestore(userId, env, provider)` reutiliza el mecanismo de JWT+Firestore REST que ya existía en `handleAdmin()` (mismo patrón `getAccessToken`/`toFirestoreFields`), escribe `plan: 'premium'`, `planExpiresAt` (ahora + `PREMIUM_MONTHS`), `lastPaymentProvider`, `lastPaymentAt` en `users/{uid}`
- Variables de entorno (Secrets) cargadas: `MERCADOPAGO_ACCESS_TOKEN`, `LEMONSQUEEZY_API_KEY`, `LEMONSQUEEZY_STORE_ID=466721`, `LEMONSQUEEZY_PRODUCT_ID=1338284`, `LEMONSQUEEZY_WEBHOOK_SECRET`, `PREMIUM_MONTHS=6`, `PREMIUM_PRICE_ARS=6500`, `SITE_URL=https://alertatrip.com`

Si esta IA no tiene el código completo del worker-v5.js en su contexto, pedírselo al usuario — lo tiene guardado, ya lo compartió una vez.

### index.html — actualizado y entregado al usuario
- Botones de pago viejos (Stripe/PayPal/MP simulados con `setTimeout`) reemplazados por 2 botones reales: Mercado Pago (llama a `/create-mp-preference`, redirige a `init_point`) y Lemon Squeezy (llama a `/create-lemonsqueezy-checkout`, redirige a `url`)
- **`activatePremium()` fue ELIMINADO del navegador** — el agujero de seguridad donde cualquiera podía activarse Premium gratis desde la consola ya no existe. La activación ahora ocurre solo server-side, vía webhook, tras confirmar el pago
- Se agregó manejo de `?premium=success/pending/failure` en la URL de retorno, con un aviso simple (la actualización real del plan llega sola vía el listener de Firestore en tiempo real que la app ya tenía)
- Se corrigieron 4 lugares donde el precio viejo ($2 USD/año) estaba hardcodeado — ahora usan `appConfig.premiumPlan` dinámicamente (USD + ARS + meses)
- **Falta subir este archivo al repo y hacer deploy en Cloudflare Pages** — se lo dio al usuario como descarga, no se confirmó si ya lo subió

### ⚠️ PENDIENTE — verificar `appConfig/system` en Firestore
Nunca se confirmó si el documento `appConfig/system` en Firestore ya tiene los precios actualizados. Debería tener:
```json
{
  "defaultAlertThresholdPercent": 15,
  "freePlan": { "maxAlerts": 2, "months": 2, "name": "Gratis" },
  "premiumPlan": { "maxAlerts": 12, "months": 6, "priceUSD": 5, "priceARS": 6500, "name": "Premium" },
  "minMaxPriceUSD": 20,
  "autoMaxPriceFactor": 0.5,
  "botCheckIntervalMinutes": 30,
  "batchSize": 5,
  "batchDelayMs": 2000,
  "currency": "usd"
}
```
El `index.html` ya tiene estos valores como *fallback* local por si Firestore falla, pero conviene que también estén en Firestore como fuente única de verdad.

---

## 🔴 PENDIENTE #1 (PRIORIDAD INMEDIATA) — App Flutter, plan "Kimi" a medio terminar

Otra IA ("Kimi") generó un plan para unificar formatos de fecha entre App/Web/Bot centralizando en `appConfig/system`. Verificado clonando el repo (no asumir que el propio documento de Kimi refleja la realidad):

- `lib/services/alert_service.dart` → SÍ actualizado: valida límite de alertas contra `appConfig/system`, lee plan del usuario, cuenta TODAS las alertas. Bien aplicado.
- **`lib/models/flight_alert.dart` → NO actualizado.** Sigue usando `toIso8601String()` / `DateTime.parse()` en vez de `Timestamp`. Falta:
  - `import 'package:cloud_firestore/cloud_firestore.dart';`
  - En `toFirestore()`: cambiar `dateFrom?.toIso8601String()` → `dateFrom != null ? Timestamp.fromDate(dateFrom!) : null` (ídem `dateTo`), y `createdAt: createdAt.toIso8601String()` → `createdAt: FieldValue.serverTimestamp()`
  - En `fromFirestore()`: reemplazar `DateTime.parse(data['dateFrom'])` por una función helper `_parseDate()` que soporte ambos formatos:
    ```dart
    static DateTime? _parseDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }
    ```
- **Por qué importa:** si el bot del VPS espera `Timestamp` (no confirmado si ya se actualizó a una v2 que lo requiera — ver punto siguiente), las alertas nuevas creadas desde la app fallan silenciosamente.

### También sin confirmar: ¿el bot en el VPS sigue esperando el formato viejo o ya se actualizó?
Nunca se confirmó si el bot en el VPS lee ciudades/config desde Firestore (`appConfig`, plan "v2" de Kimi) o si sigue con `CITY_AIRPORTS` hardcodeado (la versión que se instaló y se corrigió en esta sesión, SIN el resto de los cambios de Kimi). El archivo `check-flight-prices-v2.js` que menciona el plan de Kimi nunca llegó adjunto al chat. Probablemente el bot actual en el VPS es la versión "clásica + fix de renotificación", sin las mejoras de Kimi (leer ciudades de Firestore, etc.) — confirmar con el usuario antes de asumir cualquier cosa.

### Además: la app Flutter no tiene integración de pagos todavía
Se armaron los pagos para la **web** (Mercado Pago + Lemon Squeezy). La app Flutter no tiene ningún flujo de pago — cuando se retome "lo de la app", probablemente haya que decidir:
- ¿La app usa un WebView a los mismos endpoints del Worker (`/create-mp-preference`, `/create-lemonsqueezy-checkout`), reutilizando todo el trabajo ya hecho?
- ¿O, si algún día se publica en las stores, hay que usar In-App Purchase de Apple/Google en su lugar (recordar el aviso dado en sesión anterior sobre políticas de las tiendas para contenido digital vendido dentro de la app)?
Esto no se definió todavía, es una conversación pendiente.

---

## 🔴 HALLAZGOS DE SEGURIDAD — SIGUEN SIN RESOLVER

### 1. Reglas de Firestore demasiado permisivas
```javascript
match /flightAlerts/{doc} {
  allow read, write: if request.auth != null; // debería exigir dueño, no solo estar logueado
}
match /flightNotifications/{doc} {
  allow read, write: if request.auth != null;
}
```
Debería ser `request.auth.uid == resource.data.userId`. Nadie lo tocó en ninguna sesión todavía.

### 2. El agujero del pago falso YA SE CERRÓ ✅
(Ver sección de pagos arriba — `activatePremium()` fue eliminado del navegador, ya no es explotable.)

---

## ⏸️ PENDIENTE SIN RETOMAR — precisión de precios ida y vuelta
El usuario reportó que a veces el precio ida y vuelta mostrado (ej. USD $252 a Bariloche) no coincide con la suma de ida + vuelta por separado (ej. $37 + $42 = $80). Causa: `/v3/prices_for_dates` es la Data API de Travelpayouts, cacheada, no en vivo. Opciones dadas: (a) aclaración textual en la UI, (b) migrar a la Search API real (firma MD5 + polling). El usuario priorizó otras cosas — sigue sin resolver, retomar cuando corresponda (no es la prioridad inmediata según el propio usuario).

---

## PERFIL DEL USUARIO
- Español (Argentina), GMT-3
- Sin experiencia previa en terminal/SSH antes de esta sesión — aprendió sobre la marcha, seguir dando instrucciones explícitas paso a paso, un comando a la vez
- Prefiere pegar código sensible directo en el chat en vez de compartir repos/tokens privados
- Nunca comparte contraseñas/tokens cuando se le pide que no lo haga
- Usa FileZilla + nano para el VPS
- Meta declarada: 100.000 usuarios (arquitectura actual con Firebase aguanta esa escala técnicamente)
- Ya usó otra IA ("Kimi") para parte del trabajo de unificación App/Web/Bot — resultado quedó a medio aplicar, hay que verificar en vez de asumir
