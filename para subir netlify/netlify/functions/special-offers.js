// netlify/functions/special-offers.js
//
// Mismo propósito que search-flights.js, pero para las "ofertas
// destacadas" (precios anormalmente bajos que detecta Travelpayouts
// para sugerencias automáticas). El token nunca sale de acá.

exports.handler = async function (event) {
  const TOKEN = process.env.TRAVELPAYOUTS_TOKEN;
  if (!TOKEN) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Falta configurar TRAVELPAYOUTS_TOKEN en las variables de entorno de Netlify." }),
    };
  }

  const params = event.queryStringParameters || {};
  const { origin, currency = "usd" } = params;

  if (!origin) {
    return { statusCode: 400, body: JSON.stringify({ error: "Falta el parámetro origin." }) };
  }

  const url = new URL("https://api.travelpayouts.com/aviasales/v3/get_special_offers");
  url.searchParams.set("origin", origin);
  url.searchParams.set("currency", currency);
  url.searchParams.set("locale", "es");
  url.searchParams.set("token", TOKEN);

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
