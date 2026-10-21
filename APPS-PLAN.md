# Plan: Church TV OS for iPhone and Mac

Written 2026-10-21. **Planning only, nothing is built.** Items marked **VERIFY** need checking against Apple's current rules or by a spike before we rely on them.

## 1. The full scope Keith wants
1. **iPhone app, first version:** a remote and status app. See which TVs are online, what each is showing, run a deck from the phone (next, back, jump, blank, start, stop), push a message, upload photos and video from the camera roll.
2. **Mac app, eventually:** everything the website does, as a native app, including making edits and scheduling (decks, themes, songs, media, calendar, screens, people, settings, and the admin console for Keith).
3. Later nice-to-haves already discussed: notifications when a TV goes offline, iPad support.

## 2. What we already have (so the apps do not start from zero)
- **One back end for everything:** Supabase (database, sign-in, file storage, row-level security). Every table the website reads and writes is reachable by an app signed in as the same user, with the same permissions. Roles already exist (owner, admin, editor, operator), and **operator** is currently read-only, which is exactly the role meant for remote control.
- **Business logic lives in the database:** repeating-schedule expansion, song expansion, deck expansion, delete protection, trial/suspend rules. Apps call the same RPCs; nothing needs rewriting per platform.
- **Apps share one data contract:** `dashboard/src/slidesTypes.ts` plus the SQL migrations.
- **Missing for a remote:** TVs only poll every 30 seconds and cannot receive commands or report what they are showing. That is the main new back-end work (section 4).

