# PDF / PowerPoint / picture import: contract

Written 2026-10-21. What the web dashboard's importer produces, so the Apple app can mirror it. Source of truth in code:
`dashboard/src/importer/` (`pptx.ts` reader, `pdf.ts` renderer, `importLogic.ts` rules and limits, `ImportDialog.tsx` flow,
`uploadMedia.ts` upload). Tests: `dashboard/src/importer/pptx.test.ts` (`npm test`). Keep this file and the code in step.

There is no server-side renderer. Everything happens on the client, then the results go through the normal media upload.
Nothing changes in the database: the importer only writes ordinary `media`, `media_folders`, `decks` and `playlists` rows.

## 1. Inputs
| Input | What it becomes |
|---|---|
| `.pdf` | One picture per page (exact look, no animation). |
| `.pptx` | **Editable**: text slides (decks) / pictures of the text (Kids). See section 4. |
| `.png .jpg .jpeg .webp .gif` (several at once) | One picture each, uploaded as is. Sorted by natural file name (Slide2 before Slide10). |
| `.ppt`, `.key` | Refused with a message (save as .pptx, or export to PDF). |

Exact look of a PowerPoint: tell the user to use PowerPoint File > Export > PDF (or PNG images) and import that. Do not try to render a pptx.

## 2. Limits
- Pages per import: **150**. More: the first 150 are listed, with a message to split the rest.
- PDF / pptx file size: **150 MB** (whole file is read into memory).
- Each uploaded file (rendered page, embedded picture, video, audio, picture file): **50 MB** (free Supabase plan limit). Larger ones fail for that page only (pictures) or are shown disabled (pptx media).
- Per-page errors never stop the import: successful pages are added, failures are listed.
- Permission: the Slides module (decks) or Kids module (playlists) enabled for the church and the member (`moduleOn`) and `canEditContent(module, site)`: editor role or above.

## 3. PDF rendering and media
- Page drawn on a canvas with the long edge **1920 px**: 16:9 gives 1920x1080, portrait 9:16 gives 1080x1920, 4:3 gives 1920x1440. White background filled first.
- Saved as **JPEG, quality 0.9**, content type `image/jpeg`.
- File name `"<file base name> <NN>.jpg"`, NN = the page number in the source, zero padded to at least 2 digits (width of the page count if larger): `Easter Sunday 03.jpg`. The media `title` is the file name without the extension.
- **Folder**: a new folder at the **top level of the module's library** (`media_folders`, module `slides` for decks, `kids` for playlists), named after the file without extension (user can edit it). Pictures-only import: the shared start of the file names, else `Imported pictures YYYY-MM-DD`. If the name is taken (case-insensitive) append ` (2)`, ` (3)`. Folder `site_id` and each media row's `site_id` = the deck/playlist's scope (null = all sites). The folder is created lazily on the first upload.
- Media row: `module`, `folder_id`, `kind` ('image'/'video'/'audio'), `storage_path` = `<org id>/<uuid>-<sanitized file name>` in the `media` bucket, `url` = public URL, `size_bytes`. Same row as the Media page upload.
- Uploaded with up to 3 pages in flight. Order of results always follows the reviewed list, not the upload order.

## 4. .pptx reading rules ("Editable")
Parsed with a zip reader plus an XML parser; no rendering.

**Slide order** is `ppt/presentation.xml` `p:sldIdLst`, resolved through `ppt/_rels/presentation.xml.rels` (file names like slide9.xml mean nothing). If the list is missing, fall back to numeric order of `slideN.xml`. Slide size `p:sldSz` gives the aspect ratio. `show="0"` marks a hidden slide (listed, **unticked by default**).

**Text extraction** (shape tree `p:spTree`, in document order, recursing into groups `p:grpSp` and the `Choice` branch of `mc:AlternateContent`):
- Placeholder `ph type` `title` / `ctrTitle` -> **title**. Any other placeholder (body, subTitle, object, no type) -> **body**, in tree order, placeholders before free text boxes.
- Footer, date, slide number, header placeholders (`ftr`, `dt`, `sldNum`, `hdr`) are skipped; so are `a:fld` slide-number and date fields inside text.
- Non-placeholder text boxes -> body, in tree order, separated from the previous block by one blank line. **Exception**: when the slide has no title placeholder, more than one text block exists, and the first text box is a single line of at most 80 characters, that line becomes the **title**.
- Tables (`graphicFrame` with `a:tbl`): one body line per row, cell texts joined with ` | `.
- Paragraph text = its runs, `a:br` -> newline, non-breaking spaces -> spaces. Each paragraph is one line. A paragraph with `a:pPr lvl >= 1` starts with `– ` (en dash and space). No other bullet characters are added. Empty paragraphs collapse to one blank line; none at the start or end. A title's line breaks become spaces.
- Nothing else is imported: fonts, colours, positions, shapes, charts, SmartArt, animations, transitions.

