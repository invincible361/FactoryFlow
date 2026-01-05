-- Enhanced geofence tracking columns for worker_boundary_events
DO $$
BEGIN
    -- Add coordinate and time columns if they don't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_latitude') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN entry_latitude DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_longitude') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN entry_longitude DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_latitude') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN exit_latitude DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_longitude') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN exit_longitude DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'entry_time') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN entry_time TIMESTAMP WITH TIME ZONE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'exit_time') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN exit_time TIMESTAMP WITH TIME ZONE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'worker_boundary_events' AND column_name = 'duration_minutes') THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN duration_minutes TEXT;
    END IF;
END $$;
