-- New churches start on a free trial with a ready-to-use room, so a first-time user can pair a TV straight away.
-- (A church created before this had no entitlements, so pairing failed with "Your plan allows 0 TVs".)
-- Trial terms are a placeholder until billing exists: Kids + Signage, 2 TVs, status 'trialing'. current_period_end
-- is informational only; nothing expires yet.

create or replace function public.create_organization(p_name text, p_slug text, p_site text default 'Main Campus')
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_site uuid;
  v_email text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select lower(email) into v_email from auth.users where id = auth.uid();
  insert into organizations (name, slug) values (trim(p_name), lower(trim(p_slug))) returning id into v_org;
  insert into sites (organization_id, name) values (v_org, trim(p_site)) returning id into v_site;
  insert into locations (organization_id, site_id, name, modules) values (v_org, v_site, 'Main Room', '{kids,signage}');
  insert into memberships (organization_id, user_id, email, role) values (v_org, auth.uid(), v_email, 'owner');
  insert into entitlements (organization_id, module, status, tv_limit, plan, current_period_end)
    select v_org, m.id, 'trialing', 2, 'trial', now() + interval '30 days'
    from modules m where m.available;
  return v_org;
end $$;

create or replace function public.claim_screen(p_code text, p_location_id uuid, p_name text default null) returns uuid
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
  if v_limit = 0 then
    raise exception 'This church does not have an active plan yet, so no TVs can be paired. Contact support at keith@sparrownest.com.';
  end if;
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

-- Backfill: churches that were created without a plan or a room.
insert into entitlements (organization_id, module, status, tv_limit, plan, current_period_end)
select o.id, m.id, 'trialing', 2, 'trial', now() + interval '30 days'
from organizations o cross join modules m
where m.available
  and not exists (select 1 from entitlements e where e.organization_id = o.id);

insert into locations (organization_id, site_id, name, modules)
select o.id, (select s.id from sites s where s.organization_id = o.id order by s.created_at limit 1), 'Main Room', '{kids,signage}'
from organizations o
where not exists (select 1 from locations l where l.organization_id = o.id)
  and exists (select 1 from sites s where s.organization_id = o.id);