**Speaker notes**: `notesSlide` related from the slide; text of the `body` placeholder only (not slide image, slide number). Same paragraph rules.

**Slide kind**: `text` (title or body not empty) | `picture` (no text, but an `p:pic`, a picture-filled shape, or a background picture) | `empty` (nothing: shown disabled, not importable unless it carries importable media).
- `p:pic` that is the poster of a video/audio (`videoFile` / `audioFile` / `media` in `nvPr`) is not a picture.
- Importable picture formats: png, jpg, jpeg, gif, webp. EMF, WMF, TIFF, SVG etc.: slide row says the format is not supported; importing it fails for that slide with a message to export PNG pictures from PowerPoint.
- A picture slide uses the **largest drawn picture** (`a:ext cx*cy`) among supported ones, else the background picture.
- Optional (decks only, default off): for **text** slides also add each supported picture as an extra picture slide right after the text slide, named `<base> <NN> picture <k>.<ext>`.
- Picture file name: `<base> <NN>.<ext>` (NN = slide number, padded as above); the `title` is that name without extension.

**Embedded media**: every `video` / `audio` / `media` relationship of a slide (deduplicated by target). Listed with slide number, name and size. Importable when the format is video mp4 / m4v / mov / webm or audio mp3 / m4a / aac / wav / ogg and the size is at most 50 MB; ticked by default when importable. Online video links (external target, e.g. YouTube) are listed only, with a hint to use a Live stream / YouTube item. Videos become **video slides/items right after their slide**. Audio is uploaded into the library folder only (no slide kind plays it) and the row says so.

## 5. What is created
Common: the user chooses **time per page** and **where**: append to the end, insert after position N (0 = start), or a new deck/playlist (name defaults to the file/folder name, editable; scope chosen when started from a list page, inherited inside an editor).

### Slides deck (`decks.slides`, see `slidesTypes.ts`)
Ids use the usual `newSlideId` (`s_` + 5 chars, unique in the deck). All new slides have `seconds` from the chosen time (default **null = wait for Next**).
- Text slide: `{id, kind:'text', title, body, layout, seconds, notes?}`; `layout` = `title_body` (both), `title` (title only), `body` (body only). `notes` = speaker notes, only when not empty. No other fields: the theme decides the look.
- Picture slide (PDF page, picture file, pptx picture): `{id, kind:'media', media_id, url, media_kind:'image', fit:'contain', seconds, background:{type:'color', color:'#000000'}}` plus `notes` for pptx picture slides with notes. The black background makes pages that do not match the screen's shape letterbox on black instead of the theme colour.
- Video: `{id, kind:'media', media_id, url, media_kind:'video', fit:'contain', audio:true, background:{type:'color', color:'#000000'}}` (no `seconds`: advances when it ends).
- A new deck: `theme_id null`, `background null`, `loops false`. Appending inside the editor only changes the editor state; the user presses Save.

### Kids playlist (`playlists.items`, see `types.ts`)
Kids has no text slide, so for **pptx text slides** the importer draws a picture: canvas with the slide's aspect (long edge 1920), solid background = church `primary_color` (default `#1f3a5f`), white centred text with a soft shadow, title 9% of height (weight 800), body 5.5% (weight 500), wrapped in an 84% x 84% box and shrunk in 5% steps to fit; saved as JPEG 0.9 named `<base> <NN>.jpg`.
- Picture: `{type:'image', title, url, media_id, seconds}`; default `seconds` = **10** (null = wait for the remote).
- Video: `{type:'video', title, url, media_id}`.
- Speaker notes are **not kept** (no field). A new playlist: `{organization_id, site_id, name, items}`.

## 6. Flow (UI)
1. Import button: Decks page and deck editor (next to + Add slide); Playlists page and playlist editor. Hidden/disabled without permission.
2. Choose file(s) (drop or pick) -> read (PDF: page count and thumbnails drawn one at a time; pptx: parse, text preview card or picture thumbnail).
3. Review list: checkbox per page, up/down reorder, select all/none, media list for pptx, options (time, destination, folder name, new name).
4. Import: progress per page (waiting / working % / done / failed + reason), Stop button (what is done is kept and added). Then a summary. Files already uploaded stay in the library even if saving the deck or playlist fails (the summary says so).

## 7. Notes for the Apple app
- Rendering PDFs natively (PDFKit) at the same size rule, JPEG 0.9, is fine and gives the same result. A .pptx reader is just zip + XML as above; mirror the extraction rules exactly and keep the same test fixture ideas (shuffled file names, placeholders vs text boxes, notes, picture-only, media rels, hidden).
- Do not invent extra fields on slides or items.
