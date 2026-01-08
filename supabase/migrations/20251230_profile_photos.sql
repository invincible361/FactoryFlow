-- Profile Photos Storage and Columns
-- 1. Storage Bucket
insert into storage.buckets (id, name, public)
values ('profile_photos', 'profile_photos', true)
on conflict (id) do update set public = true;

drop policy if exists "Profile Public Access" on storage.objects;
drop policy if exists "Profile Public Upload" on storage.objects;

create policy "Profile Public Access" on storage.objects for select using ( bucket_id = 'profile_photos' );
create policy "Profile Public Upload" on storage.objects for insert with check ( bucket_id = 'profile_photos' );

-- 2. Worker Photo Columns
alter table public.workers add column if not exists photo_url text;
alter table public.workers add column if not exists avatar_url text;
alter table public.workers add column if not exists image_url text;

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'workers' and column_name = 'image_url') then
    update public.workers set photo_url = coalesce(photo_url, image_url);
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'workers' and column_name = 'avatar_url') then
    update public.workers set photo_url = coalesce(photo_url, avatar_url);
  end if;
end $$;
