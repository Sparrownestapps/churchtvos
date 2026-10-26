-- Dated signage slots, for one-off and "until" scheduling (used by the Church TV OS MCP server, usable by the dashboard later).
-- A slot with start_date/end_date only applies on those dates (in the site's time zone); null = always, as before.
-- The date test happens here in device_state, so TVs on any app version pick it up without an update.
-- source = 'mcp' marks slots made by an AI assistant through the MCP server; their one-image playlists are cleaned up with them.

alter table public.signage_slots add column start_date date;
alter table public.signage_slots add column end_date date;
alter table public.signage_slots add column label text;
alter table public.signage_slots add column source text check (source in ('mcp'));
alter table public.signage_slots add column created_by uuid default auth.uid();
alter table public.signage_slots add constraint signage_slots_dates_check check (end_date is null or start_date is null or end_date >= start_date);
create index on public.signage_slots (organization_id, end_date);

alter table public.signage_playlists add column source text check (source in ('mcp'));

-- Removes expired assistant-made slots (ended more than a day ago in any time zone) and the playlists made for them.
create function public.purge_expired_mcp_slots() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from signage_slots where source = 'mcp' and end_date is not null and end_date < current_date - 2;
  delete from signage_playlists p where p.source = 'mcp'
    and not exists (select 1 from signage_slots s where s.playlist_id = p.id)
    and not exists (select 1 from screens sc where sc.signage_default_playlist_id = p.id);
end $$;
revoke all on function public.purge_expired_mcp_slots() from public, anon, authenticated;

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
  v_today    date;
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
  v_today := (now() at time zone coalesce(v_site.timezone, 'America/Toronto'))::date;

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
             'playlist', jsonb_build_object('id', p.id, 'name', p.name,
                'items', case when v_org.ndi_enabled then p.items else public.ndi_strip(p.items, 'type') end)
           ) order by s.priority, s.created_at), '[]')
      into v_slots
      from signage_slots s join signage_playlists p on p.id = s.playlist_id
      where (s.screen_id = v_screen.id or (v_screen.group_id is not null and s.group_id = v_screen.group_id))
        and (s.start_date is null or s.start_date <= v_today)
        and (s.end_date is null or s.end_date >= v_today);

    select jsonb_build_object('id', p.id, 'name', p.name,
             'items', case when v_org.ndi_enabled then p.items else public.ndi_strip(p.items, 'type') end) into v_default
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
    'experimental', jsonb_build_object('ndi', v_org.ndi_enabled),
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
