-- FIX RLS POLICIES AND SCHEMA FOR GEOFENCING & OUT OF BOUNDS
-- This script ensures the Admin/Supervisor apps can see the logs.

-- 1. Fix production_outofbounds
-- Ensure column types are correct
DO $$
BEGIN
    -- Change worker_id to TEXT if it's UUID
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'production_outofbounds' 
        AND column_name = 'worker_id' 
        AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.production_outofbounds RENAME COLUMN worker_id TO worker_id_old;
        ALTER TABLE public.production_outofbounds ADD COLUMN worker_id TEXT;
        UPDATE public.production_outofbounds SET worker_id = worker_id_old::text;
        ALTER TABLE public.production_outofbounds DROP COLUMN worker_id_old;
    END IF;
END $$;

-- Enable RLS and set permissive policies for anon (since apps use custom login)
ALTER TABLE public.production_outofbounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can read their own organization's outofbounds" ON public.production_outofbounds;
DROP POLICY IF EXISTS "Workers can insert their own outofbounds" ON public.production_outofbounds;
DROP POLICY IF EXISTS "Workers can update their own outofbounds" ON public.production_outofbounds;
DROP POLICY IF EXISTS "Allow all for anon" ON public.production_outofbounds;
CREATE POLICY "Allow all for anon" ON public.production_outofbounds FOR ALL USING (true) WITH CHECK (true);

-- 2. Fix worker_boundary_events
-- Ensure remarks column exists
ALTER TABLE public.worker_boundary_events ADD COLUMN IF NOT EXISTS remarks TEXT;

-- Enable RLS and set permissive policies
ALTER TABLE public.worker_boundary_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.worker_boundary_events;
DROP POLICY IF EXISTS "Allow all for anon" ON public.worker_boundary_events;
CREATE POLICY "Allow all for anon" ON public.worker_boundary_events FOR ALL USING (true) WITH CHECK (true);

-- 3. Fix daily_geofence_summaries
-- Enable RLS and set permissive policies
ALTER TABLE public.daily_geofence_summaries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.daily_geofence_summaries;
DROP POLICY IF EXISTS "Allow all for anon" ON public.daily_geofence_summaries;
CREATE POLICY "Allow all for anon" ON public.daily_geofence_summaries FOR ALL USING (true) WITH CHECK (true);

-- 4. Fix notifications (Already fixed but for safety)
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon" ON public.notifications;
CREATE POLICY "Allow all for anon" ON public.notifications FOR ALL USING (true) WITH CHECK (true);

-- 5. Add Foreign Key Relationships for easy joining in Supabase
-- production_outofbounds -> workers
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_outofbounds_worker_id_fkey') THEN
        ALTER TABLE public.production_outofbounds 
        ADD CONSTRAINT production_outofbounds_worker_id_fkey 
        FOREIGN KEY (worker_id) 
        REFERENCES public.workers(worker_id) 
        ON DELETE CASCADE;
    END IF;
END $$;

-- worker_boundary_events -> workers
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'worker_boundary_events_worker_id_fkey') THEN
        ALTER TABLE public.worker_boundary_events 
        ADD CONSTRAINT worker_boundary_events_worker_id_fkey 
        FOREIGN KEY (worker_id) 
        REFERENCES public.workers(worker_id) 
        ON DELETE CASCADE;
    END IF;
END $$;
