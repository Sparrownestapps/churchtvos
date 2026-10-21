-- EXPERIMENTAL: NDI source for Kids playlists, Signage playlists and Slides decks. See NDI-CONTRACT.md.
--
-- The NDI SDK licence for Android is unconfirmed (the licence says Android/fixed-purpose devices need a commercial
-- agreement with NDI), so the feature is OFF for every church. Only the platform administrator can switch it on, per church.
--   * organizations.ndi_enabled  : the flag. Members can read it (the editors hide the option, the TV is told in device_state).
--                                  Only a platform admin can change it (guard trigger), via admin_update_organization(p_ndi).
--   * Saving: a trigger refuses to add or change an NDI item/slide for a church without the flag, and validates the shape.
--   * Playing: device_state leaves NDI items/slides out for a church without the flag, so a stale item never plays.
--   * Audit: every toggle is written to admin_audit_log (who, when).

alter table public.organizations add column ndi_enabled boolean not null default false;

-- ───────────────────────── helpers ─────────────────────────
create function public.org_ndi_enabled(p_org uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select ndi_enabled from organizations where id = p_org), false);
$$;
grant execute on function public.org_ndi_enabled(uuid) to authenticated;

-- Only the elements of a jsonb array whose p_key field is 'ndi' (Kids/Signage items use 'type', deck slides use 'kind').
create function public.ndi_elements(p_items jsonb, p_key text) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(e), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) e
  where e->>p_key = 'ndi';
$$;

-- Everything except the NDI elements (used when a church does not have the flag).
create function public.ndi_strip(p_items jsonb, p_key text) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_agg(e), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) e
  where coalesce(e->>p_key, '') <> 'ndi';
$$;

-- The shape contract. Raises with a readable message.
create function public.ndi_check(e jsonb) returns void
language plpgsql immutable as $$
declare n numeric;
begin
  if jsonb_typeof(e->'source') is distinct from 'string' or btrim(e->>'source') = '' then
    raise exception 'NDI source: the source name is required';
  end if;
  if length(e->>'source') > 200 then raise exception 'NDI source: the source name is too long'; end if;
  if e ? 'address' and jsonb_typeof(e->'address') <> 'null' then
    if jsonb_typeof(e->'address') <> 'string' or length(e->>'address') > 255 or (e->>'address') ~ '\s' then
      raise exception 'NDI source: the address must be a host or IP with an optional :port and no spaces';
    end if;
  end if;
  if e ? 'audio' and jsonb_typeof(e->'audio') not in ('boolean', 'null') then raise exception 'NDI source: audio must be true or false'; end if;
  if e ? 'fit' and (e->>'fit') not in ('fit', 'fill') then raise exception 'NDI source: fit must be "fit" or "fill"'; end if;
  if e ? 'fallback' and (e->>'fallback') not in ('skip', 'message') then raise exception 'NDI source: fallback must be "skip" or "message"'; end if;
  if e ? 'fallback_text' and jsonb_typeof(e->'fallback_text') not in ('string', 'null') then raise exception 'NDI source: fallback_text must be text'; end if;
  if length(coalesce(e->>'fallback_text', '')) > 200 then raise exception 'NDI source: the fallback message is too long (200 characters)'; end if;
  if e ? 'max_wait_seconds' and jsonb_typeof(e->'max_wait_seconds') <> 'null' then
    if jsonb_typeof(e->'max_wait_seconds') <> 'number' then raise exception 'NDI source: max_wait_seconds must be a number'; end if;
    n := (e->>'max_wait_seconds')::numeric;
    if n < 3 or n > 120 or n <> trunc(n) then raise exception 'NDI source: max_wait_seconds must be a whole number from 3 to 120'; end if;
  end if;
  if e ? 'seconds' and jsonb_typeof(e->'seconds') <> 'null' then
    if jsonb_typeof(e->'seconds') <> 'number' then raise exception 'NDI source: seconds must be a number or null'; end if;
    n := (e->>'seconds')::numeric;
    if n < 1 or n > 86400 or n <> trunc(n) then raise exception 'NDI source: seconds must be a whole number from 1 to 86400, or empty'; end if;
  end if;
