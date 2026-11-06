# Next build: TV screen changes (Android 1.7.1, Vega 1.0.1, LG/Samsung)

Requested by Keith on 2026-11-05. App changes only: the server already sends everything needed, so no dashboard or database work.
Each kind of TV needs the new build installed (Android: store update plus reinstall on the sideloaded TCLs; Vega: rebuild and reinstall; LG/Samsung: next package).

## 1. Show the TV name on the Kids screen (and Slides)
- **Today:** the Kids home screen shows the site (small caps) and the room (large). The TV's own name is missing.
- **Change:** add the screen name as a third line under the room, smaller and muted, so it reads site, then room, then TV name.
  Hide the line when the TV has no name. The Slides home screen shares the same header, so give it the same line.
- **Data:** already in device state (`screen.name`), and already shown in Settings.
- **Where:** Android `tv-app/.../HomeScreen.kt` and `SlidesModule.kt` (pass `device.screen.name`); Vega and LG/Samsung
  `vega-app/src/ui/HomeScreens.tsx` plus the two call sites in `vega-app/src/App.tsx` (lines ~79 and ~133).
- **Check:** landscape and portrait, a long TV name (should shrink or truncate, never wrap into the playlist card).

## 2. Bigger church logo at the top
- **Today:** the logo box is 300 x 72 (dp), top-left, on the Kids home screen and the branded frames.
- **Change:** make it noticeably bigger, about 480 x 120 in landscape (portrait similar, kept within the screen width),
  still inside the TV-safe margins. Adjust the spacing below it so the playlist card doesn't get pushed off screen.
- **Where:** `OrgLogo` in Android `tv-app/.../HomeScreen.kt` and Vega/web `vega-app/src/ui/common.tsx`.
- **Check:** a wide logo, a tall/square logo, the name-only fallback (no logo set), and the pairing and splash screens
  still look right.

## 3. Slides: "Loop" option on video slides
Requested 2026-11-06.
- **Today:** a video slide plays once, then moves to the next slide. Only video *backgrounds* loop, and they're always muted.
- **Change:** add **Loop** to video slides. **Off by default**, which keeps today's behaviour. When it's on, the video repeats,
  with sound if audio is on, until someone presses Next.
- **Data:** `MediaSlide.loop?: boolean` (videos only; missing = false). Older TVs ignore the field and play once.
- **Dashboard:** a "Loop until Next" checkbox on video slides in the deck editor. Show "loops" on the slide in the slide list.
- **TV (Android, Vega, LG/Samsung):** when `loop` is true, set the player to repeat and don't advance on end (Android:
  `repeatMode = REPEAT_MODE_ONE` and skip the `STATE_ENDED -> next()` in `SlidesPlayer.kt`; Vega/web: the `loop` prop on `VideoView`).
- **Check:** a looping video with sound; Next and Previous still work; a looping video as the last slide of a deck that loops.

## 4. Slides: background audio for a deck
Requested 2026-11-06.
- **Change:** an optional music track for a whole deck that plays under the slides. Audio file from the media library (same as countdown audio).
- **Settings (deck editor):** track, volume, and **At the end of the track: Stop (default) / Loop**. Plus a fade-out of about 2 s when
  the deck ends or the TV leaves Slides.
- **Data (proposal):** `decks.audio jsonb` = `{ media_id, url, volume, loop: false }`, null = no music. One migration;
  include the audio in the TV's download list so it plays offline.
