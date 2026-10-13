-- Applications (modules) registry, location tags, per-application media libraries with folders.

-- ───────────────────────── Module registry ─────────────────────────
-- Adding an application (e.g. production) = one row here plus its dashboard pages.
create table public.modules (
  id        text primary key,
  name      text not null,
  sort      int  not null default 0,
  available boolean not null default true   -- false = planned, hidden everywhere
);
alter table public.modules enable row level security;
create policy "anyone signed in reads modules" on public.modules for select to authenticated using (true);
insert into public.modules (id, name, sort, available) values
  ('kids', 'Kids', 1, true), ('signage', 'Signage', 2, true), ('production', 'Production', 3, false);

create function public.valid_module(p text) returns boolean
language sql stable as $$ select exists (select 1 from public.modules where id = p) $$;

create function public.valid_modules(p text[]) returns boolean
language sql stable as $$
  select not exists (select 1 from unnest(p) m where not public.valid_module(m))
$$;

-- Replace the hard-coded ('kids','signage') checks.
alter table public.memberships drop constraint memberships_modules_check;
alter table public.memberships add constraint memberships_modules_check check (public.valid_modules(modules));
alter table public.entitlements drop constraint entitlements_module_check;
alter table public.entitlements add constraint entitlements_module_check check (public.valid_module(module));
alter table public.screens drop constraint screens_default_module_check;
alter table public.screens add constraint screens_default_module_check check (default_module = 'off' or public.valid_module(default_module));
alter table public.screen_schedules drop constraint screen_schedules_module_check;
alter table public.screen_schedules add constraint screen_schedules_module_check check (module = 'off' or public.valid_module(module));

grant execute on function public.valid_module(text), public.valid_modules(text[]) to authenticated, anon;

-- ───────────────────────── Location tags ─────────────────────────
-- Which applications use a location. A location may carry several (it then shows under each).
alter table public.locations add column modules text[] not null default '{kids,signage}';
alter table public.locations add constraint locations_modules_check check (public.valid_modules(modules));

-- ───────────────────────── Media folders ─────────────────────────
alter table public.media add column module text not null default 'kids';
alter table public.media alter column module drop default;
alter table public.media add constraint media_module_check check (public.valid_module(module));

