// Kids and Slides scheduling. Both modules have the same shape: content is scheduled into a ROOM (location), either once
// (schedules / deck_schedules, timestamps) or repeating (kids_series / deck_series: days + times + a rotation, with per-date exceptions).
import {
  CONFIRM_NOTE, DAYNAMES, PREVIEW_NOTE, Recorder, ToolError, activityLine, addDays, dayList, dow, isUuid, isoToLocal, loadRoom,
  localNow, moduleActive, moduleWarnings, must, needDate, needUuid, parseDays, parseWindow, span, text, zonedToIso,
  type Ctx, type Tool,
} from "./lib.ts";

type Cfg = {
  module: "kids" | "slides";
  label: string;          // "Kids" / "Slides"
  thing: string;          // "playlist" / "deck"
  contentTable: string;   // playlists / decks
  idsArg: string;         // playlist_ids / deck_ids
  oneOff: string;         // schedules / deck_schedules
  oneOffRef: string;      // playlist_id / deck_id
  series: string;         // kids_series / deck_series
  seriesRefs: string;     // playlist_ids / deck_ids
  exceptions: string;     // kids_series_exceptions / deck_series_exceptions
  swapAction: string;     // 'playlist' / 'deck'
  occurrences: string;    // kids_series_occurrences / deck_series_occurrences
};
const KIDS: Cfg = {
  module: "kids", label: "Kids", thing: "playlist", contentTable: "playlists", idsArg: "playlist_ids", oneOff: "schedules", oneOffRef: "playlist_id",
  series: "kids_series", seriesRefs: "playlist_ids", exceptions: "kids_series_exceptions", swapAction: "playlist", occurrences: "kids_series_occurrences",
};
const SLIDES: Cfg = {
  module: "slides", label: "Slides", thing: "deck", contentTable: "decks", idsArg: "deck_ids", oneOff: "deck_schedules", oneOffRef: "deck_id",
  series: "deck_series", seriesRefs: "deck_ids", exceptions: "deck_series_exceptions", swapAction: "deck", occurrences: "deck_series_occurrences",
};

const GUARD_MINUTES = 30;
/** Refuses changes that touch what a room shows now or within 30 minutes, unless during_service_ok. */
function serviceGuard(a: any, tz: string, date: string, start: string, end: string, what: string) {
  if (a.during_service_ok === true) return;
  const now = localNow(tz);
  if (date !== now.date) return;
  const soon = new Date(Date.parse(`2000-01-01T${now.time}:00Z`) + GUARD_MINUTES * 60000).toISOString().slice(11, 16);
  const nowT = now.time + ":00", soonT = (soon < now.time ? "23:59" : soon) + ":00";
  if (start < soonT && end > nowT) {
    throw new ToolError(`This ${what} affects what the room shows now or within ${GUARD_MINUTES} minutes (local time ${now.time}), possibly during a service. ` +
      `Only go ahead if the user clearly wants that; then pass during_service_ok=true.`);
  }
}

async function contentNames(ctx: Ctx, cfg: Cfg, ids: string[], org: string): Promise<Map<string, string>> {
  const rows = must(await ctx.db.from(cfg.contentTable).select("id,name,organization_id").in("id", [...new Set(ids)]), `read ${cfg.thing}s`) as any[];
  for (const id of ids) {
    const r = rows.find((x) => x.id === id);
    if (!r || r.organization_id !== org) throw new ToolError(`${cfg.thing} ${id} wasn't found in this church. Use list_${cfg.module === "kids" ? "kids_playlists" : "decks"}.`);
  }
  return new Map(rows.map((r) => [r.id, r.name]));
}