- **Rules to settle while building:**
  - Video slides with sound and countdowns with their own audio: duck (lower) the deck music, or pause it, while they play.
    Recommend **pause and resume**.
  - The track keeps playing across slide changes (doesn't restart on each slide).
  - "Audio off" from the remote mutes it too.
- **TV:** a second audio player in `SlidesPlayer` (Android) and the shared Slides player (Vega and LG/Samsung).
  Vega has no volume control, so the volume setting applies on Android and LG/Samsung only.
- **Check:** stop vs loop, offline playback, pause/resume around a video with sound and a countdown with audio, leaving the deck mid-track.

## 5. Phone app: more settings when pairing a TV
Requested 2026-11-06. iPhone app (`apple/ChurchTVRemote`, "Pair a TV" sheet in `App/Pairing/PairTVSheet.swift`).
- **Today:** the pair sheet asks for the code, location and name. Everything else is set afterwards on the screen's detail page.
- **Add to the pair sheet, all optional, with the current defaults pre-filled:**
  - **Orientation:** Landscape (default) / Portrait / Portrait (flipped).
  - **Default module:** the church's modules plus Off (default: what a new screen gets today).
  - **Group:** None (default) or one of the church's groups.
  - **Signage default playlist:** shown only when the default module is Signage. None or a signage playlist,
    sorted and searchable the same way as the dashboard's new playlist picker (site first, then folders).
  - Put these under an "More settings" section that's collapsed by default, so the quick pair stays one screen.
- **How:** `claim_screen` already returns the new screen's id. Right after it succeeds, save the chosen settings to that screen
  with the same update the screen detail page uses (`OperationsService`). No database change.
  If that second save fails, the TV is still paired: say "Paired, but some settings didn't save" and open the screen's detail page.
- **Same options in the dashboard:** add the same "More settings" to the web "Pair a TV" form (`dashboard/src/pages/ScreensPage.tsx`)
  and the phone-friendly pair page (`PairPage.tsx`), so all three ways of pairing match. Dashboard only, so it can go out before the TV build.
- **Release:** a new iPhone build through TestFlight / the App Store. TVs don't need updating for this item.

## 6. iPhone app: edit a screen
Requested 2026-11-06. The Mac app already edits screens (`ChurchTVMac/App/Native/ScreensSection.swift`); the iPhone app can't.
- Add **Edit** to each screen in the Screens tab (`ChurchTVRemote/App/ScreensView.swift`): name, room, orientation, default module,
  group, signage default playlist (only when the default is Signage), autoplay, and Unpair (with a confirm).
- Share one form with item 5's "More settings" when pairing, so pairing and editing match. Reuse the update the Mac app uses.
- Owners and admins edit; everyone else sees the details read-only.

## 7. Bug: iPhone "Today" schedule misses Signage
Found 2026-11-06 (screenshot: Cameron Hall (Maps) shows "Nothing scheduled today" though it has a daily 8:00-10:00 Maps slot).
- **Cause:** `SupabaseService.schedule(...)` in `ChurchTVCore` loads Kids and Slides one-offs and repeats plus module switches,
  but never `signage_slots`, and ignores a screen's default signage content.
- **Fix:** load `signage_slots` for today (weekly days, plus the dated start/end range) for each screen and its group, with playlist names;
  add an "Otherwise: <default content>" line when a screen has a signage default playlist; sort entries by start time.
- Same check for the Mac app if it uses the same function.

## 8. Folders in the iPhone and Mac apps
Requested 2026-11-06.
- Wherever the apps list Kids playlists, Signage playlists or Slides decks (Play now, scheduling, Create), group them by the website's
  folders (`content_folders`, `folder_id` on each), hide archived ones, and add search.
- Put "On this TV" and "Recently used" at the top, the same as the dashboard's new playlist picker (`dashboard/src/calendar/pickerGroups.ts`
  has the ordering rules to copy).

## 9. Make room vs TV scheduling clear (dashboard and apps)
Discussed 2026-11-06. Keep both models: **Kids and Slides are scheduled per room** (every TV in the room shows the same thing),
**Signage and module switches per TV or group**. The confusion is that the calendar lets you pick a TV and then schedule Kids for it,
which really schedules the whole room.
- When Kids or Slides is chosen, say so plainly: "This plays on every TV in Preschool (2 TVs)." When a single TV is selected,
  label it as its room.
- When Signage is chosen with a room selected, say it will add one slot for each TV in the room, or suggest a group.
- Help text: two TVs in one room that need different Kids content → make them two rooms.
- **Decided 2026-11-06 (Keith): keep both models.**

