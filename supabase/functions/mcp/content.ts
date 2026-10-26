// Kids playlists and Slides decks: list, read, create, replace. Plus the song library and slide themes they draw on.
// Item / slide shapes are the shared contract in dashboard/src/types.ts (PlaylistItem) and dashboard/src/slidesTypes.ts (DeckSlide).
import {
  CONFIRM_NOTE, PREVIEW_NOTE, Recorder, ToolError, activityLine, isUuid, must, needUuid, text,
  type Ctx, type Db, type Tool,
} from "./lib.ts";
import { LIST_PROPS, folderFor, listContent } from "./organize.ts";

type Lookups = { media: Map<string, any>; songs: Map<string, any> };

async function lookups(db: Db, org: string, list: any[]): Promise<Lookups> {
  const mids = [...new Set(list.map((i) => i?.media_id).filter(isUuid))];
  const sids = [...new Set(list.map((i) => i?.song_id).filter(isUuid))];
  const [m, s] = await Promise.all([
    mids.length ? db.from("media").select("id,title,kind,url,organization_id").in("id", mids) : Promise.resolve({ data: [], error: null }),
    sids.length ? db.from("songs").select("id,title,organization_id").in("id", sids) : Promise.resolve({ data: [], error: null }),
  ]);
  const media = new Map((must(m as any, "read media") as any[]).filter((x) => x.organization_id === org).map((x) => [x.id, x]));
  const songs = new Map((must(s as any, "read songs") as any[]).filter((x) => x.organization_id === org).map((x) => [x.id, x]));
  return { media, songs };
}
const getMedia = (L: Lookups, id: unknown, kinds: string[]) => {
  const m = L.media.get(id as string);
  if (!m) throw new ToolError(`media_id ${id} wasn't found in this church's library. Use list_media.`);
  if (!kinds.includes(m.kind)) throw new ToolError(`"${m.title}" is ${m.kind}; this needs ${kinds.join(" or ")}.`);
  return m;
};
const getSong = (L: Lookups, id: unknown) => {
  const s = L.songs.get(id as string);
  if (!s) throw new ToolError(`song_id ${id} wasn't found. Use search_songs.`);
  return s;
};
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
function countdownFields(i: any) {
  const title = text(i.title, 120) || "Starting soon";
  if (i.until) {
    if (!HHMM.test(i.until)) throw new ToolError("countdown until must be HH:MM (24-hour).");
    return { title, mode: "until", until: i.until, at_zero: i.at_zero === "next" ? "next" : "hold", if_passed: "zero" };
  }
  const seconds = Math.round(+i.seconds || 0);
  if (seconds < 5 || seconds > 4 * 3600) throw new ToolError("countdown needs seconds (5 to 14400) or until (HH:MM).");
  return { title, mode: "duration", seconds, at_zero: i.at_zero === "next" ? "next" : "hold" };
}
function streamUrl(u: unknown) {
  if (typeof u !== "string" || !/^https:\/\/.+\.m3u8(\?.*)?$/i.test(u)) throw new ToolError("stream url must be an https .m3u8 (HLS) link.");
  return u;
}

function kidsItem(i: any, L: Lookups): any {
  switch (i?.type) {
    case "video": { const m = getMedia(L, i.media_id, ["video"]); return { type: "video", title: m.title, url: m.url, media_id: m.id }; }
    case "image": { const m = getMedia(L, i.media_id, ["image"]); return { type: "image", title: m.title, url: m.url, media_id: m.id, seconds: i.seconds ? Math.max(1, Math.round(+i.seconds)) : null }; }
    case "countdown": return { type: "countdown", ...countdownFields(i) };
    case "lyrics": { const s = getSong(L, i.song_id); return { type: "lyrics", title: s.title, song_id: s.id, show_title: !!i.show_title }; }
    case "youtube": {
      const vid = typeof i.video_id === "string" && /^[\w-]{11}$/.test(i.video_id) ? i.video_id : null;
      const ch = typeof i.channel_id === "string" && /^UC[\w-]{22}$/.test(i.channel_id) ? i.channel_id : null;
      if (!vid && !ch) throw new ToolError("youtube needs video_id (11 characters) or channel_id (UC…, plays its live stream).");
      return { type: "youtube", title: text(i.title, 120) || "YouTube", video_id: vid, channel_id: vid ? null : ch, start: null };
    }
    case "stream": return { type: "stream", title: text(i.title, 120) || "Live", url: streamUrl(i.url), seconds: null, audio: i.audio !== false, fallback: "skip" };
    default: throw new ToolError(`Unknown Kids item type "${i?.type}". Use video, image, countdown, lyrics, youtube or stream.`);
  }
}

