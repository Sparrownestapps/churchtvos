-- Offline alerts: which people to notify about which screens, with de-duplication, decided in the database so it can be tested.
-- Called only by the notify-offline Edge Function (service role). A TV that has not been seen for 10 minutes, but was seen in the
-- last 24 hours, is "offline" (alert once). When it comes back, a "back online" notice goes out once.

create function public.claim_offline_alerts()
returns table (kind text, screen_id uuid, screen_name text, org_name text, token text, platform text, environment text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  drop table if exists _alerts;
  create temp table _alerts (kind text, screen_id uuid) on commit drop;

  insert into _alerts
  select 'offline', s.id
  from screens s
  join organizations o on o.id = s.organization_id and o.status = 'active'
  left join screen_alert_state a on a.screen_id = s.id
  where s.organization_id is not null
    and s.last_seen_at < now() - interval '10 minutes' and s.last_seen_at > now() - interval '24 hours'
    and a.alerted_at is null;

  insert into _alerts
  select 'online', s.id
  from screens s
  join screen_alert_state a on a.screen_id = s.id
  where a.alerted_at is not null and s.last_seen_at > now() - interval '2 minutes';

  insert into screen_alert_state (screen_id, alerted_at)
  select x.screen_id, now() from _alerts x where x.kind = 'offline'
  on conflict (screen_id) do update set alerted_at = now(), online_since = null;

  update screen_alert_state a set alerted_at = null, online_since = now()
  from _alerts x where x.kind = 'online' and a.screen_id = x.screen_id;

  return query
  select x.kind, s.id, coalesce(nullif(s.name, ''), l.name, 'A TV'), o.name, pd.token, pd.platform, pd.environment
  from _alerts x
  join screens s on s.id = x.screen_id
  join organizations o on o.id = s.organization_id
  left join locations l on l.id = s.location_id
  join memberships m on m.organization_id = s.organization_id and m.user_id is not null
    and m.role in ('owner', 'admin', 'editor', 'operator')
    and (m.role in ('owner', 'admin') or m.site_ids is null or l.site_id = any (m.site_ids))
  left join notification_prefs np on np.user_id = m.user_id and np.organization_id = m.organization_id
  join push_devices pd on pd.user_id = m.user_id
  where coalesce(np.offline_alerts, true);
end $$;

revoke execute on function public.claim_offline_alerts() from public, anon, authenticated;
grant execute on function public.claim_offline_alerts() to service_role;
