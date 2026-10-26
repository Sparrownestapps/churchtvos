// Tools shared by every module: who/where (list_targets), the media library, and getting files in.
//
// Getting a file in. A chat app does not hand its attachments to MCP servers, so there are four routes:
//   1. upload_from_url    the file is already online (Canva export link, shared Google Drive / Dropbox link, website).
//   2. create_upload_url  the assistant can run commands (Claude Code, Cowork): it PUTs the file to a one-time signed URL.
//   3. the upload page    everyone else: schedule_signage with `upload` (or request_upload) gives a link to app.churchtvos.com/upload,
//                         where the person picks the file and, for a schedule, confirms in the same step.
//   4. upload_image       base64 in the call itself; only practical for very small images.
import {
  DAYNAMES, Recorder, ToolError, dow, isOnline, localNow, must, needUuid, text,
  type Ctx, type Db, type Tool,
} from "./lib.ts";

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MAX_VIDEO_BYTES = 50 * 1024 * 1024; // fetched into memory by the function; bigger files go through the upload page
export const APP_URL = Deno.env.get("APP_URL") ?? "https://app.churchtvos.com";
const MODULES = ["kids", "signage", "slides"];

async function listTargets({ db, userId }: Ctx) {
  const mem = must(await db.from("memberships").select("organization_id,role,modules,site_ids").eq("user_id", userId), "read your churches") as any[];
  if (!mem.length) return "This account isn't a member of any church yet.";
  const orgIds = mem.map((m) => m.organization_id);
  const [orgs, sites, locs, screens, groups, ents] = await Promise.all([
    db.from("organizations").select("id,name").in("id", orgIds),
    db.from("sites").select("id,name,timezone,organization_id").in("organization_id", orgIds).order("name"),
    db.from("locations").select("id,name,site_id,organization_id").in("organization_id", orgIds).order("name"),
    db.from("screens").select("id,name,organization_id,location_id,group_id,default_module,orientation,last_seen_at,app_version").in("organization_id", orgIds).order("name"),
    db.from("screen_groups").select("id,name,organization_id").in("organization_id", orgIds),
    db.from("entitlements").select("organization_id,module,status").in("organization_id", orgIds),
  ]);
  const O = must(orgs, "read churches") as any[], S = must(sites, "read sites") as any[], L = must(locs, "read rooms") as any[];
  const SC = must(screens, "read screens") as any[], G = must(groups, "read groups") as any[], E = must(ents, "read plans") as any[];
  const screenLine = (sc: any) => {
    const grp = G.find((g) => g.id === sc.group_id);
    return `Screen "${sc.name ?? "Unnamed"}"  screen_id: ${sc.id}  default: ${sc.default_module}${sc.orientation && sc.orientation !== "landscape" ? `  ${sc.orientation}` : ""}` +
      `${grp ? `  group: ${grp.name}` : ""}  ${isOnline(sc) ? "online" : "OFFLINE"}${sc.app_version ? `  app ${sc.app_version}` : ""}`;
  };
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
        for (const sc of SC.filter((x) => x.location_id === l.id)) out.push(`  - ${screenLine(sc)}`);
      }
    }
    const loose = SC.filter((x) => x.organization_id === o.id && !L.some((l) => l.id === x.location_id));
    if (loose.length) {
      out.push(`\n## Screens not in a room (assign one in the dashboard's Screens page; Kids and Slides need a room)`);
      for (const sc of loose) out.push(`- ${screenLine(sc)}`);
    }
  }
  out.push("\nPortrait screens: give them upright portrait artwork (e.g. 1080×1920); the TV turns it to suit how the screen is mounted.");
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

