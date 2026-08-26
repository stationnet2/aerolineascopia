// netlify/functions/admin-destinations.js
//
// Backend simple para panel.html: lee y escribe las colecciones
// "destinations" y "popular_destinations" en Firestore usando
// credenciales de administrador (así el panel puede escribir aunque
// las reglas de Firestore bloqueen la escritura desde cualquier app
// cliente — eso sigue protegido).
//
// Protegido con una clave secreta simple (no es un sistema de usuarios
// completo, es "una sola clave que solo vos conocés"): cada pedido
// tiene que mandar el header x-admin-key con el valor que configures
// en la variable de entorno ADMIN_PANEL_KEY de Netlify. Sin eso, la
// función devuelve 401 y no hace nada.

const admin = require("firebase-admin");

if (!admin.apps.length) {
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const ALLOWED_COLLECTIONS = ["destinations", "popular_destinations"];

exports.handler = async function (event) {
  const adminKey = event.headers["x-admin-key"];
  if (!adminKey || adminKey !== process.env.ADMIN_PANEL_KEY) {
    return { statusCode: 401, body: JSON.stringify({ error: "Clave de administrador inválida o faltante." }) };
  }

  try {
    if (event.httpMethod === "GET") {
      const collection = event.queryStringParameters?.collection;
      if (!ALLOWED_COLLECTIONS.includes(collection)) {
        return { statusCode: 400, body: JSON.stringify({ error: "Colección inválida." }) };
      }
      const snapshot = await db.collection(collection).get();
      const docs = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
      return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ docs }) };
    }

    if (event.httpMethod === "POST") {
      const { collection, id, data } = JSON.parse(event.body || "{}");
      if (!ALLOWED_COLLECTIONS.includes(collection) || !id || !data) {
        return { statusCode: 400, body: JSON.stringify({ error: "Faltan datos (collection, id, data)." }) };
      }
      await db.collection(collection).doc(id).set(data, { merge: false });
      return { statusCode: 200, body: JSON.stringify({ ok: true }) };
    }

    if (event.httpMethod === "DELETE") {
      const collection = event.queryStringParameters?.collection;
      const id = event.queryStringParameters?.id;
      if (!ALLOWED_COLLECTIONS.includes(collection) || !id) {
        return { statusCode: 400, body: JSON.stringify({ error: "Faltan datos (collection, id)." }) };
      }
      await db.collection(collection).doc(id).delete();
      return { statusCode: 200, body: JSON.stringify({ ok: true }) };
    }

    return { statusCode: 405, body: JSON.stringify({ error: "Método no soportado." }) };
  } catch (error) {
    return { statusCode: 500, body: JSON.stringify({ error: "Error interno.", detail: error.message }) };
  }
};
