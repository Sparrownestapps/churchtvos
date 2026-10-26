// Live control (play now / stop / on-screen message), which module a screen runs when (screen_schedules), and the activity log with undo.
import {
  CONFIRM_NOTE, PREVIEW_NOTE, Recorder, ToolError, activityLine, dayList, isOnline, loadScreens, must, needUuid, parseDays, parseWindow, reverse, span, text,
  type Ctx, type Tool,
} from "./lib.ts";

async function playNow({ db }: Ctx, a: any) {
  const [s] = await loadScreens(db, [needUuid(a.screen_id, "screen_id")]);
  const kind = a.deck_id ? "deck" : a.playlist_id ? "playlist" : null;
  if (!kind) throw new ToolError("Give deck_id (Slides) or playlist_id (Kids).");
  const ref = needUuid(kind === "deck" ? a.deck_id : a.playlist_id, kind === "deck" ? "deck_id" : "playlist_id");
  const row = must(await db.from(kind === "deck" ? "decks" : "playlists").select("name").eq("id", ref).maybeSingle(), "read it") as any;
  if (!row) throw new ToolError(`That ${kind} wasn't found.`);
  const minutes = Math.min(Math.max(Math.round(+a.minutes || 240), 5), 1440);
  const what = `"${row.name}" on ${s.name} (${s.room ?? "no room"}) right now, for up to ${minutes} minutes or until stopped`;
  if (a.confirm !== true) return `${PREVIEW_NOTE} This would interrupt whatever ${s.name} is showing and play ${what}.${isOnline(s) ? "" : " The screen looks offline."}\n\n${CONFIRM_NOTE}`;
  must(await db.rpc("send_screen_command", { p_screen_id: s.id, p_command: "start", p_payload: { kind, id: ref, minutes } }), "control that screen");
  return `Playing ${what}. Use stop_playing to return it to its schedule.`;
}
async function stopPlaying({ db }: Ctx, a: any) {
  const [s] = await loadScreens(db, [needUuid(a.screen_id, "screen_id")]);
  must(await db.rpc("send_screen_command", { p_screen_id: s.id, p_command: "stop", p_payload: {} }), "control that screen");
  return `${s.name} is back on its normal schedule.`;
}
async function showMessage({ db }: Ctx, a: any) {
  const [s] = await loadScreens(db, [needUuid(a.screen_id, "screen_id")]);
  const msg = text(a.text, 200);
  if (!msg) throw new ToolError("text is required (up to 200 characters).");
  const seconds = Math.min(Math.max(Math.round(+a.seconds || 30), 5), 300);
  if (a.confirm !== true) return `${PREVIEW_NOTE} This would show "${msg}" over ${s.name} for ${seconds} seconds.\n\n${CONFIRM_NOTE}`;
  must(await db.rpc("send_screen_command", { p_screen_id: s.id, p_command: "message", p_payload: { text: msg, seconds } }), "send a message to that screen");
  return `Showing "${msg}" on ${s.name} for ${seconds} seconds.`;
}

async function listScreenRules({ db }: Ctx, a: any) {
  const [s] = await loadScreens(db, [needUuid(a.screen_id, "screen_id")]);
  const rules = must(
    await db.from("screen_schedules").select("id,module,days,start_time,end_time,priority,screen_id,group_id").or(`screen_id.eq.${s.id}${s.group_id ? `,group_id.eq.${s.group_id}` : ""}`).order("priority"),
    "read the screen's rules",
  ) as any[];
  const lines = rules.map((r) => `- ${r.module} ${dayList(r.days)} ${span(r.start_time, r.end_time)} (priority ${r.priority}${r.group_id ? ", from its group" : ""})  rule_id: ${r.id}`);
  return `${s.name}: runs ${s.default_module} by default.${lines.length ? `\nRules (highest priority wins):\n${lines.join("\n")}` : " No time rules."}`;
}
async function setScreenModule({ db }: Ctx, a: any) {
  const screens = await loadScreens(db, [...new Set(Array.isArray(a.screen_ids) ? a.screen_ids : [])] as string[]);
  const module = a.module;
  if (!["kids", "signage", "slides", "off"].includes(module)) throw new ToolError("module must be kids, signage, slides or off.");
  const days = parseDays(a.days ?? "every day");
  const { start, end } = parseWindow(a);
  const what = `${screens.map((s) => s.name).join(", ")} run ${module === "off" ? "nothing (blank)" : module} ${dayList(days)} ${span(start, end)}, every week`;
  if (a.confirm !== true) return `${PREVIEW_NOTE} This adds a standing rule: ${what}. Other times keep their current rules/default.\n\n${CONFIRM_NOTE}`;
  const org = screens[0].organization_id;
  if (screens.some((s) => s.organization_id !== org)) throw new ToolError("All screens must belong to the same church.");
  const rec = new Recorder(db, org, "set_screen_module");
  const rows = await rec.insert("screen_schedules", screens.map((s) => ({ organization_id: org, screen_id: s.id, module, days, start_time: start, end_time: end, priority: 10 })),
    "change screen rules (owners and admins only)");
  return `Added: ${what}.\n${rows.map((r) => `rule_id: ${r.id}`).join("\n")}${activityLine(await rec.commit(`Screen rule: ${what}`))}`;
}
async function removeScreenRule({ db }: Ctx, a: any) {
  const id = needUuid(a.rule_id, "rule_id");
  const r = must(await db.from("screen_schedules").select("*").eq("id", id).maybeSingle(), "read that rule") as any;
  if (!r) throw new ToolError("That rule wasn't found.");
  const what = `the rule "${r.module} ${dayList(r.days)} ${span(r.start_time, r.end_time)}"`;
  if (a.confirm !== true) return `${PREVIEW_NOTE} This would remove ${what}.\n\n${CONFIRM_NOTE}`;
  const rec = new Recorder(db, r.organization_id, "remove_screen_rule");
  await rec.remove("screen_schedules", { id }, "remove that rule (owners and admins only)");
  return `Removed ${what}.${activityLine(await rec.commit(`Removed ${what}`))}`;
}

