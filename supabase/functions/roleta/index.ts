// Roleta Achei no Pão — API pública
// Deploy: supabase functions deploy roleta --no-verify-jwt
//
// GET  ?acao=config&b=<padaria>                 → fatias e regras
// POST { acao:"codigo", phone }                  → envia código por WhatsApp (se OTP ligado)
// POST { acao:"girar", phone, name, bairro, b, device, consent, otp?, captcha? }
// POST { acao:"resgatar", code, pin, confirmar } → anunciante valida o prêmio
//
// O sorteio acontece no banco (do_spin). O navegador só recebe o resultado e anima.

import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const SALT = Deno.env.get("SPIN_SALT") ?? "troque-este-sal";
const TURNSTILE_SECRET = Deno.env.get("TURNSTILE_SECRET");        // opcional: Cloudflare Turnstile
const OTP_WEBHOOK_URL = Deno.env.get("OTP_WEBHOOK_URL");          // opcional: seu disparador de WhatsApp
const OTP_WEBHOOK_TOKEN = Deno.env.get("OTP_WEBHOOK_TOKEN") ?? "";
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "*").split(",").map((s) => s.trim());

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const cors = {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.includes("*") ? "*" : (ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]),
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, authorization, apikey, x-client-info",
    "Vary": "Origin",
  };
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  try {
    const url = new URL(req.url);
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || req.headers.get("x-real-ip") || "0.0.0.0";
    const ipHash = await sha256(`${SALT}|ip|${ip}`);

    if (req.method === "GET" && url.searchParams.get("acao") === "config") {
      const { data, error } = await sb.rpc("wheel_config", { p_bakery: url.searchParams.get("b") ?? "" });
      if (error) throw error;
      return json(data);
    }

    if (req.method !== "POST") return json({ error: "metodo" }, 405);
    const body = await req.json().catch(() => ({}));

    // ---- Código por WhatsApp ----
    if (body.acao === "codigo") {
      const phone = normPhone(body.phone);
      if (!phone) return json({ error: "telefone_invalido" });
      if (!OTP_WEBHOOK_URL) return json({ error: "otp_indisponivel" });
      const { data, error } = await sb.rpc("otp_issue", { p_phone: phone });
      if (error) throw error;
      if (data.error) return json(data);
      const r = await fetch(OTP_WEBHOOK_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${OTP_WEBHOOK_TOKEN}` },
        body: JSON.stringify({ phone, code: data.code, message: `Seu código da Roleta Achei no Pão é ${data.code}. Não compartilhe.` }),
        signal: AbortSignal.timeout(8000),
      });
      if (!r.ok) return json({ error: "envio_falhou" });
      return json({ ok: true });
    }

    // ---- Girar ----
    if (body.acao === "girar") {
      const phone = normPhone(body.phone);
      if (!phone) return json({ error: "telefone_invalido" });
      if (body.consent !== true) return json({ error: "consentimento" });
      const bairro = String(body.bairro ?? "").trim().slice(0, 60);
      if (bairro.length < 2) return json({ error: "bairro" });
      if (typeof body.device !== "string" || !/^[a-zA-Z0-9_-]{16,80}$/.test(body.device)) return json({ error: "aparelho_invalido" });
      if (TURNSTILE_SECRET && !(await turnstileOk(body.captcha, ip))) return json({ error: "captcha" });

      const ua = req.headers.get("user-agent") ?? "";
      const { data, error } = await sb.rpc("do_spin", {
        p_phone: phone,
        p_name: String(body.name ?? "").slice(0, 60),
        p_bakery: String(body.b ?? ""),
        p_device: await sha256(`${SALT}|dev|${body.device}`),   // id do aparelho guardado só como hash
        p_ip_hash: ipHash,
        p_ua: ua,
        p_otp: body.otp ? String(body.otp).replace(/\D/g, "").slice(0, 6) : null,
        p_neighborhood: bairro,
      });
      if (error) throw error;
      return json(data);
    }

    // ---- Resgate no anunciante ----
    if (body.acao === "resgatar") {
      const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9-]/g, "").slice(0, 16);
      const pin = String(body.pin ?? "").replace(/\D/g, "").slice(0, 8);
      if (!code || pin.length < 4) return json({ error: "codigo_ou_pin_invalido" });
      const { data, error } = await sb.rpc("redeem", { p_code: code, p_pin: pin, p_ip_hash: ipHash, p_confirm: body.confirmar === true });
      if (error) throw error;
      return json(data);
    }

    return json({ error: "acao_desconhecida" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "interno" }, 500);
  }
});

// Celular brasileiro: DDD + 9 + 8 dígitos → 55DD9XXXXXXXX
function normPhone(v: unknown): string | null {
  let d = String(v ?? "").replace(/\D/g, "");
  if (d.length === 13 && d.startsWith("55")) d = d.slice(2);
  if (!/^[1-9][0-9]9[0-9]{8}$/.test(d)) return null;
  return "55" + d;
}

async function turnstileOk(token: unknown, ip: string) {
  if (typeof token !== "string" || !token) return false;
  const form = new FormData();
  form.append("secret", TURNSTILE_SECRET!); form.append("response", token); form.append("remoteip", ip);
  const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
  return (await r.json()).success === true;
}

async function sha256(s: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 40);
}
