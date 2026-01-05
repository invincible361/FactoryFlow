-- Fix worker_id column in production_outofbounds to be TEXT instead of UUID
-- This ensures it matches the rest of the system where worker_id is a String (e.g., 'W001')

DO $$
BEGIN
    -- 1. Check if worker_id is UUID and change it to TEXT
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'production_outofbounds'
        AND column_name = 'worker_id'
        AND data_type = 'uuid'
    ) THEN
        -- We need to drop the column and recreate it as TEXT because you can't directly cast UUID to TEXT easily in some Postgres versions without issues
        -- But since we want to keep data if possible, we'll use a temporary column
        ALTER TABLE public.production_outofbounds RENAME COLUMN worker_id TO worker_id_old;
        ALTER TABLE public.production_outofbounds ADD COLUMN worker_id TEXT;
        UPDATE public.production_outofbounds SET worker_id = worker_id_old::text;
        ALTER TABLE public.production_outofbounds DROP COLUMN worker_id_old;
    END IF;

    -- 2. Ensure worker_id is TEXT if it was missing or already something else
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'production_outofbounds'
        AND column_name = 'worker_id'
    ) THEN
        ALTER TABLE public.production_outofbounds ADD COLUMN worker_id TEXT;
    END IF;

END $$;
