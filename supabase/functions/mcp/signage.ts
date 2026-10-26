// Signage tools: schedule one or more graphics (or an existing signage playlist) on screens, list and cancel those schedules.
// A schedule = a signage playlist + one signage_slots row per screen. Slots may carry start_date/end_date (see the
// 20261026000001 migration); device_state only hands a TV the slots whose dates include today in the site's time zone.
import {
  CONFIRM_NOTE, DAYNAMES, PREVIEW_NOTE, Recorder, ToolError, activityLine, addDays, dayList, dow, isDate, loadScreens, localNow,
  moduleActive, moduleWarnings, must, needUuid, parseDays, parseWindow, span, text,
  type Ctx, type Db, type Tool,
} from "./lib.ts";
import { APP_URL, createUploadRequest } from "./common.ts";

const ONE_OFF_PRIORITY = 100; // a dated one-off beats everything else
const RUN_PRIORITY = 50;      // assistant-made recurring runs beat everyday slots (0..)
// "Hold until the slot ends": the TV app turns a missing signage duration into 10 s, so holding is stored as a day
// (slots end by midnight). Same value as HOLD_SECONDS in dashboard/src/lib.ts.
export const HOLD_SECONDS = 86400;

type Item = { type: string; title: string; url: string; media_id: string; seconds?: number };

async function buildItems(db: Db, a: any): Promise<{ org: string; items: Item[]; names: string[] }> {
  const list = Array.isArray(a.items) ? a.items : [];
  if (!list.length || list.length > 50) throw new ToolError("items must list 1 to 50 graphics: [{media_id, seconds?}].");
  const ids = list.map((i: any) => needUuid(i?.media_id, "items[].media_id"));
  const media = must(await db.from("media").select("id,title,kind,url,organization_id").in("id", [...new Set(ids)]), "read the graphics") as any[];
  const items: Item[] = [];
  for (const i of list) {
    const m = media.find((x) => x.id === i.media_id);
    if (!m) throw new ToolError(`media_id ${i.media_id} wasn't found (or you don't have access). Use list_media.`);
    if (m.kind === "audio") throw new ToolError(`"${m.title}" is audio; signage shows images and videos.`);
    const item: Item = { type: m.kind, title: m.title, url: m.url, media_id: m.id };
    if (m.kind === "image") {
      // A lone image (with no seconds asked for) or hold:true stays up for the whole window instead of restarting every few seconds.
      const hold = i.hold === true || (list.length === 1 && !i.seconds && !a.seconds);
      item.seconds = hold ? HOLD_SECONDS : Math.min(Math.max(Math.round(+i.seconds || +a.seconds || 10), 3), 3600);
    }
    items.push(item);
  }
  const orgs = new Set(media.map((m) => m.organization_id));
  if (orgs.size !== 1) throw new ToolError("All graphics must belong to the same church.");
  const dur = (i: Item) => (!i.seconds ? "" : i.seconds >= HOLD_SECONDS ? " (holds for the whole window)" : ` (${i.seconds}s)`);
  return { org: [...orgs][0], items, names: items.map((i) => `${i.title}${dur(i)}`) };
}

type When = { days: number[]; startDate: string; endDate: string | null; oneOff: boolean; start: string; end: string };
function parseWhen(a: any): When {
  const { start, end } = parseWindow(a);
  if (a.date) {
    if (!isDate(a.date)) throw new ToolError("date must be YYYY-MM-DD.");
    return { days: [dow(a.date)], startDate: a.date, endDate: a.date, oneOff: true, start, end };
  }
  if (a.days === undefined) throw new ToolError("Give either date (one day) or days (a weekly run, e.g. \"weekdays\").");
  const days = parseDays(a.days);
  if (a.start_date !== undefined && !isDate(a.start_date)) throw new ToolError("start_date must be YYYY-MM-DD.");
  if (a.end_date !== undefined && !isDate(a.end_date)) throw new ToolError("end_date must be YYYY-MM-DD.");
  const startDate = a.start_date ?? null, endDate = a.end_date ?? null;
  if (startDate && endDate && endDate < startDate) throw new ToolError("end_date is before start_date.");
  return { days, startDate, endDate, oneOff: false, start, end } as When;
}
const whenText = (w: When) =>
  w.oneOff
    ? `${DAYNAMES[w.days[0]]} ${w.startDate}, ${span(w.start, w.end)}`
    : `${dayList(w.days)}, ${span(w.start, w.end)}, ${w.startDate ? `from ${w.startDate}` : "starting now"}${w.endDate ? ` through ${w.endDate}` : ", no end date"}`;

