// functions/search-flights.js
//
// Versión para Cloudflare Pages Functions de la misma función que
// teníamos en Netlify (netlify/functions/search-flights.js). La lógica
// es idéntica; solo cambia la "forma" de la función porque Cloudflare
// usa un runtime distinto a Node.js (no exports.handler, sino
// onRequestGet; no process.env, sino context.env; se responde con un
// objeto Response en vez de {statusCode, body}).

export async function onRequestGet(context) {
  const TOKEN = context.env.TRAVELPAYOUTS_TOKEN;
  if (!TOKEN) {
    return new Response(JSON.stringify({ error: "Falta configurar TRAVELPAYOUTS_TOKEN." }), { status: 500 });
  }

  const url = new URL(context.request.url);
  const params = url.searchParams;
  const origin = params.get("origin");
  const destination = params.get("destination");
  const departure_at = params.get("departure_at");
  const return_at = params.get("return_at");
  const currency = params.get("currency") || "usd";
  const one_way = params.get("one_way") || "true";

  if (!origin || !destination) {
    return new Response(JSON.stringify({ error: "Faltan los parámetros origin y destination." }), { status: 400 });
  }

  const upstream = new URL("https://api.travelpayouts.com/aviasales/v3/prices_for_dates");
  upstream.searchParams.set("origin", origin);
  upstream.searchParams.set("destination", destination);
  upstream.searchParams.set("currency", currency);
  upstream.searchParams.set("sorting", "price");
  upstream.searchParams.set("direct", "false");
  upstream.searchParams.set("one_way", one_way);
  upstream.searchParams.set("limit", "10");
  upstream.searchParams.set("token", TOKEN);
  if (departure_at) upstream.searchParams.set("departure_at", departure_at);
  if (return_at) upstream.searchParams.set("return_at", return_at);

  try {
    const response = await fetch(upstream.toString());
    const data = await response.text();
    return new Response(data, {
      status: response.status,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: "Error consultando Travelpayouts.", detail: error.message }), { status: 502 });
  }
}
