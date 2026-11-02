# Church TV OS for Vega OS (Fire TV)

Native React Native build of the Church TV OS TV player for Amazon's Vega OS, the Linux-based system on the newest Fire TV sticks
(Fire TV Stick 4K Select, the 2026 Fire TV Stick HD). The Android app in `tv-app/` can't run there. This app follows `tv-app` 1.7.0
and talks to the same Supabase device functions. App version 1.0.0; it reports `1.7.0-vega` to the server (see `src/core/config.ts`).

**Status (2026-11-02):** builds with SDK 2.0.13986 (packages for Vega OS 1.2 and 2.0) and runs on the Vega Virtual Device: Keith paired it ("Keith Virtual Test")
and checked the Kids home screen, playback, the phone remote, Settings and demo mode. Never run on a real stick yet. Earlier checks: It type-checks against the real Vega packages, bundles with Metro for the
`kepler` platform, and the platform-neutral core passes its tests. It has **never run on the Vega Virtual Device or a real stick**.

## Layout

| Folder | What's in it |
|---|---|
| `src/core/` | Platform-neutral logic, mirroring the Kotlin files: server calls (`api.ts`), sync and remote loops (`sync.ts`), schedules and module rules (`modules.ts`), playlists and decks (`model.ts`), countdowns, branding, remote commands, slide style, text fit, cache names. Runs in Node. |
| `src/platform/` | Everything Vega-specific: AsyncStorage, the media cache (`expo-file-system` in `/data/media`), the video player (`w3cmedia`), remote keys, Back. Device gaps get fixed here. |
| `src/ui/` | Screens: pairing with QR, Kids and Slides home screens, the Kids/Signage player, the Slides player, settings, demo mode. |
| `src/App.tsx` | What the TV shows when: pairing, module by schedule, play-now overrides, messages, Settings. |
| `test/` | `npm test` (Node, no SDK needed). |
| `assets/` | App icon (`image/icon.png`), Lato and Julius Sans One, demo pictures (same as the Android app). |

## Build and run

Needs the Vega SDK (macOS on Apple Silicon, Node 22.14+). One-time setup, from Amazon's install page:

```
softwareupdate --install-rosetta --agree-to-license
brew install binutils coreutils gawk findutils grep jq lz4 gnu-sed watchman
curl -fsSL https://sdk-installer.vega.labcollab.net/get_vvm.sh | bash && source ~/vega/env
vega --version
```

Then, in this folder:

```
npm install
npm test                      # core tests, no SDK needed
npm run typecheck
vega exec vpt validate manifest.toml
tools/build.sh                # Release build. Amazon's tools break on paths with spaces, so it builds a copy in ~/dev/churchtvos-vega
                              # and copies build/aarch64-release (virtual device) and build/armv7-release (Fire TV stick, Appstore) back
npm run vvd:start && npm run vvd:run
```

Virtual device keys: Back = Esc, Home = F1, Menu = F2, Play/Pause = F4.

**On a Fire TV Stick 4K Select:** Settings > My Fire TV > About, press Select 7 times on the device name; Developer options > Developer
Mode > Continue (shows a code). Then `vega devmode login`, `vega devmode enable-device --code <code>`, `vega device list`,
`npm run device:install`, `npm run device:launch`. Use the stick's own power adapter; a laptop USB port may not power it.

**Appstore:** same package id as the Fire OS app (`com.churchtvos.tv`), so it goes on the existing listing: Add Upcoming Version, upload
the armv7 `.vpkg`, Target Your App > Fire TV > Amazon Vega TV. Don't mention "Vega" in any listing text. Live App Testing works for Vega.

## What it does (parity with the Android app)

- Registers with `register_device` (UUID + 64-hex secret in AsyncStorage), pairing screen with the code and QR
  (`https://app.churchtvos.com/pair?code=<CODE>`), polls every 5 s until paired, then 30 s. Last state saved and used offline.
- Module rules evaluated on the TV in the site's time zone: Kids playlists (video, picture, countdown, lyrics with title slide, sign, stream),
  Signage loops (slot or default, black when none), Slides decks (text, picture, video, countdown, stream, blank, song title and lyrics,
  themes, colour/gradient/picture/video backgrounds with dimming, lower thirds, labels, logo), black for `off`, module splash screens.
- Remote control exactly as `Remote.kt`: polls `device_poll_commands` every 2 s while playing (5 s idle), reports status on every change and
  every 15 s with the outline: next, previous, jump, blank, stop, start, message overlay, clear_message, play-now overrides.
- Media pre-downloaded to `/data/media` with the same SHA-1 file names as Android, via a `.part` file, 500 MB kept free, unused files pruned.
  A file that hasn't finished downloading plays from the web instead.
- Portrait screens: the UI is laid out sideways and turned a quarter turn, as on Android.
- Remote: Right/Left next and back, OK pauses video (Kids/Signage) or opens the slide list (decks), Play/Pause blanks (decks), Back stops,
  Menu or holding OK opens Settings. Settings: demo mode, unpair, version and TV id.
- Unknown item, slide, background and command types are skipped, never a crash.

## Known gaps and differences from Android

- **YouTube items are skipped** (no YouTube player on Vega); the Kids home screen marks them "not on this TV".
- **Live streams (HLS) don't play yet.** Vega's player needs the Shaka or hls.js MSE player for `.m3u8`; Amazon's `vega-video-sample` has the
  setup (`shaka-setup/`). Until it's added, stream slides follow their fallback: skip, or "Waiting for the live feed…" then skip.
- **No volume control on Vega's player:** countdown music plays at full level (no fade), and "audio off" on a stream or video slide can't
  mute it. Countdown music is still timed and stops at zero; `align_end` waits so the track ends at zero, or seeks into it.
- **No auto-launch at power-on** (Vega has no API for it); Settings tells people to start it from the home screen.
- **No keep-screen-on API.** The screensaver starts after 5 minutes without remote input. Whether a playing video holds it off is unknown.
  A Signage screen showing pictures may get the screensaver: test this first; it decides whether Vega suits unattended signage.
- NDI: like Roku, only NDI items with `fallback: "message"` are shown (as their message), and only for churches with the flag.
- Gradients are drawn as 48 colour bands (no gradient library), so very subtle gradients may show faint steps.
- Text fit is an estimate (React Native can't measure text before drawing), tuned to err small.

## Never run on a real device (check these first)

1. Video from a downloaded file: `src/platform` passes `file:///data/media/<name>` to the player and to `<Image>` (`FILE_URI`). If either
   wants a bare `/data/...` path, change `FILE_URI` only.
2. The screensaver during video and during a picture-only Signage loop (see above).
3. Video under the portrait rotation (`Oriented`), and "cover" fit, on `KeplerVideoSurfaceView`.
4. `Intl` time zones in Hermes on Vega (`src/core/time.ts`). If `Intl.DateTimeFormat` with `timeZone` isn't supported, times fall back to the
   stick's own time zone, which is right when the stick's setting matches the church. The Roku app's built-in zone table could be ported.
5. `crypto.getRandomValues` (device secret). There's a non-cryptographic fallback; replace it if Vega has a native random source.
6. Fonts via `@amazon-devices/expo-font`, remote keys (key names and the hold-OK-for-Settings timing), Back from every screen,
   AsyncStorage persistence across reboot, download speed and space on the stick, focus on the Play buttons.
7. Amazon's pre-submission checks: Back and relaunch, Home and relaunch with no audio left playing, HDMI or input changes, relaunch after a restart
   keeps the pairing, Alexa interruption.
