# NDI source (EXPERIMENTAL): contract

Status: experimental, off for every church. The NDI SDK licence for Android is unconfirmed (the licence says Android and
fixed-purpose devices need a commercial agreement with NDI). **Do not enable for customers. Never ship the `ndi` build to a store.**

This file is the contract between the database, the web dashboard, the TV app and the iOS editors. Source of truth in code:
`supabase/migrations/20261023000001_ndi_experimental.sql` (`ndi_check`), `dashboard/src/types.ts` (`NdiConfig`),
`dashboard/src/ndiLogic.ts`, `tv-app/.../NdiModel.kt`.

## 1. The feature flag

- Column `organizations.ndi_enabled boolean not null default false`.
- **Write:** platform admins only (RPC `admin_update_organization(p_org, ..., p_ndi boolean)`; a trigger also refuses any other writer).
  Every toggle is recorded in `admin_audit_log` (`action` = `ndi_enabled` / `ndi_disabled`, who, when). The web console
  (Admin, church detail, "Experimental features") has the switch and a licence warning.
- **Read:** any member of the church (`organizations` is readable by members, so the editors read `org.ndi_enabled`).
  iOS: select `ndi_enabled` with the organization row.
- **TV:** `device_state` includes `"experimental": {"ndi": true|false}`.
- **Editors must hide the option when the flag is false.** If the flag is false but a playlist or deck already contains an NDI
  entry, show it read-only with a note and let the user delete it (the server allows removal, refuses add or change).

## 2. JSON shape

Same fields in all places. The discriminator differs: Kids and Signage playlist items use `"type": "ndi"`, Slides deck slides use `"kind": "ndi"` (plus the usual `id`, optional `background` (ignored), `notes`).

```json
{
  "type": "ndi",
  "title": "Main camera",
  "source": "STUDIO-PC (Camera 1)",
  "address": "192.168.1.50:5961",
  "audio": false,
  "fit": "fit",
  "fallback": "message",
  "fallback_text": "Camera is offline, back soon",
  "max_wait_seconds": 15,
  "seconds": null
}
```

| Field | Type | Rules |
|---|---|---|
| `source` | string | Required, non-blank, max 200. The NDI source name exactly as NDI lists it, "MACHINE (Source)". |
| `address` | string or absent/null | Optional host or IP with optional `:port`, no spaces, max 255. For networks where discovery does not work. Editors should check `^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(:\d{1,5})?$` and port 1 to 65535. |
| `audio` | boolean | Default false. |
| `fit` | `"fit"` or `"fill"` | Default `fit` (whole picture, bars if shapes differ). `fill` crops to fill the screen. |
| `fallback` | `"skip"` or `"message"` | Default `skip`. What happens when the source is not available. |
| `fallback_text` | string | Max 200. Shown when `fallback` is `message`. Empty: the TV shows "Waiting for the live feed…". Omit when fallback is skip. |
| `max_wait_seconds` | integer 3 to 120 | Default 15. How long the TV waits for the source (first connect, and after a drop) before the fallback applies. |
| `seconds` | integer 1 to 86400 or null | Default null: until Next (Kids), until the loop moves on (Signage: the TV treats null as 30 s), Slides: until Next. |
| `title` | string | Label for lists and the remote. Optional. |

Rejected by the database (`ndi_check`) with a readable message: missing source, bad address, bad fit/fallback, wait outside 3 to 120,
seconds outside 1 to 86400, fallback text over 200.

## 3. Server rules

1. **Saving** (`playlists.items`, `signage_playlists.items`, `decks.slides`): a trigger refuses any NDI add or change for a church
   without the flag ("NDI sources are an experimental feature that is not enabled for this church"), and validates the shape
   when the flag is on. With the flag off, existing NDI entries may be deleted or left alone.
2. **Playing** (`device_state`, `kids_expand_items`, `deck_expand`): NDI items and slides are left out unless the church has the flag, so a stale item never plays.
3. Older TV apps decode unknown kinds as Unknown and skip them (decoders have a default deserializer). Nothing breaks.

## 4. TV app behaviour

- Two product flavors in `tv-app/app`: **`store`** (Amazon, Google Play: contains no NDI code or libraries; an NDI item is skipped,
  or shows its fallback message when `fallback` is `message`) and **`ndi`** (experimental, links the NDI SDK, `versionName` ends `-ndi`, shown as the screen's app version).
- Receive: find the source by exact name (case-insensitive second chance), or connect directly when `address` is set. Video is drawn into a
  TextureView (rotates on portrait screens like other slides). Audio is optional (stereo 16-bit). A dropped source is retried by NDI itself;
  frames resuming bring the picture back and hide the message.
- Fallback: nothing for `max_wait_seconds` then `skip` moves to the next slide, `message` shows `fallback_text` until the source returns, the slide's `seconds` ends or someone presses Next.
- Remote status: the screen's now-playing label gets a note, e.g. `NDI: Main camera, live` / `connecting` / `unavailable`.
- NDI trademark notice appears in Settings in the ndi build.

## 5. iOS editors (to do by the iOS agent)

Add an "NDI source (experimental)" option to the playlist item picker and the deck slide picker, shown only when `organizations.ndi_enabled`
is true. Fields as in section 2 with the same validation. Preview: a placeholder only (no NDI preview on iOS/web). Help text: same LAN, discovery
does not cross VLANs/subnets (type the address then), NDI|HX recommended on Wi-Fi, experimental TV build only.

## 6. Building the `ndi` variant

The NDI SDK is confidential and is NOT in git. Accepting the NDI licence is Keith's decision.

1. Install the Android NDK and CMake (Android Studio, SDK Manager, SDK Tools). Neither is installed on this Mac today.
2. Run the installer yourself (`vendor/ndi-installer/Install_NDI_SDK_v6_Android.sh`, it asks you to accept the licence) in a scratch folder.
3. Copy `NDI SDK for Android/include/` to `tv-app/app/ndi-sdk/include/` and `NDI SDK for Android/lib/` to `tv-app/app/ndi-sdk/lib/` (needs `arm64-v8a/libndi.so` and `armeabi-v7a/libndi.so`). `tv-app/app/ndi-sdk/` is gitignored.
4. `cd tv-app && export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`
5. `./gradlew assembleNdiDebug` (installs as `com.churchtvos.tv.dev`) or `./gradlew assembleNdiRelease` (signed with the release key; sideload only).
6. Normal store builds: `./gradlew assembleStoreRelease bundleStoreRelease`. Without the SDK folder the ndi variants do not exist, so `assembleRelease` can only build the store flavor.
7. Compile/test the Kotlin side without the SDK: `./gradlew -PndiCompileOnly=true testNdiDebugUnitTest` (result has no NDI libraries).

The Android installer does contain Android binaries: `lib/{arm64-v8a,armeabi-v7a,x86,x86_64}/libndi.so` and the C headers in `include/`.
`tv-app/ndi-native/src/main/cpp/ndi_jni.cpp` was written against the v6 C API from knowledge and has not been compiled against the real headers.
