-- Migration to ensure supervisor_quantity exists
ALTER TABLE public.production_logs ADD COLUMN IF NOT EXISTS supervisor_quantity INTEGER;
