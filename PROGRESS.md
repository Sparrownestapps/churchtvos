# Phase 1 progress (2026-10-13)

## Done
- Repo: copied tv-app, dashboard, brand from forward-tv (forward-tv untouched); local git commit made. Not yet pushed.
- Supabase (gqkefjngblgomuovaivj): `supabase/migrations/20261013000001_foundation.sql` applied and smoke-tested (register → pair → device_state). Applied via `supabase db query --linked`, so it is not in the CLI's migration history table.
- TV app `com.churchtvos.tv`: builds (debug + release, new signing key in tv-app/keystore, gitignored, BACK IT UP). Module switch (Kids / Signage / off) evaluated on the TV from server rules, per-church branding, portrait rotation (Oriented), signage looping player, new placeholder icon/banner. Verified pairing screen on the emulator against the live project.
- Dashboard: multi-church refactor (org switcher, create church, module-gated nav, Screens, Sites & Locations, People, Settings/branding, Kids + Signage pages, platform-admin entitlements editor). Builds; not run against live data.

## Needs Keith
1. Push to GitHub (needs credentials/approval).
2. `netlify login` approval, then create site, connect churchtvos.com (GoDaddy DNS), turn off Visitor access.
3. Sign up in the dashboard with keith@sparrownest.com (platform admin is pre-seeded), create Forward Church, grant entitlements (kind=internal).
4. Supabase Auth Site URL + redirect URLs -> https://app.churchtvos.com.
5. Decide the real icon/logo (current is placeholder; Fire TV caches the launcher icon from first install).
6. ~~Move Forward Church data~~ Decided 2026-10-13: no migration, Forward Church starts from scratch in the new dashboard. Re-pair TVs when ready.

## Known gaps
- YouTube slides and portrait rotation: video layer is behind the window, so YouTube will not rotate.
- Auto-launch is on by default (pref exists, no UI yet); make it opt-in before Appstore.
- No demo mode yet. Test TV (172.16.51.189) was unreachable from here.
- One stray unpaired test screen row from the emulator may remain in `screens`.

## Update (later 2026-10-13)
- Live: https://app.churchtvos.com (Netlify site churchtvos-app, team Sparrownest; GoDaddy CNAME app -> churchtvos-app.netlify.app).
- Keith signed up (platform admin); Forward Church org created with internal-plan entitlements (kids + signage, 50 TVs).
- Icon concept A chosen and built in. Branding v2 shipped: dark logo, per-module looks, full-screen splash (untested on a real TV).

## Update (2026-10-21): experimental NDI source
- Per-church flag `organizations.ndi_enabled` (platform admin only, audited), NDI items/slides in Kids playlists and Slides decks, `ndi` TV build flavor (version 1.6.0, code 7). Contract and build steps: NDI-CONTRACT.md. Untested on a real NDI feed; NDI licence for Android unconfirmed.

## Update (2026-10-21): PDF / PowerPoint / picture import (web dashboard)
- Import button on Decks, the deck editor, Playlists and the playlist editor. PDF pages are drawn in the browser (pdf.js 6.4.299, lazy chunk, worker bundled; fonts and cmaps copied to `dashboard/public/pdfjs/`) as 1920px JPEGs and become full-screen picture slides / Kids image items. .pptx (jszip 3.10.2, lazy chunk) becomes editable text slides with notes, picture slides, and optional video. PNG/JPG multi-select works too. No exact-look pptx render exists: the dialog tells users to export to PDF.
- Contract for the Apple agent: PPTX-IMPORT-CONTRACT.md. Code: `dashboard/src/importer/`. Tests: `npm test` in dashboard (vitest + jsdom).
- Not verified against live Supabase (no login in the build session): the upload + insert path reuses the Media page logic but was not run end to end.
