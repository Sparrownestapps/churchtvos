-- Slides module: themes, decks (presentations), dated and repeating schedules, server-side expansion for the TV.
-- The module stays hidden (modules.available = false) until the dashboard and TV app are ready.

insert into public.modules (id, name, sort, available) values ('slides', 'Slides', 3, false)
  on conflict (id) do update set name = 'Slides', sort = 3;
update public.modules set sort = 4 where id = 'production';

-- Members created from now on get Slides too; existing members keep what they had plus Slides (they had every module).
alter table public.memberships alter column modules set default '{kids,signage,slides}';
update public.memberships set modules = modules || '{slides}' where not ('slides' = any (modules));

create table public.slide_themes (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  name            text not null check (length(trim(name)) > 0),
  -- {"font":"lato"|"julius","title_size":1.0,"body_size":1.0,"text_color":"#FFFFFF","align":"center"|"left","position":"center"|"lower"|"top",
  --  "shadow":true,"outline":false,"margin":8,"background":{...},"show_labels":true,"logo":{"show":false,"position":"bottom_left"}}
  config          jsonb not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, organization_id),
  unique (organization_id, name)
);
create trigger slide_themes_updated_at before update on public.slide_themes
  for each row execute function public.touch_updated_at();

create table public.decks (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  site_id         uuid references public.sites on delete cascade,   -- null = shared across the church
  name            text not null check (length(trim(name)) > 0),
  theme_id        uuid,
  background      jsonb,        -- deck default background (overrides the theme's); a slide can override again
  -- ordered slides, see SLIDES-MODULE-PLAN.md / dashboard types: kinds text, media, song, countdown, stream, blank
  slides          jsonb not null default '[]',
  loops           boolean not null default false,   -- start over after the last slide
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (theme_id, organization_id) references public.slide_themes (id, organization_id) on delete set null (theme_id)
);
create trigger decks_updated_at before update on public.decks
  for each row execute function public.touch_updated_at();

create table public.deck_schedules (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  location_id     uuid not null,
  deck_id         uuid not null,
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  created_at      timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  foreign key (location_id, organization_id) references public.locations (id, organization_id) on delete cascade,
  foreign key (deck_id, organization_id) references public.decks (id, organization_id) on delete cascade
);
create index on public.deck_schedules (location_id, starts_at);

create table public.deck_series (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  location_id     uuid not null,
  name            text,
  days            int[] not null default '{0}',
  start_time      time not null,
  end_time        time not null,
  start_date      date not null,
  end_date        date,
  deck_ids        uuid[] not null,
  on_end          text not null default 'loop' check (on_end in ('stop', 'loop')),
  created_at      timestamptz not null default now(),
  check (end_time > start_time),
  check (end_date is null or end_date >= start_date),
  check (cardinality(deck_ids) >= 1),
  check (cardinality(days) >= 1),
  foreign key (location_id, organization_id) references public.locations (id, organization_id) on delete cascade
);
create index on public.deck_series (organization_id, location_id);

create table public.deck_series_exceptions (
  series_id uuid not null references public.deck_series on delete cascade,
  on_date   date not null,
  action    text not null check (action in ('skip', 'deck')),
  deck_id   uuid references public.decks on delete cascade,
  primary key (series_id, on_date),
  check (action <> 'deck' or deck_id is not null)
);

alter table public.slide_themes enable row level security;
alter table public.decks enable row level security;
alter table public.deck_schedules enable row level security;
alter table public.deck_series enable row level security;
alter table public.deck_series_exceptions enable row level security;

create policy "view themes"   on public.slide_themes for select to authenticated using (public.has_module(organization_id, 'slides'));
create policy "edit themes"   on public.slide_themes for all to authenticated
  using (public.can_edit_content(organization_id, null, 'slides')) with check (public.can_edit_content(organization_id, null, 'slides'));

create policy "view decks"   on public.decks for select to authenticated using (public.can_view_content(organization_id, site_id, 'slides'));
create policy "insert decks" on public.decks for insert to authenticated with check (public.can_edit_content(organization_id, site_id, 'slides'));
create policy "update decks" on public.decks for update to authenticated
  using (public.can_edit_content(organization_id, site_id, 'slides')) with check (public.can_edit_content(organization_id, site_id, 'slides'));
create policy "delete decks" on public.decks for delete to authenticated using (public.can_edit_content(organization_id, site_id, 'slides'));

create policy "view deck schedules" on public.deck_schedules for select to authenticated
  using (public.can_view_content(organization_id, public.location_site(location_id), 'slides'));
create policy "edit deck schedules" on public.deck_schedules for all to authenticated
  using (public.can_edit_content(organization_id, public.location_site(location_id), 'slides'))
  with check (public.can_edit_content(organization_id, public.location_site(location_id), 'slides'));

create policy "view deck series" on public.deck_series for select to authenticated
  using (public.can_view_content(organization_id, public.location_site(location_id), 'slides'));
create policy "edit deck series" on public.deck_series for all to authenticated
  using (public.can_edit_content(organization_id, public.location_site(location_id), 'slides'))
  with check (public.can_edit_content(organization_id, public.location_site(location_id), 'slides'));

create function public.dseries_org(p_series uuid) returns uuid
language sql stable security definer set search_path = public as $$ select organization_id from deck_series where id = p_series $$;
create function public.dseries_site(p_series uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select l.site_id from deck_series s join locations l on l.id = s.location_id where s.id = p_series
$$;
grant execute on function public.dseries_org(uuid), public.dseries_site(uuid) to authenticated;

create policy "view deck series exceptions" on public.deck_series_exceptions for select to authenticated
  using (public.can_view_content(public.dseries_org(series_id), public.dseries_site(series_id), 'slides'));
create policy "edit deck series exceptions" on public.deck_series_exceptions for all to authenticated
  using (public.can_edit_content(public.dseries_org(series_id), public.dseries_site(series_id), 'slides'))
  with check (public.can_edit_content(public.dseries_org(series_id), public.dseries_site(series_id), 'slides'));

-- ───────────────────────── Delete protection ─────────────────────────
-- A deck used by a repeating schedule cannot be deleted.
create function public.deck_block_delete_in_series() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_names text;
begin
  if not exists (select 1 from organizations where id = old.organization_id) then return old; end if;
  select string_agg(coalesce(nullif(name, ''), 'Repeating schedule'), ', ') into v_names
    from deck_series where organization_id = old.organization_id and old.id = any (deck_ids);
  if v_names is null then
    select 'a repeating schedule' into v_names
      from deck_series_exceptions e join deck_series s on s.id = e.series_id
      where s.organization_id = old.organization_id and e.deck_id = old.id limit 1;
  end if;
  if v_names is not null then
    raise exception '"%" is used by a repeating schedule (%). Remove it there first.', old.name, v_names;
  end if;
  return old;
end $$;
create trigger decks_block_delete_series before delete on public.decks
  for each row execute function public.deck_block_delete_in_series();

-- A theme in use by a deck can be deleted (decks fall back to the default look), no protection needed.

-- Media used by decks or themes (as a slide, a background, or a theme background) cannot be deleted.
create or replace function public.media_block_delete_in_use() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_names text;
  v_id text := old.id::text;
begin
  if not exists (select 1 from organizations where id = old.organization_id) then return old; end if;
  select string_agg(name, ', ') into v_names from (
    select name from playlists where organization_id = old.organization_id
      and items @> jsonb_build_array(jsonb_build_object('media_id', v_id))
    union
    select name from signage_playlists where organization_id = old.organization_id
      and items @> jsonb_build_array(jsonb_build_object('media_id', v_id))
    union
    select name from decks where organization_id = old.organization_id
      and (position(v_id in slides::text) > 0 or position(v_id in coalesce(background::text, '')) > 0)
    union
    select name || ' (theme)' from slide_themes where organization_id = old.organization_id
      and position(v_id in config::text) > 0
  ) u;
  if v_names is not null then
    raise exception '"%" is used in: %. Remove it from those first.', old.title, v_names;
  end if;
  return old;
end $$;

create or replace function public.media_usage(p_org uuid, p_module text)
returns table (media_id uuid, playlist_names text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_module(p_org, p_module) then raise exception 'No access'; end if;
  if p_module = 'kids' then
    return query
      select (i->>'media_id')::uuid, array_agg(distinct p.name order by p.name)
      from playlists p, jsonb_array_elements(p.items) i
      where p.organization_id = p_org and nullif(i->>'media_id', '') is not null
      group by 1;
  elsif p_module = 'signage' then
    return query
      select (i->>'media_id')::uuid, array_agg(distinct p.name order by p.name)
      from signage_playlists p, jsonb_array_elements(p.items) i
      where p.organization_id = p_org and nullif(i->>'media_id', '') is not null
      group by 1;
  elsif p_module = 'slides' then
    return query
      select m.id, array_agg(distinct u.name order by u.name)
      from media m
      join (
        select name, slides::text || coalesce(background::text, '') as body from decks where organization_id = p_org
        union all
        select name || ' (theme)', config::text from slide_themes where organization_id = p_org
      ) u on position(m.id::text in u.body) > 0
      where m.organization_id = p_org and m.module = 'slides'
      group by m.id;
  end if;
end $$;

-- A song used by a deck cannot be deleted either; usage lists decks too.
create or replace function public.song_block_delete_in_use() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_names text;
begin
  if not exists (select 1 from organizations where id = old.organization_id) then return old; end if;
  select string_agg(name, ', ') into v_names from (
    select name from playlists
      where organization_id = old.organization_id
        and items @> jsonb_build_array(jsonb_build_object('song_id', old.id::text))
    union
    select name from decks
      where organization_id = old.organization_id
        and slides @> jsonb_build_array(jsonb_build_object('song_id', old.id::text))
  ) u;
  if v_names is not null then
    raise exception '"%" is used in: %. Remove it from those playlists or decks first.', old.title, v_names;
  end if;
  return old;
end $$;

create or replace function public.song_usage(p_org uuid)
returns table (song_id uuid, playlist_names text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_use_songs(p_org) then raise exception 'No access'; end if;
  return query
    select u.sid, array_agg(distinct u.name order by u.name)
    from (
      select (i->>'song_id')::uuid as sid, p.name
        from playlists p, jsonb_array_elements(p.items) i
        where p.organization_id = p_org and nullif(i->>'song_id', '') is not null
      union all
      select (s->>'song_id')::uuid, d.name || ' (deck)'
        from decks d, jsonb_array_elements(d.slides) s
        where d.organization_id = p_org and nullif(s->>'song_id', '') is not null
    ) u
    group by u.sid;
end $$;

-- ───────────────────────── Expansion for the TV ─────────────────────────
-- A deck as the TV reads it: songs expanded into title + lyric slides, theme config attached.
create function public.deck_expand(p_deck public.decks) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_theme jsonb := '{}';
  v_out jsonb := '[]';
  v_slide jsonb;
  v_song songs;
  v_exp jsonb;
  v_n int;
  i int;
begin
  if p_deck.theme_id is not null then
    select config into v_theme from slide_themes where id = p_deck.theme_id and organization_id = p_deck.organization_id;
    v_theme := coalesce(v_theme, '{}');
  end if;

  for v_slide in select e from jsonb_array_elements(coalesce(p_deck.slides, '[]')) e loop
    if v_slide->>'kind' = 'song' then
      select * into v_song from songs where id = nullif(v_slide->>'song_id', '')::uuid and organization_id = p_deck.organization_id;
      continue when not found;
      v_exp := public.song_expand(v_song);
      v_n := jsonb_array_length(v_exp->'slides');
      if coalesce((v_slide->>'show_title')::boolean, false) then
        v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'kind', 'song_title', 'title', v_song.title,
          'authors', nullif(v_song.authors, ''), 'ccli', nullif(v_song.ccli_number, ''), 'copyright', nullif(v_song.copyright, ''),
          'background', v_slide->'background')));
      end if;
      for i in 0..v_n - 1 loop
        v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'kind', 'lyric', 'song', v_song.title, 'text', v_exp->'slides'->>i, 'label', v_exp->'labels'->>i,
          'number', i + 1, 'count', v_n, 'background', v_slide->'background')));
      end loop;
    else
      v_out := v_out || jsonb_build_array(v_slide - 'notes');
    end if;
  end loop;

  return jsonb_strip_nulls(jsonb_build_object(
    'id', p_deck.id, 'name', p_deck.name, 'loop', p_deck.loops,
    'theme', v_theme, 'background', p_deck.background, 'slides', v_out));
