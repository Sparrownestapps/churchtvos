-- Repeating Kids schedules ("series") with a playlist rotation, and the server-side expansion
-- into the same dated list the TV already reads. No TV change needed.

create table public.kids_series (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  location_id     uuid not null,
  name            text,
  days            int[] not null default '{0}',            -- 0 = Sunday
  start_time      time not null,
  end_time        time not null,
  start_date      date not null,
  end_date        date,
  playlist_ids    uuid[] not null,                          -- the rotation, in order (1 = same playlist every week)
  on_end          text not null default 'loop' check (on_end in ('stop', 'loop')),
  created_at      timestamptz not null default now(),
  check (end_time > start_time),
  check (end_date is null or end_date >= start_date),
  check (cardinality(playlist_ids) >= 1),
  check (cardinality(days) >= 1),
  foreign key (location_id, organization_id) references public.locations (id, organization_id) on delete cascade
);
create index on public.kids_series (organization_id, location_id);

-- skip = this date does not happen (the rotation waits, so the skipped playlist moves to the next date);
-- playlist = this date plays a different playlist (it still uses up its place in the rotation).
create table public.kids_series_exceptions (
  series_id   uuid not null references public.kids_series on delete cascade,
  on_date     date not null,
  action      text not null check (action in ('skip', 'playlist')),
  playlist_id uuid references public.playlists on delete cascade,
  primary key (series_id, on_date),
  check (action <> 'playlist' or playlist_id is not null)
);

alter table public.kids_series enable row level security;
alter table public.kids_series_exceptions enable row level security;

create policy "view kids series" on public.kids_series for select to authenticated
  using (public.can_view_content(organization_id, public.location_site(location_id), 'kids'));
create policy "edit kids series" on public.kids_series for all to authenticated
  using (public.can_edit_content(organization_id, public.location_site(location_id), 'kids'))
  with check (public.can_edit_content(organization_id, public.location_site(location_id), 'kids'));

create function public.series_org(p_series uuid) returns uuid
language sql stable security definer set search_path = public as $$ select organization_id from kids_series where id = p_series $$;
create function public.series_site(p_series uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select l.site_id from kids_series s join locations l on l.id = s.location_id where s.id = p_series
$$;
grant execute on function public.series_org(uuid), public.series_site(uuid) to authenticated;

create policy "view kids series exceptions" on public.kids_series_exceptions for select to authenticated
  using (public.can_view_content(public.series_org(series_id), public.series_site(series_id), 'kids'));
create policy "edit kids series exceptions" on public.kids_series_exceptions for all to authenticated
  using (public.can_edit_content(public.series_org(series_id), public.series_site(series_id), 'kids'))
  with check (public.can_edit_content(public.series_org(series_id), public.series_site(series_id), 'kids'));

-- A playlist used by a repeating schedule cannot be deleted (it would silently drop out of the rotation).
create function public.playlist_block_delete_in_series() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_names text;
begin
  if not exists (select 1 from organizations where id = old.organization_id) then return old; end if;
  select string_agg(coalesce(nullif(name, ''), 'Repeating schedule'), ', ') into v_names
    from kids_series where organization_id = old.organization_id and old.id = any (playlist_ids);
  if v_names is null then
    select string_agg('a repeating schedule', ', ') into v_names
      from kids_series_exceptions e join kids_series s on s.id = e.series_id
      where s.organization_id = old.organization_id and e.playlist_id = old.id;
  end if;
  if v_names is not null then
    raise exception '"%" is used by a repeating schedule (%). Remove it there first.', old.name, v_names;
  end if;
  return old;
end $$;
create trigger playlists_block_delete_series before delete on public.playlists
  for each row execute function public.playlist_block_delete_in_series();

-- ───────────────────────── Expansion ─────────────────────────
-- Occurrences of repeating schedules that overlap [p_from, p_to]. Times are wall-clock in the site's
-- time zone, so daylight saving is handled. Internal helper (no direct grant).
create function public.kids_series_expand(p_org uuid, p_location uuid, p_from timestamptz, p_to timestamptz)
returns table (series_id uuid, location_id uuid, on_date date, starts_at timestamptz, ends_at timestamptz,
               playlist_id uuid, occurrence_no int, is_override boolean)
language sql stable security definer set search_path = public as $$
  with s as (
    select ks.*, coalesce(st.timezone, 'America/Toronto') as tz
    from kids_series ks
    join locations l on l.id = ks.location_id
    join sites st on st.id = l.site_id
    where ks.organization_id = p_org and (p_location is null or ks.location_id = p_location)
  ),
  days as (
    select s.id as sid, s.tz, s.start_time, s.end_time, s.playlist_ids, s.on_end, s.location_id as loc, d::date as d
    from s,
      generate_series(s.start_date::timestamp,
                      least(coalesce(s.end_date, (p_to at time zone s.tz)::date), (p_to at time zone s.tz)::date)::timestamp,
                      interval '1 day') d
    where extract(dow from d)::int = any (s.days)
  ),
  numbered as (
    select days.*, ex.action, ex.playlist_id as ex_playlist,
           count(*) filter (where ex.action is distinct from 'skip') over (partition by days.sid order by days.d) as n
    from days
    left join kids_series_exceptions ex on ex.series_id = days.sid and ex.on_date = days.d
  ),
  resolved as (
    select sid, loc, d, tz, start_time, end_time, n::int as n,
           (action = 'playlist') as is_override,
           case
             when action = 'playlist' then ex_playlist
             when on_end = 'loop' or n <= cardinality(playlist_ids) then playlist_ids[((n - 1) % cardinality(playlist_ids)) + 1]
           end as pl
    from numbered
    where action is distinct from 'skip'
  )
  select sid, loc, d,
         (d + start_time) at time zone tz,
         (d + end_time) at time zone tz,
         pl, n, is_override
  from resolved
  where pl is not null
    and (d + end_time) at time zone tz > p_from
    and (d + start_time) at time zone tz < p_to
  order by 4
$$;

-- For the calendar: the signed-in user's view of repeating schedules in a date range.
create function public.kids_series_occurrences(p_org uuid, p_from timestamptz, p_to timestamptz, p_location uuid default null)
returns table (series_id uuid, location_id uuid, on_date date, starts_at timestamptz, ends_at timestamptz,
               playlist_id uuid, occurrence_no int, is_override boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_module(p_org, 'kids') then raise exception 'No access'; end if;
  return query
    select e.* from public.kids_series_expand(p_org, p_location, p_from, p_to) e
    where public.in_site_scope(p_org, public.location_site(e.location_id));
end $$;
grant execute on function public.kids_series_occurrences(uuid, timestamptz, timestamptz, uuid) to authenticated;

-- What a TV gets for Kids: the one-off schedules (as before) plus repeating occurrences.
-- A one-off that overlaps a repeating occurrence replaces it.
create function public.kids_schedule_entries(p_location uuid, p_now timestamptz) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_org uuid;
  v_result jsonb;
begin
  select organization_id into v_org from locations where id = p_location;
  with active as (
    select * from schedules where location_id = p_location and (ends_at is null or ends_at > p_now)
  ), picked as (
    (select id::text as id, starts_at, ends_at, playlist_id from active where starts_at <= p_now order by starts_at desc limit 1)
    union all
    (select id::text, starts_at, ends_at, playlist_id from active where starts_at > p_now and starts_at <= p_now + interval '14 days')
  ), series as (
    select e.series_id::text || ':' || e.on_date::text as id, e.starts_at, e.ends_at, e.playlist_id
    from public.kids_series_expand(v_org, p_location, p_now, p_now + interval '14 days') e
    where not exists (
      select 1 from active a
      where a.starts_at < e.ends_at and coalesce(a.ends_at, 'infinity'::timestamptz) > e.starts_at
    )
  ), merged as (
    select * from picked union all select * from series
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'starts_at', m.starts_at, 'ends_at', m.ends_at,
           'playlist', jsonb_build_object('id', p.id, 'name', p.name, 'items', p.items)
         ) order by m.starts_at), '[]')
    into v_result
    from merged m join playlists p on p.id = m.playlist_id;
  return v_result;