// ───────────────────────── File type checks ─────────────────────────
type Sniffed = { ct: string; kind: "image" | "video"; ext: string };
export function sniff(b: Uint8Array): Sniffed | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return { ct: "image/png", kind: "image", ext: "png" };
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { ct: "image/jpeg", kind: "image", ext: "jpg" };
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45) return { ct: "image/webp", kind: "image", ext: "webp" };
  if (b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) { // "ftyp": MP4 / MOV
    const brand = String.fromCharCode(b[8], b[9], b[10], b[11]);
    return brand === "qt  " ? { ct: "video/quicktime", kind: "video", ext: "mov" } : { ct: "video/mp4", kind: "video", ext: "mp4" };
  }
  if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) return { ct: "video/webm", kind: "video", ext: "webm" };
  return null;
}
const PRIVATE_HOST = /^(localhost|127\.|10\.|0\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[|metadata\.)/i;
function publicHttps(raw: string): URL {
  let u: URL;
  try { u = new URL(raw); } catch { throw new ToolError("That isn't a valid link."); }
  if (u.protocol !== "https:" || PRIVATE_HOST.test(u.hostname) || !u.hostname.includes(".") || /^\d+\.\d+\.\d+\.\d+$/.test(u.hostname)) {
    throw new ToolError("The link must be a public https address.");
  }
  return u;
}
/** Share links that point at a viewer page -> their direct-download form. */
export function directLink(raw: string): string {
  const u = publicHttps(raw);
  const drive = /^\/file\/d\/([\w-]+)/.exec(u.pathname);
  if (u.hostname === "drive.google.com" && drive) return `https://drive.usercontent.google.com/download?id=${drive[1]}&export=download&confirm=t`;
  if (u.hostname === "drive.google.com" && u.searchParams.get("id")) return `https://drive.usercontent.google.com/download?id=${u.searchParams.get("id")}&export=download&confirm=t`;
  if (/(^|\.)dropbox\.com$/.test(u.hostname)) { u.searchParams.delete("dl"); u.searchParams.set("raw", "1"); return u.toString(); }
  return u.toString();
}

async function fetchFile(raw: string): Promise<{ bytes: Uint8Array } & Sniffed> {
  let url = directLink(raw);
  let r: Response | null = null;
  for (let hop = 0; hop < 5; hop++) { // follow redirects ourselves so every hop is checked for private addresses
    r = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(30000), headers: { "user-agent": "ChurchTVOS-MCP/1.0" } });
    const next = r.status >= 300 && r.status < 400 ? r.headers.get("location") : null;
    if (!next) break;
    url = publicHttps(new URL(next, url).toString()).toString();
  }
  if (!r || !r.ok) throw new ToolError(`Couldn't download that link (${r?.status ?? "no response"}). If it's a shared link, make sure anyone with the link can view it.`);
  const declared = +(r.headers.get("content-length") ?? 0);
  if (declared > MAX_VIDEO_BYTES) throw new ToolError("That file is over 50 MB; use the upload page (request_upload) for big videos.");
  const bytes = new Uint8Array(await r.arrayBuffer());
  const kind = sniff(bytes);
  if (!kind) {
    const html = /text\/html/i.test(r.headers.get("content-type") ?? "");
    throw new ToolError(html
      ? "That link opens a web page, not the file itself. Use a direct download link (for Canva, the export download link; for Drive or Dropbox, a share link set to 'anyone with the link')."
      : "That file isn't a PNG, JPEG, WebP, MP4, MOV or WebM.");
  }
  if (kind.kind === "image" && bytes.length > MAX_IMAGE_BYTES) throw new ToolError("That image is over 10 MB.");
  if (bytes.length > MAX_VIDEO_BYTES) throw new ToolError("That file is over 50 MB; use the upload page (request_upload) for big videos.");
  return { bytes, ...kind };
}

async function storeMedia(db: Db, org: string, module: string, title: string, bytes: Uint8Array, f: Sniffed, tool: string): Promise<string> {
  const path = `${org}/${crypto.randomUUID()}.${f.ext}`;
  const up = await db.storage.from("media").upload(path, bytes, { contentType: f.ct, upsert: false, cacheControl: "3600" });
  if (up.error) {
    throw new ToolError(/row-level security|not allowed|unauthorized|403/i.test(up.error.message)
      ? "Your account isn't allowed to upload to that church's media library (you need the editor role for Kids or Signage)."
      : `Upload failed: ${up.error.message}`);
  }
  const url = db.storage.from("media").getPublicUrl(path).data.publicUrl;
  const rec = new Recorder(db, org, tool);
  try {
    const [row] = await rec.insert("media", { organization_id: org, site_id: null, module, title, kind: f.kind, storage_path: path, url, size_bytes: bytes.length }, "add it to the media library");
    await rec.commit(`Added "${title}" (${f.kind}) to the ${module} library`);
    return row.id;
  } catch (e) {
    await db.storage.from("media").remove([path]);
    throw e;
  }
}
function libraryArgs(a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const module = a.module ?? "signage";
  if (!MODULES.includes(module)) throw new ToolError("module must be kids, signage or slides.");
  const title = text(a.title, 120);
  if (!title) throw new ToolError("title is required.");
  return { org, module, title };
}

