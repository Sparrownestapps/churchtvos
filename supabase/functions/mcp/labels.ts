// Human-readable titles and behaviour hints for every tool (MCP tool annotations), as directories and clients show them.
// read = only looks; write = adds or changes something that can be undone or removed; replace = can overwrite or remove
// existing content or schedules (still previewed first, and undo_change can reverse it).
type Kind = "read" | "write" | "replace";

const LABELS: Record<string, [string, Kind]> = {
  list_targets: ["List screens and rooms", "read"],
  list_media: ["List media library", "read"],
  upload_from_url: ["Upload a file from a link", "write"],
  create_upload_url: ["Create an upload link for a file", "write"],
  request_upload: ["Ask the user to upload a file", "write"],
  check_upload: ["Check an upload", "read"],
  upload_image: ["Upload a small image", "write"],
  schedule_signage: ["Schedule signage", "write"],
  list_signage_playlists: ["List signage playlists", "read"],
  list_signage_schedule: ["List signage schedule", "read"],
  cancel_signage: ["Cancel scheduled signage", "replace"],
  list_kids_playlists: ["List Kids playlists", "read"],
  get_kids_playlist: ["Show a Kids playlist", "read"],
  save_kids_playlist: ["Create or edit a Kids playlist", "replace"],
  list_decks: ["List slide decks", "read"],
  get_deck: ["Show a slide deck", "read"],
  save_deck: ["Create or edit a slide deck", "replace"],
  list_themes: ["List slide themes", "read"],
  search_songs: ["Search the song library", "read"],
  save_song: ["Add or edit a song", "replace"],
  get_song: ["Show a song", "read"],
  schedule_kids: ["Schedule Kids playlists", "write"],
  list_kids_schedule: ["List Kids schedule", "read"],
  change_kids_schedule: ["Change or remove a Kids schedule", "replace"],
  schedule_slides: ["Schedule slide decks", "write"],
  list_slides_schedule: ["List Slides schedule", "read"],
  change_slides_schedule: ["Change or remove a Slides schedule", "replace"],
  list_folders: ["List folders", "read"],
  organize_content: ["Move or archive playlists and decks", "write"],
  play_now: ["Play on a screen now", "write"],
  stop_playing: ["Stop playing on a screen", "write"],
  show_message: ["Show a message on a screen", "write"],
  list_screen_rules: ["List screen rules", "read"],
  set_screen_module: ["Set what a screen shows when", "write"],
  remove_screen_rule: ["Remove a screen rule", "replace"],
  list_activity: ["List assistant activity", "read"],
  undo_change: ["Undo an assistant change", "replace"],
};

/** The tool as listed to clients: top-level title plus annotations (title, readOnlyHint, destructiveHint, openWorldHint). */
export function labelled<T extends { name: string; annotations?: Record<string, unknown> }>(t: T) {
  const label = LABELS[t.name];
  if (!label) throw new Error(`No title/annotations for tool ${t.name} (add it to labels.ts)`);
  const [title, kind] = label;
  return {
    ...t,
    title,
    annotations: {
      ...t.annotations,
      title,
      readOnlyHint: kind === "read",
      ...(kind !== "read" && { destructiveHint: kind === "replace" }),
      openWorldHint: t.name === "upload_from_url",
    },
  };
}
