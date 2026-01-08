-- Add fcm_token column to workers table
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS fcm_token TEXT;
