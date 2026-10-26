// Church TV OS MCP server (hosted). Lets an AI assistant (Claude, etc.) work with a church's signage on the person's behalf:
// find rooms and screens, add a graphic to the media library, schedule it for a time window, list and cancel those schedules.
//
// Sign-in is Supabase Auth's OAuth 2.1 server (the person approves the assistant on app.churchtvos.com/oauth/consent).
// Every database call below uses the PERSON'S token, so row-level security applies exactly as it does in the dashboard:
// an assistant can never do more than its user can. Nothing here uses the service-role key.
//
// Transport: MCP "streamable HTTP", stateless, JSON responses only. See README.md for setup.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/mcp`;
const SERVER = { name: "church-tv-os", version: "0.1.0" };
const PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05"];
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const TAKEOVER_PRIORITY = 100; // assistant-made slots win over everyday slots (which use 0..)
const STALE_MINUTES = 10;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, mcp-protocol-version, mcp-session-id, accept",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-expose-headers": "www-authenticate",
};
const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...CORS, ...extra } });

// ───────────────────────── Tools ─────────────────────────
const TOOLS = [
  {
    name: "list_targets",
    description:
      "Start here. Lists the churches (organizations) the user belongs to, with their sites (and each site's time zone and current local date/time), rooms, " +
      "and screens (TVs) including what each screen is currently set to run. Use it to work out the ids and the local date before scheduling. " +
      "Screen times are always in the SITE's local time zone.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true },
  },
  {
    name: "list_graphics",
    description: "Lists images and videos already in a church's Signage media library (newest first) so one can be reused instead of uploading again.",
    inputSchema: {
      type: "object",
      properties: { organization_id: { type: "string", description: "Church id from list_targets" }, limit: { type: "integer", default: 20 } },
      required: ["organization_id"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: "upload_graphic",
    description:
      "Adds an image to a church's Signage media library and returns its media_id. Provide the image as base64 (image_base64, PNG/JPEG/WebP, up to 10 MB) " +
      "or as a public https link (image_url). Does not put anything on a screen; use schedule_graphic for that.",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string" },
        title: { type: "string", description: "Short name shown in the media library, e.g. 'Youth Night poster'" },
        image_base64: { type: "string", description: "Raw base64 of the image file (no data: prefix needed)" },
        image_url: { type: "string", description: "Public https URL of the image, used when image_base64 is not given" },
        content_type: { type: "string", description: "image/png, image/jpeg or image/webp (detected from the file if omitted)" },
      },
      required: ["organization_id", "title"],
      additionalProperties: false,
    },
  },
  {
    name: "schedule_graphic",
    description:
      "Shows a graphic from the media library on one or more screens during a time window, taking over from the screen's normal signage for that window. " +
      "ALWAYS call it first WITHOUT confirm to get a preview (what, where, when, and any conflicts or warnings), show that summary to the user, and only call it again with confirm=true after they agree. " +
      "Times are the site's local time. The window must be within one day (end after start). For 'every Friday' use repeat_weekly_until.",
    inputSchema: {
      type: "object",
      properties: {
        media_id: { type: "string", description: "From upload_graphic or list_graphics" },
        screen_ids: { type: "array", items: { type: "string" }, description: "Screens from list_targets (all must belong to the same church)" },
        date: { type: "string", description: "YYYY-MM-DD, the local date of the first (or only) showing" },
        start: { type: "string", description: "HH:MM, 24-hour local time, e.g. 20:00" },
        end: { type: "string", description: "HH:MM, 24-hour local time, e.g. 22:00 (use 23:59 for end of day)" },
        repeat_weekly_until: { type: "string", description: "Optional YYYY-MM-DD. Repeats on the same weekday every week through this date." },
        seconds: { type: "integer", description: "Images only: seconds on screen per pass (default 15). It repeats for the whole window anyway." },
        label: { type: "string", description: "Optional note, e.g. 'Youth Night promo'" },
        confirm: { type: "boolean", description: "false/omitted = preview only. true = actually schedule it." },
      },
      required: ["media_id", "screen_ids", "date", "start", "end"],
      additionalProperties: false,
    },
  },
  {
    name: "list_scheduled",
    description: "Lists upcoming and current assistant-scheduled graphics (and any other dated signage slots) with their screens and times, plus slot ids for cancelling.",
    inputSchema: { type: "object", properties: { organization_id: { type: "string" } }, required: ["organization_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
  },
  {
    name: "cancel_scheduled",
    description:
      "Removes a scheduled graphic (a slot id from list_scheduled or schedule_graphic). Call without confirm first to see what would be removed, then with confirm=true after the user agrees. " +
      "For a weekly repeat this removes every remaining showing.",
    inputSchema: {
      type: "object",
      properties: { slot_id: { type: "string" }, confirm: { type: "boolean" } },
      required: ["slot_id"],
      additionalProperties: false,
    },
  },
];

// ───────────────────────── Helpers ─────────────────────────
class ToolError extends Error {}
type Db = SupabaseClient;

const isUuid = (s: unknown): s is string => typeof s === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
const isDate = (s: unknown): s is string => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(Date.parse(s + "T00:00:00Z"));
const dow = (d: string) => new Date(d + "T00:00:00Z").getUTCDay(); // 0 = Sunday, same as the database
const addDays = (d: string, n: number) => new Date(Date.parse(d + "T00:00:00Z") + n * 86400000).toISOString().slice(0, 10);
const DAYNAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function parseTime(s: unknown, field: string): string {
  const m = typeof s === "string" ? /^(\d{1,2}):(\d{2})$/.exec(s.trim()) : null;
  if (!m) throw new ToolError(`${field} must look like 20:00 (24-hour HH:MM).`);
  const h = +m[1], min = +m[2];
  if ((h === 24 && min === 0)) return "23:59:59";
  if (h > 23 || min > 59) throw new ToolError(`${field} must look like 20:00 (24-hour HH:MM).`);
  return `${String(h).padStart(2, "0")}:${m[2]}:00`;
}
const hm = (t: string) => t.slice(0, 5);
const nice12 = (t: string) => {
  const [h, m] = t.split(":").map(Number);
  return `${((h + 11) % 12) + 1}${m ? ":" + String(m).padStart(2, "0") : ""}${h < 12 ? "am" : "pm"}`;
};

function localNow(tz: string): { date: string; time: string } {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
      .formatToParts(new Date()).map((p) => [p.type, p.value]),
  );
  return { date: `${parts.year}-${parts.month}-${parts.day}`, time: `${parts.hour}:${parts.minute}` };
}

function must<T>(r: { data: T | null; error: { message: string } | null }, what: string): T {
  if (r.error) {
    const msg = /row-level security|permission denied/i.test(r.error.message)
      ? `Your account isn't allowed to ${what}. Ask a church admin to give you the Signage editor role for that site.`
      : `${what}: ${r.error.message}`;
    throw new ToolError(msg);
  }
  return r.data as T;
}

async function loadScreens(db: Db, ids: string[]) {
  const screens = must(
    await db.from("screens").select("id,name,organization_id,location_id,group_id,default_module,last_seen_at").in("id", ids),
    "read those screens",
  ) as any[];
  if (screens.length !== new Set(ids).size) throw new ToolError("One or more screen ids were not found (or you don't have access). Use list_targets for valid ids.");
  const locIds = [...new Set(screens.map((s) => s.location_id).filter(Boolean))];
  const locs = locIds.length ? (must(await db.from("locations").select("id,name,site_id").in("id", locIds), "read rooms") as any[]) : [];
  const siteIds = [...new Set(locs.map((l) => l.site_id))];
  const sites = siteIds.length ? (must(await db.from("sites").select("id,name,timezone").in("id", siteIds), "read sites") as any[]) : [];
  return screens.map((s) => {
    const loc = locs.find((l) => l.id === s.location_id);
    const site = sites.find((x) => x.id === loc?.site_id);
    return { ...s, room: loc?.name ?? null, site_id: site?.id ?? null, site: site?.name ?? null, tz: site?.timezone ?? "America/Toronto" };
  });
}

// ───────────────────────── Tool implementations ─────────────────────────
async function listTargets(db: Db, userId: string) {
  const mem = must(await db.from("memberships").select("organization_id,role,modules,site_ids").eq("user_id", userId), "read your churches") as any[];
  if (!mem.length) return "This account isn't a member of any church yet.";
  const orgIds = mem.map((m) => m.organization_id);
  const [orgs, sites, locs, screens, groups, ents] = await Promise.all([
    db.from("organizations").select("id,name").in("id", orgIds),
    db.from("sites").select("id,name,timezone,organization_id").in("organization_id", orgIds),
    db.from("locations").select("id,name,site_id,organization_id").in("organization_id", orgIds),
    db.from("screens").select("id,name,organization_id,location_id,group_id,default_module,last_seen_at").in("organization_id", orgIds),
    db.from("screen_groups").select("id,name,organization_id").in("organization_id", orgIds),
    db.from("entitlements").select("organization_id,module,status").in("organization_id", orgIds),
  ]);
  const O = must(orgs, "read churches") as any[], S = must(sites, "read sites") as any[], L = must(locs, "read rooms") as any[];
  const SC = must(screens, "read screens") as any[], G = must(groups, "read groups") as any[], E = must(ents, "read plans") as any[];
  const out: string[] = [];
  for (const o of O) {
    const m = mem.find((x) => x.organization_id === o.id)!;
    const signageOn = E.some((e) => e.organization_id === o.id && e.module === "signage" && ["active", "trialing", "past_due"].includes(e.status));
    out.push(`# ${o.name}  (organization_id: ${o.id})`);
    out.push(`Your role: ${m.role}${m.site_ids ? " (limited to some sites)" : ""}. Signage plan: ${signageOn ? "yes" : "NOT active"}.`);
    for (const s of S.filter((x) => x.organization_id === o.id)) {
      const n = localNow(s.timezone);
      out.push(`\n## Site: ${s.name}  (${s.timezone}; local now ${n.date} ${DAYNAMES[dow(n.date)]} ${n.time})`);
      for (const l of L.filter((x) => x.site_id === s.id)) {
        out.push(`- Room: ${l.name}`);
        for (const sc of SC.filter((x) => x.location_id === l.id)) {
          const online = sc.last_seen_at && Date.now() - Date.parse(sc.last_seen_at) < STALE_MINUTES * 60000;
          const grp = G.find((g) => g.id === sc.group_id);
          out.push(`  - Screen "${sc.name ?? "Unnamed"}"  screen_id: ${sc.id}  runs: ${sc.default_module}${grp ? `  group: ${grp.name}` : ""}  ${online ? "online" : "OFFLINE"}`);
        }
      }
    }
  }
  return out.join("\n");
}

async function listGraphics(db: Db, a: any) {
  if (!isUuid(a.organization_id)) throw new ToolError("organization_id is required (from list_targets).");
  const rows = must(
    await db.from("media").select("id,title,kind,url,created_at").eq("organization_id", a.organization_id).eq("module", "signage").in("kind", ["image", "video"])
      .order("created_at", { ascending: false }).limit(Math.min(Math.max(+a.limit || 20, 1), 100)),
    "read the media library",
  ) as any[];
  if (!rows.length) return "The Signage media library is empty.";
  return rows.map((r) => `- ${r.title} (${r.kind})  media_id: ${r.id}  ${r.url}`).join("\n");
}

function extFor(ct: string) {
  return ct === "image/png" ? "png" : ct === "image/webp" ? "webp" : "jpg";
}
function sniff(b: Uint8Array): string | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0xff && b[1] === 0xd8) return "image/jpeg";
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  return null;
}

