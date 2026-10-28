// The song library: save a song from pasted lyrics (or ready-made sections) and read one back.
// Pasted text goes through the same parsers as the dashboard's Songs > Import, so a song looks the same however it was added.
// What the TV shows comes from song_expand() in the database; expandSong() mirrors it for the preview here.
import { CONFIRM_NOTE, PREVIEW_NOTE, Recorder, ToolError, activityLine, must, needUuid, text, type Ctx, type Db, type Tool } from "./lib.ts";
import { expandSong, labelFromLine, parseChordPro, parsePlainText, type SongSection } from "../../../dashboard/src/songParsers.ts";

const CHORDPRO = /^\s*\{\s*(title|t|start_of_\w+|sov|soc)\b/im;

/**
 * Sections from pasted lyrics. A section pasted again word for word (a repeated chorus) is kept once and the paste order
 * becomes the arrangement, so the slides still follow the song as written.
 */
export function fromLyrics(raw: string) {
  const parsed = CHORDPRO.test(raw) ? parseChordPro(raw) : parsePlainText(raw);
  const sections: SongSection[] = [];
  const order: string[] = [];
  for (const s of parsed.sections) {
    const key = s.text.replace(/\s+/g, " ").trim().toLowerCase();
    const same = sections.find((x) => x.text.replace(/\s+/g, " ").trim().toLowerCase() === key && (x.label === s.label || /^Section \d+$/.test(s.label)));
    if (same) order.push(same.id);
    else {
      const id = `s${sections.length + 1}`;
      sections.push({ ...s, id });
      order.push(id);
    }
  }
  return { ...parsed, sections, arrangement: order.length === sections.length ? null : order };
}

function fromSections(list: unknown): SongSection[] {
  if (!Array.isArray(list) || !list.length || list.length > 60) throw new ToolError("sections must be a list of {label, text} (up to 60).");
  return list.map((s: any, i) => {
    const body = typeof s?.text === "string" ? s.text.replace(/\r\n?/g, "\n").trim().slice(0, 4000) : "";
    if (!body) throw new ToolError(`Section ${i + 1} has no text.`);
    return { id: `s${i + 1}`, label: text(s.label, 60) || `Section ${i + 1}`, text: body };
  });
}

/** Arrangement given as section labels ("Verse 1", "Chorus", ...) -> section ids. */
function arrangementIds(labels: unknown, sections: SongSection[]): string[] | null {
  if (!Array.isArray(labels) || !labels.length) return null;
  const norm = (l: string) => (labelFromLine(l) ?? l).trim().toLowerCase();
  const ids = labels.map((l) => {
    const want = norm(String(l));
    const s = sections.find((x) => x.label.toLowerCase() === want) ?? sections.find((x) => x.label.toLowerCase().startsWith(want));
    if (!s) throw new ToolError(`"${l}" isn't one of this song's sections: ${sections.map((x) => x.label).join(", ")}.`);
    return s.id;
  });
  return ids.length === sections.length && ids.every((id, i) => id === sections[i].id) ? null : ids;
}

const slidesPreview = (song: { sections: SongSection[]; arrangement: string[] | null; lines_per_slide: number }) => {
  const slides = expandSong(song);
  const order = (song.arrangement ?? song.sections.map((s) => s.id)).map((id) => song.sections.find((s) => s.id === id)?.label).filter(Boolean);
  return `Order: ${order.join(" → ")}\n${slides.length} slides:\n` +
    slides.map((s, i) => `${i + 1}. [${s.label}] ${s.text.replace(/\n/g, " / ")}`).join("\n");
};

/** Kids playlists and decks that show this song, so an edit can say what it affects. */
async function songUsers(db: Db, org: string, id: string): Promise<string[]> {
  const [p, d] = await Promise.all([
    db.from("playlists").select("name,items").eq("organization_id", org),
    db.from("decks").select("name,slides").eq("organization_id", org),
  ]);
  return [
    ...(must(p, "check playlists") as any[]).filter((x) => (x.items ?? []).some((i: any) => i?.song_id === id)).map((x) => `Kids playlist "${x.name}"`),
    ...(must(d, "check decks") as any[]).filter((x) => (x.slides ?? []).some((s: any) => s?.song_id === id)).map((x) => `deck "${x.name}"`),
  ];
}

async function saveSong({ db }: Ctx, a: any) {
  const editing = a.song_id ? needUuid(a.song_id, "song_id") : null;
  const existing = editing ? (must(await db.from("songs").select("*").eq("id", editing).maybeSingle(), "read that song") as any) : null;
  if (editing && !existing) throw new ToolError("That song wasn't found. Use search_songs.");
  const org = existing?.organization_id ?? needUuid(a.organization_id, "organization_id");

  let parsed: { title: string; authors: string; ccli_number: string; copyright: string; sections: SongSection[]; arrangement: string[] | null } | null = null;
  if (typeof a.lyrics === "string" && a.lyrics.trim()) {
    if (a.lyrics.length > 30000) throw new ToolError("Those lyrics are too long for one song.");
    parsed = fromLyrics(a.lyrics);
    if (!parsed.sections.length) throw new ToolError("No lyrics found in that text.");
  } else if (a.sections !== undefined) {
    parsed = { title: "", authors: "", ccli_number: "", copyright: "", sections: fromSections(a.sections), arrangement: null };
  }
  if (!existing && !parsed) throw new ToolError("Give the lyrics (pasted text) or sections.");

  const sections: SongSection[] = parsed?.sections ?? existing.sections;
  // New sections mean new ids, so an old arrangement can't be kept.
  let arrangement: string[] | null = parsed ? parsed.arrangement : existing.arrangement;
  if (a.arrangement !== undefined) arrangement = arrangementIds(a.arrangement, sections);
  const lps = a.lines_per_slide !== undefined ? Math.round(+a.lines_per_slide) : existing?.lines_per_slide ?? 0;
  if (!(lps >= 0 && lps <= 12)) throw new ToolError("lines_per_slide must be 0 (one slide per section) to 12.");
  const field = (k: "authors" | "ccli_number" | "copyright", max: number) =>
    a[k] !== undefined ? text(a[k], max) || null : parsed?.[k] || existing?.[k] || null;
  const row = {
    title: text(a.title, 200) || parsed?.title || existing?.title || "",
    authors: field("authors", 300),
    ccli_number: a.ccli_number !== undefined ? (/\d{3,9}/.exec(String(a.ccli_number))?.[0] ?? null) : field("ccli_number", 20),
    copyright: field("copyright", 400),
    sections, arrangement, lines_per_slide: lps,
  };
  if (!row.title) throw new ToolError("What's the song called? Give title.");
  const preview = `"${row.title}"${row.authors ? ` — ${row.authors}` : ""}${row.ccli_number ? ` (CCLI ${row.ccli_number})` : ""}\n` +
    `Sections: ${sections.map((s) => `${s.label} (${s.text.split("\n").length} lines)`).join(", ")}\n` + slidesPreview(row);

  if (!editing) {
    const same = must(await db.from("songs").select("id,title").eq("organization_id", org).ilike("title", row.title.replace(/[%_]/g, "")), "check the library") as any[];
    if (same.length && a.allow_duplicate !== true)
      throw new ToolError(`"${same[0].title}" is already in the library (song_id: ${same[0].id}). Pass that song_id to update it, or allow_duplicate=true to add a second copy.`);
    const rec = new Recorder(db, org, "create_song");
    const [made] = await rec.insert("songs", { organization_id: org, ...row, source: "mcp" }, "add the song");
    const act = await rec.commit(`Song "${row.title}" added`);
    return `Added to the song library  song_id: ${made.id}\n${preview}\n\n` +
      "Check the section breaks and order above with the user. To fix them, call save_song again with this song_id (lyrics, sections, arrangement or lines_per_slide). " +
      `To put it in a deck: save_deck with {kind:'song', song_id:'${made.id}', show_title:true}; for Kids, a {type:'lyrics', song_id} item.` +
      (row.ccli_number ? "" : " No CCLI number was found; add ccli_number if the church reports it.") + activityLine(act);
  }

  const users = await songUsers(db, org, editing);
  if (a.confirm !== true) {
    return `${PREVIEW_NOTE}${users.length ? ` This song is used in ${users.join(", ")}; they'll show the new version.` : ""}\n\n` +
      `Before:\n${slidesPreview(existing)}\n\nAfter:\n${preview}\n\n${CONFIRM_NOTE}`;
  }
  const rec = new Recorder(db, org, "update_song");
  await rec.update("songs", { id: editing }, row, "update the song");
  const act = await rec.commit(`Song "${row.title}" changed`);
  return `Saved.\n${preview}${activityLine(act)}`;
}

async function getSong({ db }: Ctx, a: any) {
  const s = must(await db.from("songs").select("*").eq("id", needUuid(a.song_id, "song_id")).maybeSingle(), "read that song") as any;
  if (!s) throw new ToolError("That song wasn't found. Use search_songs.");
  return `${s.title}${s.authors ? ` — ${s.authors}` : ""}${s.ccli_number ? ` (CCLI ${s.ccli_number})` : ""}  song_id: ${s.id}\n` +
    `Lines per slide: ${s.lines_per_slide || "whole section"}\n\n` +
    (s.sections ?? []).map((x: SongSection) => `[${x.label}]\n${x.text}`).join("\n\n") + `\n\n${slidesPreview(s)}`;
}

export const SONG_TOOLS: Tool[] = [
  {
    name: "save_song",
    description:
      "Adds a song to the church's song library from lyrics the user pastes, so it can go in a Slides deck (save_deck {kind:'song', song_id}) or a Kids playlist (lyrics item). " +
      "Pass the pasted text as `lyrics` exactly as given: labels like 'Verse 1', '[Chorus]', 'Bridge:' start sections, blank lines separate unlabelled ones, a chorus pasted again is kept once and repeated in the order, " +
      "and CCLI/copyright lines are picked up. Or pass `sections` [{label, text}] if you structured it yourself. " +
      "Optional: arrangement (section labels in sung order, repeats allowed), lines_per_slide (0 = one slide per section; 2 is typical for worship), title, authors, ccli_number, copyright. " +
      "Shows the resulting slides; check them with the user. With song_id it updates an existing song (preview first, then confirm=true). " +
      "Only add lyrics the user provides; don't write out copyrighted lyrics from memory.",
    inputSchema: {
      type: "object",
      properties: {
        organization_id: { type: "string", description: "Required when adding" }, song_id: { type: "string", description: "To update an existing song" },
        lyrics: { type: "string", description: "The pasted lyrics, as given" },
        sections: { type: "array", items: { type: "object", properties: { label: { type: "string" }, text: { type: "string" } } } },
        title: { type: "string" }, authors: { type: "string" }, ccli_number: { type: "string" }, copyright: { type: "string" },
        arrangement: { type: "array", items: { type: "string" }, description: "Section labels in the order sung, e.g. [\"Verse 1\",\"Chorus\",\"Verse 2\",\"Chorus\",\"Bridge\",\"Chorus\"]" },
        lines_per_slide: { type: "integer", minimum: 0, maximum: 12 },
        allow_duplicate: { type: "boolean" }, confirm: { type: "boolean" },
      },
      additionalProperties: false,
    },
    run: saveSong,
  },
  {
    name: "get_song",
    description: "Shows a library song's sections, lyrics and the slides it makes.",
    inputSchema: { type: "object", properties: { song_id: { type: "string" } }, required: ["song_id"], additionalProperties: false },
    annotations: { readOnlyHint: true },
    run: getSong,
  },
];
