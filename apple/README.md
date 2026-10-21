# Church TV OS for Apple devices

- `ChurchTVCore/` Swift package shared by every Apple app: models, Supabase wrapper (`SupabaseService`), `MockService` (demo mode), formatting, unit tests.
- `ChurchTVEditors/` Swift package with the SwiftUI content editors (Create section, playlist/deck/theme editors, scheduling sheet, media/song pickers, UI kit). iOS 17 + macOS 14, depends only on ChurchTVCore. Used by the Remote app; the Mac app can import it.
- `ChurchTVRemote/` the iPhone and iPad app (SwiftUI, bundle id `com.churchtvos.remote`, name "Church TV OS Remote"). `project.yml` is the XcodeGen spec; `ChurchTVRemote.xcodeproj` is generated from it and also checked in.
- `ChurchTVMac/` the Mac app (native SwiftUI with a web fallback pane, bundle id `com.churchtvos.mac`, name "Church TV OS"). See "Mac app" below.
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

Adding Swift files: XcodeGen includes everything under `App/` and `Tests/`. Without XcodeGen run `python3 sync_xcodeproj.py` in `ChurchTVRemote/` (adds the new files to the checked-in `.xcodeproj`, idempotent). Regenerate the project after changing `project.yml`: `brew install xcodegen` (or build it from source: github.com/yonaskolb/XcodeGen) then `xcodegen generate` in `ChurchTVRemote/`.

## Signing team
`DEVELOPMENT_TEAM` is empty on purpose. Set it in Xcode (target > Signing & Capabilities > Team) or in `project.yml` under `settings.base.DEVELOPMENT_TEAM` and regenerate. The Push Notifications capability needs a real team; `aps-environment` is `development` in `Resources/ChurchTVRemote.entitlements` (Xcode switches to production when archiving). Debug builds register push tokens as `sandbox`, release builds as `production`.