async function uploadGraphic(db: Db, a: any) {
  if (!isUuid(a.organization_id)) throw new ToolError("organization_id is required (from list_targets).");
  const title = String(a.title ?? "").trim().slice(0, 120);
  if (!title) throw new ToolError("title is required.");
  let bytes: Uint8Array;
  if (typeof a.image_base64 === "string" && a.image_base64) {
    const raw = a.image_base64.replace(/^data:[^,]*,/, "").replace(/\s+/g, "");
    if (raw.length > MAX_IMAGE_BYTES * 1.4) throw new ToolError("That image is over 10 MB. Resize or compress it first.");
    try { bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)); } catch { throw new ToolError("image_base64 is not valid base64."); }
  } else if (typeof a.image_url === "string" && a.image_url) {
    let u: URL;
    try { u = new URL(a.image_url); } catch { throw new ToolError("image_url is not a valid URL."); }
    if (u.protocol !== "https:" || /^(localhost|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[)/i.test(u.hostname) || !u.hostname.includes(".")) {
      throw new ToolError("image_url must be a public https link.");
    }
    const r = await fetch(u, { redirect: "follow", signal: AbortSignal.timeout(20000) });
    if (!r.ok) throw new ToolError(`Couldn't download that link (${r.status}).`);
    const buf = new Uint8Array(await r.arrayBuffer());
    if (buf.length > MAX_IMAGE_BYTES) throw new ToolError("That image is over 10 MB. Resize or compress it first.");
    bytes = buf;
  } else throw new ToolError("Give either image_base64 or image_url.");
  if (bytes.length > MAX_IMAGE_BYTES) throw new ToolError("That image is over 10 MB. Resize or compress it first.");
  const ct = sniff(bytes);
  if (!ct) throw new ToolError("Only PNG, JPEG and WebP images are supported.");

  const path = `${a.organization_id}/${crypto.randomUUID()}.${extFor(ct)}`;
  const up = await db.storage.from("media").upload(path, bytes, { contentType: ct, upsert: false });
  if (up.error) {
    throw new ToolError(/row-level security|not allowed|unauthorized/i.test(up.error.message)
      ? "Your account isn't allowed to upload to that church's media library. Ask a church admin for the Signage editor role."
      : `Upload failed: ${up.error.message}`);
  }
  const url = db.storage.from("media").getPublicUrl(path).data.publicUrl;
  const row = must(
    await db.from("media").insert({ organization_id: a.organization_id, site_id: null, title, kind: "image", storage_path: path, url, size_bytes: bytes.length, module: "signage" }).select("id").single(),
    "add the image to the media library",
  ) as any;
  return `Added "${title}" to the Signage media library.\nmedia_id: ${row.id}\n${url}`;
}

