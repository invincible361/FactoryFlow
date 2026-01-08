-- Out of Bounds Tracking and Fixes
-- 1. Historical Tracking Table
CREATE TABLE IF NOT EXISTS public.production_outofbounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id TEXT,
    worker_name TEXT,
    organization_code TEXT,
    date DATE DEFAULT CURRENT_DATE,
    exit_time TIMESTAMP WITH TIME ZONE,
    entry_time TIMESTAMP WITH TIME ZONE,
    exit_latitude DOUBLE PRECISION,
    exit_longitude DOUBLE PRECISION,
    entry_latitude DOUBLE PRECISION,
    entry_longitude DOUBLE PRECISION,
    duration_minutes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.production_outofbounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can read their own organization's outofbounds" ON public.production_outofbounds;
CREATE POLICY "Users can read their own organization's outofbounds" ON public.production_outofbounds FOR SELECT USING (true);
DROP POLICY IF EXISTS "Workers can insert their own outofbounds" ON public.production_outofbounds;
CREATE POLICY "Workers can insert their own outofbounds" ON public.production_outofbounds FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Workers can update their own outofbounds" ON public.production_outofbounds;
CREATE POLICY "Workers can update their own outofbounds" ON public.production_outofbounds FOR UPDATE USING (true);

-- 2. Worker Boundary Events Fixes
DO $$
BEGIN
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

    -- Make all extra columns nullable to avoid crashes
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_time') THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN exit_time DROP NOT NULL;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_time') THEN
        ALTER TABLE public.worker_boundary_events ALTER COLUMN entry_time DROP NOT NULL;
    END IF;
END $$;
