-- Migration: Backend as ONLY Time Source
-- 1. Ensure all timestamp columns are TIMESTAMPTZ
ALTER TABLE public.production_logs 
  ALTER COLUMN start_time TYPE TIMESTAMPTZ,
  ALTER COLUMN end_time TYPE TIMESTAMPTZ,
  ALTER COLUMN timestamp TYPE TIMESTAMPTZ,
  ALTER COLUMN created_at TYPE TIMESTAMPTZ;

ALTER TABLE public.attendance 
  ALTER COLUMN check_in TYPE TIMESTAMPTZ,
  ALTER COLUMN check_out TYPE TIMESTAMPTZ,
  ALTER COLUMN created_at TYPE TIMESTAMPTZ;

ALTER TABLE public.worker_boundary_events 
  ALTER COLUMN created_at TYPE TIMESTAMPTZ;

-- 2. Add duration calculation to production_logs
ALTER TABLE public.production_logs 
ADD COLUMN IF NOT EXISTS duration_minutes INTEGER GENERATED ALWAYS AS (
    CASE 
        WHEN start_time IS NOT NULL AND end_time IS NOT NULL 
        THEN EXTRACT(EPOCH FROM (end_time - start_time)) / 60
        ELSE 0
    END
) STORED;

-- 3. Update/Create RPCs to use NOW() and handle all time logic

-- Attendance Check-In
CREATE OR REPLACE FUNCTION attendance_check_in(
    p_worker_id TEXT,
    p_org_code TEXT,
    p_date DATE,
    p_shift_name TEXT,
    p_shift_start TEXT,
    p_shift_end TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO public.attendance (
        worker_id, organization_code, date, shift_name, 
        shift_start_time, shift_end_time, check_in, status
    ) VALUES (
        p_worker_id, p_org_code, p_date, p_shift_name, 
        p_shift_start, p_shift_end, NOW(), 'On Time'
    ) ON CONFLICT (worker_id, date, organization_code) 
    DO UPDATE SET 
        check_in = COALESCE(public.attendance.check_in, NOW()),
        status = 'On Time';
END;
$$ LANGUAGE plpgsql;

-- Attendance Check-Out
CREATE OR REPLACE FUNCTION attendance_check_out(
    p_worker_id TEXT,
    p_org_code TEXT,
    p_date DATE
) RETURNS VOID AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_shift_end_time TEXT;
    v_shift_start_time TEXT;
    v_shift_end_dt TIMESTAMPTZ;
    v_diff_minutes INTEGER;
    v_status TEXT;
BEGIN
    -- Get shift info
    SELECT shift_end_time, shift_start_time INTO v_shift_end_time, v_shift_start_time
    FROM public.attendance
    WHERE worker_id = p_worker_id AND date = p_date AND organization_code = p_org_code;

    -- Calculate status based on backend NOW()
    -- (This logic is simplified for the RPC, full logic can be added as needed)
    
    UPDATE public.attendance SET 
        check_out = v_now,
        updated_at = v_now
    WHERE worker_id = p_worker_id AND date = p_date AND organization_code = p_org_code
    AND check_out IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Production Start
DROP FUNCTION IF EXISTS log_production_start(TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT);
CREATE OR REPLACE FUNCTION log_production_start(
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

-- Production End
DROP FUNCTION IF EXISTS log_production_end(TEXT, INTEGER, TEXT, INTEGER, DOUBLE PRECISION, DOUBLE PRECISION);
CREATE OR REPLACE FUNCTION log_production_end(
    p_id UUID,
    p_quantity INTEGER,
    p_remarks TEXT,
    p_perf_diff INTEGER,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lng DOUBLE PRECISION DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE public.production_logs SET 
        end_time = NOW(),
        quantity = p_quantity,
        remarks = p_remarks,
        performance_diff = p_perf_diff,
        latitude = COALESCE(p_lat, latitude),
        longitude = COALESCE(p_lng, longitude),
        is_active = false
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;
