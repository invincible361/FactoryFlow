-- Comprehensive RLS Fix for all tables (Allowing Anon for MVP)
-- This ensures that both authenticated and anonymous users can perform all operations
-- Note: In production, you should use Supabase Auth and restrict these policies.

DO $$
DECLARE
    t text;
    tables_to_fix text[] := ARRAY[
        'work_assignments',
        'notifications',
        'production_logs',
        'workers',
        'machines',
        'items',
        'organizations',
        'shifts',
        'worker_boundary_events',
        'worker_breaks',
        'daily_geofence_summaries',
        'login_logs'
    ];
BEGIN
    FOREACH t IN ARRAY tables_to_fix LOOP
        -- Enable RLS
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        
        -- Drop existing policies if any
        EXECUTE format('DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.%I', t);
        EXECUTE format('DROP POLICY IF EXISTS "Enable all for everyone" ON public.%I', t);
        
        -- Create policy to allow all operations for both authenticated and anon users
        EXECUTE format('CREATE POLICY "Enable all for everyone" ON public.%I FOR ALL USING (true) WITH CHECK (true)', t);
    END LOOP;
END $$;
