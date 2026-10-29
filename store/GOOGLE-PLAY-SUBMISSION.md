# Google Play (Google TV / Android TV) submission kit: Church TV OS 1.7.0

Same app and package name as the Amazon build (`com.churchtvos.tv`). Console labels change; match by meaning. Items marked **VERIFY** are current-policy details to confirm in Play Console.

## Files
| What | Where |
|---|---|
| Signed app bundle (upload this) | `store/build/church-tv-os-1.7.0-play.aab` (version 1.7.0, code 8; the "play" flavor: no NDI, no auto-launch) |
| Same build as an APK (sideload test) | `store/build/church-tv-os-1.7.0-play.apk` |
| Amazon build (keeps auto-launch) | `store/build/church-tv-os-1.7.0.apk` |
| App icon 512x512 | `store/assets/icon-512.png` |
| Feature graphic 1024x500 | `store/assets/promo-1024x500.png` |
| TV banner 1280x720 | `store/assets/firetv-app-icon-1280x720.png` |
| Screenshots 1920x1080 (TV) | `store/screenshots/` |
| Privacy policy | https://app.churchtvos.com/privacy.html |
| Account/data deletion page | https://app.churchtvos.com/delete-account.html |
| Support email | support@churchtvos.com |

Amazon: if you have not yet uploaded the 1.1.0 update to the Amazon Appstore, upload **1.2.0** instead. It contains everything in 1.1.0 plus the Google TV changes (settings without a Menu button; auto-launch only offered on Amazon devices).

## What changed for Google TV in 1.2.0
- Google TV remotes have no Menu button, so Settings and Demo mode are reachable from a button on the pairing screen and by holding OK for a second anywhere.
- Auto-launch is only offered on Amazon devices. Android 10+ blocks apps from opening themselves from the background, so on Google TV the setting is replaced by a short explanation and the background service never starts.

## 1. Developer account (you)
1. play.google.com/console -> create a developer account with **keith@sparrownest.com** (one-time US$25). Choose "Personal" or "Organization" (an organization needs a D-U-N-S number).
2. Verify identity. **VERIFY:** new personal accounts may have to run a **closed test with about 12 testers for 14 days** before Production is allowed. Start the closed test early. Organization accounts are not subject to this.
3. Create app -> name "Church TV OS", default language English, App (not game), Free.

## 2. Release path
1. **Internal testing** track first: upload the `.aab`, add yourself as a tester, install from the Play link. No review needed for internal testing.
2. **Closed testing** (if required) with Forward Church staff as testers.
3. **Production** when ready.
- Opt in to Google Play App Signing when asked (Google keeps the final signing key; your key is the upload key). Keep `tv-app/keystore/` backed up.

## 3. Form factors (important)
The manifest marks leanback and touchscreen as not required so one build serves Amazon and Google. In Play Console, under Release > Setup > **Advanced settings > Form factors** (or the device catalog), publish **only to Android TV**. Do not enable phones, tablets, Wear or Auto. **VERIFY** the current location of this setting.

## 4. Store listing
- **App name:** Church TV OS
- **Short description (80 characters max):**
  Kids-room displays and church signage on your TVs, scheduled from the web.
- **Full description (4000 max):** use the long description from `store/AMAZON-SUBMISSION.md` (section 2), then add:
  "Works on Google TV and Android TV devices. Create your church's free account at app.churchtvos.com. Open Settings from the pairing screen for a built-in demo that needs no account."
- **Category:** Tools or Productivity (Lifestyle also fits). **Tags:** as offered.
- **Graphics:** icon 512, feature graphic 1024x500, TV banner 1280x720, TV screenshots (1920x1080 landscape; Play wants several, upload 4-8).
- **Contact:** support@churchtvos.com, website https://app.churchtvos.com, privacy policy URL above.

## 5. App content forms
- **Privacy policy:** URL above.
- **App access (login-protected functionality):** the app needs an organization account to pair, but a demo needs no account. Paste: "The app is a display client for organizations that manage content in a web dashboard (app.churchtvos.com). No sign-in is required to evaluate it: on the first screen choose 'Settings and demo mode', then 'Demo mode', then 'Kids demo' or 'Signage demo'. Press Back to leave a demo."
- **Ads:** none.
- **Target audience and content:** 18+ (not designed for children; children may see content on a screen but do not use the app). Not a Families app.
- **Content rating questionnaire:** no violence, sexual content, profanity, drugs, gambling; no user-to-user communication; no location sharing; no purchases.
- **Data safety:**
  - Collected: device or other IDs (a random device identifier), app info (version), device model; purpose: app functionality; not shared with third parties for advertising or analytics; processed by service providers (Supabase, Netlify); encrypted in transit; users can request deletion at https://app.churchtvos.com/delete-account.html. No personal info, location, contacts or financial info collected by the TV app.
  - Accounts: created on the web dashboard, not in the app. Provide the deletion URL above where Play asks for an account deletion link.
- **Government apps / financial features / health:** none.
- **Permissions:** the Play build asks only for internet, network state and wake lock. It has no boot receiver and no foreground service (auto-launch is Fire OS only and lives in the Amazon build), so no special-use declaration is needed.
- **Target API level:** the app targets API 36. **VERIFY** Play's current minimum.

## 6. Testing on Google TV
No Google TV device yet. Options: a Chromecast with Google TV or an onn 4K box (adb install, see below), or an Android Studio "Google TV" emulator image (a download of roughly 1.5 GB from Google; not installed).
```
adb connect <TV-IP>:5555
adb install -r store/build/church-tv-os-1.7.0.apk
```
Enable Developer options (tap Android TV OS build seven times), then USB/Wireless debugging.
Checklist on a real Google TV: pairing screen and code, Settings button, hold OK, demo, a paired Kids playlist, a Signage loop, a stream slide, portrait screen, HDMI-CEC/standby wake (the app should resume from the Google TV home screen only when the user opens it).

## 7. Known differences from Fire TV
- No auto-launch on boot/wake (platform restriction).
- Google TV home shows the app in the Apps row; users may want to pin it to Favorite apps.
- The newest Amazon Vega OS sticks still cannot run this APK; Google TV has no such restriction.

## Building
Google Play: `cd tv-app && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew bundlePlayRelease assemblePlayRelease` (flavor `play`). Amazon: `bundleStoreRelease assembleStoreRelease` (flavor `store`). Both are signed with the same upload key.

## Test TV
The Community Room TV at Forward (TCL 98" Google TV, has the Play Store) runs a sideloaded 1.7.0. Once Play App Signing is on, the Play copy is signed by Google's key, so the sideloaded app must be uninstalled first (the TV then needs pairing again).
