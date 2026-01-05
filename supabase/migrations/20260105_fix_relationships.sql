-- Fix relationships for Postgrest (Supabase needs explicit foreign keys to link tables)
-- This fixes the PGRST200 errors by allowing Supabase to auto-detect relationships.

DO $$
BEGIN
    -- 1. Fix worker_breaks -> workers relationship
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'worker_breaks') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'worker_breaks_worker_id_fkey') THEN
            ALTER TABLE public.worker_breaks 
            ADD CONSTRAINT worker_breaks_worker_id_fkey 
            FOREIGN KEY (worker_id) 
            REFERENCES public.workers(worker_id) 
            ON DELETE CASCADE;
        END IF;
    END IF;

    -- 2. Fix worker_boundary_events -> workers relationship
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'worker_boundary_events') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'worker_boundary_events_worker_id_fkey') THEN
            ALTER TABLE public.worker_boundary_events 
            ADD CONSTRAINT worker_boundary_events_worker_id_fkey 
            FOREIGN KEY (worker_id) 
            REFERENCES public.workers(worker_id) 
            ON DELETE CASCADE;
        END IF;
    END IF;

    -- 3. Fix work_assignments -> workers relationship
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'work_assignments') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_assignments_worker_id_fkey') THEN
            ALTER TABLE public.work_assignments 
            ADD CONSTRAINT work_assignments_worker_id_fkey 
            FOREIGN KEY (worker_id) 
            REFERENCES public.workers(worker_id) 
            ON DELETE CASCADE;
        END IF;
    END IF;

    -- 4. Fix login_logs -> workers relationship
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'login_logs') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'login_logs_worker_id_fkey') THEN
            ALTER TABLE public.login_logs 
            ADD CONSTRAINT login_logs_worker_id_fkey 
            FOREIGN KEY (worker_id) 
            REFERENCES public.workers(worker_id) 
            ON DELETE CASCADE;
        END IF;
    END IF;

    -- 5. Fix notifications -> workers relationship
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notifications') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'notifications_worker_id_fkey') THEN
            ALTER TABLE public.notifications 
            ADD CONSTRAINT notifications_worker_id_fkey 
            FOREIGN KEY (worker_id) 
            REFERENCES public.workers(worker_id) 
            ON DELETE CASCADE;
        END IF;
    END IF;
END $$;
