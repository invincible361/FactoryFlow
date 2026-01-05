-- Fix worker_boundary_events schema to ensure it matches the code's expectations
-- and handle the 'exit_time' column error reported by the user.

DO $$
BEGIN
    -- 1. Ensure the table exists with the base columns we definitely need
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'worker_boundary_events') THEN
        CREATE TABLE public.worker_boundary_events (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            worker_id TEXT NOT NULL,
            organization_code TEXT NOT NULL,
            type TEXT NOT NULL,
            latitude DOUBLE PRECISION,
            longitude DOUBLE PRECISION,
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
    END IF;

    -- 2. If 'exit_time' column exists, make it nullable
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'worker_boundary_events'
        AND column_name = 'exit_time'
    ) THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN exit_time DROP NOT NULL;
    END IF;

    -- 3. If 'created_at' is missing, add it
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'worker_boundary_events'
        AND column_name = 'created_at'
    ) THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- 4. Ensure 'type' exists
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'worker_boundary_events'
        AND column_name = 'type'
    ) THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN type TEXT DEFAULT 'periodic';
    END IF;

    -- 5. Ensure 'latitude' and 'longitude' exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'latitude') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN latitude DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'longitude') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN longitude DOUBLE PRECISION;
    END IF;

END $$;
