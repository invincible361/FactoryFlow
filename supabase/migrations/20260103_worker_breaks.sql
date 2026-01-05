-- Create worker_breaks table to track lunch and other breaks
create table if not exists public.worker_breaks (
    id uuid primary key default gen_random_uuid(),
    worker_id text not null,
    organization_code text not null references public.organizations(organization_code) on delete cascade,
    start_time timestamptz not null default now(),
    end_time timestamptz,
    break_type text default 'lunch', -- 'lunch', 'tea', 'other'
    duration_minutes integer,
    created_at timestamptz default now()
);

-- Enable RLS
alter table public.worker_breaks enable row level security;

-- Policies
create policy "Workers can insert their own breaks"
    on public.worker_breaks for insert
    with check (true);

create policy "Workers can view their own breaks"
    on public.worker_breaks for select
    using (true);

create policy "Workers can update their own breaks"
    on public.worker_breaks for update
    using (true);

-- Index for performance
create index if not exists worker_breaks_worker_id_idx on public.worker_breaks(worker_id);
create index if not exists worker_breaks_org_code_idx on public.worker_breaks(organization_code);
