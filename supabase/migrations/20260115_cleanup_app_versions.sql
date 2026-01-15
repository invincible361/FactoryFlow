-- Cleanup app_versions table as we are moving to GitHub-based versioning via version.json
DROP TABLE IF EXISTS public.app_versions CASCADE;