async function listActivity({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const rows = must(await db.from("mcp_activity").select("id,tool,summary,undone_at,created_at").eq("organization_id", org).order("created_at", { ascending: false }).limit(Math.min(+a.limit || 20, 100)), "read activity") as any[];
  return rows.length ? rows.map((r) => `- [${r.created_at.slice(0, 16).replace("T", " ")} UTC] ${r.summary}${r.undone_at ? " (UNDONE)" : ""}  activity_id: ${r.id}`).join("\n") : "No assistant activity yet.";
}
async function undoChange({ db }: Ctx, a: any) {
  const id = Math.round(+a.activity_id);
  if (!id) throw new ToolError("activity_id is required (from list_activity).");
  const r = must(await db.from("mcp_activity").select("*").eq("id", id).maybeSingle(), "read that activity") as any;
  if (!r) throw new ToolError("That activity wasn't found.");
  if (r.undone_at) throw new ToolError("That was already undone.");
  if (a.confirm !== true) return `${PREVIEW_NOTE} This would undo: ${r.summary} (${r.changes.length} change${r.changes.length === 1 ? "" : "s"}).\n\n${CONFIRM_NOTE}`;
  const problems = await reverse(db, r.changes);
  await db.from("mcp_activity").update({ undone_at: new Date().toISOString() }).eq("id", id);
  return problems.length ? `Partly undone: ${r.summary}. Couldn't reverse:\n- ${problems.join("\n- ")}` : `Undone: ${r.summary}.`;
}

export const CONTROL_TOOLS: Tool[] = [
  {
    name: "play_now",
    description: "Plays a Slides deck or a Kids playlist on one screen immediately, interrupting its schedule, for up to `minutes` (default 240) or until stop_playing. Preview first, then confirm=true.",
    inputSchema: { type: "object", properties: { screen_id: { type: "string" }, deck_id: { type: "string" }, playlist_id: { type: "string" }, minutes: { type: "integer" }, confirm: { type: "boolean" } }, required: ["screen_id"], additionalProperties: false },
    run: playNow,
  },
  {
    name: "stop_playing",
    description: "Ends a play_now on a screen so it goes back to its schedule.",
    inputSchema: { type: "object", properties: { screen_id: { type: "string" } }, required: ["screen_id"], additionalProperties: false },
    run: stopPlaying,
  },
  {
    name: "show_message",
    description: "Shows a short text message over a screen for a few seconds (e.g. a parent pickup notice). Preview first, then confirm=true.",
    inputSchema: { type: "object", properties: { screen_id: { type: "string" }, text: { type: "string" }, seconds: { type: "integer" }, confirm: { type: "boolean" } }, required: ["screen_id", "text"], additionalProperties: false },
    run: showMessage,
  },
  {
    name: "list_screen_rules",
    description: "Shows which module (kids, signage, slides, off) a screen runs by default and its weekly time rules.",
    inputSchema: { type: "object", properties: { screen_id: { type: "string" } }, required: ["screen_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: listScreenRules,
  },
  {
    name: "set_screen_module",
    description: "Adds a standing weekly rule that makes screens run a module (kids, signage, slides, or off) during a time window, e.g. Kids on Sundays 08:00–13:00. Owners/admins only. Preview first, then confirm=true.",
    inputSchema: {
      type: "object",
      properties: { screen_ids: { type: "array", items: { type: "string" } }, module: { type: "string", enum: ["kids", "signage", "slides", "off"] }, days: {}, start: { type: "string" }, end: { type: "string" }, confirm: { type: "boolean" } },
      required: ["screen_ids", "module", "start", "end"],
      additionalProperties: false,
    },
    run: setScreenModule,
  },
  {
    name: "remove_screen_rule",
    description: "Removes a screen time rule (rule_id from list_screen_rules). Preview first, then confirm=true.",
    inputSchema: { type: "object", properties: { rule_id: { type: "string" }, confirm: { type: "boolean" } }, required: ["rule_id"], additionalProperties: false },
    run: removeScreenRule,
  },
  {
    name: "list_activity",
    description: "Lists recent changes made through this assistant connection (yours; admins see everyone's), with activity_id for undo_change.",
    inputSchema: { type: "object", properties: { organization_id: { type: "string" }, limit: { type: "integer" } }, required: ["organization_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: listActivity,
  },
  {
    name: "undo_change",
    description: "Reverses one earlier assistant change (activity_id from list_activity or a tool result). Preview first, then confirm=true.",
    inputSchema: { type: "object", properties: { activity_id: { type: "integer" }, confirm: { type: "boolean" } }, required: ["activity_id"], additionalProperties: false },
    run: undoChange,
  },
];
