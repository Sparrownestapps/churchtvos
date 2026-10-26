# mcp: Church TV OS MCP server (hosted)

Lets an AI assistant (Claude, etc.) schedule signage for a church on the signed-in person's behalf.
Endpoint: `https://gqkefjngblgomuovaivj.supabase.co/functions/v1/mcp`

Tools: `list_targets`, `list_graphics`, `upload_graphic`, `schedule_graphic` (preview first, then `confirm: true`), `list_scheduled`, `cancel_scheduled`.

How a one-off graphic works: `schedule_graphic` creates a one-image Signage playlist and a **dated** Signage slot (`signage_slots.start_date/end_date`, priority 100)
for each screen. The database function `device_state` only hands a TV the slots whose dates include today in the site's time zone, so no TV app update is needed.
The screen must be running Signage at that time (the preview warns if its schedule says Kids/off).

Security: sign-in is Supabase Auth's OAuth 2.1 server; the person approves each assistant on `app.churchtvos.com/oauth/consent`. All database calls use the
person's own token, so row-level security limits the assistant to what that person can do. The function never uses the service-role key.

## One-time setup (Keith)
1. Apply the migration `20261026000001_dated_signage_slots.sql`.
2. Supabase dashboard > Authentication > **OAuth Server**: enable it, set **Authorization Path** to `/oauth/consent`, turn on **Allow dynamic client registration**.
   Authentication > URL Configuration > **Site URL** must be `https://app.churchtvos.com` (the consent page lives there).
3. Deploy the dashboard (it contains the `/oauth/consent` page) and the function: `supabase functions deploy mcp --no-verify-jwt`
4. Optional, tidies expired assistant-made slots daily:
   `select cron.schedule('purge-mcp-slots', '15 4 * * *', $$select public.purge_expired_mcp_slots()$$);`
5. Connect: in Claude, Settings > Connectors > Add custom connector > the endpoint URL above. Sign in and press Allow.

## Try it
"Here's the Youth Night poster. Put it on the lobby screen this Friday from 8 to 10pm." Claude should upload it, show a preview (screen, date, local times, conflicts), and only schedule after you say yes.
