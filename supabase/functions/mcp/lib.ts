// Shared helpers for the MCP tools: validation, local time zones, screen lookups, and the change recorder (activity + undo).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type Db = SupabaseClient;
export type Ctx = { db: Db; userId: string };
export type Tool = {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations?: Record<string, unknown>;
  run: (ctx: Ctx, args: any) => Promise<string>;
};

export class ToolError extends Error {}

export const STALE_MINUTES = 10;
export const DAYNAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

export const isUuid = (s: unknown): s is string =>
  typeof s === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
export const isDate = (s: unknown): s is string =>
  typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(Date.parse(s + "T00:00:00Z"));
export const dow = (d: string) => new Date(d + "T00:00:00Z").getUTCDay(); // 0 = Sunday, same as the database
export const addDays = (d: string, n: number) => new Date(Date.parse(d + "T00:00:00Z") + n * 86400000).toISOString().slice(0, 10);
export const hm = (t: string) => t.slice(0, 5);
export const nice12 = (t: string) => {
  const [h, m] = t.split(":").map(Number);
  return `${((h + 11) % 12) + 1}${m ? ":" + String(m).padStart(2, "0") : ""}${h < 12 ? "am" : "pm"}`;
};
export const span = (start: string, end: string) => `${nice12(hm(start))}–${end >= "23:59" ? "end of day" : nice12(hm(end))}`;

export function need<T>(v: T | undefined | null, msg: string): T {
  if (v === undefined || v === null || v === "") throw new ToolError(msg);
  return v;
}
export const needUuid = (v: unknown, what: string) => {
  if (!isUuid(v)) throw new ToolError(`${what} is required (an id from an earlier list tool).`);
  return v;
};
export const needDate = (v: unknown, what: string) => {
  if (!isDate(v)) throw new ToolError(`${what} must be a date like 2026-10-30.`);
  return v;
};
export const text = (v: unknown, max = 200) => (typeof v === "string" ? v.trim().slice(0, max) : "");

/** "20:00" -> "20:00:00"; "24:00" -> end of day. */
export function parseTime(s: unknown, field: string): string {
  const m = typeof s === "string" ? /^(\d{1,2}):(\d{2})$/.exec(s.trim()) : null;
  if (!m) throw new ToolError(`${field} must look like 20:00 (24-hour HH:MM).`);
  const h = +m[1], min = +m[2];
  if (h === 24 && min === 0) return "23:59:59";
  if (h > 23 || min > 59) throw new ToolError(`${field} must look like 20:00 (24-hour HH:MM).`);
  return `${String(h).padStart(2, "0")}:${m[2]}:00`;
}
export function parseWindow(a: any): { start: string; end: string } {
  const start = parseTime(a.start, "start"), end = parseTime(a.end, "end");
  if (end <= start) throw new ToolError("end must be later than start on the same day. For an overnight run, use two schedules (e.g. 18:00–24:00 and 00:00–09:00).");
  return { start, end };
}

const DAYKEYS: Record<string, number> = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
/** [1,2,3] or ["mon","Tuesday"] or "weekdays" / "weekends" / "every day" -> sorted day numbers (0 = Sunday). */
export function parseDays(v: unknown): number[] {
  if (typeof v === "string") {
    const s = v.toLowerCase().trim();
    if (/^week ?days$/.test(s)) return [1, 2, 3, 4, 5];
    if (/^week ?ends$/.test(s)) return [0, 6];
    if (/^(every ?day|daily|all)$/.test(s)) return [0, 1, 2, 3, 4, 5, 6];
    v = s.split(/[\s,]+/);
  }
  if (!Array.isArray(v) || !v.length) throw new ToolError('days must be a list like ["mon","tue"] or [1,2], or "weekdays".');
  const out = new Set<number>();
  for (const d of v) {
    const n = typeof d === "number" ? d : DAYKEYS[String(d).toLowerCase().slice(0, 3)];
    if (!Number.isInteger(n) || n < 0 || n > 6) throw new ToolError(`Unknown day: ${d}. Use mon..sun or 0 (Sunday)..6.`);
    out.add(n);
  }
  return [...out].sort();
}
export const dayList = (days: number[]) =>
  days.length === 7 ? "every day" : days.join() === "1,2,3,4,5" ? "Monday–Friday" : days.join() === "0,6" ? "weekends" : days.map((d) => DAYNAMES[d]).join(", ");

