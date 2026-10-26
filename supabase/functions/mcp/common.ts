// Tools shared by every module: who/where (list_targets), the media library, uploads.
import {
  DAYNAMES, Recorder, ToolError, activityLine, dow, isOnline, localNow, must, needUuid, text,
  type Ctx, type Tool,
} from "./lib.ts";

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const APP_URL = Deno.env.get("APP_URL") ?? "https://app.churchtvos.com";
const MODULES = ["kids", "signage", "slides"];

async function listTargets({ db, userId }: Ctx) {
  const mem = must(await db.from("memberships").select("organization_id,role,modules,site_ids").eq("user_id", userId), "read your churches") as any[];
  if (!mem.length) return "This account isn't a member of any church yet.";
  const orgIds = mem.map((m) => m.organization_id);
  const [orgs, sites, locs, screens, groups, ents] = await Promise.all([
    db.from("organizations").select("id,name").in("id", orgIds),
    db.from("sites").select("id,name,timezone,organization_id").in("organization_id", orgIds).order("name"),
    db.from("locations").select("id,name,site_id,organization_id").in("organization_id", orgIds).order("name"),
    db.from("screens").select("id,name,organization_id,location_id,group_id,default_module,last_seen_at,app_version").in("organization_id", orgIds).order("name"),
    db.from("screen_groups").select("id,name,organization_id").in("organization_id", orgIds),
    db.from("entitlements").select("organization_id,module,status").in("organization_id", orgIds),
  ]);
  const O = must(orgs, "read churches") as any[], S = must(sites, "read sites") as any[], L = must(locs, "read rooms") as any[];
  const SC = must(screens, "read screens") as any[], G = must(groups, "read groups") as any[], E = must(ents, "read plans") as any[];
  const out: string[] = [];
  for (const o of O) {
    const m = mem.find((x) => x.organization_id === o.id)!;
    const on = MODULES.filter((mod) => E.some((e) => e.organization_id === o.id && e.module === mod && ["active", "trialing", "past_due"].includes(e.status)));
    const yours = ["owner", "admin"].includes(m.role) ? "all" : (m.modules ?? []).join(", ");
    out.push(`# ${o.name}  (organization_id: ${o.id})`);
    out.push(`Your role: ${m.role}${m.site_ids ? " (limited to some sites)" : ""}; your applications: ${yours}. Church has: ${on.join(", ") || "no active plan"}.`);
    for (const s of S.filter((x) => x.organization_id === o.id)) {
      const n = localNow(s.timezone);
      out.push(`\n## Site: ${s.name}  site_id: ${s.id}  (${s.timezone}; local now ${DAYNAMES[dow(n.date)]} ${n.date} ${n.time})`);
      for (const l of L.filter((x) => x.site_id === s.id)) {
        out.push(`- Room: ${l.name}  location_id: ${l.id}`);
        for (const sc of SC.filter((x) => x.location_id === l.id)) {
          const grp = G.find((g) => g.id === sc.group_id);
          out.push(`  - Screen "${sc.name ?? "Unnamed"}"  screen_id: ${sc.id}  default: ${sc.default_module}${grp ? `  group: ${grp.name}` : ""}  ${isOnline(sc) ? "online" : "OFFLINE"}${sc.app_version ? `  app ${sc.app_version}` : ""}`);
        }
      }
    }
  }
  return out.join("\n");
}

async function listMedia({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  let q = db.from("media").select("id,title,kind,module,url,created_at").eq("organization_id", org);
  if (a.module) q = q.eq("module", a.module);
  if (a.kind) q = q.eq("kind", a.kind);
  if (text(a.query)) q = q.ilike("title", `%${text(a.query).replace(/[%_]/g, "")}%`);
  const rows = must(await q.order("created_at", { ascending: false }).limit(Math.min(Math.max(+a.limit || 25, 1), 100)), "read the media library") as any[];
  if (!rows.length) return "No matching media.";
  return rows.map((r) => `- ${r.title} (${r.kind}, ${r.module})  media_id: ${r.id}`).join("\n");
}

function sniff(b: Uint8Array): string | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0xff && b[1] === 0xd8) return "image/jpeg";
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  return null;
}
const PRIVATE_HOST = /^(localhost|127\.|10\.|0\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[)/i;

async function uploadImage({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const module = a.module ?? "signage";
  if (!MODULES.includes(module)) throw new ToolError("module must be kids, signage or slides.");
  const title = text(a.title, 120);
  if (!title) throw new ToolError("title is required.");
  let bytes: Uint8Array;
  if (typeof a.image_base64 === "string" && a.image_base64) {
    const raw = a.image_base64.replace(/^data:[^,]*,/, "").replace(/\s+/g, "");
    if (raw.length > MAX_IMAGE_BYTES * 1.4) throw new ToolError("That image is over 10 MB. Resize it, or use request_upload.");
    try { bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)); } catch { throw new ToolError("image_base64 isn't valid base64."); }
  } else if (typeof a.image_url === "string" && a.image_url) {
    let u: URL;
    try { u = new URL(a.image_url); } catch { throw new ToolError("image_url isn't a valid URL."); }
    if (u.protocol !== "https:" || PRIVATE_HOST.test(u.hostname) || !u.hostname.includes(".")) throw new ToolError("image_url must be a public https link.");
    const r = await fetch(u, { redirect: "follow", signal: AbortSignal.timeout(20000) });
    if (!r.ok) throw new ToolError(`Couldn't download that link (${r.status}).`);
    bytes = new Uint8Array(await r.arrayBuffer());
  } else throw new ToolError("Give either image_base64 or image_url. For videos or big files use request_upload.");
  if (bytes.length > MAX_IMAGE_BYTES) throw new ToolError("That image is over 10 MB. Resize it, or use request_upload.");
  const ct = sniff(bytes);
  if (!ct) throw new ToolError("Only PNG, JPEG and WebP images can be sent this way. For other files use request_upload.");

  const path = `${org}/${crypto.randomUUID()}.${ct === "image/png" ? "png" : ct === "image/webp" ? "webp" : "jpg"}`;
  const up = await db.storage.from("media").upload(path, bytes, { contentType: ct, upsert: false, cacheControl: "3600" });
  if (up.error) {
    throw new ToolError(/row-level security|not allowed|unauthorized|403/i.test(up.error.message)
      ? "Your account isn't allowed to upload to that church's media library (you need the editor role for Kids or Signage)."
      : `Upload failed: ${up.error.message}`);
  }
  const url = db.storage.from("media").getPublicUrl(path).data.publicUrl;
  const rec = new Recorder(db, org, "upload_image");
  let row;
  try {
    [row] = await rec.insert("media", { organization_id: org, site_id: null, module, title, kind: "image", storage_path: path, url, size_bytes: bytes.length }, "add the image to the media library");
  } catch (e) {
    await db.storage.from("media").remove([path]);
    throw e;
  }
  return `Added "${title}" to the ${module} media library.\nmedia_id: ${row.id}`;
}

