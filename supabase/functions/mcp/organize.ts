// Folders and archiving for Kids playlists, Signage playlists and Slides decks (content_folders; see the 20261026000003 migration).
// What an assistant creates goes into the built-in "Made by assistant" folder unless it is told otherwise.
import { Recorder, ToolError, activityLine, isUuid, must, needUuid, text, type Ctx, type Db, type Tool } from "./lib.ts";

export type Mod = "kids" | "signage" | "slides";
export const TABLE: Record<Mod, string> = { kids: "playlists", signage: "signage_playlists", slides: "decks" };
const NOUN: Record<Mod, string> = { kids: "Kids playlist", signage: "Signage playlist", slides: "deck" };
const MODS = ["kids", "signage", "slides"];
const needMod = (m: unknown): Mod => {
  if (!MODS.includes(m as string)) throw new ToolError("module must be kids, signage or slides.");
  return m as Mod;
};

/** The church's "Made by assistant" folder for a module, created on first use. */
export async function assistantFolder(db: Db, org: string, module: Mod): Promise<string | null> {
  const found = await db.from("content_folders").select("id").eq("organization_id", org).eq("module", module).eq("system", "assistant").maybeSingle();
  if (found.data) return (found.data as any).id;
  const made = await db.from("content_folders").insert({ organization_id: org, module, name: "Made by assistant", system: "assistant" }).select("id").single();
  if (!made.error) return (made.data as any).id;
  // Someone already has a folder with that name, or can't create folders: just leave it at the top level.
  return null;
}

/** folder_id from the arguments (must be this church and module), else the assistant folder. */
export async function folderFor(db: Db, org: string, module: Mod, folderId: unknown): Promise<string | null> {
  if (folderId === null || folderId === "top") return null;
  if (!folderId) return assistantFolder(db, org, module);
  const f = must(await db.from("content_folders").select("id,organization_id,module").eq("id", needUuid(folderId, "folder_id")).maybeSingle(), "read that folder") as any;
  if (!f || f.organization_id !== org || f.module !== module) throw new ToolError("That folder isn't in this church's " + module + " library. Use list_folders.");
  return f.id;
}

/** id -> "Parent / Child" for a module's folders. */
export async function folderPaths(db: Db, org: string, module: Mod): Promise<Map<string, string>> {
  const rows = must(await db.from("content_folders").select("id,name,parent_id").eq("organization_id", org).eq("module", module), "read folders") as any[];
  const byId = new Map(rows.map((r) => [r.id, r]));
  const out = new Map<string, string>();
  for (const r of rows) {
    const names: string[] = [];
    for (let f = r, n = 0; f && n < 50; f = f.parent_id ? byId.get(f.parent_id) : undefined, n++) names.unshift(f.name);
    out.set(r.id, names.join(" / "));
  }
  return out;
}

/** Shared filtering for the list_* tools: hides archived (unless asked), optional folder and name filters, adds the folder path. */
export async function listContent(db: Db, module: Mod, a: any, cols: string): Promise<{ rows: any[]; path: (id: string | null) => string }> {
  const org = needUuid(a.organization_id, "organization_id");
  let q = db.from(TABLE[module]).select(`${cols},folder_id,archived_at,source`).eq("organization_id", org);
  if (a.include_archived !== true) q = q.is("archived_at", null);
  if (isUuid(a.folder_id)) q = q.eq("folder_id", a.folder_id);
  const s = text(a.query).replace(/[%_]/g, "");
  if (s) q = q.ilike("name", `%${s}%`);
  const rows = must(await q.order("name"), `read ${NOUN[module]}s`) as any[];
  const paths = await folderPaths(db, org, module);
  return { rows, path: (id) => (id && paths.get(id) ? `  [${paths.get(id)}]` : "") };
}
export const LIST_PROPS = {
  organization_id: { type: "string" },
  query: { type: "string", description: "Part of the name" },
  folder_id: { type: "string", description: "Only this folder (list_folders)" },
  include_archived: { type: "boolean" },
};

async function listFolders({ db }: Ctx, a: any) {
  const org = needUuid(a.organization_id, "organization_id");
  const module = needMod(a.module);
  const [paths, items] = await Promise.all([
    folderPaths(db, org, module),
    db.from(TABLE[module]).select("folder_id,archived_at").eq("organization_id", org),
  ]);
  const counts = new Map<string, number>();
  for (const r of must(items, "read contents") as any[]) if (!r.archived_at) counts.set(r.folder_id ?? "top", (counts.get(r.folder_id ?? "top") ?? 0) + 1);
  const lines = [...paths.entries()].sort((x, y) => x[1].localeCompare(y[1])).map(([id, p]) => `- ${p} (${counts.get(id) ?? 0})  folder_id: ${id}`);
  return `${NOUN[module]}s: ${counts.get("top") ?? 0} at the top level.${lines.length ? "\n" + lines.join("\n") : " No folders yet."}`;
}

