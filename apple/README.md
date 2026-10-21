# Church TV OS for Apple devices

- `ChurchTVCore/` Swift package shared by every Apple app: models, Supabase wrapper (`SupabaseService`), `MockService` (demo mode), formatting, unit tests.
- `ChurchTVRemote/` the iPhone and iPad app (SwiftUI, bundle id `com.churchtvos.remote`, name "Church TV OS Remote"). `project.yml` is the XcodeGen spec; `ChurchTVRemote.xcodeproj` is generated from it and also checked in.
- `screenshots/` simulator screenshots taken in demo mode.

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
cd apple/ChurchTVCore && swift test                      # 25 unit tests
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
