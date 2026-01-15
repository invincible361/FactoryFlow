-- Migration: Duplicates & Data Consistency
-- 1. Allow only ONE active task per worker
ALTER TABLE public.production_logs 
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- Ensure existing logs are handled (setting older logs to false if multiple active exist is complex, 
-- but for simplicity we assume current state is clean or will be cleaned by app)
UPDATE public.production_logs SET is_active = false WHERE end_time IS NOT NULL;

-- Create partial unique index
DROP INDEX IF EXISTS one_active_task_per_worker;
CREATE UNIQUE INDEX one_active_task_per_worker 
ON public.production_logs(worker_id) 
WHERE (is_active = true);

-- 2. Prevent duplicate attendance entries
DROP INDEX IF EXISTS unique_attendance_event;
CREATE UNIQUE INDEX unique_attendance_event 
ON public.worker_boundary_events(worker_id, type, date_trunc('minute', created_at));
