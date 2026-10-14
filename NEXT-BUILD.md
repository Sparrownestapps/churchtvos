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
