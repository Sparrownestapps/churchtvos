-- Remote control: commands to a screen, status from a screen, "play this now" overrides, push-notification registry.
-- Used by the website Control page and the iPhone/iPad/Mac apps. Operators and above may control; only editors and above edit.

-- ───────────────────────── Who may control a screen ─────────────────────────
create function public.can_control_screen(p_screen uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from screens s
    where s.id = p_screen and s.organization_id is not null
      and (public.is_platform_admin() or (
        exists (select 1 from memberships m
                where m.organization_id = s.organization_id and m.user_id = auth.uid()
                  and m.role in ('owner', 'admin', 'editor', 'operator'))
        and public.in_site_scope(s.organization_id, public.location_site(s.location_id))
        and (public.has_module(s.organization_id, 'kids') or public.has_module(s.organization_id, 'slides') or public.has_module(s.organization_id, 'signage'))
      ))
  );
$$;
grant execute on function public.can_control_screen(uuid) to authenticated;

-- ───────────────────────── Commands ─────────────────────────
create table public.screen_commands (
  id              bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations on delete cascade,
  screen_id       uuid not null references public.screens on delete cascade,
  command         text not null check (command in ('next', 'previous', 'jump', 'blank', 'stop', 'start', 'message', 'clear_message')),
  payload         jsonb not null default '{}',
  issued_by       uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  handled_at      timestamptz
);
create index on public.screen_commands (screen_id, handled_at, id);
alter table public.screen_commands enable row level security;
create policy "controllers read commands" on public.screen_commands for select to authenticated using (public.can_control_screen(screen_id));

create table public.screen_overrides (
  screen_id       uuid primary key references public.screens on delete cascade,
  organization_id uuid not null references public.organizations on delete cascade,
  kind            text not null check (kind in ('deck', 'playlist')),
  ref_id          uuid not null,
  until           timestamptz not null,
  issued_by       uuid default auth.uid(),
  created_at      timestamptz not null default now()
);
alter table public.screen_overrides enable row level security;
create policy "controllers read overrides" on public.screen_overrides for select to authenticated using (public.can_control_screen(screen_id));

-- What a screen is showing right now, written by the TV.
create table public.screen_status (
  screen_id       uuid primary key references public.screens on delete cascade,
  organization_id uuid not null references public.organizations on delete cascade,
  module          text,
  state           text not null default 'idle' check (state in ('idle', 'playing', 'blank', 'message')),
  title           text,        -- deck or playlist name
  item_label      text,        -- e.g. "Verse 1 · Great Are You Lord"
  slide_index     int,
  slide_count     int,
  updated_at      timestamptz not null default now()
);
alter table public.screen_status enable row level security;
create policy "members read status" on public.screen_status for select to authenticated
  using (public.is_member(organization_id) and public.in_site_scope(organization_id, public.location_site((select location_id from public.screens s where s.id = screen_id))));

-- ───────────────────────── Sending commands (apps and website) ─────────────────────────
create function public.send_screen_command(p_screen_id uuid, p_command text, p_payload jsonb default '{}')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_id bigint;
  v_kind text;
  v_ref uuid;
  v_minutes int;
  v_text text;
begin
  if not public.can_control_screen(p_screen_id) then raise exception 'You do not have access to control that screen'; end if;
  select organization_id into v_org from screens where id = p_screen_id;
  if (select count(*) from screen_commands where screen_id = p_screen_id and created_at > now() - interval '10 seconds') >= 20 then
    raise exception 'Too many commands, wait a moment';
  end if;
  p_payload := coalesce(p_payload, '{}');

  if p_command = 'jump' and (p_payload->>'index') is null then raise exception 'jump needs an index'; end if;

  if p_command = 'message' then
    v_text := btrim(coalesce(p_payload->>'text', ''));
    if length(v_text) = 0 or length(v_text) > 200 then raise exception 'A message needs 1 to 200 characters'; end if;
    p_payload := jsonb_build_object('text', v_text,
      'seconds', least(300, greatest(5, coalesce((p_payload->>'seconds')::int, 30))),
      'background', coalesce(nullif(p_payload->>'background', ''), '#1B2A4A'));
  end if;

  if p_command = 'start' then
    v_kind := p_payload->>'kind';
    v_ref := nullif(p_payload->>'id', '')::uuid;
    v_minutes := least(1440, greatest(5, coalesce((p_payload->>'minutes')::int, 240)));
    if v_kind = 'deck' then
      if not exists (select 1 from decks where id = v_ref and organization_id = v_org) then raise exception 'Unknown deck'; end if;
      if not public.has_module(v_org, 'slides') then raise exception 'No access to Slides'; end if;
    elsif v_kind = 'playlist' then
      if not exists (select 1 from playlists where id = v_ref and organization_id = v_org) then raise exception 'Unknown playlist'; end if;
      if not public.has_module(v_org, 'kids') then raise exception 'No access to Kids'; end if;
    else
      raise exception 'start needs kind deck or playlist';
    end if;
    insert into screen_overrides (screen_id, organization_id, kind, ref_id, until)
    values (p_screen_id, v_org, v_kind, v_ref, now() + make_interval(mins => v_minutes))
    on conflict (screen_id) do update set kind = excluded.kind, ref_id = excluded.ref_id, until = excluded.until, issued_by = auth.uid(), created_at = now();
  end if;

  if p_command = 'stop' then
    delete from screen_overrides where screen_id = p_screen_id;
  end if;

  insert into screen_commands (organization_id, screen_id, command, payload)
  values (v_org, p_screen_id, p_command, p_payload) returning id into v_id;
  return v_id;
