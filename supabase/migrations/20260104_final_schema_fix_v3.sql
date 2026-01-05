-- Final fix for worker_boundary_events schema to resolve NOT NULL constraint violations
-- This migration ensures that all potential columns are nullable and the table structure is robust.

DO $$
BEGIN
    -- 1. Ensure the table exists
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

    -- 2. Make 'exit_time' nullable if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_time'
    ) THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN exit_time DROP NOT NULL;
    END IF;

    -- 3. Make 'entry_time' nullable if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_time'
    ) THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN entry_time DROP NOT NULL;
    END IF;

    -- 4. Make 'worker_name' nullable if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'worker_boundary_events' AND column_name = 'worker_name'
    ) THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN worker_name DROP NOT NULL;
    END IF;

    -- 5. Make 'duration_minutes' nullable if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'worker_boundary_events' AND column_name = 'duration_minutes'
    ) THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN duration_minutes DROP NOT NULL;
    END IF;

    -- 6. Make coordinate columns nullable if they exist
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_latitude') THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN exit_latitude DROP NOT NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_longitude') THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN exit_longitude DROP NOT NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_latitude') THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN entry_latitude DROP NOT NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_longitude') THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN entry_longitude DROP NOT NULL;
    END IF;

    -- 7. Ensure RLS is enabled and policies are permissive for logging
    ALTER TABLE public.worker_boundary_events ENABLE ROW LEVEL SECURITY;
    
    DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.worker_boundary_events;
    CREATE POLICY "Enable all for authenticated users" ON public.worker_boundary_events
        FOR ALL USING (true) WITH CHECK (true);

END $$;