## 3. Technology choices (recommended)
- **SwiftUI multiplatform**, one codebase for iPhone, iPad and Mac, using the official `supabase-swift` SDK. Minimum OS: iOS 17 and macOS 14 (**VERIFY** the SDK's current requirements).
- A shared Swift package, **ChurchTVCore**: Codable models mirroring `slidesTypes.ts`, Supabase client and repositories, screen status/command types, formatting helpers, and a Swift port of `songParsers` and `expandSong` (so the Mac can import songs and preview slides).
- **Sign-in:** the same email and password as the website, kept in the Keychain; optional Face ID/Touch ID lock. New accounts are still created on the website. (Apple requires an in-app way to start account deletion if an app lets people create accounts; sign-up on the web only keeps us out of that, but link to the existing delete-account page.)
- **Billing stays on the web.** Do not show prices or purchase links inside the apps (Apple's in-app purchase rules). Apple has an exception for business-to-business services sold to organisations; **VERIFY** the current wording before shipping.
- **Apple accounts:** Apple Developer Program, US$99/year, in Keith's name. TestFlight for beta testers. Bundle ids proposal: `com.churchtvos.remote` (iPhone/iPad) and `com.churchtvos.mac` (Mac), or one multiplatform app id; decide before the first upload because ids are permanent.
- **Mac distribution:** Mac App Store, or a notarised direct download (no review, but requires Developer ID signing).

## 4. Back-end and TV work needed first (shared by phone and Mac)
All of this is also useful on the website (a "Control" page for operators).
1. **Commands to a screen.** Table `screen_commands` (id, screen_id, command, payload jsonb, issued_by, created_at, handled_at). Commands: `next`, `previous`, `jump {index}`, `blank {on}`, `stop`, `start {deck_id|playlist_id}`, `show_message {text, seconds}`. Row-level security: operators and above, for screens in their sites and with the module. Rate-limited.
2. **Status from a screen.** Table `screen_status` (screen_id, module, what is playing, slide index/count, label, playing/blank, updated_at). The TV writes it through a device-authenticated function every few seconds while playing and on every slide change. Phones and the website read it.
3. **How the TV hears commands.** Start with a short poll (every 1-2 seconds while a deck or playlist is playing, 30 seconds otherwise); move to Supabase Realtime (WebSocket) once proven, for near-instant response. A same-Wi-Fi shortcut (a tiny local server on the TV, found by Bonjour) is possible later but adds security work; defer.
4. **Push now / overrides.** A `screen_overrides` table so an operator can say "play this deck on this screen now until X" without editing the schedule; the TV applies it ahead of the schedule.
5. **Push message.** A quick sign (text, colour, duration) shown over whatever is playing, using the sign renderer already in the TV app.
6. **Notifications (later).** A `push_devices` table (APNs tokens), a Supabase Edge Function plus an APNs key (needs the Apple account) that sends "TV offline during a scheduled time" alerts; each person opts in.
7. **TV app 1.5.0**: command handling, status reporting, overrides, push message, and the new Settings diagnostics. Needs an Amazon and Google Play update.
8. **Permissions:** give the operator role real control (commands, push now, push message) but no editing; editors and above also control.

## 5. iPhone app phases
**Phase P1: status and remote (size: medium)**
- Sign in, choose church (organization switcher for people in more than one).
- Screens list: online/offline, location, module, what is playing now, slide x of y, last seen.
- **Remote** for one screen: big Next/Back, slide list to jump, Blank, Start/Stop, switch module or start a deck or playlist now, today's schedule for that screen. Landscape-friendly for use while running a service.
- Done when: an operator on a phone runs a Slides deck on a TV with under a second or two of delay and sees the current slide update.

**Phase P2: content from the phone (size: medium)**
- Push a message to a screen or group.
- Upload photos and video from the camera roll to a module's media library (resumable background uploads to Supabase storage, folder choice, progress), and "add to a slide or playlist" afterwards.
- Quick look at the calendar for today and this week (read-only), tap to open the website for edits.

**Phase P3: notifications and polish (size: medium)**
- Offline alerts, a Home Screen widget with TV status, Live Activity while a deck is running (**VERIFY** worth it), iPad layout.

## 6. Mac app phases
Strategy (recommended): **hybrid, then replace screen by screen.** A full native rebuild of every website page is a large job, and the website keeps changing. Start with something useful quickly and replace pieces with native versions in the order that gains the most.
**Phase M1: Mac app shell (size: small to medium)**
- A native Mac app that embeds the website dashboard in a web view (one sign-in), with native menu bar, window management, keyboard shortcuts, Dock badge, notifications, drag-and-drop files from Finder into the media library (bridged to the web uploader), and a **menu bar item** with live TV status and quick remote controls (reusing Phase P1 code). Gives "the website as an app" quickly.
**Phase M2: native operations (size: medium)**
- Native Screens, Remote, status, People, Settings and branding using ChurchTVCore. Admin console (Keith) as native tables.
**Phase M3: native content (size: large)**
- Media library with folders and Finder drag-and-drop with resumable uploads; Songs library with file import (drag SongSelect and text files, ChordPro); themes.
**Phase M4: native scheduling (size: large)**
- Week calendar with drag to create, move and resize across Kids playlists, Slides decks, Signage slots and module switching, repeating series with rotation and exceptions, multi-screen scheduling (a native port of the web calendar; the database does the heavy logic).
**Phase M5: native deck editor (size: largest)**
- Slide strip, per-slide editors, backgrounds, themes and live preview. Three renderers must agree (TV in Compose, web preview in React, Mac in SwiftUI). Mitigation: keep the web preview component in a web view inside the native editor so there is still one preview implementation; replace it only if needed.
At every step the website stays the source of truth for features: anything not yet native opens in the embedded web view.

## 7. Risks and unknowns
- **Remote latency and reliability** depend on the TV polling or Realtime; verify on the Fire TV hardware before promising "instant" (spike first).
- **Many TVs polling every second** will not scale forever; Realtime or a local shortcut is the answer once there are many churches.
- **Apple review for a business tool** with web-only sign-up and billing: write clear reviewer notes and provide a demo church account; follow the rules in section 3. **VERIFY** current guidelines at submission time.
- **Renderer parity** (see M5).
- **Workload:** the Mac app's later phases are months of work; the iPhone remote can ship much sooner.
- **Fire TV only runs Android apps:** none of this changes the TV side except the 1.5.0 update.

## 8. Decisions needed before building
1. **Order:** back-end/TV remote work and the iPhone remote first (recommended), then the Mac shell, then native Mac pieces.
2. **Mac strategy:** hybrid (web view first, then native pieces) as recommended, or fully native from the start?
3. **Apple Developer account:** create it now (Keith, personal) so the app ids and TestFlight are ready.
4. **Who can use the remote:** operators and above only, or also viewers?
5. **iPad:** include in the iPhone app from the start (SwiftUI makes it cheap) or later?
6. **Notifications:** wanted in the first release or later?
7. **App names and ids:** "Church TV OS Remote" and "Church TV OS" for the Mac app, with the ids above?
8. Whether the website gets the same Control page (recommended; the back end is shared).
