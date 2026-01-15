-- Add test records for admin and supervisor apps
INSERT INTO public.app_versions (app_type, version, apk_url, is_force_update, release_notes)
VALUES 
('admin', '1.0.0', 'https://github.com/invincible361/FactoryFlow/releases/download/v1.0.0/admin-release.apk', false, 'Initial admin release with auto-update support'),
('supervisor', '1.0.0', 'https://github.com/invincible361/FactoryFlow/releases/download/v1.0.0/supervisor-release.apk', false, 'Initial supervisor release with auto-update support')
ON CONFLICT (app_type, version) DO NOTHING;
