// Chari - recoit les notifications de Stripe et active le Premium 30 jours.
// A deployer SANS verification JWT (Stripe n'envoie pas de jeton Supabase) :
// la securite vient de la signature Stripe verifiee ci-dessous.
//
// Secrets a definir dans Supabase > Edge Functions > Secrets :
//   STRIPE_WEBHOOK_SECRET  (whsec_..., donne par Stripe a la creation du webhook)
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const enc = new TextEncoder();

function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// Verification de l'en-tete Stripe-Signature (t=...,v1=...)
async function verifyStripe(payload: string, header: string, secret: string): Promise<boolean> {
  const parts = Object.fromEntries(
    header.split(",").map((p) => p.split("=") as [string, string]).filter((p) => p.length === 2),
  );
  const t = parts["t"];
  const sigs = header.split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || !sigs.length) return false;
  // Refuse les notifications de plus de 5 minutes (anti-rejeu)
  if (Math.abs(Date.now() / 1000 - Number(t)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = hex(await crypto.subtle.sign("HMAC", key, enc.encode(`${t}.${payload}`)));
  return sigs.some((s) => safeEqual(s, mac));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Methode non autorisee", { status: 405 });
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!secret) return new Response("Webhook non configure", { status: 503 });

  const payload = await req.text();
  const sig = req.headers.get("Stripe-Signature") ?? "";
  if (!(await verifyStripe(payload, sig, secret))) {
    return new Response("Signature invalide", { status: 400 });
  }

  const event = JSON.parse(payload);
  if (event.type !== "checkout.session.completed" && event.type !== "checkout.session.async_payment_succeeded") {
    return new Response(JSON.stringify({ ignored: event.type }), { status: 200 });
  }

  const s = event.data.object;
  if (s.payment_status !== "paid") return new Response(JSON.stringify({ pending: true }), { status: 200 });
  const userId = s.metadata?.user_id ?? s.client_reference_id;
  if (!userId) return new Response("Utilisateur inconnu", { status: 200 });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // Idempotence : une session Stripe n'active le Premium qu'une seule fois
  const { data: already } = await admin.from("payments").select("id").eq("provider_session_id", s.id).maybeSingle();
  if (already) return new Response(JSON.stringify({ duplicate: true }), { status: 200 });

  const { data: prof } = await admin.from("profiles").select("premium_until").eq("id", userId).maybeSingle();
  const base = prof?.premium_until && new Date(prof.premium_until) > new Date() ? new Date(prof.premium_until) : new Date();
  const until = new Date(base.getTime() + 30 * 24 * 3600 * 1000).toISOString();

  const { error: payErr } = await admin.from("payments").insert({
    user_id: userId,
    provider: "stripe",
    provider_session_id: s.id,
    amount: s.amount_total ?? 0,
    currency: s.currency ?? "",
    status: "paid",
    premium_until: until,
  });
  if (payErr) {
    console.error("payments insert", payErr.message);
    return new Response("Erreur base", { status: 500 }); // Stripe reessaiera
  }

  const { error: upErr } = await admin.from("profiles")
    .update({ is_premium: true, premium_until: until })
    .eq("id", userId);
  if (upErr) {
    console.error("profiles update", upErr.message);
    // On annule l'enregistrement pour que la nouvelle tentative de Stripe reussisse
    await admin.from("payments").delete().eq("provider_session_id", s.id);
    return new Response("Erreur base", { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true, premium_until: until }), { status: 200 });
});
