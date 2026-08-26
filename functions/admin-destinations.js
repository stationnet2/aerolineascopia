// functions/admin-destinations.js
//
// Backend del panel (panel.html), reescrito para Cloudflare Pages.
//
// Netlify corre las funciones sobre Node.js, así que podíamos usar la
// librería "firebase-admin" tal cual. Cloudflare Pages Functions corre
// sobre un motor distinto (el mismo que usan los Workers) que NO
// soporta esa librería. En vez de eso, esta versión le habla
// directamente a la API web de Firestore, autenticándose "a mano" con
// la cuenta de servicio (genera su propio token de acceso de Google,
// sin ninguna librería de por medio — todo con funciones que el propio
// navegador/Cloudflare ya trae incorporadas).
//
// Misma protección que antes: cada pedido tiene que mandar el header
// x-admin-key con el valor configurado en la variable de entorno
// ADMIN_PANEL_KEY.

const ALLOWED_COLLECTIONS = ["destinations", "popular_destinations"];
const FIRESTORE_SCOPE = "https://www.googleapis.com/auth/datastore";

function base64url(bytes) {
  let binary = "";
  const arr = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : bytes;
  for (const b of arr) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlString(str) {
  return base64url(new TextEncoder().encode(str));
}

// Convierte el PEM de la clave privada (tal como viene en el JSON de
// Firebase) en una CryptoKey que el navegador/Cloudflare puedan usar
// para firmar.
async function importPrivateKey(pem) {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

// Arma y firma el "JWT" que Google pide para darnos un token de acceso
// a la API de Firestore, a partir de la cuenta de servicio.
async function getAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64urlString(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64urlString(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: FIRESTORE_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned)
  );
  const jwt = `${unsigned}.${base64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error("No se pudo obtener token de Google: " + JSON.stringify(json));
  return json.access_token;
}

// --- Conversión entre JSON normal y el formato "tipado" que usa la
// API de Firestore (todo valor va envuelto: {stringValue: "..."}, etc).
function toFirestoreValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toFirestoreValue) } };
  if (typeof v === "object") return { mapValue: { fields: toFirestoreFields(v) } };
  return { stringValue: String(v) };
}
function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, val] of Object.entries(obj)) fields[k] = toFirestoreValue(val);
  return fields;
}
function fromFirestoreValue(v) {
  if (!v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("nullValue" in v) return null;
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(fromFirestoreValue);
  if ("mapValue" in v) return fromFirestoreFields(v.mapValue.fields || {});
  return null;
}
function fromFirestoreFields(fields) {
  const obj = {};
  for (const [k, val] of Object.entries(fields)) obj[k] = fromFirestoreValue(val);
  return obj;
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

export async function onRequest(context) {
  const { request, env } = context;
  const adminKey = request.headers.get("x-admin-key");
  if (!adminKey || adminKey !== env.ADMIN_PANEL_KEY) {
    return jsonResponse(401, { error: "Clave de administrador inválida o faltante." });
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  } catch {
    return jsonResponse(500, { error: "FIREBASE_SERVICE_ACCOUNT no es un JSON válido." });
  }
  const projectId = serviceAccount.project_id;

  let accessToken;
  try {
    accessToken = await getAccessToken(serviceAccount);
  } catch (error) {
    return jsonResponse(500, { error: "No se pudo autenticar con Firebase.", detail: error.message });
  }

  const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  const authHeaders = { Authorization: `Bearer ${accessToken}` };
  const url = new URL(request.url);

  try {
    if (request.method === "GET") {
      const collection = url.searchParams.get("collection");
      if (!ALLOWED_COLLECTIONS.includes(collection)) return jsonResponse(400, { error: "Colección inválida." });

      const res = await fetch(`${base}/${collection}`, { headers: authHeaders });
      const json = await res.json();
      if (!res.ok) return jsonResponse(res.status, json);
      const docs = (json.documents || []).map((doc) => ({
        id: doc.name.split("/").pop(),
        ...fromFirestoreFields(doc.fields || {}),
      }));
      return jsonResponse(200, { docs });
    }

    if (request.method === "POST") {
      const { collection, id, data } = await request.json();
      if (!ALLOWED_COLLECTIONS.includes(collection) || !id || !data) {
        return jsonResponse(400, { error: "Faltan datos (collection, id, data)." });
      }
      const res = await fetch(`${base}/${collection}/${id}`, {
        method: "PATCH",
        headers: { ...authHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({ fields: toFirestoreFields(data) }),
      });
      const json = await res.json();
      if (!res.ok) return jsonResponse(res.status, json);
      return jsonResponse(200, { ok: true });
    }

    if (request.method === "DELETE") {
      const collection = url.searchParams.get("collection");
      const id = url.searchParams.get("id");
      if (!ALLOWED_COLLECTIONS.includes(collection) || !id) {
        return jsonResponse(400, { error: "Faltan datos (collection, id)." });
      }
      const res = await fetch(`${base}/${collection}/${id}`, { method: "DELETE", headers: authHeaders });
      if (!res.ok) {
        const json = await res.json().catch(() => ({}));
        return jsonResponse(res.status, json);
      }
      return jsonResponse(200, { ok: true });
    }

    return jsonResponse(405, { error: "Método no soportado." });
  } catch (error) {
    return jsonResponse(500, { error: "Error interno.", detail: error.message });
  }
}
