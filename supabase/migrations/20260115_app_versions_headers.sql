-- Add headers column to app_versions for OTA update authentication
ALTER TABLE public.app_versions ADD COLUMN IF NOT EXISTS headers JSONB DEFAULT '{}'::jsonb;
