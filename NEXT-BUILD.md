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
