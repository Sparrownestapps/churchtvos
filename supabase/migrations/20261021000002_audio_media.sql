-- Media library accepts audio files (countdown music).
alter table public.media drop constraint media_kind_check;
alter table public.media add constraint media_kind_check check (kind in ('video', 'image', 'audio'));