async function uploadImage({ db }: Ctx, a: any) {
  const { org, module, title } = libraryArgs(a);
  if (a.image_url) return uploadFromUrl({ db } as Ctx, { ...a, url: a.image_url });
  if (typeof a.image_base64 !== "string" || !a.image_base64) throw new ToolError("Give image_base64. For files online use upload_from_url; otherwise use the upload page (schedule_signage with upload, or request_upload).");
  const raw = a.image_base64.replace(/^data:[^,]*,/, "").replace(/\s+/g, "");
  if (raw.length > MAX_IMAGE_BYTES * 1.4) throw new ToolError("That image is over 10 MB.");
  let bytes: Uint8Array;
  try { bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0)); } catch { throw new ToolError("image_base64 isn't valid base64."); }
  const f = sniff(bytes);
  if (!f || f.kind !== "image") throw new ToolError("Only PNG, JPEG and WebP images can be sent as base64.");
  const id = await storeMedia(db, org, module, title, bytes, f, "upload_image");
  return `Added "${title}" to the ${module} media library.\nmedia_id: ${id}`;
}

async function uploadFromUrl({ db }: Ctx, a: any) {
  const { org, module, title } = libraryArgs(a);
  if (typeof a.url !== "string" || !a.url) throw new ToolError("url is required.");
  const f = await fetchFile(a.url);
  const id = await storeMedia(db, org, module, title, f.bytes, f, "upload_from_url");
  return `Added "${title}" (${f.kind}, ${(f.bytes.length / 1048576).toFixed(1)} MB) to the ${module} media library.\nmedia_id: ${id}`;
}

/** An upload request: the upload page (link) or a signed URL. `plan` makes the page schedule it too (see signage.ts). */
export async function createUploadRequest(db: Db, fields: Record<string, unknown>): Promise<string> {
  const row = must(await db.from("mcp_upload_requests").insert(fields).select("id").single(), "start an upload") as any;
  return row.id;
}

async function requestUpload({ db }: Ctx, a: any) {
  const { org, module, title } = libraryArgs(a);
  const id = await createUploadRequest(db, { organization_id: org, module, title });
  return `Give the user this link to open (it works on a phone; they sign in to Church TV OS if asked) and choose the file:\n${APP_URL}/upload?request=${id}\n\n` +
    `When they say it's done, call check_upload with upload_id ${id} for the media_id. ` +
    `(To upload AND schedule signage in one step, use schedule_signage with upload instead.)`;
}

async function createUploadUrl({ db }: Ctx, a: any) {
  const { org, module, title } = libraryArgs(a);
  const name = text(a.filename, 200);
  const ext = (/\.([a-z0-9]{2,5})$/i.exec(name)?.[1] ?? "").toLowerCase();
  if (!["png", "jpg", "jpeg", "webp", "mp4", "mov", "m4v", "webm", "mp3", "m4a", "wav"].includes(ext)) {
    throw new ToolError("filename must end in .png, .jpg, .webp, .mp4, .mov, .webm, .mp3, .m4a or .wav.");
  }
  const path = `${org}/${crypto.randomUUID()}.${ext === "jpeg" ? "jpg" : ext}`;
  const s = await db.storage.from("media").createSignedUploadUrl(path);
  if (s.error || !s.data) {
    throw new ToolError(/row-level security|not allowed|unauthorized|403/i.test(s.error?.message ?? "")
      ? "Your account isn't allowed to upload to that church's media library (you need the editor role for Kids or Signage)."
      : `Couldn't create an upload address: ${s.error?.message}`);
  }
  const id = await createUploadRequest(db, { organization_id: org, module, title, storage_path: path });
  const ct = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", mp4: "video/mp4", m4v: "video/mp4", mov: "video/quicktime", webm: "video/webm", mp3: "audio/mpeg", m4a: "audio/mp4", wav: "audio/wav" }[ext];
  return `Upload the file with one HTTP PUT (valid for 2 hours), for example:\n` +
    `curl -sS -X PUT -H "Content-Type: ${ct}" --data-binary @"${name}" "${s.data.signedUrl}"\n\n` +
    `Then call check_upload with upload_id ${id} to add it to the library and get the media_id.`;
}

const MEDIA_KIND: Record<string, string> = { image: "image", video: "video", audio: "audio" };

