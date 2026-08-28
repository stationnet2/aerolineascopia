# PROMPT DE CONTINUIDAD — PROYECTO ALERTATRIP

## Contexto general
AlertaTrip es una plataforma de búsqueda de vuelos con alertas de precio. Usa:
- **Travelpayouts/Aviasales** como fuente de vuelos (monetización por afiliado, marker=761958)
- **Firebase** (Firestore + Auth con email/password) para persistencia de alertas, destinos y usuarios
- **Cloudflare Pages** para alojar la web estática (proyectoclouflare/index.html)
- **Cloudflare Worker** como API proxy (`api-alertatrip.descuentonadrian.workers.dev`)
- **GitHub Actions bot** (`check-flight-prices.js`) que corre cada 6 horas monitoreando alertas

## Estructura del repo (GitHub: stationnet2/aerolineascopia)
Tres carpetas separadas, todas para el mismo producto:

| Carpeta | Qué es | Estado | NOTAS IMPORTANTES |
|---|---|---|---|
| `lib/` | App Flutter (iOS/Android) | ✅ Funciona OK | NO TOCAR. Usa auth anónimo + email/password. Lee `affiliateLink` directo del bot. |
| `proyectonetlfy/` | Web para Netlify | ✅ Funciona OK | NO TOCAR. Tiene `assets/app.js` con auth anónimo + FCM. |
| `proyectoclouflare/` | Web para Cloudflare Pages | 🚧 ESTAMOS TRABAJANDO ACÁ | Archivo principal: `index.html` (monolítico, todo en un HTML). |

## Firebase (compartido con la app)
- **Project**: `alerta-vuelos-49ba1`
- **Auth**: Email/Password habilitado (antes era anónimo, ahora migrado a email/password para sincronizar entre dispositivos)
- **Colecciones**:

### `destinations`
Documentos con:
```json
{
  "displayName": "Madrid",
  "country": "España",
  "airports": [{"code": "MAD", "lat": 40.5, "lng": -3.5, "isPrimary": true}],
  "imageUrl": "https://images.unsplash.com/photo-...",
  "klookSvalue": "...",
  "klookStype": "...",
  "klookCityId": "..."
}
```

### `flightAlerts`
Alertas creadas por usuarios. Campos:
```json
{
  "userId": "uid_de_firebase_auth",
  "originCityId": "buenos_aires",
  "destinationCityId": "estambul",
  "maxPrice": 12000,
  "passengers": 1,
  "alertThresholdPercent": 15,
  "dateFrom": null,
  "dateTo": null,
  "flexibleDates": true,
  "isActive": true,
  "createdAt": "2026-08-27T11:50:28.187519",
  "lastKnownPrice": 574,
  "lastKnownCurrency": "USD",
  "lastKnownDepartureDate": "2026-11-14T21:30:00-03:00",
  "lastKnownReturnDate": null,
  "lastAffiliateLink": "https://www.aviasales.com/search/AEP1411IST1?locale=es&marker=...",
  "lastCheckedAt": "timestamp",
  "lastNotifiedAt": "timestamp",
  "lastNotifiedPrice": 558
}
```

### `flightNotifications`
Creado por el bot cuando encuentra precio bajo. Campos:
```json
{
  "userId": "uid",
  "alertId": "id_de_la_alerta",
  "title": "¡Encontramos un precio para tu alerta!",
  "body": "AEP → IST por USD 553",
  "origin": "AEP",
  "destination": "IST",
  "originCityId": "buenos_aires",
  "destinationCityId": "estambul",
  "price": 553,
  "previousPrice": 890,
  "maxPrice": 12000,
  "currency": "USD",
  "departureDate": "2026-11-14",
  "returnDate": null,
  "affiliateLink": "https://www.aviasales.com/search/AEP1411IST1?locale=es&marker=...",
  "read": false,
  "createdAt": "2026-08-27T11:56:34.000Z",
  "isTest": false,
  "pushSent": false,
  "fcmMessageId": null,
  "pushSentAt": null
}
```

### `users`
```json
{
  "fcmToken": "...",
  "testNotificationRequested": false,
  "lastTestNotificationAt": "timestamp"
}
```

## Cloudflare Worker (api-alertatrip v4)
URL: `https://api-alertatrip.descuentonadrian.workers.dev`

Endpoints:
- `GET /search-flights?origin=XXX&destination=YYY&departure_at=YYYY-MM-DD&return_at=YYYY-MM-DD&currency=usd&trip_type=one_way|round_trip`
- `GET /special-offers?origin=XXX&currency=usd`
- `GET/POST/DELETE /admin-destinations` — panel admin conectado a Firestore

## Bot GitHub Actions
- Archivo: `.github/workflows/check-prices.yml`
- Corre `node check-flight-prices.js` cada 6 horas
- Lee `flightAlerts` activas, busca precios en Travelpayouts, y si baja el precio crea documento en `flightNotifications`
- Usa secrets: `FIREBASE_SERVICE_ACCOUNT`, `TRAVELPAYOUTS_TOKEN`, `TRAVELPAYOUTS_MARKER`
- **IMPORTANTE**: El secret `TRAVELPAYOUTS_MARKER` en GitHub debe ser SOLO `761958` (sin texto extra). Si tiene texto como "Secret: 761958 (tu marker de afiliado). 'Add secret'.", el bot guarda links corruptos.
- El bot guarda `affiliateLink` en `flightNotifications` pero a veces el marker viene corrupto. El frontend de la web reconstruye el link con los datos de la notificación (origin, destination, departureDate, returnDate) + `marker=761958`.

