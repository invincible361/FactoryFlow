-- 1. Create the buckets if they don't exist, and ensure they are PUBLIC
insert into storage.buckets (id, name, public)
values 
  ('operation_images', 'operation_images', true),
  ('operation_documents', 'operation_documents', true)
on conflict (id) do update
set public = true;

-- 2. Remove existing policies to avoid conflicts
drop policy if exists "Public Access Images" on storage.objects;
drop policy if exists "Public Upload Images" on storage.objects;
drop policy if exists "Public Access Documents" on storage.objects;
drop policy if exists "Public Upload Documents" on storage.objects;

-- 3. Allow EVERYONE to VIEW files in these buckets
create policy "Public Access Images"
  on storage.objects for select
  using ( bucket_id = 'operation_images' );

create policy "Public Access Documents"
  on storage.objects for select
  using ( bucket_id = 'operation_documents' );

-- 4. Allow EVERYONE to UPLOAD files to these buckets
create policy "Public Upload Images"
  on storage.objects for insert
  with check ( bucket_id = 'operation_images' );

create policy "Public Upload Documents"
  on storage.objects for insert
  with check ( bucket_id = 'operation_documents' );
