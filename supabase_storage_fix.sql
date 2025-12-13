-- 1. Create the bucket 'operation-images' if it doesn't exist, and ensure it is PUBLIC
insert into storage.buckets (id, name, public)
values ('operation-images', 'operation-images', true)
on conflict (id) do update
set public = true;

-- 2. Remove existing policies to avoid conflicts
drop policy if exists "Public Access" on storage.objects;
drop policy if exists "Public Upload" on storage.objects;

-- 3. Allow EVERYONE to VIEW images in this bucket (Required for Worker App)
create policy "Public Access"
  on storage.objects for select
  using ( bucket_id = 'operation-images' );

-- 4. Allow EVERYONE to UPLOAD images to this bucket (Required for Admin App without Auth)
create policy "Public Upload"
  on storage.objects for insert
  with check ( bucket_id = 'operation-images' );
