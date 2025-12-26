-- Create Attendance Table for tracking worker presence
CREATE TABLE IF NOT EXISTS public.attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id TEXT NOT NULL,
    organization_code TEXT NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    check_in TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    check_out TIMESTAMP WITH TIME ZONE,
    shift_name TEXT,
    shift_start_time TEXT,
    shift_end_time TEXT,
    is_early_leave BOOLEAN DEFAULT FALSE,
    is_overtime BOOLEAN DEFAULT FALSE,
    status TEXT, -- 'On Time', 'Early Leave', 'Overtime', 'Both'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure one record per worker per day
    UNIQUE(worker_id, date, organization_code)
);

-- Fix relationship for Postgrest (Supabase needs an explicit foreign key to link tables)
-- We link worker_id in attendance to worker_id in workers
-- First ensure the workers table has a unique constraint on worker_id (already exists but for safety)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'attendance_worker_id_fkey') THEN
        ALTER TABLE public.attendance 
        ADD CONSTRAINT attendance_worker_id_fkey 
        FOREIGN KEY (worker_id) 
        REFERENCES public.workers(worker_id) 
        ON DELETE CASCADE;
    END IF;
END $$;

-- Enable RLS
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

-- Allow all for anon (for MVP simplicity as requested in previous scripts)
DROP POLICY IF EXISTS "Allow all for anon" ON public.attendance;
CREATE POLICY "Allow all for anon" ON public.attendance FOR ALL USING (true);