export function localNow(tz: string): { date: string; time: string } {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
      .formatToParts(new Date()).map((x) => [x.type, x.value]),
  );
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}
function tzOffsetMs(ms: number, tz: string): number {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" })
      .formatToParts(new Date(ms)).map((x) => [x.type, x.value]),
  );
  return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - ms;
}
/** Local wall time in a time zone -> ISO instant (for the timestamptz columns). */
export function zonedToIso(date: string, time: string, tz: string): string {
  const [y, mo, d] = date.split("-").map(Number);
  const [h, mi, s] = time.split(":").map(Number);
  const wall = Date.UTC(y, mo - 1, d, h, mi, s || 0);
  let t = wall - tzOffsetMs(wall, tz);
  t = wall - tzOffsetMs(t, tz); // second pass settles DST edges
  return new Date(t).toISOString();
}
/** ISO instant -> { date, time } in a time zone. */
export function isoToLocal(iso: string, tz: string): { date: string; time: string } {
  const ms = Date.parse(iso);
  const local = new Date(ms + tzOffsetMs(ms, tz)).toISOString();
  return { date: local.slice(0, 10), time: local.slice(11, 16) };
}

export function friendly(message: string, what: string): string {
  if (/row-level security|permission denied|violates.*policy/i.test(message)) {
    return `Your account isn't allowed to ${what}. A church owner or admin can change your role or applications in People.`;
  }
  if (/is used (in|by)/i.test(message)) return message; // the database's own "in use" messages are already readable
  return `Couldn't ${what}: ${message}`;
}
export function must<T>(r: { data: T | null; error: { message: string } | null }, what: string): T {
  if (r.error) throw new ToolError(friendly(r.error.message, what));
  return r.data as T;
}

/** Entitlement check: the church pays for (or trials) the module. */
export async function moduleActive(db: Db, org: string, module: string): Promise<boolean> {
  const rows = must(await db.from("entitlements").select("status").eq("organization_id", org).eq("module", module), "read the church's plan") as any[];
  return rows.some((e) => ["active", "trialing", "past_due"].includes(e.status));
}

export type ScreenInfo = {
  id: string; name: string; organization_id: string; location_id: string | null; group_id: string | null;
  default_module: string; last_seen_at: string | null; signage_default_playlist_id: string | null; app_version: string | null;
  room: string | null; site_id: string | null; site: string | null; tz: string;
};
const SCREEN_COLS = "id,name,organization_id,location_id,group_id,default_module,last_seen_at,signage_default_playlist_id,app_version";

async function decorate(db: Db, screens: any[]): Promise<ScreenInfo[]> {
  const locIds = [...new Set(screens.map((s) => s.location_id).filter(Boolean))];
  const locs = locIds.length ? (must(await db.from("locations").select("id,name,site_id").in("id", locIds), "read rooms") as any[]) : [];
  const siteIds = [...new Set(locs.map((l) => l.site_id))];
  const sites = siteIds.length ? (must(await db.from("sites").select("id,name,timezone").in("id", siteIds), "read sites") as any[]) : [];
  return screens.map((s) => {
    const loc = locs.find((l) => l.id === s.location_id);
    const site = sites.find((x) => x.id === loc?.site_id);
    return { ...s, name: s.name ?? "Unnamed screen", room: loc?.name ?? null, site_id: site?.id ?? null, site: site?.name ?? null, tz: site?.timezone ?? "America/Toronto" };
  });
}
export async function loadScreens(db: Db, ids: string[]): Promise<ScreenInfo[]> {
  if (!ids.length || !ids.every(isUuid)) throw new ToolError("screen_ids must be a list of screen ids from list_targets.");
  const rows = must(await db.from("screens").select(SCREEN_COLS).in("id", ids), "read those screens") as any[];
  if (rows.length !== new Set(ids).size) throw new ToolError("One or more screen ids weren't found (or you don't have access). Use list_targets for valid ids.");
  return decorate(db, rows);
}
export async function loadRoom(db: Db, locationId: string) {
  const loc = must(await db.from("locations").select("id,name,site_id,organization_id").eq("id", locationId).maybeSingle(), "read that room") as any;
  if (!loc) throw new ToolError("That room (location_id) wasn't found, or you don't have access. Use list_targets.");
  const site = must(await db.from("sites").select("id,name,timezone").eq("id", loc.site_id).maybeSingle(), "read the site") as any;
  const screens = await decorate(db, must(await db.from("screens").select(SCREEN_COLS).eq("location_id", locationId), "read the room's screens") as any[]);
  return {
    id: loc.id as string, name: loc.name as string, site_id: loc.site_id as string, organization_id: loc.organization_id as string,
    site: (site?.name ?? "") as string, tz: (site?.timezone ?? "America/Toronto") as string, screens,
  };
}