type Plan = {
  media: any;
  screens: any[];
  dates: string[]; // local dates the graphic will show, in order
  start: string; end: string; // HH:MM:SS
  until: string | null;
  weekday: number;
  warnings: string[];
  replaces: string[];
};

async function plan(db: Db, a: any): Promise<Plan> {
  if (!isUuid(a.media_id)) throw new ToolError("media_id is required (from upload_graphic or list_graphics).");
  const ids = Array.isArray(a.screen_ids) ? [...new Set(a.screen_ids)] : [];
  if (!ids.length || !ids.every(isUuid)) throw new ToolError("screen_ids must be a list of screen ids from list_targets.");
  if (!isDate(a.date)) throw new ToolError("date must be YYYY-MM-DD.");
  const start = parseTime(a.start, "start"), end = parseTime(a.end, "end");
  if (end <= start) throw new ToolError("end must be later than start on the same day. For an overnight window, make two schedules.");
  const until = a.repeat_weekly_until ? (isDate(a.repeat_weekly_until) ? a.repeat_weekly_until : (() => { throw new ToolError("repeat_weekly_until must be YYYY-MM-DD."); })()) : null;
  if (until && until < a.date) throw new ToolError("repeat_weekly_until is before date.");
  if (until && Date.parse(until) - Date.parse(a.date) > 400 * 86400000) throw new ToolError("Repeats are limited to about a year at a time.");

  const media = must(await db.from("media").select("id,title,kind,url,organization_id,module").eq("id", a.media_id).maybeSingle(), "read that graphic") as any;
  if (!media) throw new ToolError("That media_id wasn't found (or you don't have access).");
  if (media.kind === "audio") throw new ToolError("That media file is audio. Pick an image or video.");
  const screens = await loadScreens(db, ids as string[]);
  if (screens.some((s) => s.organization_id !== media.organization_id)) throw new ToolError("The graphic and the screens must all belong to the same church.");

  const weekday = dow(a.date);
  const dates: string[] = [];
  for (let d = a.date; d <= (until ?? a.date); d = addDays(d, 7)) dates.push(d);
  const warnings: string[] = [], replaces: string[] = [];

  const ent = must(await db.from("entitlements").select("status").eq("organization_id", media.organization_id).eq("module", "signage"), "read the plan") as any[];
  if (!ent.some((e) => ["active", "trialing", "past_due"].includes(e.status))) warnings.push("This church doesn't have an active Signage plan, so screens won't show it.");

  for (const s of screens) {
    const now = localNow(s.tz);
    if (a.date < now.date || (a.date === now.date && end <= now.time + ":00")) throw new ToolError(`That time has already passed in ${s.site ?? "the site"}'s local time (now ${now.date} ${now.time}).`);
    const last = s.last_seen_at && Date.now() - Date.parse(s.last_seen_at) < STALE_MINUTES * 60000;
    if (!last) warnings.push(`"${s.name}" looks offline right now. It will pick the schedule up when it reconnects.`);

    // What the screen is set to run at that time.
    const rules = must(
      await db.from("screen_schedules").select("module,days,start_time,end_time,priority,screen_id,group_id")
        .or(`screen_id.eq.${s.id}${s.group_id ? `,group_id.eq.${s.group_id}` : ""}`),
      "read screen rules",
    ) as any[];
    const hit = rules.filter((r) => r.days.includes(weekday) && r.start_time < end && r.end_time > start).sort((x, y) => y.priority - x.priority);
    const mod = hit.length ? hit[0].module : s.default_module;
    if (mod !== "signage") warnings.push(`"${s.name}" is set to run ${mod === "off" ? "nothing (off)" : mod} at that time, not Signage, so the graphic won't appear. Change its schedule in Screens first.`);

    // Other slots that overlap.
    const slots = must(
      await db.from("signage_slots").select("id,days,start_time,end_time,priority,start_date,end_date,label,playlist_id,screen_id,group_id")
        .or(`screen_id.eq.${s.id}${s.group_id ? `,group_id.eq.${s.group_id}` : ""}`),
      "read existing slots",
    ) as any[];
    const over = slots.filter((x) =>
      x.days.includes(weekday) && x.start_time < end && x.end_time > start &&
      (x.start_date == null || x.start_date <= dates[dates.length - 1]) && (x.end_date == null || x.end_date >= dates[0]));
    for (const x of over) {
      const pl = x.playlist_id ? (must(await db.from("signage_playlists").select("name").eq("id", x.playlist_id).maybeSingle(), "read playlists") as any) : null;
      const label = x.label || pl?.name || "another slot";
      if (x.priority >= TAKEOVER_PRIORITY) warnings.push(`"${s.name}" already has "${label}" (${nice12(hm(x.start_time))}–${nice12(hm(x.end_time))}) at equal or higher priority; they will compete.`);
      else replaces.push(`"${s.name}": "${label}" ${nice12(hm(x.start_time))}–${nice12(hm(x.end_time))}`);
    }
  }
  return { media, screens, dates, start, end, until, weekday, warnings, replaces };
}

