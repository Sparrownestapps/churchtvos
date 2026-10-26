-- Organizing playlists and decks: folders per application (Kids playlists, Signage playlists, Slides decks), archiving,
-- and a built-in "Made by assistant" folder for what an AI assistant creates through the MCP server.
-- Mirrors media_folders: deleting a folder moves what is inside up one level; a folder limited to a site passes that on.

create table public.content_folders (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations on delete cascade,
  module          text not null check (module in ('kids', 'signage', 'slides')),
  parent_id       uuid,
  site_id         uuid references public.sites on delete cascade,   -- null = all sites; inherited by everything inside
  name            text not null check (length(trim(name)) > 0),
  system          text check (system in ('assistant')),             -- 'assistant' = the built-in "Made by assistant" folder
  created_at      timestamptz not null default now(),
  unique (id, organization_id, module),
  foreign key (parent_id, organization_id, module)
    references public.content_folders (id, organization_id, module) on delete set null (parent_id)
);
create unique index content_folders_unique_name on public.content_folders
  (organization_id, module, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'), lower(name));
create unique index content_folders_one_assistant on public.content_folders (organization_id, module) where system = 'assistant';

alter table public.content_folders enable row level security;
create policy "view content folders"   on public.content_folders for select to authenticated using (public.can_view_content(organization_id, site_id, module));
create policy "insert content folders" on public.content_folders for insert to authenticated with check (public.can_edit_content(organization_id, site_id, module));
create policy "update content folders" on public.content_folders for update to authenticated
  using (public.can_edit_content(organization_id, site_id, module)) with check (public.can_edit_content(organization_id, site_id, module));
create policy "delete content folders" on public.content_folders for delete to authenticated using (public.can_edit_content(organization_id, site_id, module));

-- Folder, archive and origin on the three kinds of content.
alter table public.playlists         add column folder_id uuid references public.content_folders on delete set null;
alter table public.signage_playlists add column folder_id uuid references public.content_folders on delete set null;
alter table public.decks             add column folder_id uuid references public.content_folders on delete set null;
alter table public.playlists         add column archived_at timestamptz;
alter table public.signage_playlists add column archived_at timestamptz;
alter table public.decks             add column archived_at timestamptz;
alter table public.playlists         add column source text check (source in ('mcp'));
alter table public.decks             add column source text check (source in ('mcp'));
create index on public.playlists (organization_id, folder_id);
create index on public.signage_playlists (organization_id, folder_id);
create index on public.decks (organization_id, folder_id);

-- Deleting a folder moves its sub-folders and contents up one level (nothing is deleted with it).
create function public.content_folder_reparent() returns trigger
language plpgsql as $$
begin
  update public.content_folders set parent_id = old.parent_id where parent_id = old.id;
  update public.playlists set folder_id = old.parent_id where folder_id = old.id;
  update public.signage_playlists set folder_id = old.parent_id where folder_id = old.id;
  update public.decks set folder_id = old.parent_id where folder_id = old.id;
  return old;
end $$;
create trigger content_folders_reparent before delete on public.content_folders
  for each row execute function public.content_folder_reparent();

create function public.content_folder_inherit_site() returns trigger
language plpgsql as $$
declare v_parent_site uuid;
begin
  if new.parent_id is not null then
    select site_id into v_parent_site from public.content_folders where id = new.parent_id;
    if v_parent_site is not null then new.site_id := v_parent_site; end if;
  end if;
  return new;
end $$;
create trigger content_folders_inherit_site before insert or update of parent_id on public.content_folders
  for each row execute function public.content_folder_inherit_site();

-- Content placed in a folder: the folder must be the same church and application; a site-limited folder sets the site.
-- TG_ARGV[0] = the table's application.
create function public.content_in_folder() returns trigger
language plpgsql as $$
declare v_folder public.content_folders;
begin
  if new.folder_id is null then return new; end if;
  select * into v_folder from public.content_folders where id = new.folder_id;
  if v_folder.id is null or v_folder.organization_id <> new.organization_id or v_folder.module <> TG_ARGV[0] then
    raise exception 'That folder belongs to a different library';
  end if;
  if v_folder.site_id is not null then new.site_id := v_folder.site_id; end if;
  return new;
end $$;
create trigger playlists_in_folder before insert or update of folder_id on public.playlists
  for each row execute function public.content_in_folder('kids');
create trigger signage_playlists_in_folder before insert or update of folder_id on public.signage_playlists
  for each row execute function public.content_in_folder('signage');
create trigger decks_in_folder before insert or update of folder_id on public.decks
  for each row execute function public.content_in_folder('slides');

-- ───────────────────────── Tidying assistant-made signage ─────────────────────────
-- Per church, callable by its members (the MCP server and the Signage page call it): removes assistant-made slots that ended
-- more than two days ago, then assistant-made signage playlists that are still in "Made by assistant" (not moved by a person),
-- are used by no slot and no screen default, and haven't changed for a week.
create function public.tidy_assistant_content(p_org uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_member(p_org) then raise exception 'No access'; end if;
  delete from signage_slots where organization_id = p_org and source = 'mcp' and end_date is not null and end_date < current_date - 2;
  delete from signage_playlists p
    where p.organization_id = p_org and p.source = 'mcp' and p.updated_at < now() - interval '7 days'
      and (p.folder_id is null or p.folder_id in (select id from content_folders where organization_id = p_org and system = 'assistant'))
      and not exists (select 1 from signage_slots s where s.playlist_id = p.id)
      and not exists (select 1 from screens sc where sc.signage_default_playlist_id = p.id);
  get diagnostics v_n = row_count;
  return v_n;
end $$;
grant execute on function public.tidy_assistant_content(uuid) to authenticated;

-- The old all-churches version is superseded.
drop function if exists public.purge_expired_mcp_slots();

-- File what assistants already made into each church's "Made by assistant" folder.
insert into public.content_folders (organization_id, module, name, system)
select distinct organization_id, 'signage', 'Made by assistant', 'assistant' from public.signage_playlists where source = 'mcp'
on conflict do nothing;
update public.signage_playlists p set folder_id = f.id
  from public.content_folders f
  where p.source = 'mcp' and p.folder_id is null and f.organization_id = p.organization_id and f.module = 'signage' and f.system = 'assistant';