export const isOnline = (s: { last_seen_at: string | null }) => !!s.last_seen_at && Date.now() - Date.parse(s.last_seen_at) < STALE_MINUTES * 60000;

/**
 * Warnings when a screen will not be running `module` during the window on those days (its Screens schedule rules,
 * else its default module), plus an offline note.
 */
export async function moduleWarnings(db: Db, s: ScreenInfo, module: string, days: number[], start: string, end: string): Promise<string[]> {
  const out: string[] = [];
  if (!isOnline(s)) out.push(`"${s.name}" looks offline right now; it will pick changes up when it reconnects.`);
  const rules = must(
    await db.from("screen_schedules").select("module,days,start_time,end_time,priority,created_at")
      .or(`screen_id.eq.${s.id}${s.group_id ? `,group_id.eq.${s.group_id}` : ""}`),
    "read the screen's schedule",
  ) as any[];
  const bad = new Set<string>();
  for (const d of days) {
    const hits = rules.filter((r) => r.days.includes(d) && r.start_time < end && r.end_time > start)
      .sort((x, y) => y.priority - x.priority || (y.created_at > x.created_at ? 1 : -1));
    const covering = hits.find((r) => r.start_time <= start && r.end_time >= end);
    const mods = new Set<string>(hits.map((r) => r.module));
    if (!covering) mods.add(s.default_module);
    for (const m of mods) if (m !== module) bad.add(m);
  }
  if (bad.size) {
    const names = [...bad].map((m) => (m === "off" ? "off (blank)" : m)).join(" / ");
    out.push(`"${s.name}" is set to run ${names} for some or all of that time, not ${module}, so it won't show this then. ` +
      `Use set_screen_module (or the dashboard's Screens page) to have it run ${module} during that window.`);
  }
  if (module === "slides" && s.app_version && !versionGe(s.app_version, "1.4.0")) out.push(`"${s.name}" runs app ${s.app_version}; Slides needs 1.4.0 or later.`);
  return out;
}
export function versionGe(a: string, b: string) {
  const pa = a.split(/[.-]/).map((x) => parseInt(x) || 0), pb = b.split(".").map(Number);
  for (let i = 0; i < pb.length; i++) {
    if ((pa[i] ?? 0) > pb[i]) return true;
    if ((pa[i] ?? 0) < pb[i]) return false;
  }
  return true;
}

/** Dates (YYYY-MM-DD) from `from` through `to` that fall on `days`, capped. */
export function datesOn(days: number[], from: string, to: string, cap = 400): string[] {
  const out: string[] = [];
  for (let d = from; d <= to && out.length < cap; d = addDays(d, 1)) if (days.includes(dow(d))) out.push(d);
  return out;
}

export const PREVIEW_NOTE = "PREVIEW ONLY. Nothing has been changed yet.";
export const CONFIRM_NOTE = "Show this to the user. If they agree, call the same tool again with the same arguments plus confirm=true.";

