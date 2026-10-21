// Church TV OS: sends "TV offline" and "back online" push notifications to the iPhone/iPad/Mac apps.
// Runs every 5 minutes (pg_cron calls it; see README.md). The database function claim_offline_alerts() decides who to tell
// and records that it did, so this function only has to talk to Apple.
import { createClient } from "npm:@supabase/supabase-js@2";

const KEY_ID = Deno.env.get("APNS_KEY_ID");
const TEAM_ID = Deno.env.get("APNS_TEAM_ID");
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY"); // the contents of the AuthKey_XXXX.p8 file
const TOPIC_IOS = Deno.env.get("APNS_TOPIC_IOS") ?? "com.churchtvos.remote";
const TOPIC_MAC = Deno.env.get("APNS_TOPIC_MAC") ?? "com.churchtvos.mac";
const CRON_SECRET = Deno.env.get("NOTIFY_CRON_SECRET");

type Alert = {
  kind: "offline" | "online";
  screen_id: string;
  screen_name: string;
  org_name: string;
  token: string;
  platform: "ios" | "macos";
  environment: "production" | "sandbox";
};

const b64url = (input: ArrayBuffer | string): string => {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

let cachedJwt: { token: string; at: number } | null = null;

// Apple wants a fresh signed token at most every hour and at least every 20 minutes between uses of the same one; we reuse for 40.
async function providerToken(): Promise<string> {
  if (cachedJwt && Date.now() - cachedJwt.at < 40 * 60 * 1000) return cachedJwt.token;
  const pem = (PRIVATE_KEY ?? "").replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  const token = `${header}.${claims}.${b64url(sig)}`;
  cachedJwt = { token, at: Date.now() };
  return token;
}

async function sendOne(a: Alert): Promise<{ ok: boolean; status: number; reason?: string }> {
  const host = a.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const title = a.kind === "offline" ? `${a.screen_name} is offline` : `${a.screen_name} is back online`;
  const body = a.kind === "offline"
    ? `${a.org_name}: this screen has not checked in for 10 minutes.`
    : `${a.org_name}: this screen is connected again.`;
  const res = await fetch(`https://${host}/3/device/${a.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": a.platform === "macos" ? TOPIC_MAC : TOPIC_IOS,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title, body }, sound: a.kind === "offline" ? "default" : undefined, "thread-id": a.screen_id },
      screenId: a.screen_id,
      kind: a.kind,
    }),
  });
  let reason: string | undefined;
  if (!res.ok) {
    try { reason = (await res.json()).reason; } catch { /* no body */ }
  }
  return { ok: res.ok, status: res.status, reason };
}

Deno.serve(async (req) => {
  if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }
  if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY) {
    return new Response(JSON.stringify({ error: "APNs secrets are not set yet" }), { status: 500, headers: { "content-type": "application/json" } });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await supabase.rpc("claim_offline_alerts");
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { "content-type": "application/json" } });

  const alerts = (data ?? []) as Alert[];
  let sent = 0;
  let failed = 0;
  const dead: string[] = [];
  for (const a of alerts) {
    try {
      const r = await sendOne(a);
      if (r.ok) sent++;
      else {
        failed++;
        // The phone uninstalled the app or the token is wrong: forget it.
        if (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered" || r.reason === "DeviceTokenNotForTopic") dead.push(a.token);
      }
    } catch (_e) {
      failed++;
    }
  }
  if (dead.length) await supabase.from("push_devices").delete().in("token", dead);
  return new Response(JSON.stringify({ alerts: alerts.length, sent, failed, removed: dead.length }), { headers: { "content-type": "application/json" } });
});
