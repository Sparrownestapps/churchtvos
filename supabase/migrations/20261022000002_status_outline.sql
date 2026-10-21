-- The TV reports its own list of slide labels (what "jump to slide N" means on that TV), so remotes never disagree with it.
alter table public.screen_status add column outline jsonb;   -- ["Welcome","Great Are You Lord (title)","Verse 1",...] index = slide number - 1
alter table public.screen_status add column ref_kind text;   -- 'deck' | 'playlist' | null
alter table public.screen_status add column ref_id uuid;

drop function public.device_report_status(uuid, text, text, text, text, text, int, int);
create function public.device_report_status(p_device_id uuid, p_secret text, p_module text, p_state text, p_title text,
                                            p_item_label text, p_slide_index int, p_slide_count int,
                                            p_outline jsonb default null, p_ref_kind text default null, p_ref_id uuid default null) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_screen screens := authenticate_screen(p_device_id, p_secret);
begin
  if v_screen.organization_id is null then return; end if;
  insert into screen_status (screen_id, organization_id, module, state, title, item_label, slide_index, slide_count, updated_at, outline, ref_kind, ref_id)
  values (v_screen.id, v_screen.organization_id, p_module, coalesce(nullif(p_state, ''), 'idle'), left(p_title, 200), left(p_item_label, 200),
          p_slide_index, p_slide_count, now(), p_outline, p_ref_kind, p_ref_id)
  on conflict (screen_id) do update set module = excluded.module, state = excluded.state, title = excluded.title,
    item_label = excluded.item_label, slide_index = excluded.slide_index, slide_count = excluded.slide_count, updated_at = now(),
    outline = case when p_state = 'idle' then null else coalesce(p_outline, screen_status.outline) end,
    ref_kind = case when p_state = 'idle' then null else coalesce(p_ref_kind, screen_status.ref_kind) end,
    ref_id = case when p_state = 'idle' then null else coalesce(p_ref_id, screen_status.ref_id) end;
  update screens set last_seen_at = now() where id = v_screen.id;
end $$;
