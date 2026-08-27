// netlify/functions/search-flights.js
//
// Intermediario entre la app y la API de Travelpayouts. El token secreto
// vive acá (como variable de entorno en Netlify, nunca en el código) y
// nunca viaja dentro del APK de la app — así nadie puede extraerlo
// descompilando la aplicación instalada en su celular.
//
// La app le pide los precios a ESTA función (con los mismos parámetros
// que antes le mandaba directo a Travelpayouts, menos el token), y esta
// función arma el pedido real agregando el token, se lo pasa a
// Travelpayouts, y le devuelve la respuesta tal cual a la app.

exports.handler = async function (event) {
  const TOKEN = process.env.TRAVELPAYOUTS_TOKEN;
  if (!TOKEN) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Falta configurar TRAVELPAYOUTS_TOKEN en las variables de entorno de Netlify." }),
    };
  }

  const params = event.queryStringParameters || {};
  const { origin, destination, departure_at, return_at, currency = "usd", one_way = "true" } = params;

  if (!origin || !destination) {
    return { statusCode: 400, body: JSON.stringify({ error: "Faltan los parámetros origin y destination." }) };
  }

  const url = new URL("https://api.travelpayouts.com/aviasales/v3/prices_for_dates");
  url.searchParams.set("origin", origin);
  url.searchParams.set("destination", destination);
  url.searchParams.set("currency", currency);
  url.searchParams.set("sorting", "price");
  url.searchParams.set("direct", "false");
  url.searchParams.set("one_way", one_way);
  url.searchParams.set("limit", "10");
  url.searchParams.set("token", TOKEN);
  if (departure_at) url.searchParams.set("departure_at", departure_at);
  if (return_at) url.searchParams.set("return_at", return_at);

  try {
    const response = await fetch(url.toString());
    const data = await response.json();
    return {
      statusCode: response.status,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    };
  } catch (error) {
    return {
      statusCode: 502,
      body: JSON.stringify({ error: "Error consultando Travelpayouts.", detail: error.message }),
    };
  }
};
