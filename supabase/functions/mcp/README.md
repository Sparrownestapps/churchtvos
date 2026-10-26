# mcp: Church TV OS MCP server (hosted)

Lets an AI assistant (Claude, etc.) run a church's screens on the signed-in person's behalf: Signage graphics and runs, Kids playlists and
schedules, Slides decks and schedules, live control, and undo.

Endpoint: `https://gqkefjngblgomuovaivj.supabase.co/functions/v1/mcp`

## Tools (31)
| Area | Tools |
| --- | --- |
| Start / media | `list_targets` (churches, sites + local time, rooms, screens), `list_media`, `upload_image` (base64 or https link, ≤10 MB), `request_upload` + `check_upload` (videos/big files via a link to app.churchtvos.com/upload) |
| Signage | `schedule_signage` (one or many graphics or a playlist; one date, or weekly days with optional start/end dates), `list_signage_playlists`, `list_signage_schedule`, `cancel_signage` |
| Kids | `list_kids_playlists`, `get_kids_playlist`, `save_kids_playlist`, `schedule_kids`, `list_kids_schedule`, `change_kids_schedule` (remove, delete a series, or skip/swap/restore one date) |
| Slides | `list_decks`, `get_deck`, `save_deck`, `list_themes`, `search_songs`, `schedule_slides`, `list_slides_schedule`, `change_slides_schedule` |
| Control | `play_now`, `stop_playing`, `show_message`, `list_screen_rules`, `set_screen_module`, `remove_screen_rule` |
| Safety | `list_activity`, `undo_change` |

## Safety rules built in
- **Preview, then confirm.** Every tool that changes something returns a preview first (what, where, day/date, local times, conflicts, warnings).
  It only acts when called again with `confirm: true`, and the server instructions tell the assistant to get the user's yes first.
- **Same permissions as the person.** Sign-in is Supabase Auth's OAuth 2.1 server; every query runs with the person's own token, so row-level
  security applies. Owners/admins only for screen rules, editors for content, and so on. No service-role key is used.
- **Service guard.** Kids and Slides changes that would affect a room now or in the next 30 minutes are refused unless the assistant passes
  `during_service_ok` (meant for when the user clearly asked).
- **Dashboard slots are protected.** `cancel_signage` only removes assistant-made slots unless `include_regular` is passed.
- **Undo.** Every change is written to `mcp_activity` with the rows it touched; `undo_change` reverses it.
- **Module warnings.** A screen only shows a module while its rules say so; previews warn when they won't, and say what the screen shows
  outside the window (its default content, or blank when nothing is scheduled).

## How signage date ranges work
`schedule_signage` creates a signage playlist and one `signage_slots` row per screen. One-off slots get priority 100, weekly runs 50, so both win
over everyday slots (0). Slots now have `start_date` / `end_date`; the database function `device_state` only hands a TV the slots whose dates
include today in the site's time zone, so no TV app update is needed. Overnight windows are two slots (slots can't cross midnight).

## One-time setup (Keith)
1. Apply the migration `supabase/migrations/20261026000001_dated_signage_slots.sql` (dated slots, `device_state` date filter,
   `mcp_activity`, `mcp_upload_requests`).
2. Supabase dashboard > Authentication > **OAuth Server**: enable it, set **Authorization Path** to `/oauth/consent`, turn on
   **Allow dynamic client registration**. Authentication > URL Configuration > **Site URL** must be `https://app.churchtvos.com`.
3. Deploy the dashboard (it has `/oauth/consent` and `/upload`) and the function:
   `supabase functions deploy mcp --no-verify-jwt`
4. Optional, tidies expired assistant-made slots daily:
   `select cron.schedule('purge-mcp-slots', '15 4 * * *', $$select public.purge_expired_mcp_slots()$$);`
5. Connect: in Claude, Settings > Connectors > Add custom connector > the endpoint URL. Sign in and press Allow.

## Tests
`node supabase/functions/mcp/tests/test.mjs` runs every tool end to end against an in-memory database (Node 22.18+; no packages, no network).
It checks logic, not row-level security; test permissions against the real project with a non-admin account.

## Things to try
- "Here's the Youth Night poster. Put it on the lobby screen this Friday from 8 to 10pm."
- "Show these two images every 10 seconds Monday to Friday from 9am to 6pm on the lobby TVs."
- "Make a Kids playlist with a countdown to 9:30, the week 2 video and Way Maker, and schedule it every Sunday 9–12 in the Kids Room."
- "Make a welcome deck and put it up in the Auditorium on Sunday from 9:30 to 10:00."
- "Skip next Sunday's Kids schedule." / "Undo that."
