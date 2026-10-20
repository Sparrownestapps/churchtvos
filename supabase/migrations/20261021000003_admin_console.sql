-- Platform admin console support: church status, trial expiry that really ends access, audit trail, overview.

alter table public.organizations
  add column status text not null default 'active' check (status in ('active', 'suspended')),
  add column suspended_reason text,
  add column admin_notes text,
  add column reviewed_at timestamptz;   -- null = a new church the platform admin has not looked at yet

-- A church that signed up before this migration has been "seen" by definition.
update public.organizations set reviewed_at = now() where slug = 'forward-church';

-- Is a plan row currently in force? Suspended churches have nothing; trials end on current_period_end.
create function public.entitlement_live(e public.entitlements) returns boolean
language sql stable as $$
  select e.status = 'active'
      or (e.status = 'trialing' and (e.current_period_end is null or e.current_period_end > now()))
      or (e.status = 'past_due' and e.grace_ends_at > now());
$$;

create or replace function public.module_enabled(p_org uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from entitlements e join organizations o on o.id = e.organization_id
    where e.organization_id = p_org and e.module = p_module and o.status = 'active'
      and public.entitlement_live(e)
  );
$$;

create or replace function public.tv_limit(p_org uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(max(e.tv_limit), 0)::int from entitlements e join organizations o on o.id = e.organization_id
  where e.organization_id = p_org and o.status = 'active' and public.entitlement_live(e);
$$;
grant execute on function public.entitlement_live(public.entitlements) to authenticated;

-- ───────────────────────── Audit trail ─────────────────────────
create table public.admin_audit_log (
  id              bigint generated always as identity primary key,
  at              timestamptz not null default now(),
  actor           uuid default auth.uid(),
  actor_email     text,
  organization_id uuid,
  action          text not null,
  detail          jsonb not null default '{}'
);
create index on public.admin_audit_log (organization_id, at desc);
alter table public.admin_audit_log enable row level security;
create policy "platform admins read audit" on public.admin_audit_log for select to authenticated using (public.is_platform_admin());
create policy "platform admins write audit" on public.admin_audit_log for insert to authenticated with check (public.is_platform_admin());

create function public.audit_entitlement_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  select lower(email) into v_email from auth.users where id = auth.uid();
  insert into admin_audit_log (actor_email, organization_id, action, detail)
  values (v_email, coalesce(new.organization_id, old.organization_id), 'plan_' || lower(tg_op),
    jsonb_build_object('module', coalesce(new.module, old.module),
      'from', case when tg_op = 'INSERT' then null else to_jsonb(old) - 'organization_id' end,
      'to', case when tg_op = 'DELETE' then null else to_jsonb(new) - 'organization_id' end));
  return coalesce(new, old);
end $$;
create trigger entitlements_audit after insert or update or delete on public.entitlements
  for each row execute function public.audit_entitlement_change();

create function public.audit_org_status_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  select lower(email) into v_email from auth.users where id = auth.uid();
  if new.status is distinct from old.status then
    insert into admin_audit_log (actor_email, organization_id, action, detail)
    values (v_email, new.id, case when new.status = 'suspended' then 'church_suspended' else 'church_reactivated' end,
            jsonb_build_object('reason', new.suspended_reason));
  end if;
  if new.reviewed_at is distinct from old.reviewed_at and new.reviewed_at is not null then
    insert into admin_audit_log (actor_email, organization_id, action) values (v_email, new.id, 'church_reviewed');
  end if;
  return new;
end $$;
create trigger organizations_audit after update on public.organizations
  for each row execute function public.audit_org_status_change();

-- Only platform admins may change status, notes and review markers (church owners can edit name/branding only).
create function public.organizations_guard_admin_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.status is distinct from old.status or new.suspended_reason is distinct from old.suspended_reason
      or new.admin_notes is distinct from old.admin_notes or new.reviewed_at is distinct from old.reviewed_at)
     and not (public.is_platform_admin() or auth.uid() is null) then
    raise exception 'Only the platform administrator can change this';
  end if;
  return new;
end $$;
create trigger organizations_guard before update on public.organizations
  for each row execute function public.organizations_guard_admin_columns();

-- Church owners and admins must not read the admin-only columns through the normal select, so expose them only via the RPC below.
revoke select (admin_notes, suspended_reason) on public.organizations from authenticated;
grant select (admin_notes, suspended_reason) on public.organizations to service_role;

-- ───────────────────────── Overview for the platform admin ─────────────────────────
create function public.admin_list_organizations()
returns table (
  id uuid, name text, slug text, created_at timestamptz, status text, suspended_reason text, admin_notes text, reviewed_at timestamptz,
  owner_emails text[], member_count bigint, screen_count bigint, last_seen_at timestamptz,
  media_count bigint, storage_bytes bigint, song_count bigint, deck_count bigint, playlist_count bigint,
  entitlements jsonb
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrators only'; end if;
  return query
  select o.id, o.name, o.slug, o.created_at, o.status, o.suspended_reason, o.admin_notes, o.reviewed_at,
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
              from entitlements e where e.organization_id = o.id), '[]')
  from organizations o
  order by o.created_at desc;
end $$;
grant execute on function public.admin_list_organizations() to authenticated;

-- Mark a church as looked at, set status, notes: single functions so the console does not need column grants.
create function public.admin_update_organization(p_org uuid, p_status text default null, p_reason text default null, p_notes text default null, p_reviewed boolean default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrators only'; end if;
  update organizations set
    status = coalesce(p_status, status),
    suspended_reason = case when p_status = 'active' then null when p_status = 'suspended' then p_reason else suspended_reason end,
    admin_notes = coalesce(p_notes, admin_notes),
    reviewed_at = case when p_reviewed is true then coalesce(reviewed_at, now()) when p_reviewed is false then null else reviewed_at end
  where id = p_org;
end $$;
grant execute on function public.admin_update_organization(uuid, text, text, text, boolean) to authenticated;

-- New signups appear as "new" until reviewed; create_organization keeps its trial and room (see previous migration).

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
    'organization', jsonb_build_object('name', v_org.name, 'branding', v_org.branding, 'status', v_org.status),
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