end $$;

create or replace function public.device_state(p_device_id uuid, p_secret text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_screen   screens := authenticate_screen(p_device_id, p_secret);
  v_org      organizations;
  v_loc      locations;
  v_site     sites;
  v_enabled  jsonb;
  v_rules    jsonb;
  v_kids     jsonb := '[]';
  v_slots    jsonb := '[]';
  v_default  jsonb;
begin
  update screens set last_seen_at = now() where id = p_device_id;

  if v_screen.organization_id is null then
    if v_screen.pairing_code is null then
      update screens set pairing_code = new_pairing_code() where id = p_device_id returning * into v_screen;
    end if;
    return jsonb_build_object('paired', false, 'pairing_code', v_screen.pairing_code);
  end if;

  select * into v_org  from organizations where id = v_screen.organization_id;
  select * into v_loc  from locations where id = v_screen.location_id;
  select * into v_site from sites where id = v_loc.site_id;

  select coalesce(jsonb_agg(m.id), '[]') into v_enabled
    from public.modules m where m.available and module_enabled(v_org.id, m.id);

  select coalesce(jsonb_agg(jsonb_build_object(
           'module', r.module, 'days', r.days, 'start', r.start_time, 'end', r.end_time, 'priority', r.priority
         ) order by r.priority, r.created_at), '[]')
    into v_rules
    from screen_schedules r
    where r.screen_id = v_screen.id or (v_screen.group_id is not null and r.group_id = v_screen.group_id);

  if v_enabled ? 'kids' and v_screen.location_id is not null then
    v_kids := public.kids_schedule_entries(v_screen.location_id, now());
  end if;

  if v_enabled ? 'signage' then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', s.id, 'days', s.days, 'start', s.start_time, 'end', s.end_time, 'priority', s.priority,
             'playlist', jsonb_build_object('id', p.id, 'name', p.name, 'items', p.items)
           ) order by s.priority, s.created_at), '[]')
      into v_slots
      from signage_slots s join signage_playlists p on p.id = s.playlist_id
      where s.screen_id = v_screen.id or (v_screen.group_id is not null and s.group_id = v_screen.group_id);

    select jsonb_build_object('id', p.id, 'name', p.name, 'items', p.items) into v_default
      from signage_playlists p where p.id = v_screen.signage_default_playlist_id;
  end if;

  return jsonb_build_object(
    'paired', true,
    'organization', jsonb_build_object('name', v_org.name, 'branding', v_org.branding),
    'site', v_site.name,
    'location', v_loc.name,
    'timezone', coalesce(v_site.timezone, 'America/Toronto'),
    'screen', jsonb_build_object('name', v_screen.name, 'orientation', v_screen.orientation),
    'enabled_modules', v_enabled,
    'default_module', v_screen.default_module,
    'module_rules', v_rules,
    'kids', jsonb_build_object('schedules', v_kids),
    'signage', jsonb_build_object('slots', v_slots, 'default_playlist', v_default)
  );
end $$;