## Links de afiliado
- **Vuelos (Aviasales)**: `https://www.aviasales.com/search/{ORIGEN}{DDMM}{DESTINO}{DDMM}1?marker=761958&locale=es`
  - El `1` al final es la cantidad de pasajeros. SIN ESO, Aviasales da error.
  - Ejemplo ida: `AEP1411IST1` (AEP → IST, 14/11, 1 pasajero)
  - Ejemplo ida+vuelta: `AEP1411IST20101` (AEP → IST 14/11, IST → AEP 20/10, 1 pasajero)
- **Hoteles (Klook)**: `https://www.klook.com/es/search/?campaign_id=137&marker=761958&p=4110&trs=567185`
- **Excursiones (KKday)**: `https://www.kkday.com/es/search?campaign_id=633&marker=761958&p=9074&trs=567185`

## Lo que YA está hecho en proyectoclouflare/index.html
1. ✅ Carrusel horizontal de ofertas destacadas con fotos desde Firebase (`imageUrl` de cada destino)
2. ✅ Botón "Crear alerta" en navbar que activa la pestaña "Crear alerta" y hace scroll
3. ✅ Auth con email/password (reemplazó auth anónimo)
   - Modal de login/registro
   - Botón "Ingresar" / "Cerrar sesión" en navbar
   - Si no está logueado, al intentar crear alerta aparece el modal
   - Si no está logueado, "Mis alertas" muestra "Iniciá sesión para ver tus alertas"
4. ✅ `onSnapshot` en tiempo real para "Mis alertas" (se actualizan solas)
5. ✅ Toast flotante arriba a la derecha con campana roja agitándose cuando hay notificaciones no leídas. Al hacer clic lleva a "Mis alertas". NO tiene X para cerrar.
6. ✅ Dentro de "Mis alertas" se muestran las notificaciones con:
   - Precio anterior tachado vs nuevo
   - Fechas del vuelo encontrado
   - Botón "Reservar ahora" con link reconstruido (NO usa affiliateLink del bot directamente, reconstruye con datos de la notificación)
   - Botón "Marcar como leída" (solo desde acá se borra)
7. ✅ Campos de alerta alineados con la app: `passengers`, `alertThresholdPercent`, `createdAt` como String ISO
8. ✅ Links de afiliado en Klook (hoteles) y KKday (excursiones) en resultados de búsqueda y ofertas
9. ✅ Búsqueda de fechas cercanas (±7 días) cuando no hay resultados para la fecha exacta
10. ✅ Modal de redirección antes de salir a Aviasales/Klook/KKday
11. ✅ PWA: manifest.json, service worker, iconos (instalable)

## Pendientes que el usuario pidió (en orden de prioridad)
1. 🔔 **Notificar al cliente por email** cuando se encuentra un precio (no tiene que entrar a la web)
2. 🗑️ **Borrar alertas automáticamente** después de un tiempo (ej: 30 días sin encontrar precio, o 7 días después de la fecha de viaje)
3. 🛡️ **Validación de precios mínimos** — evitar que alguien ponga maxPrice=1 para joder el bot
4. 📱 **Flutter**: Agregar login con email/password para sincronizar alertas entre app y web
5. 🖥️ **Migración a VPS** (DonWeb u otro) — Docker compose con Nginx + Node.js + PostgreSQL + Redis + Bot

## Reglas de Firestore necesarias
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /flightAlerts/{doc} {
      allow read, write: if request.auth != null;
    }
    match /flightNotifications/{doc} {
      allow read, write: if request.auth != null;
    }
    match /destinations/{doc} {
      allow read: if true;
    }
  }
}
```

## Firebase Auth: habilitar Email/Password
1. Firebase Console → Authentication → Sign-in method
2. Habilitar **Email/Password**
3. (Opcional) Deshabilitar Anonymous si ya no se usa

## Colores del diseño
- `--teal-dark`: #0B3D37
- `--teal`: #0F9D8D
- `--coral`: #FF7A45
- Fuentes: Inter, IBM Plex Mono

## Firebase JS versión
Usa Firebase v10 modular por CDN (NO compat):
```html
<script type="module">
  import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";
  import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";
  import { getFirestore, collection, query, where, onSnapshot, getDocs, addDoc, deleteDoc, doc, updateDoc, orderBy } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore.js";
</script>
```

## Worker URL
```javascript
const WORKER_URL = "https://api-alertatrip.descuentonadrian.workers.dev";
```

## Instrucción para la siguiente IA
Si el usuario pide cambios, trabajar sobre `/mnt/agents/output/index.html` (o el archivo que esté en `proyectoclouflare/index.html` del repo). Mantener el estilo visual existente. Todo el código Firebase usa la versión 10 modular por CDN. El worker URL es `https://api-alertatrip.descuentonadrian.workers.dev`.

**NO tocar** `lib/` (Flutter) ni `proyectonetlfy/` (Netlify) salvo que el usuario lo pida explícitamente.

**NO tocar** el bot `check-flight-prices.js` salvo que el usuario lo pida explícitamente. Si hay que arreglar algo del bot, avisarle primero.

**Problema conocido del bot**: El secret `TRAVELPAYOUTS_MARKER` en GitHub Actions a veces tiene texto extra. El frontend de la web reconstruye los links de las notificaciones con los datos de la notificación (no usa affiliateLink directo del bot) para evitar links rotos.
