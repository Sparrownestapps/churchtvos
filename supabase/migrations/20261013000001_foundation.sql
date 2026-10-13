-- Church TV OS: multi-church foundation.
-- Organizations, memberships (role + module access + site scope), sites/locations,
-- screens (TVs), per-screen module schedules, Kids content, Signage content,
-- entitlements, row-level security, and the TV device functions.

create extension if not exists pgcrypto with schema extensions;

-- ───────────────────────── Platform admins ─────────────────────────
-- Keith (and anyone he adds). Can see every organization and manage entitlements.
create table public.platform_admins (
  email   text primary key,
  user_id uuid unique references auth.users on delete set null
);
alter table public.platform_admins enable row level security;
insert into public.platform_admins (email) values ('keith@sparrownest.com');

-- ───────────────────────── Organizations ─────────────────────────
create table public.organizations (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  slug               text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}$'),
  -- {"logo_url": "...", "primary_color": "#...", "accent_color": "#..."}
  branding           jsonb not null default '{}',
  stripe_customer_id text,
  created_at         timestamptz not null default now()
);

create table public.sites (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  name            text not null,
  timezone        text not null default 'America/Toronto',
  created_at      timestamptz not null default now(),
  unique (organization_id, name),
  unique (id, organization_id)
);

-- Rooms, lobbies, hallways.
create table public.locations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  site_id         uuid not null,
  name            text not null,
  created_at      timestamptz not null default now(),
  unique (site_id, name),
  unique (id, organization_id),
  foreign key (site_id, organization_id) references public.sites (id, organization_id) on delete cascade
);

-- ───────────────────────── Memberships ─────────────────────────
-- Add a row by email before someone signs up; it links to their login automatically.
create table public.memberships (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  user_id         uuid references auth.users on delete cascade,
  email           text not null,
  role            text not null check (role in ('owner', 'admin', 'editor', 'operator')),
  modules         text[] not null default '{kids,signage}',
  site_ids        uuid[],            -- null = all sites
  created_at      timestamptz not null default now(),
  unique (organization_id, email),
  check (modules <@ array['kids', 'signage'])
);
create index on public.memberships (user_id);

-- ───────────────────────── Entitlements (billing) ─────────────────────────
-- What each organization has paid for. One row per module. Billing code (Stripe, later) writes these.
create table public.entitlements (
  organization_id uuid not null references public.organizations on delete cascade,
  module          text not null check (module in ('kids', 'signage')),
  status          text not null default 'active' check (status in ('trialing', 'active', 'past_due', 'canceled')),
  tv_limit        int  not null default 0,
  plan            text not null default 'standard',   -- 'internal' = free internal plan
  grace_ends_at   timestamptz,                         -- past_due modules keep working until then
  current_period_end timestamptz,
  primary key (organization_id, module)
);

-- ───────────────────────── Media and playlists ─────────────────────────
-- site_id null = shared across the whole organization.
create table public.media (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  site_id         uuid references public.sites on delete cascade,
  title           text not null,
  kind            text not null check (kind in ('video', 'image')),
  storage_path    text not null unique,   -- always starts with '<organization_id>/'
  url             text not null,
  size_bytes      bigint,
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now()
);

-- Kids playlist. items is the JSON the TV plays, e.g.
-- [{"type":"video","title":"Week 1","url":"https://…","media_id":"…"},
--  {"type":"countdown","title":"Service starts in","seconds":300},
--  {"type":"lyrics","title":"Song","slides":["Verse 1…","Chorus…"]}]
create table public.playlists (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  site_id         uuid references public.sites on delete cascade,
  name            text not null,
  items           jsonb not null default '[]',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, organization_id)
);

-- A Kids playlist shows in a location from starts_at until ends_at (or until the next one starts).
create table public.schedules (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  location_id     uuid not null,
  playlist_id     uuid not null,
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  created_at      timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at),
  foreign key (location_id, organization_id) references public.locations (id, organization_id) on delete cascade,
  foreign key (playlist_id, organization_id) references public.playlists (id, organization_id) on delete cascade
);
create index on public.schedules (location_id, starts_at);

-- Signage playlist. items: [{"type":"image"|"video","title":"…","url":"…","seconds":10,"media_id":"…"}]
create table public.signage_playlists (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  site_id         uuid references public.sites on delete cascade,
  name            text not null,
  items           jsonb not null default '[]',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, organization_id)
);

