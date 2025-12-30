-- Ensure 'profile_photos' bucket exists and is public, with permissive policies
insert into storage.buckets (id, name, public)
values ('profile_photos', 'profile_photos', true)
on conflict (id) do update set public = true;

-- Clean old policies to avoid duplicates
drop policy if exists "Profile Public Access" on storage.objects;
drop policy if exists "Profile Public Upload" on storage.objects;

-- Allow everyone to view images
create policy "Profile Public Access"
  on storage.objects for select
  using ( bucket_id = 'profile_photos' );

-- Allow everyone to upload images
create policy "Profile Public Upload"
  on storage.objects for insert
  with check ( bucket_id = 'profile_photos' );
