# Church TV OS for Apple devices

- `ChurchTVCore/` Swift package shared by every Apple app: models, Supabase wrapper (`SupabaseService`), `MockService` (demo mode), formatting, unit tests.
- `ChurchTVRemote/` the iPhone and iPad app (SwiftUI, bundle id `com.churchtvos.remote`, name "Church TV OS Remote"). `project.yml` is the XcodeGen spec; `ChurchTVRemote.xcodeproj` is generated from it and also checked in.
- `ChurchTVMac/` the Mac app (SwiftUI + WKWebView, bundle id `com.churchtvos.mac`, name "Church TV OS"). See "Mac app" below.
- `screenshots/` simulator screenshots taken in demo mode (`mac-*.png` are from the Mac app).

Deployment target: iOS 17.0 (supabase-swift 2.55.4 needs iOS 16, the app uses the Observation framework from iOS 17). Swift language mode 5 (toolchain Swift 6.x).

## Build and run in the simulator
```
cd apple/ChurchTVRemote
xcodebuild -project ChurchTVRemote.xcodeproj -scheme ChurchTVRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/ChurchTVRemote.app
xcrun simctl launch booted com.churchtvos.remote
```
Or open the project in Xcode and press Run. On the sign-in screen tap **Try the demo** (sample church, 4 TVs, simulated commands). Test helper launch arguments: `-demo` (skip sign-in) and `-tab remote|today|settings`.
For iPad use `name=iPad Pro 13-inch (M5)`.

Regenerate the project after changing `project.yml`: `brew install xcodegen` (or build it from source: github.com/yonaskolb/XcodeGen) then `xcodegen generate` in `ChurchTVRemote/`.

## Signing team
`DEVELOPMENT_TEAM` is empty on purpose. Set it in Xcode (target > Signing & Capabilities > Team) or in `project.yml` under `settings.base.DEVELOPMENT_TEAM` and regenerate. The Push Notifications capability needs a real team; `aps-environment` is `development` in `Resources/ChurchTVRemote.entitlements` (Xcode switches to production when archiving). Debug builds register push tokens as `sandbox`, release builds as `production`.

## Tests
```
cd apple/ChurchTVCore && swift test                      # 31 unit tests (incl. Mac support logic)
cd apple/ChurchTVRemote && xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test
```

## Back-end settings
Only `ChurchTVCore/Sources/ChurchTVCore/Config.swift` holds the Supabase URL and publishable key (both safe to ship) and the website links. No secret keys anywhere.

## Push notification table contract (server side is built separately)
- `push_devices (user_id default auth.uid(), platform 'ios', token, environment 'sandbox'|'production', last_seen_at, unique(user_id, token))`. The app upserts on `user_id,token` after the user turns on alerts in Settings, again whenever iOS hands out a (new) token, and deletes the row on sign out. `token` is the hex APNs device token; `environment` tells the sender which APNs host to use.
- `notification_prefs (user_id, organization_id, offline_alerts boolean)`. The app upserts on `user_id,organization_id` when the Settings toggle changes. A missing row means the default (true).

## Notes and behaviours
- Remote: `send_screen_command` RPC; payloads as in the migration (`jump {index}` is 0-based like `screen_status.slide_index`). TV app 1.5.0+ is required, a warning shows otherwise. Online = `last_seen_at` within 90 s, status stale after 60 s. Auto refresh every 3 s while the app is active.
- Today: reads `deck_schedules`, `schedules`, `screen_schedules` and the RPCs `deck_series_occurrences` / `kids_series_occurrences`.
- Add media: PhotosPicker, upload to bucket `media` at `<org>/<uuid>-<filename>` then insert a `media` row. Photos are converted to JPEG. Editors and above only (operators are read-only on content). Progress is per file with a spinner-style bar because the SDK upload exposes no byte progress; background/resumable upload is not done. Folder is optional (the `folder_id` column is nullable); module is required. Warning above 200 MB.
- Billing, sign-up and pricing are not in the app; links go to the website.

# Mac app (`ChurchTVMac/`)

Phase M1 of `APPS-PLAN.md`: a native shell around the website plus a menu bar item. macOS 14+, SwiftUI with AppKit/WebKit where needed, reuses `ChurchTVCore`.