function newId(used: Set<string>) {
  for (;;) {
    const id = "s_" + Math.random().toString(36).slice(2, 7).padEnd(5, "0");
    if (!used.has(id)) { used.add(id); return id; }
  }
}
function deckSlide(i: any, L: Lookups, used: Set<string>): any {
  const base = { id: newId(used) };
  const secs = (v: unknown) => (v ? Math.max(1, Math.round(+v)) : null);
  switch (i?.kind) {
    case "text": {
      const title = text(i.title, 200), body = typeof i.body === "string" ? i.body.slice(0, 2000) : "";
      if (!title && !body) throw new ToolError("A text slide needs a title or body.");
      const layout = ["title_body", "title", "body", "lower_third"].includes(i.layout) ? i.layout : undefined;
      return { ...base, kind: "text", ...(title && { title }), ...(body && { body }), ...(layout && { layout }), seconds: secs(i.seconds) };
    }
    case "media": {
      const m = getMedia(L, i.media_id, ["image", "video"]);
      return { ...base, kind: "media", media_id: m.id, url: m.url, media_kind: m.kind, fit: i.fit === "cover" ? "cover" : "contain", ...(m.kind === "image" && { seconds: secs(i.seconds) }) };
    }
    case "song": { const s = getSong(L, i.song_id); return { ...base, kind: "song", song_id: s.id, show_title: !!i.show_title }; }
    case "countdown": return { ...base, kind: "countdown", ...countdownFields(i) };
    case "stream": return { ...base, kind: "stream", title: text(i.title, 120) || "Live", url: streamUrl(i.url), audio: i.audio !== false, fallback: "skip", seconds: null };
    case "blank": return { ...base, kind: "blank", ...(typeof i.color === "string" && /^#[0-9a-f]{6}$/i.test(i.color) && { color: i.color }) };
    default: throw new ToolError(`Unknown slide kind "${i?.kind}". Use text, media, song, countdown, stream or blank.`);
  }
}

const itemLine = (x: any, n: number) => {
  const t = x.type ?? x.kind;
  const what = x.title ?? x.body?.slice(0, 40) ?? "";
  const extra = t === "countdown" ? (x.until ? ` until ${x.until}` : ` ${x.seconds}s`) : x.seconds ? ` ${x.seconds}s` : "";
  return `${n + 1}. ${t}${what ? `: ${what}` : ""}${extra}`;
};

// ───────────────────────── Kids playlists ─────────────────────────
async function listKidsPlaylists({ db }: Ctx, a: any) {
  const { rows, path } = await listContent(db, "kids", a, "id,name,items");
  return rows.length
    ? rows.map((p) => `- ${p.name} (${(p.items ?? []).length} items)${p.archived_at ? " ARCHIVED" : ""}${path(p.folder_id)}  playlist_id: ${p.id}`).join("\n")
    : "No matching Kids playlists.";
}
async function getKidsPlaylist({ db }: Ctx, a: any) {
  const p = must(await db.from("playlists").select("id,name,items").eq("id", needUuid(a.playlist_id, "playlist_id")).maybeSingle(), "read that playlist") as any;
  if (!p) throw new ToolError("That playlist wasn't found.");
  return `${p.name}  playlist_id: ${p.id}\n${(p.items ?? []).map(itemLine).join("\n") || "(empty)"}`;
}
async function saveKidsPlaylist({ db }: Ctx, a: any) {
  const editing = a.playlist_id ? needUuid(a.playlist_id, "playlist_id") : null;
  const existing = editing ? (must(await db.from("playlists").select("id,name,organization_id,items").eq("id", editing).maybeSingle(), "read that playlist") as any) : null;
  if (editing && !existing) throw new ToolError("That playlist wasn't found.");
  const org = existing?.organization_id ?? needUuid(a.organization_id, "organization_id");
  const name = text(a.name, 120) || existing?.name;
  if (!name) throw new ToolError("name is required.");
  let items = existing?.items;
  if (a.items !== undefined) {
    if (!Array.isArray(a.items) || a.items.length > 200) throw new ToolError("items must be a list (up to 200).");
    const L = await lookups(db, org, a.items);
    items = a.items.map((i: any) => kidsItem(i, L));
  }
  if (!editing) {
    const rec = new Recorder(db, org, "create_kids_playlist");
    const folder_id = await folderFor(db, org, "kids", a.folder_id);
    const [row] = await rec.insert("playlists", { organization_id: org, site_id: isUuid(a.site_id) ? a.site_id : null, folder_id, source: "mcp", name, items: items ?? [] }, "create the Kids playlist");
    const act = await rec.commit(`Kids playlist "${name}" created`);
    return `Created Kids playlist "${name}"  playlist_id: ${row.id}\n${(items ?? []).map(itemLine).join("\n")}\n\nIt isn't on any screen until scheduled (schedule_kids).${activityLine(act)}`;
  }
  const preview = `"${existing.name}" → "${name}"\nBefore (${existing.items.length}):\n${existing.items.map(itemLine).join("\n")}\nAfter (${items.length}):\n${items.map(itemLine).join("\n")}`;
  if (a.confirm !== true) return `${PREVIEW_NOTE} Anything already scheduled with this playlist will play the new version.\n\n${preview}\n\n${CONFIRM_NOTE}`;
  const rec = new Recorder(db, org, "update_kids_playlist");
  await rec.update("playlists", { id: editing }, { name, items }, "update the Kids playlist");
  const act = await rec.commit(`Kids playlist "${name}" changed`);
  return `Saved.\n\n${preview}${activityLine(act)}`;
}

// ───────────────────────── Slides decks ─────────────────────────
async function listDecks({ db }: Ctx, a: any) {
  const { rows, path } = await listContent(db, "slides", a, "id,name,slides,loops");
  return rows.length
    ? rows.map((d) => `- ${d.name} (${(d.slides ?? []).length} slides${d.loops ? ", loops" : ""})${d.archived_at ? " ARCHIVED" : ""}${path(d.folder_id)}  deck_id: ${d.id}`).join("\n")
    : "No matching decks.";
}
async function getDeck({ db }: Ctx, a: any) {
  const d = must(await db.from("decks").select("id,name,slides,loops,theme_id").eq("id", needUuid(a.deck_id, "deck_id")).maybeSingle(), "read that deck") as any;
  if (!d) throw new ToolError("That deck wasn't found.");
  return `${d.name}  deck_id: ${d.id}${d.loops ? " (loops)" : ""}\n${(d.slides ?? []).map(itemLine).join("\n") || "(empty)"}`;
}
async function saveDeck({ db }: Ctx, a: any) {
  const editing = a.deck_id ? needUuid(a.deck_id, "deck_id") : null;
  const existing = editing ? (must(await db.from("decks").select("id,name,organization_id,slides,loops,theme_id").eq("id", editing).maybeSingle(), "read that deck") as any) : null;
  if (editing && !existing) throw new ToolError("That deck wasn't found.");
  const org = existing?.organization_id ?? needUuid(a.organization_id, "organization_id");
  const name = text(a.name, 120) || existing?.name;
  if (!name) throw new ToolError("name is required.");
  let slides = existing?.slides;
  if (a.slides !== undefined) {
    if (!Array.isArray(a.slides) || a.slides.length > 300) throw new ToolError("slides must be a list (up to 300).");
    const L = await lookups(db, org, a.slides);
    const used = new Set<string>();
    slides = a.slides.map((i: any) => deckSlide(i, L, used));
  }
  const patch: Record<string, unknown> = { name, slides: slides ?? [] };
  if (a.loops !== undefined) patch.loops = !!a.loops;
  if (a.theme_id !== undefined) patch.theme_id = isUuid(a.theme_id) ? a.theme_id : null;
  if (!editing) {
    const rec = new Recorder(db, org, "create_deck");
    const folder_id = await folderFor(db, org, "slides", a.folder_id);
    const [row] = await rec.insert("decks", { organization_id: org, site_id: isUuid(a.site_id) ? a.site_id : null, folder_id, source: "mcp", loops: false, ...patch }, "create the deck");
    const act = await rec.commit(`Deck "${name}" created`);
    return `Created deck "${name}"  deck_id: ${row.id}\n${(slides ?? []).map(itemLine).join("\n")}\n\nIt isn't on any screen until scheduled (schedule_slides) or played (play_now).${activityLine(act)}`;
  }
  const preview = `"${existing.name}" → "${name}"\nBefore (${existing.slides.length}):\n${existing.slides.map(itemLine).join("\n")}\nAfter (${(slides ?? []).length}):\n${(slides ?? []).map(itemLine).join("\n")}`;
  if (a.confirm !== true) return `${PREVIEW_NOTE} Anything already scheduled with this deck will show the new version.\n\n${preview}\n\n${CONFIRM_NOTE}`;
  const rec = new Recorder(db, org, "update_deck");
  await rec.update("decks", { id: editing }, patch, "update the deck");
  const act = await rec.commit(`Deck "${name}" changed`);
  return `Saved.\n\n${preview}${activityLine(act)}`;
}
async function listThemes({ db }: Ctx, a: any) {
  const rows = must(await db.from("slide_themes").select("id,name").eq("organization_id", needUuid(a.organization_id, "organization_id")).order("name"), "read themes") as any[];
  return rows.length ? rows.map((t) => `- ${t.name}  theme_id: ${t.id}`).join("\n") : "No themes yet (decks use the church's default look).";
}
async function searchSongs({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  let q = db.from("songs").select("id,title,authors,ccli_number").eq("organization_id", org);
  const s = text(a.query).replace(/[%_,()]/g, "");
  if (s) q = q.or(`title.ilike.%${s}%,authors.ilike.%${s}%`);
  const rows = must(await q.order("title").limit(30), "search songs") as any[];
  return rows.length ? rows.map((r) => `- ${r.title}${r.authors ? ` — ${r.authors}` : ""}${r.ccli_number ? ` (CCLI ${r.ccli_number})` : ""}  song_id: ${r.id}`).join("\n")
    : "No matching songs in the library. Songs are added in the dashboard (Songs) so their lyrics and licensing details are right.";
}

const KIDS_ITEM_DOC =
  "items, in order. Each is one of: {type:'video', media_id} · {type:'image', media_id, seconds?} · {type:'countdown', title?, seconds | until:'HH:MM', at_zero?:'hold'|'next'} · " +
  "{type:'lyrics', song_id, show_title?} · {type:'youtube', video_id | channel_id, title?} · {type:'stream', url (https .m3u8), title?}";
const SLIDE_DOC =
  "slides, in order. Each is one of: {kind:'text', title?, body?, layout?:'title_body'|'title'|'body'|'lower_third', seconds?} · {kind:'media', media_id, seconds?, fit?:'contain'|'cover'} · " +
  "{kind:'song', song_id, show_title?} · {kind:'countdown', title?, seconds | until:'HH:MM', at_zero?} · {kind:'stream', url, title?} · {kind:'blank', color?}. " +
  "seconds absent = waits for Next on the remote.";

export const CONTENT_TOOLS: Tool[] = [
  { name: "list_kids_playlists", description: "Lists a church's Kids playlists with their folders (archived ones hidden unless include_archived).", inputSchema: { type: "object", properties: LIST_PROPS, required: ["organization_id"], additionalProperties: false }, annotations: { readOnlyHint: true }, run: listKidsPlaylists },
  { name: "get_kids_playlist", description: "Shows the items in a Kids playlist.", inputSchema: { type: "object", properties: { playlist_id: { type: "string" } }, required: ["playlist_id"], additionalProperties: false }, annotations: { readOnlyHint: true }, run: getKidsPlaylist },
  {
    name: "save_kids_playlist",
    description: "Creates a Kids playlist (no playlist_id), or replaces an existing one's name and/or items (playlist_id; preview first, then confirm=true). " + KIDS_ITEM_DOC,
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string", description: "Required when creating" }, playlist_id: { type: "string" }, site_id: { type: "string", description: "Optional: only for one site" },
        folder_id: { type: "string", description: "Creating: folder to put it in (list_folders); default \"Made by assistant\"; \"top\" for the top level" },
        name: { type: "string" }, items: { type: "array", items: { type: "object" } }, confirm: { type: "boolean" },
      },
      additionalProperties: false,
    },
    run: saveKidsPlaylist,
  },
  { name: "list_decks", description: "Lists a church's Slides decks with their folders (archived ones hidden unless include_archived).", inputSchema: { type: "object", properties: LIST_PROPS, required: ["organization_id"], additionalProperties: false }, annotations: { readOnlyHint: true }, run: listDecks },
  { name: "get_deck", description: "Shows the slides in a deck.", inputSchema: { type: "object", properties: { deck_id: { type: "string" } }, required: ["deck_id"], additionalProperties: false }, annotations: { readOnlyHint: true }, run: getDeck },
  {
    name: "save_deck",
    description: "Creates a Slides deck (no deck_id), or replaces an existing deck's name/slides/theme/looping (deck_id; preview first, then confirm=true). " + SLIDE_DOC,
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string", description: "Required when creating" }, deck_id: { type: "string" }, site_id: { type: "string" },
        folder_id: { type: "string", description: "Creating: folder to put it in (list_folders); default \"Made by assistant\"; \"top\" for the top level" },
        name: { type: "string" }, slides: { type: "array", items: { type: "object" } }, theme_id: { type: "string" }, loops: { type: "boolean" }, confirm: { type: "boolean" },
      },
      additionalProperties: false,
    },
    run: saveDeck,
  },
  { name: "list_themes", description: "Lists a church's slide themes (for save_deck theme_id).", inputSchema: { type: "object", properties: { organization_id: { type: "string" } }, required: ["organization_id"], additionalProperties: false }, annotations: { readOnlyHint: true }, run: listThemes },
  {
    name: "search_songs",
    description: "Searches the church's song library by title or author (for lyrics items and song slides). Songs themselves are added in the dashboard.",
    inputSchema: { type: "object", properties: { organization_id: { type: "string" }, query: { type: "string" } }, required: ["organization_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: searchSongs,
  },
];