async function requestUpload({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const module = a.module ?? "signage";
  if (!MODULES.includes(module)) throw new ToolError("module must be kids, signage or slides.");
  const title = text(a.title, 120);
  if (!title) throw new ToolError("title is required.");
  const row = must(await db.from("mcp_upload_requests").insert({ organization_id: org, module, title }).select("id").single(), "start an upload") as any;
  return `Ask the user to open this link (signed in to Church TV OS) and choose the file:\n${APP_URL}/upload?request=${row.id}\n\n` +
    `When they say it's done, call check_upload with upload_id ${row.id} to get the media_id.`;
}

async function checkUpload({ db }: Ctx, a: any) {
  const id = needUuid(a.upload_id, "upload_id");
  const r = must(await db.from("mcp_upload_requests").select("media_id,title,module").eq("id", id).maybeSingle(), "read that upload") as any;
  if (!r) throw new ToolError("That upload_id wasn't found.");
  if (!r.media_id) return `Not uploaded yet ("${r.title}"). Ask the user to finish the upload page, then check again.`;
  const m = must(await db.from("media").select("id,title,kind").eq("id", r.media_id).maybeSingle(), "read the media") as any;
  return `Uploaded: "${m?.title ?? r.title}" (${m?.kind ?? "file"}) in the ${r.module} library.\nmedia_id: ${r.media_id}`;
}

export const COMMON_TOOLS: Tool[] = [
  {
    name: "list_targets",
    description:
      "Start here. Lists the user's churches with their sites (time zone and the current LOCAL date/time), rooms (location_id), and screens (screen_id), " +
      "what each screen runs by default, whether it is online, and which applications (kids, signage, slides) the church and the user have. " +
      "All schedule times are in the site's local time.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: (ctx) => listTargets(ctx),
  },
  {
    name: "list_media",
    description: "Lists files in a church's media library (newest first), optionally filtered by module, kind or title text. Use to reuse a file instead of uploading again.",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string" },
        module: { type: "string", enum: MODULES },
        kind: { type: "string", enum: ["image", "video", "audio"] },
        query: { type: "string", description: "Part of the title" },
        limit: { type: "integer", default: 25 },
      },
      required: ["organization_id"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true },
    run: listMedia,
  },
  {
    name: "upload_image",
    description:
      "Adds an image to a church's media library and returns its media_id. Give the image as base64 (image_base64; PNG, JPEG or WebP, up to 10 MB) or as a public https link (image_url). " +
      "For videos, audio or larger files use request_upload. Uploading does not put anything on a screen.",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string" },
        module: { type: "string", enum: MODULES, description: "Which library: signage (default), slides or kids" },
        title: { type: "string", description: "Short name shown in the library, e.g. 'Youth Night poster'" },
        image_base64: { type: "string" },
        image_url: { type: "string" },
      },
      required: ["organization_id", "title"],
      additionalProperties: false,
    },
    run: uploadImage,
  },
  {
    name: "request_upload",
    description:
      "For videos, audio, or files too big to send in the chat: returns a link the user opens (signed in to Church TV OS) to upload the file from their device. " +
      "Then call check_upload to get the media_id.",
    inputSchema: {
      type: "object",
      properties: { organization_id: { type: "string" }, module: { type: "string", enum: MODULES }, title: { type: "string" } },
      required: ["organization_id", "module", "title"],
      additionalProperties: false,
    },
    run: requestUpload,
  },
  {
    name: "check_upload",
    description: "Checks whether the user finished a request_upload, and returns the media_id when they have.",
    inputSchema: { type: "object", properties: { upload_id: { type: "string" } }, required: ["upload_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: checkUpload,
  },
];
