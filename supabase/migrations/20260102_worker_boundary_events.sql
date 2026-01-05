-- Create worker_boundary_events table for real-time location tracking
create table if not exists public.worker_boundary_events (
    id uuid default gen_random_uuid() primary key,
    worker_id text not null,
    organization_code text not null references public.organizations(organization_code) on delete cascade,
    type text not null, -- 'entry', 'exit', or 'periodic'
    latitude double precision,
    longitude double precision,
    created_at timestamptz default now()
);

-- Index for faster status lookups
create index if not exists worker_boundary_events_worker_id_idx on public.worker_boundary_events(worker_id, created_at desc);

-- RLS Policies
alter table public.worker_boundary_events enable row level security;

create policy "Enable all for authenticated users" on public.worker_boundary_events
    for all using (true) with check (true);
