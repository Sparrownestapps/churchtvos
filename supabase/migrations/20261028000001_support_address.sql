-- Support address in the "no active plan" pairing message is now support@churchtvos.com (same function otherwise).
CREATE OR REPLACE FUNCTION public.claim_screen(p_code text, p_location_id uuid, p_name text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'This church does not have an active plan yet, so no TVs can be paired. Contact support at support@churchtvos.com.';
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
end $function$;
