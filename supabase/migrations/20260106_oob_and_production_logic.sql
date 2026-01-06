-- ADVANCED TIME HANDLING AND OOB LOGIC
-- This migration adds functions and triggers to ensure "Backend as Truth"
-- and correct duration calculations for Out-of-Bounds events.

-- 1. Function to calculate duration between two timestamps in minutes
CREATE OR REPLACE FUNCTION calculate_duration_minutes(start_t timestamptz, end_t timestamptz)
RETURNS TEXT AS $$
DECLARE
    diff interval;
    total_minutes integer;
BEGIN
    IF start_t IS NULL OR end_t IS NULL THEN
        RETURN NULL;
    END IF;
    diff := end_t - start_t;
    total_minutes := EXTRACT(EPOCH FROM diff) / 60;
    RETURN total_minutes || ' mins';
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger to automatically calculate duration for production_outofbounds
CREATE OR REPLACE FUNCTION trg_calculate_oob_duration()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.entry_time IS NOT NULL AND OLD.entry_time IS NULL THEN
        -- entry_time was just set
        NEW.duration_minutes := calculate_duration_minutes(NEW.exit_time, NEW.entry_time);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS calculate_oob_duration_trg ON public.production_outofbounds;
CREATE TRIGGER calculate_oob_duration_trg
    BEFORE UPDATE ON public.production_outofbounds
    FOR EACH ROW
    EXECUTE FUNCTION trg_calculate_oob_duration();

-- 3. Function to handle worker return (OOB Entry)
-- This allows the app to just call this function instead of manual update
CREATE OR REPLACE FUNCTION handle_worker_return(event_id uuid, entry_lat double precision, entry_lng double precision)
RETURNS void AS $$
BEGIN
    UPDATE public.production_outofbounds
    SET 
        entry_time = NOW(),
        entry_latitude = entry_lat,
        entry_longitude = entry_lng
    WHERE id = event_id;
END;
$$ LANGUAGE plpgsql;

-- 4. Ensure production_logs also uses NOW() for start_time if requested
-- We'll add a function to log production start
CREATE OR REPLACE FUNCTION log_production_start(
    p_id text,
    p_worker_id text,
    p_machine_id text,
    p_item_id text,
    p_operation text,
    p_lat double precision,
    p_lng double precision,
    p_org_code text,
    p_shift_name text
) RETURNS void AS $$
BEGIN
    INSERT INTO public.production_logs (
        id, worker_id, machine_id, item_id, operation, 
        start_time, latitude, longitude, organization_code, shift_name,
        quantity, timestamp -- placeholders
    ) VALUES (
        p_id, p_worker_id, p_machine_id, p_item_id, p_operation,
        NOW(), p_lat, p_lng, p_org_code, p_shift_name,
        0, NOW()
    );
END;
$$ LANGUAGE plpgsql;

-- 5. Function to log production end
CREATE OR REPLACE FUNCTION log_production_end(
    p_id text,
    p_quantity integer,
    p_remarks text,
    p_performance_diff integer
) RETURNS void AS $$
BEGIN
    UPDATE public.production_logs
    SET 
        end_time = NOW(),
        quantity = p_quantity,
        remarks = p_remarks,
        performance_diff = p_performance_diff
    WHERE id::text = p_id::text;
END;
$$ LANGUAGE plpgsql;

-- 6. Function to handle attendance check-in
CREATE OR REPLACE FUNCTION attendance_check_in(
    p_worker_id text,
    p_org_code text,
    p_date date,
    p_shift_name text,
    p_shift_start text,
    p_shift_end text
) RETURNS void AS $$
BEGIN
    INSERT INTO public.attendance (
        worker_id, organization_code, date, 
        shift_name, shift_start_time, shift_end_time,
        check_in, status
    ) VALUES (
        p_worker_id, p_org_code, p_date,
        p_shift_name, p_shift_start, p_shift_end,
        NOW(), 'On Time'
    ) ON CONFLICT (worker_id, date, organization_code) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- 7. Function to handle attendance check-out
CREATE OR REPLACE FUNCTION attendance_check_out(
    p_worker_id text,
    p_org_code text,
    p_date date
) RETURNS void AS $$
BEGIN
    UPDATE public.attendance
    SET check_out = NOW()
    WHERE worker_id = p_worker_id 
      AND date = p_date 
      AND organization_code = p_org_code
      AND check_out IS NULL;
END;
$$ LANGUAGE plpgsql;
