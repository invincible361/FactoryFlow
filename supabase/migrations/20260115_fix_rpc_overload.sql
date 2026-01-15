-- Migration to fix RPC overloading by explicitly dropping old TEXT-based versions
-- and ensuring only UUID-based versions remain.

-- 1. Drop log_production_start (all possible overloaded versions)
DROP FUNCTION IF EXISTS public.log_production_start(TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.log_production_start(UUID, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT);

-- Recreate the correct one
CREATE OR REPLACE FUNCTION public.log_production_start(
    p_id UUID,
    p_worker_id TEXT,
    p_machine_id TEXT,
    p_item_id TEXT,
    p_operation TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_org_code TEXT,
    p_shift_name TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO public.production_logs (
        id, worker_id, machine_id, item_id, operation, 
        latitude, longitude, organization_code, shift_name,
        start_time, timestamp, is_active, quantity
    ) VALUES (
        p_id, p_worker_id, p_machine_id, p_item_id, p_operation,
        p_lat, p_lng, p_org_code, p_shift_name,
        NOW(), NOW(), true, 0
    );
END;
$$ LANGUAGE plpgsql;

-- 2. Drop log_production_end (all possible overloaded versions)
DROP FUNCTION IF EXISTS public.log_production_end(TEXT, INTEGER, TEXT, INTEGER, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.log_production_end(UUID, INTEGER, TEXT, INTEGER, DOUBLE PRECISION, DOUBLE PRECISION);

-- Recreate the correct one
CREATE OR REPLACE FUNCTION public.log_production_end(
    p_id UUID,
    p_quantity INTEGER,
    p_remarks TEXT,
    p_performance_diff INTEGER,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lng DOUBLE PRECISION DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE public.production_logs SET 
        end_time = NOW(),
        quantity = p_quantity,
        remarks = p_remarks,
        performance_diff = p_performance_diff,
        latitude = COALESCE(p_lat, latitude),
        longitude = COALESCE(p_lng, longitude),
        is_active = false
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;