end $$;
grant execute on function public.send_screen_command(uuid, text, jsonb) to authenticated;

-- ───────────────────────── The TV's side ─────────────────────────
-- Commands waiting for this TV (oldest first). Anything older than a minute is dropped, so a TV that was off never replays them.
create function public.device_poll_commands(p_device_id uuid, p_secret text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_screen screens := authenticate_screen(p_device_id, p_secret);
  v_out jsonb;
begin
  update screen_commands set handled_at = now()
    where screen_id = v_screen.id and handled_at is null and created_at < now() - interval '60 seconds';
  with taken as (
    update screen_commands set handled_at = now()
    where screen_id = v_screen.id and handled_at is null
    returning id, command, payload
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'command', command, 'payload', payload) order by id), '[]') into v_out from taken;
  update screens set last_seen_at = now() where id = v_screen.id;
  return v_out;
end $$;

create function public.device_report_status(p_device_id uuid, p_secret text, p_module text, p_state text, p_title text,
                                            p_item_label text, p_slide_index int, p_slide_count int) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_screen screens := authenticate_screen(p_device_id, p_secret);
begin
  if v_screen.organization_id is null then return; end if;
  insert into screen_status (screen_id, organization_id, module, state, title, item_label, slide_index, slide_count, updated_at)
  values (v_screen.id, v_screen.organization_id, p_module, coalesce(nullif(p_state, ''), 'idle'), left(p_title, 200), left(p_item_label, 200), p_slide_index, p_slide_count, now())
  on conflict (screen_id) do update set module = excluded.module, state = excluded.state, title = excluded.title,
    item_label = excluded.item_label, slide_index = excluded.slide_index, slide_count = excluded.slide_count, updated_at = now();
  update screens set last_seen_at = now() where id = v_screen.id;
end $$;

-- ───────────────────────── Push notifications (phones and Macs) ─────────────────────────
create table public.push_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users on delete cascade default auth.uid(),
  platform     text not null check (platform in ('ios', 'macos')),
  token        text not null,
  environment  text not null default 'production' check (environment in ('production', 'sandbox')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, token)
);
alter table public.push_devices enable row level security;
create policy "own devices" on public.push_devices for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table public.notification_prefs (
  user_id         uuid not null references auth.users on delete cascade default auth.uid(),
  organization_id uuid not null references public.organizations on delete cascade,
  offline_alerts  boolean not null default true,
  primary key (user_id, organization_id)
);
alter table public.notification_prefs enable row level security;
create policy "own prefs" on public.notification_prefs for all to authenticated
  using (user_id = auth.uid() and public.is_member(organization_id)) with check (user_id = auth.uid() and public.is_member(organization_id));

-- De-duplication for offline alerts.
create table public.screen_alert_state (
  screen_id     uuid primary key references public.screens on delete cascade,
  alerted_at    timestamptz,   -- when we last said "offline"
  online_since  timestamptz
);
alter table public.screen_alert_state enable row level security;   -- no policies: only the service role touches it

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
  v_override jsonb;
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

  -- A "play this now" override from a phone or the website, if one is in force.
  select case o.kind
           when 'deck' then jsonb_build_object('kind', 'deck', 'until', o.until, 'deck', public.deck_expand(d))
           else jsonb_build_object('kind', 'playlist', 'until', o.until,
                  'playlist', jsonb_build_object('id', p.id, 'name', p.name, 'items', public.kids_expand_items(p.items, v_screen.app_version, v_org.id)))
         end
    into v_override
    from screen_overrides o
    left join decks d on o.kind = 'deck' and d.id = o.ref_id
    left join playlists p on o.kind = 'playlist' and p.id = o.ref_id
    where o.screen_id = v_screen.id and o.until > now()
      and ((o.kind = 'deck' and d.id is not null and v_enabled ? 'slides') or (o.kind = 'playlist' and p.id is not null and v_enabled ? 'kids'));

  return jsonb_build_object(
    'paired', true,
    'organization', jsonb_build_object('name', v_org.name, 'branding', v_org.branding, 'status', v_org.status),
    'site', v_site.name,
    'location', v_loc.name,
    'timezone', coalesce(v_site.timezone, 'America/Toronto'),
    'screen', jsonb_build_object('name', v_screen.name, 'orientation', v_screen.orientation, 'autoplay', v_screen.autoplay),
    'enabled_modules', v_enabled,
    'default_module', v_screen.default_module,
    'module_rules', v_rules,
    'kids', jsonb_build_object('schedules', v_kids),
    'signage', jsonb_build_object('slots', v_slots, 'default_playlist', v_default),
    'slides', jsonb_build_object('schedules', v_decks),
    'override', v_override
  );
end $$;
