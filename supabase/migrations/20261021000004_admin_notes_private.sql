-- Internal notes and the suspension reason must never be readable by a church's own owners.
-- Column grants cannot hide a column from `select *`, so they live in a platform-admin-only table.

create table public.organization_admin (
  organization_id  uuid primary key references public.organizations on delete cascade,
  notes            text,
  suspended_reason text
);
alter table public.organization_admin enable row level security;
create policy "platform admins only" on public.organization_admin for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

insert into public.organization_admin (organization_id, notes, suspended_reason)
select id, admin_notes, suspended_reason from public.organizations
where admin_notes is not null or suspended_reason is not null;

-- Functions that mention the old columns must go first.
drop function public.admin_list_organizations();
drop function public.admin_update_organization(uuid, text, text, text, boolean);
drop trigger organizations_guard on public.organizations;
drop trigger organizations_audit on public.organizations;
drop function public.organizations_guard_admin_columns();
drop function public.audit_org_status_change();

alter table public.organizations drop column admin_notes, drop column suspended_reason;
grant select on public.organizations to authenticated;   -- back to the default table-level grant

create function public.organizations_guard_admin_columns() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.status is distinct from old.status or new.reviewed_at is distinct from old.reviewed_at)
     and not (public.is_platform_admin() or auth.uid() is null) then
    raise exception 'Only the platform administrator can change this';
  end if;
  return new;
end $$;
create trigger organizations_guard before update on public.organizations
  for each row execute function public.organizations_guard_admin_columns();

create function public.audit_org_status_change() returns trigger
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
  return new;
end $$;
create trigger organizations_audit after update on public.organizations
  for each row execute function public.audit_org_status_change();

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
              from entitlements e where e.organization_id = o.id), '[]')
  from organizations o
  order by o.created_at desc;
end $$;
grant execute on function public.admin_list_organizations() to authenticated;

create function public.admin_update_organization(p_org uuid, p_status text default null, p_reason text default null, p_notes text default null, p_reviewed boolean default null)
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
    reviewed_at = case when p_reviewed is true then coalesce(reviewed_at, now()) when p_reviewed is false then null else reviewed_at end
  where id = p_org;
end $$;
grant execute on function public.admin_update_organization(uuid, text, text, text, boolean) to authenticated;
