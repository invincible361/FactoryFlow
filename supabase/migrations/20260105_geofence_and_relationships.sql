-- Geofence Summaries and Enhanced Tracking
-- 1. Daily Geofence Summaries
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
    UNIQUE(worker_id, date, organization_code)
);

CREATE INDEX IF NOT EXISTS idx_geofence_summary_org_date ON public.daily_geofence_summaries(organization_code, date);

-- 2. Enhanced Tracking Columns
DO $$
BEGIN
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

-- 3. Relationships Fix
DO $$
BEGIN
    -- Foreign Keys for Workers
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'worker_breaks_worker_id_fkey') THEN
        ALTER TABLE public.worker_breaks ADD CONSTRAINT worker_breaks_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'worker_boundary_events_worker_id_fkey') THEN
        ALTER TABLE public.worker_boundary_events ADD CONSTRAINT worker_boundary_events_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_assignments_worker_id_fkey') THEN
        ALTER TABLE public.work_assignments ADD CONSTRAINT work_assignments_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'login_logs_worker_id_fkey') THEN
        ALTER TABLE public.login_logs ADD CONSTRAINT login_logs_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_worker_id_fkey') THEN
        ALTER TABLE public.notifications ADD CONSTRAINT notifications_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'daily_geofence_summaries_worker_id_fkey') THEN
        ALTER TABLE public.daily_geofence_summaries ADD CONSTRAINT daily_geofence_summaries_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id) ON DELETE CASCADE;
    END IF;
END $$;