end $$;

-- ───────────────────────── write guard (playlists, signage playlists, decks) ─────────────────────────
-- p_key is 'type' for playlist items and 'kind' for deck slides. With the flag off, existing NDI entries may stay or be
-- removed but nothing NDI can be added or changed.
create or replace function public.ndi_guard_content() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_key text := case tg_table_name when 'decks' then 'kind' else 'type' end;
  v_new jsonb;
  v_old jsonb := '[]'::jsonb;
  e jsonb;
begin
  v_new := public.ndi_elements(to_jsonb(new) -> case tg_table_name when 'decks' then 'slides' else 'items' end, v_key);
  if jsonb_array_length(v_new) = 0 then return new; end if;
  if tg_op = 'UPDATE' then
    v_old := public.ndi_elements(to_jsonb(old) -> case tg_table_name when 'decks' then 'slides' else 'items' end, v_key);
    if v_new = v_old then return new; end if;   -- untouched (possibly reordered by position only: same array)
  end if;
  if not public.org_ndi_enabled(new.organization_id) then
    raise exception 'NDI sources are an experimental feature that is not enabled for this church';
  end if;
  for e in select x from jsonb_array_elements(v_new) x loop perform public.ndi_check(e); end loop;
  return new;
end $$;

create trigger playlists_ndi_guard before insert or update of items on public.playlists
  for each row execute function public.ndi_guard_content();
create trigger signage_playlists_ndi_guard before insert or update of items on public.signage_playlists
  for each row execute function public.ndi_guard_content();
create trigger decks_ndi_guard before insert or update of slides on public.decks
  for each row execute function public.ndi_guard_content();

-- ───────────────────────── flag guard + audit ─────────────────────────
create or replace function public.organizations_guard_admin_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.status is distinct from old.status or new.reviewed_at is distinct from old.reviewed_at
      or new.ndi_enabled is distinct from old.ndi_enabled)
     and not (public.is_platform_admin() or auth.uid() is null) then
    raise exception 'Only the platform administrator can change this';
  end if;
  return new;
end $$;

create or replace function public.audit_org_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  select lower(email) into v_email from auth.users where id = auth.uid();
  if new.status is distinct from old.status then
    insert into admin_audit_log (actor_email, organization_id, action, detail)
    values (v_email, new.id, case when new.status = 'suspended' then 'church_suspended' else 'church_reactivated' end,
            jsonb_build_object('reason', (select suspended_reason from organization_admin where organization_id = new.id)));
  end if;
  if new.reviewed_at is distinct from old.reviewed_at and new.reviewed_at is not null then
    insert into admin_audit_log (actor_email, organization_id, action) values (v_email, new.id, 'church_reviewed');
  end if;
  if new.ndi_enabled is distinct from old.ndi_enabled then
    insert into admin_audit_log (actor_email, organization_id, action, detail)
    values (v_email, new.id, case when new.ndi_enabled then 'ndi_enabled' else 'ndi_disabled' end,
            jsonb_build_object('feature', 'ndi', 'enabled', new.ndi_enabled));
  end if;
  return new;
end $$;

