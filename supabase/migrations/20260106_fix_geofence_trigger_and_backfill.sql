-- Fix geofence summary trigger to use event timestamp for date and backfill existing data
-- This ensures that events are grouped by the date they occurred, not the date the trigger ran.

-- 1. Update the function to be more robust
CREATE OR REPLACE FUNCTION public.update_geofence_summary()
RETURNS TRIGGER AS $$
DECLARE
    event_date DATE;
BEGIN
    -- Only process 'entry' and 'exit' types
    IF NEW.type NOT IN ('entry', 'exit') THEN
        RETURN NEW;
    END IF;

    -- Use the date from created_at (in local time if possible, but UTC is standard for DB)
    -- We'll use the date part of the event's created_at
    event_date := (NEW.created_at AT TIME ZONE 'UTC')::DATE;

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
        event_date,
        CASE WHEN NEW.type = 'entry' THEN NEW.created_at ELSE NULL END,
        CASE WHEN NEW.type = 'entry' THEN 1 ELSE 0 END,
        CASE WHEN NEW.type = 'exit' THEN 1 ELSE 0 END,
        NEW.created_at
    )
    ON CONFLICT (worker_id, date, organization_code)
    DO UPDATE SET
        -- Only update first_entry_time if it's currently NULL and the new event is an entry
        first_entry_time = CASE 
            WHEN daily_geofence_summaries.first_entry_time IS NULL AND EXCLUDED.first_entry_time IS NOT NULL THEN EXCLUDED.first_entry_time
            WHEN daily_geofence_summaries.first_entry_time IS NOT NULL AND EXCLUDED.first_entry_time IS NOT NULL AND EXCLUDED.first_entry_time < daily_geofence_summaries.first_entry_time THEN EXCLUDED.first_entry_time
            ELSE daily_geofence_summaries.first_entry_time
        END,
        entry_count = daily_geofence_summaries.entry_count + (CASE WHEN NEW.type = 'entry' THEN 1 ELSE 0 END),
        exit_count = daily_geofence_summaries.exit_count + (CASE WHEN NEW.type = 'exit' THEN 1 ELSE 0 END),
        last_event_time = GREATEST(daily_geofence_summaries.last_event_time, NEW.created_at);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Backfill existing data from worker_boundary_events
-- Clear existing summaries to ensure a clean backfill
TRUNCATE TABLE public.daily_geofence_summaries;

-- Insert summaries for all existing entry/exit events
INSERT INTO public.daily_geofence_summaries (
    worker_id,
    organization_code,
    date,
    first_entry_time,
    entry_count,
    exit_count,
    last_event_time
)
SELECT 
    worker_id,
    organization_code,
    (created_at AT TIME ZONE 'UTC')::DATE as event_date,
    MIN(CASE WHEN type = 'entry' THEN created_at ELSE NULL END) as first_entry_time,
    COUNT(CASE WHEN type = 'entry' THEN 1 ELSE NULL END) as entry_count,
    COUNT(CASE WHEN type = 'exit' THEN 1 ELSE NULL END) as exit_count,
    MAX(created_at) as last_event_time
FROM 
    public.worker_boundary_events
WHERE 
    type IN ('entry', 'exit')
GROUP BY 
    worker_id, 
    organization_code, 
    (created_at AT TIME ZONE 'UTC')::DATE
ON CONFLICT (worker_id, date, organization_code) DO NOTHING;

-- 3. Ensure RLS is still correct
ALTER TABLE public.daily_geofence_summaries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon" ON public.daily_geofence_summaries;
CREATE POLICY "Allow all for anon" ON public.daily_geofence_summaries FOR ALL USING (true) WITH CHECK (true);