function summarize(p: Plan, a: any): string {
  const when = p.until
    ? `every ${DAYNAMES[p.weekday]} ${nice12(hm(p.start))}–${nice12(hm(p.end))}, from ${p.dates[0]} through ${p.dates[p.dates.length - 1]} (${p.dates.length} showings)`
    : `${DAYNAMES[p.weekday]} ${p.dates[0]}, ${nice12(hm(p.start))}–${nice12(hm(p.end))}`;
  const where = p.screens.map((s) => `${s.name} (${s.room ?? "no room"}, ${s.site ?? ""} · ${s.tz})`).join("; ");
  const lines = [`Graphic: "${p.media.title}" (${p.media.kind})`, `Screens: ${where}`, `When: ${when} local time`];
  if (p.replaces.length) lines.push(`Takes over from (only during that window):\n  - ${p.replaces.join("\n  - ")}`);
  if (p.warnings.length) lines.push(`Warnings:\n  - ${p.warnings.join("\n  - ")}`);
  return lines.join("\n");
}

async function scheduleGraphic(db: Db, a: any) {
  const p = await plan(db, a);
  const summary = summarize(p, a);
  if (a.confirm !== true) return `PREVIEW ONLY. Nothing has been scheduled yet.\n\n${summary}\n\nShow this to the user. If they agree, call schedule_graphic again with the same arguments and confirm=true.`;

  const sites = new Set(p.screens.map((s) => s.site_id));
  const seconds = p.media.kind === "image" ? Math.min(Math.max(Math.round(+a.seconds || 15), 3), 300) : null;
  const item: Record<string, unknown> = { type: p.media.kind, title: p.media.title, url: p.media.url, media_id: p.media.id };
  if (seconds) item.seconds = seconds;
  const label = (typeof a.label === "string" && a.label.trim()) ? a.label.trim().slice(0, 120) : p.media.title;
  const pl = must(
    await db.from("signage_playlists").insert({
      organization_id: p.media.organization_id, site_id: sites.size === 1 ? [...sites][0] : null, name: `Scheduled: ${label}`.slice(0, 120), items: [item], source: "mcp",
    }).select("id").single(),
    "create the playlist for this graphic",
  ) as any;

  const rows = p.screens.map((s) => ({
    organization_id: p.media.organization_id, screen_id: s.id, playlist_id: pl.id, days: [p.weekday], start_time: p.start, end_time: p.end,
    priority: TAKEOVER_PRIORITY, start_date: p.dates[0], end_date: p.dates[p.dates.length - 1], label, source: "mcp",
  }));
  const ins = await db.from("signage_slots").insert(rows).select("id,screen_id");
  if (ins.error) {
    await db.from("signage_playlists").delete().eq("id", pl.id);
    must(ins as any, "schedule the graphic");
  }
  const made = (ins.data as any[]).map((r) => `${p.screens.find((s) => s.id === r.screen_id)?.name}: slot_id ${r.id}`).join("\n");
  return `Scheduled.\n\n${summary}\n\n${made}\n\nScreens pick up changes within a minute or two. Use cancel_scheduled with a slot_id to remove it.`;
}

