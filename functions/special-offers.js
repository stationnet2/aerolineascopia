// functions/special-offers.js
//
// Versión para Cloudflare Pages Functions (antes era Netlify).
// Ahora usa onRequestGet y context.env en vez de exports.handler.

export async function onRequestGet(context) {
  const TOKEN = context.env.TRAVELPAYOUTS_TOKEN;
  if (!TOKEN) {
    return new Response(JSON.stringify({ error: "Falta configurar TRAVELPAYOUTS_TOKEN." }), { status: 500 });
  }

  const url = new URL(context.request.url);
  const params = url.searchParams;
  const origin = params.get("origin");
  const currency = params.get("currency") || "usd";

  if (!origin) {
    return new Response(JSON.stringify({ error: "Falta el parámetro origin." }), { status: 400 });
  }

  const upstream = new URL("https://api.travelpayouts.com/aviasales/v3/get_special_offers");
  upstream.searchParams.set("origin", origin);
  upstream.searchParams.set("currency", currency);
  upstream.searchParams.set("locale", "es");
  upstream.searchParams.set("token", TOKEN);

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