async function checkUpload({ db }: Ctx, a: any) {
  const id = needUuid(a.upload_id, "upload_id");
  const r = must(await db.from("mcp_upload_requests").select("*").eq("id", id).maybeSingle(), "read that upload") as any;
  if (!r) throw new ToolError("That upload_id wasn't found.");

  // Signed-URL upload: turn the stored file into a media row the first time we see it.
  if (r.storage_path && !r.media_id) {
    const folder = r.storage_path.split("/")[0], file = r.storage_path.split("/").slice(1).join("/");
    const listed = await db.storage.from("media").list(folder, { search: file, limit: 5 });
    const obj = (listed.data ?? []).find((o: any) => o.name === file);
    if (!obj) return `The file hasn't arrived yet. Run the PUT from create_upload_url, then check again.`;
    const mime = String(obj.metadata?.mimetype ?? "");
    const kind = MEDIA_KIND[mime.split("/")[0]];
    if (!kind) {
      await db.storage.from("media").remove([r.storage_path]);
      throw new ToolError(`That file's type (${mime || "unknown"}) isn't an image, video or audio file; it was removed.`);
    }
    const url = db.storage.from("media").getPublicUrl(r.storage_path).data.publicUrl;
    const rec = new Recorder(db, r.organization_id, "check_upload");
    const [m] = await rec.insert("media", { organization_id: r.organization_id, site_id: null, module: r.module, title: r.title, kind, storage_path: r.storage_path, url, size_bytes: obj.metadata?.size ?? null }, "add it to the media library");
    await rec.commit(`Added "${r.title}" (${kind}) to the ${r.module} library`);
    must(await db.from("mcp_upload_requests").update({ media_id: m.id, media_ids: [m.id] }).eq("id", id).select("id"), "record the upload");
    return `Uploaded: "${r.title}" (${kind}) in the ${r.module} library.\nmedia_id: ${m.id}`;
  }

  if (!r.media_id) return `Not uploaded yet ("${r.title}"). The user still needs to finish the upload page: ${APP_URL}/upload?request=${id}`;
  const ids: string[] = r.media_ids?.length ? r.media_ids : [r.media_id];
  const lines = [`Uploaded ${ids.length === 1 ? `"${r.title}"` : `${ids.length} files`} to the ${r.module} library. media_id${ids.length > 1 ? "s" : ""}: ${ids.join(", ")}`];
  if (r.plan) lines.push(r.result ? `Schedule result:\n${r.result}` : "The schedule hasn't been confirmed on the page yet (it may have failed there; the user can try again from the same link).");
  return lines.join("\n\n");
}

export const COMMON_TOOLS: Tool[] = [
  {
    name: "list_targets",
    description:
      "Start here. Lists the user's churches with their sites (time zone and the current LOCAL date/time), rooms (location_id), and screens (screen_id), " +
      "what each screen runs by default, its orientation, whether it is online, and which applications (kids, signage, slides) the church and the user have. " +
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
    name: "upload_from_url",
    description:
      "Adds an image or video that is already online to a church's media library and returns its media_id. Works with Canva export download links, " +
      "Google Drive and Dropbox share links (set to 'anyone with the link'), and direct file links. PNG/JPEG/WebP up to 10 MB, MP4/MOV/WebM up to 50 MB. " +
      "Use this whenever the file has a link (for a Canva design, export it with the Canva tools and pass the download URL).",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string" },
        module: { type: "string", enum: MODULES, description: "Which library: signage (default), slides or kids" },
        title: { type: "string", description: "Short name shown in the library" },
        url: { type: "string" },
      },
      required: ["organization_id", "title", "url"],
      additionalProperties: false,
    },
    run: uploadFromUrl,
  },
  {
    name: "create_upload_url",
    description:
      "For assistants that can run shell commands (Claude Code, Cowork) and have the file on disk: returns a one-time signed URL and a curl command to PUT the file, " +
      "then check_upload adds it to the library. Fastest route when available; no action needed from the user. Not useful in a plain chat.",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string" }, module: { type: "string", enum: MODULES }, title: { type: "string" },
        filename: { type: "string", description: "Local file name incl. extension, e.g. poster.png" },
      },
      required: ["organization_id", "title", "filename"],
      additionalProperties: false,
    },
    run: createUploadUrl,
  },
  {
    name: "request_upload",
    description:
      "When the file only exists on the user's device (e.g. an image they attached in chat; chat attachments can't be passed to this server): returns a link the user opens " +
      "on their phone or computer to pick the file. For signage you usually want schedule_signage with `upload` instead, which uploads and schedules in one step on that page.",
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
    description: "Checks an upload (from request_upload, create_upload_url, or schedule_signage with upload): returns the media_id(s), and for upload-and-schedule, whether the schedule went through.",
    inputSchema: { type: "object", properties: { upload_id: { type: "string" } }, required: ["upload_id"], additionalProperties: false },
    run: checkUpload,
  },
  {
    name: "upload_image",
    description: "Adds a SMALL image sent as base64 (image_base64) to the media library. Only practical for tiny images; prefer upload_from_url, create_upload_url or the upload page.",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string" }, module: { type: "string", enum: MODULES }, title: { type: "string" },
        image_base64: { type: "string" }, image_url: { type: "string", description: "Deprecated: use upload_from_url" },
      },
      required: ["organization_id", "title"],
      additionalProperties: false,
    },
    run: uploadImage,
  },
];
