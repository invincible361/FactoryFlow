CREATE TABLE IF NOT EXISTS public.gate_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    worker_id TEXT NOT NULL,
    organization_code TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('entry','exit')),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    "timestamp" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'gate_events_worker_id_fkey'
    ) THEN
        ALTER TABLE public.gate_events
        ADD CONSTRAINT gate_events_worker_id_fkey
        FOREIGN KEY (worker_id)
        REFERENCES public.workers(worker_id)
        ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS gate_events_worker_idx ON public.gate_events(worker_id);
CREATE INDEX IF NOT EXISTS gate_events_org_idx ON public.gate_events(organization_code);
CREATE INDEX IF NOT EXISTS gate_events_ts_idx ON public.gate_events("timestamp" DESC);

CREATE OR REPLACE FUNCTION public.mark_attendance()
RETURNS TRIGGER AS $$
DECLARE
    v_date DATE := NEW."timestamp"::date;
BEGIN
    IF NEW.event_type = 'entry' THEN
        INSERT INTO public.attendance (worker_id, organization_code, date, check_in)
        VALUES (NEW.worker_id, NEW.organization_code, v_date, NEW."timestamp")
        ON CONFLICT (worker_id, date, organization_code)
        DO UPDATE SET check_in = COALESCE(attendance.check_in, EXCLUDED.check_in);
    ELSIF NEW.event_type = 'exit' THEN
        INSERT INTO public.attendance (worker_id, organization_code, date, check_out)
        VALUES (NEW.worker_id, NEW.organization_code, v_date, NEW."timestamp")
        ON CONFLICT (worker_id, date, organization_code)
        DO UPDATE SET check_out = EXCLUDED.check_out;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS gate_event_trigger ON public.gate_events;
CREATE TRIGGER gate_event_trigger
AFTER INSERT ON public.gate_events
FOR EACH ROW EXECUTE FUNCTION public.mark_attendance();

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'gate_events') THEN
        RAISE NOTICE 'gate_events not created';
    END IF;
    EXECUTE 'ALTER TABLE public.gate_events ENABLE ROW LEVEL SECURITY';
    BEGIN
        EXECUTE 'DROP POLICY IF EXISTS "Allow all for anon" ON public.gate_events';
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    EXECUTE 'CREATE POLICY "Allow all for anon" ON public.gate_events FOR ALL USING (true) WITH CHECK (true)';
END $$;

