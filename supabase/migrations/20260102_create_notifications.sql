-- Create Notifications Table for tracking alerts and messages
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_code TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT, -- 'return', 'out_of_bounds', 'production_alert', etc.
    worker_id TEXT,
    worker_name TEXT,
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Allow all for anon (for MVP simplicity)
DROP POLICY IF EXISTS "Allow all for anon" ON public.notifications;
CREATE POLICY "Allow all for anon" ON public.notifications FOR ALL USING (true);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_notifications_org_code ON public.notifications(organization_code);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON public.notifications(read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);
