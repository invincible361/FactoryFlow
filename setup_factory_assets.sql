-- 1. Create the bucket 'factory-assets' if it doesn't exist, and ensure it is PUBLIC
insert into storage.buckets (id, name, public)
values ('factory-assets', 'factory-assets', true)
on conflict (id) do update
set public = true;

-- 2. Remove existing policies to avoid conflicts
drop policy if exists "Factory Public Access" on storage.objects;
drop policy if exists "Factory Public Upload" on storage.objects;

-- 3. Allow EVERYONE to VIEW images in this bucket (Required for Worker App)
create policy "Factory Public Access"
  on storage.objects for select
  using ( bucket_id = 'factory-assets' );

-- 4. Allow EVERYONE to UPLOAD images to this bucket (Required for Admin App)
create policy "Factory Public Upload"
  on storage.objects for insert
  with check ( bucket_id = 'factory-assets' );