## Tests
```
cd apple/ChurchTVCore && swift test                      # 55 unit tests (incl. Mac support logic and content models)
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

# Build 2 architecture (content editing on the phone)

Build 2 (CURRENT_PROJECT_VERSION 2) adds a **Create** section: Kids playlists, Signage playlists, Slides decks and themes. Stage 1 (this) is the shared foundation; stages 2 and 3 plug editors into it.

## Core (ChurchTVCore/Sources/ChurchTVCore/Content, all additive)
- `RawJSON.swift`: `RawJSON`, `RawObjectCodable`, `ContentJSON` coders. **Decode content with `ContentJSON.decoder()`, never `ChurchJSON.decoder()`** (its snake_case conversion would rename keys inside JSON columns). Every model keeps the keys it does not understand in `extra` and writes them back; unknown item types, slide kinds and background types survive whole.
- `PlaylistItems.swift`: `PlaylistKind` (.kids/.signage, `itemTypes`), `PlaylistItem` (struct with stable `uid` and `content: .video/.image(MediaClip) .countdown(CountdownItem) .lyrics(LyricsItem) .youtube .sign .stream .unknown`), `PlaylistItem.new(_:kind:)` mirrors the website's Add buttons, `.problem` is the save validation text.
- `Countdown.swift`: `CountdownSettings` (shared by Kids items and deck slides; `.new`, `setMode`, `setAudio`, `.problem`), `CountdownAudio`.
- `DeckSlides.swift`: `DeckSlide` (id, background, notes, `content: .text/.media/.song/.countdown/.stream/.blank/.unknown`), `DeckSlide.new(_:existing:)`, `.problem`, `.cleaned()`.
- `Theme.swift`: `SlideBackground` (flat struct, `kind` color/gradient/image/video), `ThemeConfig`, `SlideTheme`, `ThemePreset.all`, `ColorTools`.
- `Rows.swift`: `Playlist` (both tables), `SlideDeck`, write payloads, **drafts** `PlaylistDraft` / `DeckDraft` (client-made `id`, `isNew`, `problem`, `cleaned()`), `ScheduleTarget` (.deck / .playlist).
- `Songs.swift`: full `Song`, `SongSection`, `SongExpander.expand` (port of expandSong). `Media.swift`: `MediaItem`, `MediaLibrary` (folders, breadcrumb, search, counts). `SlideRender.swift`: port of render.ts (`ResolvedTheme`, `BackgroundResolver`, `PreviewFrame`, `SlideRender.frames/planText/fitScale`), `DeckOutline` / `PlaylistOutline` (labels exactly like the TV app). `ContentPermissions.swift`: role/module/site rules, `ChurchAccess.showsCreateSection`.
- `ContentService.swift`: `ContentService` protocol (ChurchService extends it; defaults throw, so Mac keeps compiling). `SupabaseService+Content.swift` real tables; `MockService+Content.swift` + `MockContent.swift` in-memory demo content (2 Kids, 2 Signage, 2 decks with every slide kind, 2 themes, 5 songs, media with folders; demo files use `demo:` URLs drawn as gradients). Server refusals ("is used in...", "used by a repeating schedule") pass through as `ChurchError`. Demo: deleting the Sunday deck or the Week 3 playlist is refused like the server does.

## App (ChurchTVRemote/App)
- `Create/ContentModel.swift` (`model.content`): lists, songs, sites, themes, media libraries, `save(draft, kind:)`, `save(deckDraft)`, `save(theme)`, duplicate/delete. **Editors save only through these** (they validate with `problem`, call the service, keep lists in sync and throw a `ChurchError` with text safe to show).
- `Create/CreateView.swift`: `CreateRoot` (own NavigationStack), segmented Kids/Signage/Slides (only modules the member may edit), Decks/Themes, '+' (name prompt then editor), swipe duplicate/delete/schedule, pull to refresh. Shown only when `model.canCreate` (owner/admin/editor with a live module); tab on iPhone, sidebar entry on iPad.
- `Kit/`: `MediaPickerView(module:kinds:selectedId:onSelect:)`, `SongPickerView(selectedId:onSelect:)`, `ColorRow` / `ColorSwatches` / `OptionalColorRow`, `CountdownFieldsView(settings:module:)` (put inside a Form), `SlidePreview` (frame or deck slide, 16:9 / 9:16, `live` video), `SlidePreviewCard` (both shapes + stepper), `PlaylistItemPreview`, `MediaThumbnail`, `KitGalleryView` (DEBUG: launch `-demo -kitgallery -kitpage slides|items|controls`). `AddMediaView` gained optional `fixedModule`, `initialFolder`, `kinds` (`.audio` adds "Choose audio files" from Files), `onUploaded`.

## What the next agents implement (replace the placeholder BODY in `Create/EditorPlaceholders.swift`, keep names and initialisers)
1. **Playlist editor agent**: `PlaylistEditorView(kind: PlaylistKind, playlist: PlaylistDraft)`. Items per `kind.itemTypes`, add/reorder/duplicate/delete, per-type forms (media via MediaPickerView, lyrics typed or SongPickerView + show_title, countdown via CountdownFieldsView, youtube, stream, sign with ColorRow), `PlaylistItemPreview`, site scope picker (`model.content.selectableSites`, "All sites" only when `model.content.hasAllSites`).
2. **Deck/theme editor agent**: `DeckEditorView(deck: DeckDraft)` and `ThemeEditorView(theme: SlideTheme)`. Slide strip with `SlidePreviewCard`, slide forms per `DeckSlide.Content`, background picker (`SlideBackground`), theme choice, loops; theme fields of `ThemeConfig`, presets, name uniqueness errors from the service.
3. **Scheduling agent**: `ScheduleSheet(target: ScheduleTarget)`; already presented from the Create swipe actions and the Play now sheet. Locations: `model.content.locations`, `Location.uses(target.module)`; add `ContentService`-style methods for schedules in Core.

## Conventions
- Draft pattern: `@State var draft` copied from the row plus `let original`; unsaved changes = `draft != original`; confirm on back/dismiss when true; `interactiveDismissDisabled(draft != original)` for sheets. After a successful save set `original = saved draft`.
- New things have a device-made `id` and `isNew == true`; the service inserts with that id (`createX`), existing ones update. Every insert sets `organization_id`; `site_id` is always sent (null = all sites).
- Errors: `do { try await model.content.save(...) } catch { errorText = Formatting.message(for: error) }` shown in an alert or `Banner(style: .error)`; never swallow server messages.
- Keep editing the typed model; never rebuild items from scratch (unknown keys live in `extra`).
- Permissions: `ContentPermissions` / `ChurchAccess.editableModules`. Admins and owners are treated as having every module and all sites (database `in_site_scope`), even if `memberships.site_ids` is set.
- Adding files: `python3 sync_xcodeproj.py` (or XcodeGen).

# Mac app (`ChurchTVMac/`)

Native SwiftUI app (macOS 14+, bundle id `com.churchtvos.mac`, team 4K3495W2H2). The website is only a **fallback pane** for sections that are not native yet (today: "Sites & Locations"). Reuses `ChurchTVCore`, `ChurchTVEditors` and `ChurchTVCalendar`.

## What is in it
- **Sign in**: email + password with the same Supabase account as the website (`NativeSignInView`), "Try the demo" (MockService). The session lives in the Keychain (supabase-swift) and the SDK refreshes it (`autoRefreshToken: true`). The old website-to-menu-bar session bridge was removed: the fallback web view keeps its own, separate sign-in. Sign out also clears the web view's sign-in.
- **Window**: `NavigationSplitView`. Sidebar groups: Operate (Screens, Remote, Calendar), Library (Media, Songs), Create (Kids playlists, Signage playlists, Slides decks, Themes), Manage (People, Settings, Sites & Locations = web fallback), Admin (platform admins only). Church switcher on top, account menu at the bottom, offline-TV count badge on Screens. Visibility follows the website's `buildNav` (`AppSection.isVisible`: role, live modules, `ContentPermissions`, `rpc('is_platform_admin')`). Window frame is remembered (`WindowFrameSaver`), last section is remembered, light/dark follow the system, Dock badge = number of offline TVs.
- **Menus**: File (Pair a TV ⌥⌘N, Refresh ⌘R, Open Dashboard in Browser ⇧⌘O), View (sidebar), Go (⌘1...⌘0 = the visible sections), Remote (Next ⌥⌘→, Previous ⌥⌘←, Blank ⌥⌘B, Stop ⌥⌘., Send Message ⌥⌘M), Window (Show Church TV OS Window ⌥⌘0, Show TV Status ⇧⌘T), Help. The menu bar extra and `TV Status` window work as before; Preferences (⌘,) has menu bar/Dock/login/alerts/demo.
- **Screens** (`ScreensSection`): list with status and what is playing, detail with now playing, rename, location, orientation, default module, group, signage default playlist, autoplay, unpair (confirm), "Pair a TV" sheet (code, location, name; plan limit message from `claim_screen`). Owners and admins edit; others see details.
- **Remote** (`RemoteSection`): TV picker, previous/next, blank, stop, start a deck or playlist (duration), send message, slide list (double-click = jump). Same `send_screen_command` protocol as the iPhone app.
- **People** (`PeopleSection`): list, invite, change role/modules/sites, remove (not yourself). Mirrors PeoplePage.tsx exactly (insert/update/delete on `memberships`, same validation texts, owners/admins always have everything). Owners/admins only.
- **Settings** (`ChurchSettingsSection`): church name, logos (upload to `media/<org>/branding/`), colours, splash, per-module looks (Kids/Signage/Slides, anything unset inherits), YouTube channel id, plan (read only). Branding is edited as raw JSON so unknown keys survive a save.
- **Create** (`ContentSections`): the editors package. `MenuModel` is the `ContentHost` (service, church, screens, Play now through the remote protocol via `EditorPlayNow`). `CreateRoot(initialSection:)` pins each sidebar entry to Kids, Signage, Slides decks or Themes.
- **Calendar**: `ChurchTVCalendar`. Tapping a block opens the real `ScheduleSheet`; "+" or dragging out a time asks which deck/playlist to schedule, then opens the `ScheduleSheet` (it picks the room and time itself, the dragged time is not passed on).
- **Media** (`MediaSection`): Kids/Signage/Slides libraries, folders (breadcrumb, create, rename, move, delete moves contents up), search, rename/move/delete files (also multi-select with Cmd/Shift-click), drag a file onto a folder to move it, Finder drag-and-drop and "Add files" (⌘U) upload with per-file progress. Delete-protection and duplicate-folder errors from the server are shown in plain alerts ("... is used in: ... Remove it from those playlists first."). Upload is the standard SDK upload (stage-based progress, not resumable or background: Core has no resumable upload yet). Warning chip above 200 MB.
- **Songs** (`SongsSection`): list/search, editor (title, authors, CCLI, copyright, lines per slide, sections, custom order, live slide preview), duplicate, delete (usage errors shown), import by file picker, Finder drop or pasted text. Parsers are the Swift port of `songParsers.ts` (`ChurchTVCore/Library/SongParsers.swift`, `SongParserTests`): SongSelect `.usr`, ChordPro, plain text; duplicate titles can be skipped, replaced or added as a copy.
- **Admin** (`AdminSection`, platform admin only): churches table with stats, search, bucket filter and sortable columns; church detail with plan presets and per-module entitlement editor (the "grants"), live preview, suspend/reactivate with reason, mark reviewed, experimental NDI switch, internal notes, people (add/remove), screens, usage, activity; global Activity log with filters and paging. Deleting a church is intentionally left to the website.

## Core additions for the Mac app (`ChurchTVCore`)
`Operations/` (`OperationsService`, models, rules, `SupabaseOperations`, `DemoOperations`), `Library/SongParsers.swift`, `Admin/AdminLogic.swift`. Three protocols (`OperationsService`, `LibraryService`, `AdminService`) with throwing defaults; `SupabaseService` and `MockService` conform in extensions, so `Service.swift` and `MockService.swift` were not touched. Demo state that MockService cannot hold lives in `DemoOpsStore` (screen edits are an overlay applied by `overlayScreens`).

## Build and run
```
cd apple/ChurchTVMac
./build.sh                       # ad-hoc signed local build -> build/Build/Products/Debug/Church TV OS.app
open "build/Build/Products/Debug/Church TV OS.app" --args -demo      # demo data, no account needed
python3 sync_xcodeproj.py        # after adding or removing Swift files under App/ (XcodeGen is not required)
```
`build.sh` signs ad hoc with `Resources/ChurchTVMac-LocalTest.entitlements` (sandbox, network, user-selected files, Downloads, no push). With the team set (project.yml and the checked-in project use 4K3495W2H2) Xcode uses `Resources/ChurchTVMac.entitlements` (sandbox, network client, user-selected files read/write, Downloads, `aps-environment`; Hardened Runtime on). The Keychain needs no extra entitlement for the app's own items.
Debug launch arguments (all with `-demo`; `-demoadmin` makes the demo user a platform admin): `-section screens|remote|calendar|media|songs|kids|signage|slides|themes|people|settings|sites|admin`, `-mediamodule kids|signage|slides`, `-songpick`, `-personpick`, `-admintab activity`, `-adminopen <part of a church short name>`, calendar: `-calmode day|3day|week -caldate 2026-10-25 -callane <name> -calcreate`, `-url <website page>` for the fallback pane. Screenshots (`screenshots/mac-*.png`) are taken with `screencapture -l <window id>`.
In demo mode the sample TV code for "Pair a TV" is `DEM 123`.

## Signing, notarizing, distributing
1. Team 4K3495W2H2 is set. Register the App ID `com.churchtvos.mac` with Push Notifications (Xcode does this with automatic signing).
2. **Outside the Mac App Store (Developer ID)**: Product > Archive > Distribute App > Direct Distribution > notarize, staple, put in a `.dmg`/`.zip`. Command line: `xcrun notarytool submit App.zip --keychain-profile <profile> --wait` then `xcrun stapler staple "Church TV OS.app"`.
3. **Mac App Store**: create the app record for `com.churchtvos.mac` first; billing stays on the website (no prices in the app); Delete account is in Help and Preferences.
4. **Push**: shared APNs key, topic `com.churchtvos.mac` (see `supabase/functions/notify-offline/README.md`).

## Known limits and things to check on a real account
- Not verified without an account: real sign-in and Keychain persistence in a signed build, every write against the real database (screens, people, branding, media, songs, admin RPCs), file uploads (the Mac upload code path is only covered by the demo service), push delivery, the fallback web view's own sign-in.
- Finder drag-and-drop upload and song import by drop use SwiftUI `dropDestination(for: URL.self)`; they compile and the demo service path is tested, but the drop gestures were not driven by hand.
- Calendar: gestures and shortcuts of the calendar package are untested on the Mac by hand. Dragging out a range does not pass the time into the `ScheduleSheet`.
- "Open this church" from the Admin console is not built (a platform admin without a membership has no church to switch to in the Mac app); use the website for that and for deleting a church.
- The Create lists still say "Swipe a row to duplicate, schedule or delete" (editors package text); on the Mac use the context menu or the row buttons the list offers.
- A user who used the old session bridge must sign in once natively.

## Scheduling (build 2)
`ScheduleSheet(target:)` (`App/Create/Schedule/`): Kids playlists and Slides decks go to locations (one-off `schedules`/`deck_schedules` or weekly `kids_series`/`deck_series` with a rotation, loop/stop), Signage playlists go to screens or screen groups (`signage_slots`, optional priority = highest existing + 1). Wall-clock times are converted in the site's time zone (`SiteClock`, DST safe); the sheet shows the zone and highlights it when it differs from the phone. Core: `Content/ScheduleLogic.swift` (form, rows, expander, overlap hints), `ScheduleService.swift` (`ChurchService` now also extends `ScheduleService`, defaults throw), `SupabaseService+Schedule.swift`, `MockService+Schedule.swift`. Upcoming list reads the `*_series_occurrences` RPCs (14 days); "Skip next date" writes a `skip` exception. Debug launch args: `-schedule deck|kids|signage`, `-schedmode repeat`, `-schedpick`, `-schedscroll when|upcoming`.

## Editors package (`ChurchTVEditors/`)
The editors moved out of `ChurchTVRemote/App/Create` and `App/Kit` into the package (`Sources/ChurchTVEditors/{Create,Kit}`). Tests that cover them are in `ChurchTVEditors/Tests`; `swift test` in the package folder, `xcodebuild -scheme ChurchTVEditors -destination 'platform=macOS' build` proves the Mac build.
- **Host contract**: the editors read everything through `ContentModel` (SwiftUI environment: `.environment(contentModel)` once at the app root). `ContentModel(host:)` takes a `ContentHost` (service, church, screens, `loadPlayNow`, `loadSchedule`, `supportsPlayNow`, `playNowView`). The Remote's `AppModel` conforms (`App/EditorsBridge.swift`); a Mac host can leave the defaults (no TVs, no Play now).
- **Public API**: `ContentHost`, `PlayNowTarget`, `ContentModel` (init, `reset()`, `church`, `canAddMedia`), `CreateRoot`, `CreateView`, `CreateRoute`, `CreateSection`, `PlaylistEditorView`, `DeckEditorView`, `ThemeEditorView`, `ScheduleSheet`, `AddMediaView`, `MediaPickerView`, `SongPickerView`, `Banner`, `Haptics`, `KitGalleryView` (DEBUG). Everything else is internal.
- The Remote keeps thin aliases: `App/Create/CreateView.swift` (`CreateRoot`, `CreateView`) and `App/EditorsBridge.swift` (`Banner`, `Haptics`, `ScheduleSheet`, `AddMediaView`, `KitGalleryView`), so Remote files need no import. `PlaylistPlayNow.swift` and `DeckPlayNow.swift` stay in the Remote (they use its remote-control commands).
- Platform shims are in `Kit/Platform.swift` (colours, JPEG conversion, keyboard/capitalisation modifiers, EditMode stand-in on macOS, sheet sizing, Cmd+S / Esc shortcuts). On the Mac: forms use the grouped style, sheets have minimum sizes, pushed editors are capped in width, the deck and theme editors always use the wide strip + preview + form layout, Reorder buttons are hidden (drag rows), haptics are no-ops.
- `sync_xcodeproj.py` now also links the package and removes stale file references.

# Calendar (`ChurchTVCalendar/`, native week/day calendar)
- **Core** (`ChurchTVCore/Sources/ChurchTVCore/Calendar`): `CalendarService` (range reads `scheduleRange`, `listModuleRules`, row updates; implemented by `SupabaseService` and `MockService`), `CalendarEventBuilder` (Kids/Slides one-offs and `*_series_occurrences`, Signage slots, module switches, per-module style, locks from `CalendarPermissions`, lane = all / location / screen / group in the site's time zone), `CalendarSegments` (wall-clock day split, DST safe), `CalendarBands`, `CalendarEditPlanner` + `CalendarEditor` (move/resize -> rows; repeating occurrences offer "This date only" = skip exception + one-off, or "Whole series"; multi-day weekly rules offer all days / only this day), `CalendarLoader`.
- **Package** `ChurchTVCalendar` (iOS 17, macOS 14, depends only on Core, never on the editors): `CalendarModel` (@Observable), `ChurchCalendarView(model:callbacks:)`, `CalendarGeometry` (time<->y, 15 min snap, overlap columns). Callbacks: `onSelect(event)`, `onCreate(CalendarCreateRequest)`. iPhone/iPad: tap = select, tap empty = 1 h create, press-and-hold then drag = create / move, drag bottom handle = resize (UIKit `HoldDrag`, so scrolling still works); Mac: plain drag, arrows, T, Cmd-1/2/3.
- **Remote**: `App/Calendar/CalendarTab.swift` (iPhone: Today | Calendar segments in the Schedule tab; iPad: Calendar in the sidebar), `CalendarQuickAdd.swift`. Tap opens the existing `ScheduleSheet`. Launch args (DEBUG, with `-demo`): `-calendar -calmode day|3day|week -caldate 2026-10-25 -callane <name> -calquickadd`.

# PowerPoint, PDF and picture import (decks and Kids playlists)

Mirrors the website importer (`dashboard/src/importer/`, rules in `PPTX-IMPORT-CONTRACT.md`). Import button in the deck editor (next to Add slide) and the Kids playlist editor (not Signage), on iPhone, iPad and Mac; people without the Editor role or the module do not see it.
- Core (`ChurchTVCore/Import`, pure and tested in `ImportTests`): `ZipArchive` (stored and deflate via Compression, no zip64, size caps), `PPTXReader` (slide order, title/body rules, notes, pictures, media), `PDFRenderer` (CoreGraphics, long edge 1920, JPEG 0.9), `TextSlideRenderer` (Kids text slides drawn as pictures), `ImportSession` (preview entries, per-entry upload plan, file preparation), `ImportBuilder` (deck slides / Kids items, placement), `ImportSamples` (generated PDF/PPTX fixtures, also used by the debug screenshots).
- Editors (`ChurchTVEditors/Import`): `ImportButton`, `ImportSheet`, `ImportFlow` (3 uploads in flight, per-page errors, Stop keeps what is done, folder named after the file with " (2)" on clashes). Choose via the file importer or drop a file on the sheet.
- Limits: 150 pages per import, 150 MB per PDF/pptx, 50 MB per uploaded file. Tip shown: "In PowerPoint choose File > Export > PDF for an exact look."
- Debug launch arguments (with `-demo`, Slides or Kids editor open): `-importopen` opens the sheet, `-importdemo pdf|pptx|pictures` loads a generated sample.