end $$;

create function public.deck_series_expand(p_org uuid, p_location uuid, p_from timestamptz, p_to timestamptz)
returns table (series_id uuid, location_id uuid, on_date date, starts_at timestamptz, ends_at timestamptz,
               deck_id uuid, occurrence_no int, is_override boolean)
language sql stable security definer set search_path = public as $$
  with s as (
    select ks.*, coalesce(st.timezone, 'America/Toronto') as tz
    from deck_series ks
    join locations l on l.id = ks.location_id
    join sites st on st.id = l.site_id
    where ks.organization_id = p_org and (p_location is null or ks.location_id = p_location)
  ),
  days as (
    select s.id as sid, s.tz, s.start_time, s.end_time, s.deck_ids, s.on_end, s.location_id as loc, d::date as d
    from s,
      generate_series(s.start_date::timestamp,
                      least(coalesce(s.end_date, (p_to at time zone s.tz)::date), (p_to at time zone s.tz)::date)::timestamp,
                      interval '1 day') d
    where extract(dow from d)::int = any (s.days)
  ),
  numbered as (
    select days.*, ex.action, ex.deck_id as ex_deck,
           count(*) filter (where ex.action is distinct from 'skip') over (partition by days.sid order by days.d) as n
    from days
    left join deck_series_exceptions ex on ex.series_id = days.sid and ex.on_date = days.d
  ),
  resolved as (
    select sid, loc, d, tz, start_time, end_time, n::int as n,
           (action = 'deck') as is_override,
           case
             when action = 'deck' then ex_deck
             when on_end = 'loop' or n <= cardinality(deck_ids) then deck_ids[((n - 1) % cardinality(deck_ids)) + 1]
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

create function public.deck_series_occurrences(p_org uuid, p_from timestamptz, p_to timestamptz, p_location uuid default null)
returns table (series_id uuid, location_id uuid, on_date date, starts_at timestamptz, ends_at timestamptz,
               deck_id uuid, occurrence_no int, is_override boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_module(p_org, 'slides') then raise exception 'No access'; end if;
  return query
    select e.* from public.deck_series_expand(p_org, p_location, p_from, p_to) e
    where public.in_site_scope(p_org, public.location_site(e.location_id));
end $$;
grant execute on function public.deck_series_occurrences(uuid, timestamptz, timestamptz, uuid) to authenticated;

-- What a TV gets for Slides: one-off schedules plus repeating occurrences (a one-off replaces an overlapping repeat).
create function public.deck_schedule_entries(p_location uuid, p_now timestamptz, p_app_version text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_org uuid;
  v_result jsonb;
begin
  select organization_id into v_org from locations where id = p_location;
  with active as (
    select * from deck_schedules where location_id = p_location and (ends_at is null or ends_at > p_now)
  ), picked as (
    (select id::text as id, starts_at, ends_at, deck_id from active where starts_at <= p_now order by starts_at desc limit 1)
    union all
    (select id::text, starts_at, ends_at, deck_id from active where starts_at > p_now and starts_at <= p_now + interval '14 days')
  ), series as (
    select e.series_id::text || ':' || e.on_date::text as id, e.starts_at, e.ends_at, e.deck_id
    from public.deck_series_expand(v_org, p_location, p_now, p_now + interval '14 days') e
    where not exists (
      select 1 from active a
      where a.starts_at < e.ends_at and coalesce(a.ends_at, 'infinity'::timestamptz) > e.starts_at
    )
  ), merged as (
    select * from picked union all select * from series
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'starts_at', m.starts_at, 'ends_at', m.ends_at,
           'deck', public.deck_expand(d)
         ) order by m.starts_at), '[]')
    into v_result
    from merged m join decks d on d.id = m.deck_id;
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
  v_decks    jsonb := '[]';
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
    from public.modules m where m.available and module_enabled(v_org.id, m.id)
      and (m.id <> 'slides' or public.version_ge(v_screen.app_version, '1.4.0'));

  select coalesce(jsonb_agg(jsonb_build_object(
           'module', r.module, 'days', r.days, 'start', r.start_time, 'end', r.end_time, 'priority', r.priority
         ) order by r.priority, r.created_at), '[]')
    into v_rules
    from screen_schedules r
    where r.screen_id = v_screen.id or (v_screen.group_id is not null and r.group_id = v_screen.group_id);

  if v_enabled ? 'kids' and v_screen.location_id is not null then
    v_kids := public.kids_schedule_entries(v_screen.location_id, now(), v_screen.app_version);
  end if;

  if v_enabled ? 'slides' and v_screen.location_id is not null then
    v_decks := public.deck_schedule_entries(v_screen.location_id, now(), v_screen.app_version);
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
    'signage', jsonb_build_object('slots', v_slots, 'default_playlist', v_default),
    'slides', jsonb_build_object('schedules', v_decks)
  );
end $$;

-- Slides entitlements for churches that already have Kids (same plan, status and TV limit).
insert into public.entitlements (organization_id, module, status, tv_limit, plan, grace_ends_at, current_period_end)
select organization_id, 'slides', status, tv_limit, plan, grace_ends_at, current_period_end
from public.entitlements where module = 'kids'
on conflict do nothing;