async function listScheduled(db: Db, a: any) {
  if (!isUuid(a.organization_id)) throw new ToolError("organization_id is required (from list_targets).");
  const slots = must(
    await db.from("signage_slots").select("id,screen_id,group_id,playlist_id,days,start_time,end_time,start_date,end_date,label,source")
      .eq("organization_id", a.organization_id).not("start_date", "is", null).order("start_date"),
    "read scheduled graphics",
  ) as any[];
  if (!slots.length) return "No dated or assistant-scheduled graphics.";
  const sc = slots.filter((s) => s.screen_id).map((s) => s.screen_id);
  const screens = sc.length ? (must(await db.from("screens").select("id,name,location_id").in("id", sc), "read screens") as any[]) : [];
  const out: string[] = [];
  const today = new Date().toISOString().slice(0, 10);
  for (const s of slots) {
    if (s.end_date && s.end_date < addDays(today, -1)) continue;
    const name = screens.find((x) => x.id === s.screen_id)?.name ?? "(group)";
    const repeat = s.end_date !== s.start_date ? `every ${DAYNAMES[s.days[0]]}, ${s.start_date} → ${s.end_date}` : `${DAYNAMES[s.days[0]]} ${s.start_date}`;
    out.push(`- ${s.label ?? "(no label)"}: ${name}, ${repeat}, ${nice12(hm(s.start_time))}–${nice12(hm(s.end_time))}${s.source === "mcp" ? " [assistant]" : ""}  slot_id: ${s.id}`);
  }
  return out.length ? out.join("\n") : "Nothing upcoming.";
}

