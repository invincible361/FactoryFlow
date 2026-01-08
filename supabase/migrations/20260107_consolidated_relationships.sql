-- Consolidated 20260107 Migration: Boundary Flags and Composite Relationships
-- 1. Add is_inside column to worker_boundary_events
ALTER TABLE public.worker_boundary_events ADD COLUMN IF NOT EXISTS is_inside BOOLEAN;
UPDATE public.worker_boundary_events SET is_inside = true WHERE type = 'entry';
UPDATE public.worker_boundary_events SET is_inside = false WHERE type = 'exit';
UPDATE public.worker_boundary_events SET is_inside = true WHERE type = 'periodic' AND remarks = 'STILL_INSIDE';
UPDATE public.worker_boundary_events SET is_inside = false WHERE type = 'periodic' AND remarks = 'STILL_OUTSIDE';

-- 2. Composite Foreign Key Relationships (Multi-tenant joins)
DO $$
BEGIN
    -- production_logs -> workers
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_worker_id_fkey') THEN
        ALTER TABLE public.production_logs ADD CONSTRAINT production_logs_worker_id_fkey FOREIGN KEY (worker_id, organization_code) REFERENCES public.workers(worker_id, organization_code) ON DELETE CASCADE;
    END IF;

    -- production_logs -> items
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_item_id_fkey') THEN
        ALTER TABLE public.production_logs ADD CONSTRAINT production_logs_item_id_fkey FOREIGN KEY (item_id, organization_code) REFERENCES public.items(item_id, organization_code) ON DELETE CASCADE;
    END IF;

    -- production_logs -> machines
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'production_logs_machine_id_fkey') THEN
        ALTER TABLE public.production_logs ADD CONSTRAINT production_logs_machine_id_fkey FOREIGN KEY (machine_id, organization_code) REFERENCES public.machines(machine_id, organization_code) ON DELETE CASCADE;
    END IF;

    -- work_assignments -> items
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_assignments_item_id_fkey') THEN
        ALTER TABLE public.work_assignments ADD CONSTRAINT work_assignments_item_id_fkey FOREIGN KEY (item_id, organization_code) REFERENCES public.items(item_id, organization_code) ON DELETE CASCADE;
    END IF;

    -- work_assignments -> machines
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'work_assignments_machine_id_fkey') THEN
        ALTER TABLE public.work_assignments ADD CONSTRAINT work_assignments_machine_id_fkey FOREIGN KEY (machine_id, organization_code) REFERENCES public.machines(machine_id, organization_code) ON DELETE CASCADE;
    END IF;
END $$;
