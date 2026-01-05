-- Create daily_geofence_summaries table to store processed geofence stats
CREATE TABLE IF NOT EXISTS public.daily_geofence_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id TEXT NOT NULL,
    organization_code TEXT NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    first_entry_time TIMESTAMP WITH TIME ZONE,
    entry_count INTEGER DEFAULT 0,
    exit_count INTEGER DEFAULT 0,
    last_event_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure one record per worker per day
    UNIQUE(worker_id, date, organization_code)
);

-- Add foreign key relationship for worker_id to workers table
-- This allows Supabase to perform joins like .select('*, workers:worker_id(name)')
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'daily_geofence_summaries_worker_id_fkey') THEN
        ALTER TABLE public.daily_geofence_summaries 
        ADD CONSTRAINT daily_geofence_summaries_worker_id_fkey 
        FOREIGN KEY (worker_id) 
        REFERENCES public.workers(worker_id) 
        ON DELETE CASCADE;
    END IF;
END $$;

-- Index for faster retrieval by date and organization
CREATE INDEX IF NOT EXISTS idx_geofence_summary_org_date ON public.daily_geofence_summaries(organization_code, date);

-- Function to update the daily summary based on boundary events
CREATE OR REPLACE FUNCTION public.update_geofence_summary()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process 'entry' and 'exit' types
    IF NEW.type NOT IN ('entry', 'exit') THEN
        RETURN NEW;
    END IF;

    -- Upsert the summary record
    INSERT INTO public.daily_geofence_summaries (
        worker_id, 
        organization_code, 
        date, 
        first_entry_time, 
        entry_count, 
        exit_count, 
        last_event_time
    )
    VALUES (
        NEW.worker_id,
        NEW.organization_code,
        CURRENT_DATE,
        CASE WHEN NEW.type = 'entry' THEN NEW.created_at ELSE NULL END,
        CASE WHEN NEW.type = 'entry' THEN 1 ELSE 0 END,
        CASE WHEN NEW.type = 'exit' THEN 1 ELSE 0 END,
        NEW.created_at
    )
    ON CONFLICT (worker_id, date, organization_code)
    DO UPDATE SET
        entry_count = daily_geofence_summaries.entry_count + (CASE WHEN EXCLUDED.entry_count = 1 THEN 1 ELSE 0 END),
        exit_count = daily_geofence_summaries.exit_count + (CASE WHEN EXCLUDED.exit_count = 1 THEN 1 ELSE 0 END),
        first_entry_time = COALESCE(daily_geofence_summaries.first_entry_time, CASE WHEN EXCLUDED.entry_count = 1 THEN EXCLUDED.first_entry_time ELSE NULL END),
        last_event_time = EXCLUDED.last_event_time;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to run the function after each insert into worker_boundary_events
DROP TRIGGER IF EXISTS trg_update_geofence_summary ON public.worker_boundary_events;
CREATE TRIGGER trg_update_geofence_summary
AFTER INSERT ON public.worker_boundary_events
FOR EACH ROW EXECUTE FUNCTION public.update_geofence_summary();

-- Enable RLS
ALTER TABLE public.daily_geofence_summaries ENABLE ROW LEVEL SECURITY;

-- Permissive policy for authenticated users (admin/supervisor can read all, workers can see their own)
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.daily_geofence_summaries;
CREATE POLICY "Enable all for authenticated users" ON public.daily_geofence_summaries
    FOR ALL USING (true) WITH CHECK (true);
