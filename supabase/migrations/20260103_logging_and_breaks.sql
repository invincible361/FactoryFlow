-- Supervisor Logging and Worker Breaks
-- 1. Worker Breaks
create table if not exists public.worker_breaks (
    id uuid primary key default gen_random_uuid(),
    worker_id text not null,
    organization_code text not null references public.organizations(organization_code) on delete cascade,
    start_time timestamptz not null default now(),
    end_time timestamptz,
    break_type text default 'lunch',
    duration_minutes integer,
    created_at timestamptz default now()
);

alter table public.worker_breaks enable row level security;
drop policy if exists "Workers can insert their own breaks" on public.worker_breaks;
create policy "Workers can insert their own breaks" on public.worker_breaks for insert with check (true);
drop policy if exists "Workers can view their own breaks" on public.worker_breaks;
create policy "Workers can view their own breaks" on public.worker_breaks for select using (true);
drop policy if exists "Workers can update their own breaks" on public.worker_breaks;
create policy "Workers can update their own breaks" on public.worker_breaks for update using (true);

-- 2. Supervisor Logging
alter table public.production_logs add column if not exists created_by_supervisor boolean default false;
alter table public.production_logs add column if not exists supervisor_id text;