async function schedule(cfg: Cfg, ctx: Ctx, a: any) {
  const { db } = ctx;
  const room = await loadRoom(db, needUuid(a.location_id, "location_id"));
  const ids = Array.isArray(a[cfg.idsArg]) ? a[cfg.idsArg] : [];
  if (!ids.length || ids.length > 52 || !ids.every(isUuid)) throw new ToolError(`${cfg.idsArg} must list 1 or more ${cfg.thing} ids (a rotation when repeating).`);
  const names = await contentNames(ctx, cfg, ids, room.organization_id);
  const { start, end } = parseWindow(a);
  const now = localNow(room.tz);

  const oneOff = !!a.date;
  let days: number[], startDate: string, endDate: string | null;
  if (oneOff) {
    startDate = endDate = needDate(a.date, "date");
    days = [dow(startDate)];
    if (ids.length > 1) throw new ToolError(`A one-day schedule takes one ${cfg.thing}. Use days (weekly) for a rotation.`);
    if (startDate < now.date || (startDate === now.date && end.slice(0, 5) <= now.time)) throw new ToolError(`That time has already passed (local now ${now.date} ${now.time}).`);
  } else {
    if (a.days === undefined) throw new ToolError("Give date (one day) or days (weekly, e.g. [\"sun\"]).");
    days = parseDays(a.days);
    startDate = a.start_date ? needDate(a.start_date, "start_date") : now.date;
    endDate = a.end_date ? needDate(a.end_date, "end_date") : null;
    if (endDate && endDate < startDate) throw new ToolError("end_date is before start_date.");
  }
  serviceGuard(a, room.tz, days.includes(dow(now.date)) && startDate <= now.date && (!endDate || endDate >= now.date) ? now.date : "", start, end, "schedule");

  const warnings: string[] = [];
  if (!(await moduleActive(db, room.organization_id, cfg.module))) warnings.push(`This church doesn't have an active ${cfg.label} plan.`);
  if (!room.screens.length) warnings.push(`There are no screens in ${room.name} yet, so nothing will show until one is paired there.`);
  for (const s of room.screens) warnings.push(...await moduleWarnings(db, s, cfg.module, days, start, end));

  // Overlaps in the next 8 weeks (or the one day).
  const from = zonedToIso(startDate, "00:00:00", room.tz);
  const toDate = oneOff ? startDate : (endDate && endDate < addDays(startDate, 56) ? endDate : addDays(startDate, 56));
  const to = zonedToIso(addDays(toDate, 1), "00:00:00", room.tz);
  const [ones, occ] = await Promise.all([
    db.from(cfg.oneOff).select(`id,starts_at,ends_at,${cfg.oneOffRef}`).eq("location_id", room.id).lt("starts_at", to).or(`ends_at.is.null,ends_at.gt.${from}`),
    db.rpc(cfg.occurrences, { p_org: room.organization_id, p_from: from, p_to: to, p_location: room.id }),
  ]);
  const clashes: string[] = [];
  const hits = (d: string, s: string, e: string) => days.includes(dow(d)) && d >= startDate && (!endDate || d <= endDate) && s < end && e > start;
  for (const o of must(ones, "read the room's schedule") as any[]) {
    const s = isoToLocal(o.starts_at, room.tz), e = o.ends_at ? isoToLocal(o.ends_at, room.tz) : { date: s.date, time: "23:59" };
    if (hits(s.date, s.time + ":00", e.date === s.date ? e.time + ":00" : "23:59:59")) clashes.push(`one-off on ${s.date} ${s.time}–${e.time} (schedule_id ${o.id})`);
  }
  for (const o of (must(occ, "read the room's repeating schedules") as any[]).slice(0, 200)) {
    const s = isoToLocal(o.starts_at, room.tz), e = isoToLocal(o.ends_at, room.tz);
    if (hits(s.date, s.time + ":00", e.time + ":00")) clashes.push(`repeating schedule on ${s.date} ${s.time}–${e.time} (series_id ${o.series_id})`);
  }
  if (clashes.length) {
    warnings.push(`Overlaps with existing ${cfg.label} schedules in ${room.name}${oneOff ? " (a one-off replaces a repeating one for that time)" : ""}:\n    · ${[...new Set(clashes)].slice(0, 12).join("\n    · ")}`);
  }

  const rotation = ids.map((id: string) => `"${names.get(id)}"`).join(" → ");
  const when = oneOff
    ? `${DAYNAMES[days[0]]} ${startDate}, ${span(start, end)}`
    : `${dayList(days)}, ${span(start, end)}, from ${startDate}${endDate ? ` through ${endDate}` : ", no end date"}`;
  const summary = [
    `${cfg.label}: ${rotation}${ids.length > 1 ? ` (a different one each time, ${a.on_end === "stop" ? "stopping after the last" : "then starting over"})` : ""}`,
    `Room: ${room.name} (${room.site}) — screens: ${room.screens.map((s) => s.name).join(", ") || "none"}`,
    `When: ${when} (local time)`,
    warnings.length ? `Warnings:\n  - ${[...new Set(warnings)].join("\n  - ")}` : "",
  ].filter(Boolean).join("\n");
  if (a.confirm !== true) return `${PREVIEW_NOTE}\n\n${summary}\n\n${CONFIRM_NOTE}`;

  const rec = new Recorder(db, room.organization_id, `schedule_${cfg.module}`);
  let made: any;
  if (oneOff) {
    [made] = await rec.insert(cfg.oneOff, {
      organization_id: room.organization_id, location_id: room.id, [cfg.oneOffRef]: ids[0],
      starts_at: zonedToIso(startDate, start, room.tz), ends_at: zonedToIso(startDate, end, room.tz),
    }, "add the schedule");
  } else {
    [made] = await rec.insert(cfg.series, {
      organization_id: room.organization_id, location_id: room.id, name: text(a.name, 120) || null, days, start_time: start, end_time: end,
      start_date: startDate, end_date: endDate, [cfg.seriesRefs]: ids, on_end: a.on_end === "stop" ? "stop" : "loop",
    }, "add the repeating schedule");
  }
  const act = await rec.commit(`${cfg.label}: ${rotation} in ${room.name}, ${when}`);
  return `Scheduled.\n\n${summary}\n\n${oneOff ? `schedule_id: ${made.id}` : `series_id: ${made.id}`}${activityLine(act)}`;
}

