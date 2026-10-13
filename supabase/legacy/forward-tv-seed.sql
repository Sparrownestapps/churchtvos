-- Forward Church sites and rooms

insert into public.sites (name) values ('Cambridge'), ('Kitchener'), ('Brant');

insert into public.rooms (site_id, name)
select s.id, r.name
from (values
  ('Cambridge', 'Room 201'),
  ('Cambridge', 'Room 204'),
  ('Cambridge', 'Room 205'),
  ('Cambridge', 'Area 31'),
  ('Cambridge', 'Main Hallway'),
  ('Cambridge', 'Secondary Hallway'),
  ('Kitchener', 'Elementary'),
  ('Kitchener', 'Nursery'),
  ('Kitchener', 'Preschool'),
  ('Brant', 'Room 1'),
  ('Brant', 'Room 2'),
  ('Brant', 'Room 3')
) as r(site, name)
join public.sites s on s.name = r.site;