async function scheduleSignage({ db }: Ctx, a: any) {
  const when = parseWhen(a);
  const screenIds = [...new Set(Array.isArray(a.screen_ids) ? a.screen_ids : [])] as string[];
  const screens = await loadScreens(db, screenIds);

  let org: string, names: string[], items: Item[] | null = null, playlist: any = null;
  const upload = a.upload && typeof a.upload === "object" ? a.upload : null;
  if (upload) {
    // Files not uploaded yet: the person uploads them on the upload page, which also confirms this schedule.
    if (a.items || a.playlist_id) throw new ToolError("Give upload OR items OR playlist_id, not several.");
    org = screens[0].organization_id;
    const files = Math.min(Math.max(Math.round(+upload.files || 1), 1), 20);
    const title = text(upload.title, 120);
    if (!title) throw new ToolError("upload.title is required (the name the graphic gets in the library).");
    names = [`${files === 1 ? `"${title}"` : `${files} graphics ("${title}")`} — to be uploaded on the next page`];
  } else if (a.playlist_id) {
    playlist = must(await db.from("signage_playlists").select("id,name,organization_id,items").eq("id", needUuid(a.playlist_id, "playlist_id")).maybeSingle(), "read that playlist") as any;
    if (!playlist) throw new ToolError("That signage playlist wasn't found. Use list_signage_playlists.");
    org = playlist.organization_id;
    names = [`playlist "${playlist.name}" (${(playlist.items ?? []).length} items)`];
  } else {
    ({ org, items, names } = await buildItems(db, a));
  }
  if (screens.some((s) => s.organization_id !== org)) throw new ToolError("The graphics and the screens must all belong to the same church.");

  const warnings: string[] = [], replaces: string[] = [], outside: string[] = [];
  if (!(await moduleActive(db, org, "signage"))) warnings.push("This church doesn't have an active Signage plan, so screens won't show it.");
  for (const s of screens) {
    const now = localNow(s.tz);
    const lastDate = when.endDate;
    if (lastDate && (lastDate < now.date || (lastDate === now.date && when.end.slice(0, 5) <= now.time))) {
      throw new ToolError(`That has already ended in ${s.site ?? "the site"}'s local time (now ${now.date} ${now.time}).`);
    }
    warnings.push(...await moduleWarnings(db, s, "signage", when.days, when.start, when.end));
    const slots = must(
      await db.from("signage_slots").select("id,days,start_time,end_time,priority,start_date,end_date,label,playlist_id")
        .or(`screen_id.eq.${s.id}${s.group_id ? `,group_id.eq.${s.group_id}` : ""}`),
      "read existing slots",
    ) as any[];
    const ours = when.oneOff ? ONE_OFF_PRIORITY : RUN_PRIORITY;
    for (const x of slots) {
      const dayHit = x.days.some((d: number) => when.days.includes(d));
      const dateHit = (x.end_date == null || !when.startDate || x.end_date >= when.startDate) && (x.start_date == null || !when.endDate || x.start_date <= when.endDate);
      if (!dayHit || !dateHit || !(x.start_time < when.end && x.end_time > when.start)) continue;
      const pl = x.playlist_id ? (must(await db.from("signage_playlists").select("name").eq("id", x.playlist_id).maybeSingle(), "read playlists") as any) : null;
      const label = `"${x.label || pl?.name || "another slot"}" ${span(x.start_time, x.end_time)}`;
      if (x.priority >= ours) warnings.push(`"${s.name}" already has ${label} at equal or higher priority; that one may win.`);
      else replaces.push(`"${s.name}": ${label}`);
    }
    if (s.signage_default_playlist_id) {
      const d = must(await db.from("signage_playlists").select("name").eq("id", s.signage_default_playlist_id).maybeSingle(), "read default content") as any;
      outside.push(`"${s.name}" shows its default content "${d?.name ?? "?"}" when nothing is scheduled`);
    } else outside.push(`"${s.name}" goes blank when nothing is scheduled`);
  }

  const summary = [
    `Showing: ${names.join(", ")}${items && items.length > 1 ? " — rotating in that order, looping" : ""}`,
    `Screens: ${screens.map((s) => `${s.name} (${s.room ?? "no room"}, ${s.site ?? ""})`).join("; ")}`,
    `When: ${whenText(when)} (local time)`,
    `Outside those times: ${outside.join("; ")}.`,
    replaces.length ? `Takes over from, during that window only:\n  - ${replaces.join("\n  - ")}` : "",
    warnings.length ? `Warnings:\n  - ${[...new Set(warnings)].join("\n  - ")}` : "",
  ].filter(Boolean).join("\n");
  if (upload) {
    const { upload: _u, confirm: _c, ...plan } = a;
    const files = Math.min(Math.max(Math.round(+upload.files || 1), 1), 20);
    const id = await createUploadRequest(db, {
      organization_id: org, module: "signage", title: text(upload.title, 120), plan: { ...plan, files }, summary: summary.replace(/ — to be uploaded on the next page/, ""),
    });
    return `NOTHING IS SCHEDULED YET. Give the user this link; on it they choose the file${files > 1 ? "s" : ""} and press "Upload & schedule", which is their confirmation:\n` +
      `${APP_URL}/upload?request=${id}\n\nWhat the page will schedule:\n${summary}\n\n` +
      `Tell the user the link works on their phone too. When they say it's done, call check_upload with upload_id ${id} to confirm the result.`;
  }
  if (a.confirm !== true) return `${PREVIEW_NOTE}\n\n${summary}\n\n${CONFIRM_NOTE}`;

  const rec = new Recorder(db, org, "schedule_signage");
  const label = text(a.label, 120) || (playlist ? playlist.name : items!.length === 1 ? items![0].title : `${items!.length} graphics`);
  if (!playlist) {
    const sites = new Set(screens.map((s) => s.site_id));
    [playlist] = await rec.insert("signage_playlists", {
      organization_id: org, site_id: sites.size === 1 ? [...sites][0] : null, name: `Scheduled: ${label}`.slice(0, 120), items, source: "mcp",
    }, "create the playlist");
  }
  const made = await rec.insert("signage_slots", screens.map((s) => ({
    organization_id: org, screen_id: s.id, playlist_id: playlist.id, days: when.days, start_time: when.start, end_time: when.end,
    priority: when.oneOff ? ONE_OFF_PRIORITY : RUN_PRIORITY, start_date: when.startDate ?? localNow(s.tz).date, end_date: when.endDate,
    label, source: "mcp",
  })), "schedule it");
  const act = await rec.commit(`Signage: ${label} on ${screens.map((s) => s.name).join(", ")}, ${whenText(when)}`);
  return `Scheduled.\n\n${summary}\n\n${made.map((r) => `${screens.find((s) => s.id === r.screen_id)?.name}: slot_id ${r.id}`).join("\n")}` +
    `\n\nScreens pick up changes within a minute or two.${activityLine(act)}`;
}

