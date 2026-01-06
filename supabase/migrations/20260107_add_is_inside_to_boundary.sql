-- Add is_inside column to worker_boundary_events for easier status tracking
ALTER TABLE public.worker_boundary_events ADD COLUMN IF NOT EXISTS is_inside BOOLEAN;

-- Update existing records based on type
UPDATE public.worker_boundary_events SET is_inside = true WHERE type = 'entry';
UPDATE public.worker_boundary_events SET is_inside = false WHERE type = 'exit';
UPDATE public.worker_boundary_events SET is_inside = true WHERE type = 'periodic' AND remarks = 'STILL_INSIDE';
UPDATE public.worker_boundary_events SET is_inside = false WHERE type = 'periodic' AND remarks = 'STILL_OUTSIDE';