async function cancelScheduled(db: Db, a: any) {
  if (!isUuid(a.slot_id)) throw new ToolError("slot_id is required (from list_scheduled).");
  const slot = must(await db.from("signage_slots").select("id,screen_id,playlist_id,start_time,end_time,start_date,end_date,days,label,source").eq("id", a.slot_id).maybeSingle(), "read that slot") as any;
  if (!slot) throw new ToolError("That slot wasn't found (or you don't have access).");
  const screen = slot.screen_id ? (must(await db.from("screens").select("name").eq("id", slot.screen_id).maybeSingle(), "read screen") as any) : null;
  const what = `"${slot.label ?? "slot"}" on ${screen?.name ?? "a screen group"}, ${slot.start_date ? `${slot.start_date}${slot.end_date !== slot.start_date ? ` → ${slot.end_date} (weekly)` : ""}` : "every week"}, ${nice12(hm(slot.start_time))}–${nice12(hm(slot.end_time))}`;
  if (slot.start_date == null && slot.source !== "mcp") throw new ToolError("That is a regular weekly slot, not a scheduled graphic. Change it in the dashboard (Signage > Slots & schedule).");
  if (a.confirm !== true) return `PREVIEW ONLY. This would remove ${what}. Ask the user, then call again with confirm=true.`;
  const del = must(await db.from("signage_slots").delete().eq("id", slot.id).select("id"), "remove that slot") as any[];
  if (!del.length) throw new ToolError("Your account isn't allowed to remove that slot.");
  if (slot.playlist_id) {
    const others = await db.from("signage_slots").select("id", { count: "exact", head: true }).eq("playlist_id", slot.playlist_id);
    if (!others.error && (others.count ?? 1) === 0) await db.from("signage_playlists").delete().eq("id", slot.playlist_id).eq("source", "mcp");
  }
  return `Removed ${what}.`;
}