// ───────────────────────── Change recorder (activity log + undo) ─────────────────────────
type Change = { table: string; op: "insert" | "update" | "delete"; key: Record<string, unknown>; row?: Record<string, unknown> };
const KEYS: Record<string, string[]> = { kids_series_exceptions: ["series_id", "on_date"], deck_series_exceptions: ["series_id", "on_date"] };
const keyOf = (table: string, row: any) => Object.fromEntries((KEYS[table] ?? ["id"]).map((k) => [k, row[k]]));
function whereKey(q: any, key: Record<string, unknown>) {
  for (const [k, v] of Object.entries(key)) q = q.eq(k, v);
  return q;
}

export class Recorder {
  changes: Change[] = [];
  private db: Db;
  private org: string;
  private tool: string;
  constructor(db: Db, org: string, tool: string) {
    this.db = db;
    this.org = org;
    this.tool = tool;
  }

  async insert(table: string, rows: Record<string, unknown> | Record<string, unknown>[], what: string): Promise<any[]> {
    const list = Array.isArray(rows) ? rows : [rows];
    const r = await this.db.from(table).insert(list).select("*");
    if (r.error) {
      await this.rollback();
      throw new ToolError(friendly(r.error.message, what));
    }
    for (const row of r.data as any[]) this.changes.push({ table, op: "insert", key: keyOf(table, row) });
    return r.data as any[];
  }
  async update(table: string, key: Record<string, unknown>, patch: Record<string, unknown>, what: string): Promise<any> {
    const before = must(await whereKey(this.db.from(table).select("*"), key).maybeSingle(), what) as any;
    if (!before) throw new ToolError(`Couldn't ${what}: not found.`);
    const r = await whereKey(this.db.from(table).update(patch), key).select("*");
    if (r.error || !(r.data as any[])?.length) {
      await this.rollback();
      throw new ToolError(r.error ? friendly(r.error.message, what) : `Your account isn't allowed to ${what}.`);
    }
    this.changes.push({ table, op: "update", key, row: pick(before, Object.keys(patch)) });
    return (r.data as any[])[0];
  }
  async remove(table: string, key: Record<string, unknown>, what: string): Promise<any> {
    const before = must(await whereKey(this.db.from(table).select("*"), key).maybeSingle(), what) as any;
    if (!before) throw new ToolError(`Couldn't ${what}: not found.`);
    const r = await whereKey(this.db.from(table).delete(), key).select("*");
    if (r.error || !(r.data as any[])?.length) {
      await this.rollback();
      throw new ToolError(r.error ? friendly(r.error.message, what) : `Your account isn't allowed to ${what}.`);
    }
    this.changes.push({ table, op: "delete", key, row: before });
    return before;
  }
  /** Best effort: reverse what this call already did after a later step failed. */
  async rollback() {
    await reverse(this.db, this.changes);
    this.changes = [];
  }
  /** Writes the activity entry; returns its id (for undo_change). */
  async commit(summary: string): Promise<number | null> {
    if (!this.changes.length) return null;
    const r = await this.db.from("mcp_activity").insert({ organization_id: this.org, tool: this.tool, summary, changes: this.changes }).select("id").single();
    return r.error ? null : (r.data as any).id;
  }
}
const pick = (o: any, keys: string[]) => Object.fromEntries(keys.map((k) => [k, o[k]]));

/** Undoes changes newest first. Returns a list of problems (empty = all reversed). */
export async function reverse(db: Db, changes: Change[]): Promise<string[]> {
  const problems: string[] = [];
  for (const c of [...changes].reverse()) {
    let r: any;
    if (c.op === "insert") r = await whereKey(db.from(c.table).delete(), c.key);
    else if (c.op === "delete") r = await db.from(c.table).insert(c.row!);
    else r = await whereKey(db.from(c.table).update(c.row!), c.key);
    if (r?.error) problems.push(`${c.table}: ${r.error.message}`);
  }
  return problems;
}

export const activityLine = (id: number | null) => (id ? `\n\nactivity_id: ${id} (undo_change can reverse this).` : "");
