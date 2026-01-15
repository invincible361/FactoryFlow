-- Table to track app versions for auto-updates
CREATE TABLE IF NOT EXISTS public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_type TEXT NOT NULL, -- 'worker', 'admin', 'supervisor'
    version TEXT NOT NULL, -- e.g., '1.2.0'
    apk_url TEXT NOT NULL, -- URL to the APK file (GitHub Release or Firebase Hosting)
    is_force_update BOOLEAN DEFAULT FALSE,
    release_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(app_type, version)
);

-- Enable RLS
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;

-- Allow anyone to read versions
CREATE POLICY "Allow public read access to app_versions" 
ON public.app_versions FOR SELECT 
USING (true);

-- Insert a dummy record for testing
INSERT INTO public.app_versions (app_type, version, apk_url, is_force_update, release_notes)
VALUES ('worker', '1.0.0', 'https://github.com/invincible361/FactoryFlow/releases/download/v1.0.0/worker-release.apk', false, 'Initial release with auto-update support');