## 10. Bug: messages show landscape on portrait TVs (Android)
Found 2026-11-06.
- **Cause:** in `tv-app/.../MainActivity.kt`, `MessageOverlay(message)` is drawn after (outside) the `Oriented(...)` wrapper,
  so it never rotates. Vega and LG/Samsung already draw it inside the wrapper.
- **Fix:** move `MessageOverlay` inside `Oriented`. Check on a portrait and a flipped-portrait screen, with short and long messages.

## Install after building
- TCL TVs (172.16.51.242, .244, .76): reinstall over adb.
- VEGA stick (192.168.0.246): rebuild with `vega-app/tools/build.sh` and reinstall.
- Fire TV / Google Play: submit 1.7.1 as an update.

---

# Next build: Church TV OS 1.1.0

Written 2026-10-14. Version 1.0.0 (versionCode 1) is with Amazon for review (estimated approval by 2026-10-19). Everything here needs a new TV build, so the plan is to let 1.0.0 get approved, then ship these together as **1.1.0** (versionCode 2) through Amazon's update review. Fixed builds can be sideloaded to the test TV (172.16.51.193) in the meantime.

## 1. Fix: church logo never shows on the TV (bug)
- **Symptom:** the Kids home screen (and the full-screen splash) shows no logo, even though a logo is saved under Settings, Branding.
- **Cause:** `tv-app/app/build.gradle.kts` includes `io.coil-kt.coil3:coil-compose` but not a Coil network module, so Coil can't load `https://` images. Local cached files work, remote URLs fail silently.
- **Fix:** add `io.coil-kt.coil3:coil-network-okhttp` (same version as coil-compose), rebuild, and check the logo on the Kids home screen, the pairing screen (once paired) and the splash.
- **Also check:** the dark-background logo variant, per-module logo overrides, and an offline TV with a logo (the logo is not cached on disk today; consider caching it alongside media so it survives offline).

## 2. Portrait version for portrait-mounted TVs
Already in place: per-screen orientation (Landscape / Portrait / Portrait flipped) and the `Oriented` wrapper that turns the whole UI; video uses a TextureView when rotated.

To do:
- Proper stacked portrait layout for the Kids home screen (the current two-column layout is cramped when turned).
- Check pairing, settings, demo, countdown, lyrics, splash and signage loop in both portrait directions.
- YouTube slides cannot rotate (the video sits on a layer behind the window). Skip them on portrait screens or show a clear warning in the dashboard.
- Dashboard: say which media sizes suit portrait (1080x1920), warn when a portrait screen has landscape media or a YouTube item, and preview portrait.
- Test: set the test TV to Portrait in the dashboard and read screenshots; confirm on a physically turned TV when one is available.
- Open question: do we have a TV that can be physically turned for a real check?

## 3. Sign creator (Signage)
A simple "Sign" playlist item built in the dashboard:
- Background colour, title, optional subtext, duration (seconds).
- Rendered natively on the TV with the Church TV OS fonts, so it is sharp at any size, in landscape and portrait.
- Included extras: automatic text colour for contrast, alignment and size choices, optional church logo, quick colour picks from the church's primary/accent, and a live preview showing landscape and portrait.
- Item shape (proposal): `{"type":"sign","title":"...","subtext":"...","background":"#1B2A4A","seconds":10,"align":"center","logo":true}`.
- Starts as signs living inside playlists with a Duplicate button. Optional later: a saved library of signs to reuse (decision pending).
- **Compatibility risk:** TVs on 1.0.0 would fail to parse a playlist containing an unknown item type (the whole playlist is rejected). So in 1.1.0 make decoding tolerant of unknown types (skip them), and avoid using signs until TVs are on 1.1.0. Consider a minimum-app-version note in the dashboard.

## Decisions still needed
1. Signs: inside playlists only, or also a saved library?
2. Portrait: is there a TV that can be physically turned for testing?
3. Go-ahead to build all three together as 1.1.0 (logo fix first).