async function listSignagePlaylists({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const rows = must(await db.from("signage_playlists").select("id,name,items,source").eq("organization_id", org).order("name"), "read signage playlists") as any[];
  if (!rows.length) return "No signage playlists yet.";
  return rows.map((p) => `- ${p.name} (${(p.items ?? []).length} items${p.source === "mcp" ? ", made by an assistant" : ""})  playlist_id: ${p.id}`).join("\n");
}

async function listSignageSchedule({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  let q = db.from("signage_slots").select("id,screen_id,group_id,playlist_id,days,start_time,end_time,start_date,end_date,label,priority,source").eq("organization_id", org);
  if (a.screen_id) q = q.eq("screen_id", needUuid(a.screen_id, "screen_id"));
  const slots = must(await q, "read the signage schedule") as any[];
  const today = new Date().toISOString().slice(0, 10);
  const live = slots.filter((s) => !s.end_date || s.end_date >= addDays(today, -1));
  if (!live.length) return "No signage slots.";
  const scIds = [...new Set(live.map((s) => s.screen_id).filter(Boolean))];
  const plIds = [...new Set(live.map((s) => s.playlist_id))];
  const [screens, pls] = await Promise.all([
    scIds.length ? db.from("screens").select("id,name").in("id", scIds) : Promise.resolve({ data: [], error: null }),
    db.from("signage_playlists").select("id,name").in("id", plIds),
  ]);
  const S = must(screens as any, "read screens") as any[], P = must(pls, "read playlists") as any[];
  return live
    .sort((x, y) => (x.start_date ?? "").localeCompare(y.start_date ?? "") || x.start_time.localeCompare(y.start_time))
    .map((s) => {
      const where = S.find((x) => x.id === s.screen_id)?.name ?? "(screen group)";
      const what = s.label || P.find((p) => p.id === s.playlist_id)?.name || "?";
      const dates = s.start_date && s.start_date === s.end_date ? `on ${s.start_date}` : `${s.start_date ? `from ${s.start_date}` : "ongoing"}${s.end_date ? ` to ${s.end_date}` : ""}`;
      return `- ${what}: ${where}, ${dayList(s.days)}, ${span(s.start_time, s.end_time)}, ${dates}${s.source === "mcp" ? " [assistant]" : ""}  slot_id: ${s.id}`;
    }).join("\n");
}

async function cancelSignage({ db }: Ctx, a: any) {
  const id = needUuid(a.slot_id, "slot_id");
  const slot = must(await db.from("signage_slots").select("id,organization_id,screen_id,playlist_id,days,start_time,end_time,start_date,end_date,label,source").eq("id", id).maybeSingle(), "read that slot") as any;
  if (!slot) throw new ToolError("That slot wasn't found (or you don't have access).");
  const screen = slot.screen_id ? (must(await db.from("screens").select("name").eq("id", slot.screen_id).maybeSingle(), "read screen") as any) : null;
  const what = `"${slot.label ?? "slot"}" on ${screen?.name ?? "a screen group"}, ${dayList(slot.days)} ${span(slot.start_time, slot.end_time)}` +
    `${slot.start_date ? `, ${slot.start_date}${slot.end_date !== slot.start_date ? ` to ${slot.end_date ?? "no end"}` : ""}` : ""}`;
  if (slot.source !== "mcp" && a.include_regular !== true) {
    throw new ToolError(`That's a regular slot made in the dashboard (${what}). Only remove it if the user clearly asked; then pass include_regular=true.`);
  }
  if (a.confirm !== true) return `${PREVIEW_NOTE} This would remove ${what}.\n\n${CONFIRM_NOTE}`;
  const rec = new Recorder(db, slot.organization_id, "cancel_signage");
  await rec.remove("signage_slots", { id: slot.id }, "remove that slot");
  if (slot.playlist_id) {
    const others = await db.from("signage_slots").select("id", { count: "exact", head: true }).eq("playlist_id", slot.playlist_id);
    const pl = must(await db.from("signage_playlists").select("source").eq("id", slot.playlist_id).maybeSingle(), "read playlist") as any;
    if (!others.error && (others.count ?? 1) === 0 && pl?.source === "mcp") await rec.remove("signage_playlists", { id: slot.playlist_id }, "tidy up the playlist");
  }
  const act = await rec.commit(`Removed signage ${what}`);
  return `Removed ${what}.${activityLine(act)}`;
}

export const SIGNAGE_TOOLS: Tool[] = [
  {
    name: "schedule_signage",
    description:
      "Puts graphics on signage screens for a time window: one image, several images that rotate (each for N seconds), videos, or an existing signage playlist. " +
      "One day: give date. Weekly run: give days (e.g. \"weekdays\", [\"mon\",\"wed\"]) and optionally start_date/end_date. Times are the site's local time. " +
      "Outside the window the screen goes back to whatever else is scheduled, or its default content, or blank. " +
      "ALWAYS call without confirm first, show the preview to the user, then call again with confirm=true once they agree. " +
      "If the graphic is an image the user attached in chat, use upload (not items): the user uploads and confirms on a page in one step.",
    inputSchema: {
      type: "object",
      properties: {
        screen_ids: { type: "array", items: { type: "string" } },
        items: {
          type: "array",
          description: "Graphics in order: [{media_id, seconds?, hold?}]. Images rotate every `seconds` (default 10). A single image holds for the whole window automatically; hold:true makes any image stay up (items after it won't show).",
          items: { type: "object", properties: { media_id: { type: "string" }, seconds: { type: "integer" }, hold: { type: "boolean" } }, required: ["media_id"] },
        },
        playlist_id: { type: "string", description: "Instead of items: an existing signage playlist (list_signage_playlists)" },
        upload: {
          type: "object",
          description: "Instead of items, when the graphics are only on the user's device (e.g. attached in chat): {title, files?}. Returns a link where the user uploads them and confirms in one step.",
          properties: { title: { type: "string" }, files: { type: "integer", description: "How many files (rotate in the order chosen), default 1" } },
          required: ["title"],
        },
        seconds: { type: "integer", description: "Default seconds per image" },
        date: { type: "string", description: "YYYY-MM-DD for a single day" },
        days: { description: "Weekly: list of days or \"weekdays\"/\"weekends\"/\"every day\"" },
        start_date: { type: "string", description: "Weekly: first date (default today)" },
        end_date: { type: "string", description: "Weekly: last date (omit for no end)" },
        start: { type: "string", description: "HH:MM local, e.g. 09:00" },
        end: { type: "string", description: "HH:MM local, e.g. 18:00 (24:00 = end of day)" },
        label: { type: "string" },
        confirm: { type: "boolean" },
      },
      required: ["screen_ids", "start", "end"],
      additionalProperties: false,
    },
    run: scheduleSignage,
  },
  {
    name: "list_signage_playlists",
    description: "Lists a church's signage playlists.",
    inputSchema: { type: "object", properties: { organization_id: { type: "string" } }, required: ["organization_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: listSignagePlaylists,
  },
  {
    name: "list_signage_schedule",
    description: "Lists current and upcoming signage slots (regular and assistant-made) with slot_id, optionally for one screen.",
    inputSchema: { type: "object", properties: { organization_id: { type: "string" }, screen_id: { type: "string" } }, required: ["organization_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: listSignageSchedule,
  },
  {
    name: "cancel_signage",
    description:
      "Removes a signage slot (slot_id from list_signage_schedule). Assistant-made slots only, unless include_regular=true because the user clearly asked. " +
      "Preview first, then confirm=true after the user agrees.",
    inputSchema: {
      type: "object",
      properties: { slot_id: { type: "string" }, include_regular: { type: "boolean" }, confirm: { type: "boolean" } },
      required: ["slot_id"],
      additionalProperties: false,
    },
    run: cancelSignage,
  },
];