async function organize({ db }: Ctx, a: any) {
  const module = needMod(a.module);
  const ids = [...new Set(Array.isArray(a.ids) ? a.ids : [])] as string[];
  if (!ids.length || !ids.every(isUuid)) throw new ToolError(`ids must list ${NOUN[module]} ids.`);
  const rows = must(await db.from(TABLE[module]).select("id,name,organization_id,folder_id,archived_at").in("id", ids), "read them") as any[];
  if (rows.length !== ids.length) throw new ToolError("Some ids weren't found (or you don't have access).");
  const org = rows[0].organization_id;
  if (rows.some((r) => r.organization_id !== org)) throw new ToolError("All items must belong to the same church.");
  const rec = new Recorder(db, org, "organize_content");
  const done: string[] = [];

  let target: string | null | undefined;
  const folderName = text(a.new_folder_name, 120);
  if (folderName) {
    const parent = a.parent_folder_id ? await folderFor(db, org, module, a.parent_folder_id) : null;
    const existing = must(await db.from("content_folders").select("id").eq("organization_id", org).eq("module", module).ilike("name", folderName.replace(/[%_]/g, "")), "read folders") as any[];
    if (existing.length === 1) target = existing[0].id;
    else [{ id: target }] = await rec.insert("content_folders", { organization_id: org, module, parent_id: parent, name: folderName }, "create the folder");
    done.push(`folder "${folderName}"`);
  } else if (a.folder_id !== undefined) {
    target = a.folder_id === null || a.folder_id === "top" ? null : await folderFor(db, org, module, a.folder_id);
  }
  if (target !== undefined) {
    for (const r of rows) if (r.folder_id !== target) await rec.update(TABLE[module], { id: r.id }, { folder_id: target }, "move it");
    done.push(`moved ${rows.length} to ${target ? "the folder" : "the top level"}`);
  }
  if (a.archive === true || a.archive === false) {
    if (a.archive) {
      // Only things nothing uses can be archived (archived items disappear from the pickers).
      const used = await inUse(db, module, org, ids);
      if (used.length) throw new ToolError(`Still in use, so not archived: ${used.map((id) => rows.find((r) => r.id === id)?.name).join(", ")}. Remove them from their schedules first.`);
    }
    for (const r of rows) if (!!r.archived_at !== a.archive) await rec.update(TABLE[module], { id: r.id }, { archived_at: a.archive ? new Date().toISOString() : null }, a.archive ? "archive it" : "restore it");
    done.push(a.archive ? "archived" : "restored");
  }
  if (!done.length) throw new ToolError("Say what to do: folder_id (or \"top\"), new_folder_name, and/or archive true/false.");
  const names = rows.map((r) => `"${r.name}"`).join(", ");
  const act = await rec.commit(`Organized ${names}: ${done.join(", ")}`);
  return `Done for ${names}: ${done.join(", ")}.${activityLine(act)}`;
}

async function inUse(db: Db, module: Mod, org: string, ids: string[]): Promise<string[]> {
  const used = new Set<string>();
  const today = new Date().toISOString().slice(0, 10), now = new Date().toISOString();
  if (module === "signage") {
    for (const s of must(await db.from("signage_slots").select("playlist_id,end_date").eq("organization_id", org).in("playlist_id", ids), "check use") as any[]) if (!s.end_date || s.end_date >= today) used.add(s.playlist_id);
    for (const s of must(await db.from("screens").select("signage_default_playlist_id").eq("organization_id", org).in("signage_default_playlist_id", ids), "check use") as any[]) used.add(s.signage_default_playlist_id);
  } else {
    const kids = module === "kids", ref = kids ? "playlist_id" : "deck_id";
    for (const o of must(await db.from(kids ? "schedules" : "deck_schedules").select(ref).eq("organization_id", org).in(ref, ids).or(`ends_at.is.null,ends_at.gt.${now}`), "check use") as any[]) used.add(o[ref]);
    for (const s of must(await db.from(kids ? "kids_series" : "deck_series").select(`${kids ? "playlist_ids" : "deck_ids"},end_date`).eq("organization_id", org), "check use") as any[]) {
      if (s.end_date && s.end_date < today) continue;
      for (const id of s[kids ? "playlist_ids" : "deck_ids"]) if (ids.includes(id)) used.add(id);
    }
  }
  return [...used];
}

export const ORGANIZE_TOOLS: Tool[] = [
  {
    name: "list_folders",
    description: "Lists the folders of Kids playlists, Signage playlists or Slides decks (with how many items each holds). \"Made by assistant\" is where things you create land by default.",
    inputSchema: { type: "object", properties: { organization_id: { type: "string" }, module: { type: "string", enum: MODS } }, required: ["organization_id", "module"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: listFolders,
  },
  {
    name: "organize_content",
    description:
      "Moves Kids playlists, Signage playlists or decks into a folder (folder_id, or \"top\" for the top level), into a new folder (new_folder_name, created if needed), " +
      "and/or archives them (archive=true hides them from lists and menus without deleting; only allowed when nothing schedules them) or restores them (archive=false). " +
      "Doesn't change what any screen shows, so no preview is needed; it can be undone with undo_change.",
    inputSchema: {
      type: "object",
      properties: {
        module: { type: "string", enum: MODS }, ids: { type: "array", items: { type: "string" } },
        folder_id: { type: "string" }, new_folder_name: { type: "string" }, parent_folder_id: { type: "string" }, archive: { type: "boolean" },
      },
      required: ["module", "ids"],
      additionalProperties: false,
    },
    run: organize,
  },
];
