# Amazon Appstore (Fire TV) submission kit: Church TV OS 1.0.0

Everything below is ready to paste. Console labels change over time; match them by meaning.

## Files
| What | Where |
|---|---|
| Signed release APK (v1.0.0, code 1, `com.churchtvos.tv`) | `store/build/church-tv-os-1.0.0.apk` (git-ignored; SHA-256 starts `cde1a372bed2a313`) |
| Large icon 512x512 / small icon 114x114 | `store/assets/icon-512.png`, `icon-114.png` |
| Promo image 1024x500 (optional) | `store/assets/promo-1024x500.png` |
| Screenshots 1920x1080 (need at least 3) | `store/screenshots/` (9 images) |
| Privacy policy URL | https://app.churchtvos.com/privacy.html |
| Terms URL | https://app.churchtvos.com/terms.html |
| Support email | keith@sparrownest.com |

## 1. Developer account (you, about 30 minutes)
1. developer.amazon.com -> Sign in / Create account using **keith@sparrownest.com** (not the church account).
2. Complete the developer profile: legal name, address, phone. Pick the **developer name shown in the store**.
3. Tax and payout details are only required if you sell or take in-app payments. The app is free, so you can skip these for now.
4. Open the Appstore dashboard: Apps & Services -> My Apps -> **Add New App -> Android**.

## 2. App details
- **Title:** Church TV OS
- **Package name:** com.churchtvos.tv (permanent once published)
- **Price:** Free. No in-app purchases.
- **Category:** Lifestyle (alternatives: Productivity / Business)
- **Target:** Fire TV only. Deselect phones and tablets if offered.
- **Device support:** whatever the console computes for an Android/Fire OS APK. Expect Fire OS devices only (newer Vega OS sticks cannot run it).
- **Keywords:** church, signage, digital signage, kids, classroom, display, announcements, lyrics, countdown
- **Account deletion URL:** https://app.churchtvos.com/delete-account.html
- **Short description (up to ~120 characters):**
  Run kids-room displays and church signage on your TVs, scheduled from the web or your phone.
- **Long description:**
  Church TV OS turns any Fire TV into a managed display for your church or organization.

  Kids module: show your curriculum videos, countdown timers and song lyrics in each classroom, with the right content scheduled for the right room.

  Signage module: loop announcements, images and videos in lobbies, hallways and welcome areas on a weekly schedule.

  - Pair a TV in seconds with a six-character code.
  - Manage content, schedules and multiple campuses from the web dashboard at app.churchtvos.com, including from your phone.
  - A TV can switch between Kids and Signage on a schedule, for example Signage on weekdays and Kids on Sunday.
  - Add your own logo and colours, with an optional full-screen logo splash.
  - Landscape and portrait screens.
  - Keeps playing from saved content if the internet drops.
  - Optional auto-launch when the TV turns on.

  A free account for your church is created in the dashboard. Open Menu on the remote for a built-in demo mode that needs no account.
- **What's new (v1.0.0):** First release.

## 3. Content rating and data answers (check each against the current form)
- Violence, sexual content, profanity, gambling, alcohol/drugs: **none**.
- Intended audience: **general**; this is a business/organization tool. Not directed at children (children may see content on a screen but never use the app or have data collected).
- User-generated content: organization staff upload content for their own screens; it is not shared between organizations.
- Ads: **none**. Analytics or tracking SDKs: **none**.
- Data collected: a random device identifier, device model, app version and last-connected time, tied to the organization's screen. No names, contacts, location or advertising IDs from the TV.
- Data shared with third parties: hosting and database providers only (Supabase, Netlify), plus YouTube playback when a playlist includes YouTube.
- Account creation: done on the web dashboard, not in the TV app.
- In-app purchases / subscriptions: none in the app. Plans (when introduced) are billed on the web.

## 4. Testing instructions for Amazon's reviewers (paste into the notes field)
  The app is a display client for organizations that manage content in a web dashboard, so it normally needs an organization account to pair. No sign-in is required to evaluate it: on the first screen press the remote's **Menu** button -> **Demo mode** -> choose **Kids demo** (countdown and lyrics) or **Signage demo** (looping slides). Press **Back** to leave a demo.
  Pairing screen: the TV shows a six-character code that is entered in the dashboard (app.churchtvos.com). [Optional: add reviewer login details here once a reviewer account exists.]
  Auto-launch on boot is opt-in: after pairing the app asks once, and it can be changed under Menu -> Settings.
  The app has a foreground service only when the user turns auto-launch on; its purpose is to reopen the display app when the TV is switched on.

## 5. Things Amazon may query
- `FOREGROUND_SERVICE_SPECIAL_USE`: used only when the user opts in to auto-launch (reopening the display app on TV power-on). The manifest property explains this.
- `RECEIVE_BOOT_COMPLETED`: same purpose.
- Landscape lock: the app is declared landscape; portrait is done by rotating content inside the app for portrait-mounted TVs.

## 6. Recommended release path
1. Upload the APK, fill the listing, then use **Live App Testing** (invite-only) to put it on Forward Church's TVs first.
2. Fix anything found, then submit for public release.
3. Sideloaded installs cannot update to the store build (Amazon re-signs it). Reinstall from the store before rolling out widely.

## 7. Known open items before public release
- Replace sample/placeholder reviewer content if you want a richer demo.
- Have the privacy policy and terms reviewed by someone qualified.
- Test on at least one more Fire OS device (for example a Fire TV Stick 4K Max or a Fire OS 8 device).
- Decide whether to create a reviewer account in the dashboard (test church with one screen).