## What is in it
- **Main window**: one `WKWebView` (persistent default data store, so the web sign-in survives restarts) loading https://app.churchtvos.com. Same-site links stay in the window; external links and `target=_blank`/`window.open` open in the default browser. JavaScript alert/confirm/prompt are native sheets, file inputs open `NSOpenPanel`, downloads (`WKDownload`) go to Downloads with a "Show in Finder" note, loading bar, offline/error page with Retry, window title follows the page, window frame is remembered, zoom is remembered. Light/dark follows the system. The web view lives for the whole app run (also with the window closed).
- **Menus**: App (About with version, Settings, Hide, Quit), File (Open Dashboard in Browser), Edit (standard), View (Reload ⌘R, Back ⌘[, Forward ⌘], Actual Size ⌘0, Zoom In ⌘+, Zoom Out ⌘-, Full Screen), Go (Screens ⌘1, Control ⌘2, Calendar ⌘3, Songs ⌘4: hash routes), Window (+ Show TV Status ⇧⌘T), Help (Help, Privacy, Terms, Delete my account; these open in the browser).
- **Menu bar item** (`MenuBarExtra`, window style): TV icon with a status dot (green all online, amber some offline, grey signed out/none). Popover: church picker, each TV with online dot, state chip, now-showing line with slide x of y, Previous / Next / Blank-Unblank / Stop, "Send message…" (text, seconds, presets, clear), Open dashboard, Control page (#control), Sign out, Use demo data, Settings, Quit. Refreshes every 3 s while a popover/status window is visible, every 15 s otherwise. `Window > Show TV Status` shows the same view as a normal window (handy for testing).
- **Settings (⌘,)**: account (email, church, role, sign out, fallback sign-in sheet), show menu bar item, Dock icon on/off (menu-bar-only mode; the two can never both be off), Launch at login (`SMAppService.mainApp`), offline-alert toggle per church (writes `notification_prefs`, asks notification permission, registers for remote notifications, upserts `push_devices` with platform `macos`, environment `sandbox` in Debug / `production` in Release, deletes the row on sign-out), Use demo data (`MockService`), About and links.

## Sign in once (session bridge)
The website (supabase-js) keeps its session in `localStorage["sb-gqkefjngblgomuovaivj-auth-token"]`. `MenuModel` reads it with `evaluateJavaScript` every 15 s (3 s while the popover is open), once the page has loaded on app.churchtvos.com, and hands it to `SupabaseService.setSession` (supabase-swift stores it in the Keychain). Rules:
- The website owns the refresh token. The Mac `SupabaseService` is created with `autoRefreshToken: false` and a session is only adopted while its access token is still valid (> 30 s left), so the SDK never rotates the refresh token behind the website's back (that would sign the website out). When the website refreshes, the new access token is picked up on the next read. If the token has expired and the page is not refreshing (for example the machine slept), the popover says to open the dashboard window.
- Website signed out (key gone) -> the menu bar signs out too. Sign out in the Mac app -> the SDK session and the website's `sb-*-auth-token` keys are cleared and the page reloads to the login screen. The offline-alert push token row is deleted first.
- Tokens are never logged (`WebSession.description` hides them) and are not stored anywhere except the SDK's Keychain storage.
- Fallback: Settings > "Sign in here instead…" signs in natively (email + password) for the menu bar only; such a session is not tied to the website and is not signed out by the bridge.
Pure logic (JSON parsing, key names, expiry, link routing, status roll-up) lives in `ChurchTVCore/MacSupport.swift` with tests in `MacSupportTests.swift`.

## Build and run
```
cd apple/ChurchTVMac
./build.sh                       # ad-hoc signed local build -> build/Build/Products/Debug/Church TV OS.app
open "build/Build/Products/Debug/Church TV OS.app" --args -demo      # demo data, no account needed
```
`build.sh` signs ad hoc with `Resources/ChurchTVMac-LocalTest.entitlements` (sandbox on, network, user-selected files, Downloads, and NO push entitlement, because `aps-environment` is a restricted entitlement that macOS only accepts with a provisioning profile; an app signed with it ad hoc will not launch). In Xcode with a team set, the real `Resources/ChurchTVMac.entitlements` is used (App Sandbox, network client, user-selected files read/write, Downloads read/write, `aps-environment`; Hardened Runtime is on). Test launch arguments: `-demo`, `-url https://app.churchtvos.com/help/` (first page to load; same host only).
Regenerate the project after editing `project.yml`: `xcodegen generate` (XcodeGen can be built from source: `git clone https://github.com/yonaskolb/XcodeGen && swift build -c release`). The `.xcodeproj` is checked in.

## Signing, notarizing, distributing
1. Set the team: Xcode > target > Signing & Capabilities > Team, or `DEVELOPMENT_TEAM` in `project.yml` (left empty on purpose) and regenerate. Register the App ID `com.churchtvos.mac` with the **Push Notifications** capability (Xcode does this with automatic signing).
2. **Outside the Mac App Store (Developer ID)**: Product > Archive > Distribute App > Direct Distribution (Developer ID, hardened runtime is already on) > Upload for notarization, then export the stapled app and put it in a `.dmg` or `.zip`. Command line alternative: `xcrun notarytool submit App.zip --keychain-profile <profile> --wait` then `xcrun stapler staple "Church TV OS.app"`. Push needs a provisioning profile with the push entitlement for Developer ID too (Xcode creates it).
3. **Mac App Store**: Distribute App > App Store Connect, create the app record for `com.churchtvos.mac` first. Same notes as the iPhone app apply (billing stays on the website, no prices in the app; Delete account link is in Help and Settings).
4. **Push key**: the APNs key is shared with the iPhone app: see `supabase/functions/notify-offline/README.md`. The Mac topic is `com.churchtvos.mac` (the function picks it for rows with platform `macos`; set `APNS_TOPIC_MAC` if the id changes). No extra key is needed beyond enabling Push on the Mac App ID.
5. Archive builds are Release: they register push tokens as `production`; Debug as `sandbox`.

## Known limits and things to check on a real account
- Not verified without an account: real sign-in, the bridge against a real session, token adoption/Keychain write in a signed build, push registration and delivery, uploads and Finder drag and drop through the web view. WKWebView supports `<input type=file>` (via `NSOpenPanel`, implemented) and dropping Finder files onto page drop zones natively (the media page uses `dragover`/`drop` with `dataTransfer.files`), so no bridge was written; if a drop does not reach the page, the fallback is a native drop target on the web view that forwards file URLs through `NSOpenPanel`-style injection (not built).
- Links with `target=_blank` to the same site (for example the Help link, "/#songs") open in the default browser by design.
- Only the first four sections have Go-menu shortcuts; pages a person cannot see fall back to their first page.
