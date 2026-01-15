-- Enable RLS and allow all operations for anon on gate_events and attendance

-- gate_events
ALTER TABLE public.gate_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon" ON public.gate_events;
CREATE POLICY "Allow all for anon" ON public.gate_events
FOR ALL
USING (true)
WITH CHECK (true);

CREATE OR REPLACE VIEW public.gate_activity_daily_latest AS
WITH ge AS (
  SELECT
    g.worker_id,
    g.organization_code,
    w.name AS worker_name,
    g.event_type,
    (g."timestamp" AT TIME ZONE 'Asia/Kolkata') AS event_time_ist,
    (g."timestamp" AT TIME ZONE 'Asia/Kolkata')::date AS date_ist,
    g.latitude,
    g.longitude
  FROM public.gate_events g
  LEFT JOIN public.workers w ON w.worker_id = g.worker_id
)
SELECT DISTINCT ON (worker_id, organization_code, date_ist)
  worker_id,
  worker_name,
  organization_code,
  date_ist,
  event_type,
  CASE WHEN event_type = 'entry' THEN true ELSE false END AS is_inside,
  event_time_ist,
  latitude,
  longitude
FROM ge
ORDER BY worker_id, organization_code, date_ist, event_time_ist DESC;

CREATE OR REPLACE VIEW public.gate_activity_daily AS
SELECT
  g.worker_id,
  w.name AS worker_name,
  g.organization_code,
  (g."timestamp" AT TIME ZONE 'Asia/Kolkata')::date AS date_ist,
  (g."timestamp" AT TIME ZONE 'Asia/Kolkata') AS event_time_ist,
  g.event_type,
  g.latitude,
  g.longitude
FROM public.gate_events g
LEFT JOIN public.workers w ON w.worker_id = g.worker_id
ORDER BY date_ist DESC, event_time_ist DESC;

CREATE INDEX IF NOT EXISTS idx_gate_events_date_utc ON public.gate_events (("timestamp"::date));
CREATE INDEX IF NOT EXISTS idx_gate_events_org ON public.gate_events (organization_code);

-- attendance
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for anon" ON public.attendance;
CREATE POLICY "Allow all for anon" ON public.attendance
FOR ALL
USING (true)
WITH CHECK (true);