-- Same call as before plus p_ndi (platform admin only; the guard trigger enforces it again).
drop function public.admin_update_organization(uuid, text, text, text, boolean);
create function public.admin_update_organization(p_org uuid, p_status text default null, p_reason text default null, p_notes text default null, p_reviewed boolean default null, p_ndi boolean default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrators only'; end if;
  insert into organization_admin (organization_id) values (p_org) on conflict do nothing;
  if p_notes is not null then update organization_admin set notes = p_notes where organization_id = p_org; end if;
  if p_status is not null then
    update organization_admin set suspended_reason = case when p_status = 'suspended' then p_reason else null end where organization_id = p_org;
  end if;
  update organizations set
    status = coalesce(p_status, status),
    reviewed_at = case when p_reviewed is true then coalesce(reviewed_at, now()) when p_reviewed is false then null else reviewed_at end,
    ndi_enabled = coalesce(p_ndi, ndi_enabled)
  where id = p_org;
end $$;
grant execute on function public.admin_update_organization(uuid, text, text, text, boolean, boolean) to authenticated;

-- admin_list_organizations gains ndi_enabled.
drop function public.admin_list_organizations();
create function public.admin_list_organizations()
returns table (
  id uuid, name text, slug text, created_at timestamptz, status text, suspended_reason text, admin_notes text, reviewed_at timestamptz,
  owner_emails text[], member_count bigint, screen_count bigint, last_seen_at timestamptz,
  media_count bigint, storage_bytes bigint, song_count bigint, deck_count bigint, playlist_count bigint,
  entitlements jsonb, ndi_enabled boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrators only'; end if;
  return query
  select o.id, o.name, o.slug, o.created_at, o.status,
    (select a.suspended_reason from organization_admin a where a.organization_id = o.id),
    (select a.notes from organization_admin a where a.organization_id = o.id),
    o.reviewed_at,
    coalesce((select array_agg(m.email order by m.created_at) from memberships m where m.organization_id = o.id and m.role = 'owner'), '{}'),
    (select count(*) from memberships m where m.organization_id = o.id),
    (select count(*) from screens s where s.organization_id = o.id),
    (select max(s.last_seen_at) from screens s where s.organization_id = o.id),
    (select count(*) from media md where md.organization_id = o.id),
    (select coalesce(sum(md.size_bytes), 0)::bigint from media md where md.organization_id = o.id),
    (select count(*) from songs sg where sg.organization_id = o.id),
    (select count(*) from decks dk where dk.organization_id = o.id),
    (select count(*) from playlists pl where pl.organization_id = o.id) + (select count(*) from signage_playlists sp where sp.organization_id = o.id),
    coalesce((select jsonb_agg(jsonb_build_object('module', e.module, 'status', e.status, 'tv_limit', e.tv_limit, 'plan', e.plan,
                'current_period_end', e.current_period_end, 'grace_ends_at', e.grace_ends_at, 'live', public.entitlement_live(e)) order by e.module)
              from entitlements e where e.organization_id = o.id), '[]'),
    o.ndi_enabled
  from organizations o
  order by o.created_at desc;
end $$;
grant execute on function public.admin_list_organizations() to authenticated;

-- ───────────────────────── what the TV receives ─────────────────────────
-- Kids playlists: NDI items are left out unless the church has the flag.
create or replace function public.kids_expand_items(p_items jsonb, p_app_version text, p_org uuid) returns jsonb
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
  v_ndi boolean := public.org_ndi_enabled(p_org);
begin
  for v_item in select e from jsonb_array_elements(coalesce(p_items, '[]')) e loop
    if v_item->>'type' = 'ndi' and not v_ndi then continue; end if;
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

-- Decks: NDI slides are left out unless the church has the flag.
create or replace function public.deck_expand(p_deck public.decks) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_theme jsonb := '{}';
  v_out jsonb := '[]';
  v_slide jsonb;
  v_song songs;
  v_exp jsonb;
  v_n int;
  i int;
  v_ndi boolean := public.org_ndi_enabled(p_deck.organization_id);
begin
  if p_deck.theme_id is not null then
    select config into v_theme from slide_themes where id = p_deck.theme_id and organization_id = p_deck.organization_id;
    v_theme := coalesce(v_theme, '{}');
  end if;

  for v_slide in select e from jsonb_array_elements(coalesce(p_deck.slides, '[]')) e loop
    if v_slide->>'kind' = 'ndi' and not v_ndi then continue; end if;
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

-- device_state: Signage playlists are filtered, and the church's experimental flags are included.
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
             'playlist', jsonb_build_object('id', p.id, 'name', p.name,
                'items', case when v_org.ndi_enabled then p.items else public.ndi_strip(p.items, 'type') end)
           ) order by s.priority, s.created_at), '[]')
      into v_slots
      from signage_slots s join signage_playlists p on p.id = s.playlist_id
      where s.screen_id = v_screen.id or (v_screen.group_id is not null and s.group_id = v_screen.group_id);

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