-- ───────────────────────── Screens ─────────────────────────
create table public.screen_groups (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  name            text not null,
  created_at      timestamptz not null default now(),
  unique (organization_id, name),
  unique (id, organization_id)
);

-- Each TV. It identifies itself with a random id + secret it generates on first launch.
-- organization_id / location_id stay null until someone enters its pairing code in the dashboard.
create table public.screens (
  id              uuid primary key,
  secret_hash     text not null,
  pairing_code    text unique,
  organization_id uuid references public.organizations on delete cascade,
  location_id     uuid,
  group_id        uuid,
  name            text,
  orientation     text not null default 'landscape' check (orientation in ('landscape', 'portrait', 'portrait_flipped')),
  default_module  text not null default 'kids' check (default_module in ('kids', 'signage', 'off')),
  -- Signage content when no slot is active ("Default content"); null = black screen.
  signage_default_playlist_id uuid,
  model           text,
  app_version     text,
  last_seen_at    timestamptz,
  created_at      timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (location_id, organization_id) references public.locations (id, organization_id),
  foreign key (group_id, organization_id) references public.screen_groups (id, organization_id) on delete set null (group_id),
  foreign key (signage_default_playlist_id, organization_id) references public.signage_playlists (id, organization_id) on delete set null (signage_default_playlist_id)
);
create index on public.screens (organization_id);

-- Which module a screen (or group of screens) runs, and when. This is what makes mixed TVs work:
-- e.g. Signage Mon–Sat, Kids on Sunday 08:00–13:00. Times are in the site's time zone.
-- Latest-created / highest priority wins when slots overlap. No match = the screen's default_module.
create table public.screen_schedules (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  screen_id       uuid,
  group_id        uuid,
  module          text not null check (module in ('kids', 'signage', 'off')),
  days            int[] not null default '{0,1,2,3,4,5,6}',   -- 0 = Sunday
  start_time      time not null default '00:00',
  end_time        time not null default '23:59:59',
  priority        int  not null default 0,
  created_at      timestamptz not null default now(),
  check ((screen_id is null) <> (group_id is null)),
  check (end_time > start_time),
  foreign key (screen_id, organization_id) references public.screens (id, organization_id) on delete cascade,
  foreign key (group_id, organization_id) references public.screen_groups (id, organization_id) on delete cascade
);

-- Recurring Signage slots: which playlist plays on a screen or group at which times.
create table public.signage_slots (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  screen_id       uuid,
  group_id        uuid,
  playlist_id     uuid not null,
  days            int[] not null default '{0,1,2,3,4,5,6}',
  start_time      time not null default '00:00',
  end_time        time not null default '23:59:59',
  priority        int  not null default 0,
  created_at      timestamptz not null default now(),
  check ((screen_id is null) <> (group_id is null)),
  check (end_time > start_time),
  foreign key (screen_id, organization_id) references public.screens (id, organization_id) on delete cascade,
  foreign key (group_id, organization_id) references public.screen_groups (id, organization_id) on delete cascade,
  foreign key (playlist_id, organization_id) references public.signage_playlists (id, organization_id) on delete cascade
);

create function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger playlists_updated_at before update on public.playlists
  for each row execute function public.touch_updated_at();
create trigger signage_playlists_updated_at before update on public.signage_playlists
  for each row execute function public.touch_updated_at();

-- ───────────────────────── Access helpers ─────────────────────────

create function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from platform_admins where user_id = auth.uid());
$$;

create function public.is_member(p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships where organization_id = p_org and user_id = auth.uid())
      or public.is_platform_admin();
$$;

-- Owners and admins manage people, sites, screens and billing.
create function public.is_org_admin(p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
                 where organization_id = p_org and user_id = auth.uid() and role in ('owner', 'admin'))
      or public.is_platform_admin();
$$;

create function public.has_module(p_org uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
                 where organization_id = p_org and user_id = auth.uid()
                   and (role in ('owner', 'admin') or p_module = any (modules)))
      or public.is_platform_admin();
$$;

-- Site scope: null site (organization-wide) needs all-sites access.
create function public.in_site_scope(p_org uuid, p_site uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m
                 where m.organization_id = p_org and m.user_id = auth.uid()
                   and (m.role in ('owner', 'admin') or m.site_ids is null
                        or (p_site is not null and p_site = any (m.site_ids))))
      or public.is_platform_admin();
$$;

