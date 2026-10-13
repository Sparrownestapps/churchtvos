-- Forward TV database schema
-- Run once in Supabase: SQL Editor → New query → paste → Run.

create extension if not exists pgcrypto with schema extensions;

-- ───────────────────────── Tables ─────────────────────────

create table public.sites (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  created_at timestamptz not null default now()
);

create table public.rooms (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.sites on delete cascade,
  name       text not null,
  created_at timestamptz not null default now(),
  unique (site_id, name)
);

-- Who can use the dashboard. Admins see every site; site staff see only theirs.
-- Add a row by email before someone signs up; it links to their login automatically.
create table public.staff (
  email      text primary key,
  user_id    uuid unique references auth.users on delete set null,
  role       text not null check (role in ('admin', 'site')),
  site_id    uuid references public.sites on delete set null,
  created_at timestamptz not null default now(),
  check (role = 'admin' or site_id is not null)
);

-- site_id null = shared with every site (e.g. curriculum used church-wide)
create table public.media (
  id           uuid primary key default gen_random_uuid(),
  site_id      uuid references public.sites on delete cascade,
  title        text not null,
  kind         text not null check (kind in ('video', 'image')),
  storage_path text not null unique,
  url          text not null,
  size_bytes   bigint,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now()
);

-- items is the exact JSON the TV app plays, e.g.
-- [{"type":"video","title":"Week 1","url":"https://…","media_id":"…"},
--  {"type":"countdown","title":"Service starts in","seconds":300},
--  {"type":"lyrics","title":"Song","slides":["Verse 1…","Chorus…"]}]
create table public.playlists (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid references public.sites on delete cascade,
  name       text not null,
  items      jsonb not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A playlist shows in a room from starts_at until ends_at (or until the next one starts).
create table public.schedules (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms on delete cascade,
  playlist_id uuid not null references public.playlists on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  created_at  timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);
create index on public.schedules (room_id, starts_at);

-- Each Fire TV. It identifies itself with a random id + secret it generates on first launch.
create table public.devices (
  id           uuid primary key,
  secret_hash  text not null,
  pairing_code text unique,
  room_id      uuid references public.rooms on delete set null,
  model        text,
  app_version  text,
  last_seen_at timestamptz,
  created_at   timestamptz not null default now()
);

create function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger playlists_updated_at before update on public.playlists
  for each row execute function public.touch_updated_at();

-- ───────────────────────── Access helpers ─────────────────────────

create function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where user_id = auth.uid());
$$;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where user_id = auth.uid() and role = 'admin');
$$;

create function public.can_access_site(p_site uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from staff
    where user_id = auth.uid() and (role = 'admin' or site_id = p_site)
  );
$$;

-- Shared (site_id null) content is visible to all staff but only admins can change it.
create function public.can_view(p_site uuid) returns boolean
language sql stable as $$
  select public.is_staff() and (p_site is null or public.can_access_site(p_site));
$$;

create function public.can_edit(p_site uuid) returns boolean
language sql stable as $$
  select case when p_site is null then public.is_admin() else public.can_access_site(p_site) end;
$$;

create function public.room_site(p_room uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select site_id from rooms where id = p_room;
$$;

-- Link new logins to their staff row. The very first person to sign up becomes admin.
create function public.link_staff() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from staff) then
    insert into staff (email, user_id, role) values (lower(new.email), new.id, 'admin');
  else
    update staff set user_id = new.id where email = lower(new.email);
  end if;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.link_staff();

-- ───────────────────────── Row level security ─────────────────────────

alter table public.sites     enable row level security;
alter table public.rooms     enable row level security;
alter table public.staff     enable row level security;
alter table public.media     enable row level security;
alter table public.playlists enable row level security;
alter table public.schedules enable row level security;
alter table public.devices   enable row level security;

create policy "staff read sites"  on public.sites for select to authenticated using (public.is_staff());
create policy "admins edit sites" on public.sites for all    to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "site rooms" on public.rooms for all to authenticated
  using (public.can_access_site(site_id)) with check (public.can_access_site(site_id));

create policy "read own staff row" on public.staff for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy "admins manage staff" on public.staff for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "view media"   on public.media for select to authenticated using (public.can_view(site_id));
create policy "insert media" on public.media for insert to authenticated with check (public.can_edit(site_id));
create policy "update media" on public.media for update to authenticated using (public.can_edit(site_id)) with check (public.can_edit(site_id));
create policy "delete media" on public.media for delete to authenticated using (public.can_edit(site_id));

create policy "view playlists"   on public.playlists for select to authenticated using (public.can_view(site_id));
create policy "insert playlists" on public.playlists for insert to authenticated with check (public.can_edit(site_id));
create policy "update playlists" on public.playlists for update to authenticated using (public.can_edit(site_id)) with check (public.can_edit(site_id));
create policy "delete playlists" on public.playlists for delete to authenticated using (public.can_edit(site_id));

