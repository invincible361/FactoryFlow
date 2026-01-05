-- Fix RLS policies for Geofencing and Out of Bounds tracking
-- The apps use a custom login system and the 'anon' key, so policies must allow 'anon' access.

-- 1. Fix production_outofbounds policies
ALTER TABLE public.production_outofbounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can read their own organization's outofbounds" ON public.production_outofbounds;
DROP POLICY IF EXISTS "Workers can insert their own outofbounds" ON public.production_outofbounds;
DROP POLICY IF EXISTS "Workers can update their own outofbounds" ON public.production_outofbounds;
DROP POLICY IF EXISTS "Allow all for anon" ON public.production_outofbounds;

CREATE POLICY "Allow all for anon" ON public.production_outofbounds FOR ALL USING (true) WITH CHECK (true);

-- 2. Fix worker_boundary_events policies
ALTER TABLE public.worker_boundary_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.worker_boundary_events;
DROP POLICY IF EXISTS "Allow all for anon" ON public.worker_boundary_events;

CREATE POLICY "Allow all for anon" ON public.worker_boundary_events FOR ALL USING (true) WITH CHECK (true);

-- 3. Fix daily_geofence_summaries policies
ALTER TABLE public.daily_geofence_summaries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.daily_geofence_summaries;
DROP POLICY IF EXISTS "Allow all for anon" ON public.daily_geofence_summaries;

CREATE POLICY "Allow all for anon" ON public.daily_geofence_summaries FOR ALL USING (true) WITH CHECK (true);
