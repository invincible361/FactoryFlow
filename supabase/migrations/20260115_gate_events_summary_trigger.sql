-- Migration to update daily_geofence_summaries from gate_events
CREATE OR REPLACE FUNCTION public.update_geofence_summary_from_gate_events()
RETURNS TRIGGER AS $$
DECLARE
    event_date DATE;
BEGIN
    IF NEW.event_type NOT IN ('entry', 'exit') THEN RETURN NEW; END IF;
    event_date := (NEW.timestamp AT TIME ZONE 'UTC')::DATE;
    
    INSERT INTO public.daily_geofence_summaries (worker_id, organization_code, date, first_entry_time, entry_count, exit_count, last_event_time)
    VALUES (
        NEW.worker_id, 
        NEW.organization_code, 
        event_date, 
        CASE WHEN NEW.event_type = 'entry' THEN NEW.timestamp ELSE NULL END, 
        CASE WHEN NEW.event_type = 'entry' THEN 1 ELSE 0 END, 
        CASE WHEN NEW.event_type = 'exit' THEN 1 ELSE 0 END, 
        NEW.timestamp
    )
    ON CONFLICT (worker_id, date, organization_code) DO UPDATE SET
        first_entry_time = CASE 
            WHEN daily_geofence_summaries.first_entry_time IS NULL AND EXCLUDED.first_entry_time IS NOT NULL THEN EXCLUDED.first_entry_time
            WHEN daily_geofence_summaries.first_entry_time IS NOT NULL AND EXCLUDED.first_entry_time IS NOT NULL AND EXCLUDED.first_entry_time < daily_geofence_summaries.first_entry_time THEN EXCLUDED.first_entry_time
            ELSE daily_geofence_summaries.first_entry_time
        END,
        entry_count = daily_geofence_summaries.entry_count + (CASE WHEN NEW.event_type = 'entry' THEN 1 ELSE 0 END),
        exit_count = daily_geofence_summaries.exit_count + (CASE WHEN NEW.event_type = 'exit' THEN 1 ELSE 0 END),
        last_event_time = GREATEST(daily_geofence_summaries.last_event_time, NEW.timestamp);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS gate_events_to_summary_trigger ON public.gate_events;
CREATE TRIGGER gate_events_to_summary_trigger
AFTER INSERT ON public.gate_events
FOR EACH ROW EXECUTE FUNCTION public.update_geofence_summary_from_gate_events();
