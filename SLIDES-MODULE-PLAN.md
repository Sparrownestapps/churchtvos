# Plan: "Slides" module (presentations, song slides, backgrounds, feeds)

Written 2026-10-14. **Planning only, nothing is built.** Items marked **VERIFY** were not confirmed in research or need a decision before work starts. This module sits alongside Kids and Signage in the `modules` registry; it also reuses the live-feed plan in `NEXT-BUILD.md` (HLS stream slide and NDI slide).

## 1. What it is
A dedicated presentation module. A church builds **decks** of slides in the dashboard and plays them on screens:
- Slide kinds: **text** (title and body), **media** (static image or video), **song** (lyrics split into slides), **countdown**, **live feed** (HLS stream, later NDI), **blank/black**.
- **Backgrounds** on any slide, deck or theme: solid colour, gradient, **static image**, or **looping video** (muted), with a dimming overlay so text stays readable.
- **Themes**: reusable looks (fonts, colours, text position and size, outline/shadow, margins, logo placement, default background). Change the theme and every slide updates. This is what makes "simple song slides" fast.
- **Song library**: lyrics stored per church, split into slides automatically, arranged in order (verse, chorus, verse, chorus, bridge...).
- Works in landscape and portrait, in the church's branding, with the same cached/offline behaviour as the other modules.

How it differs from Kids: Kids plays a curriculum playlist. Slides is a designer plus song tool plus (later) a live-operated presentation. Over time Kids could use the same slide renderer, but do not merge them now.

## 2. Key design decisions (recommended)
1. **Native rendering, not pre-rendered images.** The TV draws slides itself in Compose from slide data (text, positions, background), so text is sharp, portrait works, and editing is instant. Risk: the dashboard preview (React) and the TV (Compose) must look the same.
   - Mitigation: a deliberately small layout system: percent-based boxes, text sized as a percent of screen height, a fixed auto-fit rule (shrink text until it fits the box, minimum size), fixed margins and safe area. Write the rules once in a short spec file and test both renderers against shared sample slides (golden screenshots).
2. **Backgrounds as layers.** Layer 1 background (colour/gradient/image/video), layer 2 optional dim overlay (0-80%), layer 3 text/media. Consecutive slides that share the same video background keep it playing (no restart or flash).
3. **Video backgrounds are played with ExoPlayer under the text.** Unlike YouTube this works with Compose text on top; use the TextureView path in portrait (already in place). Cache videos on the TV like other media; show a "downloading" status; fall back to the slide's colour if the file is missing.
4. **Songs are data, not files.** A song = title, authors, CCLI number, copyright line, sections (label + text), and an arrangement (ordered list of sections). Slide generation is a function of song + theme + "lines per slide", so changing the theme or line count regenerates them.
5. **Two ways to run a deck** (build the first, design for the second):
   - **Scheduled**: assign a deck to a location or screen (dated, like Kids schedules) and it runs with per-slide timing or remote-advance.
   - **Live operated**: a person advances slides from a phone or the TV remote (next, back, jump, blank). Needs a realtime channel (Supabase Realtime) and uses the existing **operator** role, which is read-only today.
6. **Media library**: Slides gets its own library and folders (already supported per module: add the `slides` module id and it works).
7. **Billing**: a separate module entitlement like Kids and Signage.

## 3. Data model (new migration)
- `modules`: insert `slides` (set `available = false` until the module is ready).
- `slide_themes`: `id, organization_id, name, config jsonb` (fonts, colours, text box, size, outline/shadow, margins, default background, logo placement, lines-per-slide default).
- `decks`: `id, organization_id, site_id null, name, theme_id, slides jsonb` (ordered list; each slide has an id, a kind, content, optional background override, optional seconds, optional notes).
- `songs`: `id, organization_id, title, authors, ccli_number, copyright, sections jsonb, arrangement jsonb, source ('manual'|'paste'|'file'|'planning_center'|...), imported_at`. Private to the organization; never shared across churches.
- `song_usage`: `id, organization_id, song_id, deck_id null, screen_id null, used_at` (feeds a CCLI-style usage report CSV; see section 5).
- `deck_schedules` (dated, like Kids `schedules`): `location_id, deck_id, starts_at, ends_at` and later a "push now" override on `screens` (deck id + until).
- Row security the same pattern as other content: view needs module access and site scope; edit needs editor or above; operators can control playback later.
- `device_state`: add a `slides` block (assigned deck, its theme, songs expanded to slides) so the TV can work offline.

