# notify-offline

Sends "TV offline" / "back online" push notifications to the Church TV OS iPhone, iPad and Mac apps.

How it works: every 5 minutes a database schedule calls this function. It asks the database (`claim_offline_alerts()`) who needs telling
(each outage is announced once, plus one "back online"), then sends the pushes through Apple (APNs). People opt in by allowing notifications
in the app (which saves their device in `push_devices`) and can switch alerts off per church in the app (`notification_prefs`).

## One-time setup (Keith, needs the Apple Developer account)
1. developer.apple.com > Certificates, Identifiers & Profiles > **Keys** > add a key, tick **Apple Push Notifications service (APNs)**, download the `AuthKey_XXXXXXXXXX.p8` file (you can only download it once). Note the **Key ID** and your **Team ID** (Membership details).
2. Register the app ids with Push Notifications enabled: `com.churchtvos.remote` (iPhone/iPad) and later `com.churchtvos.mac`.
3. Set the secrets (run these yourself in a terminal; never paste the key into a chat):
   ```
   supabase secrets set APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY NOTIFY_CRON_SECRET=$(openssl rand -hex 24)
   supabase secrets set APNS_PRIVATE_KEY="$(cat /path/to/AuthKey_XXXXXXXXXX.p8)"
   ```
   Optional: `APNS_TOPIC_IOS` / `APNS_TOPIC_MAC` if the bundle ids differ from the defaults.
4. Deploy: `supabase functions deploy notify-offline --no-verify-jwt` (already done once; redeploy after edits).
5. Schedule it (Supabase dashboard > SQL editor). Replace SECRET with the same value as NOTIFY_CRON_SECRET (`supabase secrets list` shows only a digest, so keep your own copy):
   ```sql
   create extension if not exists pg_cron;
   create extension if not exists pg_net;
   select cron.schedule('notify-offline', '*/5 * * * *', $$
     select net.http_post(
       url := 'https://gqkefjngblgomuovaivj.supabase.co/functions/v1/notify-offline',
       headers := '{"x-cron-secret":"SECRET"}'::jsonb
     );
   $$);
   ```
   Stop it any time with `select cron.unschedule('notify-offline');`.
6. Test: `curl -X POST -H "x-cron-secret: SECRET" https://gqkefjngblgomuovaivj.supabase.co/functions/v1/notify-offline` returns `{alerts, sent, failed, removed}`.

Phones registered from a development build use the `sandbox` APNs host; TestFlight/App Store builds use `production` (the app records which in `push_devices.environment`).
