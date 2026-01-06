-- Add composite foreign key relationships to enable Supabase joins for production_logs and work_assignments
-- These must use (id, organization_code) to match the unique constraints in the multi-tenant schema.

DO $$
BEGIN
    -- 1. Ensure production_logs -> items relationship
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_item_id_fkey') THEN
        ALTER TABLE public.production_logs 
        ADD CONSTRAINT production_logs_item_id_fkey 
        FOREIGN KEY (item_id, organization_code) 
        REFERENCES public.items(item_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

    -- 2. Ensure production_logs -> machines relationship
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_machine_id_fkey') THEN
        ALTER TABLE public.production_logs 
        ADD CONSTRAINT production_logs_machine_id_fkey 
        FOREIGN KEY (machine_id, organization_code) 
        REFERENCES public.machines(machine_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

    -- 3. Ensure work_assignments -> items relationship
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_assignments_item_id_fkey') THEN
        ALTER TABLE public.work_assignments 
        ADD CONSTRAINT work_assignments_item_id_fkey 
        FOREIGN KEY (item_id, organization_code) 
        REFERENCES public.items(item_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

    -- 4. Ensure work_assignments -> machines relationship
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_assignments_machine_id_fkey') THEN
        ALTER TABLE public.work_assignments 
        ADD CONSTRAINT work_assignments_machine_id_fkey 
        FOREIGN KEY (machine_id, organization_code) 
        REFERENCES public.machines(machine_id, organization_code) 
        ON DELETE CASCADE;
    END IF;

END $$;