-- Content (media/playlists): view needs module access; shared content (site null) is visible to everyone in the org.
create function public.can_view_content(p_org uuid, p_site uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_module(p_org, p_module)
     and (p_site is null or public.in_site_scope(p_org, p_site));
$$;

-- Editing needs the editor role or above, module access and site scope.
create function public.can_edit_content(p_org uuid, p_site uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select (public.is_platform_admin() or exists (
            select 1 from memberships
            where organization_id = p_org and user_id = auth.uid() and role in ('owner', 'admin', 'editor')))
     and public.has_module(p_org, p_module)
     and public.in_site_scope(p_org, p_site);
$$;

create function public.location_site(p_location uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select site_id from locations where id = p_location;
$$;

-- Link new logins to their invitations.
create function public.link_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update memberships set user_id = new.id where email = lower(new.email) and user_id is null;
  update platform_admins set user_id = new.id where email = lower(new.email) and user_id is null;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.link_user();

-- Invitations for people who already have a login link up right away.
create function public.membership_normalize() returns trigger
language plpgsql security definer set search_path = public, auth as $$
begin
  new.email := lower(new.email);
  if new.user_id is null then
    select id into new.user_id from auth.users where lower(email) = new.email;
  end if;
  return new;
end $$;

create trigger memberships_normalize before insert or update of email on public.memberships
  for each row execute function public.membership_normalize();

-- An organization must always keep at least one owner.
create function public.keep_an_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'DELETE' and old.role = 'owner') or (tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner') then
    if not exists (select 1 from memberships where organization_id = old.organization_id and role = 'owner' and id <> old.id)
       and exists (select 1 from organizations where id = old.organization_id) then
      raise exception 'An organization needs at least one owner';
    end if;
  end if;
  return coalesce(new, old);
end $$;

create trigger memberships_keep_owner before update or delete on public.memberships
  for each row execute function public.keep_an_owner();

-- ───────────────────────── Row level security ─────────────────────────

alter table public.organizations      enable row level security;
alter table public.sites              enable row level security;
alter table public.locations          enable row level security;
alter table public.memberships        enable row level security;
alter table public.entitlements       enable row level security;
alter table public.media              enable row level security;
alter table public.playlists          enable row level security;
alter table public.schedules          enable row level security;
alter table public.signage_playlists  enable row level security;
alter table public.screen_groups      enable row level security;
alter table public.screens            enable row level security;
alter table public.screen_schedules   enable row level security;
alter table public.signage_slots      enable row level security;

create policy "members read org" on public.organizations for select to authenticated using (public.is_member(id));
create policy "admins update org" on public.organizations for update to authenticated
  using (public.is_org_admin(id)) with check (public.is_org_admin(id));
create policy "platform admins manage orgs" on public.organizations for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy "members read sites" on public.sites for select to authenticated using (public.is_member(organization_id));
create policy "admins manage sites" on public.sites for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

create policy "members read locations" on public.locations for select to authenticated using (public.is_member(organization_id));
create policy "admins manage locations" on public.locations for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

create policy "read memberships" on public.memberships for select to authenticated
  using (user_id = auth.uid() or public.is_org_admin(organization_id));
create policy "admins manage memberships" on public.memberships for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

create policy "members read entitlements" on public.entitlements for select to authenticated
  using (public.is_member(organization_id));
create policy "platform admins manage entitlements" on public.entitlements for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy "view media"   on public.media for select to authenticated
  using (public.is_member(organization_id) and (site_id is null or public.in_site_scope(organization_id, site_id)));
create policy "insert media" on public.media for insert to authenticated
  with check (public.can_edit_content(organization_id, site_id, 'kids') or public.can_edit_content(organization_id, site_id, 'signage'));
create policy "update media" on public.media for update to authenticated
  using (public.can_edit_content(organization_id, site_id, 'kids') or public.can_edit_content(organization_id, site_id, 'signage'))
  with check (public.can_edit_content(organization_id, site_id, 'kids') or public.can_edit_content(organization_id, site_id, 'signage'));
create policy "delete media" on public.media for delete to authenticated
  using (public.can_edit_content(organization_id, site_id, 'kids') or public.can_edit_content(organization_id, site_id, 'signage'));

create policy "view playlists"   on public.playlists for select to authenticated using (public.can_view_content(organization_id, site_id, 'kids'));
create policy "insert playlists" on public.playlists for insert to authenticated with check (public.can_edit_content(organization_id, site_id, 'kids'));
create policy "update playlists" on public.playlists for update to authenticated
  using (public.can_edit_content(organization_id, site_id, 'kids')) with check (public.can_edit_content(organization_id, site_id, 'kids'));
create policy "delete playlists" on public.playlists for delete to authenticated using (public.can_edit_content(organization_id, site_id, 'kids'));

create policy "view signage playlists"   on public.signage_playlists for select to authenticated using (public.can_view_content(organization_id, site_id, 'signage'));
create policy "insert signage playlists" on public.signage_playlists for insert to authenticated with check (public.can_edit_content(organization_id, site_id, 'signage'));
create policy "update signage playlists" on public.signage_playlists for update to authenticated
  using (public.can_edit_content(organization_id, site_id, 'signage')) with check (public.can_edit_content(organization_id, site_id, 'signage'));
create policy "delete signage playlists" on public.signage_playlists for delete to authenticated using (public.can_edit_content(organization_id, site_id, 'signage'));

create policy "view schedules" on public.schedules for select to authenticated
  using (public.can_view_content(organization_id, public.location_site(location_id), 'kids'));
create policy "edit schedules" on public.schedules for all to authenticated
  using (public.can_edit_content(organization_id, public.location_site(location_id), 'kids'))
  with check (public.can_edit_content(organization_id, public.location_site(location_id), 'kids'));

create policy "members read screen groups" on public.screen_groups for select to authenticated using (public.is_member(organization_id));
create policy "admins manage screen groups" on public.screen_groups for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

-- TVs never touch these tables directly; they use the functions below.
create policy "members read screens" on public.screens for select to authenticated
  using (organization_id is not null and public.is_member(organization_id)
         and public.in_site_scope(organization_id, public.location_site(location_id)));
create policy "admins update screens" on public.screens for update to authenticated
  using (organization_id is not null and public.is_org_admin(organization_id))
  with check (organization_id is not null and public.is_org_admin(organization_id));
create policy "admins delete screens" on public.screens for delete to authenticated
  using (organization_id is not null and public.is_org_admin(organization_id));

create policy "members read screen schedules" on public.screen_schedules for select to authenticated using (public.is_member(organization_id));
create policy "admins manage screen schedules" on public.screen_schedules for all to authenticated
  using (public.is_org_admin(organization_id)) with check (public.is_org_admin(organization_id));

create policy "members read signage slots" on public.signage_slots for select to authenticated using (public.has_module(organization_id, 'signage'));
create policy "editors manage signage slots" on public.signage_slots for all to authenticated
  using (public.can_edit_content(organization_id, null, 'signage')) with check (public.can_edit_content(organization_id, null, 'signage'));

-- ───────────────────────── Onboarding ─────────────────────────

-- Creates an organization with the caller as owner. Entitlements are added by a platform admin (or by billing, later).
create function public.create_organization(p_name text, p_slug text, p_site text default 'Main Campus')
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_email text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  insert into organizations (name, slug) values (trim(p_name), lower(trim(p_slug))) returning id into v_org;
  insert into sites (organization_id, name) values (v_org, trim(p_site));
  insert into memberships (organization_id, user_id, email, role) values (v_org, auth.uid(), v_email, 'owner');
  return v_org;
end $$;

-- ───────────────────────── Entitlement helpers ─────────────────────────

-- Is a module switched on for an organization right now? Past-due modules work until the grace period ends.
create function public.module_enabled(p_org uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from entitlements
    where organization_id = p_org and module = p_module
      and (status in ('active', 'trialing') or (status = 'past_due' and grace_ends_at > now()))
  );
$$;

-- How many TVs an organization may pair: the largest limit among its enabled modules.
create function public.tv_limit(p_org uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(max(tv_limit), 0)::int from entitlements
  where organization_id = p_org
    and (status in ('active', 'trialing') or (status = 'past_due' and grace_ends_at > now()));
$$;

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
    exit when not exists (select 1 from screens where pairing_code = v_code);
  end loop;
  return v_code;
end $$;

create function public.authenticate_screen(p_screen_id uuid, p_secret text) returns public.screens
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_screen screens;
begin
  select * into v_screen from screens where id = p_screen_id;
  if not found or v_screen.secret_hash <> encode(digest(p_secret, 'sha256'), 'hex') then
    raise exception 'Unknown device' using errcode = '28000';
  end if;
  return v_screen;
end $$;

-- Called by a TV on every launch. Creates it the first time.
create function public.register_device(p_device_id uuid, p_secret text, p_model text, p_app_version text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(p_secret) < 32 then
    raise exception 'Secret too short';
  end if;
  if exists (select 1 from screens where id = p_device_id) then
    perform authenticate_screen(p_device_id, p_secret);
    update screens set model = p_model, app_version = p_app_version, last_seen_at = now()
      where id = p_device_id;
  else
    insert into screens (id, secret_hash, pairing_code, model, app_version, last_seen_at)
    values (p_device_id, encode(digest(p_secret, 'sha256'), 'hex'), new_pairing_code(), p_model, p_app_version, now());
  end if;
end $$;

-- Everything a TV needs. The TV works out which module to show from module_rules (so it keeps
-- switching correctly while offline); the server only decides which modules are paid for.
create function public.device_state(p_device_id uuid, p_secret text) returns jsonb
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

  select coalesce(jsonb_agg(m.module), '[]') into v_enabled
    from (values ('kids'), ('signage')) m(module) where module_enabled(v_org.id, m.module);

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

-- Dashboard: assign the TV showing this code to a location. Blocked above the organization's TV limit.
create function public.claim_screen(p_code text, p_location_id uuid, p_name text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org   uuid;
  v_id    uuid;
  v_limit int;
begin
  select organization_id into v_org from locations where id = p_location_id;
  if v_org is null or not is_org_admin(v_org) then
    raise exception 'You don''t have access to that location';
  end if;

  v_limit := tv_limit(v_org);
  if (select count(*) from screens where organization_id = v_org) >= v_limit then
    raise exception 'Your plan allows % TV(s). Remove a TV or upgrade to add more.', v_limit;
  end if;

  update screens set organization_id = v_org, location_id = p_location_id,
                     name = coalesce(nullif(trim(p_name), ''), name), pairing_code = null
    where pairing_code = upper(trim(p_code))
    returning id into v_id;
  if v_id is null then
    raise exception 'No TV is showing code %', upper(trim(p_code));
  end if;
  return v_id;
end $$;

-- Unpair: the TV forgets the organization and shows a new pairing code.
create function public.release_screen(p_screen_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from screens where id = p_screen_id;
  if v_org is null or not is_org_admin(v_org) then
    raise exception 'You don''t have access to that TV';
  end if;
  delete from screens where id = p_screen_id;   -- the TV re-registers itself on its next poll
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.register_device(uuid, text, text, text) to anon, authenticated;
grant execute on function public.device_state(uuid, text) to anon, authenticated;
grant execute on function public.claim_screen(text, uuid, text) to authenticated;
grant execute on function public.release_screen(uuid) to authenticated;
grant execute on function public.create_organization(text, text, text) to authenticated;
grant execute on function
  public.is_platform_admin(), public.is_member(uuid), public.is_org_admin(uuid), public.has_module(uuid, text),
  public.in_site_scope(uuid, uuid), public.can_view_content(uuid, uuid, text), public.can_edit_content(uuid, uuid, text),
  public.location_site(uuid), public.module_enabled(uuid, text), public.tv_limit(uuid)
  to authenticated;

-- ───────────────────────── Media storage ─────────────────────────
-- Files live under '<organization_id>/…'. Public read so TVs can download without logging in; paths are random.
insert into storage.buckets (id, name, public) values ('media', 'media', true)
  on conflict (id) do nothing;

create function public.storage_org(p_name text) returns uuid
language sql immutable as $$
  select case when (storage.foldername(p_name))[1] ~ '^[0-9a-f-]{36}$'
              then (storage.foldername(p_name))[1]::uuid end;
$$;
grant execute on function public.storage_org(text) to authenticated;

create policy "members read media files" on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(public.storage_org(name)));
create policy "editors upload media files" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (public.can_edit_content(public.storage_org(name), null, 'kids')
                                       or public.can_edit_content(public.storage_org(name), null, 'signage')));
create policy "editors update media files" on storage.objects for update to authenticated
  using (bucket_id = 'media' and (public.can_edit_content(public.storage_org(name), null, 'kids')
                                  or public.can_edit_content(public.storage_org(name), null, 'signage')));
create policy "editors delete media files" on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (public.can_edit_content(public.storage_org(name), null, 'kids')
                                  or public.can_edit_content(public.storage_org(name), null, 'signage')));
