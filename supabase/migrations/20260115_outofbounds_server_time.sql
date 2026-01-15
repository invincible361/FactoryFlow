-- 1. Update production_outofbounds to use server-side defaults
ALTER TABLE public.production_outofbounds ALTER COLUMN exit_time SET DEFAULT now();

-- 2. Create function to handle worker return (updates entry_time)
CREATE OR REPLACE FUNCTION public.handle_worker_return(
    event_id UUID,
    entry_lat DOUBLE PRECISION,
    entry_lng DOUBLE PRECISION
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.production_outofbounds
    SET 
        entry_time = now(),
        entry_latitude = entry_lat,
        entry_longitude = entry_lng,
        duration_minutes = EXTRACT(EPOCH FROM (now() - exit_time))/60
    WHERE id = event_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Grant access to handle_worker_return
GRANT EXECUTE ON FUNCTION public.handle_worker_return TO anon, authenticated;
