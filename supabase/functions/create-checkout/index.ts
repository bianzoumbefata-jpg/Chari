// Chari - cree une page de paiement Stripe Checkout pour 1 mois de Premium.
// La carte est saisie uniquement sur la page Stripe : Chari ne la voit jamais.
//
// Secrets a definir dans Supabase > Edge Functions > Secrets :
//   STRIPE_SECRET_KEY   (sk_test_... pour tester, sk_live_... en production)
//   PRICE_AMOUNT        (optionnel, defaut 5000)
//   PRICE_CURRENCY      (optionnel, defaut "xaf" = franc CFA)
//   ALLOWED_ORIGINS     (optionnel, defaut chari-flame.vercel.app + localhost)

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const DEFAULT_ORIGINS = [
  "https://chari-flame.vercel.app",
  "http://localhost:3000",
  "capacitor://localhost",
  "https://localhost",
];

function allowedOrigins(): string[] {
  const raw = Deno.env.get("ALLOWED_ORIGINS");
  return raw ? raw.split(",").map((s) => s.trim()).filter(Boolean) : DEFAULT_ORIGINS;
}

function cors(origin: string | null) {
  const ok = origin && allowedOrigins().includes(origin) ? origin : allowedOrigins()[0];
  return {
    "Access-Control-Allow-Origin": ok,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(origin), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "POST") return json({ error: "Methode non autorisee" }, 405, origin);

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) return json({ error: "Paiement non configure" }, 503, origin);

  // 1. Qui paie ? (session Supabase du membre connecte)
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: userErr } = await supabase.auth.getUser();
  if (userErr || !user) return json({ error: "Connexion requise" }, 401, origin);

  // 2. Adresse de retour : uniquement vers l'application Chari
  let body: { return_url?: string } = {};
  try { body = await req.json(); } catch (_) { /* corps vide */ }
  let returnUrl = allowedOrigins()[0] + "/";
  try {
    const u = new URL(body.return_url ?? "");
    if (allowedOrigins().includes(u.origin)) returnUrl = u.origin + u.pathname;
  } catch (_) { /* adresse invalide : valeur par defaut */ }

  const amount = parseInt(Deno.env.get("PRICE_AMOUNT") ?? "5000", 10);
  const currency = (Deno.env.get("PRICE_CURRENCY") ?? "xaf").toLowerCase();

  // 3. Creation de la session Stripe Checkout (paiement unique, 30 jours)
  const form = new URLSearchParams({
    "mode": "payment",
    "payment_method_types[0]": "card",
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": currency,
    "line_items[0][price_data][unit_amount]": String(amount),
    "line_items[0][price_data][product_data][name]": "Chari Premium - 1 mois",
    "line_items[0][price_data][product_data][description]": "Profils et demandes illimites, mode incognito, pendant 30 jours.",
    "client_reference_id": user.id,
    "metadata[user_id]": user.id,
    "metadata[plan]": "premium_month",
    "payment_intent_data[metadata][user_id]": user.id,
    "success_url": returnUrl + "?paiement=ok&session={CHECKOUT_SESSION_ID}",
    "cancel_url": returnUrl + "?paiement=annule",
    "locale": "auto",
  });
  if (user.email) form.set("customer_email", user.email);

  const res = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${stripeKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
  });
  const session = await res.json();
  if (!res.ok) {
    console.error("Stripe error", session?.error?.message);
    return json({ error: "Impossible de creer le paiement" }, 502, origin);
  }
  return json({ url: session.url }, 200, origin);
});
