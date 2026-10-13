# Church TV OS: Handoff Brief

Starting point for the new chat. Written 2026-10-13 at the end of the Forward Kids TV build.

## Decisions (from Keith)

| Topic | Decision |
|---|---|
| Name | **Church TV OS** |
| Ownership | **Keith's personally.** Built and run on Keith's personal accounts (keith@sparrownest.com), not Forward Church's. Forward Church becomes customer #1. |
| App ID | **`com.churchtvos.tv`** (based on the domain `churchtvos.com`). Permanent once published to a store. |
| Modules | **Kids** (the existing curriculum player, keep as is) and **Signage** (new). More can be added later. |
| Mixed TVs | **Yes.** A TV can switch between modules on a schedule, e.g. Signage on weekdays and Kids on Sunday. |
| Orientation | Landscape **and portrait** supported, set per screen. |
| Platforms | **Fire TV first**, then Google TV / Android TV (same Android app), then Roku (a separate app written in Roku's own language). |
| Pricing | **Per module + per TV.** Bundled packages later. Forward Church on a free internal plan. |
| Rollout | **Hold off** installing Forward Kids TV on more TVs until Church TV OS replaces it. |

## Accounts (personal, keith@sparrownest.com)

Claude can't create accounts or enter passwords, so Keith signs up for these himself.

**Done (2026-10-13). Keith will give the details below in the first message of the new chat:**
- [x] Domain: **churchtvos.com** registered. Registrar: ______. DNS points to Netlify once the site exists.
- [x] **Supabase**: organization and project "Church TV OS". Project URL: ______. Publishable key: ______. *(Never paste the secret / service_role key into chat.)*
- [x] **GitHub**: private repo. URL: ______.

**In progress:**
- [ ] **Netlify**: account under keith@sparrownest.com. Then Claude runs `netlify login` (Keith approves in the browser), creates the site, and connects churchtvos.com.
  - **Watch out:** new Netlify teams may turn on **Team protection** (visitor access) by default. That's what hid forward-kids-tv.netlify.app behind a Netlify login. Keith turns it off under Project configuration → Access & security → Visitor access.
  - **After the site exists:** set the Supabase **Site URL** and redirect URLs to the dashboard's address (e.g. `https://app.churchtvos.com`), so sign-up emails link to the right place.
  - **Before the Kids module plays YouTube:** update the TV app's YouTube embed origin to the new domain. Today it's hard-coded to forward-kids-tv.netlify.app in `YouTubeSlide.kt`.

**Later phases:**
- [ ] **Stripe**: subscriptions (when we reach the commercial phase).
- [ ] **Amazon Developer**: free; Fire TV Appstore and Live App Testing.
- [ ] Later: **Google Play** ($25 one-time), **Apple Developer** ($99/yr for the iPhone app), **Roku Developer** (free).
- [ ] Optional: Cloudflare R2 for video storage (no download fees).
- [ ] Recommended: a short written note with Forward Church leadership confirming Church TV OS is Keith's and that Forward Church uses it as a customer. Parts of the prototype were built on church accounts and tested on church equipment.

## What already exists (Forward Kids TV), the starting point

Code lives in `../forward-tv/`. **Leave it alone.** It's Forward Church's working system until the cutover. Copy it into `church-tv-os/` as the starting point rather than editing it in place.

- `forward-tv/tv-app/`: Fire TV app, written in Kotlin with Jetpack Compose for TV and Media3 (ExoPlayer). App ID `ca.forwardchurch.tv`.
  - **Pairing:** 6-character code. The TV polls Supabase's `device_state` function every 30 seconds.
  - **Offline:** caches media and its last-known schedule.
  - **Slides:** countdown, image, video, lyrics, and YouTube (IFrame player in a WebView; see the black-screen fix notes in `YouTubeSlide.kt`).
  - **Auto-launch** on boot and wake, only when paired.
  - **Signing:** signed with `tv-app/keystore/` (Forward Kids TV key; Church TV OS gets its own new key).
- `forward-tv/dashboard/`: Vite + React + TypeScript + supabase-js, with resumable uploads.
  - **Pages:** Schedule, Playlists, Media, TVs, Sites & Rooms, Staff.
  - **YouTube streams picker** through `/api/youtube` (a Netlify function).
  - **Hosting:** forward-kids-tv.netlify.app.
- `forward-tv/supabase/schema.sql`: sites, rooms, staff, media, playlists, schedules, devices, the device functions, and row-level security rules. **Single church only.**
- `forward-tv/brand/`: Forward Kids branding plus the app tile and icon generator.
- **Test TV:** AFTTI43 (43" Fire TV, Fire OS 7) at 172.16.51.189:5555.

### Lessons worth keeping
- **YouTube in a WebView:** the video sits on a layer *behind* the window. The window background, the WebView and the page body must be transparent while it plays, and nothing from Compose may be drawn on top (stale pixels never clear). Base URL must be a real https origin, or YouTube refuses to play.
- **Fire TV launcher icons:** the launcher caches an app's icon from its first install forever, even through reinstalls. Get the Church TV OS icon right before the first install.
- **Amazon re-signs Appstore apps** with its own key, so sideloaded installs can't update to the store version. Switch TVs to the store build before deploying widely.
- **Auto-launch** must be an opt-in setting for Appstore approval. Look into the **Amazon Signage** program (Signage Stick) for always-on signage.

## Target architecture

### Back end (new Supabase project, built for many churches)
- **`organizations`:** one per church, holding name, branding (logo, colours) and Stripe customer.
- **`memberships`:** user ↔ organization. Each has a role (`owner`, `admin`, `editor`, `operator`), module access (`kids`, `signage`, …) and site scope (all sites or a list).
- **`sites` → `locations`:** rooms, lobbies, hallways.
- **`screens`:** each TV. Holds pairing info, location, **orientation** (landscape, portrait, portrait-flipped), last seen and app version.
- **`screen_schedules`:** which **module** a screen runs at which times (this is what makes mixed TVs work), plus a default module.
- **Kids tables:** media, playlists, schedules, carried over from today, scoped by organization.
- **Signage tables:**
  - **Content:** images, videos, slideshows with per-item durations.
  - **Playlists.**
  - **Recurring time slots** per screen or **screen group**.
  - **Default content.**
  - **"Black screen when nothing is scheduled".**
  - Later: "push now" overrides, split layouts.
- **Billing tables:** subscriptions and entitlements per organization per module, with a **TV-count limit**. Enforced on the server: pairing is blocked above the limit, and an unpaid module switches off after a grace period.
- **Security:** row-level security on everything, keyed by organization and membership.

### TV app (`com.churchtvos.tv`)
- One app with a **module switch**: it asks the server which module to run right now, then hands off to the Kids player, the Signage player or a black screen.
- **Orientation** comes from the screen's settings, so the content rotates for portrait-mounted TVs.
- **Offline caching** for both modules.
- **Demo mode** for app-store reviewers.
- **Auto-launch** as an on/off setting.
- **Per-church branding** on the pairing and home screens (no Forward branding baked in).

### Web dashboard
- **Organization switcher** for people in more than one church.
- **Modules** in the navigation, based on what each person has access to.
- **Works on a phone** first (can be added to the iPhone home screen), then a native iPhone app later.
- **Self-serve sign-up and billing** come in the commercial phase.

## Phases
1. **Foundation:**
   - New accounts, the multi-church back end, roles and module access.
   - Rename everything; the TV app gets the module switch and orientation support.
   - Kids works exactly as it does today.
   - Move Forward Church's data over, then re-pair the TVs once.
2. **Signage, first version:**
   - Image, video and slideshow content.
   - Recurring schedules.
   - Black screen when idle.
   - Screen groups and portrait support.
3. **Phone-friendly dashboard,** then the native iPhone app (sees TV status, starts and stops rooms, pushes messages, uploads from the camera roll).
4. **Planning Center:** each church connects its own account through Planning Center's official sign-in. Calendar feeds Signage; Services plans and media feed Kids. Needs a Planning Center developer app registration.
5. **Commercial:**
   - Stripe per module + per TV, with trials.
   - Self-serve sign-up and per-church branding.
   - Privacy policy and terms.
   - Amazon Appstore listing (Live App Testing first for Forward Church), then Google Play and Roku.
