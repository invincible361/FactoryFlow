-- Comprehensive RLS Fix for all tables
-- This ensures that authenticated users can perform all operations

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
        
        -- Drop existing policy if any
        EXECUTE format('DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.%I', t);
        
        -- Create policy to allow all operations for authenticated users
        EXECUTE format('CREATE POLICY "Enable all for authenticated users" ON public.%I FOR ALL TO authenticated USING (true) WITH CHECK (true)', t);
    END LOOP;
END $$;
