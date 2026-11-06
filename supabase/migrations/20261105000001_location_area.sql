-- Optional "area" for a location (room), e.g. "Kids Wing", so the dashboard can group TVs by site, then area, then room.
-- Rooms with no area sit directly under their site. Nothing on the TV reads this.
alter table public.locations add column if not exists area text;
comment on column public.locations.area is 'Optional area within the site (e.g. Kids Wing) used to group rooms and TVs in the dashboard.';
