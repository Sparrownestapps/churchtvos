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
6. Move Forward Church data from the old project, re-pair TVs.

## Known gaps
- YouTube slides and portrait rotation: video layer is behind the window, so YouTube will not rotate.
- Auto-launch is on by default (pref exists, no UI yet); make it opt-in before Appstore.
- No demo mode yet. Test TV (172.16.51.189) was unreachable from here.
- One stray unpaired test screen row from the emulator may remain in `screens`.
