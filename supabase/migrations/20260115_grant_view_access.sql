-- Grant access to analytics views for anon and authenticated roles
GRANT SELECT ON public.daily_worker_summary TO anon, authenticated;
GRANT SELECT ON public.machine_utilization_summary TO anon, authenticated;
GRANT SELECT ON public.production_efficiency_summary TO anon, authenticated;
GRANT SELECT ON public.exception_report TO anon, authenticated;

-- Ensure the underlying tables also allow select for the organization
-- (This might already be handled by existing RLS, but we'll make sure the views work)
-- Since views are created by the postgres role (default), they usually bypass RLS 
-- unless SECURITY INVOKER is used. The current views are SECURITY DEFINER (default).
