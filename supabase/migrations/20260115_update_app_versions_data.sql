-- Update app versions in Supabase
-- This table is used by VersionService to check for updates

-- Admin App
INSERT INTO public.app_versions (app_type, version, apk_url, is_force_update, release_notes, headers)
VALUES (
    'admin', 
    '1.0.9', 
    'https://github.com/invincible361/FactoryFlow/releases/download/v1.0.9-admin/factoryflow_admin_v1.0.9.apk', 
    false, 
    'Stability improvements and time offset fixes.',
    '{}'::jsonb
)
ON CONFLICT (app_type, version) DO UPDATE 
SET apk_url = EXCLUDED.apk_url, 
    is_force_update = EXCLUDED.is_force_update, 
    release_notes = EXCLUDED.release_notes,
    headers = EXCLUDED.headers;

-- Supervisor App
INSERT INTO public.app_versions (app_type, version, apk_url, is_force_update, release_notes, headers)
VALUES (
    'supervisor', 
    '1.1.9', 
    'https://github.com/invincible361/FactoryFlow/releases/download/v1.1.9-supervisor/factoryflow_supervisor_v1.1.9.apk', 
    false, 
    'Stability improvements and time offset fixes.',
    '{}'::jsonb
)
ON CONFLICT (app_type, version) DO UPDATE 
SET apk_url = EXCLUDED.apk_url, 
    is_force_update = EXCLUDED.is_force_update, 
    release_notes = EXCLUDED.release_notes,
    headers = EXCLUDED.headers;

-- Worker App
INSERT INTO public.app_versions (app_type, version, apk_url, is_force_update, release_notes, headers)
VALUES (
    'worker', 
    '1.2.9', 
    'https://github.com/invincible361/FactoryFlow/releases/download/v1.2.9-worker/factoryflow_worker_v1.2.9.apk', 
    false, 
    'Stability improvements, time offset fixes, and server-side event tracking.',
    '{}'::jsonb
)
ON CONFLICT (app_type, version) DO UPDATE 
SET apk_url = EXCLUDED.apk_url, 
    is_force_update = EXCLUDED.is_force_update, 
    release_notes = EXCLUDED.release_notes,
    headers = EXCLUDED.headers;
