-- Shared song library (Kids and, later, Slides) and server-side expansion of song items.
-- A Kids lyrics item can point at a library song ({"type":"lyrics","song_id":...,"show_title":true}); the server expands
-- it into the lyrics shape the TV reads. Old TVs keep working: for app versions before 1.3.0 a title slide is added as
-- an ordinary first slide instead of a structured flag.

create function public.version_ge(a text, b text) returns boolean
language plpgsql immutable as $$
declare pa int[]; pb int[]; i int;
begin
  if a is null or b is null then return false; end if;
  pa := regexp_split_to_array(regexp_replace(a, '[^0-9.].*$', ''), '\.')::int[];
  pb := regexp_split_to_array(regexp_replace(b, '[^0-9.].*$', ''), '\.')::int[];
  for i in 1..greatest(cardinality(pa), cardinality(pb)) loop
    if coalesce(pa[i], 0) > coalesce(pb[i], 0) then return true; end if;
    if coalesce(pa[i], 0) < coalesce(pb[i], 0) then return false; end if;
  end loop;
  return true;
exception when others then return false;
end $$;

create table public.songs (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  title           text not null check (length(trim(title)) > 0),
  authors         text,
  ccli_number     text,
  copyright       text,
  -- [{"id":"s1","label":"Verse 1","text":"line one\nline two"}, ...]
  sections        jsonb not null default '[]',
  -- ordered section ids to play (repeats allowed); null/empty = every section once, in order
  arrangement     jsonb,
  lines_per_slide int not null default 0 check (lines_per_slide between 0 and 12),   -- 0 = one slide per section
  source          text not null default 'manual',
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, organization_id)
);
create index on public.songs (organization_id, lower(title));
create trigger songs_updated_at before update on public.songs
  for each row execute function public.touch_updated_at();

