-- Migration to add notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_code TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT, -- 'out_of_bounds', 'return', etc.
  worker_id TEXT,
  worker_name TEXT,
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_notifications_org ON notifications(organization_code);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