create policy "site schedules" on public.schedules for all to authenticated
  using (public.can_access_site(public.room_site(room_id)))
  with check (public.can_access_site(public.room_site(room_id)));

-- Staff see TVs in their rooms. TVs never touch this table directly — only through the functions below.
create policy "site devices" on public.devices for select to authenticated
  using (public.is_admin() or public.can_access_site(public.room_site(room_id)));
create policy "site devices update" on public.devices for update to authenticated
  using (public.is_admin() or public.can_access_site(public.room_site(room_id)))
  with check (room_id is null or public.can_access_site(public.room_site(room_id)));
create policy "site devices delete" on public.devices for delete to authenticated
  using (public.is_admin() or public.can_access_site(public.room_site(room_id)));

-- ───────────────────────── TV device functions ─────────────────────────

create function public.new_pairing_code() returns text
language plpgsql set search_path = public as $$
declare
  v_code text;
begin
  loop
    -- No 0/O, 1/I/L so codes are easy to read off a TV across a room.
    select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
      into v_code from generate_series(1, 6);
    exit when not exists (select 1 from devices where pairing_code = v_code);
  end loop;
  return v_code;
end $$;

create function public.authenticate_device(p_device_id uuid, p_secret text) returns public.devices
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_device devices;
begin
  select * into v_device from devices where id = p_device_id;
  if not found or v_device.secret_hash <> encode(digest(p_secret, 'sha256'), 'hex') then
    raise exception 'Unknown device' using errcode = '28000';
  end if;
  return v_device;
end $$;

-- Called by a TV on every launch. Creates it the first time.
create function public.register_device(p_device_id uuid, p_secret text, p_model text, p_app_version text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(p_secret) < 32 then
    raise exception 'Secret too short';
  end if;
  if exists (select 1 from devices where id = p_device_id) then
    perform authenticate_device(p_device_id, p_secret);
    update devices set model = p_model, app_version = p_app_version, last_seen_at = now()
      where id = p_device_id;
  else
    insert into devices (id, secret_hash, pairing_code, model, app_version, last_seen_at)
    values (p_device_id, encode(digest(p_secret, 'sha256'), 'hex'), new_pairing_code(), p_model, p_app_version, now());
  end if;
end $$;

-- Everything a TV needs: its room, or its pairing code, plus the current and upcoming playlists.
create function public.device_state(p_device_id uuid, p_secret text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_device    devices := authenticate_device(p_device_id, p_secret);
  v_schedules jsonb;
begin
  update devices set last_seen_at = now() where id = p_device_id;

  if v_device.room_id is null then
    if v_device.pairing_code is null then
      update devices set pairing_code = new_pairing_code() where id = p_device_id
        returning * into v_device;
    end if;
    return jsonb_build_object('paired', false, 'pairing_code', v_device.pairing_code);
  end if;

  with active as (
    select * from schedules
    where room_id = v_device.room_id and (ends_at is null or ends_at > now())
  ), picked as (
    (select * from active where starts_at <= now() order by starts_at desc limit 1)
    union all
    (select * from active where starts_at > now() and starts_at <= now() + interval '14 days')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'starts_at', s.starts_at,
           'ends_at', s.ends_at,
           'playlist', jsonb_build_object('id', p.id, 'name', p.name, 'items', p.items)
         ) order by s.starts_at), '[]')
    into v_schedules
    from picked s join playlists p on p.id = s.playlist_id;

  return (
    select jsonb_build_object(
      'paired', true,
      'site', si.name,
      'room', r.name,
      'schedules', v_schedules
    )
    from rooms r join sites si on si.id = r.site_id
    where r.id = v_device.room_id
  );
end $$;

-- Dashboard: assign the TV showing this code to a room.
create function public.claim_device(p_code text, p_room_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not can_access_site(room_site(p_room_id)) then
    raise exception 'You don''t have access to that room';
  end if;
  update devices set room_id = p_room_id, pairing_code = null
    where pairing_code = upper(trim(p_code))
    returning id into v_id;
  if v_id is null then
    raise exception 'No TV is showing code %', upper(trim(p_code));
  end if;
  return v_id;
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.register_device(uuid, text, text, text) to anon, authenticated;
grant execute on function public.device_state(uuid, text) to anon, authenticated;
grant execute on function public.claim_device(text, uuid) to authenticated;
grant execute on function
  public.is_staff(), public.is_admin(), public.can_access_site(uuid),
  public.can_view(uuid), public.can_edit(uuid), public.room_site(uuid)
  to authenticated;

-- ───────────────────────── Media storage ─────────────────────────

-- Public read so TVs can download without logging in; file paths are random.
insert into storage.buckets (id, name, public) values ('media', 'media', true)
  on conflict (id) do nothing;

create policy "staff read media files" on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_staff());
create policy "staff upload media files" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_staff());
create policy "staff update media files" on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.is_staff());
create policy "staff delete media files" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.is_staff());
