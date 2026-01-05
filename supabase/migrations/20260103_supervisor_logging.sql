-- Add supervisor logging tracking to production_logs
alter table public.production_logs add column if not exists created_by_supervisor boolean default false;
alter table public.production_logs add column if not exists supervisor_id text;