## Other items parked for later
- Branding extras: font choice, logo on the Kids countdown/lyrics screens, branded Signage screens, a different logo per module on dark backgrounds beyond the splash.
- Storage rules: a site-limited editor probably cannot upload files (storage policies check all-sites access). Tighten per site and per module.
- Auto-launch: Forward Kids TV and Church TV OS fight for the foreground when both are installed on a TV. Remove or disable the old app on TVs that move over.
- Demo mode: richer sample content, and a reviewer account (a test church with one screen) if Amazon asks for login details.
- Production module (green room, stage displays, run of show): one row in the `modules` table (set available) plus its dashboard pages and TV support.
- Vega OS: Amazon's newest Fire TV sticks cannot run the Android app. Revisit a Vega build (or a browser-based player) if those devices become common in churches. Meanwhile recommend Fire TV Stick 4K Max, Fire TV Cube or Google TV devices.
- Google Play listing (Android TV / Google TV) with the same APK, plus Roku as a separate app.
- Fire TV install guide for churches (supported devices, pairing, Menu button).
- Housekeeping: delete the stray unpaired test screens in the `screens` table; uninstall the debug "(dev)" build from the test TV; push local commits to GitHub; revoke old GitHub tokens.
- Planning Center (Phase 4) and Stripe billing (Phase 5) per HANDOFF.md.

---

# Feature plan: live video feeds (NDI, plus HLS/BoxCast) for Kids and Signage