async function callTool(db: Db, userId: string, name: string, args: any): Promise<string> {
  switch (name) {
    case "list_targets": return await listTargets(db, userId);
    case "list_graphics": return await listGraphics(db, args ?? {});
    case "upload_graphic": return await uploadGraphic(db, args ?? {});
    case "schedule_graphic": return await scheduleGraphic(db, args ?? {});
    case "list_scheduled": return await listScheduled(db, args ?? {});
    case "cancel_scheduled": return await cancelScheduled(db, args ?? {});
    default: throw new ToolError(`Unknown tool: ${name}`);
  }
}

// ───────────────────────── MCP protocol ─────────────────────────
async function handleRpc(msg: any, db: Db, userId: string): Promise<unknown | null> {
  const id = msg.id;
  const ok = (result: unknown) => ({ jsonrpc: "2.0", id, result });
  const fail = (code: number, message: string) => ({ jsonrpc: "2.0", id, error: { code, message } });
  if (id === undefined) return null; // notification
  switch (msg.method) {
    case "initialize": {
      const asked = msg.params?.protocolVersion;
      return ok({
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER,
        instructions:
          "Church TV OS signage. Start with list_targets to learn the churches, screens and the local date. To put a graphic on a screen: upload_graphic (or list_graphics), then " +
          "schedule_graphic WITHOUT confirm, read the preview back to the user (graphic, screens, day/date, local times, conflicts), and only after they agree call it again with confirm=true. " +
          "Never schedule or cancel without that confirmation. Times are the site's local time.",
      });
    }
    case "ping": return ok({});
    case "tools/list": return ok({ tools: TOOLS });
    case "tools/call": {
      try {
        const text = await callTool(db, userId, msg.params?.name, msg.params?.arguments);
        return ok({ content: [{ type: "text", text }] });
      } catch (e) {
        if (e instanceof ToolError) return ok({ isError: true, content: [{ type: "text", text: e.message }] });
        console.error(e);
        return ok({ isError: true, content: [{ type: "text", text: "Something went wrong on the server. Nothing was changed unless a message above says so." }] });
      }
    }
    default: return fail(-32601, `Method not found: ${msg.method}`);
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (url.pathname.includes("/.well-known/oauth-protected-resource")) {
    return json({ resource: FUNCTION_URL, authorization_servers: [`${SUPABASE_URL}/auth/v1`], bearer_methods_supported: ["header"], resource_name: "Church TV OS" });
  }
  if (req.method === "GET") return json({ name: SERVER.name, mcp: FUNCTION_URL, docs: "https://app.churchtvos.com" });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const unauthorized = () =>
    json({ jsonrpc: "2.0", error: { code: -32001, message: "Sign in required" }, id: null }, 401, {
      "www-authenticate": `Bearer resource_metadata="${FUNCTION_URL}/.well-known/oauth-protected-resource"`,
    });
  const token = /^Bearer (.+)$/i.exec(req.headers.get("authorization") ?? "")?.[1];
  if (!token) return unauthorized();
  const db = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: u, error: ue } = await db.auth.getUser(token);
  if (ue || !u.user) return unauthorized();

  let body: any;
  try { body = await req.json(); } catch { return json({ jsonrpc: "2.0", error: { code: -32700, message: "Parse error" }, id: null }, 400); }
  if (Array.isArray(body)) {
    const results = (await Promise.all(body.map((m) => handleRpc(m, db, u.user.id)))).filter((r) => r !== null);
    return results.length ? json(results) : new Response(null, { status: 202, headers: CORS });
  }
  const res = await handleRpc(body, db, u.user.id);
  return res === null ? new Response(null, { status: 202, headers: CORS }) : json(res);
});
