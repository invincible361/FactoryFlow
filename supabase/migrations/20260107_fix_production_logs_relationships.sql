-- Add composite foreign key relationships to enable Supabase joins for production_logs
-- This fixes the PGRST200 error: no relationship between production_logs and worker_id

DO $$
BEGIN
    -- 1. Ensure production_logs -> workers relationship
    -- Using composite key (worker_id, organization_code) for multi-tenancy
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_worker_id_fkey') THEN
        ALTER TABLE public.production_logs 
        ADD CONSTRAINT production_logs_worker_id_fkey 
        FOREIGN KEY (worker_id, organization_code) 
        REFERENCES public.workers(worker_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

    -- 2. Ensure production_logs -> items relationship (double check)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_item_id_fkey') THEN
        ALTER TABLE public.production_logs 
        ADD CONSTRAINT production_logs_item_id_fkey 
        FOREIGN KEY (item_id, organization_code) 
        REFERENCES public.items(item_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

    -- 3. Ensure production_logs -> machines relationship (double check)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_machine_id_fkey') THEN
        ALTER TABLE public.production_logs 
        ADD CONSTRAINT production_logs_machine_id_fkey 
        FOREIGN KEY (machine_id, organization_code) 
        REFERENCES public.machines(machine_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

END $$;
