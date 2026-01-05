-- Create production_outofbounds table for historical tracking of worker boundary events
CREATE TABLE IF NOT EXISTS public.production_outofbounds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    worker_id UUID NULL, -- Explicitly allow NULL for non-worker users like Admin
    worker_name TEXT,
    organization_code TEXT,
    date DATE DEFAULT CURRENT_DATE,
    exit_time TIMESTAMP WITH TIME ZONE,
    entry_time TIMESTAMP WITH TIME ZONE,
    exit_latitude DOUBLE PRECISION,
    exit_longitude DOUBLE PRECISION,
    entry_latitude DOUBLE PRECISION,
    entry_longitude DOUBLE PRECISION,
    duration_minutes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ensure worker_id is nullable if the table already exists
ALTER TABLE public.production_outofbounds ALTER COLUMN worker_id DROP NOT NULL;

-- Enable RLS
ALTER TABLE public.production_outofbounds ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own organization's data
DROP POLICY IF EXISTS "Users can read their own organization's outofbounds" ON public.production_outofbounds;
CREATE POLICY "Users can read their own organization's outofbounds" ON public.production_outofbounds
    FOR SELECT USING (auth.jwt() ->> 'organization_code' = organization_code);

-- Policy: Workers can insert their own data
DROP POLICY IF EXISTS "Workers can insert their own outofbounds" ON public.production_outofbounds;
CREATE POLICY "Workers can insert their own outofbounds" ON public.production_outofbounds
    FOR INSERT WITH CHECK (true);

-- Policy: Workers can update their own data (for entry time)
DROP POLICY IF EXISTS "Workers can update their own outofbounds" ON public.production_outofbounds;
CREATE POLICY "Workers can update their own outofbounds" ON public.production_outofbounds
    FOR UPDATE USING (true);
