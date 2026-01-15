-- Enable RLS for work_assignments
ALTER TABLE public.work_assignments ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if any
DROP POLICY IF EXISTS "Enable all for authenticated users" ON public.work_assignments;

-- Create policy to allow all operations for authenticated users
CREATE POLICY "Enable all for authenticated users" ON public.work_assignments
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);