## 4. Backgrounds, in detail (your question)
Yes. Each slide resolves its background in this order: slide override, then deck setting, then theme default.
- Types: solid colour, two-colour gradient (angle), image (fit: cover/contain), video (loop, muted, cover).
- Dim overlay slider so lyrics stay readable on busy backgrounds; optional blur is a later nicety.
- Pick images and videos from the Slides media library (folders already supported).
- Guidance shown in the picker: 1080p H.264, up to about 20 Mbps, loops of 10-60 seconds, keep files modest because Fire TV sticks have little storage; warn above a size threshold.
- Portrait screens: a landscape background is cropped (cover) unless the church supplies a portrait version; the dashboard preview should show both.

## 5. Importing songs from CCLI and MultiTracks (research)
Neither offers an open developer API today, so plan for several routes and rank them.

**CCLI SongSelect**
- CCLI's [SongSelect Partner API documentation](https://documenter.getpostman.com/view/604633/TzseGkmA) states the partner program is retired and not taking new partners. It is undated, so confirm with CCLI. A [FreeShow GitHub discussion](https://github.com/ChurchApps/FreeShow/issues/572) says CCLI told developers there are no plans to replace the API and that ProPresenter has a special arrangement. One comment recalled about US$1,200 a year for access (unverified).
- Planning Center and Elvanto integrate by having the user sign in to SongSelect and approve the link ([Planning Center](https://help.planningcenter.com/en/139448-songselect--by-ccli-integration.html), [Elvanto](https://help.elvanto.com/hc/en-us/articles/7607943730199-How-to-set-up-the-SongSelect-by-CCLI-Integration)). That is partner-level access we do not have. Do not automate a user's SongSelect login or scrape SongSelect; it likely breaks their terms (**VERIFY** in SongSelect's terms).
- **Practical route:** import the lyric files a licensed user downloads from SongSelect (formats include a CCLI `.usr` lyric file, ChordPro and plain text; **VERIFY** the current download formats). Build a bulk uploader that parses these files, reads the CCLI song number, title, authors and copyright line, and splits sections by their labels. This needs no CCLI permission because the church supplies its own downloads.
- **Also needed:** a "paste lyrics" importer (works for any song or source) that splits sections on blank lines and recognised labels (Verse 1, Chorus, Bridge...).
- **Reporting:** churches must report CCLI usage. Store the CCLI number and log plays (`song_usage`), with a CSV export a church can use for its report. **VERIFY** CCLI's reporting requirements, and the licence needed for projecting lyrics versus streaming them (this is the church's licence, not ours).
- **Ask CCLI:** is the partner program reopening, what does it cost, and may a cloud tool store lyrics a licensed church downloaded?

**MultiTracks**
- No public developer program found. Their documented lyric access is a partner integration: lyric import into ProPresenter 7.8+ (needs a Chart Pro seat; limited to 200 songs a year on annual plans or 16 a month on monthly) and a song-file integration with Planning Center. See [MultiTracks' ProPresenter import guide](https://helpcenter.multitracks.com/en/articles/5783763-how-to-propresenter-lyric-and-template-import) and [Planning Center's MultiTracks page](https://help.planningcenter.com/en/139447-multitracks-integrations.html).
- MultiTracks' [terms of use](https://www.multitracks.com/terms/accept.aspx) prohibit copying song lyrics and scraping. Do not scrape.
- A [MultiTracks MCP tool list](https://helpcenter.multitracks.com/en/articles/15589252-multitracks-mcp-tools-catalog-reference) exists (lyric phrase search, song sections with ChordPro). It is built for AI assistants acting on a user's own account, not a developer API, and its access terms are not described. It does show MultiTracks has the data in structured form.
- **Practical route:** none direct without a partnership. **Ask MultiTracks** about a partner or API arrangement for lyric import into a signage/presentation product. Until then, MultiTracks users bring lyrics in via the file/paste importers or Planning Center.

**Best indirect route: Planning Center**
- Many churches already keep songs in Planning Center Services, and PCO connects to SongSelect and MultiTracks. Phase 4 of `HANDOFF.md` already plans a Planning Center integration (each church connects its own account through Planning Center's official sign-in). A "Songs from Planning Center" import (title, authors, CCLI number, arrangements with lyrics and section order) would reach CCLI and MultiTracks users without our own deals. **VERIFY** that PCO's API exposes lyrics and section order for songs a church imported, and which MultiTracks tiers include lyrics (PCO lists lyrics for Chart Pro and RehearsalPack, not RehearsalMix).
- Service plans could also drive decks (the order of service), which is Phase 4+ work.

## 6. Build plan in phases
**Phase 0: decisions and permissions (no code)**
- Confirm the module name and the decisions in section 8.
- Contact CCLI and MultiTracks (questions above); read SongSelect's terms; check Planning Center's API for lyrics.
- Write the layout/auto-fit spec and a handful of sample slides (the renderer contract).

**Phase 1: deck foundation (size: large)**
- Migration: registry row (hidden), `slide_themes`, `decks`, `deck_schedules`, row security, `device_state` slides block.
- TV: `Module.SLIDES`, `SlidesModule`, `SlideRenderer` (text, media, countdown, blank), backgrounds (colour, gradient, image, looping video with dim), per-deck theme, scheduled play with per-slide seconds or remote advance, offline cache and orientation support.
- Dashboard: Slides nav group; deck list; deck editor (slide strip, editor, live landscape/portrait preview); theme editor; background picker; media library (Slides) with folders; assign a deck to a location/schedule.
- Compatibility: TVs without the module must ignore unknown content (see the tolerant-decoding item in `NEXT-BUILD.md`).
- Done when: a church builds a three-slide deck with a video background and a theme, schedules it on a room, and the TV plays it, offline included, in both orientations.

**Phase 2: songs (size: medium to large)**
- Tables: `songs`, `song_usage`. Song library page: add by paste or file upload.
- Importers: paste, plain text, ChordPro, CCLI `.usr` (bulk). Preview and fix section labels before saving.
- Slide generation: lines per slide, section labels on/off, arrangement editor, theme applied; "add song to deck".
- Usage logging and CCLI-style CSV export.
- Done when: pasting or uploading a song produces correct, readable slides in a chosen theme and background in under a minute.

**Phase 3: live feeds (size: medium, see `NEXT-BUILD.md`)**
- HLS stream slide first (works with BoxCast static links), then native NDI after the licence check and spike.

**Phase 4: live operation (size: medium)**
- Realtime session per screen: current slide index and state; TV subscribes; phone-friendly controller page (next, back, jump, blank, "start deck on this screen"); remote-control keys on the TV; operator role gets playback control without edit rights.

**Phase 5: integrations and extras**
- Planning Center songs and service-plan import; CCLI/MultiTracks direct import if partnerships exist; PowerPoint/Keynote/PDF import as image slides; shared template packs; translations/second-language lines; stage-display layouts for the Production module.

## 7. Risks and unknowns
- Preview parity between React and Compose (mitigated by the constrained layout system and golden screenshots).
- Video backgrounds on weak Fire TV sticks (decode load, storage, heat): test on a stick and a Cube, cap file sizes, show warnings.
- Song data is copyrighted: store lyrics per organization only, never shared or cached across churches, and make CCLI numbers and copyright lines travel with each song. Terms of CCLI/MultiTracks may limit what we can automate (VERIFY).
- Amazon review: an update with a new module needs a resubmission; the Slides module should ship hidden until ready.
- Scope creep: PowerPoint-style freeform design tools. Keep v1 to fixed layouts and themes.

## 8. Decisions needed before building
1. **Name:** "Slides" or "Presentations"? (Slides is shorter; the module id would be `slides`.)
2. **Playback model for v1:** scheduled decks (like Kids), live-operated from a phone (Phase 4), or both in v1?
3. **Scheduling:** dated schedules per location (Kids style), or weekly recurring slots (Signage style), or both?
4. **Song sources for v1:** paste plus file import only, or include Planning Center import in v1? Do you want to contact CCLI and MultiTracks yourself (they will likely respond faster to a church account holder)?
5. **Backgrounds:** are image and video backgrounds both required in v1 (recommended), with gradients as a bonus?
6. **Existing Kids "lyrics" items:** later, migrate them to song slides, or keep them separate?
7. **Pricing:** a separate module price, or bundled with Signage?
