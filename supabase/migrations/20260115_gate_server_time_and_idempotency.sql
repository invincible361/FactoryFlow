-- 1. Add last_boundary_state to workers
ALTER TABLE public.workers ADD COLUMN IF NOT EXISTS last_boundary_state TEXT DEFAULT 'outside';

-- 2. Update mark_attendance trigger function with idempotency
CREATE OR REPLACE FUNCTION public.mark_attendance()
RETURNS TRIGGER AS $$
DECLARE
    v_date DATE := (NEW."timestamp" AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF NEW.event_type = 'entry' THEN
        -- Idempotent check for entry: only insert if no entry exists for this worker on this day (IST)
        INSERT INTO public.attendance (worker_id, organization_code, date, check_in)
        SELECT NEW.worker_id, NEW.organization_code, v_date, NEW."timestamp"
        WHERE NOT EXISTS (
            SELECT 1 FROM public.attendance 
            WHERE worker_id = NEW.worker_id 
            AND organization_code = NEW.organization_code
            AND date = v_date
            AND check_in IS NOT NULL
        )
        ON CONFLICT (worker_id, date, organization_code) 
        DO UPDATE SET check_in = COALESCE(attendance.check_in, EXCLUDED.check_in);

    ELSIF NEW.event_type = 'exit' THEN
        -- For exit, we update the existing record
        INSERT INTO public.attendance (worker_id, organization_code, date, check_out)
        VALUES (NEW.worker_id, NEW.organization_code, v_date, NEW."timestamp")
        ON CONFLICT (worker_id, date, organization_code)
        DO UPDATE SET check_out = EXCLUDED.check_out;
    END IF;

    -- Update last_boundary_state in workers table
    UPDATE public.workers 
    SET last_boundary_state = CASE WHEN NEW.event_type = 'entry' THEN 'inside' ELSE 'outside' END
    WHERE worker_id = NEW.worker_id AND organization_code = NEW.organization_code;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Ensure the trigger is active (it was already created in 20260114_gate_events_and_attendance_trigger.sql)
-- But we'll drop and recreate it just to be sure it points to the new function
DROP TRIGGER IF EXISTS gate_event_trigger ON public.gate_events;
CREATE TRIGGER gate_event_trigger
AFTER INSERT ON public.gate_events
FOR EACH ROW EXECUTE FUNCTION public.mark_attendance();
