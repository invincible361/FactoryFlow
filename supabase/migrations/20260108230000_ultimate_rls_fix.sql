-- Ultimate RLS Fix for ALL tables in the public schema
-- This ensures that both authenticated and anonymous users can perform all operations
-- to prevent any 42501 (Unauthorized) errors in the apps.

DO $$
DECLARE
    tbl_name text;
    pol_name text;
BEGIN
    FOR tbl_name IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_type = 'BASE TABLE'
    LOOP
        -- Enable RLS
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl_name);
        
        -- Drop all existing policies for this table to start clean
        FOR pol_name IN 
            SELECT policyname 
            FROM pg_policies 
            WHERE schemaname = 'public' 
            AND tablename = tbl_name
        LOOP
            EXECUTE format('DROP POLICY %I ON public.%I', pol_name, tbl_name);
        END LOOP;
        
        -- Create the catch-all policy
        EXECUTE format('CREATE POLICY "Enable all for everyone" ON public.%I FOR ALL USING (true) WITH CHECK (true)', tbl_name);
        
        RAISE NOTICE 'Applied catch-all RLS policy to table: %', tbl_name;
    END LOOP;
END $$;
