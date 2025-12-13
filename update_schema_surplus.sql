-- Add performance_diff column to production_logs
-- This will store the difference between produced quantity and target
-- Positive value = Surplus (Overachieved)
-- Negative value = Deficit (Underachieved)
-- Zero = Exact Target

ALTER TABLE production_logs 
ADD COLUMN IF NOT EXISTS performance_diff INTEGER DEFAULT 0;
