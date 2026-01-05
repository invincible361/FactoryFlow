-- Add remarks column to worker_boundary_events table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'worker_boundary_events'
        AND column_name = 'remarks'
    ) THEN
        ALTER TABLE public.worker_boundary_events ADD COLUMN remarks TEXT;
    END IF;
END $$;