async function listSchedule(cfg: Cfg, { db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const daysAhead = Math.min(Math.max(+a.days_ahead || 14, 1), 120);
  const locs = must(await db.from("locations").select("id,name,site_id").eq("organization_id", org), "read rooms") as any[];
  const sites = must(await db.from("sites").select("id,timezone").eq("organization_id", org), "read sites") as any[];
  const tzOf = (loc: string) => sites.find((s) => s.id === locs.find((l) => l.id === loc)?.site_id)?.timezone ?? "America/Toronto";
  const roomOf = (loc: string) => locs.find((l) => l.id === loc)?.name ?? "?";
  const from = new Date(Date.now() - 6 * 3600000).toISOString(), to = new Date(Date.now() + daysAhead * 86400000).toISOString();
  let q1 = db.from(cfg.oneOff).select(`id,location_id,starts_at,ends_at,${cfg.oneOffRef}`).eq("organization_id", org).lt("starts_at", to).or(`ends_at.is.null,ends_at.gt.${from}`);
  let q2 = db.from(cfg.series).select(`id,location_id,name,days,start_time,end_time,start_date,end_date,${cfg.seriesRefs}`).eq("organization_id", org);
  if (a.location_id) { q1 = q1.eq("location_id", needUuid(a.location_id, "location_id")); q2 = q2.eq("location_id", a.location_id); }
  const [ones, series] = [must(await q1.order("starts_at"), "read schedules") as any[], must(await q2, "read repeating schedules") as any[]];
  const allIds = [...ones.map((o) => o[cfg.oneOffRef]), ...series.flatMap((s) => s[cfg.seriesRefs])];
  const names = allIds.length ? new Map((must(await db.from(cfg.contentTable).select("id,name").in("id", [...new Set(allIds)]), "read names") as any[]).map((r) => [r.id, r.name])) : new Map();
  const out: string[] = [];
  if (series.length) out.push("Repeating:");
  for (const s of series) {
    out.push(`- ${s.name ? `${s.name}: ` : ""}${s[cfg.seriesRefs].map((id: string) => names.get(id) ?? "?").join(" → ")} in ${roomOf(s.location_id)}, ${dayList(s.days)} ${span(s.start_time, s.end_time)}, from ${s.start_date}${s.end_date ? ` to ${s.end_date}` : ""}  series_id: ${s.id}`);
  }
  if (ones.length) out.push(`One-off (next ${daysAhead} days):`);
  for (const o of ones) {
    const tz = tzOf(o.location_id), s = isoToLocal(o.starts_at, tz), e = o.ends_at ? isoToLocal(o.ends_at, tz) : null;
    out.push(`- ${names.get(o[cfg.oneOffRef]) ?? "?"} in ${roomOf(o.location_id)}, ${DAYNAMES[dow(s.date)]} ${s.date} ${s.time}${e ? `–${e.time}` : " onward"}  schedule_id: ${o.id}`);
  }
  return out.length ? out.join("\n") : `No ${cfg.label} schedules.`;
}

async function cancel(cfg: Cfg, { db }: Ctx, a: any) {
  if (a.schedule_id) {
    const row = must(await db.from(cfg.oneOff).select(`*`).eq("id", needUuid(a.schedule_id, "schedule_id")).maybeSingle(), "read that schedule") as any;
    if (!row) throw new ToolError("That schedule wasn't found.");
    const room = await loadRoom(db, row.location_id);
    const s = isoToLocal(row.starts_at, room.tz), e = row.ends_at ? isoToLocal(row.ends_at, room.tz) : { date: s.date, time: "23:59" };
    serviceGuard(a, room.tz, s.date, s.time + ":00", (e.date === s.date ? e.time : "23:59") + ":00", "cancellation");
    const what = `the one-off ${cfg.label} schedule in ${room.name} on ${s.date} ${s.time}–${e.time}`;
    if (a.confirm !== true) return `${PREVIEW_NOTE} This would remove ${what}.\n\n${CONFIRM_NOTE}`;
    const rec = new Recorder(db, row.organization_id, `cancel_${cfg.module}_schedule`);
    await rec.remove(cfg.oneOff, { id: row.id }, "remove that schedule");
    return `Removed ${what}.${activityLine(await rec.commit(`Removed ${what}`))}`;
  }
  const sid = needUuid(a.series_id, "series_id or schedule_id");
  const row = must(await db.from(cfg.series).select("*").eq("id", sid).maybeSingle(), "read that repeating schedule") as any;
  if (!row) throw new ToolError("That repeating schedule wasn't found.");
  const room = await loadRoom(db, row.location_id);
  const now = localNow(room.tz);
  const what = `the repeating ${cfg.label} schedule in ${room.name} (${dayList(row.days)} ${span(row.start_time, row.end_time)})`;

  if (a.on_date) {
    // One date only: skip it, swap in other content, or restore it.
    const d = needDate(a.on_date, "on_date");
    if (!row.days.includes(dow(d)) || d < row.start_date || (row.end_date && d > row.end_date)) throw new ToolError(`${d} isn't one of that schedule's dates.`);
    serviceGuard(a, room.tz, d, row.start_time, row.end_time, "change");
    const action = a.action ?? "skip";
    const existing = must(await db.from(cfg.exceptions).select("*").eq("series_id", sid).eq("on_date", d).maybeSingle(), "read exceptions") as any;
    let desc: string;
    if (action === "restore") {
      if (!existing) return `${d} already runs as normal.`;
      desc = `put ${d} back to normal in ${what}`;
    } else if (action === "swap") {
      const swap = needUuid(a.swap_id, "swap_id");
      const names = await contentNames({ db } as Ctx, cfg, [swap], row.organization_id);
      desc = `show "${names.get(swap)}" instead on ${d} in ${what}`;
    } else if (action === "skip") desc = `skip ${d} in ${what}${cfg.module === "kids" ? " (the rotation waits a week)" : ""}`;
    else throw new ToolError("action must be skip, swap or restore.");
    if (a.confirm !== true) return `${PREVIEW_NOTE} This would ${desc}.\n\n${CONFIRM_NOTE}`;
    const rec = new Recorder(db, row.organization_id, `change_${cfg.module}_date`);
    if (existing) await rec.remove(cfg.exceptions, { series_id: sid, on_date: d }, "clear the date's earlier change");
    if (action !== "restore") {
      await rec.insert(cfg.exceptions, { series_id: sid, on_date: d, action: action === "swap" ? cfg.swapAction : "skip", [cfg.oneOffRef]: action === "swap" ? a.swap_id : null }, "change that date");
    }
    return `Done: ${desc}.${activityLine(await rec.commit(desc.charAt(0).toUpperCase() + desc.slice(1)))}`;
  }

  if (row.days.includes(dow(now.date)) && row.start_date <= now.date && (!row.end_date || row.end_date >= now.date)) serviceGuard(a, room.tz, now.date, row.start_time, row.end_time, "cancellation");
  if (a.confirm !== true) return `${PREVIEW_NOTE} This would delete ${what} entirely (every future date).\n\n${CONFIRM_NOTE}`;
  const rec = new Recorder(db, row.organization_id, `cancel_${cfg.module}_schedule`);
  const ex = must(await db.from(cfg.exceptions).select("*").eq("series_id", sid), "read exceptions") as any[];
  for (const e of ex) await rec.remove(cfg.exceptions, { series_id: sid, on_date: e.on_date }, "clear its date changes");
  await rec.remove(cfg.series, { id: sid }, "delete the repeating schedule");
  return `Deleted ${what}.${activityLine(await rec.commit(`Deleted ${what}`))}`;
}

function toolsFor(cfg: Cfg): Tool[] {
  const m = cfg.module;
  const guard = { during_service_ok: { type: "boolean", description: `Only when the user clearly wants to change what a room shows now or in the next ${GUARD_MINUTES} minutes` } };
  return [
    {
      name: `schedule_${m}`,
      description:
        `Schedules ${cfg.label} ${cfg.thing}s into a room (location_id from list_targets). One day: date + one ${cfg.thing}. Weekly: days (e.g. ["sun"]), start_date/end_date optional, ` +
        `and ${cfg.idsArg} can list several to rotate one per date. Times are the site's local time. ALWAYS preview first (no confirm), show the user, then confirm=true.`,
      inputSchema: {
        type: "object",
        properties: {
          location_id: { type: "string" }, [cfg.idsArg]: { type: "array", items: { type: "string" } },
          date: { type: "string" }, days: { description: "Weekly days" }, start_date: { type: "string" }, end_date: { type: "string" },
          start: { type: "string", description: "HH:MM local" }, end: { type: "string", description: "HH:MM local" },
          name: { type: "string", description: "Weekly: optional name, e.g. 'Sunday 9am'" },
          on_end: { type: "string", enum: ["loop", "stop"], description: "Weekly rotation: start over (default) or stop after the last" },
          ...guard, confirm: { type: "boolean" },
        },
        required: ["location_id", cfg.idsArg, "start", "end"],
        additionalProperties: false,
      },
      run: (ctx, a) => schedule(cfg, ctx, a),
    },
    {
      name: `list_${m}_schedule`,
      description: `Lists ${cfg.label} repeating schedules (series_id) and upcoming one-offs (schedule_id), optionally for one room.`,
      inputSchema: { type: "object", properties: { organization_id: { type: "string" }, location_id: { type: "string" }, days_ahead: { type: "integer" } }, required: ["organization_id"], additionalProperties: false },
      annotations: { readOnlyHint: true },
      run: (ctx, a) => listSchedule(cfg, ctx, a),
    },
    {
      name: `change_${m}_schedule`,
      description:
        `Changes or removes a ${cfg.label} schedule. schedule_id: removes that one-off. series_id alone: deletes the whole repeating schedule. ` +
        `series_id + on_date: changes just that date (action skip | swap with swap_id | restore). Preview first, then confirm=true.`,
      inputSchema: {
        type: "object",
        properties: {
          schedule_id: { type: "string" }, series_id: { type: "string" }, on_date: { type: "string" },
          action: { type: "string", enum: ["skip", "swap", "restore"] }, swap_id: { type: "string", description: `The ${cfg.thing} to show instead (swap)` },
          ...guard, confirm: { type: "boolean" },
        },
        additionalProperties: false,
      },
      run: (ctx, a) => cancel(cfg, ctx, a),
    },
  ];
}

export const SCHEDULE_TOOLS: Tool[] = [...toolsFor(KIDS), ...toolsFor(SLIDES)];