create table public.media_folders (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  module          text not null check (public.valid_module(module)),
  parent_id       uuid,
  site_id         uuid references public.sites on delete cascade,   -- null = all sites; inherited by everything inside
  name            text not null check (length(trim(name)) > 0),
  created_at      timestamptz not null default now(),
  unique (id, organization_id, module),
  foreign key (parent_id, organization_id, module)
    references public.media_folders (id, organization_id, module) on delete set null (parent_id)
);
create unique index media_folders_unique_name on public.media_folders
  (organization_id, module, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'), lower(name));

alter table public.media add column folder_id uuid;
alter table public.media add foreign key (folder_id, organization_id, module)
  references public.media_folders (id, organization_id, module) on delete set null (folder_id);
create index on public.media (organization_id, module, folder_id);

-- Deleting a folder moves what is inside up one level (nothing is deleted with it).
create function public.media_folder_reparent() returns trigger
language plpgsql as $$
begin
  update public.media_folders set parent_id = old.parent_id where parent_id = old.id;
  update public.media set folder_id = old.parent_id where folder_id = old.id;
  return old;
end $$;
create trigger media_folders_reparent before delete on public.media_folders
  for each row execute function public.media_folder_reparent();

-- A folder limited to a site passes that limit to its sub-folders and files.
create function public.media_folder_inherit_site() returns trigger
language plpgsql as $$
declare
  v_parent_site uuid;
begin
  if new.parent_id is not null then
    select site_id into v_parent_site from public.media_folders where id = new.parent_id;
    if v_parent_site is not null then new.site_id := v_parent_site; end if;
  end if;
  return new;
end $$;
create trigger media_folders_inherit_site before insert or update of parent_id on public.media_folders
  for each row execute function public.media_folder_inherit_site();

create function public.media_folder_cascade_site() returns trigger
language plpgsql as $$
begin
  if new.site_id is distinct from old.site_id then
    with recursive tree as (
      select id from public.media_folders where parent_id = new.id
      union all
      select f.id from public.media_folders f join tree t on f.parent_id = t.id
    )
    update public.media_folders set site_id = new.site_id where id in (select id from tree);
    update public.media set site_id = new.site_id
      where folder_id = new.id or folder_id in (
        with recursive tree as (
          select id from public.media_folders where parent_id = new.id
          union all
          select f.id from public.media_folders f join tree t on f.parent_id = t.id
        ) select id from tree);
  end if;
  return new;
end $$;
create trigger media_folders_cascade_site after update of site_id on public.media_folders
  for each row execute function public.media_folder_cascade_site();

create function public.media_inherit_folder_site() returns trigger
language plpgsql as $$
declare
  v_site uuid;
begin
  if new.folder_id is not null then
    select site_id into v_site from public.media_folders where id = new.folder_id;
    if v_site is not null then new.site_id := v_site; end if;
  end if;
  return new;
end $$;
create trigger media_inherit_folder_site before insert or update of folder_id on public.media
  for each row execute function public.media_inherit_folder_site();

-- ───────────────────────── Media in use ─────────────────────────
-- Which playlists use each file (ids and names), for the "used in N playlists" label and delete protection.
create function public.media_usage(p_org uuid, p_module text)
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
  end if;
end $$;
grant execute on function public.media_usage(uuid, text) to authenticated;

-- Refuse to delete a file a playlist still uses (the file would silently vanish from the TV).
create function public.media_block_delete_in_use() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_names text;
begin
  if not exists (select 1 from organizations where id = old.organization_id) then return old; end if;  -- whole church being removed
  select string_agg(name, ', ') into v_names from (
    select name from playlists where organization_id = old.organization_id
      and items @> jsonb_build_array(jsonb_build_object('media_id', old.id::text))
    union
    select name from signage_playlists where organization_id = old.organization_id
      and items @> jsonb_build_array(jsonb_build_object('media_id', old.id::text))
  ) u;
  if v_names is not null then
    raise exception '"%" is used in: %. Remove it from those playlists first.', old.title, v_names;
  end if;
  return old;
end $$;
create trigger media_block_delete before delete on public.media
  for each row execute function public.media_block_delete_in_use();

-- Storage used per application, for the library headers.
create function public.media_storage_by_module(p_org uuid)
returns table (module text, files bigint, bytes bigint)
language sql stable security definer set search_path = public as $$
  select m.module, count(*), coalesce(sum(m.size_bytes), 0)::bigint
  from media m
  where m.organization_id = p_org and public.has_module(p_org, m.module)
  group by m.module
$$;
grant execute on function public.media_storage_by_module(uuid) to authenticated;

-- ───────────────────────── Row level security ─────────────────────────
alter table public.media_folders enable row level security;

drop policy "view media" on public.media;
drop policy "insert media" on public.media;
drop policy "update media" on public.media;
drop policy "delete media" on public.media;
create policy "view media"   on public.media for select to authenticated using (public.can_view_content(organization_id, site_id, module));
create policy "insert media" on public.media for insert to authenticated with check (public.can_edit_content(organization_id, site_id, module));
create policy "update media" on public.media for update to authenticated
  using (public.can_edit_content(organization_id, site_id, module)) with check (public.can_edit_content(organization_id, site_id, module));
create policy "delete media" on public.media for delete to authenticated using (public.can_edit_content(organization_id, site_id, module));

create policy "view media folders"   on public.media_folders for select to authenticated using (public.can_view_content(organization_id, site_id, module));
create policy "insert media folders" on public.media_folders for insert to authenticated with check (public.can_edit_content(organization_id, site_id, module));
create policy "update media folders" on public.media_folders for update to authenticated
  using (public.can_edit_content(organization_id, site_id, module)) with check (public.can_edit_content(organization_id, site_id, module));
create policy "delete media folders" on public.media_folders for delete to authenticated using (public.can_edit_content(organization_id, site_id, module));

-- ───────────────────────── device_state: modules come from the registry ─────────────────────────
-- Everything a TV needs. The TV works out which module to show from module_rules (so it keeps
-- switching correctly while offline); the server only decides which modules are paid for.
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
    with active as (
      select * from schedules
      where location_id = v_screen.location_id and (ends_at is null or ends_at > now())
    ), picked as (
      (select * from active where starts_at <= now() order by starts_at desc limit 1)
      union all
      (select * from active where starts_at > now() and starts_at <= now() + interval '14 days')
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', s.id, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
             'playlist', jsonb_build_object('id', p.id, 'name', p.name, 'items', p.items)
           ) order by s.starts_at), '[]')
      into v_kids
      from picked s join playlists p on p.id = s.playlist_id;
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