Researched 2026-10-14. Goal: let a playlist in **either module** include a live video feed as a slide, in particular an NDI source (a camera, production switcher or computer on the church's network). This section is the build brief. Things marked **VERIFY** were not confirmed in research and must be settled before or during the build.

## Summary of options
| Route | Delay | Needs | Verdict |
|---|---|---|---|
| **A. Native NDI receive in the TV app** | Real-time (well under a second on a good network) | NDI Android SDK, native code, wired network for full-bandwidth NDI, NDI licence check | The real answer for lyrics, confidence and stage use. Biggest build. |
| **B. NDI converted to HLS by a gateway at the church** | About 3-10 seconds | A computer at the church running Nimble Streamer, FFmpeg with NDI, or OBS | Works with no NDI code in our app. Good for overflow and lobby screens. |
| **C. BoxCast live stream** | About 30-40 seconds on the normal viewer feed | BoxCast account; either a pasted static HLS link or the BoxCast API | Good for "watch the service" screens, not for real-time. |

Build order: **Phase 1 = the HLS stream slide** (covers routes B and C with no licence risk), **Phase 2 = native NDI** (route A), **Phase 3 = "BoxCast: now live" API integration**.

## Shared design: a "feed" slide type for Kids and Signage
Both modules already play slides through `PlayerScreen`. Add two new slide kinds that either module's playlist editor can insert:
- `{"type":"stream","title":"Sunday service","url":"https://.../playlist.m3u8","seconds":null,"audio":false,"fallback":"skip"}` (HLS URL, phase 1)
- `{"type":"ndi","title":"Main camera","source":"STUDIO-PC (Camera 1)","address":"192.168.1.50:5961","seconds":null,"audio":false,"fit":"contain","fallback":"skip"}` (NDI, phase 2)

Common fields:
- `seconds`: how long to show it; null = until the user presses next (Kids) or until the playlist loops past it (a sensible default of 30 for Signage, adjustable).
- `audio`: default off (signage rooms are usually silent).
- `fit`: contain (letterbox) or cover (fill and crop). Portrait screens: warn that landscape feeds will letterbox.
- `fallback` if the feed is unavailable: `skip` (move on), `hold` (show a "waiting for feed" card for N seconds, then skip), or `slide` (show a fallback sign/image chosen in the editor). Default: skip, so a dead feed never leaves a blank room.

### Compatibility (do this first, it blocks everything)
TVs on 1.0.0 cannot parse a playlist containing an unknown item type (the whole playlist is rejected). In 1.1.0 make the item decoder tolerant: unknown types are skipped, not fatal (`PlaylistItem` is a sealed interface in `tv-app/.../Model.kt`; use a default/fallback serializer or decode items individually). Do not put feed items in a playlist until TVs run 1.1.0 (consider showing a dashboard warning based on each screen's `app_version`).

## Phase 1: HLS stream slide (Kids and Signage)
**TV app**
1. Add `PlaylistItem.Stream` and `Slide.Stream(url, audio, seconds)` in `Model.kt`.
2. In `PlayerScreen.kt`, play it with the existing ExoPlayer (Media3 already includes HLS support; add `androidx.media3:media3-exoplayer-hls` at the same version as the other Media3 modules). Muted unless `audio` is true.
3. Live-stream behaviour: do not advance on "ended" for a live stream unless `seconds` is set; on playback error or no data for ~10 s, apply the fallback rule and retry in the background.
4. Never cache streams in `MediaCache`; exclude them from `mediaUrls`.
5. Rotation: ExoPlayer in portrait uses the TextureView path that already exists.
**Dashboard**
1. Add "Live stream" to the Kids playlist editor (`PlaylistsPage.tsx`) and Signage playlist editor (`SignagePlaylistsPage.tsx`), using the shared item types in `types.ts`.
2. Fields: title, HLS (.m3u8) URL, duration, audio on/off, fallback. Add a "Test link" button that checks the URL responds (HEAD/GET from the browser; note CORS may block it, so treat a failure as a hint, not an error).
3. Help text with a BoxCast example: BoxCast broadcast, Embed page, "Static M3U8" (note BoxCast says viewers on that link are not counted in their analytics).
**Done when:** a BoxCast static link and a test HLS stream (for example from OBS or Nimble) play in a Kids slide and a Signage slide on the test TV; a dead URL falls back correctly; the stream survives an hour on a Fire TV without leaking memory.

## Phase 2: native NDI receive (Kids and Signage)
### 2.0 Before any code
- **Licence check (blocking):** read the licence agreement at the root of the downloaded SDK and email NDI to confirm: (1) whether a commercial Android app running on TVs / fixed-purpose devices needs a commercial licence; (2) whether HX2/HX3 receive beyond ~5 minutes requires the Advanced SDK (one open-source Android project says yes; NDI's docs do not say); (3) what we may redistribute in the APK; (4) attribution wording. **VERIFY all four.**
- Known obligations from NDI's licensing page: link to ndi.video where NDI is used (in the app's About/Settings and on the website), show "NDI® is a registered trademark of Vizrt NDI AB", report the commercial app to NDI, do not put "NDI" in our product name without asking, ship only the files the SDK allows, build with an SDK version under 30 days old when releasing, and handle codec licensing (H.264/H.265) ourselves.
- Download the Android SDK from https://ndi.video/for-developers/ndi-sdk/ and keep the `arm64-v8a` and `armeabi-v7a` libraries (Fire TV sticks are ARM; skip x86 in release).

### 2.0a Licence finding (2026-10-15, read from the NDI SDK v6 Android installer's licence text)
- The SDK licence covers "Products" that run on general-purpose operating systems and computers. It **expressly excludes** products on fixed-purpose appliances and on **embedded devices using an embedded-type operating system, which it says includes Android** (and Linux, iOS and similar). For those exclusions the licence says you **must enter into a commercial licence agreement with NDI**.
- Church TV OS runs on Android-based Fire TV and Google TV devices, so it very likely falls under that exclusion. A commercial agreement with NDI is probably required, even for development. This is a reading of the text, not legal advice; NDI decides.
- Other terms that apply regardless: ship only files the SDK documentation says may be distributed; the bundled app must use the latest SDK version at release; end-user terms must pass NDI's restrictions through to customers (no reverse engineering, warranty and liability disclaimers, copyright notice); NDI trademark rules and notices; the SDK is confidential (do not share it or commit it to the repo; `vendor/` is git-ignored).
- **Action:** email NDI first and describe the product (Android TV app, free download, subscription on the web). Do not run the installer or start the spike until their answer is in. The installer itself asks the user to type "y" to accept the licence, which is Keith's decision, not ours.
- The installer is in `~/Downloads/Install_NDI_SDK_v6_Android.tar.gz`; a copy of the extracted (not run) script is in `vendor/ndi-installer/` (ignored by git).

### 2.1 Spike (1-2 days, test TV only)
- New Android Studio native module (NDK/CMake) with a thin JNI wrapper around the NDI receiver: find sources, connect, pull video frames, release.
- Create an `NsdManager` (`getSystemService(Context.NSD_SERVICE)`) and keep it alive for as long as any finder/receiver exists. NDI's docs require this on Android.
- Render frames to a `Surface` / `TextureView` from a native-owned decode thread; measure CPU, memory, frame rate and latency on the AFTTI43 (Fire OS 7) and on a Fire TV Stick 4K Max or Cube.
- Test three sources: NDI|HX (H.264), NDI|HX3, and full-bandwidth NDI over wired Ethernet and over Wi-Fi.
- **Go/no-go:** smooth 1080p30 with latency under about 300 ms on the test devices; otherwise fall back to routes B/C only.

### 2.2 TV app implementation
1. `PlaylistItem.Ndi` / `Slide.Ndi(source, address, audio, fit, seconds, fallback)` (see shared design).
2. `NdiSlide` composable hosting the video surface; join the source by exact name via discovery, or by `address` (IP/host:port) when set. Support both because many church networks block multicast discovery across VLANs.
3. Receiver lifecycle: create the receiver when the slide appears, destroy when it leaves; keep one receiver per screen at a time; survive screen-off/on and network loss with exponential-backoff reconnects (1 s up to 15 s).
4. Quality: request the lowest-latency receive mode and the lowest bandwidth the SDK allows when the screen is small; drop frames rather than build latency.
5. Audio: off by default; if on, route through `AudioTrack` with the SDK's audio frames; keep A/V sync simple (video-only is acceptable for v1).
6. Safety: wrap native calls so a crash in the library cannot take down the app loop; log connect/disconnect reasons (shown under Menu > Settings > Diagnostics).
7. Legal UI: Settings screen shows "NDI® is a registered trademark of Vizrt NDI AB" and ndi.video (as the licence requires).
8. Release build: ABI filters, keep the NDI library out of ProGuard/minify, confirm APK size growth, and re-verify the manifest/permissions (internet, network state, multicast; confirm whether `CHANGE_WIFI_MULTICAST_STATE` is needed on Fire OS **VERIFY**).
9. Amazon: re-submit as an update (1.1.0). Note native code in the review notes and add the NDI attribution to the listing description.

### 2.3 Dashboard (Kids and Signage)
- New "NDI feed" item in both playlist editors with: title, source name, optional address (IP:port), duration, audio, fit, fallback.
- Network help text: the TV and the NDI source must be on the same network (or reachable by the address); recommend a wired TV or Cube for full-bandwidth NDI, NDI|HX for Wi-Fi.
- Warn on portrait screens (letterboxing) and on screens whose `app_version` is below 1.1.0.
- Optional later: the TV reports the NDI sources it can currently see (a "Discover" button in the dashboard that shows them); this needs a small status channel from TV to server (a new `screens` column or table).

### 2.4 Testing checklist
- Source goes away mid-slide, returns, is renamed; Wi-Fi drop; TV sleep/wake; module switch while a feed is playing; boot with the source offline.
- Portrait screens (both directions) and letterbox/cover modes.
- Long run: 8 hours on a Fire TV Cube and a stick, watching memory and heat.
- Mixed playlist: image, video, lyrics, then NDI, then back, with no flashes or black frames between slides.
- A Fire TV with only Wi-Fi playing full-bandwidth NDI (expect to fail; confirm the dashboard guidance is clear).

### 2.5 Risks
- NDI licence terms for Android/fixed-purpose devices (blocking until answered).
- Weak Fire TV sticks may not decode HX3/high bitrates smoothly.
- Church network setups (VLANs, blocked multicast) make discovery unreliable, so the manual address option is essential.
- Newer Vega OS sticks cannot run any of this (the Android app does not run on them).
- Production module overlap: green room and stage displays (confidence feeds) are the strongest NDI use case; build the receiver as a reusable component.

## Phase 3: "BoxCast: now live" (API)
- Each church connects its BoxCast account in Settings via OAuth (BoxCast's OAuth access app for multi-account tools). Store tokens server-side only (Supabase table with strict row security, tokens encrypted; never in the TV app).
- A Supabase Edge Function lists the church's broadcasts and returns the playable HLS link from the broadcast "view" call (optionally with the low-latency `byteranges` flag). It checks BoxCast's `status` (live or recorded) and the TV app gets a ready-to-play URL in `device_state`.
- New slide type `{"type":"boxcast","title":"Service","channel":"...","mode":"live_now","fallback":"skip"}` that resolves to whatever is live at play time (like the YouTube "Live now" item); refresh the link before it expires.
- **Ask BoxCast support first:** (1) can the low-latency playlist be used for viewers and how low is it; (2) which plans include API/OAuth; (3) the API base URL (one source says `api.boxcast.com`; the reference shows sign-in on `auth.boxcast.com`); (4) how long a stream link stays valid.
- Expect about 30-40 s viewer delay on the standard feed: label this clearly in the dashboard so nobody uses it for lyrics.

## Acceptance for the whole feed feature
- Both modules can place a live feed slide in a playlist from the dashboard.
- Feeds never leave a blank or frozen screen (fallback rules work).
- Old TV builds are protected (tolerant decoding + dashboard warning).
- NDI attribution and trademark notices are present in the app and listing.
- The HLS stream slide ships first; NDI follows once the spike and licence check pass.

---

# Feature plan: weekly Calendar page and dark mode (dashboard)

Planned 2026-10-15. Dashboard and database only, so **no TV update or Amazon review is needed**. Decisions from Keith: one Calendar page for everything; Kids schedules can repeat weekly, with a different playlist per repeat; 15-minute snapping; one drag can schedule several screens; dark mode defaults to the system setting.

## A. Calendar page (replaces the schedule pages as the main way to schedule; keep the old list pages as a "List" view)

### What the user sees
- New nav item **Calendar** (top level, above the module groups). A week grid (Mon-Sun, hours down the side), with previous/next week, "today", and a week/day toggle.
- A **view picker**: one screen, a screen group, or a location. The grid shows that target's blocks. Colour by type: Kids, Signage, Slides (later), and module-switch rules; a faint background band shows which module is active at each hour.
- **Create**: drag across an empty slot to make a window (snaps to 15 minutes). A side panel (a bottom sheet on phones) asks:
  1. What plays: a Kids playlist, a Signage playlist, or "switch this screen to [module]" (and later a Slides deck).
  2. Which screens: this screen, several screens, or a whole group. (One drag can schedule many screens.)
  3. Repeat: this week only, every week on chosen days, until a date, or a rotation (see B).
- **Edit**: drag a block to move it, drag top or bottom edge to resize, click to edit, delete, or duplicate. Recurring blocks ask "this one, or all in the series?".
- **Copy week**: copy this week's blocks to the next week or a date range.
- **Overlaps**: flag clashes; show which block wins using the existing priority rule (highest priority, then latest created). An "Add as higher priority" toggle in the panel.
- Times are in the site's time zone (shown in the header); a screen in a different zone than the user's browser is labelled.
- **Permissions**: blocks the user cannot edit show locked/read-only (module rules need owner or admin; Kids content needs editor and the site; Signage slots need an all-sites editor, per current row security). No block exists that the user can edit without the right role.
- **Phone**: show 1-3 days at a time, horizontal swipe between days, long-press to drag, and a tap on an empty slot opens the panel as a plain form (always works without precise dragging).

### Data it reads and writes (existing tables unless noted)
| Block type | Table | Notes |
|---|---|---|
| Signage playlist | `signage_slots` | weekly recurring already; target screen or group |
| Module switching | `screen_schedules` | weekly recurring already; target screen or group |
| Kids one-off | `schedules` | dated, per location (a TV's Kids blocks come from its location) |
| Kids repeating (new) | `kids_series` + `kids_series_exceptions` (see B) | the server expands them into the same dated list the TV already reads |

### Build approach
- Use FullCalendar's free core packages (`@fullcalendar/react`, `daygrid`, `timegrid`, `interaction`; MIT licence) for the grid, drag, resize and touch handling, and style it to the dashboard (check licence terms for the packages used before adding; avoid the paid "premium" resource views). Fallback if bundle size or touch handling is a problem: a custom CSS-grid calendar with pointer events.
- Lazy-load the calendar page so the main bundle (already about 565 kB) does not grow.
- One component with three adapters (Signage slots, module rules, Kids schedules/series) that turn rows into events and events back into inserts/updates.
- Writes use the existing row-security rules; multi-screen creates are one batch per target.

### Done when
- Dragging a window creates the right rows for 1 screen, 3 screens, and a group; moving and resizing update them; deleting removes them.
- A weekly Signage slot, a module switch, and a Kids playlist for one location all appear together for a screen and the TV follows them.
- Works with a mouse and with touch on a phone; locked blocks cannot be edited; overlap flags are right.

## B. Kids repeats, with a different playlist per repeat
Meaning: a **series** that repeats weekly, where each occurrence can use a different playlist. Two ways, both supported:
1. **Rotation (curriculum)**: choose an ordered list of playlists (Week 1, Week 2, Week 3...). Occurrence 1 plays the first, occurrence 2 the second, and so on; at the end either **stop** or **loop back to the start**.
2. **Per-occurrence override**: in the calendar, open one occurrence and change just that one's playlist, or skip it (for a holiday).

### Data model (new migration)
- `kids_series`: `id, organization_id, location_id, days int[] (0 = Sunday), start_time, end_time, start_date, end_date null, playlist_ids uuid[] (the rotation), on_end ('stop'|'loop'), priority, created_at`.
- `kids_series_exceptions`: `series_id, on_date, action ('skip'|'playlist'), playlist_id null`.
- Decision still open: when an occurrence is **skipped** for a holiday, does the rotation advance or wait? Recommend **wait** (the skipped week's playlist moves to the next occurrence) with a "skip and advance" option.
- `device_state` expands each series into dated entries for the next 14 days in the existing `kids.schedules` shape (`starts_at`, `ends_at`, `playlist`), working out which playlist applies to each date from the series start. Dated one-offs in `schedules` take precedence over series when they overlap. **No TV change.**
- Use the site's time zone for times and DST (do not store as UTC offsets). Test across a daylight-saving change.
- Calendar shows the series occurrences as blocks labelled with the playlist (for example "Week 3: Noah").

## C. Dark mode
- Header switch: **Light / Dark / System** (default System), remembered per browser in `localStorage` (wrapped in try/catch) and applied before first paint to avoid a flash.
- Move the dashboard's colours to a shared set of CSS variables for both themes (background, surfaces, borders, text, muted text, inputs, buttons, notices, calendar colours). Audit the styles for any hard-coded colours (the branding preview mock-ups, thumbnails, drag highlights, tables).
- **Church colours on dark**: the primary colour is used for buttons and accents; compute a readable tint for dark mode so a dark navy primary does not disappear against a dark background. Keep a contrast check (the Settings preview already warns about light colours; add the dark-background equivalent).
- Use the church's **logo for dark backgrounds** in the header in dark mode (falls back to the normal logo).
- Leave the TV-style preview mock-ups in Settings unchanged (they show the TV, not the dashboard); set `color-scheme` so form controls, scrollbars and date/time pickers follow the theme; update the `theme-color` meta tag and the iPhone home-screen status bar.
- **Done when:** every page is readable in both themes (check each page, the media library, the calendar, dialogs), no flash of the wrong theme on load, and brand colours stay legible.

## Order and sizing
1. Dark mode (small to medium, independent).
2. Calendar read-only view with Signage slots and module rules (medium).
3. Calendar create/move/resize and multi-screen scheduling (medium to large).
4. Kids series with rotation and exceptions, plus the server expansion (medium).
5. Polish: copy week, overlap hints, phone behaviour, tests across a daylight-saving change.
