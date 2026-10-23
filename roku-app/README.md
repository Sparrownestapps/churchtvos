# Church TV OS for Roku

First Roku build of the Church TV OS TV player (BrightScript + SceneGraph, written in BrighterScript). It follows the Fire TV / Android app
(`tv-app/`, 1.7.0) and talks to the same Supabase device functions. Channel version 1.0.0 (`manifest`: 1.0.1 build).

**Honesty note:** there was no Roku device or official emulator available when this was built. It was compiled and linted strictly with
`bsc`, unit tested, and exercised in the community `brs-node` BrightScript/SceneGraph interpreter against a mock server. Everything in the
"Never run on a real Roku" list below still needs a first sideload.

## Build, test, sideload

```
npm install
npm run lint        # bsc --noEmit with bslint: must print nothing
npm test            # off-device unit tests + QR decode check (about 20 s)
npm run package     # lint + build -> dist/church-tv-os-roku-1.0.0.zip (dist/ is gitignored)
ROKU_IP=192.168.1.50 ROKU_DEV_PASSWORD='...' npm run deploy
```

`deploy` uses roku-deploy (dev installer at `http://<ip>/plugin_install`, digest auth, user `rokudev`). The IP and password come from
environment variables only and are never written to disk or logs.

Enable developer mode on the Roku: on the remote press Home x3, Up x2, Right, Left, Right, Left, Right; note the IP, set a password, reboot.
Then open `http://<ip>` in a browser, or use `npm run deploy`. Logs: `telnet <ip> 8085`. Debug console commands: `logrendezvous on`, `bsprof_enable`.
Roku shows installed dev channels as "Church TV OS" (dev); the first run registers the TV and shows a 6-character pairing code and QR.