create function public.can_use_songs(p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_module(p_org, 'kids') or public.has_module(p_org, 'slides');
$$;
create function public.can_edit_songs(p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.can_use_songs(p_org)
     and (public.is_platform_admin() or exists (
            select 1 from memberships
            where organization_id = p_org and user_id = auth.uid() and role in ('owner', 'admin', 'editor')));
$$;
grant execute on function public.can_use_songs(uuid), public.can_edit_songs(uuid) to authenticated;

alter table public.songs enable row level security;
create policy "view songs"   on public.songs for select to authenticated using (public.can_use_songs(organization_id));
create policy "insert songs" on public.songs for insert to authenticated with check (public.can_edit_songs(organization_id));
create policy "update songs" on public.songs for update to authenticated
  using (public.can_edit_songs(organization_id)) with check (public.can_edit_songs(organization_id));
create policy "delete songs" on public.songs for delete to authenticated using (public.can_edit_songs(organization_id));

-- A song a playlist still uses cannot be deleted.
create function public.song_block_delete_in_use() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_names text;
begin
  if not exists (select 1 from organizations where id = old.organization_id) then return old; end if;
  select string_agg(name, ', ') into v_names from playlists
    where organization_id = old.organization_id
      and items @> jsonb_build_array(jsonb_build_object('song_id', old.id::text));
  if v_names is not null then
    raise exception '"%" is used in: %. Remove it from those playlists first.', old.title, v_names;
  end if;
  return old;
end $$;
create trigger songs_block_delete before delete on public.songs
  for each row execute function public.song_block_delete_in_use();

-- For the Songs page: which playlists use each song.
create function public.song_usage(p_org uuid)
returns table (song_id uuid, playlist_names text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_use_songs(p_org) then raise exception 'No access'; end if;
  return query
    select (i->>'song_id')::uuid, array_agg(distinct p.name order by p.name)
    from playlists p, jsonb_array_elements(p.items) i
    where p.organization_id = p_org and nullif(i->>'song_id', '') is not null
    group by 1;
end $$;
grant execute on function public.song_usage(uuid) to authenticated;

-- A song as ordered slide texts + matching section labels, following its arrangement and lines-per-slide.
create function public.song_expand(p_song public.songs) returns jsonb
language plpgsql immutable as $$
declare
  v_ids jsonb;
  v_id text;
  v_sec jsonb;
  v_lines text[];
  v_slides jsonb := '[]';
  v_labels jsonb := '[]';
  v_n int;
  v_i int;
  v_chunk text;
begin
  if p_song.arrangement is null or jsonb_typeof(p_song.arrangement) <> 'array' or jsonb_array_length(p_song.arrangement) = 0 then
    select coalesce(jsonb_agg(e->>'id' order by ord), '[]') into v_ids
      from jsonb_array_elements(p_song.sections) with ordinality t(e, ord);
  else
    v_ids := p_song.arrangement;
  end if;

  for v_id in select jsonb_array_elements_text(v_ids) loop
    select e into v_sec from jsonb_array_elements(p_song.sections) e where e->>'id' = v_id limit 1;
    continue when v_sec is null;
    v_lines := regexp_split_to_array(btrim(replace(coalesce(v_sec->>'text', ''), E'\r', ''), E'\n '), E'\n');
    continue when cardinality(v_lines) = 0 or btrim(array_to_string(v_lines, '')) = '';
    if p_song.lines_per_slide > 0 then
      v_n := cardinality(v_lines);
      v_i := 1;
      while v_i <= v_n loop
        v_chunk := array_to_string(v_lines[v_i:least(v_i + p_song.lines_per_slide - 1, v_n)], E'\n');
        v_slides := v_slides || to_jsonb(v_chunk);
        v_labels := v_labels || to_jsonb(coalesce(v_sec->>'label', ''));
        v_i := v_i + p_song.lines_per_slide;
      end loop;
    else
      v_slides := v_slides || to_jsonb(array_to_string(v_lines, E'\n'));
      v_labels := v_labels || to_jsonb(coalesce(v_sec->>'label', ''));
    end if;
  end loop;
  return jsonb_build_object('slides', v_slides, 'labels', v_labels);
end $$;

-- Expand lyrics items in a Kids playlist for one TV (identified by its app version).
create function public.kids_expand_items(p_items jsonb, p_app_version text, p_org uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_out jsonb := '[]';
  v_item jsonb;
  v_song songs;
  v_exp jsonb;
  v_title text;
  v_show boolean;
  v_new boolean := public.version_ge(p_app_version, '1.3.0');
  v_slides jsonb;
  v_labels jsonb;
begin
  for v_item in select e from jsonb_array_elements(coalesce(p_items, '[]')) e loop
    if v_item->>'type' <> 'lyrics' then
      v_out := v_out || jsonb_build_array(v_item);
      continue;
    end if;
    v_show := coalesce((v_item->>'show_title')::boolean, false);
    v_title := v_item->>'title';
    v_labels := '[]';
    if nullif(v_item->>'song_id', '') is not null then
      select * into v_song from songs where id = (v_item->>'song_id')::uuid and organization_id = p_org;
      if not found then continue; end if;   -- song removed: skip the item
      v_exp := public.song_expand(v_song);
      v_slides := v_exp->'slides';
      v_labels := v_exp->'labels';
      v_title := v_song.title;
    else
      v_slides := coalesce(v_item->'slides', '[]');
      v_song := null;
    end if;

    if v_new then
      v_out := v_out || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'type', 'lyrics', 'title', v_title, 'slides', v_slides, 'labels', v_labels,
        'show_title', v_show,
        'authors', nullif(v_song.authors, ''), 'ccli', nullif(v_song.ccli_number, ''), 'copyright', nullif(v_song.copyright, ''))));
    else
      if v_show then
        v_slides := jsonb_build_array(v_title || case when nullif(v_song.authors, '') is not null then E'\n' || v_song.authors else '' end) || v_slides;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('type', 'lyrics', 'title', v_title, 'slides', v_slides));
    end if;
  end loop;
  return v_out;
end $$;

-- Replace the Kids schedule builder so it expands song items for the TV that is asking.
drop function public.kids_schedule_entries(uuid, timestamptz);
create function public.kids_schedule_entries(p_location uuid, p_now timestamptz, p_app_version text default null) returns jsonb
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
           'playlist', jsonb_build_object('id', p.id, 'name', p.name, 'items', public.kids_expand_items(p.items, p_app_version, v_org))
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
    v_kids := public.kids_schedule_entries(v_screen.location_id, now(), v_screen.app_version);
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
