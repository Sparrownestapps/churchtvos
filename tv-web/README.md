# Church TV OS web player (LG webOS and Samsung Tizen)

The Vega app's screens and logic (`../vega-app/src`) running on react-native-web, with a web platform layer (`src/platform`) in place of
the Vega one. The same build runs in a browser and is packaged as an LG app (`.ipk`) and a Samsung app (`.wgt`).
It reports `1.7.0-webos`, `1.7.0-tizen` or `1.7.0-web` to the server, so the dashboard shows which kind of TV it is.

**Status (2026-11-02):** runs in Chrome (dev server and packaged `file://` build): registers, pairing screen with QR, Settings, demo mode
(countdown, lyrics, bundled pictures), remote keys and Back. The LG `.ipk` packages. **Never run on an LG or Samsung TV or simulator yet.**

## Commands

```
npm install
npm run dev          # http://localhost:5175 in a browser (arrow keys, Enter, Esc = Back, M = Settings)
npm run build        # dist/ (modern + legacy) for a web server
npm run package      # dist-tv/ (classic scripts only), then out/com.churchtvos.tv_1.0.0_all.ipk and, with Tizen Studio, the .wgt
```

Shared code lives in `../vega-app/src` (type-checked there). This project's own check is `npm run typecheck`.

## LG webOS

- Package: `webos/appinfo.json` (id `com.churchtvos.tv`, `disableBackHistoryAPI` so Back arrives as key 461), icons, splash.
- Developer Mode: create an account at webostv.developer.lge.com, install "Developer Mode" from the LG Content Store on the TV, sign in, turn it on
  (the session lasts about 50 hours; extend it in the app). Then on the Mac:
  ```
  npx ares-setup-device        # add the TV: its IP, port 9922, user prisoner, passphrase shown in the Developer Mode app
  npx ares-install -d <tv> out/com.churchtvos.tv_1.0.0_all.ipk
  npx ares-launch -d <tv> com.churchtvos.tv
  npx ares-inspect -d <tv> --app com.churchtvos.tv --open   # remote Chrome DevTools
  ```
- Simulator: the webOS TV Simulator from LG's developer site; `npx ares-launch -s <version> .pkg/webos`.
- Store: LG Seller Lounge (seller.lgappstv.com).

## Samsung Tizen

- Package: `tizen/config.xml` (package `CHTVOS0001`; Samsung may assign a different one at registration, update it then), privileges
  for internet, remote keys and product info, icon 512 x 423. The packaging step adds Samsung's `webapis.js` for screensaver control.
- Needs Tizen Studio with the TV extensions and a Samsung certificate profile (Certificate Manager, signed in with a Samsung account).
  Name the profile `churchtvos`, or set `TIZEN_PROFILE`.
- Developer Mode on the TV: Apps, press 1 2 3 4 5, switch on, enter the Mac's IP, restart the TV. Then
  `sdb connect <tv-ip>`, `tizen install -n out/ChurchTVOS.wgt -t <device>`, `tizen run -p CHTVOS0001.ChurchTVOS -t <device>`.
- Store: Samsung Seller Office (seller.samsungapps.com).

## Differences from the Android and Vega apps

- **Live streams (HLS):** native `<video>` on TVs, hls.js in desktop browsers.
- **Volume and mute work** (countdown music fades; "audio off" mutes), unlike Vega.
- **Keep awake:** Samsung switches its screensaver off while content shows (`webapis.appcommon.setScreenSaver`); browsers use the Wake Lock
  API; LG: unknown, test on a TV.
- **Offline media:** downloads go to the browser's Cache Storage and play from object URLs. Where Cache Storage isn't available (often for
  apps loaded from `file://`), nothing is cached and media streams. Samsung's `tizen.download` / filesystem and LG's storage are the next step
  if offline playback matters on these TVs. **Check this first on each TV.**
- **Arrow-key focus** between buttons is done in `src/platform` (browsers don't move focus with arrows; TVs' native apps do).
- No auto-launch at power-on on consumer LG or Samsung TVs. YouTube items are skipped (as on Vega).

## Never run on a real TV (check these)

1. The packaged app on webOS 5+ and Tizen 5.5+ (classic-script build, `file://` loading, fonts).
2. Remote keys: Back (LG 461, Samsung 10009), Play/Pause and track keys (Samsung registers them in `src/platform/tv.ts`), Settings
   (Menu / Tools key; hold OK also works).
3. Offline media (Cache Storage availability) and video playback from object URLs.
4. Screensaver during a picture-only Signage loop (Samsung should hold it off; LG unknown).
5. Portrait rotation with video playing.
6. Leaving the app with Back from the pairing or home screen.
