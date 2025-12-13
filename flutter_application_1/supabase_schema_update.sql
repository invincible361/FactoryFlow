-- 1. Modify 'items' table to store detailed operation info (Target + Image)
-- We will add a new column 'operation_details' of type JSONB
-- The structure will be:
-- [
--   { "name": "Op1", "target": 100, "image_url": "https://..." },
--   { "name": "Op2", "target": 200, "image_url": "https://..." }
-- ]
ALTER TABLE items ADD COLUMN operation_details JSONB DEFAULT '[]'::jsonb;

-- 2. Modify 'production_logs' table to store Shift Name
ALTER TABLE production_logs ADD COLUMN shift_name TEXT;

-- 3. Create a Storage Bucket for Images
-- Go to Storage -> Create a new bucket named 'operation-images'
-- Make sure it's Public
-- Add a policy to allow authenticated uploads (or public if you prefer for dev)

-- 4. (Optional) Data Migration if you already have data
-- This is just an example, you might not need it if starting fresh
-- UPDATE items SET operation_details = (
--   SELECT jsonb_agg(jsonb_build_object('name', op, 'target', 0, 'image_url', ''))
--   FROM unnest(operations) as op
-- );
