-- Migration: Analytics & Reports Views
-- 1. Daily Worker Summary
CREATE OR REPLACE VIEW public.daily_worker_summary AS
WITH daily_stats AS (
    SELECT 
        a.worker_id,
        a.organization_code,
        a.date,
        a.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata' as first_entry,
        a.check_out AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata' as last_exit,
        -- Total Outside Time from production_outofbounds
        COALESCE((
            SELECT SUM(EXTRACT(EPOCH FROM (COALESCE(entry_time, NOW()) - exit_time)) / 60)
            FROM public.production_outofbounds oob
            WHERE oob.worker_id = a.worker_id 
              AND oob.organization_code = a.organization_code 
              AND oob.date = a.date
        ), 0) as total_outside_minutes,
        -- Total Production Time from production_logs
        COALESCE((
            SELECT SUM(duration_minutes)
            FROM public.production_logs pl
            WHERE pl.worker_id = a.worker_id 
              AND pl.organization_code = a.organization_code 
              AND (pl.start_time AT TIME ZONE 'UTC')::DATE = a.date
        ), 0) as total_production_minutes
    FROM public.attendance a
)
SELECT 
    s.*,
    w.name as worker_name,
    -- Total Inside Time = (Last Exit - First Entry) - Total Outside
    CASE 
        WHEN s.last_exit IS NOT NULL THEN
            (EXTRACT(EPOCH FROM (s.last_exit - s.first_entry)) / 60) - s.total_outside_minutes
        ELSE
            (EXTRACT(EPOCH FROM (NOW() - s.first_entry)) / 60) - s.total_outside_minutes
    END as total_inside_minutes
FROM daily_stats s
JOIN public.workers w ON s.worker_id = w.worker_id;

-- 2. Daily Machine Utilization
CREATE OR REPLACE VIEW public.machine_utilization_summary AS
SELECT 
    m.machine_id,
    m.name as machine_name,
    m.organization_code,
    (pl.start_time AT TIME ZONE 'UTC')::DATE as date,
    SUM(pl.duration_minutes) as running_minutes,
    -- Assuming 8-hour shift (480 mins) for idle calculation if no explicit shift data
    480 - SUM(pl.duration_minutes) as idle_minutes,
    COUNT(DISTINCT pl.worker_id) as operator_count,
    COUNT(pl.id) as task_count
FROM public.machines m
LEFT JOIN public.production_logs pl ON m.machine_id = pl.machine_id 
  AND m.organization_code = pl.organization_code
GROUP BY m.machine_id, m.name, m.organization_code, (pl.start_time AT TIME ZONE 'UTC')::DATE;

-- 3. Production Efficiency
CREATE OR REPLACE VIEW public.production_efficiency_summary AS
SELECT 
    pl.organization_code,
    (pl.start_time AT TIME ZONE 'UTC')::DATE as date,
    pl.item_id,
    i.name as item_name,
    pl.operation,
    SUM(pl.quantity) as actual_output,
    -- Output per hour calculation
    CASE 
        WHEN SUM(pl.duration_minutes) > 0 
        THEN ROUND((SUM(pl.quantity)::numeric / (SUM(pl.duration_minutes)::numeric / 60)), 2)
        ELSE 0 
    END as output_per_hour,
    SUM(pl.performance_diff) as total_correction_delta
FROM public.production_logs pl
JOIN public.items i ON pl.item_id = i.item_id AND pl.organization_code = i.organization_code
GROUP BY pl.organization_code, (pl.start_time AT TIME ZONE 'UTC')::DATE, pl.item_id, i.name, pl.operation;

-- 4. Exception Reporting
CREATE OR REPLACE VIEW public.exception_report AS
SELECT 
    'Late Arrival' as exception_type,
    a.worker_id,
    w.name as worker_name,
    a.organization_code,
    a.date,
    'Arrived at ' || TO_CHAR(a.check_in AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM') as details
FROM public.attendance a
JOIN public.workers w ON a.worker_id = w.worker_id
WHERE a.status = 'Late' -- Assuming status is updated to Late by system

UNION ALL

SELECT 
    'Long Outside Duration' as exception_type,
    oob.worker_id,
    w.name as worker_name,
    oob.organization_code,
    oob.date,
    'Duration: ' || oob.duration_minutes || ' mins' as details
FROM public.production_outofbounds oob
JOIN public.workers w ON oob.worker_id = w.worker_id
WHERE (NULLIF(REGEXP_REPLACE(oob.duration_minutes, '\D', '', 'g'), '')::integer) > 30 -- More than 30 mins outside

UNION ALL

SELECT 
    'Abnormal Production Spike' as exception_type,
    pl.worker_id,
    w.name as worker_name,
    pl.organization_code,
    (pl.start_time AT TIME ZONE 'UTC')::DATE as date,
    'Quantity: ' || pl.quantity || ' in ' || pl.duration_minutes || ' mins' as details
FROM public.production_logs pl
JOIN public.workers w ON pl.worker_id = w.worker_id
WHERE pl.duration_minutes > 0 AND (pl.quantity::numeric / (pl.duration_minutes::numeric / 60)) > 500; -- Arbitrary spike threshold