Other tools: `python3 tools/make_assets.py` (channel icons, splash, gradient ramps from `store/assets`; needs Pillow),
`node tools/gen_vectors.mjs` (reference test data from the `qrcode` package and Node's Intl time zones),
`node tools/smoke.mjs [pairing kids deck signage settings portrait remote override offline demo]` (headless run against `tools/mock_server.mjs`,
screenshots into `.tmp/shots/`; needs python3; never contacts the real Supabase).

### Packaging for beta or the store later
Sideload zips are unsigned dev packages. For a beta/store package: on the Roku press the dev-installer "Packager" page, or run
`genkey` over telnet 8085 to get a signing password and key, then package from `http://<ip>:80` > Packager. **The signing key and password
are tied to the channel identity forever: back them up somewhere safe (not in git); losing them means a new channel ID.** Then create the
channel in the Roku Developer Dashboard, upload the signed `.pkg`, and complete the content metadata. Beta channels use a channel access code.
Set `major_version/minor_version/build_version` in `manifest` for each upload.

## What it does (parity with the Android app)
- Registers with `register_device` (UUID + 64-hex secret in the Roku registry), pairing screen with the 6-character code and a QR
  (`https://app.churchtvos.com/pair?code=<CODE>`), polls until claimed, per-church colours and logo.
- `device_state` polling: 30 s paired, 5 s while unpaired. Last state cached in `cachefs:/state.json` and used offline. Suspended church
  and not-enabled-module messages, "Connecting" screen, offline note on home and pairing.
- Modules switched by the schedule rules (evaluated on the TV in the site time zone): Kids playlists (image, video, lyrics with optional
  title slide, countdown, sign, HLS stream), Signage loops (slots and groups are resolved by the server; the TV picks the matching slot or
  the default, black when none), Slides decks (text, picture, video, countdown, stream, blank, song title/lyrics, themes, gradient/colour/
  picture backgrounds with dimming, per-slide overrides, labels, logo, lower thirds), black screen for `off`.
- Countdowns: until/duration, at_zero hold/next, if_passed zero/skip, DST-safe wall clock in the site zone.
- Remote control exactly as Remote.kt: polls `device_poll_commands` every 2 s while playing (5 s idle), reports `device_report_status` on
  every change and every 15 s with the outline: next, previous, jump, blank, stop, start, message overlay, clear_message, play-now override.
- Portrait screens: content is laid out sideways and turned with a node rotation. Remote keys: Right/Fwd next, Left/Rev back, OK = pause
  video (Kids/Signage) or slide list (decks), Play = black screen (decks) or pause, Back = stop, `*` = Settings from anywhere.
- Settings (device id, church, screen, version, time zone, refresh, demo mode, unpair), demo mode with bundled sample content.
- Media downloaded in a Task to `cachefs:/media` (SHA-1 names like Android), capped at 1.5 GB, stale files pruned; playback falls back to
  streaming the URL if a file is missing.
- Unknown item, slide, background and command types are skipped, never a crash.

## Device protocol assumptions and the server
- Same RPCs and headers as Android: `POST {SUPABASE_URL}/rest/v1/rpc/<name>` with the publishable `apikey` header only.
- **Version gating (no server change needed):** the server hides Slides below app version 1.4.0 and sends old-style lyrics below 1.3.0,
  comparing only the leading numeric part of `screens.app_version` (`version_ge`). The Roku reports `p_app_version = "1.7.0-roku"`
  (the protocol level it implements, with a platform suffix visible in the dashboard) and `p_model = "Roku <model>"`. There is no
  platform column or allowlist. If a real `platform` field is wanted later, that is a new migration plus a column on `screens`; none was added.
  Bump `REPORTED_APP_VERSION` in `source/lib/Config.bs` when Android gains protocol features the Roku supports.
- NDI: the server may send NDI items to churches with the flag. Roku has no NDI, so only items with `fallback: "message"` are shown (as their
  message); `skip` items are dropped.
- "Unpair" clears the TV's identity and registers a new screen; the old screen row stays in the dashboard and should be deleted there.

## Known gaps and differences from Android
- **YouTube** items/slides cannot be embedded on Roku: skipped (like unknown kinds) and marked "not supported on Roku" on the home screen.
- **Video and live streams on portrait screens are skipped** (Roku's video plane cannot be rotated). Backgrounds that are video are ignored in portrait.
- Only one video plays at a time (video plane): a Slides video slide shows without its looping background video.
- Video "cover" fit cannot crop; it is shown fitted.
- Countdown music: no volume or fade control on Roku (Audio node), so volume and fade are ignored; it plays at full level and stops at zero.
  `align_end` start/seek is implemented but unverified. Looping restarts the track with a small gap.
- Text shadow/outline are black copies of the text; no letter spacing; Julius Sans One and Lato ship in the package.
- Gradients use 15-degree steps of a shipped alpha ramp (stretched to the screen), not an exact CSS angle on non-square boxes.
- Time zones: Roku has no tz database. Common IANA zones (North America, Europe, Australia, NZ, Asia) are built in and tested against Node
  for 2025-2030; an unknown zone falls back to the Roku's own time zone setting. British Columbia and Alberta follow tz 2026c (permanent daylight time).
- The `cachefs:/` volume is persistent but the system may clear it; the TV then streams. The cached state also lives there: a cleared cache plus no
  network means a black "Connecting" screen until online.
- **Autostart and keep-awake:** a Roku channel cannot launch on power-on; the closest options are setting the TV's power-on input to the Roku and
  the Roku's "Start from home screen" settings, or a remote ECP launch. Roku's screensaver is a user setting (Settings > Theme > Screensaver,
  wait time) and applies to static slides; it does not start while a video plays. There is no API to disable it. Raise the wait time.
- Autoplay of scheduled items (screen autoplay flag) is supported; the "open automatically" prompt does not exist on Roku.
- Offline banner appears on home and pairing screens only (as on Android), not over playing content.
- Image size: images much larger than 1920x1080 are downscaled on load (Poster `loadWidth/loadHeight`).

## Verified off-device vs never run on a real Roku
Verified (automated): BrighterScript compile with zero errors and zero lint warnings; `npm test` (247 checks): QR encoder module-for-module identical to the
`qrcode` package for 10 payloads (including the pairing URL, version 4) and decodable by jsQR; time zone offsets for 28,948 instants and 417 wall-clock
"count down until" cases against Node Intl; ISO parsing; module/slot/schedule selection; branding; playlist, deck and theme expansion; countdown maths;
remote command parsing and status params; cache naming; text-fit estimates.
Exercised in the brs-node interpreter against a mock API (interpreter, not a Roku): registration, pairing screen with QR, paired Kids/Slides/Signage home and
player, countdown, lyrics, song title, lower third, gradient, slide list, settings, portrait layout, remote commands (next, blank, jump, message, clear, stop) with
the exact status sequence reported, request headers and `register_device` parameters.
**Never run on a real Roku:** actual SceneGraph rendering and fonts/text measurement (`Label.boundingRect`), Video/Audio nodes (HLS, MP4, cachefs playback, audio
alignment), roUrlTransfer HTTPS with the CA bundle, registry and cachefs behaviour and space limits, `roDeviceInfo.GetRandomUUID`, portrait rotation direction
(Roku rotation sign was taken from the documentation and the engine; swap the sign in `applyOrientation` in `components/MainScene.bs` if a turned TV shows upside down),
memory use on low-end models, key handling in practice, store certification checks (channel art is generated but unreviewed).
