-- FIX COMPOSITE UNIQUE CONSTRAINTS FOR MULTI-TENANCY
-- Run this script in your Supabase SQL Editor

-- NOTE: We use CASCADE to drop dependent foreign keys, then recreate them
-- as simple data columns since foreign keys to non-primary keys are complex 
-- in multi-tenant environments without composite foreign keys.

-- 1. WORKERS TABLE
-- Drop constraints and dependent objects
ALTER TABLE public.workers DROP CONSTRAINT IF EXISTS workers_worker_id_key CASCADE;
ALTER TABLE public.workers DROP CONSTRAINT IF EXISTS workers_username_key CASCADE;

-- Add composite unique constraints
ALTER TABLE public.workers ADD CONSTRAINT workers_worker_id_org_unique UNIQUE (worker_id, organization_code);
ALTER TABLE public.workers ADD CONSTRAINT workers_username_org_unique UNIQUE (username, organization_code);


-- 2. MACHINES TABLE
ALTER TABLE public.machines DROP CONSTRAINT IF EXISTS machines_machine_id_key CASCADE;
ALTER TABLE public.machines ADD CONSTRAINT machines_machine_id_org_unique UNIQUE (machine_id, organization_code);


-- 3. ITEMS TABLE
ALTER TABLE public.items DROP CONSTRAINT IF EXISTS items_item_id_key CASCADE;
ALTER TABLE public.items ADD CONSTRAINT items_item_id_org_unique UNIQUE (item_id, organization_code);


-- 4. SHIFTS TABLE
ALTER TABLE public.shifts DROP CONSTRAINT IF EXISTS shifts_name_key CASCADE;
ALTER TABLE public.shifts ADD CONSTRAINT shifts_name_org_unique UNIQUE (name, organization_code);
