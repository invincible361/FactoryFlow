alter table public.workers add column if not exists photo_url text;
alter table public.workers add column if not exists avatar_url text;
alter table public.workers add column if not exists image_url text;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workers' and column_name = 'image_url'
  ) then
    update public.workers set photo_url = coalesce(photo_url, image_url);
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workers' and column_name = 'imageurl'
  ) then
    update public.workers set photo_url = coalesce(photo_url, imageurl);
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workers' and column_name = 'avatar_url'
  ) then
    update public.workers set photo_url = coalesce(photo_url, avatar_url);
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workers' and column_name = 'photourl'
  ) then
    update public.workers set photo_url = coalesce(photo_url, photourl);
  end if;
end $$;
